import Foundation

/// 评分调度器（actor）。
///
/// 相比原来的 `struct`，改为 `actor` 的收益：
/// 1. 暂停状态（`isPauseRequested`）内聚在调度器内部，不再泄漏到 `AppState`；
/// 2. 编译器级的隔离保证，串行化对内部可变状态的访问。
///
/// 性能策略（对应「批量评分」优化）：
/// - 每次从数据库领取 `batchSize`（默认 200）个待评任务为一批；
/// - 批内用 `TaskGroup` 以 `scoringConcurrency` 的并发度同时跑 Vision，充分利用 CPU/GPU/ANE；
/// - 一批评分结果在**单个数据库事务**里批量落库；
/// - 每批结束后只回调 `didScoreBatch` **一次**，由上层做一次界面刷新（无逐张刷新闪烁）。
actor AnalysisScheduler {
    private let repository: AnalysisRepository
    private let photoLibraryAdapter: PhotoLibraryAdapter
    private let provider: AppleVisionAestheticsProvider

    /// 单批领取与界面刷新的粒度。
    let batchSize: Int
    /// 批内并发评分的最大并行度。
    let scoringConcurrency: Int

    private var isPauseRequested = false

    init(
        repository: AnalysisRepository,
        photoLibraryAdapter: PhotoLibraryAdapter,
        provider: AppleVisionAestheticsProvider,
        batchSize: Int = 200,
        scoringConcurrency: Int = AnalysisScheduler.defaultConcurrency
    ) {
        self.repository = repository
        self.photoLibraryAdapter = photoLibraryAdapter
        self.provider = provider
        self.batchSize = batchSize
        self.scoringConcurrency = scoringConcurrency
    }

    static var defaultConcurrency: Int {
        max(2, min(ProcessInfo.processInfo.activeProcessorCount, 8))
    }

    func pause() { isPauseRequested = true }
    func resume() { isPauseRequested = false }

    // MARK: - 入口

    func scoreVisiblePhotos(
        _ photoIDs: [String],
        runStarted: (@MainActor @Sendable (String) -> Void)? = nil,
        progressHandler: (@MainActor @Sendable (AnalysisProgress) -> Void)? = nil,
        didScoreBatch: (@MainActor @Sendable () async -> Void)? = nil
    ) async throws {
        try await scorePhotos(
            photoIDs,
            requestedScopeJSON: #"{"source":"visiblePhotos"}"#,
            runStarted: runStarted,
            progressHandler: progressHandler,
            didScoreBatch: didScoreBatch
        )
    }

    func scorePhotos(
        _ photoIDs: [String],
        requestedScopeJSON: String,
        runStarted: (@MainActor @Sendable (String) -> Void)? = nil,
        progressHandler: (@MainActor @Sendable (AnalysisProgress) -> Void)? = nil,
        didScoreBatch: (@MainActor @Sendable () async -> Void)? = nil
    ) async throws {
        guard !photoIDs.isEmpty else {
            await progressHandler?(.idle)
            return
        }

        isPauseRequested = false
        // 已评过美学分的照片在建 run 时被跳过（见 createVisionAestheticsRun）。
        let runID = try repository.createVisionAestheticsRun(
            photoIDs: photoIDs,
            requestedScopeJSON: requestedScopeJSON
        )
        try await processRun(
            runID: runID,
            runStarted: runStarted,
            progressHandler: progressHandler,
            didScoreBatch: didScoreBatch
        )
    }

    func resumeVisionAestheticsRun(
        runID: String,
        runStarted: (@MainActor @Sendable (String) -> Void)? = nil,
        progressHandler: (@MainActor @Sendable (AnalysisProgress) -> Void)? = nil,
        didScoreBatch: (@MainActor @Sendable () async -> Void)? = nil
    ) async throws {
        isPauseRequested = false
        try await processRun(
            runID: runID,
            runStarted: runStarted,
            progressHandler: progressHandler,
            didScoreBatch: didScoreBatch
        )
    }

    // MARK: - 主循环

    private func processRun(
        runID: String,
        runStarted: (@MainActor @Sendable (String) -> Void)?,
        progressHandler: (@MainActor @Sendable (AnalysisProgress) -> Void)?,
        didScoreBatch: (@MainActor @Sendable () async -> Void)?
    ) async throws {
        await runStarted?(runID)
        await progressHandler?(try repository.runProgress(runID: runID))

        while true {
            try Task.checkCancellation()
            try await waitWhilePaused(runID: runID, progressHandler: progressHandler)

            let tasks = try repository.pendingVisionTasks(runID: runID, limit: batchSize)
            guard !tasks.isEmpty else { break }

            try repository.markTasksRunning(taskIDs: tasks.map(\.id))

            let outcomes = try await scoreBatch(tasks)

            var scored: [(VisionAnalysisTaskRecord, AestheticScoreResult)] = []
            var failed: [(VisionAnalysisTaskRecord, String)] = []
            for outcome in outcomes {
                switch outcome.result {
                case .success(let value):
                    scored.append((outcome.task, value))
                case .failure(let message):
                    failed.append((outcome.task, message))
                }
            }

            // 单事务批量落库 + 单次界面刷新。
            try repository.activateAestheticScores(scored)
            try repository.markTasksFailed(failed)

            await progressHandler?(try repository.runProgress(runID: runID))
            await didScoreBatch?()
        }

        await progressHandler?(try repository.runProgress(runID: runID))
    }

    /// 批内并发评分，返回结果（顺序不保证，但每个结果带回对应 task）。
    private func scoreBatch(
        _ tasks: [VisionAnalysisTaskRecord]
    ) async throws -> [BatchOutcome] {
        let provider = self.provider
        let adapter = self.photoLibraryAdapter
        let concurrency = max(1, min(scoringConcurrency, tasks.count))

        return try await withThrowingTaskGroup(of: BatchOutcome.self) { group in
            var outcomes: [BatchOutcome] = []
            outcomes.reserveCapacity(tasks.count)
            var nextIndex = 0

            // 先填满并发窗口。
            while nextIndex < concurrency {
                let task = tasks[nextIndex]
                group.addTask { try await Self.score(task: task, adapter: adapter, provider: provider) }
                nextIndex += 1
            }

            // 每完成一个就补充一个，维持稳定的并发度。
            while let outcome = try await group.next() {
                outcomes.append(outcome)
                if nextIndex < tasks.count {
                    let task = tasks[nextIndex]
                    group.addTask { try await Self.score(task: task, adapter: adapter, provider: provider) }
                    nextIndex += 1
                }
            }

            return outcomes
        }
    }

    /// 单张评分。取消向上抛出以中止整批；其它错误转为 `.failure` 不影响同批其它照片。
    private static func score(
        task: VisionAnalysisTaskRecord,
        adapter: PhotoLibraryAdapter,
        provider: AppleVisionAestheticsProvider
    ) async throws -> BatchOutcome {
        try Task.checkCancellation()
        do {
            let result: AestheticScoreResult
            if task.isScreenshot {
                result = .screenshot()
            } else {
                let data = try await adapter.requestImageData(
                    localIdentifier: task.localIdentifier,
                    allowNetworkAccess: false
                )
                try Task.checkCancellation()
                result = try await provider.scoreImage(data: data, isScreenshot: false)
            }
            return BatchOutcome(task: task, result: .success(result))
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return BatchOutcome(task: task, result: .failure(error.localizedDescription))
        }
    }

    private func waitWhilePaused(
        runID: String,
        progressHandler: (@MainActor @Sendable (AnalysisProgress) -> Void)?
    ) async throws {
        while isPauseRequested {
            try Task.checkCancellation()
            await progressHandler?(try repository.runProgress(runID: runID))
            try await Task.sleep(for: .milliseconds(250))
        }
    }

    private struct BatchOutcome: Sendable {
        let task: VisionAnalysisTaskRecord
        let result: ScoreOutcome
    }

    private enum ScoreOutcome: Sendable {
        case success(AestheticScoreResult)
        case failure(String)
    }
}

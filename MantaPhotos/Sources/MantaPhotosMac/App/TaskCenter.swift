import Foundation
import GRDB
import Observation

/// 多任务调度中心。
///
/// 统一管理五类分析任务的开始 / 暂停 / 停止 / 进度，**同时最多并发 2 个**，其余排队。
/// 美学评分复用既有 `AnalysisViewModel`（带 run/任务/重试的引擎），其余四类用 `PhotoAnalysisProcessor`。
@MainActor
@Observable
final class TaskCenter {
    /// 四类处理器型任务的进度（美学评分进度由 `progress(for:)` 实时映射 `AnalysisViewModel`）。
    private(set) var processorProgress: [AnalysisKind: TaskProgress] = [:]
    /// 各任务整体完成度（0–100，整数；空闲时由 DB 计数得出）。
    private(set) var completion: [AnalysisKind: Int] = [:]

    /// 当前选用的向量模型 key（由设置驱动）。
    var vectorModelKey: String = EmbeddingProviderRegistry.defaultKey
    /// 反向地理编码 / 分析结果使用的 locale（默认跟随系统，随应用语言更新）。
    var localeIdentifier: String = Locale.autoupdatingCurrent.identifier
    /// 当前可访问的照片源集合：分析任务只对这些源的照片排队 / 计数。nil = 不限制。
    var accessibleSourceIDs: Set<String>?

    @ObservationIgnored private let maxConcurrent = 2
    @ObservationIgnored private let batchSize = 24
    @ObservationIgnored private var runners: [AnalysisKind: Task<Void, Never>] = [:]
    @ObservationIgnored private var paused: Set<AnalysisKind> = []
    @ObservationIgnored private var stopping: Set<AnalysisKind> = []
    @ObservationIgnored private var queue: [AnalysisKind] = []

    @ObservationIgnored private var databaseQueue: DatabaseQueue?
    @ObservationIgnored private weak var library: PhotoLibraryViewModel?
    @ObservationIgnored private weak var analysis: AnalysisViewModel?

    func attach(databaseQueue: DatabaseQueue, library: PhotoLibraryViewModel, analysis: AnalysisViewModel) {
        self.databaseQueue = databaseQueue
        self.library = library
        self.analysis = analysis
    }

    // MARK: - 对外进度

    func progress(for kind: AnalysisKind) -> TaskProgress {
        if kind == .aesthetics { return mappedAestheticsProgress() }
        return processorProgress[kind] ?? .idle
    }

    /// 当前有活跃任务的种类（用于右上角状态与并发计数）。
    var activeKinds: [AnalysisKind] {
        AnalysisKind.allCases.filter { progress(for: $0).isActive }
    }

    /// 完成度百分比：运行中用实时进度，空闲用 DB 计数快照。
    func completionPercent(for kind: AnalysisKind) -> Int {
        let progress = progress(for: kind)
        if progress.isActive, progress.total > 0 {
            return max(0, min(100, Int((progress.fraction * 100).rounded())))
        }
        return completion[kind] ?? 0
    }

    /// 异步刷新完成度快照（DB 计数放后台，避免卡 UI）。
    func refreshCompletion() {
        guard let databaseQueue else { return }
        let key = vectorModelKey
        let accessible = accessibleSourceIDs
        Task {
            let snapshot = await Task.detached(priority: .utility) { () -> [AnalysisKind: Int] in
                let repository = AnalysisDataRepository(databaseQueue: databaseQueue, accessibleSourceIDs: accessible)
                let total = (try? repository.totalPhotoCount()) ?? 0
                func percent(_ pending: Int) -> Int {
                    total <= 0 ? 0 : max(0, min(100, Int((Double(total - pending) / Double(total) * 100).rounded())))
                }
                return [
                    .aesthetics: percent((try? repository.countPendingScores()) ?? total),
                    .tagging: percent((try? repository.countPending(kind: "tagging")) ?? total),
                    .geocoding: percent((try? repository.countPending(kind: "geocoding")) ?? total),
                    .typeAnalysis: percent((try? repository.countPending(kind: "type")) ?? total),
                    .vectorIndex: percent((try? repository.countPendingEmbedding(spaceKey: key)) ?? total)
                ]
            }.value
            self.completion = snapshot
        }
    }

    private var activeSlots: Int {
        runners.count + ((analysis?.analysisProgress.isRunning ?? false) ? 1 : 0)
    }

    // MARK: - 控制

    /// 打开 App 时自动开始所有有待处理项的任务（受并发上限约束）。
    func startAllPending() {
        cleanupStaleVectorSpaces()
        refreshCompletion()
        for kind in [AnalysisKind.vectorIndex, .tagging, .geocoding, .typeAnalysis] {
            start(kind)
        }
    }

    /// 清理非当前模型、超 30 天未使用的向量空间。
    private func cleanupStaleVectorSpaces() {
        guard let databaseQueue else { return }
        let currentKey = vectorModelKey
        Task.detached(priority: .utility) {
            try? AnalysisDataRepository(databaseQueue: databaseQueue).cleanupStaleSpaces(currentKey: currentKey)
        }
    }

    func start(_ kind: AnalysisKind) {
        stopping.remove(kind)
        paused.remove(kind)

        if kind == .aesthetics {
            guard !(analysis?.analysisProgress.isRunning ?? false) else { return }
            if activeSlots >= maxConcurrent { enqueue(kind); return }
            analysis?.scoreAllMatchedPhotos()
            return
        }

        guard runners[kind] == nil else { return }
        guard let processor = makeProcessor(kind) else { return }
        let pending = (try? processor.countPending()) ?? 0
        guard pending > 0 else {
            processorProgress[kind] = TaskProgress(status: .completed, completed: 0, total: 0, failed: 0)
            return
        }
        if activeSlots >= maxConcurrent {
            processorProgress[kind] = TaskProgress(status: .queued, completed: 0, total: pending, failed: 0)
            enqueue(kind)
            return
        }
        run(processor, pending: pending)
    }

    func pause(_ kind: AnalysisKind) {
        if kind == .aesthetics { analysis?.pauseAnalysis(); return }
        guard runners[kind] != nil else { return }
        paused.insert(kind)
    }

    func resume(_ kind: AnalysisKind) {
        if kind == .aesthetics { analysis?.resumeAnalysis(); return }
        paused.remove(kind)
        if runners[kind] == nil { start(kind) }
    }

    func stop(_ kind: AnalysisKind) {
        if kind == .aesthetics { analysis?.stopAnalysis(); return }
        queue.removeAll { $0 == kind }
        if runners[kind] != nil {
            stopping.insert(kind)
        } else {
            processorProgress[kind] = .idle
        }
    }

    // MARK: - 运行循环

    private func enqueue(_ kind: AnalysisKind) {
        if !queue.contains(kind) { queue.append(kind) }
    }

    private func startNextQueuedIfPossible() {
        guard activeSlots < maxConcurrent, !queue.isEmpty else { return }
        let next = queue.removeFirst()
        start(next)
    }

    private func run(_ processor: PhotoAnalysisProcessor, pending: Int) {
        let kind = processor.kind
        processorProgress[kind] = TaskProgress(status: .running, completed: 0, total: pending, failed: 0)
        runners[kind] = Task { [weak self] in
            await self?.loop(processor)
        }
    }

    private func loop(_ processor: PhotoAnalysisProcessor) async {
        let kind = processor.kind
        let total = processorProgress[kind]?.total ?? 0
        // 已处理过的 id：若某一批没有新 id（如失败项被反复取出），说明无法再推进 → 收尾，
        // 既避免死循环、也避免完成数超过总数。
        var processedIDs = Set<String>()
        while true {
            if stopping.contains(kind) { break }
            while paused.contains(kind) {
                if processorProgress[kind]?.status != .paused { processorProgress[kind]?.status = .paused }
                try? await Task.sleep(for: .milliseconds(250))
                if stopping.contains(kind) { break }
            }
            if stopping.contains(kind) { break }
            if processorProgress[kind]?.status != .running { processorProgress[kind]?.status = .running }

            // 取批与处理都放后台，主线程只更新进度，确保大库不卡 UI。
            let batch = await Task.detached(priority: .utility) { [batchSize] in
                (try? processor.nextBatch(limit: batchSize)) ?? []
            }.value
            if batch.isEmpty { break }
            let newIDs = batch.map(\.id).filter { !processedIDs.contains($0) }
            if newIDs.isEmpty { break }

            _ = await Task.detached(priority: .utility) { (try? await processor.process(batch)) ?? 0 }.value
            processedIDs.formUnion(batch.map(\.id))
            let done = total > 0 ? min(total, processedIDs.count) : processedIDs.count
            processorProgress[kind]?.completed = done
            processorProgress[kind]?.total = max(total, done)
        }

        let wasStopped = stopping.contains(kind)
        processorProgress[kind]?.status = wasStopped ? .idle : .completed
        runners[kind] = nil
        paused.remove(kind)
        stopping.remove(kind)

        // 标签 / 评分等会改变照片展示，跑完刷新一次。
        if kind == .tagging || kind == .typeAnalysis {
            await library?.refreshPhotos()
        }
        refreshCompletion()
        startNextQueuedIfPossible()
    }

    // MARK: - 构造处理器

    private func makeProcessor(_ kind: AnalysisKind) -> PhotoAnalysisProcessor? {
        guard let databaseQueue else { return nil }
        let repository = AnalysisDataRepository(databaseQueue: databaseQueue, accessibleSourceIDs: accessibleSourceIDs)
        switch kind {
        case .tagging:
            return TaggingProcessor(repository: repository, localeIdentifier: localeIdentifier)
        case .geocoding:
            return GeocodingProcessor(repository: repository, localeIdentifier: localeIdentifier)
        case .typeAnalysis:
            return TypeProcessor(repository: repository)
        case .vectorIndex:
            let provider = EmbeddingProviderRegistry.provider(forKey: vectorModelKey)
            guard provider.descriptor.isAvailable else { return nil }
            return VectorIndexProcessor(repository: repository, provider: provider)
        case .aesthetics:
            return nil
        }
    }

    private func mappedAestheticsProgress() -> TaskProgress {
        guard let progress = analysis?.analysisProgress else { return .idle }
        let status: TaskProgress.Status
        switch progress.status {
        case .running: status = .running
        case .paused: status = .paused
        case .stopping: status = .stopping
        case .completed: status = .completed
        case .failed: status = .failed
        case .cancelled, .idle: status = .idle
        }
        return TaskProgress(status: status, completed: progress.completed, total: progress.total, failed: progress.failed)
    }
}

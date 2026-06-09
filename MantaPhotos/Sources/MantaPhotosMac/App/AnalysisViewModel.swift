import Foundation
import GRDB
import Observation

/// AI 分析（当前为 Apple Vision 美学评分）的进度与控制。
///
/// 职责单一：发起 / 暂停 / 继续 / 停止 / 重试评分任务，并对外暴露进度。
/// 暂停状态内聚在 `AnalysisScheduler`（actor）中，本对象不再持有暂停标志。
@MainActor
@Observable
final class AnalysisViewModel {
    private(set) var analysisProgress = AnalysisProgress.idle
    private(set) var lastErrorMessage: String?

    @ObservationIgnored weak var library: PhotoLibraryViewModel?
    @ObservationIgnored private var databaseQueue: DatabaseQueue?
    @ObservationIgnored private var repository: AnalysisRepository?
    @ObservationIgnored private var scheduler: AnalysisScheduler?
    @ObservationIgnored private var analysisTask: Task<Void, Never>?
    @ObservationIgnored private var analysisRunID: String?

    func attach(databaseQueue: DatabaseQueue, library: PhotoLibraryViewModel) {
        self.databaseQueue = databaseQueue
        self.library = library
        let repository = AnalysisRepository(databaseQueue: databaseQueue)
        self.repository = repository
        self.scheduler = AnalysisScheduler(
            repository: repository,
            photoLibraryAdapter: PhotoLibraryAdapter(),
            provider: AppleVisionAestheticsProvider()
        )
    }

    private var isBusy: Bool { analysisTask != nil }

    // MARK: - 发起评分

    /// 对当前已加载（可见）照片评分。
    func scoreVisiblePhotos() {
        let ids = library?.loadedPhotoIDs ?? []
        startScoring(ids: ids, requestedScopeJSON: #"{"source":"visiblePhotos"}"#)
    }

    /// 对当前筛选命中的全部照片评分。
    func scoreAllMatchedPhotos() {
        guard let library else { return }
        let ids: [String]
        do {
            ids = try library.matchedPhotoIDs()
        } catch {
            lastErrorMessage = error.localizedDescription
            return
        }
        startScoring(ids: ids, requestedScopeJSON: #"{"source":"allMatchedPhotos"}"#)
    }

    private func startScoring(ids: [String], requestedScopeJSON: String) {
        guard !isBusy, let scheduler else { return }
        guard !ids.isEmpty else {
            analysisProgress = .idle
            return
        }

        analysisTask = Task { [scheduler, ids, requestedScopeJSON] in
            do {
                try await scheduler.scorePhotos(
                    ids,
                    requestedScopeJSON: requestedScopeJSON,
                    runStarted: { [weak self] runID in
                        self?.analysisRunID = runID
                    },
                    progressHandler: { [weak self] progress in
                        self?.analysisProgress = progress
                    }
                    // 不再逐批刷新照片页（每批刷新会全量重查并重拉可见缩略图，导致评分时卡顿）。
                    // 进度条仍由 progressHandler 实时更新；照片分数在整轮结束后一次性刷新。
                )
                finishProgress(status: .completed)
            } catch is CancellationError {
                finishProgress(status: .cancelled)
            } catch {
                lastErrorMessage = error.localizedDescription
                finishProgress(status: .failed)
            }
            // 整轮评分结束后只刷新一次照片页。
            await library?.refreshPhotos()
            clearActiveRun()
        }
    }

    // MARK: - 重试失败

    func retryFailedAnalysis() {
        guard !isBusy, let scheduler, let repository else { return }
        let preferredRunID = analysisProgress.currentRunID

        analysisTask = Task { [scheduler, repository, preferredRunID] in
            do {
                let runID = if let preferredRunID {
                    preferredRunID
                } else {
                    try repository.latestRunIDWithFailedTasks()
                }

                guard let runID else {
                    lastErrorMessage = "No failed scoring tasks to retry."
                    analysisProgress = .idle
                    clearActiveRun()
                    return
                }

                let retryCount = try repository.retryFailedTasks(runID: runID)
                guard retryCount > 0 else {
                    lastErrorMessage = "No failed scoring tasks to retry."
                    analysisProgress = try repository.runProgress(runID: runID)
                    clearActiveRun()
                    return
                }

                try await scheduler.resumeVisionAestheticsRun(
                    runID: runID,
                    runStarted: { [weak self] runID in
                        self?.analysisRunID = runID
                    },
                    progressHandler: { [weak self] progress in
                        self?.analysisProgress = progress
                    }
                    // 同上：不逐批刷新，整轮结束后统一刷新一次。
                )
                finishProgress(status: .completed)
            } catch is CancellationError {
                finishProgress(status: .cancelled)
            } catch {
                lastErrorMessage = error.localizedDescription
                finishProgress(status: .failed)
            }
            await library?.refreshPhotos()
            clearActiveRun()
        }
    }

    // MARK: - 暂停 / 继续 / 停止

    func pauseAnalysis() {
        guard isBusy, let repository, let scheduler, let analysisRunID else { return }
        Task { await scheduler.pause() }
        do {
            try repository.pauseRun(runID: analysisRunID)
            analysisProgress = try repository.runProgress(runID: analysisRunID)
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func resumeAnalysis() {
        guard isBusy, let repository, let scheduler, let analysisRunID else { return }
        Task { await scheduler.resume() }
        do {
            try repository.resumeRun(runID: analysisRunID)
            analysisProgress = try repository.runProgress(runID: analysisRunID)
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func stopAnalysis() {
        guard isBusy else { return }
        let runID = analysisRunID
        analysisProgress.status = .stopping
        analysisTask?.cancel()
        if let scheduler { Task { await scheduler.resume() } }
        if let repository, let runID {
            do {
                try repository.cancelRun(runID: runID)
                analysisProgress = try repository.runProgress(runID: runID)
            } catch {
                lastErrorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Helpers

    private func finishProgress(status: AnalysisStatus) {
        analysisProgress = AnalysisProgress(
            status: status,
            completed: analysisProgress.completed,
            failed: analysisProgress.failed,
            total: analysisProgress.total,
            currentRunID: analysisProgress.currentRunID
        )
    }

    private func clearActiveRun() {
        analysisRunID = nil
        analysisTask = nil
    }
}

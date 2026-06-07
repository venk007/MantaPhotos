import Foundation
import GRDB
import Observation
import Photos

/// 照片库数据流。
///
/// 职责单一：管理照片墙的查询条件、结果集、分页、导入进度与查看器选择。
/// 不再与导航、AI 分析耦合（后两者分别在 `NavigationState` / `AnalysisViewModel`）。
@MainActor
@Observable
final class PhotoLibraryViewModel {
    var searchFilter = SearchFilterState()
    private(set) var photoResults: [PhotoSearchResult] = []
    private(set) var matchedPhotoCount = 0
    private(set) var isRefreshingPhotos = false
    private(set) var isLoadingMorePhotos = false
    var importProgress = PhotoImportProgress.idle
    private(set) var lastErrorMessage: String?

    var selectedPhotoID: String?
    var selectedPhotoForViewer: PhotoSearchResult?
    var isViewerPresented = false

    @ObservationIgnored private var databaseQueue: DatabaseQueue?
    @ObservationIgnored private var importTask: Task<Void, Never>?
    @ObservationIgnored private var didStartInitialImport = false
    @ObservationIgnored private let photoPageSize = 3_000

    /// 由组合根（`AppState`）在 bootstrap 完成后注入数据库连接。
    func attach(databaseQueue: DatabaseQueue) {
        self.databaseQueue = databaseQueue
    }

    func reportError(_ error: Error) {
        lastErrorMessage = error.localizedDescription
    }

    // MARK: - 导入

    func startInitialImportIfPossible() {
        guard !didStartInitialImport, databaseQueue != nil else { return }
        didStartInitialImport = true
        startImport()
    }

    func startImport() {
        guard importTask == nil, let databaseQueue else { return }

        importTask = Task { [databaseQueue] in
            let adapter = PhotoLibraryAdapter()
            importProgress = PhotoImportProgress(
                phase: .requestingAuthorization,
                imported: 0,
                total: 0,
                message: "Requesting Photos access"
            )

            let status = adapter.authorizationStatus()
            let resolvedStatus: PHAuthorizationStatus
            if status == .notDetermined {
                resolvedStatus = await adapter.requestAuthorization()
            } else {
                resolvedStatus = status
            }

            guard resolvedStatus == .authorized || resolvedStatus == .limited else {
                importProgress = PhotoImportProgress(
                    phase: .denied,
                    imported: 0,
                    total: 0,
                    message: "Photos access is not authorized"
                )
                importTask = nil
                return
            }

            do {
                let useCase = PhotoLibraryImportUseCase(
                    adapter: adapter,
                    repository: PhotoAssetRepository(databaseQueue: databaseQueue)
                )

                _ = try await useCase.importAll { [weak self] progress in
                    self?.importProgress = progress
                } initialBatchCompleted: { [weak self] in
                    await self?.refreshPhotos()
                }

                await refreshPhotos()
            } catch is CancellationError {
                importProgress = .idle
            } catch {
                lastErrorMessage = error.localizedDescription
                importProgress = PhotoImportProgress(
                    phase: .failed,
                    imported: importProgress.imported,
                    total: importProgress.total,
                    message: error.localizedDescription
                )
            }

            importTask = nil
        }
    }

    // MARK: - 查询与分页

    func refreshPhotos(limit: Int? = nil) async {
        guard let databaseQueue else { return }
        let filter = searchFilter
        let limit = limit ?? photoPageSize
        isRefreshingPhotos = true
        defer { isRefreshingPhotos = false }

        do {
            let repository = SearchRepository(databaseQueue: databaseQueue)
            photoResults = try await Task.detached(priority: .userInitiated) {
                try repository.searchResults(filter: filter, limit: limit)
            }.value
            matchedPhotoCount = try await Task.detached(priority: .userInitiated) {
                try repository.count(filter: filter)
            }.value
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func refreshPhotosIfNeeded(limit: Int? = nil) async {
        guard photoResults.isEmpty else { return }
        await refreshPhotos(limit: limit)
    }

    func loadMorePhotosIfNeeded() {
        guard !isRefreshingPhotos, !isLoadingMorePhotos, photoResults.count < matchedPhotoCount, let databaseQueue else { return }
        let filter = searchFilter
        let offset = photoResults.count
        isLoadingMorePhotos = true

        Task { [databaseQueue, filter, offset, photoPageSize] in
            do {
                let repository = SearchRepository(databaseQueue: databaseQueue)
                let nextResults = try await Task.detached(priority: .utility) {
                    try repository.searchResults(filter: filter, limit: photoPageSize, offset: offset)
                }.value

                let existingIDs = Set(photoResults.map(\.id))
                let uniqueResults = nextResults.filter { !existingIDs.contains($0.id) }
                photoResults.append(contentsOf: uniqueResults)
            } catch {
                lastErrorMessage = error.localizedDescription
            }

            isLoadingMorePhotos = false
        }
    }

    /// 当前已加载照片的 ID（供评分等场景按可见范围取用）。
    var loadedPhotoIDs: [String] { photoResults.map(\.id) }

    /// 当前筛选条件命中的全部照片 ID。
    func matchedPhotoIDs() throws -> [String] {
        guard let databaseQueue else { return [] }
        return try SearchRepository(databaseQueue: databaseQueue).searchIDs(filter: searchFilter)
    }

    // MARK: - 查看器

    func openViewer(for result: PhotoSearchResult) {
        selectedPhotoID = result.id
        selectedPhotoForViewer = result
        isViewerPresented = true
    }

    func closeViewer() {
        isViewerPresented = false
        selectedPhotoForViewer = nil
    }

    func selectAdjacentPhoto(delta: Int) {
        guard
            let currentID = selectedPhotoForViewer?.id,
            let index = photoResults.firstIndex(where: { $0.id == currentID })
        else { return }

        let nextIndex = max(0, min(photoResults.count - 1, index + delta))
        selectedPhotoForViewer = photoResults[nextIndex]
        selectedPhotoID = photoResults[nextIndex].id
    }

    func toggleSelectedViewerFavorite() {
        guard let selectedPhotoForViewer, let databaseQueue else { return }
        let currentIndex = photoResults.firstIndex(where: { $0.id == selectedPhotoForViewer.id }) ?? 0
        let nextValue = !selectedPhotoForViewer.asset.isFavorite

        Task { [databaseQueue] in
            do {
                try await PhotoLibraryAdapter().setFavorite(
                    localIdentifier: selectedPhotoForViewer.asset.localIdentifier,
                    isFavorite: nextValue
                )
                try PhotoAssetRepository(databaseQueue: databaseQueue).updateFavorite(
                    photoID: selectedPhotoForViewer.id,
                    isFavorite: nextValue
                )
                await refreshPhotos()
                reconcileViewerSelection(previousID: selectedPhotoForViewer.id, previousIndex: currentIndex)
            } catch {
                lastErrorMessage = error.localizedDescription
            }
        }
    }

    func toggleSelectedViewerTrash() {
        guard let selectedPhotoForViewer, let databaseQueue else { return }
        let currentIndex = photoResults.firstIndex(where: { $0.id == selectedPhotoForViewer.id }) ?? 0
        let nextValue = !selectedPhotoForViewer.asset.inTrash
        let trashedAt = nextValue ? Date() : nil

        do {
            try PhotoAssetRepository(databaseQueue: databaseQueue).updateTrash(
                photoID: selectedPhotoForViewer.id,
                inTrash: nextValue,
                trashedAt: trashedAt
            )
            Task {
                await refreshPhotos()
                reconcileViewerSelection(previousID: selectedPhotoForViewer.id, previousIndex: currentIndex)
            }
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func deleteSelectedViewerPhotoFromPhotosLibrary() {
        guard let selectedPhotoForViewer, let databaseQueue else { return }
        let currentIndex = photoResults.firstIndex(where: { $0.id == selectedPhotoForViewer.id }) ?? 0

        Task { [databaseQueue] in
            do {
                try await PhotoLibraryAdapter().deleteAsset(localIdentifier: selectedPhotoForViewer.asset.localIdentifier)
                try PhotoAssetRepository(databaseQueue: databaseQueue).markSystemDeleted(photoID: selectedPhotoForViewer.id)
                await refreshPhotos()
                reconcileViewerSelection(previousID: selectedPhotoForViewer.id, previousIndex: currentIndex)
            } catch {
                lastErrorMessage = error.localizedDescription
            }
        }
    }

    private func reconcileViewerSelection(previousID: String, previousIndex: Int) {
        if let updated = photoResults.first(where: { $0.id == previousID }) {
            selectedPhotoID = updated.id
            selectedPhotoForViewer = updated
            return
        }

        guard isViewerPresented else { return }
        guard !photoResults.isEmpty else {
            closeViewer()
            return
        }

        let nextIndex = max(0, min(photoResults.count - 1, previousIndex))
        selectedPhotoForViewer = photoResults[nextIndex]
        selectedPhotoID = photoResults[nextIndex].id
    }
}

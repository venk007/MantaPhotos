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
    /// 废片篓是一个独立功能，而非 `searchFilter` 的一项筛选条件：
    /// 开启时叠加显示已删除照片，不修改 `searchFilter` 本身，
    /// 因此退出废片篓返回照片页时，原有筛选条件原样保留。
    private(set) var isTrashViewActive = false
    private(set) var photoResults: [PhotoSearchResult] = []
    private(set) var matchedPhotoCount = 0
    private(set) var isRefreshingPhotos = false
    private(set) var isLoadingMorePhotos = false
    /// 相似照片（语义）结果模式：true 时照片墙展示的是向量检索结果。
    private(set) var isSimilarMode = false
    var importProgress = PhotoImportProgress.idle
    private(set) var lastErrorMessage: String?

    var selectedPhotoID: String?
    var selectedPhotoForViewer: PhotoSearchResult?
    var isViewerPresented = false

    /// 浏览上下文返回栈：详见 `BrowseContext`。
    private(set) var browseStack: [BrowseContext] = []
    /// 「返回」恢复后，照片墙应滚动回到的照片 ID；由 `PhotosPageView` 消费后清空。
    var pendingScrollAnchorID: String?
    /// 是否存在可返回的上一次浏览位置（驱动"返回"按钮的展示）。
    var canGoBack: Bool { !browseStack.isEmpty }

    /// 当前所有照片源（系统图库 + 本地目录等）。
    private(set) var sources: [PhotoSourceDescriptor] = []
    /// 各源当前是否可访问（sourceID → 可用）。每次启动判定：系统图库看授权 + 探测；本地源看路径可达 + 书签可解析。
    private(set) var sourceAvailability: [String: Bool] = [:]

    /// 当前可访问的源 id 集合，供搜索 / 筛选 / 照片墙限定。
    /// 尚未判定（空字典）时返回 nil（不限制）；判定后返回可访问集合（可能为空 = 无可访问源）。
    var accessibleSourceIDs: Set<String>? {
        guard !sourceAvailability.isEmpty else { return [] }
        return Set(sourceAvailability.filter(\.value).map(\.key))
    }

    @ObservationIgnored private var databaseQueue: DatabaseQueue?
    @ObservationIgnored private var sourceRepository: PhotoSourceRepository?
    @ObservationIgnored private var importTask: Task<Void, Never>?
    @ObservationIgnored private var didStartInitialImport = false
    @ObservationIgnored private let photoPageSize = 3_000
    /// 触底加载的增量页：比首屏页小，单次快照 apply 更轻，滚动到底更平滑。
    @ObservationIgnored private let loadMorePageSize = 800

    /// 由组合根（`AppState`）在 bootstrap 完成后注入数据库连接。
    func attach(databaseQueue: DatabaseQueue) {
        self.databaseQueue = databaseQueue
        self.sourceRepository = PhotoSourceRepository(databaseQueue: databaseQueue)
    }

    // MARK: - 照片源管理

    /// 读取所有源、判定可用性、解析可访问的本地源书签并注册到 `PhotoSourceRegistry`。
    /// 在 bootstrap 时调用一次。
    ///
    /// 关键：书签解析（`resolvingBookmarkData`）对已弹出的外置卷会**长时间阻塞**，
    /// 必须放到后台线程，且先用 `rootPath` 可达性做快速门，避免主线程卡死（曾导致主界面无响应）。
    func loadAndRegisterSources() async {
        PhotoSourceRegistry.shared.register(descriptor: .systemPhotos, resolvedRoot: nil)
        guard let sourceRepository else { return }
        let descriptors: [PhotoSourceDescriptor]
        do {
            descriptors = try sourceRepository.allSources()
        } catch {
            reportError(error)
            return
        }
        sources = descriptors

        let fileSources = descriptors.filter { $0.kind.isFileBased && $0.isEnabled && $0.rootBookmark != nil }

        // 全部解析与探测放后台，主线程（run loop）不被阻塞。
        let outcome = await Task.detached(priority: .userInitiated) { () -> (system: Bool, resolved: [(String, URL?)]) in
            let systemOK = Self.isSystemPhotosAccessible()
            let resolved: [(String, URL?)] = fileSources.map { descriptor in
                // 快速门：rootPath 不可达（卷已弹出 / 目录被删）→ 直接判不可用，跳过会阻塞的书签解析。
                if let path = descriptor.rootPath, !FileManager.default.fileExists(atPath: path) {
                    return (descriptor.id, nil)
                }
                guard let bookmark = descriptor.rootBookmark,
                      let url = Self.resolveBookmark(bookmark),
                      url.startAccessingSecurityScopedResource(),
                      (try? url.checkResourceIsReachable()) == true else {
                    return (descriptor.id, nil)
                }
                return (descriptor.id, url)
            }
            return (systemOK, resolved)
        }.value

        // 回到主线程更新注册表与可用性。
        var availability: [String: Bool] = [:]
        availability[PhotoSourceDescriptor.systemPhotosID] = outcome.system
        for (id, url) in outcome.resolved {
            if let url, let descriptor = descriptors.first(where: { $0.id == id }) {
                PhotoSourceRegistry.shared.register(descriptor: descriptor, resolvedRoot: url)
                availability[id] = true
            } else {
                PhotoSourceRegistry.shared.unregister(sourceID: id)
                availability[id] = false
            }
        }
        // 被停用 / 无书签的文件源标记为不可用（用于设置页展示）。
        for descriptor in descriptors where availability[descriptor.id] == nil {
            availability[descriptor.id] = descriptor.kind == .systemPhotos ? outcome.system : false
        }
        sourceAvailability = availability
    }

    /// 系统图库是否可访问：需 PhotoKit 授权，且能探测到至少一项资产（库卷已弹出时探测为空）。
    /// 注：探测在后台调用。授权但库卷不可达的精确检测受公共 API 限制，以「能取到 1 项」为近似信号。
    nonisolated private static func isSystemPhotosAccessible() -> Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else { return false }
        let options = PHFetchOptions()
        options.fetchLimit = 1
        return PHAsset.fetchAssets(with: options).count > 0
    }

    /// 添加一个本地目录源：保存安全作用域书签、注册、后台扫描导入。
    func addLocalDirectory(url: URL) {
        guard let sourceRepository, let databaseQueue else { return }
        do {
            let bookmark = try url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            let descriptor = PhotoSourceDescriptor(
                id: "local:\(UUID().uuidString)",
                kind: .localDirectory,
                displayName: url.lastPathComponent,
                rootBookmark: bookmark,
                rootPath: url.path,
                isEnabled: true
            )
            try sourceRepository.upsert(descriptor)
            _ = url.startAccessingSecurityScopedResource()
            PhotoSourceRegistry.shared.register(descriptor: descriptor, resolvedRoot: url)
            sources = try sourceRepository.allSources()
            runLocalImport(sourceID: descriptor.id, rootURL: url, databaseQueue: databaseQueue)
        } catch {
            reportError(error)
        }
    }

    /// 重新扫描一个本地源（手动同步；FSEvents 实时监听为后续增强）。
    func rescanSource(id: String) {
        guard let databaseQueue,
              PhotoSourceRegistry.shared.kind(forSourceID: id).isFileBased,
              let url = PhotoSourceRegistry.shared.rootURL(forSourceID: id) else { return }
        runLocalImport(sourceID: id, rootURL: url, databaseQueue: databaseQueue)
    }

    /// 移除一个本地 / 外部源（及其全部资产）。系统源不可移除。
    func removeSource(id: String) {
        guard id != PhotoSourceDescriptor.systemPhotosID, let sourceRepository else { return }
        do {
            PhotoSourceRegistry.shared.unregister(sourceID: id)
            try sourceRepository.deleteSource(sourceID: id)
            sources = try sourceRepository.allSources()
            Task { await refreshPhotos() }
        } catch {
            reportError(error)
        }
    }

    private func runLocalImport(sourceID: String, rootURL: URL, databaseQueue: DatabaseQueue) {
        let importer = LocalDirectoryImporter(
            repository: PhotoAssetRepository(databaseQueue: databaseQueue),
            sourceID: sourceID,
            rootURL: rootURL
        )
        Task { [weak self] in
            do {
                _ = try await Task.detached(priority: .utility) {
                    try await importer.importAll()
                }.value
                await self?.refreshPhotos()
            } catch {
                self?.reportError(error)
            }
        }
    }

    nonisolated private static func resolveBookmark(_ data: Data) -> URL? {
        var isStale = false
        return try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
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

    /// 启动时自动加载所有当前可访问源的内容：系统图库 + 已注册的本地目录（增量、幂等）。
    /// 这样打开应用即展示可访问项，无需手动点击导入。
    func startAccessibleSourceImports() {
        // 系统图库：仅在可访问（已授权且库卷可用）时导入。
        if sourceAvailability[PhotoSourceDescriptor.systemPhotosID] != false {
            startInitialImportIfPossible()
        }
        // 本地目录源：对每个可访问且已注册的源做增量扫描；导入完成后各自刷新照片墙。
        guard let databaseQueue else { return }
        for descriptor in sources where descriptor.kind.isFileBased {
            guard sourceAvailability[descriptor.id] == true,
                  let url = PhotoSourceRegistry.shared.rootURL(forSourceID: descriptor.id) else { continue }
            runLocalImport(sourceID: descriptor.id, rootURL: url, databaseQueue: databaseQueue)
        }
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

    /// 实际用于查询的筛选条件：在 `searchFilter` 基础上按废片篓视图状态
    /// 覆盖 `inTrash`，但不修改 `searchFilter` 本身（见类型注释）。
    private var effectiveFilter: SearchFilterState {
        var filter = searchFilter
        filter.inTrash = isTrashViewActive
        return filter
    }

    /// 切换废片篓视图。这是一个独立的查看模式，不写入 `searchFilter`，
    /// 因此再次点击照片页菜单 / 底部组件返回照片页时，原有筛选条件不受影响。
    ///
    /// 进入时把当前位置（筛选结果 + 滚动锚点）推入返回栈；再次点击（即关闭）时
    /// 走 `goBack()` 还原，与「相似照片」的返回路径保持一致。
    func toggleTrashView() {
        if isTrashViewActive {
            goBack()
            return
        }
        pushBrowseContext(viewerPhotoID: nil, anchorPhotoID: photoResults.first?.id)
        isTrashViewActive = true
        Task { await refreshPhotos() }
    }

    /// 退出废片篓视图，返回照片页并保留原有筛选条件。
    /// 用于「切换路由 / 点击 Logo」等主动离开场景：不走返回栈，直接清空（视为放弃返回点）。
    func exitTrashView() {
        guard isTrashViewActive else { return }
        isTrashViewActive = false
        browseStack.removeAll()
        Task { await refreshPhotos() }
    }

    // MARK: - 浏览上下文返回栈

    /// 推入当前浏览位置快照。在进入「相似照片」「废片篓」等特殊相册前调用。
    /// - Parameters:
    ///   - viewerPhotoID: 若查看器当前打开，传入正在查看的照片 ID；返回时会重新打开其详情。
    ///   - anchorPhotoID: 返回时照片墙应滚动回到的照片 ID（一般是当前可见的第一张）。
    private func pushBrowseContext(viewerPhotoID: String?, anchorPhotoID: String?) {
        browseStack.append(
            BrowseContext(
                filter: searchFilter,
                isTrashViewActive: isTrashViewActive,
                isSimilarMode: isSimilarMode,
                results: photoResults,
                matchedCount: matchedPhotoCount,
                viewerPhotoID: viewerPhotoID,
                anchorPhotoID: anchorPhotoID
            )
        )
    }

    /// 返回到进入「特殊相册」之前的位置：还原筛选结果、计数与模式，
    /// 并通过 `pendingScrollAnchorID` / 重新打开查看器恢复"上一次定位"。
    ///
    /// 栈为空时（如非正常路径直接进入）回退到简单退出，保证「返回」始终可用。
    func goBack() {
        guard let context = browseStack.popLast() else {
            if isSimilarMode {
                Task { await refreshPhotos() }
            } else if isTrashViewActive {
                isTrashViewActive = false
                Task { await refreshPhotos() }
            }
            return
        }

        searchFilter = context.filter
        isTrashViewActive = context.isTrashViewActive
        isSimilarMode = context.isSimilarMode
        photoResults = context.results
        matchedPhotoCount = context.matchedCount
        pendingScrollAnchorID = context.anchorPhotoID

        if let viewerPhotoID = context.viewerPhotoID,
           let match = context.results.first(where: { $0.id == viewerPhotoID }) {
            openViewer(for: match)
        }
    }

    func refreshPhotos(limit: Int? = nil) async {
        guard let databaseQueue else { return }
        isSimilarMode = false
        let filter = effectiveFilter
        let limit = limit ?? photoPageSize
        isRefreshingPhotos = true
        defer { isRefreshingPhotos = false }

        do {
            let repository = SearchRepository(databaseQueue: databaseQueue, accessibleSourceIDs: accessibleSourceIDs)
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
        let filter = effectiveFilter
        let offset = photoResults.count
        isLoadingMorePhotos = true

        Task { [databaseQueue, filter, offset, loadMorePageSize, accessibleSourceIDs] in
            do {
                let repository = SearchRepository(databaseQueue: databaseQueue, accessibleSourceIDs: accessibleSourceIDs)
                let nextResults = try await Task.detached(priority: .utility) {
                    try repository.searchResults(filter: filter, limit: loadMorePageSize, offset: offset)
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
        return try SearchRepository(databaseQueue: databaseQueue, accessibleSourceIDs: accessibleSourceIDs).searchIDs(filter: effectiveFilter)
    }

    // MARK: - 查看器

    func openViewer(for result: PhotoSearchResult) {
        selectedPhotoID = result.id
        selectedPhotoForViewer = result
        isViewerPresented = true
    }

    // MARK: - P2：详情与语义（相似照片）

    /// 查看器详情：地名 / 标签 / 是否 RAW（后台读取）。
    func loadExtraDetail(photoID: String) async -> PhotoExtraDetail {
        guard let databaseQueue else { return .empty }
        let repository = AnalysisDataRepository(databaseQueue: databaseQueue)
        return await Task.detached(priority: .userInitiated) {
            let place = (try? repository.fetchPlace(photoID: photoID)) ?? nil
            let tags = (try? repository.fetchTagNames(photoID: photoID)) ?? []
            let isRaw = (try? repository.isRaw(photoID: photoID)) ?? false
            return PhotoExtraDetail(place: place, tags: tags, isRaw: isRaw)
        }.value
    }

    /// 「相似照片」相似度阈值：只展示相关性较高的结果（余弦相似度，越大越相似）。
    /// 不设数量上限——结果数量完全由阈值决定，按相似度从高到低排序。
    /// `nonisolated`：纯常量，需在 `Task.detached`（非主 actor）闭包内直接访问，
    /// 否则因 `@MainActor` 隔离要求 `await`（"Expression is 'async' but is not marked with 'await'"）。
    nonisolated static let similarPhotoMinScore: Float = 0.65
    /// KNN 候选池上限（sqlite-vec 需显式 k；远大于实际命中数，practically 相当于不设上限）。
    private nonisolated static let similarPhotoCandidatePoolSize = 2000

    /// 以指定照片为查询做向量相似检索，结果替换照片墙（语义搜索：以图搜图）。
    /// 只保留相似度 ≥ `similarPhotoMinScore` 的结果，按相似度从高到低排序，不设数量上限。
    func searchSimilar(to result: PhotoSearchResult, spaceKey: String) {
        guard let databaseQueue else { return }
        let repository = AnalysisDataRepository(databaseQueue: databaseQueue)
        let search = SearchRepository(databaseQueue: databaseQueue, accessibleSourceIDs: accessibleSourceIDs)
        let queryID = result.id
        Task {
            do {
                let query = try await Task.detached(priority: .userInitiated) {
                    try repository.embedding(photoID: queryID, spaceKey: spaceKey)
                }.value
                guard let query else {
                    lastErrorMessage = "该照片尚未生成向量，请等待向量索引完成后再试。"
                    return
                }
                let matches = try await Task.detached(priority: .userInitiated) {
                    try repository.nearest(
                        to: query,
                        spaceKey: spaceKey,
                        limit: Self.similarPhotoCandidatePoolSize,
                        minScore: Self.similarPhotoMinScore,
                        excluding: queryID
                    )
                }.value
                let scoreByID = Dictionary(uniqueKeysWithValues: matches.map { ($0.photoID, Double($0.score)) })
                let ids = matches.map(\.photoID)
                let results = try await Task.detached(priority: .userInitiated) {
                    try search.results(forIDs: ids)
                }.value
                // 基准照片本身置顶展示（标记 isReferencePhoto，缩略图角标展示「原图」而非相似度）。
                var referenceItem = result
                referenceItem.similarityScore = nil
                referenceItem.isReferencePhoto = true
                let similarItems = results.map { item in
                    var item = item
                    item.similarityScore = scoreByID[item.id]
                    item.isReferencePhoto = false
                    return item
                }

                // 记录返回点：返回时重新打开基准照片的详情，并把照片墙滚动回它所在位置。
                pushBrowseContext(viewerPhotoID: queryID, anchorPhotoID: queryID)
                closeViewer()
                photoResults = [referenceItem] + similarItems
                matchedPhotoCount = photoResults.count
                isSimilarMode = true
            } catch {
                lastErrorMessage = error.localizedDescription
            }
        }
    }

    /// 文字语义搜索（需当前向量模型支持文字查询，如 JINA V5）。结果按相似度排序替换照片墙。
    func semanticSearch(query: String, spaceKey: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let databaseQueue else { return }
        let repository = AnalysisDataRepository(databaseQueue: databaseQueue)
        let search = SearchRepository(databaseQueue: databaseQueue, accessibleSourceIDs: accessibleSourceIDs)
        let provider = EmbeddingProviderRegistry.provider(forKey: spaceKey)
        Task {
            do {
                let vector = try await provider.textEmbedding(query: trimmed)
                let matches = try await Task.detached(priority: .userInitiated) {
                    try repository.nearest(to: vector, spaceKey: spaceKey, limit: 300, excluding: nil)
                }.value
                let results = try await Task.detached(priority: .userInitiated) {
                    try search.results(forIDs: matches.map(\.photoID))
                }.value
                photoResults = results
                matchedPhotoCount = results.count
                isSimilarMode = true
            } catch {
                lastErrorMessage = error.localizedDescription
            }
        }
    }

    /// 退出相似照片模式，恢复正常筛选结果。
    /// 用于「清除」按钮等主动离开场景：不走返回栈，直接清空（视为放弃返回点）。
    func exitSimilarMode() {
        browseStack.removeAll()
        Task { await refreshPhotos() }
    }

    // MARK: - 废片篓批量

    /// 全部恢复：把废片篓里的照片移出废片篓。
    func restoreAllTrashed() {
        guard let databaseQueue else { return }
        Task {
            do {
                try await Task.detached(priority: .userInitiated) {
                    try PhotoAssetRepository(databaseQueue: databaseQueue).restoreAllTrashed()
                }.value
                await refreshPhotos()
            } catch {
                lastErrorMessage = error.localizedDescription
            }
        }
    }

    /// 清空废片篓：系统源走 PhotoKit 批量删除、本地源进系统废纸篓，并标记已删除。
    func emptyTrash() {
        guard let databaseQueue else { return }
        Task {
            do {
                let locators = try await Task.detached(priority: .userInitiated) {
                    try PhotoAssetRepository(databaseQueue: databaseQueue).trashedLocators()
                }.value
                guard !locators.isEmpty else { return }

                let systemIDs = locators
                    .filter { $0.sourceID == PhotoAsset.systemPhotosSourceID }
                    .map(\.localIdentifier)
                if !systemIDs.isEmpty {
                    try await PhotoLibraryAdapter().deleteAssets(localIdentifiers: systemIDs)
                }
                for locator in locators where locator.sourceID != PhotoAsset.systemPhotosSourceID {
                    if let url = PhotoSourceRegistry.shared.fileURL(
                        forSourceID: locator.sourceID,
                        relativePath: locator.relativePath ?? locator.localIdentifier
                    ) {
                        try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
                    }
                }
                try await Task.detached(priority: .userInitiated) {
                    try PhotoAssetRepository(databaseQueue: databaseQueue).markSystemDeleted(photoIDs: locators.map(\.id))
                }.value
                await refreshPhotos()
            } catch {
                lastErrorMessage = error.localizedDescription
            }
        }
    }

    /// 高频标签（供 Find 标签筛选展示）。`limit` 传 -1 表示取全量（用于「更多」展开）。
    func topTags(limit: Int = -1) async -> [PhotoTagOption] {
        guard let databaseQueue else { return [] }
        let repository = AnalysisDataRepository(databaseQueue: databaseQueue)
        return (try? await Task.detached(priority: .userInitiated) {
            try repository.topTags(limit: limit)
        }.value) ?? []
    }

    /// 高频地点 / 城市（供 Find 地点筛选展示）。`limit` 传 -1 表示取全量（用于「更多」展开）。
    func topLocations(limit: Int = -1) async -> [PhotoLocationOption] {
        guard let databaseQueue else { return [] }
        let repository = AnalysisDataRepository(databaseQueue: databaseQueue)
        return (try? await Task.detached(priority: .userInitiated) {
            try repository.topLocalities(limit: limit)
        }.value) ?? []
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

        let asset = selectedPhotoForViewer.asset
        let photoID = selectedPhotoForViewer.id
        Task { [databaseQueue] in
            do {
                // 仅系统图库写回系统收藏；本地 / 外部源仅更新 App 内收藏状态。
                if asset.isSystemPhotos {
                    try await PhotoLibraryAdapter().setFavorite(
                        localIdentifier: asset.localIdentifier,
                        isFavorite: nextValue
                    )
                }
                try PhotoAssetRepository(databaseQueue: databaseQueue).updateFavorite(
                    photoID: photoID,
                    isFavorite: nextValue
                )
                await refreshPhotos()
                reconcileViewerSelection(previousID: photoID, previousIndex: currentIndex)
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

        let asset = selectedPhotoForViewer.asset
        let photoID = selectedPhotoForViewer.id
        Task { [databaseQueue] in
            do {
                if asset.isSystemPhotos {
                    try await PhotoLibraryAdapter().deleteAsset(localIdentifier: asset.localIdentifier)
                } else if let url = PhotoSourceRegistry.shared.fileURL(for: asset) {
                    // 本地 / 外部源：移入「废纸篓」（可恢复），不做硬删除。
                    try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                }
                try PhotoAssetRepository(databaseQueue: databaseQueue).markSystemDeleted(photoID: photoID)
                await refreshPhotos()
                reconcileViewerSelection(previousID: photoID, previousIndex: currentIndex)
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

/// 查看器额外详情（P2：地名 / 标签 / RAW）。
public struct PhotoExtraDetail: Sendable, Equatable {
    public var place: PhotoPlace?
    public var tags: [String]
    public var isRaw: Bool

    public static let empty = PhotoExtraDetail(place: nil, tags: [], isRaw: false)
}

/// 浏览上下文快照（"返回上一次位置"的核心抽象）。
///
/// 进入「相似照片」「废片篓」等具有独立结果集的特殊相册前，把当前的
/// 筛选条件、结果集、计数、模式、查看器照片、滚动锚点整体打个快照推入栈中；
/// 点击「返回」时弹出栈顶并原样还原——相当于把这些特殊相册当成「带前置筛选条件
/// 的临时相册」，离开时回到进入前那一帧。
///
/// 未来新增「智能筛选相册」「相册详情」等同类页面时，复用同一套
/// `pushBrowseContext` / `goBack` 即可获得一致的返回体验，无需各自实现。
public struct BrowseContext: Sendable {
    var filter: SearchFilterState
    var isTrashViewActive: Bool
    var isSimilarMode: Bool
    var results: [PhotoSearchResult]
    var matchedCount: Int
    /// 进入特殊相册前，查看器中正在查看的照片 ID（若有）；返回时重新打开该照片的详情。
    var viewerPhotoID: String?
    /// 返回后照片墙应滚动回到的照片 ID（若有）；用于恢复"上一次定位"。
    var anchorPhotoID: String?
}

import Foundation
import GRDB
import Observation
import SwiftUI

/// 组合根（Composition Root）。
///
/// 原 `AppState` 是承担导航、照片库、AI 分析、查看器等一切职责的 God Object。
/// 现拆分为三个职责单一的对象，`AppState` 只负责 bootstrap、设置持久化，
/// 以及把数据库连接注入到子对象。视图通过 `appState.navigation` /
/// `appState.library` / `appState.analysis` 访问各自领域的状态。
@MainActor
@Observable
final class AppState {
    let navigation = NavigationState()
    let library = PhotoLibraryViewModel()
    let analysis = AnalysisViewModel()
    let tasks = TaskCenter()

    private(set) var bootstrapStatus = BootstrapStatus.notStarted

    @ObservationIgnored let databaseURL: URL
    @ObservationIgnored private let bootstrapper = AppBootstrapper()
    @ObservationIgnored private var databaseQueue: DatabaseQueue?

    init(databaseURL: URL = AppPaths.defaultDatabaseURL) {
        self.databaseURL = databaseURL
    }

    func bootstrapIfNeeded() async {
        guard bootstrapStatus == .notStarted else { return }
        bootstrapStatus = .running

        do {
            let queue = try await bootstrapper.bootstrap(databaseURL: databaseURL)
            databaseQueue = queue
            VectorIndexEnvironment.probe(queue)
            // M1：向量存储格式升级（cosine + L2 归一化）时一次性清空旧向量，
            // 由开机自启的向量索引任务用新格式重建。
            try? AnalysisDataRepository(databaseQueue: queue).migrateVectorFormatIfNeeded()
            // #4：标签格式升级（阈值 + 本地化）→ 清理旧标签数据并触发重跑（地点标签无网络回填）。
            try? AnalysisDataRepository(databaseQueue: queue).migrateTagFormatIfNeeded()
            library.attach(databaseQueue: queue)
            analysis.attach(databaseQueue: queue, library: library)
            try loadSettings()
            tasks.attach(databaseQueue: queue, library: library, analysis: analysis)
            tasks.localeIdentifier = navigation.appLanguage.locale.identifier
            // 先让界面可交互；其后的 await 都把书签解析 / 可用性探测放后台，不阻塞主线程 run loop
            // （外置卷弹出后，主线程同步解析安全作用域书签会长时间阻塞，曾导致主界面卡死）。
            bootstrapStatus = .ready
            await registerPersistedCustomVectorModel(databaseQueue: queue)
            // 加载并注册所有照片源（系统 + 本地），后台解析书签 + 判定可用性，只注册可访问源。
            await library.loadAndRegisterSources()
            tasks.vectorModelKey = navigation.vectorModelKey
            // 分析任务只对当前可访问源排队 / 计数（不可访问源不进入队列，避免状态异常）。
            tasks.accessibleSourceIDs = library.accessibleSourceIDs
            // 仅展示当前可访问源的内容。
            await library.refreshPhotos()
            // 启动即自动加载所有可访问源（系统图库 + 本地目录），无需手动点击导入。
            library.startAccessibleSourceImports()
            tasks.startAllPending()
            // 异步检查磁盘缩略图缓存占用，超限时按 LRU 清理（不阻塞首屏）。
            enforceThumbnailCacheLimitIfNeeded()
        } catch {
            bootstrapStatus = .failed(error.localizedDescription)
        }
    }

    /// 视图层广泛使用的本地化便捷入口，转发到 `navigation`。
    func localized(_ key: String) -> String {
        navigation.localized(key)
    }

    // MARK: - 自定义向量模型（本地 MLX 模型目录）

    /// 导入并切换到一个本地 MLX 模型目录：校验文件 → 持久化书签 → 注册 → 切换 → 索引。
    func configureCustomVectorModel(directoryURL: URL) {
        guard let databaseQueue else { return }
        _ = directoryURL.startAccessingSecurityScopedResource()

        if let missing = Self.missingModelFiles(directoryURL: directoryURL), !missing.isEmpty {
            library.reportError(CustomModelImportError.missingFiles(missing))
            return
        }
        do {
            let bookmark = try directoryURL.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            let config = CustomVectorModelConfig(
                key: "custom.mlx.\(directoryURL.lastPathComponent)",
                displayName: directoryURL.lastPathComponent,
                dimension: Self.readModelDimension(directoryURL: directoryURL) ?? 1024,
                supportsTextQuery: true,
                path: directoryURL.path,
                bookmark: bookmark
            )
            EmbeddingProviderRegistry.registerCustom(config: config, resolvedURL: directoryURL)
            try AppSettingsRepository(databaseQueue: databaseQueue).saveCustomVectorModel(config)
            navigation.vectorModelKey = config.key
            tasks.vectorModelKey = config.key
            saveSettings()
            tasks.start(.vectorIndex)
        } catch {
            library.reportError(error)
        }
    }

    /// 重建当前模型的向量索引：清空旧向量后重新索引。
    func rebuildVectorIndex() {
        guard let databaseQueue else { return }
        let key = navigation.vectorModelKey
        tasks.stop(.vectorIndex)
        Task {
            try? await Task.detached(priority: .utility) {
                try AnalysisDataRepository(databaseQueue: databaseQueue).clearSpace(spaceKey: key)
            }.value
            tasks.start(.vectorIndex)
            tasks.refreshCompletion()
        }
    }

    /// 删除自定义模型：清空其向量、注销、移除持久化，切回默认模型。
    func removeCustomVectorModel() {
        guard let databaseQueue,
              let descriptor = EmbeddingProviderRegistry.customDescriptor() else { return }
        let key = descriptor.key
        tasks.stop(.vectorIndex)
        Task {
            try? await Task.detached(priority: .utility) {
                try AnalysisDataRepository(databaseQueue: databaseQueue).clearSpace(spaceKey: key)
            }.value
            EmbeddingProviderRegistry.registerCustom(config: nil, resolvedURL: nil)
            try? AppSettingsRepository(databaseQueue: databaseQueue).saveCustomVectorModel(nil)
            navigation.vectorModelKey = EmbeddingProviderRegistry.defaultKey
            tasks.vectorModelKey = EmbeddingProviderRegistry.defaultKey
            saveSettings()
            tasks.start(.vectorIndex)
            tasks.refreshCompletion()
        }
    }

    /// 校验模型目录：需有 config.json + 至少一个权重文件；返回缺失项（nil 表示通过）。
    private static func missingModelFiles(directoryURL: URL) -> [String]? {
        let fileManager = FileManager.default
        let contents = (try? fileManager.contentsOfDirectory(atPath: directoryURL.path)) ?? []
        guard !contents.isEmpty else { return ["config.json", "模型权重文件"] }

        var missing: [String] = []
        if !contents.contains("config.json") {
            missing.append("config.json")
        }
        let weightExtensions = ["safetensors", "npz", "bin", "gguf", "mlx", "pt", "weights"]
        let hasWeights = contents.contains { name in
            weightExtensions.contains((name as NSString).pathExtension.lowercased())
        }
        if !hasWeights {
            missing.append("模型权重文件（.safetensors/.npz/.bin 等）")
        }
        return missing
    }

    /// 注册持久化的自定义向量模型目录。书签解析放后台并做路径可达性门：
    /// 模型目录在已弹出的外置卷上时，主线程同步 `resolvingBookmarkData` 会长时间阻塞 → 卡死。
    private func registerPersistedCustomVectorModel(databaseQueue: DatabaseQueue) async {
        guard let config = try? AppSettingsRepository(databaseQueue: databaseQueue).loadCustomVectorModel() else { return }
        let resolved = await Task.detached(priority: .userInitiated) { () -> URL? in
            // 快速门：路径不可达（卷已弹出 / 目录被删）→ 跳过会阻塞的书签解析。
            if !config.path.isEmpty, !FileManager.default.fileExists(atPath: config.path) { return nil }
            var isStale = false
            guard let url = try? URL(
                resolvingBookmarkData: config.bookmark,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ), url.startAccessingSecurityScopedResource() else { return nil }
            return url
        }.value
        guard let resolved else { return }
        EmbeddingProviderRegistry.registerCustom(config: config, resolvedURL: resolved)
    }

    /// 尝试从模型目录 config.json 读取向量维度。
    private static func readModelDimension(directoryURL: URL) -> Int? {
        let configURL = directoryURL.appending(path: "config.json")
        guard let data = try? Data(contentsOf: configURL),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        for key in ["embedding_dim", "hidden_size", "dim", "projection_dim"] {
            if let value = object[key] as? Int { return value }
        }
        return nil
    }

    // MARK: - 设置持久化

    func saveSettings() {
        guard let databaseQueue else { return }
        do {
            try AppSettingsRepository(databaseQueue: databaseQueue).save(
                AppSettingsSnapshot(
                    themeMode: navigation.themeMode,
                    appLanguage: navigation.appLanguage,
                    gridLevel: navigation.gridLevel,
                    badgeMetric: navigation.badgeMetric,
                    vectorModelKey: navigation.vectorModelKey,
                    sidebarShownOnLaunch: navigation.sidebarShownOnLaunch,
                    thumbnailCacheLimitBytes: navigation.thumbnailCacheLimitBytes,
                    thumbnailCacheAutoCleanEnabled: navigation.thumbnailCacheAutoCleanEnabled
                )
            )
        } catch {
            library.reportError(error)
        }
    }

    private func loadSettings() throws {
        guard let databaseQueue else { return }
        let snapshot = try AppSettingsRepository(databaseQueue: databaseQueue).load()
        navigation.themeMode = snapshot.themeMode
        navigation.appLanguage = snapshot.appLanguage
        navigation.gridLevel = snapshot.gridLevel
        navigation.badgeMetric = snapshot.badgeMetric
        navigation.vectorModelKey = snapshot.vectorModelKey
        navigation.sidebarShownOnLaunch = snapshot.sidebarShownOnLaunch
        navigation.thumbnailCacheLimitBytes = snapshot.thumbnailCacheLimitBytes
        navigation.thumbnailCacheAutoCleanEnabled = snapshot.thumbnailCacheAutoCleanEnabled
        // 侧栏的初始展开状态由「启动时显示」设置决定；之后用户随时可手动展开/折叠，
        // 不会回写到这个设置项（设置项只代表「下次启动时」的默认值）。
        navigation.isSidebarExpanded = snapshot.sidebarShownOnLaunch
    }

    // MARK: - 缩略图磁盘缓存

    /// App 启动后异步检查一次磁盘缩略图缓存占用，超出设置上限且开启「自动清理」时
    /// 按 LRU 清理到上限的 90%。不阻塞首屏（在 `bootstrapIfNeeded` 末尾发起）。
    func enforceThumbnailCacheLimitIfNeeded() {
        guard navigation.thumbnailCacheAutoCleanEnabled else { return }
        let limit = navigation.thumbnailCacheLimitBytes
        guard limit > 0 else { return }
        Task.detached(priority: .background) {
            await DiskThumbnailCache.shared.enforceLimit(limit)
        }
    }

    /// 「立即清理」：清空磁盘缩略图缓存 + L1 内存缓存。
    func clearThumbnailCache() {
        LocalThumbnailProvider.shared.clearMemoryCache()
        Task.detached(priority: .utility) {
            await DiskThumbnailCache.shared.clearAll()
        }
    }

    /// 当前磁盘缩略图缓存占用（字节），供设置页展示；异步计算，不阻塞主线程。
    func thumbnailCacheUsageBytes() async -> Int64 {
        await DiskThumbnailCache.shared.currentUsageBytes()
    }
}

enum CustomModelImportError: Error, LocalizedError {
    case missingFiles([String])

    var errorDescription: String? {
        switch self {
        case .missingFiles(let files):
            "模型目录校验失败，缺少：\(files.joined(separator: "、"))"
        }
    }
}

enum BootstrapStatus: Equatable {
    case notStarted
    case running
    case ready
    case failed(String)
}

enum AppRoute: String, CaseIterable, Identifiable {
    case photos
    case timeline
    case reports
    case settings

    var id: String { rawValue }

    var titleKey: LocalizedStringKey {
        switch self {
        case .photos: "Photos"
        case .reports: "Reports"
        case .timeline: "Timeline"
        case .settings: "Settings"
        }
    }

    var localizationKey: String {
        switch self {
        case .photos: "Photos"
        case .reports: "Reports"
        case .timeline: "Timeline"
        case .settings: "Settings"
        }
    }

    var iconName: String {
        switch self {
        case .photos: "photo.on.rectangle"
        case .timeline: "clock"
        case .reports: "doc.text"
        case .settings: "gearshape"
        }
    }
}

enum ThemeMode: String, CaseIterable, Codable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    var displayName: LocalizedStringKey {
        switch self {
        case .system: "Theme System"
        case .light: "Theme Light"
        case .dark: "Theme Dark"
        }
    }

    var localizationKey: String {
        switch self {
        case .system: "Theme System"
        case .light: "Theme Light"
        case .dark: "Theme Dark"
        }
    }

    var nextMode: ThemeMode {
        switch self {
        case .system: .light
        case .light: .dark
        case .dark: .system
        }
    }

    var iconName: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max"
        case .dark: "moon"
        }
    }
}

enum AppLanguage: String, CaseIterable, Codable, Identifiable {
    case system
    case zhHans = "zh-Hans"
    case en

    var id: String { rawValue }

    var displayName: LocalizedStringKey {
        switch self {
        case .system: "Language System"
        case .zhHans: "Language zh-Hans"
        case .en: "Language en"
        }
    }

    var localizationKey: String {
        switch self {
        case .system: "Language System"
        case .zhHans: "Language zh-Hans"
        case .en: "Language en"
        }
    }

    /// 各语言以「母语名」展示（语言选择器惯例）：简体中文 / English。
    /// 系统项保持可本地化（跟随系统 / Follow System）。
    var nativeName: String? {
        switch self {
        case .system: nil
        case .zhHans: "简体中文"
        case .en: "English"
        }
    }

    var locale: Locale {
        switch self {
        case .system:
            .autoupdatingCurrent
        case .zhHans:
            Locale(identifier: "zh-Hans")
        case .en:
            Locale(identifier: "en")
        }
    }
}

enum BadgeMetric: String, CaseIterable, Codable, Identifiable {
    case aesthetic
    case overall
    case hidden

    var id: String { rawValue }

    var displayName: LocalizedStringKey {
        switch self {
        case .aesthetic: "Badge Aesthetic"
        case .overall: "Badge Overall"
        case .hidden: "Badge Hidden"
        }
    }

    var localizationKey: String {
        switch self {
        case .aesthetic: "Badge Aesthetic"
        case .overall: "Badge Overall"
        case .hidden: "Badge Hidden"
        }
    }
}

enum GridLevel: Int, CaseIterable, Codable, Identifiable {
    case columns1 = 1
    case columns3 = 3
    case columns5 = 5
    case columns7 = 7
    case columns9 = 9
    case columns15 = 15
    case columns27 = 27

    /// 默认档位（7 档里偏中间）。
    static let `default` = GridLevel.columns5

    var id: Int { rawValue }

    var displayName: LocalizedStringKey {
        "Grid Level \(rawValue)"
    }

    var localizationKey: String {
        "Grid Level %lld"
    }

    var columnCount: Int { rawValue }
}

public enum AnalysisStatus: String, Equatable, Sendable {
    case idle
    case running
    case paused
    case stopping
    case completed
    case cancelled
    case failed
}

public struct AnalysisProgress: Equatable, Sendable {
    public var status: AnalysisStatus
    public var completed: Int
    public var failed: Int
    public var total: Int
    public var currentRunID: String?

    public var isRunning: Bool {
        status == .running || status == .paused || status == .stopping
    }

    public static let idle = AnalysisProgress(status: .idle, completed: 0, failed: 0, total: 0, currentRunID: nil)
}

enum AppPaths {
    static var applicationSupportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appending(path: "MantaPhotos", directoryHint: .isDirectory)
    }

    static var defaultDatabaseURL: URL {
        applicationSupportDirectory.appending(path: "photos.db")
    }
}

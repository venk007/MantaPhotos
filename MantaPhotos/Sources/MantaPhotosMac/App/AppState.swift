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
            library.attach(databaseQueue: queue)
            analysis.attach(databaseQueue: queue, library: library)
            try loadSettings()
            bootstrapStatus = .ready
            await library.refreshPhotos()
            library.startInitialImportIfPossible()
        } catch {
            bootstrapStatus = .failed(error.localizedDescription)
        }
    }

    /// 视图层广泛使用的本地化便捷入口，转发到 `navigation`。
    func localized(_ key: String) -> String {
        navigation.localized(key)
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
                    badgeMetric: navigation.badgeMetric
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
    case columns2 = 2
    case columns4 = 4
    case columns6 = 6
    case columns8 = 8
    case columns12 = 12
    case columns16 = 16
    case columns32 = 32

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

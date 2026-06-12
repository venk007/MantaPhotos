import AppKit
import SwiftUI

struct AppShellView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                TopBarView()
                Divider()
                ZStack(alignment: .leading) {
                    routeView
                    if appState.navigation.route == .photos {
                        SidebarOverlayView()
                            .transition(.move(edge: .leading).combined(with: .opacity))
                    }
                }
                // 内容区始终撑满：否则像 Timeline/Reports/Settings 这类非贪婪内容会让整个
                // VStack 在外层 ZStack 里垂直居中，顶部标签栏上方出现大块空白。
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                BottomBarView()
            }

            if !appState.navigation.isFindOverlayPresented {
                VStack(spacing: 0) {
                    Spacer()
                    LiquidGlassDock()
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(8)
            }

            if appState.navigation.isFindOverlayPresented {
                FindOverlayView()
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    .zIndex(10)
            }

            if case .failed(let message) = appState.bootstrapStatus {
                VStack {
                    Spacer()
                    Text(message)
                        .font(.footnote)
                        .padding(DesignSystem.Spacing.md)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: DesignSystem.Radius.panel))
                        .padding()
                }
                .zIndex(20)
            }
        }
        .animation(.snappy(duration: 0.18), value: appState.navigation.isFindOverlayPresented)
        .animation(.snappy(duration: 0.2), value: appState.navigation.route)
        .background(AppKeyboardShortcutView().environment(appState).frame(width: 0, height: 0))
        .onChange(of: appState.navigation.route) { _, route in
            if route != .photos {
                appState.navigation.isSidebarExpanded = false
                appState.library.closeViewer()
            } else {
                appState.navigation.isSidebarExpanded = true
            }
        }
    }

    @ViewBuilder
    private var routeView: some View {
        switch appState.navigation.route {
        case .photos:
            PhotosPageView()
        case .reports:
            ReportsPageView()
        case .timeline:
            TimelinePlaceholderView()
        case .settings:
            SettingsPageView()
        }
    }
}

struct AppKeyboardShortcutView: NSViewRepresentable {
    @Environment(AppState.self) private var appState

    func makeCoordinator() -> Coordinator {
        Coordinator(appState: appState)
    }

    func makeNSView(context: Context) -> NSView {
        context.coordinator.start(appState: appState)
        return NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.appState = appState
        context.coordinator.start(appState: appState)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.stop()
    }

    final class Coordinator {
        weak var appState: AppState?
        private var monitor: Any?

        init(appState: AppState) {
            self.appState = appState
        }

        func start(appState: AppState) {
            self.appState = appState
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, let appState = self.appState else { return event }
                let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                let key = event.charactersIgnoringModifiers?.lowercased()

                if modifiers.contains(.command), key == "k" {
                    MainActor.assumeIsolated {
                        appState.navigation.isFindOverlayPresented.toggle()
                    }
                    return nil
                }

                if event.keyCode == 53, MainActor.assumeIsolated({
                    guard appState.navigation.isFindOverlayPresented else { return false }
                    appState.navigation.isFindOverlayPresented = false
                    return true
                }) {
                    return nil
                }

                // Tab：在照片页（且无浮层/无文本框聚焦）切换左侧抽屉。
                if event.keyCode == 48, modifiers.isEmpty, MainActor.assumeIsolated({
                    guard appState.navigation.route == .photos,
                          !appState.navigation.isFindOverlayPresented,
                          !(appState.library.isViewerPresented),
                          !(NSApp.keyWindow?.firstResponder is NSTextView) else { return false }
                    appState.navigation.isSidebarExpanded.toggle()
                    return true
                }) {
                    return nil
                }

                return event
            }
        }

        func stop() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        deinit {
            stop()
        }
    }
}

struct TopBarView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        HStack(spacing: 18) {
            HStack(spacing: 12) {
                if appState.navigation.route == .photos {
                    sidebarToggleButton
                }
                logoButton
                navTabs
            }
            .layoutPriority(1)

            Spacer(minLength: 0)
            trailingControls
        }
        .padding(.horizontal, DesignSystem.Spacing.lg)
        .frame(height: DesignSystem.Metrics.topBarHeight)
    }

    /// macOS 原生风格的侧栏开关（SF Symbol），等价于 Tab 键。
    private var sidebarToggleButton: some View {
        Button {
            appState.navigation.isSidebarExpanded.toggle()
        } label: {
            Image(systemName: "sidebar.leading")
                .font(.body)
                .symbolVariant(appState.navigation.isSidebarExpanded ? .fill : .none)
        }
        .buttonStyle(.borderless)
        .help("显示 / 隐藏侧栏（Tab）")
    }

    private var logoButton: some View {
        Button {
            appState.navigation.route = .photos
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "camera")
                Text(appState.localized("MantaPhotos"))
                    .font(.headline.weight(.semibold))
            }
        }
        .buttonStyle(.plain)
    }

    private var navTabs: some View {
        HStack(spacing: 4) {
            ForEach(AppRoute.allCases) { route in
                topTab(route)
            }
        }
    }

    private var trailingControls: some View {
        HStack(spacing: 12) {
            MultiTaskStatusView()

            Button {
                appState.navigation.themeMode = appState.navigation.themeMode.nextMode
            } label: {
                Image(systemName: appState.navigation.themeMode.iconName)
            }
            .buttonStyle(.borderless)
            .help("Theme")

            Button {} label: {
                Image(systemName: "bell")
            }
            .buttonStyle(.borderless)
            .disabled(true)
            .help("Notifications")
        }
    }

    private func topTab(_ route: AppRoute) -> some View {
        Button {
            appState.navigation.route = route
        } label: {
            Label(appState.localized(route.localizationKey), systemImage: route.iconName)
                .labelStyle(.titleAndIcon)
                .font(.callout.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .foregroundStyle(appState.navigation.route == route ? .primary : .secondary)
                .background {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(appState.navigation.route == route ? AnyShapeStyle(.regularMaterial) : AnyShapeStyle(.clear))
                }
        }
        .buttonStyle(.plain)
    }
}

struct SidebarOverlayView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        HStack(spacing: 0) {
            SidebarView()
                .frame(width: DesignSystem.Metrics.sidebarWidth)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: DesignSystem.Radius.overlay))
                .shadow(color: .black.opacity(0.16), radius: 18, x: 0, y: 10)
                .offset(x: appState.navigation.isSidebarExpanded ? 0 : -DesignSystem.Metrics.sidebarWidth - 32)
            Spacer(minLength: 0)
        }
        .padding(.leading, 16)
        .animation(.snappy(duration: 0.24), value: appState.navigation.isSidebarExpanded)
        .allowsHitTesting(appState.navigation.isSidebarExpanded)
        .zIndex(5)
    }
}

/// iOS / visionOS 风格的底部悬浮液态玻璃导航坞。
///
/// 居中胶囊承载四个分区的快速跳转，active 分区展开标题；
/// 右侧是一枚独立的圆形 🔍 玻璃按钮，打开 Find 浮层（与 ⌘K 等价）。
/// 悬浮在内容之上，照片网格已为其预留底部留白。
struct LiquidGlassDock: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 4) {
                ForEach(AppRoute.allCases) { route in
                    dockTab(route)
                }
            }
            .padding(6)
            .glassEffect(.regular, in: Capsule())
            .shadow(color: .black.opacity(0.18), radius: 16, x: 0, y: 8)

            Button {
                appState.navigation.isFindOverlayPresented = true
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 46, height: 46)
                    .glassEffect(.regular, in: Circle())
            }
            .buttonStyle(.plain)
            .shadow(color: .black.opacity(0.18), radius: 16, x: 0, y: 8)
            .help(appState.localized("Search photos"))
        }
        .padding(.bottom, DesignSystem.Metrics.bottomBarHeight + DesignSystem.Spacing.md)
        .animation(.snappy(duration: 0.2), value: appState.navigation.route)
    }

    private func dockTab(_ route: AppRoute) -> some View {
        let active = appState.navigation.route == route
        return Button {
            appState.navigation.route = route
        } label: {
            HStack(spacing: 7) {
                Image(systemName: route.iconName)
                if active {
                    Text(appState.localized(route.localizationKey))
                        .lineLimit(1)
                }
            }
            .font(.callout.weight(.medium))
            .padding(.horizontal, active ? 15 : 12)
            .padding(.vertical, 9)
            .foregroundStyle(active ? .white : .secondary)
            .background {
                if active {
                    Capsule().fill(DesignSystem.Glass.activeTint)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(appState.localized(route.localizationKey))
    }
}

struct BottomBarView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        HStack {
            Text(statusText)
                .foregroundStyle(.secondary)
            Spacer()
            Text(gridStatusText)
                .foregroundStyle(.secondary)
        }
        .font(.footnote)
        .padding(.horizontal, DesignSystem.Spacing.lg)
        .frame(height: DesignSystem.Metrics.bottomBarHeight)
    }

    private var statusText: String {
        switch appState.library.importProgress.phase {
        case .initialImport, .backgroundImport:
            "\(localizedImportMessage) \(appState.library.importProgress.imported)/\(appState.library.importProgress.total)"
        case .completed:
            appState.library.searchFilter.isEmpty ? appState.localized("Import complete") : appState.localized("Filters active")
        case .denied:
            appState.localized("Photos access needed")
        case .failed:
            localizedImportMessage
        default:
            appState.library.searchFilter.isEmpty ? appState.localized("No filters") : appState.localized("Filters active")
        }
    }

    private var gridStatusText: String {
        switch appState.navigation.appLanguage {
        case .zhHans:
            "网格 \(appState.navigation.gridLevel.rawValue) · \(appState.library.matchedPhotoCount.formatted()) 个匹配"
        case .system where Locale.preferredLanguages.first?.hasPrefix("zh") == true:
            "网格 \(appState.navigation.gridLevel.rawValue) · \(appState.library.matchedPhotoCount.formatted()) 个匹配"
        default:
            "Grid \(appState.navigation.gridLevel.rawValue) · \(appState.library.matchedPhotoCount.formatted()) matched"
        }
    }

    private var localizedImportMessage: String {
        switch appState.library.importProgress.message {
        case "Requesting Photos access":
            return appState.localized("Requesting Photos access")
        case "Photos access is not authorized":
            return appState.localized("Photos access is not authorized")
        case "Import completed":
            return appState.localized("Import complete")
        case "Preparing recent photos":
            return appState.localized("Preparing recent photos")
        case "Importing library in background":
            return appState.localized("Importing library in background")
        default:
            return appState.library.importProgress.message
        }
    }
}

struct AnalysisProgressView: View {
    @Environment(AppState.self) private var appState
    var progress: AnalysisProgress

    var body: some View {
        if progress.isRunning {
            HStack(spacing: 8) {
                ProgressView(value: Double(progress.completed), total: Double(max(progress.total, 1))) {
                    Text(progress.status.displayName)
                }
                .frame(width: 170)

                Text(progressText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 116, alignment: .trailing)

                if progress.status == .paused {
                    Button {
                        appState.analysis.resumeAnalysis()
                    } label: {
                        Image(systemName: "play.fill")
                    }
                    .help("Resume scoring")
                } else {
                    Button {
                        appState.analysis.pauseAnalysis()
                    } label: {
                        Image(systemName: "pause.fill")
                    }
                    .help("Pause scoring")
                    .disabled(progress.status == .stopping)
                }

                Button {
                    appState.analysis.stopAnalysis()
                } label: {
                    Image(systemName: "stop.fill")
                }
                .help("Stop scoring")
                .disabled(progress.status == .stopping)
            }
            .buttonStyle(.borderless)
        } else if progress.failed > 0, progress.currentRunID != nil {
            HStack(spacing: 8) {
                Label("Failed \(progress.failed)", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button {
                    appState.analysis.retryFailedAnalysis()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Retry failed scoring tasks")
            }
            .buttonStyle(.borderless)
        }
    }

    private var progressText: String {
        if progress.failed > 0 {
            return "\(progress.completed)/\(progress.total) · \(progress.failed) failed"
        }
        return "\(progress.completed)/\(progress.total)"
    }
}

private extension AnalysisStatus {
    var displayName: LocalizedStringKey {
        switch self {
        case .idle:
            "Idle"
        case .running:
            "Scoring"
        case .paused:
            "Paused"
        case .stopping:
            "Stopping"
        case .completed:
            "Completed"
        case .cancelled:
            "Cancelled"
        case .failed:
            "Failed"
        }
    }
}

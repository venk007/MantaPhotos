import AppKit
import SwiftUI

struct AppShellView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                ZStack(alignment: .leading) {
                    routeView
                    if appState.navigation.route == .photos {
                        SidebarOverlayView()
                            .transition(.move(edge: .leading).combined(with: .opacity))
                    }
                }
                // 内容区始终撑满：否则像 Timeline/Reports/Settings 这类非贪婪内容会让整个
                // VStack 在外层 ZStack 里垂直居中，顶部标签栏上方出现大块空白。
                //
                // 顶部菜单栏/标题栏已彻底移除（macOS 26 设计哲学），内容区从窗口最
                // 顶端（红绿灯所在行）开始延伸；`TopChromeOverlay` 以悬浮玻璃按钮
                // 形式叠加在上方，不再占用独立一行。
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                BottomBarView()
            }

            TopChromeOverlay()
                .zIndex(6)

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

            // 照片查看器：占据整个应用页面（而非系统 sheet），与系统照片 App 的
            // 「双击照片 → 全屏详情，点返回回到照片墙」体验一致。淡入 + 轻微放大
            // 进场、退场同一组动画反向播放，流畅但不拖沓。
            if appState.library.isViewerPresented, let viewerResult = appState.library.selectedPhotoForViewer {
                PhotoViewerView(result: viewerResult)
                    .environment(appState)
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
                    .zIndex(15)
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
        .animation(.snappy(duration: 0.22), value: appState.library.isViewerPresented)
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

/// 顶部「无菜单栏」chrome：替代原 `TopBarView`。
///
/// macOS 26 设计哲学下，标题栏/菜单栏背板已彻底移除（见
/// `MantaPhotosApp.windowStyle(.hiddenTitleBar)`），内容延伸到窗口最顶端，
/// 仅保留系统红绿灯三个按钮。本视图只悬浮两枚独立的液态玻璃按钮：
/// - 左侧：抽屉开关（红绿灯右侧），等价于 Tab 键，仅照片页显示；
/// - 右侧：分析任务状态——`MultiTaskStatusView` 仅在有任务运行时才渲染
///   自己（否则是 `EmptyView`），因此「无任务时顶部只有左侧一枚按钮」。
///
/// 原 `TopBarView` 中的 Logo / 路由 Tab 已由底部 `LiquidGlassDock` 承担同等
/// 导航功能；通知按钮（本就 `.disabled(true)` 且无实际功能）与主题切换按钮
/// （已迁移到设置页「外观」的三态分段控件）一并彻底移除。
struct TopChromeOverlay: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if appState.navigation.route == .photos {
                    drawerToggleButton
                }
                Spacer(minLength: 0)
                MultiTaskStatusView()
            }
            .padding(.leading, appState.navigation.route == .photos ? 80 : DesignSystem.Spacing.lg)
            .padding(.trailing, DesignSystem.Spacing.lg)
            .padding(.top, 10)

            Spacer(minLength: 0)
        }
        .allowsHitTesting(true)
    }

    /// 独立的液态玻璃抽屉开关：位于红绿灯三个按钮右侧，展开/收起左侧抽屉
    /// （等价于 Tab 键）。展开抽屉时本按钮与红绿灯一起浮在抽屉组件右上方。
    private var drawerToggleButton: some View {
        Button {
            appState.navigation.isSidebarExpanded.toggle()
        } label: {
            Image(systemName: "sidebar.leading")
                .font(.body)
                .symbolVariant(appState.navigation.isSidebarExpanded ? .fill : .none)
                .frame(width: 30, height: 30)
        }
        .buttonStyle(.pressableGlass)
        .liquidGlassBackground(material: .hudWindow, in: Circle())
        .glassHoverHighlight(in: Circle())
        .overlay {
            Circle().strokeBorder(DesignSystem.Glass.hairline, lineWidth: DesignSystem.Glass.hairlineWidth)
        }
        .shadow(color: .black.opacity(0.12), radius: 10, x: 0, y: 3)
        .help("显示 / 隐藏侧栏（Tab）")
    }
}

struct SidebarOverlayView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        // 不再用 `HStack + Spacer(minLength: 0)` 撑满整行：那会让 `.allowsHitTesting`
        // 作用域覆盖整个内容区（含右上角工具栏/缩放/评分维度/导入按钮等），
        // 抽屉展开时这片透明 Spacer 会拦截下层所有点击，导致按钮失效。
        // 直接让抽屉面板本身（固定宽度）参与 ZStack(alignment: .leading) 布局即可。
        //
        // 玻璃材质用 `liquidGlassBackground`（`.withinWindow` 的 `NSVisualEffectView`，
        // 而非 `.glassEffect` / `.regularMaterial` 的 `.behindWindow` 混合）：
        // `.behindWindow` 依赖 WindowServer 实时合成「窗口背后的桌面/其他 App
        // 内容」，抽屉随 `isSidebarExpanded` 插入/移除、以及应用切前台时这份
        // 跨进程合成尚未就绪，会先呈黑底再淡入玻璃效果。`.withinWindow` 只采样
        // 本窗口已渲染好的图层，无此延迟，视觉上同样是半透明液态玻璃。
        SidebarView()
            .frame(width: DesignSystem.Metrics.sidebarWidth)
            .liquidGlassBackground(material: .sidebar, in: RoundedRectangle(cornerRadius: DesignSystem.Radius.overlay))
            .overlay {
                RoundedRectangle(cornerRadius: DesignSystem.Radius.overlay)
                    .stroke(DesignSystem.Glass.hairline, lineWidth: DesignSystem.Glass.hairlineWidth)
            }
            .shadow(color: .black.opacity(0.16), radius: 18, x: 0, y: 10)
            // 顶部菜单栏已移除，内容区从窗口最顶端开始；这里补上与 `.leading`
            // 同量级的顶部边距，让抽屉顶端基本贴到窗口顶部、又留一点圆角边框
            // 与边界距离——展开时红绿灯与 `TopChromeOverlay` 的抽屉按钮正好
            // 浮在抽屉组件的左上 / 右上角上方。
            .padding(.leading, 16)
            .padding(.top, 16)
            .offset(x: appState.navigation.isSidebarExpanded ? 0 : -DesignSystem.Metrics.sidebarWidth - 32)
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
            .liquidGlassBackground(material: .hudWindow, in: Capsule())
            .shadow(color: .black.opacity(0.18), radius: 16, x: 0, y: 8)

            Button {
                appState.navigation.isFindOverlayPresented = true
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 46, height: 46)
                    .liquidGlassBackground(material: .hudWindow, in: Circle())
                    .glassHoverHighlight(in: Circle())
            }
            .buttonStyle(.pressableGlass)
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
            if route == .photos {
                appState.library.exitTrashView()
            }
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
            .glassHoverHighlight(in: Capsule())
        }
        .buttonStyle(.pressableGlass)
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
        .frame(maxWidth: .infinity)
        // 半透明液态玻璃背板，替代旧版纯色/黑色背景，与抽屉、悬浮工具栏等
        // chrome 在材质语言上保持一致（同样的 `.hudWindow` + `.withinWindow`）。
        .liquidGlassBackground(material: .hudWindow, in: Rectangle())
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

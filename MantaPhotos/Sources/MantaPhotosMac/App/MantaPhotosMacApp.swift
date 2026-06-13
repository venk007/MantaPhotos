import SwiftUI

public struct MantaPhotosApp: App {
    @State private var appState = AppState()

    public init() {}

    public var body: some Scene {
        WindowGroup {
            AppShellView()
                .environment(appState)
                .environment(\.locale, appState.navigation.appLanguage.locale)
                .preferredColorScheme(appState.navigation.themeMode.colorScheme)
                .id(appState.navigation.appLanguage.rawValue)
                .frame(minWidth: 1120, minHeight: 720)
                .task {
                    await appState.bootstrapIfNeeded()
                }
                .onChange(of: appState.navigation.themeMode) {
                    appState.saveSettings()
                }
                .onChange(of: appState.navigation.appLanguage) {
                    appState.tasks.localeIdentifier = appState.navigation.appLanguage.locale.identifier
                    appState.saveSettings()
                }
                .onChange(of: appState.navigation.gridLevel) {
                    appState.saveSettings()
                }
                .onChange(of: appState.navigation.badgeMetric) {
                    appState.saveSettings()
                }
                .onChange(of: appState.navigation.sidebarShownOnLaunch) {
                    appState.saveSettings()
                }
        }
        // macOS 26 设计哲学：去掉标题栏/菜单栏背板，内容延伸到窗口顶部，
        // 仅保留红绿灯三个系统按钮；左右两侧的抽屉/任务状态按钮由
        // `TopChromeOverlay`（AppShellView.swift）以独立液态玻璃按钮呈现。
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .sidebar) {
                Button("Zoom In") {
                    appState.navigation.adjustGridLevel(step: -1)
                }
                .keyboardShortcut("+", modifiers: [.command])

                Button("Zoom Out") {
                    appState.navigation.adjustGridLevel(step: 1)
                }
                .keyboardShortcut("-", modifiers: [.command])
            }

            CommandMenu("MantaPhotos") {
                Button("Find") {
                    appState.navigation.isFindOverlayPresented.toggle()
                }
                .keyboardShortcut("k", modifiers: [.command])
            }
        }
    }
}

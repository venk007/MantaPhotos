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
                    appState.saveSettings()
                }
                .onChange(of: appState.navigation.gridLevel) {
                    appState.saveSettings()
                }
                .onChange(of: appState.navigation.badgeMetric) {
                    appState.saveSettings()
                }
        }
        .commands {
            CommandMenu("MantaPhotos") {
                Button("Find") {
                    appState.navigation.isFindOverlayPresented.toggle()
                }
                .keyboardShortcut("k", modifiers: [.command])
            }
        }
    }
}

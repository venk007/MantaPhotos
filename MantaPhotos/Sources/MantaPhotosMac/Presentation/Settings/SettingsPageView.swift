import SwiftUI

struct SettingsPageView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var navigation = appState.navigation
        Form {
            Picker(appState.localized("Theme"), selection: $navigation.themeMode) {
                ForEach(ThemeMode.allCases) { mode in
                    Text(appState.localized(mode.localizationKey)).tag(mode)
                }
            }

            Picker(appState.localized("Language"), selection: $navigation.appLanguage) {
                ForEach(AppLanguage.allCases) { language in
                    Text(appState.localized(language.localizationKey)).tag(language)
                }
            }

            Picker(appState.localized("Grid Level"), selection: $navigation.gridLevel) {
                ForEach(GridLevel.allCases) { level in
                    Text("\(appState.localized("Grid Level")) \(level.rawValue)").tag(level)
                }
            }

            Picker(appState.localized("Badge Metric"), selection: $navigation.badgeMetric) {
                ForEach(BadgeMetric.allCases) { metric in
                    Text(appState.localized(metric.localizationKey)).tag(metric)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

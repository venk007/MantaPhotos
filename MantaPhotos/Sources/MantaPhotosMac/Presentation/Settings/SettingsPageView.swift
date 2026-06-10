import AppKit
import SwiftUI

struct SettingsPageView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var navigation = appState.navigation
        Form {
            Section("外观") {
                Picker(appState.localized("Theme"), selection: $navigation.themeMode) {
                    ForEach(ThemeMode.allCases) { mode in
                        Text(appState.localized(mode.localizationKey)).tag(mode)
                    }
                }

                Picker(appState.localized("Language"), selection: $navigation.appLanguage) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.nativeName ?? appState.localized(language.localizationKey)).tag(language)
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

            Section("照片源") {
                ForEach(appState.library.sources) { source in
                    sourceRow(source)
                }

                Button {
                    addLocalDirectory()
                } label: {
                    Label("添加本地文件夹", systemImage: "folder.badge.plus")
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    @ViewBuilder
    private func sourceRow(_ source: PhotoSourceDescriptor) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon(for: source.kind))
                .foregroundStyle(.secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text(source.displayName)
                if let path = source.rootPath {
                    Text(path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer()

            if source.kind.isFileBased {
                Button {
                    appState.library.rescanSource(id: source.id)
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("重新扫描")

                Button(role: .destructive) {
                    appState.library.removeSource(id: source.id)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("移除该源及其照片")
            } else {
                Text("系统")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func icon(for kind: PhotoSourceKind) -> String {
        switch kind {
        case .systemPhotos: "photo.on.rectangle"
        case .localDirectory: "folder"
        case .externalLibrary: "externaldrive"
        }
    }

    private func addLocalDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "选择"
        panel.message = "选择一个包含照片 / 视频的文件夹"
        if panel.runModal() == .OK, let url = panel.url {
            appState.library.addLocalDirectory(url: url)
        }
    }
}

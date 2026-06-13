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

                Picker(appState.localized("Badge Metric"), selection: $navigation.badgeMetric) {
                    ForEach(BadgeMetric.allCases) { metric in
                        Text(appState.localized(metric.localizationKey)).tag(metric)
                    }
                }

                Toggle(appState.localized("Show Sidebar On Launch"), isOn: $navigation.sidebarShownOnLaunch)
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

            Section("向量模型") {
                Picker("当前模型", selection: $navigation.vectorModelKey) {
                    ForEach(EmbeddingProviderRegistry.allDescriptors) { descriptor in
                        Text(descriptor.displayName).tag(descriptor.key)
                    }
                }
                Button {
                    importModelDirectory()
                } label: {
                    Label("导入本地模型目录…", systemImage: "tray.and.arrow.down")
                }
                Button {
                    appState.rebuildVectorIndex()
                } label: {
                    Label("重建当前模型向量", systemImage: "arrow.triangle.2.circlepath")
                }
                if EmbeddingProviderRegistry.customDescriptor()?.key == navigation.vectorModelKey {
                    Button(role: .destructive) {
                        appState.removeCustomVectorModel()
                    } label: {
                        Label("删除自定义模型", systemImage: "trash")
                    }
                }
                if let error = appState.library.lastErrorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Text("选择本地 MLX 模型目录（需含 config.json 与权重文件）后切换即可使用；多模态模型支持文字语义搜索。切换后为照片重新生成向量，旧向量超 30 天未用自动清理。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("分析任务") {
                ForEach(AnalysisKind.allCases) { kind in
                    taskRow(kind)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .task {
            appState.tasks.refreshCompletion()
        }
        .onChange(of: navigation.vectorModelKey) { _, newValue in
            appState.tasks.vectorModelKey = newValue
            appState.saveSettings()
            appState.tasks.start(.vectorIndex)
            appState.tasks.refreshCompletion()
        }
    }

    @ViewBuilder
    private func taskRow(_ kind: AnalysisKind) -> some View {
        let progress = appState.tasks.progress(for: kind)
        let percent = appState.tasks.completionPercent(for: kind)
        HStack(spacing: 10) {
            Image(systemName: kind.iconName)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(kind.fallbackName)
                    Spacer()
                    Text("\(percent)%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: Double(percent), total: 100)
                    .controlSize(.small)
            }
            taskControls(kind, progress)
        }
    }

    @ViewBuilder
    private func taskControls(_ kind: AnalysisKind, _ progress: TaskProgress) -> some View {
        HStack(spacing: 6) {
            switch progress.status {
            case .running:
                Button { appState.tasks.pause(kind) } label: { Image(systemName: "pause.fill") }
                Button { appState.tasks.stop(kind) } label: { Image(systemName: "stop.fill") }
            case .paused:
                Button { appState.tasks.resume(kind) } label: { Image(systemName: "play.fill") }
                Button { appState.tasks.stop(kind) } label: { Image(systemName: "stop.fill") }
            case .queued, .stopping:
                Button { appState.tasks.stop(kind) } label: { Image(systemName: "stop.fill") }
            case .idle, .completed, .failed:
                Button { appState.tasks.start(kind) } label: { Image(systemName: "play.fill") }
            }
        }
        .buttonStyle(.borderless)
        .font(.caption)
    }

    private func importModelDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "选择"
        panel.message = "选择本地 MLX 向量模型目录"
        if panel.runModal() == .OK, let url = panel.url {
            appState.configureCustomVectorModel(directoryURL: url)
        }
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

            if appState.library.sourceAvailability[source.id] == false {
                Text("不可用")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.orange.opacity(0.18), in: Capsule())
                    .foregroundStyle(.orange)
                    .help("该源当前不可访问（如外置硬盘已弹出或目录被移动 / 删除），其照片暂不显示；接回设备后重启应用即可恢复。")
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

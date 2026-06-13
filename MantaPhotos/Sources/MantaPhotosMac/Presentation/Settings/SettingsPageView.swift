import AppKit
import SwiftUI

struct SettingsPageView: View {
    @Environment(AppState.self) private var appState
    @State private var thumbnailCacheUsageBytes: Int64?
    @State private var isClearingThumbnailCache = false

    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()

    var body: some View {
        @Bindable var navigation = appState.navigation
        Form {
            Section("外观") {
                LabeledContent(appState.localized("Theme")) {
                    // 三态单选按钮（系统分段控件），替代下拉 Picker：
                    // 三种外观一目了然，单击即切换，无需展开菜单。
                    Picker(appState.localized("Theme"), selection: $navigation.themeMode) {
                        ForEach(ThemeMode.allCases) { mode in
                            Label(appState.localized(mode.localizationKey), systemImage: mode.iconName)
                                .labelStyle(.iconOnly)
                                .tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 160)
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

            Section("缓存") {
                HStack {
                    Text("本地照片缩略图缓存占用")
                    Spacer()
                    if let bytes = thumbnailCacheUsageBytes {
                        Text(Self.byteFormatter.string(fromByteCount: bytes))
                            .foregroundStyle(.secondary)
                    } else {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                Picker("缓存上限", selection: Binding(
                    get: { ThumbnailCacheLimitOption.closest(to: navigation.thumbnailCacheLimitBytes) },
                    set: { newValue in
                        navigation.thumbnailCacheLimitBytes = newValue.rawValue
                        appState.saveSettings()
                    }
                )) {
                    ForEach(ThumbnailCacheLimitOption.allCases) { option in
                        Text(option.displayName).tag(option)
                    }
                }

                Toggle("超出上限时自动清理最久未访问的缓存", isOn: $navigation.thumbnailCacheAutoCleanEnabled)
                    .onChange(of: navigation.thumbnailCacheAutoCleanEnabled) { _, _ in
                        appState.saveSettings()
                    }

                Button(role: .destructive) {
                    clearThumbnailCache()
                } label: {
                    Label("立即清理缩略图缓存", systemImage: "trash")
                }
                .disabled(isClearingThumbnailCache)

                Text("系统照片库的缩略图由「照片」App 自身管理，不计入此处统计；此缓存仅用于本地 / 外部文件夹中的照片与视频缩略图，用于加快网格浏览与重新打开 App 时的加载速度。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .task {
            appState.tasks.refreshCompletion()
            thumbnailCacheUsageBytes = await appState.thumbnailCacheUsageBytes()
        }
        .onChange(of: navigation.vectorModelKey) { _, newValue in
            appState.tasks.vectorModelKey = newValue
            appState.saveSettings()
            appState.tasks.start(.vectorIndex)
            appState.tasks.refreshCompletion()
        }
    }

    /// 立即清理磁盘 + 内存缩略图缓存，并刷新占用展示。
    private func clearThumbnailCache() {
        isClearingThumbnailCache = true
        appState.clearThumbnailCache()
        Task {
            // 给磁盘删除一点时间，再刷新占用展示。
            try? await Task.sleep(nanoseconds: 300_000_000)
            thumbnailCacheUsageBytes = await appState.thumbnailCacheUsageBytes()
            isClearingThumbnailCache = false
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
            } else if appState.library.sourceAvailability[source.id] == false {
                // 系统图库不可访问时，在此处提供导入入口（功能与原照片页导入按钮
                // 一致：申请权限并导入系统照片图库），替代已从照片页移除的按钮。
                Button {
                    appState.library.startImport()
                } label: {
                    Label(appState.localized("Import"), systemImage: "photo.on.rectangle")
                }
                .controlSize(.small)
                .disabled(appState.library.importProgress.phase == .initialImport || appState.library.importProgress.phase == .backgroundImport)
                .help("申请权限并导入系统照片图库")
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

/// 「缩略图缓存上限」设置项的可选档位（与 `AppSettingsSnapshot.thumbnailCacheLimitBytes` 对应）。
private enum ThumbnailCacheLimitOption: Int64, CaseIterable, Identifiable {
    case mb500 = 524_288_000        // 500 MB
    case gb1 = 1_073_741_824        // 1 GB
    case gb2 = 2_147_483_648        // 2 GB（默认）
    case gb5 = 5_368_709_120        // 5 GB
    case unlimited = 0

    var id: Int64 { rawValue }

    var displayName: String {
        switch self {
        case .mb500: "500 MB"
        case .gb1: "1 GB"
        case .gb2: "2 GB"
        case .gb5: "5 GB"
        case .unlimited: "不限"
        }
    }

    /// 把已存储的字节数映射到最接近的档位；`<= 0` 视为「不限」。
    static func closest(to bytes: Int64) -> ThumbnailCacheLimitOption {
        guard bytes > 0 else { return .unlimited }
        return allCases
            .filter { $0 != .unlimited }
            .first { $0.rawValue >= bytes } ?? .gb5
    }
}

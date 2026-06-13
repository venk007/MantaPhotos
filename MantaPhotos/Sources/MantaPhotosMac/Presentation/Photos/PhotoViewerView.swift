import AppKit
import AVFoundation
import AVKit
import Photos
import PhotosUI
import SwiftUI

// MARK: - 架构说明（本文件是什么 / 改之前先看哪里）
//
// 本文件只负责查看器的 **SwiftUI 布局、状态与业务逻辑**：整体 `body`、
// 顶部/底部工具栏的内容与样式、详情面板、媒体加载与播放控制。
//
// 所有 **AppKit interop**（`NSViewRepresentable`/`NSView` 子类：
// `HostedOverlay`、`ZoomableImageView`、`SwipeAwareScrollView`、
// `LivePhotoPlayerView`、`ViewerKeyCommandsView`）都在同目录的
// `PhotoViewerInteropViews.swift` 里。
//
// 查看器的「手势失效」「快捷键失效」「按钮位置错乱」已经反复出现过，根因
// 都是 SwiftUI 布局调整不经意间破坏了 AppKit 那一侧的 hitTest / 第一响应者
// 协议。**修改 `body`、`viewerOverlayBars`、`viewerTopBar`、
// `viewerBottomBar` 之前，请先读 `PhotoViewerInteropViews.swift` 顶部的
// 架构说明，以及 `MantaPhotos/照片查看器交互问题记录与修改指南.md`。**
//
// 速记：
//   - 工具栏必须用 `HostedOverlay` 包装，且不能撑满全屏（只能是自然高度的
//     窄条；`.frame(maxWidth: .infinity)` 只能加在 `HostedOverlay{...}`
//     外面，用于左右贴边，不能加在内部撑满整屏）。
//   - 键盘快捷键统一在 `ViewerKeyCommandsView.KeyCommandView.keyDown` 里
//     加，不要在按钮上加 `.keyboardShortcut`。

struct PhotoViewerView: View {
    @Environment(AppState.self) private var appState
    var result: PhotoSearchResult
    @State private var image: NSImage?
    @State private var player: AVPlayer?
    @State private var livePhoto: PHLivePhoto?
    @State private var thumbnailToken: ThumbnailRequestToken?
    @State private var showsInfo = false
    @State private var showsDeleteConfirmation = false
    @State private var isPlaying = false
    @State private var extraDetail: PhotoExtraDetail = .empty

    var body: some View {
        ZStack {
            DesignSystem.Glass.viewerBackdrop
                .ignoresSafeArea()

            HStack(spacing: 0) {
                viewerCanvas

                if showsInfo {
                    detailPanel
                        .frame(width: 340)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
        }
        .frame(minWidth: 980, minHeight: 680)
        .onAppear {
            requestMedia()
        }
        .onChange(of: result.id) {
            requestMedia()
        }
        .task(id: result.id) {
            extraDetail = await appState.library.loadExtraDetail(photoID: result.id)
        }
        .onDisappear {
            PhotoThumbnailProvider.shared.cancel(thumbnailToken)
            player?.pause()
            player = nil
            livePhoto = nil
        }
        .animation(.snappy(duration: 0.18), value: showsInfo)
        .onChange(of: isPlaying) {
            updatePlayback()
        }
        .confirmationDialog(
            "Delete this photo from Photos?",
            isPresented: $showsDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete from Photos", role: .destructive) {
                appState.library.deleteSelectedViewerPhotoFromPhotosLibrary()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This calls the system Photos deletion flow. App Trash is separate and can be restored before true deletion.")
        }
    }

    /// 查看器中央画布：媒体内容 + 上下工具栏覆盖层 + 键盘快捷键处理视图。
    ///
    /// 拆成独立属性是为了避免 `body` 里出现一个超大、深度嵌套、带大量
    /// 尾随闭包的表达式——这种表达式曾经触发过 Swift 类型检查器的
    /// "Failed to produce diagnostic for expression" 内部错误（编译器在
    /// 报错前就崩溃，无法定位具体问题）。每个子视图单独写成 `some View`
    /// 计算属性，类型检查的复杂度被分摊到各个属性上，编译器才能正常工作。
    private var viewerCanvas: some View {
        ZStack {
            mediaContent

            // 顶部 / 底部工具栏分别用独立的、按内容自身高度收缩的
            // `HostedOverlay`——**不能**合并成一个铺满整个 ZStack 的覆盖层
            // （之前 `viewerChrome` 就是这么做的），否则覆盖层会盖住中间的
            // 图片区域，导致 `ZoomableImageView`（NSScrollView）的捏合缩放 /
            // 拖拽平移 / 双击缩放 / 双指滑动切图全部失效——这正是「手势失效」
            // 的根因。详见 `HostedOverlay` 文档注释。
            viewerOverlayBars

            // 键盘快捷键：专用 `NSView`（不依赖 SwiftUI `.keyboardShortcut`），
            // 与上面覆盖层的层级结构完全无关，详见 `ViewerKeyCommandsView`
            // 文档注释——这是「快捷键失效」的根因修复。
            viewerKeyCommands
        }
    }

    private var viewerOverlayBars: some View {
        VStack(spacing: 0) {
            HostedOverlay { viewerTopBar }
                // `.frame(maxWidth: .infinity)` 必须加在 `HostedOverlay` 外面：
                // `NSHostingView` 默认按内容（带 `Spacer()` 的 `HStack`）在
                // 「无约束」下的理想尺寸报告 `intrinsicContentSize`，并不会
                // 自动撑满 VStack 的横向空间——不加这一句，「返回」和
                // 「上一/下一张」两组按钮会因为中间 `Spacer()` 拿不到宽度而
                // 挤在左侧中间，而不是分别贴在左上角/右上角。只设
                // `maxWidth`、不设 `maxHeight`，高度仍由内容自然高度决定，
                // 不会撑满到覆盖图片手势区。
                .frame(maxWidth: .infinity)
            Spacer()
            HostedOverlay { viewerBottomBar }
                .frame(maxWidth: .infinity)
        }
    }

    private var viewerKeyCommands: some View {
        // 注意：这里故意先用一个带显式类型标注的局部变量算出
        // `onTogglePlayback`，再传进 `ViewerKeyCommandsView` 的构造器——
        // 直接写成三目表达式
        // `result.asset.mediaType.isPlayableInViewer ? togglePlayback : nil`
        // 会让「八个尾随闭包参数 + 一个需要从『绑定方法引用』推断为
        // `(() -> Void)?` 的三目表达式」这个组合的类型检查复杂度爆炸，
        // 触发 Swift 类型检查器的
        // "Failed to produce diagnostic for expression" 内部错误。
        let onTogglePlayback: (() -> Void)?
        if result.asset.mediaType.isPlayableInViewer {
            onTogglePlayback = { togglePlayback() }
        } else {
            onTogglePlayback = nil
        }

        return ViewerKeyCommandsView(
            onBack: { appState.library.closeViewer() },
            onPrevious: { appState.library.selectAdjacentPhoto(delta: -1) },
            onNext: { appState.library.selectAdjacentPhoto(delta: 1) },
            onTogglePlayback: onTogglePlayback,
            onToggleTrash: { appState.library.toggleSelectedViewerTrash() },
            onToggleFavorite: { appState.library.toggleSelectedViewerFavorite() },
            onDelete: { showsDeleteConfirmation = true },
            onToggleInfo: { showsInfo.toggle() }
        )
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var mediaContent: some View {
        switch result.asset.mediaType {
        case .video:
            if let player {
                VideoPlayer(player: player)
                    .padding(36)
            } else {
                loadingView
            }
        case .livePhoto:
            if let livePhoto {
                LivePhotoPlayerView(livePhoto: livePhoto, isPlaying: $isPlaying)
                    .padding(36)
            } else if let image {
                stillImage(image)
            } else {
                loadingView
            }
        case .image, .unknown:
            if let image {
                stillImage(image)
            } else {
                loadingView
            }
        }
    }

    /// 静态图：手势由 `ZoomableImageView`（原生 NSScrollView）提供。
    private func stillImage(_ image: NSImage) -> some View {
        ZoomableImageView(image: image) { delta in
            appState.library.selectAdjacentPhoto(delta: delta)
        }
        .padding(36)
    }

    private var loadingView: some View {
        ProgressView()
            .tint(.white)
    }

    /// 顶部工具栏：返回 + 上一/下一张按钮。
    ///
    /// **注意**：键盘快捷键（Esc / ←→）不再用 `.keyboardShortcut` 挂在这些按钮上——
    /// 统一由 `ViewerKeyCommandsView` 处理，详见其文档注释。这里的按钮只负责
    /// 鼠标点击与视觉呈现。这一栏被包进独立的 `HostedOverlay`，其 `NSHostingView`
    /// 高度仅为本栏内容的自然高度（由 `VStack` 布局决定），**绝不能**加
    /// `.frame(maxHeight: .infinity)` 等让它撑满整个查看器——否则会盖住中间的
    /// 图片手势区域，详见 `body` 中的说明与 `HostedOverlay` 文档。
    private var viewerTopBar: some View {
        HStack {
            // 「返回」：贴近系统照片 App 全屏详情左上角的 "‹ 照片墙" 返回按钮——
            // 退出查看器、回到照片页（功能等价于原 xmark 关闭按钮，Esc 仍可用）。
            Button {
                appState.library.closeViewer()
            } label: {
                Label(appState.localized("Back"), systemImage: "chevron.left")
                    .labelStyle(.titleAndIcon)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .liquidGlassBackground(material: .hudWindow, in: Capsule())
            .overlay {
                Capsule().stroke(DesignSystem.Glass.hairline, lineWidth: DesignSystem.Glass.hairlineWidth)
            }
            .glassHoverHighlight(in: Capsule())

            Spacer()

            HStack(spacing: 16) {
                Button {
                    appState.library.selectAdjacentPhoto(delta: -1)
                } label: {
                    Image(systemName: "chevron.left")
                }

                Button {
                    appState.library.selectAdjacentPhoto(delta: 1)
                } label: {
                    Image(systemName: "chevron.right")
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .liquidGlassBackground(material: .hudWindow, in: Capsule())
            .overlay {
                Capsule().stroke(DesignSystem.Glass.hairline, lineWidth: DesignSystem.Glass.hairlineWidth)
            }
            .glassHoverHighlight(in: Capsule())
        }
        .buttonStyle(.pressableGlass)
        .font(.title3)
        .foregroundStyle(.white)
        .padding(22)
    }

    /// 底部工具栏：文件名 + 播放 / 照片篓 / 收藏 / 删除 / 信息按钮。
    ///
    /// 同 `viewerTopBar`：键盘快捷键（Space / T / F / D / I）统一由
    /// `ViewerKeyCommandsView` 处理，不再用 `.keyboardShortcut`。这一栏同样
    /// 被包进独立的 `HostedOverlay`，高度仅为自然高度——不能撑满整个查看器。
    private var viewerBottomBar: some View {
        HStack {
            Text(displayName)
                .foregroundStyle(.white)
                .font(.callout.weight(.medium))
                .lineLimit(1)

            Spacer()

            if result.asset.mediaType.isPlayableInViewer {
                Button {
                    togglePlayback()
                } label: {
                    Label(isPlaying ? "Pause" : "Play", systemImage: isPlaying ? "pause.fill" : "play.fill")
                }
                .disabled(!isPlayableReady)
            }

            Button {
                appState.library.toggleSelectedViewerTrash()
            } label: {
                Label(result.asset.inTrash ? "Restore" : "Trash", systemImage: result.asset.inTrash ? "arrow.uturn.backward" : "trash")
            }

            Button {
                appState.library.toggleSelectedViewerFavorite()
            } label: {
                Label(result.asset.isFavorite ? "Favorited" : "Favorite", systemImage: result.asset.isFavorite ? "heart.fill" : "heart")
            }

            Button {
                showsDeleteConfirmation = true
            } label: {
                Label("Delete", systemImage: "delete.left")
            }

            Button {
                showsInfo.toggle()
            } label: {
                Label("Info", systemImage: "info.circle")
            }
        }
        .buttonStyle(.pressableGlass)
        .foregroundStyle(.white)
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .liquidGlassBackground(material: .hudWindow, in: RoundedRectangle(cornerRadius: DesignSystem.Radius.overlay))
        .overlay {
            RoundedRectangle(cornerRadius: DesignSystem.Radius.overlay)
                .stroke(DesignSystem.Glass.hairline, lineWidth: DesignSystem.Glass.hairlineWidth)
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 22)
    }

    private var detailPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(displayName)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)
                    Spacer()
                    statusIcons
                }

                metadataRows

                VStack(alignment: .leading, spacing: 10) {
                    Text("Score")
                        .font(.headline)
                    scorePill("Aesthetic", value: result.aestheticScore)
                    scorePill("Overall", value: result.overallScore)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("标签")
                        .font(.headline)
                    if extraDetail.tags.isEmpty {
                        Text("暂无标签（等待自动标签任务完成）")
                            .foregroundStyle(.secondary)
                            .font(.callout)
                    } else {
                        FlowLayout(spacing: 6) {
                            ForEach(extraDetail.tags, id: \.self) { tag in
                                Text(tag)
                                    .font(.caption)
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 5)
                                    .background(.quaternary, in: Capsule())
                            }
                        }
                    }
                }

                Button {
                    appState.library.searchSimilar(to: result, spaceKey: appState.navigation.vectorModelKey)
                } label: {
                    Label("查找相似照片", systemImage: "rectangle.on.rectangle.angled")
                }
                .buttonStyle(.bordered)
            }
            .padding(22)
        }
        // 液态玻璃半透明详情栏：`LiquidGlassBackground`（`.withinWindow` 的
        // `NSVisualEffectView`）而非系统 `.ultraThinMaterial`/`.regularMaterial`，
        // 在查看器深色背景上呈现出有层次的磨砂玻璃质感，且应用切前台时不会
        // 先黑后透明（见 `DesignSystem.LiquidGlassBackground`）。
        .background(LiquidGlassBackground(material: .hudWindow))
        .environment(\.colorScheme, .dark)
    }

    private var metadataRows: some View {
        VStack(alignment: .leading, spacing: 8) {
            metadataRow("Type", value: result.asset.mediaType.rawValue + (extraDetail.isRaw ? " · RAW" : ""))
            metadataRow("Size", value: "\(result.asset.width) x \(result.asset.height)")
            if let creationDate = result.asset.creationDate {
                metadataRow("Date", value: creationDate.formatted(date: .abbreviated, time: .shortened))
            }
            // 去掉 iCloud 状态行，原位置改为「Location」「Altitude」：
            // 收藏 / 照片篓状态已上移到标题栏以图标展示（见 `statusIcons`）。
            if let place = extraDetail.place {
                if !place.displayLine.isEmpty {
                    metadataRow("Location", value: place.displayLine)
                }
                // 海拔仅在超过 1000 米（高原/高山等显著海拔）时才展示，避免日常照片的噪音数据。
                if let altitude = place.altitude, altitude > 1000 {
                    metadataRow("Altitude", value: "\(Int(altitude.rounded())) m")
                }
            }
        }
    }

    /// 收藏 / 照片篓状态：以图标直观呈现，不再单独占用一行文字。
    /// 只展示「为真」的状态，避免一排灰色占位图标造成视觉噪音。
    @ViewBuilder private var statusIcons: some View {
        if result.asset.isFavorite || result.asset.inTrash {
            HStack(spacing: 8) {
                if result.asset.isFavorite {
                    Image(systemName: "heart.fill")
                        .foregroundStyle(.pink)
                        .help(appState.localized("Favorite"))
                }
                if result.asset.inTrash {
                    Image(systemName: "trash.fill")
                        .foregroundStyle(.secondary)
                        .help(appState.localized("App Trash"))
                }
            }
            .font(.callout)
        }
    }

    private func metadataRow(_ title: String, value: String) -> some View {
        HStack {
            Text(appState.localized(title))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
        }
        .font(.callout)
    }

    private func scorePill(_ title: String, value: Double?) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value.map { "\(Int($0.rounded()))" } ?? "-")
                .monospacedDigit()
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(scoreColor(value), in: Capsule())
                .foregroundStyle(.white)
        }
        .font(.callout)
    }

    private func requestMedia() {
        PhotoThumbnailProvider.shared.cancel(thumbnailToken)
        player?.pause()
        image = nil
        player = nil
        livePhoto = nil
        isPlaying = false

        switch result.asset.mediaType {
        case .video:
            requestVideo()
        case .livePhoto:
            requestLivePhoto()
            requestStillPreview()
        case .image, .unknown:
            requestStillPreview()
        }
    }

    private func requestStillPreview() {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        thumbnailToken = PhotoThumbnailProvider.shared.requestThumbnail(
            for: result.asset,
            targetSize: CGSize(width: 1600 * scale, height: 1600 * scale)
        ) { image in
            self.image = image
        }
    }

    private func requestVideo() {
        // 本地 / 外部源：直接用文件 URL 构建 AVURLAsset（根目录安全作用域已开启）。
        if !result.asset.isSystemPhotos {
            if let url = PhotoSourceRegistry.shared.fileURL(for: result.asset) {
                player = AVPlayer(playerItem: AVPlayerItem(asset: AVURLAsset(url: url)))
            } else {
                requestStillPreview()
            }
            return
        }

        Task {
            do {
                let avAsset = try await PhotoLibraryAdapter().requestAVAsset(localIdentifier: result.asset.localIdentifier)
                guard result.id == appState.library.selectedPhotoForViewer?.id else { return }
                player = AVPlayer(playerItem: AVPlayerItem(asset: avAsset))
            } catch {
                appState.library.reportError(error)
                requestStillPreview()
            }
        }
    }

    private func requestLivePhoto() {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let targetSize = CGSize(width: 1600 * scale, height: 1600 * scale)
        Task {
            do {
                let loadedLivePhoto = try await PhotoLibraryAdapter().requestLivePhoto(
                    localIdentifier: result.asset.localIdentifier,
                    targetSize: targetSize
                )
                guard result.id == appState.library.selectedPhotoForViewer?.id else { return }
                livePhoto = loadedLivePhoto
            } catch {
                appState.library.reportError(error)
            }
        }
    }

    private var isPlayableReady: Bool {
        switch result.asset.mediaType {
        case .video:
            player != nil
        case .livePhoto:
            livePhoto != nil
        case .image, .unknown:
            false
        }
    }

    private func togglePlayback() {
        guard isPlayableReady else { return }
        isPlaying.toggle()
    }

    private func updatePlayback() {
        guard result.asset.mediaType == .video else { return }
        if isPlaying {
            player?.play()
        } else {
            player?.pause()
        }
    }

    private var displayName: String {
        result.asset.filename ?? result.asset.creationDate?.formatted(date: .abbreviated, time: .shortened) ?? result.asset.localIdentifier
    }

    private func scoreColor(_ value: Double?) -> Color {
        guard let value else { return .gray.opacity(0.6) }
        switch value {
        case 80...100: return Color(red: 0.42, green: 0.63, blue: 0.86).opacity(0.85)
        case 60..<80: return Color(red: 0.40, green: 0.76, blue: 0.58).opacity(0.85)
        case 40..<60: return Color(red: 0.91, green: 0.77, blue: 0.34).opacity(0.85)
        default: return Color(red: 0.91, green: 0.55, blue: 0.62).opacity(0.85)
        }
    }
}

private extension MediaType {
    var isPlayableInViewer: Bool {
        self == .video || self == .livePhoto
    }
}

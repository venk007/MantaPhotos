import AppKit
import AVFoundation
import AVKit
import Photos
import PhotosUI
import SwiftUI

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
                ZStack {
                    mediaContent

                    viewerChrome
                }

                if showsInfo {
                    detailPanel
                        .frame(width: 340)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }

            if !result.asset.mediaType.isPlayableInViewer {
                Button {} label: {
                    EmptyView()
                }
                .keyboardShortcut(.space, modifiers: [])
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
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

    private var viewerChrome: some View {
        VStack {
            HStack {
                HStack(spacing: 12) {
                    Button {
                        appState.library.closeViewer()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .keyboardShortcut(.escape)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay {
                    Capsule().stroke(DesignSystem.Glass.hairline, lineWidth: DesignSystem.Glass.hairlineWidth)
                }

                Spacer()

                HStack(spacing: 16) {
                    Button {
                        appState.library.selectAdjacentPhoto(delta: -1)
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .keyboardShortcut(.leftArrow, modifiers: [])

                    Button {
                        appState.library.selectAdjacentPhoto(delta: 1)
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                    .keyboardShortcut(.rightArrow, modifiers: [])
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay {
                    Capsule().stroke(DesignSystem.Glass.hairline, lineWidth: DesignSystem.Glass.hairlineWidth)
                }
            }
            .buttonStyle(.borderless)
            .font(.title3)
            .foregroundStyle(.white)
            .padding(22)

            Spacer()

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
                    .keyboardShortcut(.space, modifiers: [])
                    .disabled(!isPlayableReady)
                }

                Button {
                    appState.library.toggleSelectedViewerTrash()
                } label: {
                    Label(result.asset.inTrash ? "Restore" : "Trash", systemImage: result.asset.inTrash ? "arrow.uturn.backward" : "trash")
                }
                .keyboardShortcut("t", modifiers: [])

                Button {
                    appState.library.toggleSelectedViewerFavorite()
                } label: {
                    Label(result.asset.isFavorite ? "Favorited" : "Favorite", systemImage: result.asset.isFavorite ? "heart.fill" : "heart")
                }
                .keyboardShortcut("f", modifiers: [])

                Button {
                    showsDeleteConfirmation = true
                } label: {
                    Label("Delete", systemImage: "delete.left")
                }
                .keyboardShortcut("d", modifiers: [])

                Button {
                    showsInfo.toggle()
                } label: {
                    Label("Info", systemImage: "info.circle")
                }
                .keyboardShortcut("i", modifiers: [])
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DesignSystem.Radius.overlay))
            .overlay {
                RoundedRectangle(cornerRadius: DesignSystem.Radius.overlay)
                    .stroke(DesignSystem.Glass.hairline, lineWidth: DesignSystem.Glass.hairlineWidth)
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 22)
        }
    }

    private var detailPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(displayName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)

                metadataRows

                VStack(alignment: .leading, spacing: 10) {
                    Text("Score")
                        .font(.headline)
                    scorePill("Aesthetic", value: result.aestheticScore)
                    scorePill("Overall", value: result.overallScore)
                }

                if let place = extraDetail.place {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("地点")
                            .font(.headline)
                        Label(place.displayLine, systemImage: "mappin.and.ellipse")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
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
        .background(.regularMaterial)
    }

    private var metadataRows: some View {
        VStack(alignment: .leading, spacing: 8) {
            metadataRow("Type", value: result.asset.mediaType.rawValue + (extraDetail.isRaw ? " · RAW" : ""))
            metadataRow("Size", value: "\(result.asset.width) x \(result.asset.height)")
            if let creationDate = result.asset.creationDate {
                metadataRow("Date", value: creationDate.formatted(date: .abbreviated, time: .shortened))
            }
            metadataRow("Favorite", value: result.asset.isFavorite ? "Yes" : "No")
            metadataRow("App Trash", value: result.asset.inTrash ? "Yes" : "No")
            metadataRow("iCloud", value: result.asset.iCloudState.rawValue)
        }
    }

    private func metadataRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
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

/// 原生可缩放图片视图：基于 `NSScrollView` 的 `allowsMagnification`，
/// 免费获得与系统照片一致的触控板手势——
/// 捏合缩放、放大后双指拖拽 / 滚动平移、双击切换缩放；未放大时横向滑动切换上一/下一张。
private struct ZoomableImageView: NSViewRepresentable {
    var image: NSImage
    var onNavigate: (Int) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> SwipeAwareScrollView {
        let scrollView = SwipeAwareScrollView()
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.backgroundColor = .clear
        scrollView.allowsMagnification = true
        scrollView.minMagnification = 1
        scrollView.maxMagnification = 6
        scrollView.onNavigate = onNavigate

        let imageView = NSImageView()
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignCenter
        imageView.image = image
        imageView.autoresizingMask = [.width, .height]
        imageView.frame = scrollView.bounds
        scrollView.documentView = imageView

        let doubleClick = NSClickGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleDoubleClick(_:))
        )
        doubleClick.numberOfClicksRequired = 2
        scrollView.addGestureRecognizer(doubleClick)

        context.coordinator.scrollView = scrollView
        context.coordinator.imageView = imageView
        return scrollView
    }

    func updateNSView(_ scrollView: SwipeAwareScrollView, context: Context) {
        scrollView.onNavigate = onNavigate
        if context.coordinator.imageView?.image !== image {
            context.coordinator.imageView?.image = image
            scrollView.magnification = 1
            context.coordinator.imageView?.frame = scrollView.bounds
        }
    }

    final class Coordinator {
        weak var scrollView: NSScrollView?
        weak var imageView: NSImageView?

        @MainActor @objc func handleDoubleClick(_ recognizer: NSClickGestureRecognizer) {
            guard let scrollView else { return }
            if scrollView.magnification > 1.01 {
                scrollView.magnification = 1
            } else {
                let point = recognizer.location(in: scrollView.documentView ?? scrollView)
                scrollView.setMagnification(2.5, centeredAt: point)
            }
        }
    }
}

/// 未放大时把横向双指滑动解释为「上一/下一张」，其余情况交给 `NSScrollView` 原生平移。
final class SwipeAwareScrollView: NSScrollView {
    var onNavigate: ((Int) -> Void)?
    private var swipeAccumulator: CGFloat = 0
    private var swipeFired = false

    override func scrollWheel(with event: NSEvent) {
        let horizontalDominant = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) * 1.5
        if magnification <= 1.01, horizontalDominant {
            if event.phase == .began {
                swipeAccumulator = 0
                swipeFired = false
            }
            swipeAccumulator += event.scrollingDeltaX
            if !swipeFired, abs(swipeAccumulator) >= 60 {
                onNavigate?(swipeAccumulator < 0 ? 1 : -1)
                swipeFired = true
            }
            if event.phase == .ended || event.momentumPhase == .ended {
                swipeAccumulator = 0
                swipeFired = false
            }
            return
        }
        super.scrollWheel(with: event)
    }
}

private struct LivePhotoPlayerView: NSViewRepresentable {
    var livePhoto: PHLivePhoto
    @Binding var isPlaying: Bool

    func makeNSView(context: Context) -> PHLivePhotoView {
        let view = PHLivePhotoView()
        view.livePhoto = livePhoto
        view.delegate = context.coordinator
        return view
    }

    func updateNSView(_ view: PHLivePhotoView, context: Context) {
        if view.livePhoto != livePhoto {
            view.livePhoto = livePhoto
            context.coordinator.isPlaybackActive = false
        }

        if isPlaying, !context.coordinator.isPlaying {
            view.startPlayback(with: .full)
            context.coordinator.isPlaybackActive = true
        } else if !isPlaying, context.coordinator.isPlaying {
            view.stopPlayback()
            context.coordinator.isPlaybackActive = false
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(isPlaying: $isPlaying)
    }

    final class Coordinator: NSObject, PHLivePhotoViewDelegate {
        @Binding var playbackRequested: Bool
        var isPlaybackActive = false

        var isPlaying: Bool { isPlaybackActive }

        init(isPlaying: Binding<Bool>) {
            _playbackRequested = isPlaying
        }

        func livePhotoView(_ livePhotoView: PHLivePhotoView, didEndPlaybackWith playbackStyle: PHLivePhotoViewPlaybackStyle) {
            isPlaybackActive = false
            playbackRequested = false
        }
    }
}

private extension MediaType {
    var isPlayableInViewer: Bool {
        self == .video || self == .livePhoto
    }
}

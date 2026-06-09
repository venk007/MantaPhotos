import AppKit
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
    @State private var requestID: PHImageRequestID?
    @State private var showsInfo = false
    @State private var showsDeleteConfirmation = false
    @State private var isPlaying = false

    // 缩放 / 平移手势状态（仅作用于静态图）。
    @State private var zoomScale: CGFloat = 1
    @State private var panOffset: CGSize = .zero
    @GestureState private var pinchScale: CGFloat = 1
    @GestureState private var dragTranslation: CGSize = .zero

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
            resetZoom()
            requestMedia()
        }
        .onDisappear {
            PhotoThumbnailProvider.shared.cancel(requestID)
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
                zoomableImage(image)
            } else {
                loadingView
            }
        case .image, .unknown:
            if let image {
                zoomableImage(image)
            } else {
                loadingView
            }
        }
    }

    /// 可缩放 / 平移 / 双击放大 / 左右滑动切换的静态图。
    private func zoomableImage(_ image: NSImage) -> some View {
        let effectiveScale = max(1, zoomScale * pinchScale)
        let offset = effectiveScale > 1
            ? CGSize(
                width: panOffset.width + dragTranslation.width,
                height: panOffset.height + dragTranslation.height
            )
            : .zero

        return Image(nsImage: image)
            .resizable()
            .scaledToFit()
            .scaleEffect(effectiveScale)
            .offset(offset)
            .gesture(magnificationGesture.simultaneously(with: dragGesture))
            .onTapGesture(count: 2) { toggleZoom() }
            .padding(36)
            .clipped()
            .animation(.snappy(duration: 0.18), value: zoomScale)
    }

    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .updating($pinchScale) { value, state, _ in
                state = value
            }
            .onEnded { value in
                zoomScale = min(6, max(1, zoomScale * value))
                if zoomScale <= 1 {
                    panOffset = .zero
                }
            }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .updating($dragTranslation) { value, state, _ in
                if zoomScale > 1 {
                    state = value.translation
                }
            }
            .onEnded { value in
                if zoomScale > 1 {
                    panOffset.width += value.translation.width
                    panOffset.height += value.translation.height
                } else if value.translation.width < -60 {
                    appState.library.selectAdjacentPhoto(delta: 1)
                } else if value.translation.width > 60 {
                    appState.library.selectAdjacentPhoto(delta: -1)
                }
            }
    }

    private func toggleZoom() {
        withAnimation(.snappy(duration: 0.2)) {
            if zoomScale > 1 {
                zoomScale = 1
                panOffset = .zero
            } else {
                zoomScale = 2.5
            }
        }
    }

    private func resetZoom() {
        zoomScale = 1
        panOffset = .zero
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
                .keyboardShortcut(".", modifiers: [])

                Button {
                    showsDeleteConfirmation = true
                } label: {
                    Label("Delete", systemImage: "delete.left")
                }
                .keyboardShortcut(.delete, modifiers: [.command])

                Button {
                    showsInfo.toggle()
                } label: {
                    Label("Info", systemImage: "info.circle")
                }
                .keyboardShortcut("i", modifiers: [.command])
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

                VStack(alignment: .leading, spacing: 10) {
                    Text("Tags")
                        .font(.headline)
                    Text("P4+ custom model tags are reserved.")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }
            }
            .padding(22)
        }
        .background(.regularMaterial)
    }

    private var metadataRows: some View {
        VStack(alignment: .leading, spacing: 8) {
            metadataRow("Type", value: result.asset.mediaType.rawValue)
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
        PhotoThumbnailProvider.shared.cancel(requestID)
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
        requestID = PhotoThumbnailProvider.shared.requestThumbnail(
            localIdentifier: result.asset.localIdentifier,
            targetSize: CGSize(width: 1600 * scale, height: 1600 * scale)
        ) { image in
            self.image = image
        }
    }

    private func requestVideo() {
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

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

    var body: some View {
        ZStack {
            Color.black.opacity(0.94)
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
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(36)
            } else {
                loadingView
            }
        case .image, .unknown:
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(36)
            } else {
                loadingView
            }
        }
    }

    private var loadingView: some View {
        ProgressView()
            .tint(.white)
    }

    private var viewerChrome: some View {
        VStack {
            HStack {
                Button {
                    appState.library.closeViewer()
                } label: {
                    Image(systemName: "xmark")
                }
                .keyboardShortcut(.escape)

                Spacer()

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
                .keyboardShortcut("d", modifiers: [.command])

                Button {
                    showsInfo.toggle()
                } label: {
                    Label("Info", systemImage: "info.circle")
                }
                .keyboardShortcut("i", modifiers: [])
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.white)
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
            .background(.ultraThinMaterial)
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

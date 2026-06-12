import AppKit
import Foundation
import Photos

/// 缩略图门面：按资产所属源路由。
/// 系统源走 `PHCachingImageManager`（含预热缓存）；本地 / 外部源走 `LocalThumbnailProvider`（ImageIO）。
/// 对外统一返回 `ThumbnailRequestToken`，调用方无需关心底层是 PhotoKit 还是文件。
final class PhotoThumbnailProvider: @unchecked Sendable {
    static let shared = PhotoThumbnailProvider()

    private let imageManager = PHCachingImageManager()

    private init() {}

    @discardableResult
    func requestThumbnail(
        for asset: PhotoAsset,
        targetSize: CGSize,
        completion: @MainActor @escaping (NSImage?) -> Void
    ) -> ThumbnailRequestToken? {
        switch PhotoSourceRegistry.shared.kind(forSourceID: asset.sourceID) {
        case .systemPhotos:
            return requestSystemThumbnail(
                localIdentifier: asset.localIdentifier,
                targetSize: targetSize,
                completion: completion
            )
        case .localDirectory, .externalLibrary:
            guard let url = PhotoSourceRegistry.shared.fileURL(for: asset) else {
                Task { @MainActor in completion(nil) }
                return nil
            }
            return LocalThumbnailProvider.shared.requestThumbnail(
                fileURL: url,
                cacheKey: asset.id,
                maxPixel: max(targetSize.width, targetSize.height),
                completion: completion
            )
        }
    }

    private func requestSystemThumbnail(
        localIdentifier: String,
        targetSize: CGSize,
        completion: @MainActor @escaping (NSImage?) -> Void
    ) -> ThumbnailRequestToken? {
        let token = ThumbnailRequestToken()
        
        Task.detached(priority: .userInitiated) { [weak self] in
            let result = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
            guard let asset = result.firstObject, let self = self else {
                Task { @MainActor in completion(nil) }
                return
            }

            let options = PHImageRequestOptions()
            options.deliveryMode = .opportunistic
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = false
            options.isSynchronous = false

            let requestID = self.imageManager.requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFill,
                options: options
            ) { image, _ in
                Task { @MainActor in completion(image) }
            }

            token.setOnCancel { [weak self] in
                self?.imageManager.cancelImageRequest(requestID)
            }
        }

        return token
    }

    func cancel(_ token: ThumbnailRequestToken?) {
        token?.cancel()
    }

    func startCaching(assets: [PhotoAsset], targetSize: CGSize) {
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }
            let phAssets = self.systemPHAssets(from: assets)
            guard !phAssets.isEmpty else { return }
            self.imageManager.startCachingImages(
                for: phAssets,
                targetSize: targetSize,
                contentMode: .aspectFill,
                options: nil
            )
        }
        // 本地源缩略图由 LocalThumbnailProvider 惰性缓存，无需在此预热。
    }

    func stopCaching(assets: [PhotoAsset], targetSize: CGSize) {
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }
            let phAssets = self.systemPHAssets(from: assets)
            guard !phAssets.isEmpty else { return }
            self.imageManager.stopCachingImages(
                for: phAssets,
                targetSize: targetSize,
                contentMode: .aspectFill,
                options: nil
            )
        }
    }

    private func systemPHAssets(from assets: [PhotoAsset]) -> [PHAsset] {
        let localIdentifiers = assets
            .filter { $0.sourceID == PhotoSourceDescriptor.systemPhotosID }
            .map(\.localIdentifier)
        guard !localIdentifiers.isEmpty else { return [] }

        let result = PHAsset.fetchAssets(withLocalIdentifiers: localIdentifiers, options: nil)
        var phAssets: [PHAsset] = []
        phAssets.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in
            phAssets.append(asset)
        }
        return phAssets
    }
}

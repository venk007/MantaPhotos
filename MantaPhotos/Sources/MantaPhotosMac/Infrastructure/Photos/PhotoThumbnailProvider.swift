import AppKit
import Foundation
import Photos

final class PhotoThumbnailProvider: @unchecked Sendable {
    static let shared = PhotoThumbnailProvider()

    private let imageManager = PHCachingImageManager()

    private init() {}

    @discardableResult
    func requestThumbnail(
        localIdentifier: String,
        targetSize: CGSize,
        completion: @MainActor @escaping (NSImage?) -> Void
    ) -> PHImageRequestID? {
        let result = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
        guard let asset = result.firstObject else {
            Task { @MainActor in completion(nil) }
            return nil
        }

        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = false
        options.isSynchronous = false

        return imageManager.requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFill,
            options: options
        ) { image, _ in
            Task { @MainActor in
                completion(image)
            }
        }
    }

    func cancel(_ requestID: PHImageRequestID?) {
        guard let requestID else { return }
        imageManager.cancelImageRequest(requestID)
    }

    func startCaching(localIdentifiers: [String], targetSize: CGSize) {
        let assets = phAssets(localIdentifiers: localIdentifiers)
        guard !assets.isEmpty else { return }
        imageManager.startCachingImages(
            for: assets,
            targetSize: targetSize,
            contentMode: .aspectFill,
            options: nil
        )
    }

    func stopCaching(localIdentifiers: [String], targetSize: CGSize) {
        let assets = phAssets(localIdentifiers: localIdentifiers)
        guard !assets.isEmpty else { return }
        imageManager.stopCachingImages(
            for: assets,
            targetSize: targetSize,
            contentMode: .aspectFill,
            options: nil
        )
    }

    private func phAssets(localIdentifiers: [String]) -> [PHAsset] {
        guard !localIdentifiers.isEmpty else { return [] }
        let result = PHAsset.fetchAssets(withLocalIdentifiers: localIdentifiers, options: nil)
        var assets: [PHAsset] = []
        assets.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in
            assets.append(asset)
        }
        return assets
    }
}

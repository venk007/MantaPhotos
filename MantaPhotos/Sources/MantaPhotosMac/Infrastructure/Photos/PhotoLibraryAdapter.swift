import Foundation
@preconcurrency import AVFoundation
import Photos
import PhotosUI

struct PhotoLibraryAdapter {
    static let initialImportLimit = 3_000

    func requestAuthorization() async -> PHAuthorizationStatus {
        await PHPhotoLibrary.requestAuthorization(for: .readWrite)
    }

    func authorizationStatus() -> PHAuthorizationStatus {
        PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    func fetchAssetCount() -> Int {
        PHAsset.fetchAssets(with: Self.fetchOptions(limit: nil)).count
    }

    func fetchAssets(limit: Int? = nil, offset: Int = 0, includeFilenames: Bool = false) -> [PhotoAsset] {
        let result = PHAsset.fetchAssets(with: Self.fetchOptions(limit: limit.map { $0 + offset }))
        var assets: [PhotoAsset] = []
        assets.reserveCapacity(limit ?? max(0, result.count - offset))

        result.enumerateObjects { asset, index, stop in
            guard index >= offset else { return }
            if let limit, assets.count >= limit {
                stop.pointee = true
                return
            }
            assets.append(Self.map(asset: asset, includeFilename: includeFilenames))
        }

        return assets
    }

    func requestImageData(localIdentifier: String, allowNetworkAccess: Bool = false) async throws -> Data {
        let result = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
        guard let asset = result.firstObject else {
            throw PhotoLibraryAdapterError.assetNotFound(localIdentifier)
        }

        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = allowNetworkAccess
        options.isSynchronous = false

        return try await withCheckedThrowingContinuation { continuation in
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, info in
                if let error = info?[PHImageErrorKey] as? Error {
                    continuation.resume(throwing: error)
                    return
                }

                if let isCancelled = info?[PHImageCancelledKey] as? Bool, isCancelled {
                    continuation.resume(throwing: CancellationError())
                    return
                }

                guard let data else {
                    continuation.resume(throwing: PhotoLibraryAdapterError.imageDataUnavailable(localIdentifier))
                    return
                }

                continuation.resume(returning: data)
            }
        }
    }

    func requestAVAsset(localIdentifier: String, allowNetworkAccess: Bool = false) async throws -> AVAsset {
        let result = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
        guard let asset = result.firstObject else {
            throw PhotoLibraryAdapterError.assetNotFound(localIdentifier)
        }

        let options = PHVideoRequestOptions()
        options.deliveryMode = .automatic
        options.isNetworkAccessAllowed = allowNetworkAccess

        return try await withCheckedThrowingContinuation { continuation in
            PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, info in
                if let error = info?[PHImageErrorKey] as? Error {
                    continuation.resume(throwing: error)
                    return
                }

                if let isCancelled = info?[PHImageCancelledKey] as? Bool, isCancelled {
                    continuation.resume(throwing: CancellationError())
                    return
                }

                guard let avAsset else {
                    continuation.resume(throwing: PhotoLibraryAdapterError.videoAssetUnavailable(localIdentifier))
                    return
                }

                continuation.resume(returning: avAsset)
            }
        }
    }

    func requestLivePhoto(
        localIdentifier: String,
        targetSize: CGSize,
        allowNetworkAccess: Bool = false
    ) async throws -> PHLivePhoto {
        let result = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
        guard let asset = result.firstObject else {
            throw PhotoLibraryAdapterError.assetNotFound(localIdentifier)
        }

        let options = PHLivePhotoRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = allowNetworkAccess

        return try await withCheckedThrowingContinuation { continuation in
            var didResume = false
            PHImageManager.default().requestLivePhoto(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFit,
                options: options
            ) { livePhoto, info in
                if didResume { return }

                if let error = info?[PHImageErrorKey] as? Error {
                    didResume = true
                    continuation.resume(throwing: error)
                    return
                }

                if let isCancelled = info?[PHImageCancelledKey] as? Bool, isCancelled {
                    didResume = true
                    continuation.resume(throwing: CancellationError())
                    return
                }

                if let isDegraded = info?[PHImageResultIsDegradedKey] as? Bool, isDegraded {
                    return
                }

                guard let livePhoto else {
                    didResume = true
                    continuation.resume(throwing: PhotoLibraryAdapterError.livePhotoUnavailable(localIdentifier))
                    return
                }

                didResume = true
                continuation.resume(returning: livePhoto)
            }
        }
    }

    func setFavorite(localIdentifier: String, isFavorite: Bool) async throws {
        let asset = try await Task.detached(priority: .userInitiated) {
            let result = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
            guard let asset = result.firstObject else {
                throw PhotoLibraryAdapterError.assetNotFound(localIdentifier)
            }
            return asset
        }.value

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges {
                let request = PHAssetChangeRequest(for: asset)
                request.isFavorite = isFavorite
            } completionHandler: { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: PhotoLibraryAdapterError.photoLibraryChangeFailed)
                }
            }
        }
    }

    func deleteAsset(localIdentifier: String) async throws {
        let asset = try await Task.detached(priority: .userInitiated) {
            let result = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
            guard let asset = result.firstObject else {
                throw PhotoLibraryAdapterError.assetNotFound(localIdentifier)
            }
            return asset
        }.value

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets([asset] as NSArray)
            } completionHandler: { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: PhotoLibraryAdapterError.photoLibraryChangeFailed)
                }
            }
        }
    }

    func deleteAssets(localIdentifiers: [String]) async throws {
        guard !localIdentifiers.isEmpty else { return }
        let assets = await Task.detached(priority: .userInitiated) {
            let result = PHAsset.fetchAssets(withLocalIdentifiers: localIdentifiers, options: nil)
            guard result.count > 0 else { return [PHAsset]() }
            var assets: [PHAsset] = []
            result.enumerateObjects { asset, _, _ in assets.append(asset) }
            return assets
        }.value
        guard !assets.isEmpty else { return }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(assets as NSArray)
            } completionHandler: { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: PhotoLibraryAdapterError.photoLibraryChangeFailed)
                }
            }
        }
    }

    private static func fetchOptions(limit: Int?) -> PHFetchOptions {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        if let limit {
            options.fetchLimit = limit
        }
        return options
    }

    private static func map(asset: PHAsset, includeFilename: Bool) -> PhotoAsset {
        let filename = includeFilename ? PHAssetResource.assetResources(for: asset).first?.originalFilename : nil
        let mediaType = MediaType(phAssetMediaType: asset.mediaType, mediaSubtypes: asset.mediaSubtypes)

        return PhotoAsset(
            id: asset.localIdentifier,
            localIdentifier: asset.localIdentifier,
            filename: filename,
            mediaType: mediaType,
            mediaSubtypesRawValue: asset.mediaSubtypes.rawValue,
            creationDate: asset.creationDate,
            modificationDate: asset.modificationDate,
            width: asset.pixelWidth,
            height: asset.pixelHeight,
            duration: asset.duration > 0 ? asset.duration : nil,
            isFavorite: asset.isFavorite,
            isHidden: asset.isHidden,
            inTrash: false,
            trashedAt: nil,
            iCloudState: .unknown,
            isLocallyAvailable: nil
        )
    }
}

enum PhotoLibraryAdapterError: Error, LocalizedError {
    case assetNotFound(String)
    case imageDataUnavailable(String)
    case videoAssetUnavailable(String)
    case livePhotoUnavailable(String)
    case photoLibraryChangeFailed

    var errorDescription: String? {
        switch self {
        case .assetNotFound(let id):
            "Photo asset was not found: \(id)"
        case .imageDataUnavailable(let id):
            "Image data is unavailable for photo asset: \(id)"
        case .videoAssetUnavailable(let id):
            "Video asset is unavailable for photo asset: \(id)"
        case .livePhotoUnavailable(let id):
            "Live Photo is unavailable for photo asset: \(id)"
        case .photoLibraryChangeFailed:
            "Photos library change failed."
        }
    }
}

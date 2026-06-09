import AppKit
@preconcurrency import AVFoundation
import CoreMedia
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// 跨线程的取消标志（best-effort）。
final class CancellationBox: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelledFlag = false

    var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return cancelledFlag
    }

    func cancel() {
        lock.lock(); cancelledFlag = true; lock.unlock()
    }
}

/// 本地文件类型判定。
enum LocalMediaType {
    static let imageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "heic", "heif", "gif", "tiff", "tif", "bmp", "webp", "raw",
        "dng", "cr2", "cr3", "nef", "arw", "rw2", "orf"
    ]
    static let videoExtensions: Set<String> = [
        "mov", "mp4", "m4v", "avi", "mkv", "hevc", "3gp"
    ]

    static func isImage(_ url: URL) -> Bool { imageExtensions.contains(url.pathExtension.lowercased()) }
    static func isVideo(_ url: URL) -> Bool { videoExtensions.contains(url.pathExtension.lowercased()) }
    static func isSupported(_ url: URL) -> Bool { isImage(url) || isVideo(url) }

    static func mediaType(for url: URL) -> MediaType {
        if isVideo(url) { return .video }
        if isImage(url) { return .image }
        return .unknown
    }
}

/// 本地缩略图提供者：ImageIO 等比降采样 + NSCache；视频用 AVAssetImageGenerator 取首帧。
///
/// 取代系统源的 `PHCachingImageManager`（其缓存对本地文件不可用）。
final class LocalThumbnailProvider: @unchecked Sendable {
    static let shared = LocalThumbnailProvider()

    private let cache = NSCache<NSString, NSImage>()
    private let queue = DispatchQueue(
        label: "manta.local.thumbnail",
        qos: .userInitiated,
        attributes: .concurrent
    )

    private init() {
        cache.countLimit = 1_000
    }

    /// 返回一个可取消句柄；命中缓存则同步回主线程。
    func requestThumbnail(
        fileURL: URL,
        cacheKey: String,
        maxPixel: CGFloat,
        completion: @MainActor @escaping (NSImage?) -> Void
    ) -> ThumbnailRequestToken {
        let keyString = "\(cacheKey)@\(Int(maxPixel))"
        if let cached = cache.object(forKey: keyString as NSString) {
            Task { @MainActor in completion(cached) }
            return ThumbnailRequestToken {}
        }

        let box = CancellationBox()
        queue.async { [weak self] in
            if box.isCancelled { return }
            let image = Self.makeThumbnail(url: fileURL, maxPixel: maxPixel)
            if let image {
                self?.cache.setObject(image, forKey: keyString as NSString)
            }
            if box.isCancelled { return }
            Task { @MainActor in completion(image) }
        }
        return ThumbnailRequestToken { box.cancel() }
    }

    static func makeThumbnail(url: URL, maxPixel: CGFloat) -> NSImage? {
        if LocalMediaType.isVideo(url) {
            return videoPosterFrame(url: url, maxPixel: maxPixel)
        }
        return imageThumbnail(url: url, maxPixel: maxPixel)
    }

    static func imageThumbnail(url: URL, maxPixel: CGFloat) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: max(64, maxPixel),
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    static func videoPosterFrame(url: URL, maxPixel: CGFloat) -> NSImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxPixel, height: maxPixel)
        let time = CMTime(value: 1, timescale: 2) // 约 0.5s，避开纯黑首帧
        // 同步取帧 API 在新系统标记为弃用，但仍可用；缩略图在后台队列调用，影响可控。
        guard let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) else {
            return nil
        }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
}

/// 本地媒体取数（用于评分与查看器）。Sendable，可在评分 actor / 后台调用。
struct LocalMediaProvider: Sendable {
    /// 给评分用的图像数据：图片直接读文件；视频取一帧编码为 JPEG。
    func imageData(fileURL: URL) throws -> Data {
        if LocalMediaType.isVideo(fileURL) {
            guard let frame = LocalThumbnailProvider.videoPosterFrame(url: fileURL, maxPixel: 2048),
                  let data = Self.jpegData(from: frame) else {
                throw PhotoSourceError.thumbnailGenerationFailed(fileURL.lastPathComponent)
            }
            return data
        }
        return try Data(contentsOf: fileURL)
    }

    private static func jpegData(from image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.9])
    }
}

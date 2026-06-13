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

/// 本地缩略图提供者：两级缓存（L1 内存 `NSCache` + L2 磁盘 `DiskThumbnailCache`）+
/// ImageIO 等比降采样 / AVAssetImageGenerator 视频取首帧兜底。
///
/// 取代系统源的 `PHCachingImageManager`（其缓存对本地文件不可用）。
///
/// 缓存 key 按 `ThumbnailBucket` 档位（而非精确 `maxPixel`）：切换网格列数时
/// `maxPixel` 大多落在同一档位，直接命中；解码也按档位尺寸生成，保证返回的图
/// 永不小于目标尺寸（详见 `DiskThumbnailCache`/`ThumbnailBucket` 文档注释，
/// 对应任务「缩略图偶尔不清晰」的修复）。
final class LocalThumbnailProvider: @unchecked Sendable {
    static let shared = LocalThumbnailProvider()

    private let cache = NSCache<NSString, NSImage>()

    private init() {
        cache.countLimit = 1_000
    }

    /// 返回一个可取消句柄；命中 L1 缓存则同步回主线程。
    func requestThumbnail(
        fileURL: URL,
        cacheKey: String,
        maxPixel: CGFloat,
        completion: @MainActor @escaping (NSImage?) -> Void
    ) -> ThumbnailRequestToken {
        let bucket = ThumbnailBucket.bucket(for: maxPixel)
        let memoryKey = "\(cacheKey)@\(bucket.rawValue)" as NSString
        if let cached = cache.object(forKey: memoryKey) {
            Task { @MainActor in completion(cached) }
            return ThumbnailRequestToken {}
        }

        let box = CancellationBox()
        let task = Task.detached(priority: .userInitiated) { [weak self] in
            if box.isCancelled { return }

            // 磁盘缓存 key 追加文件 mtime：文件被替换（同名新文件）时自动失效旧缓存，
            // 无需显式失效逻辑。
            let mtime: Double
            if let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]),
               let modDate = values.contentModificationDate {
                mtime = modDate.timeIntervalSince1970
            } else {
                mtime = 0
            }
            let diskKey = "\(cacheKey)_\(Int(mtime))"

            // L2：磁盘缓存命中——解码 JPEG 回填 L1 后直接返回，不再重新生成。
            if let diskImage = await DiskThumbnailCache.shared.loadImage(cacheKey: diskKey, bucket: bucket) {
                self?.cache.setObject(diskImage, forKey: memoryKey)
                if box.isCancelled { return }
                await MainActor.run { completion(diskImage) }
                return
            }

            // L1/L2 均未命中：按「档位尺寸」（而非精确 maxPixel）解码，
            // 结果同时写回 L1 + L2，供同档位的后续请求（切换网格密度 / 重开 App）复用。
            // 实际解码（ImageIO 同步降采样 / 视频取帧）放到 `ThumbnailLoadingQueue`
            // 的高并发队列上执行，避免与 Swift Concurrency 协作线程池竞争。
            let bucketPixel = CGFloat(bucket.rawValue)
            let image: NSImage?
            if LocalMediaType.isVideo(fileURL) {
                image = await Self.videoPosterFrame(url: fileURL, maxPixel: bucketPixel)
            } else {
                image = await ThumbnailLoadingQueue.run {
                    Self.imageThumbnail(url: fileURL, maxPixel: bucketPixel)
                }
            }
            if let image {
                self?.cache.setObject(image, forKey: memoryKey)
                await DiskThumbnailCache.shared.store(image: image, cacheKey: diskKey, bucket: bucket)
            }
            if box.isCancelled { return }
            await MainActor.run { completion(image) }
        }
        return ThumbnailRequestToken {
            box.cancel()
            task.cancel()
        }
    }

    /// 清空 L1 内存缓存（配合「立即清理」一并清空磁盘缓存）。
    func clearMemoryCache() {
        cache.removeAllObjects()
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

    static func videoPosterFrame(url: URL, maxPixel: CGFloat) async -> NSImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxPixel, height: maxPixel)
        let time = CMTime(value: 1, timescale: 2) // 约 0.5s，避开纯黑首帧
        // 用 macOS 13+ 的异步 `image(at:)` 取帧，替代已弃用 / 在新 SDK 移除的 `copyCGImage(at:actualTime:)`。
        guard let cgImage = try? await generator.image(at: time).image else {
            return nil
        }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
}

/// 本地媒体取数（用于评分与查看器）。Sendable，可在评分 actor / 后台调用。
struct LocalMediaProvider: Sendable {
    /// 给评分用的图像数据：图片直接读文件；视频取一帧编码为 JPEG。
    func imageData(fileURL: URL) async throws -> Data {
        if LocalMediaType.isVideo(fileURL) {
            guard let frame = await LocalThumbnailProvider.videoPosterFrame(url: fileURL, maxPixel: 2048),
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

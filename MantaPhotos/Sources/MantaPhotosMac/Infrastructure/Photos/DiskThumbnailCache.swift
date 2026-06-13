import AppKit
import CryptoKit
import Foundation

/// 缩略图磁盘缓存的尺寸档位。
///
/// 不再用精确 `maxPixel` 做缓存 key，而是向上取整到固定档位：
/// - 切换网格列数时，`maxPixel` 多数情况落在同一档位内，直接命中缓存，不会重新生成；
/// - 查找时按 ">= 目标像素的最小档位"，**保证返回的图永远不比目标尺寸小**——
///   这是任务「缩略图偶尔不清晰」的关键修复点之一：之前按精确像素缓存时，
///   一旦目标尺寸发生像素级抖动，命中的旧缓存可能比新目标尺寸略小，
///   `resizeAspectFill` 放大显示就会发虚。
///
/// 设计详见 `doc/缩略图缓存方案设计.md` §3.2。
enum ThumbnailBucket: Int, CaseIterable, Sendable {
    case xs = 160   // 最密网格
    case sm = 320
    case md = 640
    case lg = 1024
    case xl = 2048  // 查看器静态预览

    /// 向上取整到能覆盖 `maxPixel` 的最小档位；超过最大档位则用最大档位（`xl`）。
    static func bucket(for maxPixel: CGFloat) -> ThumbnailBucket {
        allCases.first { CGFloat($0.rawValue) >= maxPixel } ?? .xl
    }

    var directoryName: String { "\(rawValue)" }
}

/// 本地 / 外部目录源缩略图的二级（磁盘）缓存。
///
/// 系统照片源由 PhotoKit 的 `resources/derivatives/` 持久化缓存覆盖，不需要、也不应该
/// 重复实现（见设计文档 §1.1）；此缓存只服务 `LocalThumbnailProvider`。
///
/// 落盘结构：
/// ```
/// ~/Library/Application Support/MantaPhotos/ThumbnailCache/<bucket>/<sha256(key)>.jpg
/// ```
/// JPEG 质量 0.85——比原图小得多，解码比重新跑一遍 ImageIO 全套降采样快很多。
///
/// LRU：不引入新的数据库表（历史上 `thumbnail_cache_index` 表因「无增量价值」被移除，
/// 见 `DatabaseMigrator.dropThumbnailCacheIndexSQL`）；改用文件系统自身的「修改时间」
/// 做轻量 LRU——每次命中读取时把 mtime `touch` 到当前时间，清理时按 mtime 升序删除。
actor DiskThumbnailCache {
    static let shared = DiskThumbnailCache()

    private let baseDirectory: URL

    private init() {
        baseDirectory = AppPaths.applicationSupportDirectory
            .appending(path: "ThumbnailCache", directoryHint: .isDirectory)
    }

    /// 读取磁盘缓存；命中时异步 `touch` 更新 mtime（用于 LRU），未命中返回 `nil`。
    /// 解码在 `ThumbnailLoadingQueue`（`.utility`）上执行，避免新的 QoS 反转。
    func loadImage(cacheKey: String, bucket: ThumbnailBucket) async -> NSImage? {
        let url = fileURL(cacheKey: cacheKey, bucket: bucket)
        return await ThumbnailLoadingQueue.run {
            guard let data = try? Data(contentsOf: url), let image = NSImage(data: data) else { return nil }
            try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
            return image
        }
    }

    /// 写入磁盘缓存（JPEG quality 0.85），目录不存在时自动创建。
    func store(image: NSImage, cacheKey: String, bucket: ThumbnailBucket) async {
        let url = fileURL(cacheKey: cacheKey, bucket: bucket)
        let directory = url.deletingLastPathComponent()
        await ThumbnailLoadingQueue.run {
            guard let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.85]) else { return }
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? jpeg.write(to: url, options: .atomic)
        }
    }

    /// 当前缓存总占用（字节），供「设置 → 缓存」展示。
    func currentUsageBytes() async -> Int64 {
        let directory = baseDirectory
        return await ThumbnailLoadingQueue.run {
            Self.totalSize(of: directory)
        }
    }

    /// 「立即清理」：删除整个磁盘缓存目录。调用方还需清空 L1 `NSCache`。
    func clearAll() async {
        let directory = baseDirectory
        await ThumbnailLoadingQueue.run {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    /// LRU 清理：占用超过 `limitBytes` 时，按 mtime 升序删除最久未访问的文件，
    /// 直到回落到上限的 90%（留缓冲，避免每次写入都触发清理）。
    func enforceLimit(_ limitBytes: Int64) async {
        guard limitBytes > 0 else { return }
        let directory = baseDirectory
        await ThumbnailLoadingQueue.run {
            let fileManager = FileManager.default
            var entries: [(url: URL, size: Int64, mtime: Date)] = []
            var total: Int64 = 0
            for url in Self.allFiles(under: directory) {
                guard let attrs = try? fileManager.attributesOfItem(atPath: url.path) else { continue }
                let size = (attrs[.size] as? Int64) ?? 0
                let mtime = (attrs[.modificationDate] as? Date) ?? .distantPast
                total += size
                entries.append((url, size, mtime))
            }
            guard total > limitBytes else { return }

            let target = Int64(Double(limitBytes) * 0.9)
            for entry in entries.sorted(by: { $0.mtime < $1.mtime }) {
                guard total > target else { break }
                try? fileManager.removeItem(at: entry.url)
                total -= entry.size
            }
        }
    }

    private func fileURL(cacheKey: String, bucket: ThumbnailBucket) -> URL {
        baseDirectory
            .appending(path: bucket.directoryName, directoryHint: .isDirectory)
            .appending(path: "\(Self.sha256Hex(cacheKey)).jpg")
    }

    private static func totalSize(of directory: URL) -> Int64 {
        let fileManager = FileManager.default
        return allFiles(under: directory).reduce(into: Int64(0)) { total, url in
            if let attrs = try? fileManager.attributesOfItem(atPath: url.path), let size = attrs[.size] as? Int64 {
                total += size
            }
        }
    }

    private static func allFiles(under directory: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) else { return [] }

        var results: [URL] = []
        for case let url as URL in enumerator {
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if !isDirectory {
                results.append(url)
            }
        }
        return results
    }

    private static func sha256Hex(_ string: String) -> String {
        let digest = SHA256.hash(data: Data(string.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

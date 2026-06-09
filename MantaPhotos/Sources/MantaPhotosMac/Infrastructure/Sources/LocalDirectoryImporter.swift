import Foundation
import ImageIO

/// 本地目录导入器：递归扫描根目录下的图片 / 视频，提取元数据并 upsert 到数据库。
///
/// 设计要点：
/// - `id` = `"{sourceID}:{relativePath}"`，幂等 upsert（同一文件重扫不产生重复行）。
/// - `local_identifier` 同步存 `id`（满足历史 not null unique 约束）。
/// - 通过源根目录的安全作用域访问读取（调用方已 `startAccessingSecurityScopedResource`）。
/// - Sendable，可在 `Task.detached` 后台执行，避免阻塞主线程。
struct LocalDirectoryImporter: Sendable {
    let repository: PhotoAssetRepository
    let sourceID: String
    let rootURL: URL
    var batchSize: Int = 200

    @discardableResult
    func importAll(
        progressHandler: (@MainActor @Sendable (PhotoImportProgress) -> Void)? = nil
    ) async throws -> PhotoImportSummary {
        let files = enumerateMediaFiles()
        let total = files.count
        var imported = 0
        var batch: [PhotoAsset] = []
        batch.reserveCapacity(batchSize)

        await progressHandler?(
            PhotoImportProgress(phase: .initialImport, imported: 0, total: total, message: "Scanning folder")
        )

        for fileURL in files {
            try Task.checkCancellation()
            if let asset = makeAsset(fileURL: fileURL) {
                batch.append(asset)
            }
            if batch.count >= batchSize {
                try repository.upsert(batch)
                imported += batch.count
                batch.removeAll(keepingCapacity: true)
                await progressHandler?(
                    PhotoImportProgress(phase: .backgroundImport, imported: imported, total: total, message: "Importing folder")
                )
            }
        }

        if !batch.isEmpty {
            try repository.upsert(batch)
            imported += batch.count
        }

        await progressHandler?(
            PhotoImportProgress(phase: .completed, imported: imported, total: total, message: "Import completed")
        )

        return PhotoImportSummary(imported: imported, total: total)
    }

    private func enumerateMediaFiles() -> [URL] {
        let fileManager = FileManager.default
        let keys: [URLResourceKey] = [.isRegularFileKey, .contentModificationDateKey]
        guard let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        var entries: [(url: URL, date: Date)] = []
        for case let url as URL in enumerator {
            guard LocalMediaType.isSupported(url) else { continue }
            let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            entries.append((url, date))
        }
        // 与系统库一致：按时间倒序（新→旧）。
        return entries.sorted { $0.date > $1.date }.map(\.url)
    }

    private func makeAsset(fileURL: URL) -> PhotoAsset? {
        let mediaType = LocalMediaType.mediaType(for: fileURL)
        guard mediaType != .unknown else { return nil }

        let relativePath = Self.relativePath(of: fileURL, root: rootURL)
        let assetID = "\(sourceID):\(relativePath)"

        let resourceValues = try? fileURL.resourceValues(
            forKeys: [.fileSizeKey, .contentModificationDateKey, .creationDateKey]
        )
        let fileSize = resourceValues?.fileSize.map { Int64($0) }
        let modificationDate = resourceValues?.contentModificationDate
        var creationDate = resourceValues?.creationDate ?? modificationDate

        var width = 0
        var height = 0
        if mediaType == .image {
            if let dimensions = Self.imageDimensions(fileURL) {
                width = dimensions.width
                height = dimensions.height
            }
            if let exifDate = Self.exifCreationDate(fileURL) {
                creationDate = exifDate
            }
        }
        // 视频的精确尺寸 / 时长需异步 AVAsset.load，导入阶段从略（不影响网格与评分）。

        return PhotoAsset(
            id: assetID,
            localIdentifier: assetID,
            filename: fileURL.lastPathComponent,
            mediaType: mediaType,
            mediaSubtypesRawValue: 0,
            creationDate: creationDate,
            modificationDate: modificationDate,
            width: width,
            height: height,
            duration: nil,
            isFavorite: false,
            isHidden: false,
            inTrash: false,
            trashedAt: nil,
            iCloudState: .local,
            isLocallyAvailable: true,
            sourceID: sourceID,
            sourceAssetKey: relativePath,
            relativePath: relativePath,
            contentHash: nil, // 跨源去重为基础版：content_hash 留待后续按需补算
            fileSize: fileSize,
            isScreenshotFlag: false
        )
    }

    static func relativePath(of url: URL, root: URL) -> String {
        let rootComponents = root.standardizedFileURL.pathComponents
        let urlComponents = url.standardizedFileURL.pathComponents
        if urlComponents.count > rootComponents.count,
           Array(urlComponents.prefix(rootComponents.count)) == rootComponents {
            return urlComponents.dropFirst(rootComponents.count).joined(separator: "/")
        }
        return url.lastPathComponent
    }

    static func imageDimensions(_ url: URL) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return nil
        }
        let width = (properties[kCGImagePropertyPixelWidth] as? Int) ?? 0
        let height = (properties[kCGImagePropertyPixelHeight] as? Int) ?? 0
        guard width > 0, height > 0 else { return nil }
        return (width, height)
    }

    static func exifCreationDate(_ url: URL) -> Date? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return nil
        }
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any]
        let raw = (exif?[kCGImagePropertyExifDateTimeOriginal] as? String)
            ?? (exif?[kCGImagePropertyExifDateTimeDigitized] as? String)
        guard let raw else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.date(from: raw)
    }
}

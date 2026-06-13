import AppKit
import Foundation
import Photos

/// 缩略图后台加载专用并发队列：并发宽度为 CPU 核心数的 4 倍（至少 8）。
///
/// Swift Concurrency 的全局协作线程池默认宽度约等于 CPU 核心数，在「切换网格密度」
/// 这类瞬间产生大量缩略图请求（解码 / PhotoKit 资产查找等含阻塞调用）的场景下
/// 容易成为瓶颈、互相排队。把这部分工作放到独立的 `OperationQueue` 上以更高并发度
/// 执行，能明显缩短整体刷新耗时；通过 `withCheckedContinuation` 桥接回
/// `async`，外层 `Task.detached` 本身不会被阻塞。
///
/// QoS 选用 `.utility` 而非 `.userInitiated`：`CGImageSourceCreateThumbnailAtIndex`
/// （见 `LocalThumbnailProvider.imageThumbnail`）内部对 RAW / HEIC 等格式会派发到
/// ImageIO 自身的 `.default`/`.utility` QoS 解码队列并同步等待——若本队列线程是
/// `.userInitiated`（高于 ImageIO 内部队列），就会出现「高 QoS 线程阻塞等待低 QoS
/// 线程」的优先级反转告警。`.utility` 低于或等于 ImageIO 内部 QoS，等待变成正常的
/// QoS 提升而非反转；并发宽度本身已远高于 CPU 核心数，实际吞吐不受影响。
enum ThumbnailLoadingQueue {
    static let shared: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "MantaPhotos.ThumbnailLoading"
        queue.maxConcurrentOperationCount = max(8, ProcessInfo.processInfo.activeProcessorCount * 4)
        queue.qualityOfService = .utility
        return queue
    }()

    /// 在高并发队列上执行同步耗时操作，并以 `async` 形式返回结果。
    ///
    /// 显式给 `BlockOperation` 设置 QoS：仅设置 `queue.qualityOfService`
    /// 不会下发到每个 `addOperation { }` 闭包的底层 GCD QoS。`.utility`
    /// 与队列一致，避免与 ImageIO 内部解码队列之间的优先级反转（见上方注释）。
    static func run<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            let operation = BlockOperation {
                continuation.resume(returning: work())
            }
            operation.qualityOfService = .utility
            shared.addOperation(operation)
        }
    }
}

/// 缩略图门面：按资产所属源路由。
/// 系统源走 `PHCachingImageManager`（含预热缓存）；本地 / 外部源走 `LocalThumbnailProvider`（ImageIO）。
/// 对外统一返回 `ThumbnailRequestToken`，调用方无需关心底层是 PhotoKit 还是文件。
final class PhotoThumbnailProvider: @unchecked Sendable {
    static let shared = PhotoThumbnailProvider()

    private let imageManager = PHCachingImageManager()
    /// localIdentifier → PHAsset 缓存，避免每次缩略图请求都重新 `fetchAssets`
    /// （切换网格密度时同一批照片会以新的 `targetSize` 重新请求一遍）。
    private let assetCache = NSCache<NSString, PHAsset>()

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
            guard let self = self else {
                Task { @MainActor in completion(nil) }
                return
            }

            let asset: PHAsset
            if let cached = self.assetCache.object(forKey: localIdentifier as NSString) {
                asset = cached
            } else {
                let fetched = await ThumbnailLoadingQueue.run {
                    PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil).firstObject
                }
                guard let fetched else {
                    Task { @MainActor in completion(nil) }
                    return
                }
                self.assetCache.setObject(fetched, forKey: localIdentifier as NSString)
                asset = fetched
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
            let phAssets = await self.systemPHAssets(from: assets)
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
            let phAssets = await self.systemPHAssets(from: assets)
            guard !phAssets.isEmpty else { return }
            self.imageManager.stopCachingImages(
                for: phAssets,
                targetSize: targetSize,
                contentMode: .aspectFill,
                options: nil
            )
        }
    }

    /// 解析一批资产对应的 `PHAsset`：先查 `assetCache`，未命中的再批量 `fetchAssets`。
    ///
    /// **关键修复**：`PHAsset.fetchAssets(withLocalIdentifiers:)` 是同步阻塞调用。
    /// 之前这里直接在 `Task.detached` 里同步执行——预热（`updateThumbnailPreheating`）
    /// 在切换网格密度、滚动时频繁调用 `startCaching`/`stopCaching`，会反复占用
    /// Swift Concurrency 协作线程池，与查看器加载大图的 `Task.detached` 抢线程，
    /// 导致「切换密度变慢」「查看器打开被缩略图加载阻塞」。
    /// 现在统一经过 `ThumbnailLoadingQueue`（独立高并发队列）+ `assetCache`，
    /// 命中缓存（绝大多数重复预热场景）时零阻塞调用直接返回。
    private func systemPHAssets(from assets: [PhotoAsset]) async -> [PHAsset] {
        let localIdentifiers = assets
            .filter { $0.sourceID == PhotoSourceDescriptor.systemPhotosID }
            .map(\.localIdentifier)
        guard !localIdentifiers.isEmpty else { return [] }

        var resolved: [PHAsset] = []
        var missing: [String] = []
        for identifier in localIdentifiers {
            if let cached = assetCache.object(forKey: identifier as NSString) {
                resolved.append(cached)
            } else {
                missing.append(identifier)
            }
        }

        guard !missing.isEmpty else { return resolved }

        // 注意：`missing` 是外层的 `var`，不能直接被 `@Sendable` 闭包捕获
        // （"Reference to captured var 'missing' in concurrently-executing code"）；
        // 拷贝成 `let` 常量数组（`[String]` 是 `Sendable`）后再捕获。
        // `assetCache`（`NSCache`，非 `Sendable`）同理不在闭包内捕获——
        // `fetchAssets` 仅在闭包内做查找，缓存写入挪到闭包返回之后、
        // 在本方法（同一 actor 隔离域）内完成。
        let missingIdentifiers = missing
        let fetched = await ThumbnailLoadingQueue.run {
            var result: [PHAsset] = []
            let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: missingIdentifiers, options: nil)
            result.reserveCapacity(fetchResult.count)
            fetchResult.enumerateObjects { asset, _, _ in
                result.append(asset)
            }
            return result
        }
        for asset in fetched {
            assetCache.setObject(asset, forKey: asset.localIdentifier as NSString)
        }
        resolved.append(contentsOf: fetched)
        return resolved
    }
}

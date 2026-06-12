import Foundation

/// 照片源类型。
public enum PhotoSourceKind: String, Codable, Sendable, CaseIterable, Identifiable {
    case systemPhotos = "system_photos"
    case localDirectory = "local_directory"
    case externalLibrary = "external_library"

    public var id: String { rawValue }

    public var localizationKey: String {
        switch self {
        case .systemPhotos: "Source System Photos"
        case .localDirectory: "Source Local Directory"
        case .externalLibrary: "Source External Library"
        }
    }

    /// 是否能写回系统图库（收藏 / 删除走 PhotoKit）。仅系统图库可以。
    public var supportsSystemWriteBack: Bool { self == .systemPhotos }

    /// 是否基于文件系统（需要安全作用域书签）。
    public var isFileBased: Bool { self != .systemPhotos }
}

/// 照片源描述符（持久化在 `photo_sources` 表，运行时在内存里）。
public struct PhotoSourceDescriptor: Identifiable, Equatable, Sendable {
    public static let systemPhotosID = PhotoAsset.systemPhotosSourceID

    public var id: String
    public var kind: PhotoSourceKind
    public var displayName: String
    /// 本地 / 外部源：根目录的安全作用域书签。
    public var rootBookmark: Data?
    /// 本地 / 外部源：根目录路径（仅展示用）。
    public var rootPath: String?
    public var isEnabled: Bool

    public init(
        id: String,
        kind: PhotoSourceKind,
        displayName: String,
        rootBookmark: Data? = nil,
        rootPath: String? = nil,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.kind = kind
        self.displayName = displayName
        self.rootBookmark = rootBookmark
        self.rootPath = rootPath
        self.isEnabled = isEnabled
    }

    /// 内置系统图库源描述符。
    public static let systemPhotos = PhotoSourceDescriptor(
        id: systemPhotosID,
        kind: .systemPhotos,
        displayName: "系统图库",
        isEnabled: true
    )
}

/// 缩略图请求句柄：抽象掉 `PHImageRequestID`，让系统源（PhotoKit）与本地源（Task）统一可取消。
/// 仅在主线程使用。
public final class ThumbnailRequestToken: @unchecked Sendable {
    private var onCancel: (() -> Void)?
    private var isCancelled = false
    private let lock = NSLock()

    public init(onCancel: (() -> Void)? = nil) {
        self.onCancel = onCancel
    }

    public func setOnCancel(_ onCancel: @escaping () -> Void) {
        lock.lock()
        let shouldCancel = isCancelled
        if !shouldCancel {
            self.onCancel = onCancel
        }
        lock.unlock()
        
        if shouldCancel {
            onCancel()
        }
    }

    public func cancel() {
        lock.lock()
        guard !isCancelled else {
            lock.unlock()
            return
        }
        isCancelled = true
        let action = onCancel
        lock.unlock()
        
        action?()
    }
}

/// 照片源运行时注册表：把 sourceID 映射到「类型」与「已解析的安全作用域根目录 URL」。
///
/// 由 `AppState` 在 bootstrap 时填充（解析书签并 `startAccessingSecurityScopedResource`）。
/// 缩略图提供者、查看器、评分图像加载器都通过它做路由，从而不必把各 source 设为 `@MainActor`。
/// 用 `NSLock` 保护，可跨线程读取。
public final class PhotoSourceRegistry: @unchecked Sendable {
    public static let shared = PhotoSourceRegistry()

    private let lock = NSLock()
    private var kinds: [String: PhotoSourceKind] = [PhotoSourceDescriptor.systemPhotosID: .systemPhotos]
    private var roots: [String: URL] = [:]

    private init() {}

    public func register(descriptor: PhotoSourceDescriptor, resolvedRoot: URL?) {
        lock.lock(); defer { lock.unlock() }
        kinds[descriptor.id] = descriptor.kind
        if let resolvedRoot {
            roots[descriptor.id] = resolvedRoot
        }
    }

    public func unregister(sourceID: String) {
        lock.lock(); defer { lock.unlock() }
        kinds[sourceID] = nil
        roots[sourceID] = nil
    }

    public func kind(forSourceID id: String) -> PhotoSourceKind {
        lock.lock(); defer { lock.unlock() }
        return kinds[id] ?? .systemPhotos
    }

    public func rootURL(forSourceID id: String) -> URL? {
        lock.lock(); defer { lock.unlock() }
        return roots[id]
    }

    public func fileURL(forSourceID id: String, relativePath: String) -> URL? {
        guard let root = rootURL(forSourceID: id) else { return nil }
        return root.appending(path: relativePath)
    }

    /// 解析某资产对应的本地文件 URL（系统源返回 nil）。
    public func fileURL(for asset: PhotoAsset) -> URL? {
        guard asset.sourceID != PhotoSourceDescriptor.systemPhotosID else { return nil }
        let relative = asset.relativePath ?? asset.sourceAssetKey
        return fileURL(forSourceID: asset.sourceID, relativePath: relative)
    }
}

public enum PhotoSourceError: Error, LocalizedError {
    case fileNotFound(String)
    case unsupportedOperation(String)
    case bookmarkResolutionFailed(String)
    case thumbnailGenerationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let path): "找不到文件：\(path)"
        case .unsupportedOperation(let op): "当前照片源不支持该操作：\(op)"
        case .bookmarkResolutionFailed(let name): "无法访问照片源目录（书签失效）：\(name)"
        case .thumbnailGenerationFailed(let path): "无法生成缩略图：\(path)"
        }
    }
}

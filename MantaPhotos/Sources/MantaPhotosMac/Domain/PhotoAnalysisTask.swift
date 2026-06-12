import Foundation

/// 五类分析任务。
public enum AnalysisKind: String, CaseIterable, Identifiable, Sendable {
    case aesthetics       // 美学评分（复用现有评分引擎）
    case tagging          // 自动标签（Vision 场景分类）
    case geocoding        // 地理位置 → 地名
    case typeAnalysis     // 类型 / RAW
    case vectorIndex      // 向量索引（语义搜索）

    public var id: String { rawValue }

    /// 写入 photo_analysis_state 的 kind（仅 tagging/geocoding/type 使用）。
    public var stateKey: String {
        switch self {
        case .tagging: "tagging"
        case .geocoding: "geocoding"
        case .typeAnalysis: "type"
        case .aesthetics: "aesthetics"
        case .vectorIndex: "vector"
        }
    }

    public var localizationKey: String {
        switch self {
        case .aesthetics: "Task Aesthetics"
        case .tagging: "Task Tagging"
        case .geocoding: "Task Geocoding"
        case .typeAnalysis: "Task Type"
        case .vectorIndex: "Task Vector"
        }
    }

    public var fallbackName: String {
        switch self {
        case .aesthetics: "美学评分"
        case .tagging: "自动标签"
        case .geocoding: "地理位置"
        case .typeAnalysis: "类型分析"
        case .vectorIndex: "向量索引"
        }
    }

    public var iconName: String {
        switch self {
        case .aesthetics: "sparkles"
        case .tagging: "tag"
        case .geocoding: "mappin.and.ellipse"
        case .typeAnalysis: "photo.on.rectangle.angled"
        case .vectorIndex: "point.3.connected.trianglepath.dotted"
        }
    }
}

/// 单个任务的进度。
public struct TaskProgress: Equatable, Sendable {
    public enum Status: String, Sendable {
        case idle, queued, running, paused, stopping, completed, failed
    }

    public var status: Status = .idle
    public var completed: Int = 0
    public var total: Int = 0
    public var failed: Int = 0

    public var isActive: Bool { status == .running || status == .paused || status == .stopping || status == .queued }
    public var isRunning: Bool { status == .running }
    public var fraction: Double { total > 0 ? Double(completed) / Double(total) : 0 }

    public static let idle = TaskProgress()
}

/// 一张待分析照片的定位信息。
public struct AnalysisTarget: Sendable, Equatable {
    public var id: String
    public var sourceID: String
    public var localIdentifier: String
    public var relativePath: String?
    public var mediaType: MediaType
    public var isScreenshot: Bool

    public var isSystemPhotos: Bool { sourceID == PhotoAsset.systemPhotosSourceID }
}

/// 分析处理器：统一「待处理计数 / 取下一批 / 处理一批」三步。
public protocol PhotoAnalysisProcessor: Sendable {
    var kind: AnalysisKind { get }
    func countPending() throws -> Int
    func nextBatch(limit: Int) throws -> [AnalysisTarget]
    /// 计算 + 落库 + 标记完成。返回成功处理的数量。
    func process(_ targets: [AnalysisTarget]) async throws -> Int
}

/// 跨源取图（复用系统 PhotoKit / 本地文件）。
public struct AssetImageLoader: Sendable {
    public init() {}

    public func imageData(for target: AnalysisTarget) async throws -> Data {
        if target.isSystemPhotos {
            return try await PhotoLibraryAdapter().requestImageData(localIdentifier: target.localIdentifier)
        }
        guard let url = PhotoSourceRegistry.shared.fileURL(
            forSourceID: target.sourceID,
            relativePath: target.relativePath ?? target.localIdentifier
        ) else {
            throw PhotoSourceError.fileNotFound(target.id)
        }
        return try await LocalMediaProvider().imageData(fileURL: url)
    }
}

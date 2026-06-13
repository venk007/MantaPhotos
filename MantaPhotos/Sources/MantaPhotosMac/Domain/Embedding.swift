import Foundation
import Vision

/// 向量模态。
public enum EmbeddingModality: String, Codable, Sendable {
    case image
    case text
    case multimodal
}

/// 一个向量空间的描述（= 一个模型 + 维度 + 模态）。
///
/// 不同模型向量长度不同，因此「空间」是隔离单位：存储与检索都按空间进行，
/// 保证语义搜索只用指定模型产出的向量。
public struct EmbeddingSpaceDescriptor: Sendable, Equatable, Identifiable {
    public var key: String              // 稳定模型标识，用作 embedding_spaces.model_key
    public var displayName: String
    public var dimension: Int
    public var modality: EmbeddingModality
    public var supportsTextQuery: Bool  // 能否把文字查询嵌入到与图片同一空间（决定是否支持文字语义搜索）
    public var isAvailable: Bool        // 当前模型是否就绪可用

    public var id: String { key }

    public init(
        key: String,
        displayName: String,
        dimension: Int,
        modality: EmbeddingModality,
        supportsTextQuery: Bool,
        isAvailable: Bool
    ) {
        self.key = key
        self.displayName = displayName
        self.dimension = dimension
        self.modality = modality
        self.supportsTextQuery = supportsTextQuery
        self.isAvailable = isAvailable
    }
}

public enum EmbeddingError: Error, LocalizedError {
    case unsupportedTextQuery(String)
    case providerUnavailable(String)
    case noObservation
    case decodeFailed

    public var errorDescription: String? {
        switch self {
        case .unsupportedTextQuery(let key): "该向量模型不支持文字语义搜索：\(key)"
        case .providerUnavailable(let key): "向量模型尚未接入：\(key)"
        case .noObservation: "Vision 未返回特征向量。"
        case .decodeFailed: "向量解码失败。"
        }
    }
}

/// 向量计算策略接口：与具体模型 / 维度 / 模态无关。
///
/// 现接入 Apple 图像特征向量；预留 MobileCLIP / MLX / JINA V5 等（文字↔图片）。
/// 后续接入新模型只需新增一个 `EmbeddingProvider` 实现并在注册表登记。
public protocol EmbeddingProvider: Sendable {
    var descriptor: EmbeddingSpaceDescriptor { get }
    /// 图片 → 向量。
    func imageEmbedding(imageData: Data) async throws -> [Float]
    /// 文字 → 向量（仅 `supportsTextQuery` 为 true 的模型实现；默认抛不支持）。
    func textEmbedding(query: String) async throws -> [Float]
}

public extension EmbeddingProvider {
    func textEmbedding(query: String) async throws -> [Float] {
        throw EmbeddingError.unsupportedTextQuery(descriptor.key)
    }
}

/// Apple 图像特征向量（`VNGenerateImageFeaturePrintRequest`）。系统自带、无需模型文件。
/// 仅图像模态 → 支持「相似照片 / 以图搜图」，不支持文字查询。
public struct AppleFeaturePrintProvider: EmbeddingProvider {
    public let descriptor = EmbeddingSpaceDescriptor(
        key: "apple.featureprint",
        displayName: "Apple 图像特征向量",
        dimension: 768,
        modality: .image,
        supportsTextQuery: false,
        isAvailable: true
    )

    public init() {}

    public func imageEmbedding(imageData: Data) async throws -> [Float] {
        try await Task.detached(priority: .utility) {
            let request = VNGenerateImageFeaturePrintRequest()
            let handler = VNImageRequestHandler(data: imageData, options: [:])
            try handler.perform([request])
            guard let observation = request.results?.first as? VNFeaturePrintObservation else {
                throw EmbeddingError.noObservation
            }
            return try Self.decode(observation: observation)
        }.value
    }

    private static func decode(observation: VNFeaturePrintObservation) throws -> [Float] {
        let count = observation.elementCount
        let data = observation.data
        switch observation.elementType {
        case .float:
            return data.withUnsafeBytes { raw -> [Float] in
                Array(raw.bindMemory(to: Float.self).prefix(count))
            }
        case .double:
            return data.withUnsafeBytes { raw -> [Float] in
                raw.bindMemory(to: Double.self).prefix(count).map { Float($0) }
            }
        default:
            throw EmbeddingError.decodeFailed
        }
    }
}

/// 尚未接入的占位提供者（在设置里以「待接入」展示）。
public struct ReservedEmbeddingProvider: EmbeddingProvider {
    public let descriptor: EmbeddingSpaceDescriptor
    public init(descriptor: EmbeddingSpaceDescriptor) { self.descriptor = descriptor }
    public func imageEmbedding(imageData: Data) async throws -> [Float] {
        throw EmbeddingError.providerUnavailable(descriptor.key)
    }
}

/// 向量模型注册表。内置 Apple；用户可导入本地 MLX 模型目录注册为「自定义模型」。
public enum EmbeddingProviderRegistry {
    public static let defaultKey = "apple.featureprint"

    private static let lock = NSLock()
    nonisolated(unsafe) private static var custom: (config: CustomVectorModelConfig, url: URL)?

    /// 注册 / 清除用户导入的本地 MLX 模型（resolvedURL 为已开启安全作用域的目录）。
    public static func registerCustom(config: CustomVectorModelConfig?, resolvedURL: URL?) {
        lock.lock(); defer { lock.unlock() }
        if let config, let resolvedURL { custom = (config, resolvedURL) } else { custom = nil }
    }

    public static func customDescriptor() -> EmbeddingSpaceDescriptor? {
        lock.lock(); defer { lock.unlock() }
        return custom?.config.descriptor
    }

    public static var allDescriptors: [EmbeddingSpaceDescriptor] {
        var all = [AppleFeaturePrintProvider().descriptor]
        if let custom = customDescriptor() { all.append(custom) }
        return all
    }

    public static func provider(forKey key: String) -> EmbeddingProvider {
        if key == defaultKey { return AppleFeaturePrintProvider() }
        lock.lock()
        let custom = custom
        lock.unlock()
        if let custom, custom.config.key == key {
            return CustomMLXEmbeddingProvider(descriptor: custom.config.descriptor, modelDirectory: custom.url)
        }
        return AppleFeaturePrintProvider()
    }
}

/// 向量数学与编解码（暴力 KNN 用；sqlite-vec 作为后续性能优化）。
public enum VectorMath {
    /// L2 归一化为单位向量。零向量原样返回。
    ///
    /// 入库前统一归一化，配合 `vec0` 的 `distance_metric=cosine`，使
    /// sqlite-vec 距离与暴力 `cosineSimilarity` 口径一致，阈值方可标定。
    public static func normalized(_ vector: [Float]) -> [Float] {
        var norm: Float = 0
        for value in vector { norm += value * value }
        norm = norm.squareRoot()
        guard norm > 0 else { return vector }
        return vector.map { $0 / norm }
    }

    public static func cosineSimilarity(_ lhs: [Float], _ rhs: [Float]) -> Float {
        guard lhs.count == rhs.count, !lhs.isEmpty else { return -1 }
        var dot: Float = 0, normL: Float = 0, normR: Float = 0
        for index in 0..<lhs.count {
            dot += lhs[index] * rhs[index]
            normL += lhs[index] * lhs[index]
            normR += rhs[index] * rhs[index]
        }
        let denominator = normL.squareRoot() * normR.squareRoot()
        return denominator > 0 ? dot / denominator : -1
    }

    public static func data(from vector: [Float]) -> Data {
        vector.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    public static func vector(from data: Data, count: Int) -> [Float] {
        data.withUnsafeBytes { raw in
            Array(raw.bindMemory(to: Float.self).prefix(count))
        }
    }
}

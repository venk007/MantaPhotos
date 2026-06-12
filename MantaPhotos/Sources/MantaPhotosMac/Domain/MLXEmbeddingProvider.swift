import Foundation

/// 本地 MLX 向量模型的推理运行时。
///
/// 真实推理需在 Mac 上接入 `mlx-swift` + 具体模型（如 jina-embeddings-v5-omni）实现本协议，
/// 并把 `MLXRuntimeFactory.make` 指向该实现；未接入时使用 `UnavailableMLXRuntime`。
public protocol MLXEmbeddingRuntime: Sendable {
    func prepare(modelDirectory: URL) throws
    func imageEmbedding(imageData: Data) async throws -> [Float]
    func textEmbedding(query: String) async throws -> [Float]
}

public struct UnavailableMLXRuntime: MLXEmbeddingRuntime {
    public init() {}
    public func prepare(modelDirectory: URL) throws {
        throw EmbeddingError.providerUnavailable("MLX 运行时未接入（需在 Mac 上集成 mlx-swift）")
    }
    public func imageEmbedding(imageData: Data) async throws -> [Float] {
        throw EmbeddingError.providerUnavailable("MLX 运行时未接入")
    }
    public func textEmbedding(query: String) async throws -> [Float] {
        throw EmbeddingError.providerUnavailable("MLX 运行时未接入")
    }
}

/// 运行时注入点：Mac 接好 mlx-swift 后替换此闭包即可全局生效。
public enum MLXRuntimeFactory {
    nonisolated(unsafe) public static var make: @Sendable () -> MLXEmbeddingRuntime = { UnavailableMLXRuntime() }
}

/// 用户导入的本地 MLX 模型配置（持久化为 JSON）。
public struct CustomVectorModelConfig: Codable, Sendable, Equatable {
    public var key: String
    public var displayName: String
    public var dimension: Int
    public var supportsTextQuery: Bool
    public var path: String
    public var bookmark: Data

    public init(key: String, displayName: String, dimension: Int, supportsTextQuery: Bool, path: String, bookmark: Data) {
        self.key = key
        self.displayName = displayName
        self.dimension = dimension
        self.supportsTextQuery = supportsTextQuery
        self.path = path
        self.bookmark = bookmark
    }

    public var descriptor: EmbeddingSpaceDescriptor {
        EmbeddingSpaceDescriptor(
            key: key,
            displayName: displayName,
            dimension: dimension,
            modality: .multimodal,
            supportsTextQuery: supportsTextQuery,
            isAvailable: true
        )
    }
}

/// 指向本地模型目录的向量提供者（推理委托给注入的 MLX 运行时）。
public struct CustomMLXEmbeddingProvider: EmbeddingProvider {
    public let descriptor: EmbeddingSpaceDescriptor
    private let modelDirectory: URL
    private let runtime: MLXEmbeddingRuntime

    public init(descriptor: EmbeddingSpaceDescriptor, modelDirectory: URL) {
        self.descriptor = descriptor
        self.modelDirectory = modelDirectory
        self.runtime = MLXRuntimeFactory.make()
    }

    public func imageEmbedding(imageData: Data) async throws -> [Float] {
        try runtime.prepare(modelDirectory: modelDirectory)
        return try await runtime.imageEmbedding(imageData: imageData)
    }

    public func textEmbedding(query: String) async throws -> [Float] {
        try runtime.prepare(modelDirectory: modelDirectory)
        return try await runtime.textEmbedding(query: query)
    }
}

import CoreLocation
import Foundation
import ImageIO
import MapKit
@preconcurrency import Photos
import UniformTypeIdentifiers
import Vision

// MARK: - 自动标签（Vision 场景分类）

struct TaggingProcessor: PhotoAnalysisProcessor {
    let kind: AnalysisKind = .tagging
    let repository: AnalysisDataRepository
    let loader = AssetImageLoader()

    func countPending() throws -> Int { try repository.countPending(kind: kind.stateKey) }

    func nextBatch(limit: Int) throws -> [AnalysisTarget] {
        try repository.analysisTargets(ids: try repository.pendingPhotoIDs(kind: kind.stateKey, limit: limit))
    }

    func process(_ targets: [AnalysisTarget]) async throws -> Int {
        for target in targets {
            do {
                let data = try await loader.imageData(for: target)
                let labels = try await Self.classify(data: data)
                if !labels.isEmpty {
                    try repository.upsertTags(photoID: target.id, labels: labels)
                }
            } catch {
                // 取图/识别失败也标记，避免反复重试
            }
        }
        try repository.markAnalyzed(photoIDs: targets.map(\.id), kind: kind.stateKey)
        return targets.count
    }

    private static func classify(data: Data) async throws -> [(key: String, confidence: Double)] {
        try await Task.detached(priority: .utility) {
            let request = VNClassifyImageRequest()
            let handler = VNImageRequestHandler(data: data, options: [:])
            try handler.perform([request])
            let observations = (request.results ?? [])
                .filter { $0.confidence >= 0.1 }
                .prefix(8)
            return observations.map { (key: $0.identifier, confidence: Double($0.confidence)) }
        }.value
    }
}

// MARK: - 地理位置 → 地名

struct GeocodingProcessor: PhotoAnalysisProcessor {
    let kind: AnalysisKind = .geocoding
    let repository: AnalysisDataRepository
    let localeIdentifier: String

    func countPending() throws -> Int { try repository.countPending(kind: kind.stateKey) }

    func nextBatch(limit: Int) throws -> [AnalysisTarget] {
        // MKReverseGeocodingRequest 有限流（每次请求都是独立实例），单批取小一些。
        try repository.analysisTargets(ids: try repository.pendingPhotoIDs(kind: kind.stateKey, limit: min(limit, 20)))
    }

    func process(_ targets: [AnalysisTarget]) async throws -> Int {
        for target in targets {
            if let coordinate = coordinate(for: target) {
                if let info = await reverseGeocode(location: coordinate, localeID: localeIdentifier) {
                    try? repository.upsertLocation(
                        photoID: target.id,
                        latitude: coordinate.coordinate.latitude,
                        longitude: coordinate.coordinate.longitude,
                        country: info.country,
                        administrativeArea: info.administrativeArea,
                        locality: info.locality,
                        placeName: info.name
                    )
                }
                // 限流：每次反查后小憩，避免触发 MapKit 限流
                try? await Task.sleep(for: .milliseconds(300))
            }
        }
        try repository.markAnalyzed(photoIDs: targets.map(\.id), kind: kind.stateKey)
        return targets.count
    }

    private func coordinate(for target: AnalysisTarget) -> CLLocation? {
        if target.isSystemPhotos {
            let result = PHAsset.fetchAssets(withLocalIdentifiers: [target.localIdentifier], options: nil)
            return result.firstObject?.location
        }
        guard let url = PhotoSourceRegistry.shared.fileURL(
            forSourceID: target.sourceID,
            relativePath: target.relativePath ?? target.localIdentifier
        ) else { return nil }
        return Self.exifLocation(url: url)
    }

    /// 反查地理位置。
    /// 使用 MapKit 的 MKReverseGeocodingRequest (macOS 26+) 替代已废弃的 CLGeocoder，
    /// 并直接消费 MKMapItem / MKAddressRepresentations，避免接触已废弃的 MKPlacemark / CLPlacemark。
    private func reverseGeocode(location: CLLocation, localeID: String) async -> GeocodedLocation? {
        guard let request = MKReverseGeocodingRequest(location: location) else { return nil }
        request.preferredLocale = Locale(identifier: localeID)
        // 在 MKMapItem 所在的 actor 上一次性提取所有字段，转成 Sendable 值类型后再传出，
        // 以避免 Swift 6 严格并发模式下跨 actor 传递非 Sendable 类型的问题。
        let locale = Locale(identifier: localeID)
        return await withCheckedContinuation { (continuation: CheckedContinuation<GeocodedLocation?, Never>) in
            request.getMapItems { items, _ in
                guard let item = items?.first else {
                    continuation.resume(returning: nil)
                    return
                }
                let representations = item.addressRepresentations
                // region 是 Locale.Region，identifier 通常是国家代码（如 "US" / "CN"）；
                // 用当前语言环境的 localizedString 把代码翻译成本地化国家名。
                let country: String?
                if let code = representations?.region?.identifier {
                    country = locale.localizedString(forRegionCode: code)
                } else {
                    country = nil
                }
                let info = GeocodedLocation(
                    name: item.name,
                    locality: representations?.cityName,
                    administrativeArea: representations?.regionName,
                    country: country
                )
                continuation.resume(returning: info)
            }
        }
    }

    private struct GeocodedLocation {
        let name: String?
        let locality: String?
        let administrativeArea: String?
        let country: String?
    }

    private static func exifLocation(url: URL) -> CLLocation? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let gps = properties[kCGImagePropertyGPSDictionary] as? [CFString: Any],
              let lat = gps[kCGImagePropertyGPSLatitude] as? Double,
              let lon = gps[kCGImagePropertyGPSLongitude] as? Double else {
            return nil
        }
        let latRef = (gps[kCGImagePropertyGPSLatitudeRef] as? String) ?? "N"
        let lonRef = (gps[kCGImagePropertyGPSLongitudeRef] as? String) ?? "E"
        let latitude = latRef == "S" ? -lat : lat
        let longitude = lonRef == "W" ? -lon : lon
        return CLLocation(latitude: latitude, longitude: longitude)
    }
}

// MARK: - 类型 / RAW

struct TypeProcessor: PhotoAnalysisProcessor {
    let kind: AnalysisKind = .typeAnalysis
    let repository: AnalysisDataRepository

    func countPending() throws -> Int { try repository.countPending(kind: kind.stateKey) }

    func nextBatch(limit: Int) throws -> [AnalysisTarget] {
        try repository.analysisTargets(ids: try repository.pendingPhotoIDs(kind: kind.stateKey, limit: limit))
    }

    func process(_ targets: [AnalysisTarget]) async throws -> Int {
        for target in targets {
            let raw = isRaw(target)
            if raw {
                try? repository.setRaw(photoID: target.id, isRaw: true)
            }
        }
        try repository.markAnalyzed(photoIDs: targets.map(\.id), kind: kind.stateKey)
        return targets.count
    }

    private func isRaw(_ target: AnalysisTarget) -> Bool {
        if target.isSystemPhotos {
            let result = PHAsset.fetchAssets(withLocalIdentifiers: [target.localIdentifier], options: nil)
            guard let asset = result.firstObject else { return false }
            for resource in PHAssetResource.assetResources(for: asset) {
                if let type = UTType(resource.uniformTypeIdentifier), type.conforms(to: .rawImage) {
                    return true
                }
            }
            return false
        }
        guard let url = PhotoSourceRegistry.shared.fileURL(
            forSourceID: target.sourceID,
            relativePath: target.relativePath ?? target.localIdentifier
        ) else { return false }
        if let type = UTType(filenameExtension: url.pathExtension.lowercased()) {
            return type.conforms(to: .rawImage)
        }
        return false
    }
}

// MARK: - 向量索引

struct VectorIndexProcessor: PhotoAnalysisProcessor {
    let kind: AnalysisKind = .vectorIndex
    let repository: AnalysisDataRepository
    let provider: EmbeddingProvider
    let loader = AssetImageLoader()

    var spaceKey: String { provider.descriptor.key }

    func countPending() throws -> Int { try repository.countPendingEmbedding(spaceKey: spaceKey) }

    func nextBatch(limit: Int) throws -> [AnalysisTarget] {
        try repository.analysisTargets(ids: try repository.pendingEmbeddingPhotoIDs(spaceKey: spaceKey, limit: limit))
    }

    func process(_ targets: [AnalysisTarget]) async throws -> Int {
        try repository.ensureSpace(provider.descriptor)
        var done = 0
        for target in targets {
            do {
                let data = try await loader.imageData(for: target)
                let vector = try await provider.imageEmbedding(imageData: data)
                try repository.upsertEmbedding(photoID: target.id, spaceKey: spaceKey, vector: vector)
                done += 1
            } catch {
                // 跳过失败项（无嵌入记录，下次仍会重试）
            }
        }
        try? repository.touchSpace(spaceKey)
        return done
    }
}

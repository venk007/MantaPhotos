@preconcurrency import AVFoundation
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
    /// 当前语言（决定标签展示语言：中文环境出中文标签，英文环境出英文标签）。
    let localeIdentifier: String
    let loader = AssetImageLoader()

    /// 标签匹配度阈值：仅保留 confidence ≥ 该值的高匹配标签。
    static let confidenceThreshold: Float = 0.3
    /// 内容标签上限：过阈值的标签按相似度降序排列，最多取前 5 个。
    /// 年份 / 日期 / 国家 / 城市不在此列——它们由照片自身的拍摄时间与地理信息直接查询得出，不写入标签表。
    static let maxTags = 5

    func countPending() throws -> Int { try repository.countPending(kind: kind.stateKey) }

    func nextBatch(limit: Int) throws -> [AnalysisTarget] {
        try repository.analysisTargets(ids: try repository.pendingPhotoIDs(kind: kind.stateKey, limit: limit))
    }

    func process(_ targets: [AnalysisTarget]) async throws -> Int {
        let locale = localeIdentifier
        for target in targets {
            do {
                let data = try await loader.imageData(for: target)
                let raw = try await Self.classify(data: data)
                // 单语言策略：当前语言下没有合适展示名的标签（如中文环境里无中文
                // 对应、也非公认英文术语的分类）直接丢弃，不写入标签表。
                let labels = raw.compactMap { item in
                    VisionTagLocalizer.displayName(forIdentifier: item.key, localeIdentifier: locale).map { name in
                        (key: item.key, displayName: name, confidence: item.confidence)
                    }
                }
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

    /// 仅返回匹配度过阈值的标签（按置信度降序），最多 maxTags 个。
    private static func classify(data: Data) async throws -> [(key: String, confidence: Double)] {
        try await Task.detached(priority: .utility) {
            let request = VNClassifyImageRequest()
            let handler = VNImageRequestHandler(data: data, options: [:])
            try handler.perform([request])
            let observations = (request.results ?? [])
                .filter { $0.confidence >= confidenceThreshold }
                .sorted { $0.confidence > $1.confidence }
                .prefix(maxTags)
            return observations.map { (key: $0.identifier, confidence: Double($0.confidence)) }
        }.value
    }
}

// MARK: - 地理位置 → 地名（坐标聚类去重 + 限流 + 断点续跑）

struct GeocodingProcessor: PhotoAnalysisProcessor {
    let kind: AnalysisKind = .geocoding
    let repository: AnalysisDataRepository
    let localeIdentifier: String

    /// 坐标网格精度：小数位数。4 位 ≈ 10m 网格（同一地点只反查一次）。
    static let gridDecimals = 4
    /// 单个聚类反查的最大重试次数（跨会话累计；超过即视为终结，不再重试）。
    static let maxClusterRetry = 5
    /// 反查之间的限流间隔。
    static let throttle = Duration.milliseconds(1100)

    func countPending() throws -> Int { try repository.countPending(kind: kind.stateKey) }

    func nextBatch(limit: Int) throws -> [AnalysisTarget] {
        // 聚类去重已大幅降低请求量；单批可比旧实现略大，但仍保守。
        try repository.analysisTargets(ids: try repository.pendingPhotoIDs(kind: kind.stateKey, limit: min(limit, 40)))
    }

    func process(_ targets: [AnalysisTarget]) async throws -> Int {
        // 阶段一：提取 GPS（经纬度 + 海拔）→ 网格聚类 → 落 photo_locations。无 GPS 直接标记完成。
        var noGPS: [String] = []
        for target in targets where (try? repository.hasPhotoLocation(photoID: target.id)) != true {
            guard let location = await coordinate(for: target) else {
                noGPS.append(target.id)
                continue
            }
            let lat = location.coordinate.latitude
            let lon = location.coordinate.longitude
            let altitude: Double? = location.verticalAccuracy >= 0 ? location.altitude : nil
            let gridLat = Self.snap(lat)
            let gridLon = Self.snap(lon)
            let geohash = Geohash.encode(latitude: lat, longitude: lon, length: 9)
            if let cluster = try? repository.upsertCluster(gridLat: gridLat, gridLon: gridLon) {
                try? repository.upsertPhotoCoordinate(
                    photoID: target.id,
                    latitude: lat,
                    longitude: lon,
                    altitude: altitude,
                    geohash: geohash,
                    clusterID: cluster.id
                )
            }
        }

        // 阶段二：对这批照片所属、仍待反查的聚类（去重）限流反查；成功回填标签。
        let clusterIDs = (try? repository.pendingClusterIDs(
            forPhotoIDs: targets.map(\.id),
            maxRetry: Self.maxClusterRetry
        )) ?? []
        for clusterID in clusterIDs {
            guard let center = try? repository.clusterCenter(clusterID: clusterID) else { continue }
            let location = CLLocation(latitude: center.latitude, longitude: center.longitude)
            if let info = await reverseGeocode(location: location, localeID: localeIdentifier) {
                try? repository.markClusterDone(
                    clusterID: clusterID,
                    country: info.country,
                    countryCode: info.countryCode,
                    admin1: info.administrativeArea,
                    city: info.locality,
                    placeName: info.name
                )
                try? repository.backfillClusterToPhotos(clusterID: clusterID)
            } else {
                try? repository.markClusterFailed(clusterID: clusterID)
            }
            try? await Task.sleep(for: Self.throttle)
        }

        // 阶段三：标记「已完成」—— 无 GPS 的 + 聚类已终结（done 或 retry 耗尽）的。
        // 聚类仍 pending/failed-可重试 的照片不标记，留待下次会话重试（天然断点续跑）。
        var resolved = noGPS
        resolved += (try? repository.resolvedGeocodingPhotoIDs(
            forPhotoIDs: targets.map(\.id),
            maxRetry: Self.maxClusterRetry
        )) ?? []
        if !resolved.isEmpty {
            try repository.markAnalyzed(photoIDs: Array(Set(resolved)), kind: kind.stateKey)
        }
        return targets.count
    }

    /// 经纬度吸附到网格中心（按 gridDecimals 四舍五入）。
    private static func snap(_ value: Double) -> Double {
        let factor = pow(10.0, Double(gridDecimals))
        return (value * factor).rounded() / factor
    }

    private func coordinate(for target: AnalysisTarget) async -> CLLocation? {
        if target.isSystemPhotos {
            // 系统库的图片 / 视频都由 PhotoKit 直接给出 location（含海拔）。
            let result = PHAsset.fetchAssets(withLocalIdentifiers: [target.localIdentifier], options: nil)
            return result.firstObject?.location
        }
        guard let url = PhotoSourceRegistry.shared.fileURL(
            forSourceID: target.sourceID,
            relativePath: target.relativePath ?? target.localIdentifier
        ) else { return nil }
        if target.mediaType == .video {
            return await Self.videoLocation(url: url)
        }
        return Self.exifLocation(url: url)
    }

    /// 本地视频容器 GPS：读 AVMetadata 通用 location 项（ISO6709 字符串，含可选海拔）。
    private static func videoLocation(url: URL) async -> CLLocation? {
        let asset = AVURLAsset(url: url)
        guard let metadata = try? await asset.load(.commonMetadata) else { return nil }
        let items = AVMetadataItem.metadataItems(from: metadata, filteredByIdentifier: .commonIdentifierLocation)
        guard let item = items.first,
              let iso = try? await item.load(.stringValue) else {
            return nil
        }
        return parseISO6709(iso)
    }

    /// 解析 ISO6709 坐标串（如 "+34.0522-118.2437+085.000/"）。按出现顺序取 纬度 / 经度 / 海拔。
    private static func parseISO6709(_ string: String) -> CLLocation? {
        guard let regex = try? NSRegularExpression(pattern: #"[+-]\d+(?:\.\d+)?"#) else { return nil }
        let range = NSRange(string.startIndex..., in: string)
        let numbers: [Double] = regex.matches(in: string, range: range).compactMap { match in
            guard let r = Range(match.range, in: string) else { return nil }
            return Double(string[r])
        }
        guard numbers.count >= 2 else { return nil }
        let coordinate = CLLocationCoordinate2D(latitude: numbers[0], longitude: numbers[1])
        if numbers.count >= 3 {
            return CLLocation(
                coordinate: coordinate,
                altitude: numbers[2],
                horizontalAccuracy: kCLLocationAccuracyBest,
                // verticalAccuracy 必须 >= 0 才表示海拔有效（kCLLocationAccuracyBest = -1 是"无效"哨兵值，
                // 会被 GeocodingProcessor 的 `verticalAccuracy >= 0` 判断丢弃）。
                verticalAccuracy: 0,
                timestamp: Date()
            )
        }
        return CLLocation(latitude: numbers[0], longitude: numbers[1])
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
                let regionCode = representations?.region?.identifier
                let country: String? = regionCode.flatMap { locale.localizedString(forRegionCode: $0) }
                let info = GeocodedLocation(
                    name: item.name,
                    locality: representations?.cityName,
                    administrativeArea: representations?.regionName,
                    country: country,
                    countryCode: regionCode
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
        let countryCode: String?
    }

    /// 本地图片 EXIF → CLLocation（含海拔）。海拔取 GPSAltitude，AltitudeRef==1 表示海平面以下取负。
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
        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)

        // 海拔（可选）：有则构造带 altitude 的 CLLocation（verticalAccuracy>=0 表示有效）。
        if let altitudeValue = gps[kCGImagePropertyGPSAltitude] as? Double {
            let belowSeaLevel = (gps[kCGImagePropertyGPSAltitudeRef] as? Int) == 1
            let altitude = belowSeaLevel ? -altitudeValue : altitudeValue
            return CLLocation(
                coordinate: coordinate,
                altitude: altitude,
                horizontalAccuracy: kCLLocationAccuracyBest,
                // verticalAccuracy 必须 >= 0 才表示海拔有效（kCLLocationAccuracyBest = -1 是"无效"哨兵值，
                // 会被 GeocodingProcessor 的 `verticalAccuracy >= 0` 判断丢弃）。
                verticalAccuracy: 0,
                timestamp: Date()
            )
        }
        return CLLocation(latitude: latitude, longitude: longitude)
    }
}

// MARK: - Geohash 编码（无依赖实现，供地图聚合 / 附近查询）

enum Geohash {
    private static let base32 = Array("0123456789bcdefghjkmnpqrstuvwxyz")

    static func encode(latitude: Double, longitude: Double, length: Int = 9) -> String {
        var latRange = (-90.0, 90.0)
        var lonRange = (-180.0, 180.0)
        var hash = ""
        var bit = 0
        var ch = 0
        var even = true

        while hash.count < length {
            if even {
                let mid = (lonRange.0 + lonRange.1) / 2
                if longitude >= mid { ch |= (1 << (4 - bit)); lonRange.0 = mid } else { lonRange.1 = mid }
            } else {
                let mid = (latRange.0 + latRange.1) / 2
                if latitude >= mid { ch |= (1 << (4 - bit)); latRange.0 = mid } else { latRange.1 = mid }
            }
            even.toggle()
            if bit < 4 {
                bit += 1
            } else {
                hash.append(base32[ch])
                bit = 0
                ch = 0
            }
        }
        return hash
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

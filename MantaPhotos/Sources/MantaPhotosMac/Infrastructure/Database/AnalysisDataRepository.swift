import Foundation
import GRDB

/// 照片地名（用于查看器详情）。
public struct PhotoPlace: Equatable, Sendable {
    public var country: String?
    public var administrativeArea: String?
    public var locality: String?
    public var placeName: String?
    /// 海拔（米）。无 GPS 海拔信息时为 nil。
    public var altitude: Double?
    /// 原始坐标（地理编码未完成前也可展示）。
    public var latitude: Double?
    public var longitude: Double?

    /// 详情页地点展示：不再包含国家 / 省级行政区，只展示「城市名称 + 后续位置名称」
    /// （例如「杭州市 · 西湖区」而不是「中国 · 浙江省 · 杭州市 · 西湖区」）。
    /// 额外用一份兜底名单过滤掉极少数地理编码把「中国」「中国大陆」之类的国家级名称
    /// 错误填进 `locality`/`placeName` 字段的情况。
    public var displayLine: String {
        let countryLikeNames: Set<String> = ["中国", "中国大陆", "中华人民共和国", "China", "Mainland China", "People's Republic of China"]
        return [locality, placeName]
            .compactMap { $0?.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !countryLikeNames.contains($0) }
            .joined(separator: " · ")
    }
}

/// 坐标聚类引用（逆地理编码以聚类为单位去重）。
public struct CoordClusterRef: Sendable, Equatable {
    public var id: Int64
    public var status: String     // pending | done | failed
    public var retryCount: Int
}

/// 标签选项（用于 Find 标签筛选 UI）。
public struct PhotoTagOption: Identifiable, Equatable, Sendable {
    public var id: String          // tag_id
    public var displayName: String
    public var count: Int
}

/// 地点选项（用于 Find 地点筛选 UI），按城市（locality）聚合。
public struct PhotoLocationOption: Identifiable, Equatable, Sendable {
    public var name: String
    public var count: Int

    public var id: String { name }
    public var displayName: String { name }
}

/// 一条向量检索结果。
public struct VectorMatch: Equatable, Sendable {
    public var photoID: String
    public var score: Float
}

/// P2 分析数据仓储：向量空间 / 嵌入、标签、地名、类型、分析状态。
public struct AnalysisDataRepository: Sendable {
    public let databaseQueue: DatabaseQueue
    /// 仅对这些源的照片排队 / 计数分析任务（当前可访问的照片源）。nil = 不限制；空集 = 无可访问源。
    public let accessibleSourceIDs: Set<String>?

    public init(databaseQueue: DatabaseQueue, accessibleSourceIDs: Set<String>? = nil) {
        self.databaseQueue = databaseQueue
        self.accessibleSourceIDs = accessibleSourceIDs
    }

    /// 可访问源约束（含前导 " and "）。返回 nil 表示不追加；空集返回恒假，确保不挑选任何照片。
    private func sourceFilterSQL() -> (clause: String, args: [any DatabaseValueConvertible])? {
        guard let ids = accessibleSourceIDs else { return nil }
        guard !ids.isEmpty else { return (" and 1 = 0", []) }
        let placeholders = Array(repeating: "?", count: ids.count).joined(separator: ", ")
        return (" and photo_assets.source_id in (\(placeholders))", ids.map { $0 as any DatabaseValueConvertible })
    }

    // MARK: - 分析状态（标签/类型/地理位置 幂等标记）

    public func pendingPhotoIDs(kind: String, limit: Int) throws -> [String] {
        try databaseQueue.read { db in
            var sql =
                """
                select photo_assets.id
                from photo_assets
                where photo_assets.system_deleted_at is null
                  and not exists (
                    select 1 from photo_analysis_state s
                    where s.photo_id = photo_assets.id and s.kind = ?
                  )
                """
            var args: [any DatabaseValueConvertible] = [kind]
            if let filter = sourceFilterSQL() { sql += filter.clause; args += filter.args }
            sql += " order by photo_assets.creation_date desc nulls last limit ?;"
            args.append(limit)
            return try String.fetchAll(db, sql: sql, arguments: StatementArguments(args))
        }
    }

    public func countPending(kind: String) throws -> Int {
        try databaseQueue.read { db in
            var sql =
                """
                select count(*) from photo_assets
                where system_deleted_at is null
                  and not exists (
                    select 1 from photo_analysis_state s
                    where s.photo_id = photo_assets.id and s.kind = ?
                  )
                """
            var args: [any DatabaseValueConvertible] = [kind]
            if let filter = sourceFilterSQL() { sql += filter.clause; args += filter.args }
            return try Int.fetchOne(db, sql: sql + ";", arguments: StatementArguments(args)) ?? 0
        }
    }

    public func markAnalyzed(photoIDs: [String], kind: String) throws {
        guard !photoIDs.isEmpty else { return }
        let now = DateCoding.string(from: Date()) ?? ""
        try databaseQueue.write { db in
            for id in photoIDs {
                try db.execute(
                    sql: "insert or replace into photo_analysis_state(photo_id, kind, analyzed_at) values (?, ?, ?);",
                    arguments: [id, kind, now]
                )
            }
        }
    }

    /// 取一批照片的分析定位信息（保持传入顺序）。
    public func analysisTargets(ids: [String]) throws -> [AnalysisTarget] {
        guard !ids.isEmpty else { return [] }
        let placeholders = Array(repeating: "?", count: ids.count).joined(separator: ", ")
        let byID: [String: AnalysisTarget] = try databaseQueue.read { db in
            let rows = try Row.fetchAll(
                db,
                sql:
                    """
                    select id, source_id, local_identifier, relative_path, media_type,
                           media_subtypes_raw, device_category
                    from photo_assets
                    where id in (\(placeholders));
                    """,
                arguments: StatementArguments(ids)
            )
            var map: [String: AnalysisTarget] = [:]
            for row in rows {
                let id: String = row["id"]
                let mediaType = MediaType(rawValue: row["media_type"] as String) ?? .unknown
                let raw = UInt(row["media_subtypes_raw"] as Int64)
                let deviceCategory: String? = row["device_category"]
                let isScreenshot = (raw & 0x0000_0008) != 0 || deviceCategory == DeviceCategory.screenshot.rawValue
                map[id] = AnalysisTarget(
                    id: id,
                    sourceID: (row["source_id"] as String?) ?? PhotoAsset.systemPhotosSourceID,
                    localIdentifier: row["local_identifier"],
                    relativePath: row["relative_path"],
                    mediaType: mediaType,
                    isScreenshot: isScreenshot
                )
            }
            return map
        }
        return ids.compactMap { byID[$0] }
    }

    public func totalPhotoCount() throws -> Int {
        try databaseQueue.read { db in
            var sql = "select count(*) from photo_assets where system_deleted_at is null"
            var args: [any DatabaseValueConvertible] = []
            if let filter = sourceFilterSQL() { sql += filter.clause; args += filter.args }
            return try Int.fetchOne(db, sql: sql + ";", arguments: StatementArguments(args)) ?? 0
        }
    }

    public func countPendingScores() throws -> Int {
        try databaseQueue.read { db in
            var sql =
                """
                select count(*) from photo_assets
                where system_deleted_at is null
                  and not exists (select 1 from photo_scores where photo_scores.photo_id = photo_assets.id)
                """
            var args: [any DatabaseValueConvertible] = []
            if let filter = sourceFilterSQL() { sql += filter.clause; args += filter.args }
            return try Int.fetchOne(db, sql: sql + ";", arguments: StatementArguments(args)) ?? 0
        }
    }

    // MARK: - 类型 / RAW

    public func setRaw(photoID: String, isRaw: Bool) throws {
        try databaseQueue.write { db in
            try db.execute(
                sql: "update photo_assets set is_raw = ? where id = ?;",
                arguments: [isRaw ? 1 : 0, photoID]
            )
        }
    }

    public func isRaw(photoID: String) throws -> Bool {
        try databaseQueue.read { db in
            (try Int.fetchOne(db, sql: "select is_raw from photo_assets where id = ?;", arguments: [photoID]) ?? 0) == 1
        }
    }

    // MARK: - 地名

    public func upsertLocation(
        photoID: String,
        latitude: Double?,
        longitude: Double?,
        country: String?,
        administrativeArea: String?,
        locality: String?,
        placeName: String?
    ) throws {
        let now = DateCoding.string(from: Date()) ?? ""
        try databaseQueue.write { db in
            try db.execute(
                sql:
                    """
                    insert into photo_locations(
                      photo_id, latitude, longitude, country, administrative_area, locality, place_name, updated_at
                    )
                    values (?, ?, ?, ?, ?, ?, ?, ?)
                    on conflict(photo_id) do update set
                      latitude = excluded.latitude,
                      longitude = excluded.longitude,
                      country = excluded.country,
                      administrative_area = excluded.administrative_area,
                      locality = excluded.locality,
                      place_name = excluded.place_name,
                      updated_at = excluded.updated_at;
                    """,
                arguments: [photoID, latitude, longitude, country, administrativeArea, locality, placeName, now]
            )
        }
    }

    public func fetchPlace(photoID: String) throws -> PhotoPlace? {
        try databaseQueue.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: "select country, administrative_area, locality, place_name, altitude, latitude, longitude from photo_locations where photo_id = ?;",
                arguments: [photoID]
            ) else { return nil }
            let place = PhotoPlace(
                country: row["country"],
                administrativeArea: row["administrative_area"],
                locality: row["locality"],
                placeName: row["place_name"],
                altitude: row["altitude"],
                latitude: row["latitude"],
                longitude: row["longitude"]
            )
            // 地名 / 海拔 / 坐标任一存在即有效（地理编码未完成前可先展示坐标与海拔）。
            let hasCoordinate = place.latitude != nil && place.longitude != nil
            return (place.displayLine.isEmpty && place.altitude == nil && !hasCoordinate) ? nil : place
        }
    }

    // MARK: - 逆地理聚类（M2）

    /// 该照片是否已有位置记录（GPS 已提取）。
    public func hasPhotoLocation(photoID: String) throws -> Bool {
        try databaseQueue.read { db in
            (try Int.fetchOne(db, sql: "select 1 from photo_locations where photo_id = ?;", arguments: [photoID])) != nil
        }
    }

    /// 按网格坐标插入或取回聚类，返回其引用（含状态 / 重试次数）。
    public func upsertCluster(gridLat: Double, gridLon: Double) throws -> CoordClusterRef {
        let now = DateCoding.string(from: Date()) ?? ""
        return try databaseQueue.write { db in
            try db.execute(
                sql:
                    """
                    insert into coord_clusters(grid_lat, grid_lon, status, updated_at)
                    values (?, ?, 'pending', ?)
                    on conflict(grid_lat, grid_lon) do nothing;
                    """,
                arguments: [gridLat, gridLon, now]
            )
            let row = try Row.fetchOne(
                db,
                sql: "select id, status, retry_count from coord_clusters where grid_lat = ? and grid_lon = ?;",
                arguments: [gridLat, gridLon]
            )
            return CoordClusterRef(
                id: row?["id"] ?? 0,
                status: row?["status"] ?? "pending",
                retryCount: row?["retry_count"] ?? 0
            )
        }
    }

    /// 写入照片坐标 / 海拔 / geohash / 聚类引用（地名留空，待聚类反查后回填）。
    public func upsertPhotoCoordinate(
        photoID: String,
        latitude: Double,
        longitude: Double,
        altitude: Double?,
        geohash: String,
        clusterID: Int64
    ) throws {
        let now = DateCoding.string(from: Date()) ?? ""
        try databaseQueue.write { db in
            try db.execute(
                sql:
                    """
                    insert into photo_locations(photo_id, latitude, longitude, altitude, geohash, cluster_id, updated_at)
                    values (?, ?, ?, ?, ?, ?, ?)
                    on conflict(photo_id) do update set
                      latitude = excluded.latitude,
                      longitude = excluded.longitude,
                      altitude = excluded.altitude,
                      geohash = excluded.geohash,
                      cluster_id = excluded.cluster_id,
                      updated_at = excluded.updated_at;
                    """,
                arguments: [photoID, latitude, longitude, altitude, geohash, clusterID, now]
            )
        }
    }

    /// 取这批照片所属、仍需反查的聚类 id（status pending/failed 且 retry < maxRetry），去重。
    public func pendingClusterIDs(forPhotoIDs ids: [String], maxRetry: Int) throws -> [Int64] {
        guard !ids.isEmpty else { return [] }
        let placeholders = Array(repeating: "?", count: ids.count).joined(separator: ", ")
        return try databaseQueue.read { db in
            try Int64.fetchAll(
                db,
                sql:
                    """
                    select distinct c.id
                    from coord_clusters c
                    join photo_locations l on l.cluster_id = c.id
                    where l.photo_id in (\(placeholders))
                      and c.status in ('pending', 'failed')
                      and c.retry_count < ?
                    order by c.id;
                    """,
                arguments: StatementArguments(ids.map { $0 as any DatabaseValueConvertible } + [maxRetry as any DatabaseValueConvertible])
            )
        }
    }

    /// 聚类网格中心坐标。
    public func clusterCenter(clusterID: Int64) throws -> (latitude: Double, longitude: Double)? {
        try databaseQueue.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: "select grid_lat, grid_lon from coord_clusters where id = ?;",
                arguments: [clusterID]
            ) else { return nil }
            return (row["grid_lat"], row["grid_lon"])
        }
    }

    /// 反查成功：写回聚类地名并置 done。
    public func markClusterDone(
        clusterID: Int64,
        country: String?,
        countryCode: String?,
        admin1: String?,
        city: String?,
        placeName: String?
    ) throws {
        let now = DateCoding.string(from: Date()) ?? ""
        try databaseQueue.write { db in
            try db.execute(
                sql:
                    """
                    update coord_clusters set
                      country = ?, country_code = ?, admin1 = ?, city = ?, place_name = ?,
                      status = 'done', last_attempt = ?, updated_at = ?
                    where id = ?;
                    """,
                arguments: [country, countryCode, admin1, city, placeName, now, now, clusterID]
            )
        }
    }

    /// 反查失败：retry_count++ 并置 failed（跨会话重试，受 maxRetry 约束）。
    public func markClusterFailed(clusterID: Int64) throws {
        let now = DateCoding.string(from: Date()) ?? ""
        try databaseQueue.write { db in
            try db.execute(
                sql:
                    """
                    update coord_clusters set
                      status = 'failed', retry_count = retry_count + 1, last_attempt = ?, updated_at = ?
                    where id = ?;
                    """,
                arguments: [now, now, clusterID]
            )
        }
    }

    /// 把聚类地名回填到其下所有照片：① denormalize 到 photo_locations（查看器详情用）；
    /// ② 更新 FTS place 字段（关键词命中地名）。
    /// 国家 / 城市不再写入标签表 —— 由 photo_locations 直接查询得出（见 §3.1 标签设计）。
    public func backfillClusterToPhotos(clusterID: Int64) throws {
        let now = DateCoding.string(from: Date()) ?? ""
        try databaseQueue.write { db in
            guard let cluster = try Row.fetchOne(
                db,
                sql: "select country, admin1, city, place_name from coord_clusters where id = ?;",
                arguments: [clusterID]
            ) else { return }
            let country: String? = cluster["country"]
            let admin1: String? = cluster["admin1"]
            let city: String? = cluster["city"]
            let placeName: String? = cluster["place_name"]

            let photoIDs = try String.fetchAll(
                db,
                sql: "select photo_id from photo_locations where cluster_id = ?;",
                arguments: [clusterID]
            )
            let placeText = [country, admin1, city, placeName]
                .compactMap { $0?.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")

            for photoID in photoIDs {
                // ① denormalize 地名
                try db.execute(
                    sql:
                        """
                        update photo_locations set
                          country = ?, administrative_area = ?, locality = ?, place_name = ?, updated_at = ?
                        where photo_id = ?;
                        """,
                    arguments: [country, admin1, city, placeName, now, photoID]
                )
                // ② FTS place 字段
                try db.execute(
                    sql: "update photo_search_documents set place = ?, updated_at = ? where photo_id = ?;",
                    arguments: [placeText, now, photoID]
                )
            }
        }
    }

    /// 取这批照片中、聚类已终结（done 或 retry 耗尽）的照片 id —— 可标记为「地理编码已完成」。
    public func resolvedGeocodingPhotoIDs(forPhotoIDs ids: [String], maxRetry: Int) throws -> [String] {
        guard !ids.isEmpty else { return [] }
        let placeholders = Array(repeating: "?", count: ids.count).joined(separator: ", ")
        return try databaseQueue.read { db in
            try String.fetchAll(
                db,
                sql:
                    """
                    select l.photo_id
                    from photo_locations l
                    join coord_clusters c on c.id = l.cluster_id
                    where l.photo_id in (\(placeholders))
                      and (c.status = 'done' or c.retry_count >= ?);
                    """,
                arguments: StatementArguments(ids.map { $0 as any DatabaseValueConvertible } + [maxRetry as any DatabaseValueConvertible])
            )
        }
    }

    // MARK: - 标签

    /// 写入内容标签。`key` 为稳定的语言无关标识（如 Vision identifier）；`displayName` 为按当前语言本地化的展示名。
    public func upsertTags(photoID: String, labels: [(key: String, displayName: String, confidence: Double)]) throws {
        let now = DateCoding.string(from: Date()) ?? ""
        try databaseQueue.write { db in
            for label in labels {
                let tagID = "vision:\(label.key)"
                // display_name 随当前语言更新（同一 tagID 切换语言时刷新展示名）。
                try db.execute(
                    sql:
                        """
                        insert into tag_definitions(id, tag_key, display_name, category, source, created_at)
                        values (?, ?, ?, 'scene', 'vision', ?)
                        on conflict(id) do update set display_name = excluded.display_name;
                        """,
                    arguments: [tagID, label.key, label.displayName, now]
                )
                try db.execute(
                    sql:
                        """
                        insert into photo_tags(photo_id, tag_id, tag_source, confidence, created_at)
                        values (?, ?, 'vision', ?, ?)
                        on conflict(photo_id, tag_id, tag_source) do update set confidence = excluded.confidence;
                        """,
                    arguments: [photoID, tagID, label.confidence, now]
                )
            }
            // 更新搜索文档的 tags 字段：本地化展示名 + 英文 key，两种语言都能命中。
            let joined = labels.flatMap { [$0.displayName, $0.key] }.joined(separator: " ")
            try db.execute(
                sql: "update photo_search_documents set tags = ?, updated_at = ? where photo_id = ?;",
                arguments: [joined, now, photoID]
            )
        }
    }

    public func fetchTagNames(photoID: String) throws -> [String] {
        try databaseQueue.read { db in
            try String.fetchAll(
                db,
                sql:
                    """
                    select tag_definitions.display_name
                    from photo_tags
                    join tag_definitions on tag_definitions.id = photo_tags.tag_id
                    where photo_tags.photo_id = ?
                    order by photo_tags.confidence desc nulls last
                    limit 12;
                    """,
                arguments: [photoID]
            )
        }
    }

    /// 供 Find 标签筛选展示的高频标签。
    public func topTags(limit: Int = 40) throws -> [PhotoTagOption] {
        try databaseQueue.read { db in
            let rows = try Row.fetchAll(
                db,
                sql:
                    """
                    select tag_definitions.id as id, tag_definitions.display_name as name, count(*) as cnt
                    from photo_tags
                    join tag_definitions on tag_definitions.id = photo_tags.tag_id
                    group by tag_definitions.id
                    order by cnt desc
                    limit ?;
                    """,
                arguments: [limit]
            )
            return rows.map { PhotoTagOption(id: $0["id"], displayName: $0["name"], count: $0["cnt"]) }
        }
    }

    /// 供 Find 地点筛选展示的高频城市（按照片数量从高到低排序）。
    /// `limit` 传 -1 表示不限制（SQLite `LIMIT -1` = 不限制），用于「更多」展开全量列表。
    public func topLocalities(limit: Int = 20) throws -> [PhotoLocationOption] {
        try databaseQueue.read { db in
            let rows = try Row.fetchAll(
                db,
                sql:
                    """
                    select photo_locations.locality as locality, count(*) as cnt
                    from photo_locations
                    join photo_assets on photo_assets.id = photo_locations.photo_id
                    where photo_locations.locality is not null
                      and photo_locations.locality != ''
                      and photo_assets.system_deleted_at is null
                    group by photo_locations.locality
                    order by cnt desc
                    limit ?;
                    """,
                arguments: [limit]
            )
            return rows.map { PhotoLocationOption(name: $0["locality"], count: $0["cnt"]) }
        }
    }

    // MARK: - 向量空间 / 嵌入

    /// 确保向量空间存在并刷新元数据，返回 space id（= model_key）。
    @discardableResult
    public func ensureSpace(_ descriptor: EmbeddingSpaceDescriptor) throws -> String {
        let now = DateCoding.string(from: Date()) ?? ""
        try databaseQueue.write { db in
            try db.execute(
                sql:
                    """
                    insert into embedding_spaces(id, model_key, display_name, dimension, modality, last_used_at, created_at, updated_at)
                    values (?, ?, ?, ?, ?, ?, ?, ?)
                    on conflict(id) do update set
                      display_name = excluded.display_name,
                      dimension = excluded.dimension,
                      modality = excluded.modality,
                      last_used_at = excluded.last_used_at,
                      updated_at = excluded.updated_at;
                    """,
                arguments: [
                    descriptor.key, descriptor.key, descriptor.displayName,
                    descriptor.dimension, descriptor.modality.rawValue, now, now, now
                ]
            )
        }
        return descriptor.key
    }

    public func touchSpace(_ spaceKey: String) throws {
        let now = DateCoding.string(from: Date()) ?? ""
        try databaseQueue.write { db in
            try db.execute(
                sql: "update embedding_spaces set last_used_at = ?, updated_at = ? where id = ?;",
                arguments: [now, now, spaceKey]
            )
        }
    }

    public func upsertEmbedding(photoID: String, spaceKey: String, vector rawVector: [Float]) throws {
        let now = DateCoding.string(from: Date()) ?? ""
        // 入库前统一 L2 归一化：BLOB 规范副本与 sqlite-vec 索引都存单位向量，
        // 配合 cosine 表，两条 KNN 路径同口径（阈值可标定）。
        let vector = VectorMath.normalized(rawVector)
        let blob = VectorMath.data(from: vector)
        try databaseQueue.write { db in
            // 规范存储（兼容无扩展环境，也用于待处理判断）。
            try db.execute(
                sql:
                    """
                    insert into photo_embeddings(photo_id, space_id, dimension, vector, updated_at)
                    values (?, ?, ?, ?, ?)
                    on conflict(photo_id, space_id) do update set
                      dimension = excluded.dimension,
                      vector = excluded.vector,
                      updated_at = excluded.updated_at;
                    """,
                arguments: [photoID, spaceKey, vector.count, blob, now]
            )
            // 加速索引（sqlite-vec），供百万级 KNN 检索。
            if VectorIndexEnvironment.sqliteVecAvailable {
                try? SQLiteVecIndex.upsert(db, spaceKey: spaceKey, dimension: vector.count, photoID: photoID, vector: vector)
            }
        }
    }

    public func pendingEmbeddingPhotoIDs(spaceKey: String, limit: Int) throws -> [String] {
        try databaseQueue.read { db in
            var sql =
                """
                select photo_assets.id
                from photo_assets
                where photo_assets.system_deleted_at is null
                  and not exists (
                    select 1 from photo_embeddings e
                    where e.photo_id = photo_assets.id and e.space_id = ?
                  )
                """
            var args: [any DatabaseValueConvertible] = [spaceKey]
            if let filter = sourceFilterSQL() { sql += filter.clause; args += filter.args }
            sql += " order by photo_assets.creation_date desc nulls last limit ?;"
            args.append(limit)
            return try String.fetchAll(db, sql: sql, arguments: StatementArguments(args))
        }
    }

    public func countPendingEmbedding(spaceKey: String) throws -> Int {
        try databaseQueue.read { db in
            var sql =
                """
                select count(*) from photo_assets
                where system_deleted_at is null
                  and not exists (
                    select 1 from photo_embeddings e
                    where e.photo_id = photo_assets.id and e.space_id = ?
                  )
                """
            var args: [any DatabaseValueConvertible] = [spaceKey]
            if let filter = sourceFilterSQL() { sql += filter.clause; args += filter.args }
            return try Int.fetchOne(db, sql: sql + ";", arguments: StatementArguments(args)) ?? 0
        }
    }

    /// KNN：有 sqlite-vec 用扩展加速（百万级），否则降级暴力余弦。结果按相似度降序。
    ///
    /// - Parameters:
    ///   - limit: 候选池大小（KNN 必须给定 k）。当 `minScore` 非 nil 时，仅作为候选池上限，
    ///     最终返回数量由 `minScore` 过滤决定，不再二次截断。
    ///   - minScore: 相似度阈值；非 nil 时仅返回 `score >= minScore` 的结果（按降序排列，数量不限）。
    public func nearest(
        to query: [Float],
        spaceKey: String,
        limit: Int,
        minScore: Float? = nil,
        excluding excludeID: String? = nil
    ) throws -> [VectorMatch] {
        if VectorIndexEnvironment.sqliteVecAvailable {
            let matches = try databaseQueue.read { db in
                try SQLiteVecIndex.nearest(db, spaceKey: spaceKey, query: query, limit: limit + 1)
            }
            let filtered = matches.filter { $0.photoID != excludeID }
            if let minScore {
                return filtered.filter { $0.score >= minScore }
            }
            return Array(filtered.prefix(limit))
        }
        let rows = try databaseQueue.read { db in
            try Row.fetchAll(
                db,
                sql: "select photo_id, dimension, vector from photo_embeddings where space_id = ?;",
                arguments: [spaceKey]
            )
        }
        var matches: [VectorMatch] = []
        matches.reserveCapacity(rows.count)
        for row in rows {
            let photoID: String = row["photo_id"]
            if let excludeID, photoID == excludeID { continue }
            let dimension: Int = row["dimension"]
            let data: Data = row["vector"]
            let vector = VectorMath.vector(from: data, count: dimension)
            guard vector.count == query.count else { continue }
            matches.append(VectorMatch(photoID: photoID, score: VectorMath.cosineSimilarity(query, vector)))
        }
        matches.sort { $0.score > $1.score }
        if let minScore {
            return matches.filter { $0.score >= minScore }
        }
        return Array(matches.prefix(limit))
    }

    public func embedding(photoID: String, spaceKey: String) throws -> [Float]? {
        try databaseQueue.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: "select dimension, vector from photo_embeddings where photo_id = ? and space_id = ?;",
                arguments: [photoID, spaceKey]
            ) else { return nil }
            let dimension: Int = row["dimension"]
            let data: Data = row["vector"]
            return VectorMath.vector(from: data, count: dimension)
        }
    }

    /// 向量存储格式版本。升级此值即触发一次性全量重建。
    /// v2：vec0 改 `distance_metric=cosine` + 入库 L2 归一化（M1）。
    private static let vectorFormatVersion = "2"

    /// 若存储格式版本落后则清空所有向量空间，强制后台用新格式（cosine + 归一化）重建。
    /// 在 `VectorIndexEnvironment.probe` 之后、启动索引任务之前调用一次。
    public func migrateVectorFormatIfNeeded() throws {
        try databaseQueue.write { db in
            let current = try String.fetchOne(
                db,
                sql: "select value from app_settings where key = 'vector.formatVersion';"
            )
            guard current != Self.vectorFormatVersion else { return }

            // 清空规范副本与空间记录（待处理判断据此重新生成）。
            try db.execute(sql: "delete from photo_embeddings;")
            try db.execute(sql: "delete from embedding_spaces;")
            // drop 所有 vec0 虚拟表（影子表随之删除），下次 upsert 时按新 DDL 重建。
            let vecTables = try String.fetchAll(
                db,
                sql: "select name from sqlite_master where type = 'table' and sql like '%using vec0%';"
            )
            for name in vecTables {
                try? db.execute(sql: "drop table if exists \(name);")
            }

            let now = DateCoding.string(from: Date()) ?? ""
            try db.execute(
                sql:
                    """
                    insert into app_settings(key, value, updated_at)
                    values ('vector.formatVersion', ?, ?)
                    on conflict(key) do update set value = excluded.value, updated_at = excluded.updated_at;
                    """,
                arguments: [Self.vectorFormatVersion, now]
            )
        }
    }

    /// 标签格式版本。升级即清理旧标签并触发重跑。
    /// v2：阈值过滤 + 本地化展示名（随系统/应用语言）。
    /// v3：国家 / 城市不再作为标签存储（由 photo_locations 直接查询），清理历史遗留的 geo:* 标签；
    ///     内容标签上限改为 5。
    /// v4：标签改为单语言策略——中文环境下不再出现无中文对应的英文标签
    ///     （除非是 RAW / HDR 等业界公认的英文术语缩写），详见 `VisionTagLocalizer`。
    private static let tagFormatVersion = "4"

    /// 标签格式升级时：清理自动标签数据（内容 + 历史遗留的地点标签）、重置 tagging 状态以重跑。
    /// 国家 / 城市信息已 denormalize 在 photo_locations 中，不受此清理影响，无需重新回填。
    /// 在启动时调用一次（`probe` 之后、启动任务之前）。
    public func migrateTagFormatIfNeeded() throws {
        try databaseQueue.write { db in
            let current = try String.fetchOne(
                db,
                sql: "select value from app_settings where key = 'tags.formatVersion';"
            )
            guard current != Self.tagFormatVersion else { return }

            try db.execute(sql: "delete from photo_tags where tag_source in ('vision', 'geocode');")
            try db.execute(sql: "delete from tag_definitions where source in ('vision', 'geocode');")
            try db.execute(sql: "delete from photo_analysis_state where kind = 'tagging';")
            try db.execute(sql: "update photo_search_documents set tags = '';")

            let now = DateCoding.string(from: Date()) ?? ""
            try db.execute(
                sql:
                    """
                    insert into app_settings(key, value, updated_at)
                    values ('tags.formatVersion', ?, ?)
                    on conflict(key) do update set value = excluded.value, updated_at = excluded.updated_at;
                    """,
                arguments: [Self.tagFormatVersion, now]
            )
        }
    }

    /// 清空指定模型的全部向量数据（photo_embeddings + sqlite-vec 表 + 空间记录）。
    /// 用于切换 / 删除自定义模型、重建索引时清理脏数据。
    public func clearSpace(spaceKey: String) throws {
        try databaseQueue.write { db in
            try db.execute(sql: "delete from photo_embeddings where space_id = ?;", arguments: [spaceKey])
            try db.execute(sql: "delete from embedding_spaces where id = ?;", arguments: [spaceKey])
            if VectorIndexEnvironment.sqliteVecAvailable {
                try? SQLiteVecIndex.dropSpace(db, spaceKey: spaceKey)
            }
        }
    }

    /// 清理：删除非当前模型、且超过 `days` 天未使用的向量空间（含其 sqlite-vec 表与向量）。
    public func cleanupStaleSpaces(currentKey: String, days: Int = 30) throws {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) else { return }
        let cutoffString = DateCoding.string(from: cutoff) ?? ""
        try databaseQueue.write { db in
            let staleKeys = try String.fetchAll(
                db,
                sql: "select id from embedding_spaces where id <> ? and (last_used_at is null or last_used_at < ?);",
                arguments: [currentKey, cutoffString]
            )
            for key in staleKeys {
                try db.execute(sql: "delete from photo_embeddings where space_id = ?;", arguments: [key])
                if VectorIndexEnvironment.sqliteVecAvailable {
                    try? SQLiteVecIndex.dropSpace(db, spaceKey: key)
                }
            }
            try db.execute(
                sql: "delete from embedding_spaces where id <> ? and (last_used_at is null or last_used_at < ?);",
                arguments: [currentKey, cutoffString]
            )
        }
    }
}

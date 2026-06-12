import Foundation
import GRDB

/// 照片地名（用于查看器详情）。
public struct PhotoPlace: Equatable, Sendable {
    public var country: String?
    public var administrativeArea: String?
    public var locality: String?
    public var placeName: String?

    public var displayLine: String {
        [country, administrativeArea, locality, placeName]
            .compactMap { $0?.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }
}

/// 标签选项（用于 Find 标签筛选 UI）。
public struct PhotoTagOption: Identifiable, Equatable, Sendable {
    public var id: String          // tag_id
    public var displayName: String
    public var count: Int
}

/// 一条向量检索结果。
public struct VectorMatch: Equatable, Sendable {
    public var photoID: String
    public var score: Float
}

/// P2 分析数据仓储：向量空间 / 嵌入、标签、地名、类型、分析状态。
public struct AnalysisDataRepository: Sendable {
    public let databaseQueue: DatabaseQueue

    public init(databaseQueue: DatabaseQueue) {
        self.databaseQueue = databaseQueue
    }

    // MARK: - 分析状态（标签/类型/地理位置 幂等标记）

    public func pendingPhotoIDs(kind: String, limit: Int) throws -> [String] {
        try databaseQueue.read { db in
            try String.fetchAll(
                db,
                sql:
                    """
                    select photo_assets.id
                    from photo_assets
                    where photo_assets.system_deleted_at is null
                      and not exists (
                        select 1 from photo_analysis_state s
                        where s.photo_id = photo_assets.id and s.kind = ?
                      )
                    order by photo_assets.creation_date desc nulls last
                    limit ?;
                    """,
                arguments: [kind, limit]
            )
        }
    }

    public func countPending(kind: String) throws -> Int {
        try databaseQueue.read { db in
            try Int.fetchOne(
                db,
                sql:
                    """
                    select count(*) from photo_assets
                    where system_deleted_at is null
                      and not exists (
                        select 1 from photo_analysis_state s
                        where s.photo_id = photo_assets.id and s.kind = ?
                      );
                    """,
                arguments: [kind]
            ) ?? 0
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
            try Int.fetchOne(db, sql: "select count(*) from photo_assets where system_deleted_at is null;") ?? 0
        }
    }

    public func countPendingScores() throws -> Int {
        try databaseQueue.read { db in
            try Int.fetchOne(
                db,
                sql:
                    """
                    select count(*) from photo_assets
                    where system_deleted_at is null
                      and not exists (select 1 from photo_scores where photo_scores.photo_id = photo_assets.id);
                    """
            ) ?? 0
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
                sql: "select country, administrative_area, locality, place_name from photo_locations where photo_id = ?;",
                arguments: [photoID]
            ) else { return nil }
            let place = PhotoPlace(
                country: row["country"],
                administrativeArea: row["administrative_area"],
                locality: row["locality"],
                placeName: row["place_name"]
            )
            return place.displayLine.isEmpty ? nil : place
        }
    }

    // MARK: - 标签

    public func upsertTags(photoID: String, labels: [(key: String, confidence: Double)]) throws {
        let now = DateCoding.string(from: Date()) ?? ""
        try databaseQueue.write { db in
            for label in labels {
                let tagID = "vision:\(label.key)"
                try db.execute(
                    sql:
                        """
                        insert into tag_definitions(id, tag_key, display_name, category, source, created_at)
                        values (?, ?, ?, 'scene', 'vision', ?)
                        on conflict(id) do nothing;
                        """,
                    arguments: [tagID, label.key, label.key, now]
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
            // 更新搜索文档的 tags 字段（FTS 关键词搜索可命中标签）。
            let joined = labels.map(\.key).joined(separator: " ")
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

    public func upsertEmbedding(photoID: String, spaceKey: String, vector: [Float]) throws {
        let now = DateCoding.string(from: Date()) ?? ""
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
            try String.fetchAll(
                db,
                sql:
                    """
                    select photo_assets.id
                    from photo_assets
                    where photo_assets.system_deleted_at is null
                      and not exists (
                        select 1 from photo_embeddings e
                        where e.photo_id = photo_assets.id and e.space_id = ?
                      )
                    order by photo_assets.creation_date desc nulls last
                    limit ?;
                    """,
                arguments: [spaceKey, limit]
            )
        }
    }

    public func countPendingEmbedding(spaceKey: String) throws -> Int {
        try databaseQueue.read { db in
            try Int.fetchOne(
                db,
                sql:
                    """
                    select count(*) from photo_assets
                    where system_deleted_at is null
                      and not exists (
                        select 1 from photo_embeddings e
                        where e.photo_id = photo_assets.id and e.space_id = ?
                      );
                    """,
                arguments: [spaceKey]
            ) ?? 0
        }
    }

    /// KNN：有 sqlite-vec 用扩展加速（百万级），否则降级暴力余弦。结果高匹配靠前。
    public func nearest(to query: [Float], spaceKey: String, limit: Int, excluding excludeID: String? = nil) throws -> [VectorMatch] {
        if VectorIndexEnvironment.sqliteVecAvailable {
            let matches = try databaseQueue.read { db in
                try SQLiteVecIndex.nearest(db, spaceKey: spaceKey, query: query, limit: limit + 1)
            }
            return Array(matches.filter { $0.photoID != excludeID }.prefix(limit))
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

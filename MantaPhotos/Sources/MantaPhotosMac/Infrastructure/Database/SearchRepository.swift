import Foundation
import GRDB
import Photos

public struct PhotoSearchResult: Identifiable, Equatable, Sendable {
    public var id: String { asset.id }
    public var asset: PhotoAsset
    public var aestheticScore: Double?
    public var overallScore: Double?
    /// 相似照片检索的相似度（0~1，越大越相似）。仅在「相似照片」结果中非 nil，用于缩略图角标展示。
    public var similarityScore: Double?
    /// 是否为「相似照片」检索的基准照片本身（置于结果首位，缩略图角标展示为「原图」而非相似度）。
    public var isReferencePhoto: Bool = false

    public init(asset: PhotoAsset, aestheticScore: Double?, overallScore: Double?, similarityScore: Double? = nil, isReferencePhoto: Bool = false) {
        self.asset = asset
        self.aestheticScore = aestheticScore
        self.overallScore = overallScore
        self.similarityScore = similarityScore
        self.isReferencePhoto = isReferencePhoto
    }
}

public struct SearchRepository: Sendable {
    public let databaseQueue: DatabaseQueue
    /// 仅检索这些源的内容（当前可访问的照片源）。nil = 不限制；空集 = 无可访问源（不返回任何结果）。
    public let accessibleSourceIDs: Set<String>?

    public init(databaseQueue: DatabaseQueue, accessibleSourceIDs: Set<String>? = nil) {
        self.databaseQueue = databaseQueue
        self.accessibleSourceIDs = accessibleSourceIDs
    }

    /// 可访问源约束子句（含前导空格）与其参数。nil 表示不追加。
    private func sourceConstraint() -> (clause: String, args: [String])? {
        guard let ids = accessibleSourceIDs else { return nil }
        guard !ids.isEmpty else { return (" and 1 = 0", []) }
        let placeholders = Array(repeating: "?", count: ids.count).joined(separator: ", ")
        return (" and photo_assets.source_id in (\(placeholders))", Array(ids))
    }

    public func search(filter: SearchFilterState, limit: Int = 200, offset: Int = 0) throws -> [PhotoAsset] {
        try searchResults(filter: filter, limit: limit, offset: offset).map(\.asset)
    }

    public func searchIDs(filter: SearchFilterState, limit: Int? = nil) throws -> [String] {
        try databaseQueue.read { database in
            let selection = filter.makeSQLSelection()
            var sql =
                """
                select photo_assets.id
                from photo_assets
                left join photo_scores on photo_scores.photo_id = photo_assets.id
                where \(selection.whereClause)
                """

            var arguments = StatementArguments(selection.arguments.map(\.databaseValueConvertible))
            let keyword = filter.keyword.trimmingCharacters(in: .whitespacesAndNewlines)
            if !keyword.isEmpty {
                sql +=
                    """
                     and photo_assets.id in (
                       select photo_search_documents.photo_id
                       from photo_search_fts
                       join photo_search_documents
                         on photo_search_documents.id = photo_search_fts.rowid
                       where photo_search_fts match ?
                     )
                    """
                _ = arguments.append(contentsOf: StatementArguments([keyword]))
            }

            if let constraint = sourceConstraint() {
                sql += constraint.clause
                _ = arguments.append(contentsOf: StatementArguments(constraint.args))
            }

            sql += " order by \(selection.orderBy)"
            if let limit {
                sql += " limit ?"
                _ = arguments.append(contentsOf: StatementArguments([limit]))
            }

            return try String.fetchAll(database, sql: sql, arguments: arguments)
        }
    }

    public func searchResults(filter: SearchFilterState, limit: Int = 200, offset: Int = 0) throws -> [PhotoSearchResult] {
        try databaseQueue.read { database in
            let selection = filter.makeSQLSelection()
            var sql =
                """
                select
                  photo_assets.*,
                  photo_scores.aesthetic_score as score_aesthetic,
                  null as score_overall
                from photo_assets
                left join photo_scores on photo_scores.photo_id = photo_assets.id
                where \(selection.whereClause)
                """

            var arguments = StatementArguments(selection.arguments.map(\.databaseValueConvertible))

            let keyword = filter.keyword.trimmingCharacters(in: .whitespacesAndNewlines)
            if !keyword.isEmpty {
                sql +=
                    """
                     and photo_assets.id in (
                       select photo_search_documents.photo_id
                       from photo_search_fts
                       join photo_search_documents
                         on photo_search_documents.id = photo_search_fts.rowid
                       where photo_search_fts match ?
                     )
                    """
                _ = arguments.append(contentsOf: StatementArguments([keyword]))
            }

            if let constraint = sourceConstraint() {
                sql += constraint.clause
                _ = arguments.append(contentsOf: StatementArguments(constraint.args))
            }

            sql += " order by \(selection.orderBy) limit ? offset ?"
            _ = arguments.append(contentsOf: StatementArguments([limit, offset]))

            return try Row.fetchAll(database, sql: sql, arguments: arguments).map(Self.mapSearchResult(row:))
        }
    }

    /// 按 id 取结果并保持给定顺序（用于相似照片 / 向量检索结果）。
    public func results(forIDs ids: [String]) throws -> [PhotoSearchResult] {
        guard !ids.isEmpty else { return [] }
        return try databaseQueue.read { database in
            let placeholders = Array(repeating: "?", count: ids.count).joined(separator: ", ")
            var sql =
                """
                select
                  photo_assets.*,
                  photo_scores.aesthetic_score as score_aesthetic,
                  null as score_overall
                from photo_assets
                left join photo_scores on photo_scores.photo_id = photo_assets.id
                where photo_assets.id in (\(placeholders))
                  and photo_assets.system_deleted_at is null
                """
            var arguments = StatementArguments(ids)
            if let constraint = sourceConstraint() {
                sql += constraint.clause
                _ = arguments.append(contentsOf: StatementArguments(constraint.args))
            }
            let rows = try Row.fetchAll(database, sql: sql + ";", arguments: arguments)
            let byID = Dictionary(
                rows.map(Self.mapSearchResult(row:)).map { ($0.id, $0) },
                uniquingKeysWith: { lhs, _ in lhs }
            )
            return ids.compactMap { byID[$0] }
        }
    }

    public func count(filter: SearchFilterState) throws -> Int {
        try databaseQueue.read { database in
            let selection = filter.makeSQLSelection()
            var sql =
                """
                select count(*)
                from photo_assets
                left join photo_scores on photo_scores.photo_id = photo_assets.id
                where \(selection.whereClause)
                """

            var arguments = StatementArguments(selection.arguments.map(\.databaseValueConvertible))
            let keyword = filter.keyword.trimmingCharacters(in: .whitespacesAndNewlines)
            if !keyword.isEmpty {
                sql +=
                    """
                     and photo_assets.id in (
                       select photo_search_documents.photo_id
                       from photo_search_fts
                       join photo_search_documents
                         on photo_search_documents.id = photo_search_fts.rowid
                       where photo_search_fts match ?
                     )
                    """
                _ = arguments.append(contentsOf: StatementArguments([keyword]))
            }

            if let constraint = sourceConstraint() {
                sql += constraint.clause
                _ = arguments.append(contentsOf: StatementArguments(constraint.args))
            }

            return try Int.fetchOne(database, sql: sql, arguments: arguments) ?? 0
        }
    }

    private static func map(row: Row) -> PhotoAsset {
        let mediaType = MediaType(rawValue: row["media_type"] as String) ?? .unknown
        let mediaSubtypesRaw = UInt(row["media_subtypes_raw"] as Int64)
        let isLocallyAvailableInt: Int? = row["is_locally_available"]

        // 多源字段（migration 5 后存在；旧库读出可能为空，回落到系统源语义）。
        let sourceID: String = (row["source_id"] as String?) ?? PhotoAsset.systemPhotosSourceID
        let sourceAssetKey: String = (row["source_asset_key"] as String?) ?? (row["local_identifier"] as String)
        let relativePath: String? = row["relative_path"]
        let contentHash: String? = row["content_hash"]
        let fileSize: Int64? = row["file_size"]
        let deviceCategory: String? = row["device_category"]

        return PhotoAsset(
            id: row["id"],
            localIdentifier: row["local_identifier"],
            filename: row["filename"],
            mediaType: mediaType,
            mediaSubtypesRawValue: mediaSubtypesRaw,
            creationDate: DateCoding.date(from: row["creation_date"]),
            modificationDate: DateCoding.date(from: row["modification_date"]),
            width: row["width"],
            height: row["height"],
            duration: row["duration"],
            isFavorite: (row["is_favorite"] as Int) == 1,
            isHidden: (row["is_hidden"] as Int) == 1,
            inTrash: (row["in_trash"] as Int) == 1,
            trashedAt: DateCoding.date(from: row["trashed_at"]),
            iCloudState: ICloudState(rawValue: row["icloud_state"] as String) ?? .unknown,
            isLocallyAvailable: isLocallyAvailableInt.map { $0 == 1 },
            sourceID: sourceID,
            sourceAssetKey: sourceAssetKey,
            relativePath: relativePath,
            contentHash: contentHash,
            fileSize: fileSize,
            isScreenshotFlag: deviceCategory == DeviceCategory.screenshot.rawValue
        )
    }

    private static func mapSearchResult(row: Row) -> PhotoSearchResult {
        PhotoSearchResult(
            asset: map(row: row),
            aestheticScore: row["score_aesthetic"],
            overallScore: row["score_overall"]
        )
    }
}

private extension SQLValue {
    var databaseValueConvertible: (any DatabaseValueConvertible)? {
        switch self {
        case .int(let value):
            value
        case .double(let value):
            value
        case .text(let value):
            value
        case .null:
            nil
        }
    }
}

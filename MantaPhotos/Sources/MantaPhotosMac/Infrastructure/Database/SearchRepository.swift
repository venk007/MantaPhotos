import Foundation
import GRDB
import Photos

public struct PhotoSearchResult: Identifiable, Equatable, Sendable {
    public var id: String { asset.id }
    public var asset: PhotoAsset
    public var aestheticScore: Double?
    public var overallScore: Double?

    public init(asset: PhotoAsset, aestheticScore: Double?, overallScore: Double?) {
        self.asset = asset
        self.aestheticScore = aestheticScore
        self.overallScore = overallScore
    }
}

public struct SearchRepository: Sendable {
    public let databaseQueue: DatabaseQueue

    public init(databaseQueue: DatabaseQueue) {
        self.databaseQueue = databaseQueue
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

            sql += " order by \(selection.orderBy) limit ? offset ?"
            _ = arguments.append(contentsOf: StatementArguments([limit, offset]))

            return try Row.fetchAll(database, sql: sql, arguments: arguments).map(Self.mapSearchResult(row:))
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

            return try Int.fetchOne(database, sql: sql, arguments: arguments) ?? 0
        }
    }

    private static func map(row: Row) -> PhotoAsset {
        let mediaType = MediaType(rawValue: row["media_type"] as String) ?? .unknown
        let mediaSubtypesRaw = UInt(row["media_subtypes_raw"] as Int64)
        let isLocallyAvailableInt: Int? = row["is_locally_available"]

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
            isLocallyAvailable: isLocallyAvailableInt.map { $0 == 1 }
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

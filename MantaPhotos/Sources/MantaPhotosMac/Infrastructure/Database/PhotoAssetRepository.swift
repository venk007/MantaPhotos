import Foundation
import GRDB

public struct PhotoAssetRepository: Sendable {
    public let databaseQueue: DatabaseQueue

    public init(databaseQueue: DatabaseQueue) {
        self.databaseQueue = databaseQueue
    }

    public func upsert(_ assets: [PhotoAsset]) throws {
        try databaseQueue.write { database in
            let now = DateCoding.string(from: Date()) ?? ""
            for asset in assets {
                try upsert(asset, now: now, database: database)
                try upsertSearchDocument(for: asset, now: now, database: database)
            }
        }
    }

    public func updateFavorite(photoID: String, isFavorite: Bool) throws {
        try databaseQueue.write { database in
            try database.execute(
                sql:
                    """
                    update photo_assets
                    set is_favorite = ?, updated_at = ?
                    where id = ?;
                    """,
                arguments: [isFavorite ? 1 : 0, DateCoding.string(from: Date()) ?? "", photoID]
            )
        }
    }

    public func updateTrash(photoID: String, inTrash: Bool, trashedAt: Date?) throws {
        try databaseQueue.write { database in
            try database.execute(
                sql:
                    """
                    update photo_assets
                    set in_trash = ?, trashed_at = ?, updated_at = ?
                    where id = ?;
                    """,
                arguments: [
                    inTrash ? 1 : 0,
                    DateCoding.string(from: trashedAt),
                    DateCoding.string(from: Date()) ?? "",
                    photoID
                ]
            )
        }
    }

    public func markSystemDeleted(photoID: String, deletedAt: Date = Date()) throws {
        try databaseQueue.write { database in
            try database.execute(
                sql:
                    """
                    update photo_assets
                    set system_deleted_at = ?, updated_at = ?
                    where id = ?;
                    """,
                arguments: [
                    DateCoding.string(from: deletedAt),
                    DateCoding.string(from: Date()) ?? "",
                    photoID
                ]
            )
        }
    }

    private func upsert(_ asset: PhotoAsset, now: String, database: Database) throws {
        let sourceTypeRaw = asset.isSystemPhotos ? "photos_library" : "local_directory"
        let values: [(any DatabaseValueConvertible)?] = [
            asset.id,
            asset.localIdentifier,
            asset.filename,
            asset.mediaType.rawValue,
            Int64(asset.mediaSubtypesRawValue),
            DateCoding.string(from: asset.creationDate),
            DateCoding.string(from: asset.modificationDate),
            asset.width,
            asset.height,
            asset.duration,
            asset.isFavorite ? 1 : 0,
            asset.isHidden ? 1 : 0,
            asset.inTrash ? 1 : 0,
            DateCoding.string(from: asset.trashedAt),
            asset.iCloudState.rawValue,
            asset.isLocallyAvailable.map { $0 ? 1 : 0 },
            sourceTypeRaw,
            asset.isScreenshot ? DeviceCategory.screenshot.rawValue : DeviceCategory.unknown.rawValue,
            asset.sourceID,
            asset.sourceAssetKey,
            nil, // file_bookmark：源根目录安全作用域书签已覆盖子文件访问，暂不存每文件书签
            asset.relativePath,
            asset.contentHash,
            asset.fileSize,
            now,
            now
        ]

        try database.execute(
            sql:
                """
                insert into photo_assets(
                  id, local_identifier, filename, media_type, media_subtypes_raw,
                  creation_date, modification_date, width, height, duration,
                  is_favorite, is_hidden, in_trash, trashed_at, icloud_state,
                  is_locally_available, source_type, device_category,
                  source_id, source_asset_key, file_bookmark, relative_path, content_hash, file_size,
                  imported_at, updated_at
                )
                values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                on conflict(id) do update set
                  local_identifier = excluded.local_identifier,
                  filename = excluded.filename,
                  media_type = excluded.media_type,
                  media_subtypes_raw = excluded.media_subtypes_raw,
                  creation_date = excluded.creation_date,
                  modification_date = excluded.modification_date,
                  width = excluded.width,
                  height = excluded.height,
                  duration = excluded.duration,
                  is_favorite = excluded.is_favorite,
                  is_hidden = excluded.is_hidden,
                  icloud_state = excluded.icloud_state,
                  is_locally_available = excluded.is_locally_available,
                  source_type = excluded.source_type,
                  device_category = excluded.device_category,
                  source_id = excluded.source_id,
                  source_asset_key = excluded.source_asset_key,
                  file_bookmark = excluded.file_bookmark,
                  relative_path = excluded.relative_path,
                  content_hash = excluded.content_hash,
                  file_size = excluded.file_size,
                  updated_at = excluded.updated_at;
                """,
            arguments: StatementArguments(values)
        )
    }

    private func upsertSearchDocument(for asset: PhotoAsset, now: String, database: Database) throws {
        let metadata = [
            asset.mediaType.rawValue,
            "\(asset.width)x\(asset.height)",
            asset.creationDate.map { Calendar.current.component(.year, from: $0).description }
        ]
        .compactMap { $0 }
        .joined(separator: " ")

        let values: [(any DatabaseValueConvertible)?] = [
            asset.id,
            asset.filename ?? "",
            "",
            "",
            "",
            "",
            metadata,
            now
        ]

        try database.execute(
            sql:
                """
                insert into photo_search_documents(
                  photo_id, filename, tags, people, place, ai_text, metadata, updated_at
                )
                values (?, ?, ?, ?, ?, ?, ?, ?)
                on conflict(photo_id) do update set
                  filename = excluded.filename,
                  metadata = excluded.metadata,
                  updated_at = excluded.updated_at;
                """,
            arguments: StatementArguments(values)
        )
    }
}

import Foundation
import GRDB

/// `photo_sources` 表的读写。
public struct PhotoSourceRepository: Sendable {
    public let databaseQueue: DatabaseQueue

    public init(databaseQueue: DatabaseQueue) {
        self.databaseQueue = databaseQueue
    }

    public func allSources() throws -> [PhotoSourceDescriptor] {
        try databaseQueue.read { database in
            let rows = try Row.fetchAll(
                database,
                sql:
                    """
                    select id, kind, display_name, root_bookmark, root_path, is_enabled
                    from photo_sources
                    order by case when kind = 'system_photos' then 0 else 1 end, created_at asc;
                    """
            )
            return rows.compactMap(Self.map(row:))
        }
    }

    public func upsert(_ descriptor: PhotoSourceDescriptor) throws {
        let now = DateCoding.string(from: Date()) ?? ""
        try databaseQueue.write { database in
            try database.execute(
                sql:
                    """
                    insert into photo_sources(
                      id, kind, display_name, root_bookmark, root_path, is_enabled, created_at, updated_at
                    )
                    values (?, ?, ?, ?, ?, ?, ?, ?)
                    on conflict(id) do update set
                      kind = excluded.kind,
                      display_name = excluded.display_name,
                      root_bookmark = excluded.root_bookmark,
                      root_path = excluded.root_path,
                      is_enabled = excluded.is_enabled,
                      updated_at = excluded.updated_at;
                    """,
                arguments: [
                    descriptor.id,
                    descriptor.kind.rawValue,
                    descriptor.displayName,
                    descriptor.rootBookmark,
                    descriptor.rootPath,
                    descriptor.isEnabled ? 1 : 0,
                    now,
                    now
                ]
            )
        }
    }

    public func setEnabled(sourceID: String, isEnabled: Bool) throws {
        let now = DateCoding.string(from: Date()) ?? ""
        try databaseQueue.write { database in
            try database.execute(
                sql: "update photo_sources set is_enabled = ?, updated_at = ? where id = ?;",
                arguments: [isEnabled ? 1 : 0, now, sourceID]
            )
        }
    }

    public func updateRootBookmark(sourceID: String, bookmark: Data) throws {
        let now = DateCoding.string(from: Date()) ?? ""
        try databaseQueue.write { database in
            try database.execute(
                sql: "update photo_sources set root_bookmark = ?, updated_at = ? where id = ?;",
                arguments: [bookmark, now, sourceID]
            )
        }
    }

    /// 删除源及其全部资产（级联：photo_assets 行 + 依赖它们的评分 / 任务 / 搜索文档）。
    public func deleteSource(sourceID: String) throws {
        guard sourceID != PhotoSourceDescriptor.systemPhotosID else { return }
        try databaseQueue.write { database in
            // photo_search_documents / photo_scores / analysis_tasks 等都对 photo_assets(id) on delete cascade。
            try database.execute(
                sql: "delete from photo_assets where source_id = ?;",
                arguments: [sourceID]
            )
            try database.execute(
                sql: "delete from photo_sources where id = ?;",
                arguments: [sourceID]
            )
        }
    }

    public func assetCount(sourceID: String) throws -> Int {
        try databaseQueue.read { database in
            try Int.fetchOne(
                database,
                sql: "select count(*) from photo_assets where source_id = ?;",
                arguments: [sourceID]
            ) ?? 0
        }
    }

    private static func map(row: Row) -> PhotoSourceDescriptor? {
        guard let kind = PhotoSourceKind(rawValue: row["kind"] as String) else { return nil }
        return PhotoSourceDescriptor(
            id: row["id"],
            kind: kind,
            displayName: row["display_name"],
            rootBookmark: row["root_bookmark"],
            rootPath: row["root_path"],
            isEnabled: (row["is_enabled"] as Int) == 1
        )
    }
}

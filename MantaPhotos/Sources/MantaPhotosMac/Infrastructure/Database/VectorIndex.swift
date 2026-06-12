import Foundation
import GRDB

/// sqlite-vec 可用性（运行时探测一次）。
///
/// sqlite-vec 是 SQLite C 扩展，需在 Mac 上通过 SwiftPM 引入并注册（`sqlite3_vec_init` /
/// `sqlite3_auto_extension`）。未引入时探测失败，向量检索自动降级为暴力 KNN（小库可用）。
enum VectorIndexEnvironment {
    nonisolated(unsafe) static var sqliteVecAvailable = false

    static func probe(_ databaseQueue: DatabaseQueue) {
        // Swift 6 + GRDB 7 在 `try? + 多语句闭包` 场景下，闭包返回类型会被推断为
        // `(any (~Copyable & ~Escapable).Type)?` 而非 `Void`，导致 "missing return" 错误。
        // 用 do-catch 显式分支，避免依赖闭包返回类型推断。
        let ok: Bool
        do {
            try databaseQueue.write { db in
                try db.execute(sql: "create virtual table if not exists __vec_probe using vec0(id text primary key, v float[4]);")
                try db.execute(sql: "drop table if exists __vec_probe;")
            }
            ok = true
        } catch {
            ok = false
        }
        sqliteVecAvailable = ok
    }
}

/// sqlite-vec 索引：每个向量空间（模型 + 维度）一张 `vec0` 虚拟表，KNN 由扩展加速，支撑百万级检索。
enum SQLiteVecIndex {
    static func tableName(forSpace key: String) -> String {
        "vec_" + String(key.map { ($0.isLetter || $0.isNumber) ? $0 : "_" })
    }

    static func ensureTable(_ db: Database, spaceKey: String, dimension: Int) throws {
        let name = tableName(forSpace: spaceKey)
        try db.execute(
            sql: "create virtual table if not exists \(name) using vec0(photo_id text primary key, embedding float[\(dimension)]);"
        )
    }

    static func upsert(_ db: Database, spaceKey: String, dimension: Int, photoID: String, vector: [Float]) throws {
        try ensureTable(db, spaceKey: spaceKey, dimension: dimension)
        try db.execute(
            sql: "insert or replace into \(tableName(forSpace: spaceKey))(photo_id, embedding) values (?, ?);",
            arguments: [photoID, VectorMath.data(from: vector)]
        )
    }

    static func nearest(_ db: Database, spaceKey: String, query: [Float], limit: Int) throws -> [VectorMatch] {
        let rows = try Row.fetchAll(
            db,
            sql:
                """
                select photo_id, distance
                from \(tableName(forSpace: spaceKey))
                where embedding match ?
                order by distance
                limit ?;
                """,
            arguments: [VectorMath.data(from: query), limit]
        )
        // 距离越小越相似 → 取负作为分数，排序时高分（更相似）靠前。
        return rows.map { VectorMatch(photoID: $0["photo_id"], score: -Float($0["distance"] as Double)) }
    }

    static func dropSpace(_ db: Database, spaceKey: String) throws {
        try db.execute(sql: "drop table if exists \(tableName(forSpace: spaceKey));")
    }
}

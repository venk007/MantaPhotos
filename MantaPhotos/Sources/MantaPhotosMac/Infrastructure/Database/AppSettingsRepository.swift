import Foundation
import GRDB

struct AppSettingsRepository: Sendable {
    let databaseQueue: DatabaseQueue

    init(databaseQueue: DatabaseQueue) {
        self.databaseQueue = databaseQueue
    }

    func load() throws -> AppSettingsSnapshot {
        try databaseQueue.read { database in
            let rows = try Row.fetchAll(database, sql: "select key, value from app_settings;")
            var values: [String: String] = [:]
            for row in rows {
                values[row["key"]] = row["value"]
            }

            return AppSettingsSnapshot(
                themeMode: ThemeMode(rawValue: values["appearance.theme"] ?? "") ?? .system,
                appLanguage: AppLanguage(rawValue: values["appearance.language"] ?? "") ?? .system,
                gridLevel: GridLevel(rawValue: Int(values["photos.gridLevel"] ?? "") ?? GridLevel.default.rawValue) ?? .default,
                badgeMetric: BadgeMetric(rawValue: values["photos.badgeMetric"] ?? "") ?? .aesthetic,
                vectorModelKey: values["analysis.vectorModel"] ?? EmbeddingProviderRegistry.defaultKey
            )
        }
    }

    func save(_ snapshot: AppSettingsSnapshot) throws {
        try databaseQueue.write { database in
            let now = DateCoding.string(from: Date()) ?? ""
            let values = [
                ("appearance.theme", snapshot.themeMode.rawValue),
                ("appearance.language", snapshot.appLanguage.rawValue),
                ("photos.gridLevel", "\(snapshot.gridLevel.rawValue)"),
                ("photos.badgeMetric", snapshot.badgeMetric.rawValue),
                ("analysis.vectorModel", snapshot.vectorModelKey)
            ]

            for (key, value) in values {
                try database.execute(
                    sql:
                        """
                        insert into app_settings(key, value, updated_at)
                        values (?, ?, ?)
                        on conflict(key) do update set
                          value = excluded.value,
                          updated_at = excluded.updated_at;
                        """,
                    arguments: [key, value, now]
                )
            }
        }
    }
}

extension AppSettingsRepository {
    private static let customModelKey = "analysis.customModel"

    func loadCustomVectorModel() throws -> CustomVectorModelConfig? {
        try databaseQueue.read { database in
            guard let json = try String.fetchOne(
                database,
                sql: "select value from app_settings where key = ?;",
                arguments: [Self.customModelKey]
            ), let data = json.data(using: .utf8) else { return nil }
            return try? JSONDecoder().decode(CustomVectorModelConfig.self, from: data)
        }
    }

    func saveCustomVectorModel(_ config: CustomVectorModelConfig?) throws {
        let now = DateCoding.string(from: Date()) ?? ""
        try databaseQueue.write { database in
            guard let config,
                  let data = try? JSONEncoder().encode(config),
                  let json = String(data: data, encoding: .utf8) else {
                try database.execute(sql: "delete from app_settings where key = ?;", arguments: [Self.customModelKey])
                return
            }
            try database.execute(
                sql:
                    """
                    insert into app_settings(key, value, updated_at) values (?, ?, ?)
                    on conflict(key) do update set value = excluded.value, updated_at = excluded.updated_at;
                    """,
                arguments: [Self.customModelKey, json, now]
            )
        }
    }
}

struct AppSettingsSnapshot: Equatable, Sendable {
    var themeMode: ThemeMode
    var appLanguage: AppLanguage
    var gridLevel: GridLevel
    var badgeMetric: BadgeMetric
    var vectorModelKey: String = EmbeddingProviderRegistry.defaultKey
}

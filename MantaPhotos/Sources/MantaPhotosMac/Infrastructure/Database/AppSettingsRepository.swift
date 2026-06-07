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
                gridLevel: GridLevel(rawValue: Int(values["photos.gridLevel"] ?? "") ?? GridLevel.columns4.rawValue) ?? .columns4,
                badgeMetric: BadgeMetric(rawValue: values["photos.badgeMetric"] ?? "") ?? .aesthetic
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
                ("photos.badgeMetric", snapshot.badgeMetric.rawValue)
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

struct AppSettingsSnapshot: Equatable, Sendable {
    var themeMode: ThemeMode
    var appLanguage: AppLanguage
    var gridLevel: GridLevel
    var badgeMetric: BadgeMetric
}

import Foundation
import GRDB

struct AppBootstrapper: Sendable {
    func bootstrap(databaseURL: URL) async throws -> DatabaseQueue {
        try await Task.detached(priority: .utility) {
            let directory = databaseURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )

            let databaseQueue = try DatabaseQueue(path: databaseURL.path)
            try DatabaseMigrator().migrate(databaseQueue: databaseQueue)
            return databaseQueue
        }.value
    }
}

import Foundation
import GRDB
import Testing
@testable import MantaPhotosCore

@Suite
struct DatabaseMigratorTests {
    @Test
    func migratorCreatesP0P1Tables() throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "manta-photos-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }

        let databaseQueue = try DatabaseQueue(path: url.path)
        try DatabaseMigrator().migrate(databaseQueue: databaseQueue)

        let migrationCount = try databaseQueue.read {
            try Int.fetchOne($0, sql: "select count(*) from schema_migrations;")
        }
        let schemaChecks = try databaseQueue.read { database in
            let modelCount = try Int.fetchOne(database, sql: "select count(*) from ai_models where id = 'apple_vision_aesthetics_v1';")
            let deviceCategoryCount = try Int.fetchOne(database, sql: "select count(*) from pragma_table_info('photo_assets') where name = 'device_category';")
            let reportTableCount = try Int.fetchOne(database, sql: "select count(*) from sqlite_master where type = 'table' and name = 'reports';")
            let faceTableCount = try Int.fetchOne(database, sql: "select count(*) from sqlite_master where type = 'table' and name = 'person_faces';")
            let sourceTableCount = try Int.fetchOne(database, sql: "select count(*) from sqlite_master where type = 'table' and name = 'photo_sources';")
            let sourceIDColumnCount = try Int.fetchOne(database, sql: "select count(*) from pragma_table_info('photo_assets') where name = 'source_id';")
            let systemSourceCount = try Int.fetchOne(database, sql: "select count(*) from photo_sources where id = 'system_photos';")

            return (
                modelCount: modelCount,
                deviceCategoryCount: deviceCategoryCount,
                reportTableCount: reportTableCount,
                faceTableCount: faceTableCount,
                sourceTableCount: sourceTableCount,
                sourceIDColumnCount: sourceIDColumnCount,
                systemSourceCount: systemSourceCount
            )
        }

        #expect(migrationCount == 5)
        #expect(schemaChecks.modelCount == 1)
        #expect(schemaChecks.deviceCategoryCount == 1)
        #expect(schemaChecks.reportTableCount == 1)
        #expect(schemaChecks.faceTableCount == 1)
        #expect(schemaChecks.sourceTableCount == 1)
        #expect(schemaChecks.sourceIDColumnCount == 1)
        #expect(schemaChecks.systemSourceCount == 1)
    }

    @Test
    func repositoriesUpsertAndSearchPhotoAssets() throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "manta-photos-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }

        let databaseQueue = try DatabaseQueue(path: url.path)
        try DatabaseMigrator().migrate(databaseQueue: databaseQueue)

        let repository = PhotoAssetRepository(databaseQueue: databaseQueue)
        try repository.upsert([
            PhotoAsset(
                id: "asset-1",
                localIdentifier: "asset-1",
                filename: "beach-sunset.jpg",
                mediaType: .image,
                mediaSubtypesRawValue: 0,
                creationDate: Date(timeIntervalSince1970: 1_700_000_000),
                modificationDate: nil,
                width: 4000,
                height: 3000,
                duration: nil,
                isFavorite: true,
                isHidden: false,
                inTrash: false,
                trashedAt: nil,
                iCloudState: .local,
                isLocallyAvailable: true
            )
        ])

        var filter = SearchFilterState()
        filter.keyword = "beach"
        filter.mediaTypes = [.image]
        filter.favoritesOnly = true

        let results = try SearchRepository(databaseQueue: databaseQueue).search(filter: filter)

        #expect(results.map(\.id) == ["asset-1"])
        #expect(results.first?.filename == "beach-sunset.jpg")

        try repository.updateTrash(
            photoID: "asset-1",
            inTrash: true,
            trashedAt: Date(timeIntervalSince1970: 1_700_000_100)
        )
        let defaultResultsAfterTrash = try SearchRepository(databaseQueue: databaseQueue).search(filter: SearchFilterState())
        var trashFilter = SearchFilterState()
        trashFilter.inTrash = true
        let trashResults = try SearchRepository(databaseQueue: databaseQueue).search(filter: trashFilter)

        #expect(defaultResultsAfterTrash.isEmpty)
        #expect(trashResults.map(\.id) == ["asset-1"])

        try repository.updateTrash(photoID: "asset-1", inTrash: false, trashedAt: nil)
        try repository.updateFavorite(photoID: "asset-1", isFavorite: false)
        try repository.markSystemDeleted(photoID: "asset-1")
        let defaultResultsAfterDelete = try SearchRepository(databaseQueue: databaseQueue).search(filter: SearchFilterState())

        #expect(defaultResultsAfterDelete.isEmpty)
    }

    @Test
    func analysisRepositoryRetriesFailedVisionTasks() throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "manta-photos-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }

        let databaseQueue = try DatabaseQueue(path: url.path)
        try DatabaseMigrator().migrate(databaseQueue: databaseQueue)

        try PhotoAssetRepository(databaseQueue: databaseQueue).upsert([
            PhotoAsset(
                id: "asset-retry",
                localIdentifier: "asset-retry",
                filename: "retry.jpg",
                mediaType: .image,
                mediaSubtypesRawValue: 0,
                creationDate: Date(timeIntervalSince1970: 1_700_000_000),
                modificationDate: nil,
                width: 4000,
                height: 3000,
                duration: nil,
                isFavorite: false,
                isHidden: false,
                inTrash: false,
                trashedAt: nil,
                iCloudState: .local,
                isLocallyAvailable: true
            )
        ])

        let analysisRepository = AnalysisRepository(databaseQueue: databaseQueue)
        let runID = try analysisRepository.createVisionAestheticsRun(
            photoIDs: ["asset-retry"],
            requestedScopeJSON: #"{"source":"test"}"#
        )
        let task = try #require(analysisRepository.pendingVisionTasks(runID: runID).first)

        try analysisRepository.markTaskRunning(taskID: task.id)
        try analysisRepository.markTaskFailed(task: task, message: "fixture failure")

        let failedProgress = try analysisRepository.runProgress(runID: runID)
        #expect(failedProgress.failed == 1)
        #expect(try analysisRepository.latestRunIDWithFailedTasks() == runID)

        let retryCount = try analysisRepository.retryFailedTasks(runID: runID)
        let pendingAfterRetry = try analysisRepository.pendingVisionTasks(runID: runID)
        let retryProgress = try analysisRepository.runProgress(runID: runID)

        #expect(retryCount == 1)
        #expect(pendingAfterRetry.map(\.photoID) == ["asset-retry"])
        #expect(retryProgress.status == .running)
        #expect(retryProgress.failed == 0)
    }
}

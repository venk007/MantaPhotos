import Foundation
import GRDB
import MantaPhotosCore

let url = FileManager.default.temporaryDirectory
    .appending(path: "manta-photos-checks-\(UUID().uuidString).sqlite")
defer { try? FileManager.default.removeItem(at: url) }

let databaseQueue = try DatabaseQueue(path: url.path)
try DatabaseMigrator().migrate(databaseQueue: databaseQueue)

let assetRepository = PhotoAssetRepository(databaseQueue: databaseQueue)
try assetRepository.upsert([
    PhotoAsset(
        id: "check-asset-1",
        localIdentifier: "check-asset-1",
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
guard results.map(\.id) == ["check-asset-1"] else {
    throw CheckError.unexpectedSearchResults(results.map(\.id))
}

let analysisRepository = AnalysisRepository(databaseQueue: databaseQueue)
let runID = try analysisRepository.createVisionAestheticsRun(photoIDs: ["check-asset-1"])
let task = try analysisRepository.pendingVisionTasks(runID: runID, limit: 1)
    .first
guard let task else {
    throw CheckError.missingAnalysisTask
}
try analysisRepository.markTaskRunning(taskID: task.id)
try analysisRepository.activateAestheticScore(
    task: task,
    result: AestheticScoreResult(
        score: 87,
        rawOverallScore: 0.74,
        isUtility: false,
        forcedZeroReason: nil
    )
)

let scoredResults = try SearchRepository(databaseQueue: databaseQueue).searchResults(filter: SearchFilterState())
guard scoredResults.first?.aestheticScore == 87 else {
    throw CheckError.unexpectedScore(scoredResults.first?.aestheticScore)
}

let cancellableRunID = try analysisRepository.createVisionAestheticsRun(photoIDs: ["check-asset-1"])
try analysisRepository.pauseRun(runID: cancellableRunID)
guard try analysisRepository.runProgress(runID: cancellableRunID).status == .paused else {
    throw CheckError.unexpectedRunStatus
}
try analysisRepository.resumeRun(runID: cancellableRunID)
guard try analysisRepository.runProgress(runID: cancellableRunID).status == .running else {
    throw CheckError.unexpectedRunStatus
}
try analysisRepository.cancelRun(runID: cancellableRunID)
guard try analysisRepository.runProgress(runID: cancellableRunID).status == .cancelled else {
    throw CheckError.unexpectedRunStatus
}

print("MantaPhotosChecks passed: migration, upsert, FTS5, SQL filters, score activation, and analysis controls are working.")

enum CheckError: Error, CustomStringConvertible {
    case unexpectedSearchResults([String])
    case missingAnalysisTask
    case unexpectedScore(Double?)
    case unexpectedRunStatus

    var description: String {
        switch self {
        case .unexpectedSearchResults(let ids):
            "Unexpected search results: \(ids)"
        case .missingAnalysisTask:
            "Expected a pending analysis task."
        case .unexpectedScore(let score):
            "Unexpected score: \(String(describing: score))"
        case .unexpectedRunStatus:
            "Unexpected analysis run status."
        }
    }
}

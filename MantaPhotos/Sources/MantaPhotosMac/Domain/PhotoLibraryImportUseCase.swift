import Foundation

struct PhotoImportProgress: Equatable, Sendable {
    enum Phase: String, Equatable, Sendable {
        case idle
        case requestingAuthorization
        case initialImport
        case backgroundImport
        case completed
        case denied
        case failed
    }

    var phase: Phase
    var imported: Int
    var total: Int
    var message: String

    static let idle = PhotoImportProgress(phase: .idle, imported: 0, total: 0, message: "")
}

struct PhotoImportSummary: Equatable, Sendable {
    var imported: Int
    var total: Int
}

struct PhotoLibraryImportUseCase: Sendable {
    var adapter: PhotoLibraryAdapter
    var repository: PhotoAssetRepository
    var pageSize: Int = 500

    @discardableResult
    func importAll(
        initialLimit: Int = PhotoLibraryAdapter.initialImportLimit,
        progressHandler: (@MainActor @Sendable (PhotoImportProgress) -> Void)? = nil,
        initialBatchCompleted: (@MainActor @Sendable () async -> Void)? = nil
    ) async throws -> PhotoImportSummary {
        let total = adapter.fetchAssetCount()
        let firstBatchLimit = min(initialLimit, total)

        try await importRange(
            offset: 0,
            limit: firstBatchLimit,
            total: total,
            phase: .initialImport,
            progressHandler: progressHandler
        )

        if let initialBatchCompleted {
            await initialBatchCompleted()
        }

        if total > firstBatchLimit {
            try await importRange(
                offset: firstBatchLimit,
                limit: total - firstBatchLimit,
                total: total,
                phase: .backgroundImport,
                progressHandler: progressHandler
            )
        }

        await progressHandler?(
            PhotoImportProgress(
                phase: .completed,
                imported: total,
                total: total,
                message: "Import completed"
            )
        )

        return PhotoImportSummary(imported: total, total: total)
    }

    private func importRange(
        offset: Int,
        limit: Int,
        total: Int,
        phase: PhotoImportProgress.Phase,
        progressHandler: (@MainActor @Sendable (PhotoImportProgress) -> Void)?
    ) async throws {
        guard limit > 0 else { return }

        var imported = offset
        while imported < offset + limit {
            try Task.checkCancellation()

            let pageLimit = min(pageSize, offset + limit - imported)
            let assets = adapter.fetchAssets(
                limit: pageLimit,
                offset: imported,
                includeFilenames: false
            )

            guard !assets.isEmpty else { break }
            try repository.upsert(assets)
            imported += assets.count

            await progressHandler?(
                PhotoImportProgress(
                    phase: phase,
                    imported: imported,
                    total: total,
                    message: phase == .initialImport ? "Preparing recent photos" : "Importing library in background"
                )
            )
        }
    }
}

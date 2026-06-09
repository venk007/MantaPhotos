import Foundation
import GRDB
import Photos

public struct VisionAnalysisTaskRecord: Identifiable, Equatable, Sendable {
    public var id: String
    public var analysisRunID: String
    public var photoID: String
    public var localIdentifier: String
    public var isScreenshot: Bool
    // 多源定位：系统源用 localIdentifier，本地 / 外部源用 sourceID + relativePath。
    public var sourceID: String
    public var sourceAssetKey: String
    public var relativePath: String?

    public var isSystemPhotos: Bool { sourceID == PhotoAsset.systemPhotosSourceID }
}

public struct AnalysisRepository: Sendable {
    public let databaseQueue: DatabaseQueue
    public let modelID = "apple_vision_aesthetics_v1"

    public init(databaseQueue: DatabaseQueue) {
        self.databaseQueue = databaseQueue
    }

    public func createVisionAestheticsRun(
        photoIDs: [String],
        requestedScopeJSON: String = #"{"source":"visiblePhotos"}"#
    ) throws -> String {
        let runID = UUID().uuidString
        let now = DateCoding.string(from: Date()) ?? ""

        try databaseQueue.write { database in
            try database.execute(
                sql:
                    """
                    insert into analysis_runs(
                      id, task_type, model_id, status, requested_scope_json,
                      total_count, completed_count, failed_count, created_at, started_at
                    )
                    values (?, 'visionAesthetics', ?, 'running', ?, 0, 0, 0, ?, ?);
                    """,
                arguments: [
                    runID,
                    modelID,
                    requestedScopeJSON,
                    now,
                    now
                ]
            )

            // 已有美学评分的照片直接跳过，不重复评分（曾失败、无分数的照片会被重新入队）。
            var enqueued = 0
            for (index, photoID) in photoIDs.enumerated() {
                try database.execute(
                    sql:
                        """
                        insert or ignore into analysis_tasks(
                          id, analysis_run_id, photo_id, task_type, status, priority, attempts, created_at
                        )
                        select ?, ?, ?, 'visionAesthetics', 'pending', ?, 0, ?
                        where not exists (
                          select 1 from photo_scores where photo_id = ?
                        );
                        """,
                    arguments: [UUID().uuidString, runID, photoID, 100 + index, now, photoID]
                )
                enqueued += database.changesCount
            }

            try database.execute(
                sql: "update analysis_runs set total_count = ? where id = ?;",
                arguments: [enqueued, runID]
            )
        }

        return runID
    }

    public func latestRunIDWithFailedTasks() throws -> String? {
        try databaseQueue.read { database in
            try String.fetchOne(
                database,
                sql:
                    """
                    select id
                    from analysis_runs
                    where task_type = 'visionAesthetics'
                      and failed_count > 0
                    order by created_at desc
                    limit 1;
                    """
            )
        }
    }

    @discardableResult
    public func retryFailedTasks(runID: String) throws -> Int {
        let now = DateCoding.string(from: Date()) ?? ""

        return try databaseQueue.write { database in
            let failedCount = try Int.fetchOne(
                database,
                sql:
                    """
                    select count(*)
                    from analysis_tasks
                    where analysis_run_id = ?
                      and task_type = 'visionAesthetics'
                      and status = 'failed';
                    """,
                arguments: [runID]
            ) ?? 0

            guard failedCount > 0 else { return 0 }

            try database.execute(
                sql:
                    """
                    update analysis_tasks
                    set status = 'pending',
                        error_message = null,
                        started_at = null,
                        completed_at = null
                    where analysis_run_id = ?
                      and task_type = 'visionAesthetics'
                      and status = 'failed';
                    """,
                arguments: [runID]
            )

            try database.execute(
                sql:
                    """
                    update analysis_runs
                    set status = 'running',
                        completed_at = null,
                        started_at = coalesce(started_at, ?)
                    where id = ?;
                    """,
                arguments: [now, runID]
            )

            try refreshRunCounts(runID: runID, now: now, database: database)
            return failedCount
        }
    }

    public func pendingVisionTasks(runID: String, limit: Int = 8) throws -> [VisionAnalysisTaskRecord] {
        try databaseQueue.read { database in
            let rows = try Row.fetchAll(
                database,
                sql:
                    """
                    select
                      analysis_tasks.id,
                      analysis_tasks.analysis_run_id,
                      analysis_tasks.photo_id,
                      photo_assets.local_identifier,
                      photo_assets.media_subtypes_raw,
                      photo_assets.source_id,
                      photo_assets.source_asset_key,
                      photo_assets.relative_path
                    from analysis_tasks
                    join photo_assets on photo_assets.id = analysis_tasks.photo_id
                    where analysis_tasks.analysis_run_id = ?
                      and analysis_tasks.task_type = 'visionAesthetics'
                      and analysis_tasks.status = 'pending'
                    order by analysis_tasks.priority asc, analysis_tasks.created_at asc
                    limit ?;
                    """,
                arguments: [runID, limit]
            )

            return rows.map { row in
                let raw = UInt(row["media_subtypes_raw"] as Int64)
                let sourceID = (row["source_id"] as String?) ?? PhotoAsset.systemPhotosSourceID
                let sourceAssetKey = (row["source_asset_key"] as String?) ?? (row["local_identifier"] as String)
                return VisionAnalysisTaskRecord(
                    id: row["id"],
                    analysisRunID: row["analysis_run_id"],
                    photoID: row["photo_id"],
                    localIdentifier: row["local_identifier"],
                    isScreenshot: (raw & PHAssetMediaSubtype.photoScreenshot.rawValue) != 0,
                    sourceID: sourceID,
                    sourceAssetKey: sourceAssetKey,
                    relativePath: row["relative_path"]
                )
            }
        }
    }

    public func pauseRun(runID: String) throws {
        try databaseQueue.write { database in
            try database.execute(
                sql:
                    """
                    update analysis_runs
                    set status = 'paused'
                    where id = ?
                      and status in ('running', 'pending');
                    """,
                arguments: [runID]
            )
        }
    }

    public func resumeRun(runID: String) throws {
        try databaseQueue.write { database in
            try database.execute(
                sql:
                    """
                    update analysis_runs
                    set status = 'running',
                        started_at = coalesce(started_at, strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
                    where id = ?
                      and status = 'paused';
                    """,
                arguments: [runID]
            )
        }
    }

    public func cancelRun(runID: String) throws {
        let now = DateCoding.string(from: Date()) ?? ""
        try databaseQueue.write { database in
            try database.execute(
                sql:
                    """
                    update analysis_tasks
                    set status = 'cancelled',
                        completed_at = ?,
                        error_message = 'cancelled by user'
                    where analysis_run_id = ?
                      and status in ('pending', 'running');
                    """,
                arguments: [now, runID]
            )
            try database.execute(
                sql:
                    """
                    update analysis_runs
                    set status = 'cancelled',
                        completed_at = ?
                    where id = ?
                      and status in ('pending', 'running', 'paused');
                    """,
                arguments: [now, runID]
            )
            try refreshRunCounts(runID: runID, now: now, database: database, forcedStatus: "cancelled")
        }
    }

    /// 批量将任务标记为运行中（单事务）。
    public func markTasksRunning(taskIDs: [String]) throws {
        guard !taskIDs.isEmpty else { return }
        let now = DateCoding.string(from: Date()) ?? ""
        try databaseQueue.write { database in
            for taskID in taskIDs {
                try database.execute(
                    sql:
                        """
                        update analysis_tasks
                        set status = 'running', attempts = attempts + 1, started_at = ?
                        where id = ?;
                        """,
                    arguments: [now, taskID]
                )
            }
        }
    }

    /// 批量落库一批评分结果（单事务），并按 run 统一刷新计数。
    public func activateAestheticScores(
        _ scored: [(VisionAnalysisTaskRecord, AestheticScoreResult)]
    ) throws {
        guard !scored.isEmpty else { return }
        let now = DateCoding.string(from: Date()) ?? ""
        try databaseQueue.write { database in
            for (task, result) in scored {
                try writeAestheticScore(task: task, result: result, now: now, database: database)
            }
            for runID in Set(scored.map { $0.0.analysisRunID }) {
                try refreshRunCounts(runID: runID, now: now, database: database)
            }
        }
    }

    /// 批量将任务标记为失败（单事务），并按 run 统一刷新计数。
    public func markTasksFailed(
        _ failed: [(VisionAnalysisTaskRecord, String)]
    ) throws {
        guard !failed.isEmpty else { return }
        let now = DateCoding.string(from: Date()) ?? ""
        try databaseQueue.write { database in
            for (task, message) in failed {
                try database.execute(
                    sql:
                        """
                        update analysis_tasks
                        set status = 'failed', error_message = ?, completed_at = ?
                        where id = ?;
                        """,
                    arguments: [message, now, task.id]
                )
            }
            for runID in Set(failed.map { $0.0.analysisRunID }) {
                try refreshRunCounts(runID: runID, now: now, database: database)
            }
        }
    }

    /// 在给定事务内写入单条美学评分（不刷新计数，由调用方批量刷新）。
    private func writeAestheticScore(
        task: VisionAnalysisTaskRecord,
        result: AestheticScoreResult,
        now: String,
        database: Database
    ) throws {
        let outputID = UUID().uuidString
        let payload =
            """
            {"score":\(result.score),"rawOverallScore":\(result.rawOverallScore),"isUtility":\(result.isUtility),"forcedZeroReason":\(jsonString(result.forcedZeroReason))}
            """

        try database.execute(
            sql:
                """
                insert into analysis_outputs(
                  id, analysis_run_id, analysis_task_id, photo_id, model_id,
                  output_type, output_payload_json, active, created_at
                )
                values (?, ?, ?, ?, ?, 'score.aesthetic', ?, 0, ?);
                """,
            arguments: [outputID, task.analysisRunID, task.id, task.photoID, modelID, payload, now]
        )

        try database.execute(
            sql:
                """
                update analysis_outputs
                set active = 0, superseded_at = ?
                where photo_id = ?
                  and output_type = 'score.aesthetic'
                  and active = 1;
                """,
            arguments: [now, task.photoID]
        )

        try database.execute(
            sql:
                """
                update analysis_outputs
                set active = 1, activated_at = ?
                where id = ?;
                """,
            arguments: [now, outputID]
        )

        try database.execute(
            sql:
                """
                insert into photo_scores(
                  photo_id, aesthetic_score, overall_score, analysis_run_id,
                  analysis_output_id, model_id, scored_at, updated_at
                )
                values (?, ?, ?, ?, ?, ?, ?, ?)
                on conflict(photo_id) do update set
                  aesthetic_score = excluded.aesthetic_score,
                  overall_score = excluded.overall_score,
                  analysis_run_id = excluded.analysis_run_id,
                  analysis_output_id = excluded.analysis_output_id,
                  model_id = excluded.model_id,
                  scored_at = excluded.scored_at,
                  updated_at = excluded.updated_at;
                """,
            arguments: [task.photoID, result.score, nil, task.analysisRunID, outputID, modelID, now, now]
        )

        try database.execute(
            sql:
                """
                update analysis_tasks
                set status = 'completed', completed_at = ?, error_message = null
                where id = ?;
                """,
            arguments: [now, task.id]
        )
    }

    // MARK: - 单条便捷封装（基于批量实现）

    public func markTaskRunning(taskID: String) throws {
        try markTasksRunning(taskIDs: [taskID])
    }

    public func activateAestheticScore(task: VisionAnalysisTaskRecord, result: AestheticScoreResult) throws {
        try activateAestheticScores([(task, result)])
    }

    public func markTaskFailed(task: VisionAnalysisTaskRecord, message: String) throws {
        try markTasksFailed([(task, message)])
    }

    public func runProgress(runID: String) throws -> AnalysisProgress {
        try databaseQueue.read { database in
            let row = try Row.fetchOne(
                database,
                sql:
                    """
                    select total_count, completed_count, failed_count, status
                    from analysis_runs
                    where id = ?;
                    """,
                arguments: [runID]
            )

            guard let row else { return .idle }
            let total: Int = row["total_count"]
            let completed: Int = row["completed_count"]
            let failed: Int = row["failed_count"]
            let status: String = row["status"]
            return AnalysisProgress(
                status: AnalysisStatus(rawValue: status) ?? .failed,
                completed: completed,
                failed: failed,
                total: total,
                currentRunID: runID
            )
        }
    }

    private func refreshRunCounts(
        runID: String,
        now: String,
        database: Database,
        forcedStatus: String? = nil
    ) throws {
        let completed = try Int.fetchOne(
            database,
            sql: "select count(*) from analysis_tasks where analysis_run_id = ? and status = 'completed';",
            arguments: [runID]
        ) ?? 0
        let failed = try Int.fetchOne(
            database,
            sql: "select count(*) from analysis_tasks where analysis_run_id = ? and status = 'failed';",
            arguments: [runID]
        ) ?? 0
        let total = try Int.fetchOne(
            database,
            sql: "select count(*) from analysis_tasks where analysis_run_id = ?;",
            arguments: [runID]
        ) ?? 0
        let status = forcedStatus ?? (completed + failed >= total ? "completed" : "running")

        try database.execute(
            sql:
                """
                update analysis_runs
                set completed_count = ?,
                    failed_count = ?,
                    status = ?,
                    completed_at = case when ? = 'completed' then ? else completed_at end
                where id = ?;
                """,
            arguments: [completed, failed, status, status, now, runID]
        )
    }

    private func jsonString(_ value: String?) -> String {
        guard let value else { return "null" }
        guard
            let data = try? JSONSerialization.data(withJSONObject: [value]),
            let json = String(data: data, encoding: .utf8),
            json.count >= 2
        else {
            return "\"\""
        }
        return String(json.dropFirst().dropLast())
    }
}

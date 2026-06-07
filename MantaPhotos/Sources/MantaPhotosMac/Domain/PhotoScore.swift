import Foundation

public struct PhotoScore: Identifiable, Equatable, Sendable {
    public var id: String { photoID }
    public var photoID: String
    public var aestheticScore: Double
    public var overallScore: Double?
    public var analysisRunID: String
    public var analysisOutputID: String
    public var modelID: String
    public var scoredAt: Date
}

enum AIModelRole: String, Codable, Sendable {
    case visionAesthetics
}

enum AnalysisTaskType: String, Codable, Sendable {
    case visionAesthetics
}

enum AnalysisTaskStatus: String, Codable, Sendable {
    case pending
    case running
    case completed
    case failed
    case cancelled
}

struct AnalysisRun: Identifiable, Equatable, Sendable {
    var id: String
    var taskType: AnalysisTaskType
    var modelID: String
    var status: AnalysisTaskStatus
    var createdAt: Date
}

struct AnalysisTask: Identifiable, Equatable, Sendable {
    var id: String
    var analysisRunID: String
    var photoID: String
    var taskType: AnalysisTaskType
    var status: AnalysisTaskStatus
    var priority: Int
    var attempts: Int
    var createdAt: Date
}

public struct AestheticScoreResult: Equatable, Sendable {
    public var score: Double
    public var rawOverallScore: Float
    public var isUtility: Bool
    public var forcedZeroReason: String?

    public init(score: Double, rawOverallScore: Float, isUtility: Bool, forcedZeroReason: String?) {
        self.score = score
        self.rawOverallScore = rawOverallScore
        self.isUtility = isUtility
        self.forcedZeroReason = forcedZeroReason
    }

    public static func screenshot(rawOverallScore: Float = -1) -> AestheticScoreResult {
        AestheticScoreResult(
            score: 0,
            rawOverallScore: rawOverallScore,
            isUtility: true,
            forcedZeroReason: "screenshot"
        )
    }
}

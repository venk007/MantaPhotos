import AppKit
import Foundation
import Vision

protocol AestheticsScoringProvider: Sendable {
    func scoreImage(data: Data, isScreenshot: Bool) async throws -> AestheticScoreResult
}

struct AppleVisionAestheticsProvider: AestheticsScoringProvider {
    func scoreImage(data: Data, isScreenshot: Bool) async throws -> AestheticScoreResult {
        if isScreenshot {
            return .screenshot()
        }

        return try await Task.detached(priority: .utility) {
            let request = VNCalculateImageAestheticsScoresRequest()
            let handler = VNImageRequestHandler(data: data)
            try handler.perform([request])

            guard let observation = request.results?.first else {
                throw VisionAestheticsError.noObservation
            }

            return AestheticScoreResult(
                score: Self.normalizedScore(from: observation.overallScore),
                rawOverallScore: observation.overallScore,
                isUtility: observation.isUtility,
                forcedZeroReason: nil
            )
        }.value
    }

    private static func normalizedScore(from rawScore: Float) -> Double {
        let clamped = max(-1, min(1, Double(rawScore)))
        return ((clamped + 1) / 2) * 100
    }
}

enum VisionAestheticsError: Error, LocalizedError {
    case noObservation

    var errorDescription: String? {
        switch self {
        case .noObservation:
            "Vision did not return an aesthetics scores observation."
        }
    }
}

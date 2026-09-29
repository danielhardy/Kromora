import CoreGraphics
import Vision

/// Test/report-only Vision image-aesthetics probe. It is intentionally kept out of the shipping
/// Auto path: the score is an observational correlation signal, never a candidate decision input.
struct VisionAestheticsScores: Sendable, Equatable {
    let overallScore: Double
    let isUtility: Bool
}

enum VisionAestheticsDiagnostics {
    /// Returns nil when Vision declines the request or produces no observation.
    static func scores(for image: CGImage) -> VisionAestheticsScores? {
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        return scores { request in
            try handler.perform([request])
        }
    }

    static func scores(
        performRequest: (VNCalculateImageAestheticsScoresRequest) throws -> Void
    ) -> VisionAestheticsScores? {
        let request = VNCalculateImageAestheticsScoresRequest()
        do {
            try performRequest(request)
        } catch {
            return nil
        }
        guard let observation = request.results?.first else { return nil }
        let score = Double(observation.overallScore)
        guard score.isFinite else { return nil }
        return VisionAestheticsScores(overallScore: score, isUtility: observation.isUtility)
    }
}

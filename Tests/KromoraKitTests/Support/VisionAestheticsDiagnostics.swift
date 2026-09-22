import CoreGraphics
import Vision

/// Test/report-only Vision image-aesthetics probe. It is intentionally kept out of the shipping
/// Auto path: the score is an observational correlation signal, never a candidate decision input.
struct VisionAestheticsScores: Sendable, Equatable {
    let overallScore: Double
    let isUtility: Bool
}

enum VisionAestheticsDiagnostics {
    /// Returns nil on macOS 14, request failure, or when Vision produces no observation.
    static func scores(for image: CGImage) -> VisionAestheticsScores? {
        guard #available(macOS 15, *) else { return nil }
        let request = VNCalculateImageAestheticsScoresRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }
        guard let observation = request.results?.first else { return nil }
        let score = Double(observation.overallScore)
        guard score.isFinite else { return nil }
        return VisionAestheticsScores(overallScore: score, isUtility: observation.isUtility)
    }
}

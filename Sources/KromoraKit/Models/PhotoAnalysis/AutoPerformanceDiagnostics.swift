import CoreGraphics
import Foundation
import Vision

/// Bounded per-stage latency record for one content-aware Auto run (KRMA-352).
///
/// Fixed scalar fields only — no arrays, no pixels, no paths — so telemetry costs a few
/// `ContinuousClock` reads and attaching it never changes candidate behavior: selection reads
/// scores and budgets, never these timings. Decode is reported separately from Auto work so a
/// slow file open cannot hide (or inflate) the Auto gate.
///
/// Stage vocabulary:
/// - decode: image decode/preparation (`AnalysisTimings.imagePreparation`), not Auto work.
/// - analysis: photo analysis excluding decode (mask generation, assembly, cache store).
/// - mask: the mask-generation subset of analysis, for outlier attribution.
/// - measurement: current-edit render measurement through the sampling seam.
/// - candidateRender: candidate renders inside the coordinator (RAW redevelopments included).
/// - rawRedevelopment: the RAW-redevelopment subset of candidate renders.
/// - validation: candidate scoring and guardrail evaluation.
/// - regional: post-global regional correction planning.
/// - persistence: populated by the apply path (async coalesced persistence lives outside the
///   engine); the engine always leaves zero rather than guessing.
/// - total: wall-clock for the whole engine run, decode included.
struct AutoRunTimings: Codable, Sendable, Equatable {
    var decodeSeconds: Double
    var analysisSeconds: Double
    var maskSeconds: Double
    var measurementSeconds: Double
    var candidateRenderSeconds: Double
    var rawRedevelopmentSeconds: Double
    var validationSeconds: Double
    var regionalSeconds: Double
    var persistenceSeconds: Double
    var totalSeconds: Double
    var candidateCount: Int
    var evaluatedCount: Int
    var smallRenders: Int
    var rawRedevelopments: Int

    static let zero = AutoRunTimings(
        decodeSeconds: 0, analysisSeconds: 0, maskSeconds: 0, measurementSeconds: 0,
        candidateRenderSeconds: 0, rawRedevelopmentSeconds: 0, validationSeconds: 0,
        regionalSeconds: 0, persistenceSeconds: 0, totalSeconds: 0,
        candidateCount: 0, evaluatedCount: 0, smallRenders: 0, rawRedevelopments: 0
    )

    init(
        decodeSeconds: Double = 0,
        analysisSeconds: Double = 0,
        maskSeconds: Double = 0,
        measurementSeconds: Double = 0,
        candidateRenderSeconds: Double = 0,
        rawRedevelopmentSeconds: Double = 0,
        validationSeconds: Double = 0,
        regionalSeconds: Double = 0,
        persistenceSeconds: Double = 0,
        totalSeconds: Double = 0,
        candidateCount: Int = 0,
        evaluatedCount: Int = 0,
        smallRenders: Int = 0,
        rawRedevelopments: Int = 0
    ) {
        self.decodeSeconds = Self.clamped(decodeSeconds)
        self.analysisSeconds = Self.clamped(analysisSeconds)
        self.maskSeconds = Self.clamped(maskSeconds)
        self.measurementSeconds = Self.clamped(measurementSeconds)
        self.candidateRenderSeconds = Self.clamped(candidateRenderSeconds)
        self.rawRedevelopmentSeconds = Self.clamped(rawRedevelopmentSeconds)
        self.validationSeconds = Self.clamped(validationSeconds)
        self.regionalSeconds = Self.clamped(regionalSeconds)
        self.persistenceSeconds = Self.clamped(persistenceSeconds)
        self.totalSeconds = Self.clamped(totalSeconds)
        self.candidateCount = max(0, candidateCount)
        self.evaluatedCount = max(0, evaluatedCount)
        self.smallRenders = max(0, smallRenders)
        self.rawRedevelopments = max(0, rawRedevelopments)
    }

    /// Auto work excluding decode. The release gate (roughly 2–5 seconds typical) applies to
    /// this value, never to a total that includes file decode.
    var autoWorkSeconds: Double {
        max(0, totalSeconds - decodeSeconds)
    }

    private static func clamped(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 3_600)
    }
}

/// Clock-read helpers for the Auto timing vocabulary. `Duration` is the value type the
/// analysis pipeline already records; these convert without allocating.
enum AutoTimingClock {
    static func seconds(_ duration: Duration) -> Double {
        let components = duration.components
        let seconds = Double(components.seconds) + Double(components.attoseconds) / 1e18
        guard seconds.isFinite else { return 0 }
        return min(max(seconds, 0), 3_600)
    }

    /// Decode portion of an analysis result: image preparation only.
    static func decodeSeconds(_ timings: AnalysisTimings) -> Double {
        seconds(timings.imagePreparation)
    }

    /// Mask-generation subset of an analysis result, for outlier attribution.
    static func maskSeconds(_ timings: AnalysisTimings) -> Double {
        seconds(timings.faceDetection)
            + seconds(timings.saliency)
            + seconds(timings.foregroundMasking)
            + seconds(timings.personSegmentation)
    }
}

/// Diagnostic-only Vision image-aesthetics scores (KRMA-352).
///
/// `VNCalculateImageAestheticsScoresRequest` is macOS 15+. This helper is `#available`-guarded,
/// fixture/diagnostics-only, and never an optimization target: no production selection path —
/// policy, scoring, or coordinator — references this type or its scores. The score is recorded
/// beside renderer output so a later review can correlate human-perceived quality with the
/// renderer's own measurements; it must never steer a candidate decision.
struct VisionAestheticsScores: Sendable, Equatable {
    /// Overall aesthetic score in [-1, 1], where 1 is most desirable.
    let overallScore: Double
    /// Utility images are not poor quality, only unexciting; recorded, never penalized.
    let isUtility: Bool
}

enum VisionAestheticsDiagnostics {
    /// Collect aesthetics scores for diagnostics. Returns nil on macOS 14, on request failure,
    /// or when Vision produces no observation — a missing diagnostic never fails a run.
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

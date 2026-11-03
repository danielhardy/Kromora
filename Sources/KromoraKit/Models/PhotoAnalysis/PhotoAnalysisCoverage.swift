import Foundation

/// Which optional mask stages a persisted `PhotoAnalysis` has already attempted, and how each
/// attempt ended.
///
/// Analysis levels are not strictly nested: `fast` asks for a face at analysis quality, `detailed`
/// asks for preview-quality masks, and `standard` asks for foreground and background. A level in
/// the cache key would either duplicate work across levels or let one level satisfy another it does
/// not cover. Coverage is therefore recorded per stage, and a request is satisfied exactly when
/// every stage of its level is accounted for. The coordinator computes only the missing stages and
/// merges them into the stored result.
///
/// Persistence format policy: coverage is an additive field of the stored entry. An entry without
/// coverage (written before this field existed) carries no stage record, so the coordinator treats
/// it as a miss and recomputes it. `AnalysisVersion` is deliberately not bumped for that.
struct PhotoAnalysisCoverage: Codable, Sendable, Equatable {
    enum Outcome: Codable, Sendable, Equatable {
        /// The stage produced a mask that is represented in the stored regions.
        case produced
        /// The provider answered deterministically that the source has no such mask (no face, no
        /// salient region) or cannot produce it. Retrying would only repeat the same answer.
        case absent
        /// The stage failed for a reason that may not recur. It is retried after a backoff, up to
        /// `maxFailedAttempts` times.
        case failed(attempts: Int, lastAttempt: Date)
    }

    struct Entry: Codable, Sendable, Equatable {
        let kind: SemanticMaskKind
        let quality: MaskQuality
        var outcome: Outcome
    }

    static let empty = PhotoAnalysisCoverage(entries: [])
    /// A stage that has failed this many times is treated as unavailable until the analysis
    /// version changes.
    static let maxFailedAttempts = 3
    private static let baseBackoff: TimeInterval = 30

    private(set) var entries: [Entry]

    /// Wait before retrying a stage that has failed `attempts` times: 30 s, then 60 s, then 120 s.
    static func backoff(afterAttempts attempts: Int) -> TimeInterval {
        baseBackoff * pow(2, Double(max(0, attempts - 1)))
    }

    /// Whether `error` is the provider's final answer for this source rather than a transient
    /// failure. Cancellation is never classified: callers rethrow it.
    static func isDeterministicAbsence(_ error: Error) -> Bool {
        guard let error = error as? VisionSemanticMaskError else { return false }
        switch error {
        case .unsupported, .unsupportedQuality, .noSalientRegion, .noFaceDetected,
             .faceIndexOutOfRange, .foregroundIndexOutOfRange, .noPersonDetected:
            return true
        case .unableToDecodeImage, .requestFailed:
            return false
        case .personNotApplicable:
            // Gated on the face/foreground signals; a transient failure of those stages can
            // produce it, so it must be retried with them rather than recorded as final.
            return false
        }
    }

    /// The stages of `required` that still need a provider call at `now`.
    func missingStages(in required: [PhotoAnalysisStage], now: Date) -> [PhotoAnalysisStage] {
        required.filter { !isSatisfied($0, now: now) }
    }

    private func isSatisfied(_ stage: PhotoAnalysisStage, now: Date) -> Bool {
        for entry in entries where entry.kind == stage.kind {
            switch entry.outcome {
            case .produced:
                // A higher-quality mask of the same kind serves a lower-quality request.
                if entry.quality >= stage.quality { return true }
            case .absent:
                if entry.quality == stage.quality { return true }
            case .failed(let attempts, let lastAttempt):
                guard entry.quality == stage.quality else { continue }
                if attempts >= Self.maxFailedAttempts { return true }
                if now < lastAttempt.addingTimeInterval(Self.backoff(afterAttempts: attempts)) {
                    return true
                }
            }
        }
        return false
    }

    mutating func recordProduced(_ stage: PhotoAnalysisStage) {
        set(stage, outcome: .produced)
    }

    mutating func recordFailure(_ stage: PhotoAnalysisStage, error: Error, at date: Date) {
        if Self.isDeterministicAbsence(error) {
            set(stage, outcome: .absent)
            return
        }
        var attempts = 1
        if let previous = outcome(of: stage), case .failed(let count, _) = previous {
            attempts = count + 1
        }
        set(stage, outcome: .failed(attempts: attempts, lastAttempt: date))
    }

    func outcome(of stage: PhotoAnalysisStage) -> Outcome? {
        entries.first { $0.kind == stage.kind && $0.quality == stage.quality }?.outcome
    }

    private mutating func set(_ stage: PhotoAnalysisStage, outcome: Outcome) {
        if let index = entries.firstIndex(where: {
            $0.kind == stage.kind && $0.quality == stage.quality
        }) {
            entries[index].outcome = outcome
        } else {
            entries.append(Entry(kind: stage.kind, quality: stage.quality, outcome: outcome))
        }
    }
}

import Foundation

/// The relative contribution of each observable signal to a primary-subject score.
///
/// The values are deliberately named policy constants rather than magic numbers. Their sum is
/// one, so the weighted score remains in the unit interval after each input is normalized.
enum PrimarySubjectScoringWeights {
    /// How much of a candidate's area is covered by the attention/saliency region.
    static let attentionOverlap: Float = 0.30
    /// Confidence supplied by foreground-instance segmentation.
    static let foregroundConfidence: Float = 0.25
    /// Confidence supplied by face detection, including indexed face instances.
    static let facePresence: Float = 0.15
    /// Confidence supplied by person segmentation.
    static let personPresence: Float = 0.15
    /// Proximity of the candidate's center to a rule-of-thirds intersection.
    static let compositionWeight: Float = 0.10
    /// Candidate mask area relative to the largest subject-like candidate.
    static let relativeSize: Float = 0.05

    static let total: Float =
        attentionOverlap + foregroundConfidence + facePresence
        + personPresence + compositionWeight + relativeSize
}

/// The normalized signals and final score for one subject-like analyzed region.
struct PrimarySubjectScore: Sendable, Codable, Equatable {
    let regionID: UUID
    let attentionOverlap: Float
    let foregroundConfidence: Float
    let facePresence: Float
    let personPresence: Float
    let compositionWeight: Float
    let relativeSize: Float
    let total: Float

    var score: Float { total }
}

/// The pure result of primary-subject selection.
struct PrimarySubjectSelection: Sendable, Codable, Equatable {
    /// The selected region in `PhotoAnalysis.regions`, or `nil` when no useful subject evidence
    /// exists. The ID is used instead of copying a region so the result stays a reference into the
    /// caller's analysis value.
    let primaryRegionID: UUID?
    let confidence: Float
    let rankedSubjects: [PrimarySubjectScore]

    /// Ranked alternatives, excluding the selected primary region.
    var secondarySubjects: [PrimarySubjectScore] {
        Array(rankedSubjects.dropFirst(primaryRegionID == nil ? 0 : 1))
    }

    var secondaryRegionIDs: [UUID] { secondarySubjects.map(\.regionID) }

    init(
        primaryRegionID: UUID?,
        confidence: Float,
        rankedSubjects: [PrimarySubjectScore] = []
    ) {
        self.primaryRegionID = primaryRegionID
        self.confidence = Self.unit(confidence)
        self.rankedSubjects = rankedSubjects
    }

    static let none = PrimarySubjectSelection(primaryRegionID: nil, confidence: 0)

    private static func unit(_ value: Float) -> Float {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }
}

/// Chooses the strongest subject evidence from assembled region facts.
///
/// This selector intentionally does not call Vision or inspect mask pixels. Region bounds let it
/// compare saliency, faces, people, and foreground instances spatially; scalar-only callers still
/// get a useful selection from the confidence, kind, and coverage facts. A weighted continuous
/// score is used throughout. Confidence combines the winning score with its separation from the
/// runner-up, so a close contest remains conservative even when both candidates have strong
/// evidence.
struct PrimarySubjectSelector: Sendable {
    static func select(from regions: [AnalyzedRegion]) -> PrimarySubjectSelection {
        let candidates = subjectCandidates(in: regions)
        guard !candidates.isEmpty else { return .none }

        let maximumCoverage = candidates.map(\.coverage).max() ?? 0
        let scored = candidates.map {
            score($0, in: regions, maximumCoverage: maximumCoverage)
        }
        let ranked = scored.sorted { lhs, rhs in
            if lhs.total != rhs.total { return lhs.total > rhs.total }
            // UUID ordering makes equal or near-equal inputs independent of incoming array order.
            return lhs.regionID.uuidString < rhs.regionID.uuidString
        }
        guard let winner = ranked.first, winner.total > 0 else {
            return PrimarySubjectSelection(
                primaryRegionID: nil, confidence: 0, rankedSubjects: ranked)
        }

        let runnerUp = ranked.dropFirst().first?.total ?? 0
        let separation = (winner.total - runnerUp) / max(winner.total, 0.0001)
        // With one candidate separation is one. With tied candidates it is zero, leaving half of
        // their evidence as the confidence floor instead of making a forced tie look certain.
        let confidence = winner.total * (0.5 + 0.5 * unit(separation))
        return PrimarySubjectSelection(
            primaryRegionID: winner.regionID,
            confidence: confidence,
            rankedSubjects: ranked
        )
    }

    private static func subjectCandidates(in regions: [AnalyzedRegion]) -> [AnalyzedRegion] {
        let instances = regions.filter { isSubjectInstance($0.kind) }
        if !instances.isEmpty { return instances }
        // A saliency-only analysis is still useful. Background and unknown regions are never
        // candidates, which prevents a zero-subject photo from receiving an arbitrary pick.
        return regions.filter { $0.kind == .subject }
    }

    private static func score(
        _ candidate: AnalyzedRegion,
        in regions: [AnalyzedRegion],
        maximumCoverage: Float
    ) -> PrimarySubjectScore {
        let attention = matchingSignal(
            candidate: candidate,
            regions: regions.filter { $0.kind == .subject },
            value: { $0.confidence }
        )
        let foreground = matchingSignal(
            candidate: candidate,
            regions: regions.filter { isForeground($0.kind) },
            value: { $0.confidence }
        )
        let face = matchingSignal(
            candidate: candidate,
            regions: regions.filter { isFace($0.kind) },
            value: { $0.confidence }
        )
        let person = matchingSignal(
            candidate: candidate,
            regions: regions.filter { $0.kind == .person },
            value: { $0.confidence }
        )
        let composition = compositionWeight(for: candidate.bounds)
        let relativeSize = maximumCoverage > 0 ? candidate.coverage / maximumCoverage : 0
        let total = weightedScore(
            attention: attention,
            foreground: foreground,
            face: face,
            person: person,
            composition: composition,
            relativeSize: relativeSize,
            attentionAvailable: regions.contains { $0.kind == .subject },
            foregroundAvailable: regions.contains { isForeground($0.kind) },
            faceAvailable: regions.contains { isFace($0.kind) },
            personAvailable: regions.contains { $0.kind == .person },
            compositionAvailable: candidate.bounds != nil
        )
        // Geometry and relative size refine evidence; they cannot create a subject on their own.
        // This continuous gate keeps a weak saliency box from becoming a confident pick merely
        // because it happens to sit on a rule-of-thirds point.
        let semanticEvidence = max(attention, max(foreground, max(face, person)))
        let gatedTotal = total * semanticEvidence

        return PrimarySubjectScore(
            regionID: candidate.id,
            attentionOverlap: attention,
            foregroundConfidence: foreground,
            facePresence: face,
            personPresence: person,
            compositionWeight: composition,
            relativeSize: relativeSize,
            total: gatedTotal
        )
    }

    private static func matchingSignal(
        candidate: AnalyzedRegion,
        regions: [AnalyzedRegion],
        value: (AnalyzedRegion) -> Float
    ) -> Float {
        regions.map { region in
            let overlap =
                candidate.id == region.id ? 1 : boundsOverlap(candidate.bounds, region.bounds)
            return overlap * unit(value(region))
        }.max() ?? 0
    }

    private static func compositionWeight(for bounds: NormalizedRect?) -> Float {
        guard let bounds, bounds.width > 0, bounds.height > 0 else { return 0 }
        let center = bounds.midPoint
        let points: [(Double, Double)] = [
            (1.0 / 3.0, 1.0 / 3.0), (2.0 / 3.0, 1.0 / 3.0),
            (1.0 / 3.0, 2.0 / 3.0), (2.0 / 3.0, 2.0 / 3.0),
        ]
        let nearestDistance =
            points.map { point in
                sqrt(pow(center.x - point.0, 2) + pow(center.y - point.1, 2))
            }.min() ?? 1
        let maximumDistance = sqrt(2.0) / 3.0
        return unit(Float(1 - min(1, nearestDistance / maximumDistance)))
    }

    private static func boundsOverlap(_ lhs: NormalizedRect?, _ rhs: NormalizedRect?) -> Float {
        guard let lhs, let rhs, lhs.width > 0, lhs.height > 0, rhs.width > 0, rhs.height > 0 else {
            return 0
        }
        let width = max(0, min(lhs.maxX, rhs.maxX) - max(lhs.minX, rhs.minX))
        let height = max(0, min(lhs.maxY, rhs.maxY) - max(lhs.minY, rhs.minY))
        let candidateArea = lhs.width * lhs.height
        guard candidateArea > 0 else { return 0 }
        return unit(Float((width * height) / candidateArea))
    }

    private static func weightedScore(
        attention: Float,
        foreground: Float,
        face: Float,
        person: Float,
        composition: Float,
        relativeSize: Float,
        attentionAvailable: Bool,
        foregroundAvailable: Bool,
        faceAvailable: Bool,
        personAvailable: Bool,
        compositionAvailable: Bool
    ) -> Float {
        let weightedSignals: [(value: Float, weight: Float, available: Bool)] = [
            (attention, PrimarySubjectScoringWeights.attentionOverlap, attentionAvailable),
            (foreground, PrimarySubjectScoringWeights.foregroundConfidence, foregroundAvailable),
            (face, PrimarySubjectScoringWeights.facePresence, faceAvailable),
            (person, PrimarySubjectScoringWeights.personPresence, personAvailable),
            (composition, PrimarySubjectScoringWeights.compositionWeight, compositionAvailable),
            (relativeSize, PrimarySubjectScoringWeights.relativeSize, true),
        ]
        let activeWeight =
            weightedSignals
            .filter { $0.available }
            .reduce(Float.zero) { $0 + $1.weight }
        guard activeWeight > 0 else { return 0 }
        let score =
            weightedSignals
            .filter { $0.available }
            .reduce(Float.zero) { $0 + $1.value * $1.weight }
        return unit(score / activeWeight)
    }

    private static func isSubjectInstance(_ kind: RegionKind) -> Bool {
        switch kind {
        case .foregroundInstance, .person, .face, .faceInstance:
            return true
        default:
            return false
        }
    }

    private static func isForeground(_ kind: RegionKind) -> Bool {
        if case .foregroundInstance = kind { return true }
        return false
    }

    private static func isFace(_ kind: RegionKind) -> Bool {
        switch kind {
        case .face, .faceInstance:
            return true
        default:
            return false
        }
    }

    private static func unit(_ value: Float) -> Float {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }
}

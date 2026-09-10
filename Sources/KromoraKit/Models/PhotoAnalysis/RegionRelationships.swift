import Foundation

/// Signed luminance relationships between the source image and its analyzed regions.
///
/// These are descriptive facts, not exposure decisions. All deltas use the perceptual tone view
/// because that is the stable, display-oriented space used by downstream scene and Auto logic;
/// linear-light values would overstate differences in the shadows from a viewer's perspective.
struct RegionRelationships: Sendable, Codable, Equatable {
    let subjectToGlobalLuminanceDelta: Float?
    let subjectToBackgroundLuminanceDelta: Float?
    let faceToSubjectLuminanceDelta: Float?
    let faceToBackgroundLuminanceDelta: Float?
    /// Absolute subject/background separation. This is retained separately from the signed delta
    /// because consumers often need a contrast magnitude without losing the direction above.
    let subjectContrast: Float?
    /// Absolute background/global separation, useful for identifying a background that is much
    /// brighter or darker than the overall scene.
    let backgroundContrast: Float?

    init(
        subjectToGlobalLuminanceDelta: Float? = nil,
        subjectToBackgroundLuminanceDelta: Float? = nil,
        faceToSubjectLuminanceDelta: Float? = nil,
        faceToBackgroundLuminanceDelta: Float? = nil,
        subjectContrast: Float? = nil,
        backgroundContrast: Float? = nil
    ) {
        self.subjectToGlobalLuminanceDelta = Self.finiteDelta(subjectToGlobalLuminanceDelta)
        self.subjectToBackgroundLuminanceDelta = Self.finiteDelta(subjectToBackgroundLuminanceDelta)
        self.faceToSubjectLuminanceDelta = Self.finiteDelta(faceToSubjectLuminanceDelta)
        self.faceToBackgroundLuminanceDelta = Self.finiteDelta(faceToBackgroundLuminanceDelta)
        self.subjectContrast = Self.finiteUnit(subjectContrast)
        self.backgroundContrast = Self.finiteUnit(backgroundContrast)
    }

    static let unavailable = RegionRelationships()

    /// Derives relationships using the primary subject selected from the same assembled regions.
    /// Missing evidence remains nil; no relationship is inferred from global values alone.
    static func make(
        globalTone: ToneStatistics,
        regions: [AnalyzedRegion],
        primarySubject: PrimarySubjectSelection
    ) -> RegionRelationships {
        guard let primaryID = primarySubject.primaryRegionID,
              let subject = regions.first(where: { $0.id == primaryID }),
              let globalMean = perceptualMean(globalTone),
              let subjectMean = perceptualMean(subject.tone) else {
            return .unavailable
        }

        let background = regions.first { $0.kind == .background }
        let backgroundMean = background.flatMap { perceptualMean($0.tone) }
        let face = bestFace(for: subject, in: regions)
        let faceMean = face.flatMap { perceptualMean($0.tone) }
        let subjectGlobalDelta = subjectMean - globalMean
        let subjectBackgroundDelta = backgroundMean.map { subjectMean - $0 }
        let faceSubjectDelta = faceMean.map { $0 - subjectMean }
        let faceBackgroundDelta: Float? = {
            guard let faceMean, let backgroundMean else { return nil }
            return faceMean - backgroundMean
        }()

        return RegionRelationships(
            subjectToGlobalLuminanceDelta: subjectGlobalDelta,
            subjectToBackgroundLuminanceDelta: subjectBackgroundDelta,
            faceToSubjectLuminanceDelta: faceSubjectDelta,
            faceToBackgroundLuminanceDelta: faceBackgroundDelta,
            subjectContrast: subjectBackgroundDelta.map { abs($0) },
            backgroundContrast: backgroundMean.map { abs($0 - globalMean) }
        )
    }

    private static func perceptualMean(_ tone: ToneStatistics) -> Float? {
        guard tone.variant == .perceptual, tone.mean.isFinite else { return nil }
        return min(max(tone.mean, 0), 1)
    }

    private static func bestFace(for subject: AnalyzedRegion, in regions: [AnalyzedRegion]) -> AnalyzedRegion? {
        regions
            .filter { isFace($0.kind) }
            .sorted { lhs, rhs in
                let leftOverlap = overlap(lhs.bounds, subject.bounds)
                let rightOverlap = overlap(rhs.bounds, subject.bounds)
                if leftOverlap != rightOverlap { return leftOverlap > rightOverlap }
                if lhs.confidence != rhs.confidence { return lhs.confidence > rhs.confidence }
                return lhs.id.uuidString < rhs.id.uuidString
            }
            .first
    }

    private static func isFace(_ kind: RegionKind) -> Bool {
        switch kind {
        case .face, .faceInstance: return true
        default: return false
        }
    }

    private static func overlap(_ lhs: NormalizedRect?, _ rhs: NormalizedRect?) -> Double {
        guard let lhs, let rhs else { return 0 }
        let width = max(0, min(lhs.maxX, rhs.maxX) - max(lhs.minX, rhs.minX))
        let height = max(0, min(lhs.maxY, rhs.maxY) - max(lhs.minY, rhs.minY))
        return width * height
    }

    private static func finiteDelta(_ value: Float?) -> Float? {
        guard let value, value.isFinite else { return nil }
        return min(max(value, -1), 1)
    }

    private static func finiteUnit(_ value: Float?) -> Float? {
        guard let value, value.isFinite else { return nil }
        return min(max(value, 0), 1)
    }
}

import Foundation

/// The analysis vocabulary intentionally reuses the mask vocabulary. A region is the analysis
/// view of a `RegionMask`, so introducing a parallel enum here would only create a conversion
/// table that can drift as new mask kinds are added. Vision's ontology has already been removed at
/// the provider boundary; `SemanticMaskKind` is a Lumo-owned value and is safe to reuse here.
typealias RegionKind = SemanticMaskKind

/// Scalar facts computed through one available semantic mask.
///
/// `importance` is deliberately a measured support score (`confidence * coverage`) rather than
/// a recommendation or an editing policy. The primary-subject ensemble may refine that fact in a
/// later analysis stage without changing this assembly boundary.
struct AnalyzedRegion: Sendable, Codable, Equatable, Identifiable {
    let id: UUID
    let kind: RegionKind
    let mask: RegionMaskReference
    let confidence: Float
    let importance: Float
    let tone: ToneStatistics
    let color: ColorStatistics
    let coverage: Float

    init(
        id: UUID,
        kind: RegionKind,
        mask: RegionMaskReference,
        confidence: Float,
        importance: Float,
        tone: ToneStatistics,
        color: ColorStatistics,
        coverage: Float
    ) {
        self.id = id
        self.kind = kind
        self.mask = mask
        self.confidence = Self.unit(confidence)
        self.importance = Self.unit(importance)
        self.tone = tone
        self.color = color
        self.coverage = Self.unit(coverage)
    }

    private static func unit(_ value: Float) -> Float {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }
}

/// Facts about one canonical source image. Relationship and scene fields intentionally do not
/// exist until LUMO-198/199 introduce their value types; growing this value then keeps this ticket
/// self-contained and avoids placeholder domain models.
///
/// `regions` contains only successfully analyzed masks supplied by the caller. Assembly never
/// invents a background region: it is present when the foreground provider returned its derived
/// `.background` mask (including the provider's full-background result when no foreground exists).
struct PhotoAnalysis: Sendable, Codable, Equatable {
    let version: AnalysisVersion
    let globalTone: ToneStatistics
    let colorStatistics: ColorStatistics
    let regions: [AnalyzedRegion]
    let quality: AnalysisQuality
    let timings: AnalysisTimings

    init(
        version: AnalysisVersion = .current,
        globalTone: ToneStatistics,
        colorStatistics: ColorStatistics,
        regions: [AnalyzedRegion] = [],
        quality: AnalysisQuality,
        timings: AnalysisTimings = .zero
    ) {
        self.version = version
        self.globalTone = globalTone
        self.colorStatistics = colorStatistics
        self.regions = regions
        self.quality = quality
        self.timings = timings
    }
}

/// The asynchronous seams needed to assemble a `PhotoAnalysis`. Both analyzers remain injectable
/// so tests and callers that share a provider's `MaskStore` do not need to expose pixels here.
struct PhotoAnalysisAssembler: Sendable {
    private let globalToneAnalyzer: GlobalToneAnalyzer
    private let maskedToneAnalyzer: MaskedToneAnalyzer

    init(
        globalToneAnalyzer: GlobalToneAnalyzer = GlobalToneAnalyzer(),
        maskedToneAnalyzer: MaskedToneAnalyzer = MaskedToneAnalyzer()
    ) {
        self.globalToneAnalyzer = globalToneAnalyzer
        self.maskedToneAnalyzer = maskedToneAnalyzer
    }

    func assemble(
        image: AnalysisImage,
        masks: [RegionMask],
        version: AnalysisVersion = .current,
        timings: AnalysisTimings = .zero
    ) async throws -> PhotoAnalysis {
        let global = try await globalToneAnalyzer.analyze(image: image)

        var regions: [AnalyzedRegion] = []
        regions.reserveCapacity(masks.count)
        for mask in masks {
            try Task.checkCancellation()
            let statistics: (tone: ToneStatistics, color: ColorStatistics)
            do {
                statistics = try await maskedToneAnalyzer.statistics(image: image, through: mask)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // Mask production is optional. A missing pixel payload or an analyzer failure is
                // represented by omission from regions and the corresponding quality flag below.
                continue
            }

            regions.append(AnalyzedRegion(
                id: mask.id,
                kind: mask.kind,
                mask: mask.reference,
                confidence: mask.confidence,
                importance: mask.confidence * mask.coverage,
                tone: statistics.tone,
                color: statistics.color,
                coverage: mask.coverage
            ))
        }

        try Task.checkCancellation()

        let quality = Self.quality(global: global.quality, regions: regions)
        return PhotoAnalysis(
            version: version,
            globalTone: global.tone.perceptual,
            colorStatistics: global.color,
            regions: regions,
            quality: quality,
            timings: timings
        )
    }

    private static func quality(
        global: AnalysisQuality,
        regions: [AnalyzedRegion]
    ) -> AnalysisQuality {
        let attentionAvailable = regions.contains { $0.kind == .subject }
        let foregroundAvailable = regions.contains {
            switch $0.kind {
            case .background, .foregroundInstance:
                return true
            default:
                return false
            }
        }
        let faceAnalysisAvailable = regions.contains {
            switch $0.kind {
            case .face, .faceInstance:
                return true
            default:
                return false
            }
        }
        let peopleAnalysisAvailable = regions.contains {
            if case .person = $0.kind { return true }
            return false
        }

        let confidenceSamples = [global.overallConfidence] + regions.map(\.confidence)
        let overallConfidence = confidenceSamples.reduce(0, +) / Float(confidenceSamples.count)
        return AnalysisQuality(
            globalToneAvailable: global.globalToneAvailable,
            attentionAvailable: attentionAvailable,
            foregroundAvailable: foregroundAvailable,
            faceAnalysisAvailable: faceAnalysisAvailable,
            peopleAnalysisAvailable: peopleAnalysisAvailable,
            overallConfidence: overallConfidence
        )
    }
}

extension PhotoAnalysis {
    /// Convenience entry point for callers that already have analyzers configured with the same
    /// renderer and `MaskStore` as their mask providers.
    static func assemble(
        image: AnalysisImage,
        masks: [RegionMask],
        version: AnalysisVersion = .current,
        timings: AnalysisTimings = .zero,
        globalToneAnalyzer: GlobalToneAnalyzer = GlobalToneAnalyzer(),
        maskedToneAnalyzer: MaskedToneAnalyzer = MaskedToneAnalyzer()
    ) async throws -> PhotoAnalysis {
        try await PhotoAnalysisAssembler(
            globalToneAnalyzer: globalToneAnalyzer,
            maskedToneAnalyzer: maskedToneAnalyzer
        ).assemble(image: image, masks: masks, version: version, timings: timings)
    }

    /// Label matching the domain term used by the architecture proposal.
    static func assemble(
        image: AnalysisImage,
        masks: [RegionMask],
        version: AnalysisVersion = .current,
        timings: AnalysisTimings = .zero,
        globalToneAnalyzer: GlobalToneAnalyzer = GlobalToneAnalyzer(),
        toneAnalyzer: MaskedToneAnalyzer
    ) async throws -> PhotoAnalysis {
        try await assemble(
            image: image,
            masks: masks,
            version: version,
            timings: timings,
            globalToneAnalyzer: globalToneAnalyzer,
            maskedToneAnalyzer: toneAnalyzer
        )
    }
}

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
    /// The normalized image-space extent of the analyzed mask. This is retained from the mask
    /// boundary so downstream pure analysis can compare regions spatially without seeing pixels.
    let bounds: NormalizedRect?
    let confidence: Float
    let importance: Float
    let tone: ToneStatistics
    let color: ColorStatistics
    let coverage: Float

    init(
        id: UUID,
        kind: RegionKind,
        mask: RegionMaskReference,
        bounds: NormalizedRect? = nil,
        confidence: Float,
        importance: Float,
        tone: ToneStatistics,
        color: ColorStatistics,
        coverage: Float
    ) {
        self.id = id
        self.kind = kind
        self.mask = mask
        self.bounds = bounds
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
    let primarySubject: PrimarySubjectSelection
    let relationships: RegionRelationships
    let scene: SceneCharacteristics
    let quality: AnalysisQuality
    let timings: AnalysisTimings

    init(
        version: AnalysisVersion = .current,
        globalTone: ToneStatistics,
        colorStatistics: ColorStatistics,
        regions: [AnalyzedRegion] = [],
        primarySubject: PrimarySubjectSelection = .none,
        relationships: RegionRelationships? = nil,
        scene: SceneCharacteristics? = nil,
        quality: AnalysisQuality,
        timings: AnalysisTimings = .zero
    ) {
        self.version = version
        self.globalTone = globalTone
        self.colorStatistics = colorStatistics
        self.regions = regions
        self.primarySubject = primarySubject
        let resolvedRelationships = relationships ?? RegionRelationships.make(
            globalTone: globalTone, regions: regions, primarySubject: primarySubject
        )
        self.relationships = resolvedRelationships
        self.scene = scene ?? SceneCharacteristicsAnalyzer.analyze(
            globalTone: globalTone,
            regions: regions,
            relationships: resolvedRelationships,
            primarySubject: primarySubject
        )
        self.quality = quality
        self.timings = timings
    }

    private enum CodingKeys: String, CodingKey {
        case version, globalTone, colorStatistics, regions, primarySubject, relationships, scene,
             quality, timings
    }

    /// Scene characteristics were added after the first cache schema. A missing scene is safely
    /// reconstructed from the persisted scalar evidence rather than invalidating a usable cache.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decodeIfPresent(AnalysisVersion.self, forKey: .version) ?? .current
        let globalTone = try container.decode(ToneStatistics.self, forKey: .globalTone)
        let colorStatistics = try container.decode(ColorStatistics.self, forKey: .colorStatistics)
        let regions = try container.decodeIfPresent([AnalyzedRegion].self, forKey: .regions) ?? []
        let primarySubject = try container.decodeIfPresent(
            PrimarySubjectSelection.self, forKey: .primarySubject
        ) ?? .none
        let relationships = try container.decodeIfPresent(
            RegionRelationships.self, forKey: .relationships
        ) ?? RegionRelationships.make(
            globalTone: globalTone, regions: regions, primarySubject: primarySubject
        )
        self.version = version
        self.globalTone = globalTone
        self.colorStatistics = colorStatistics
        self.regions = regions
        self.primarySubject = primarySubject
        self.relationships = relationships
        self.scene = try container.decodeIfPresent(SceneCharacteristics.self, forKey: .scene)
            ?? SceneCharacteristicsAnalyzer.analyze(
                globalTone: globalTone,
                regions: regions,
                relationships: relationships,
                primarySubject: primarySubject
            )
        self.quality = try container.decodeIfPresent(AnalysisQuality.self, forKey: .quality)
            ?? .unavailable
        self.timings = try container.decodeIfPresent(AnalysisTimings.self, forKey: .timings) ?? .zero
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
        let clock = ContinuousClock()
        let assemblyStart = clock.now
        var assemblyInterval = LumoObservability.begin(
            .analysisAssembly, source: image.source, maskQuality: .analysis
        )
        defer { assemblyInterval.end() }

        let globalStart = clock.now
        let global = try await globalToneAnalyzer.analyze(image: image)
        let globalDuration = globalStart.duration(to: clock.now)

        var regions: [AnalyzedRegion] = []
        regions.reserveCapacity(masks.count)
        let regionalStart = clock.now
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

            regions.append(
                AnalyzedRegion(
                    id: mask.id,
                    kind: mask.kind,
                    mask: mask.reference,
                    bounds: mask.bounds,
                    confidence: mask.confidence,
                    importance: mask.confidence * mask.coverage,
                    tone: statistics.tone,
                    color: statistics.color,
                    coverage: mask.coverage
                ))
        }

        try Task.checkCancellation()

        let quality = Self.quality(global: global.quality, regions: regions)
        let regionalDuration = regionalStart.duration(to: clock.now)
        let assemblyDuration = assemblyStart.duration(to: clock.now)
        let totalDuration = max(timings.total, assemblyDuration)
        let primarySubject = PrimarySubjectSelector.select(from: regions)
        return PhotoAnalysis(
            version: version,
            globalTone: global.tone.perceptual,
            colorStatistics: global.color,
            regions: regions,
            primarySubject: primarySubject,
            relationships: RegionRelationships.make(
                globalTone: global.tone.perceptual,
                regions: regions,
                primarySubject: primarySubject
            ),
            quality: quality,
            timings: timings.replacing(
                globalTone: globalDuration,
                regionalAnalysis: regionalDuration,
                total: totalDuration
            )
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
    func withTimings(_ timings: AnalysisTimings) -> PhotoAnalysis {
        PhotoAnalysis(
            version: version,
            globalTone: globalTone,
            colorStatistics: colorStatistics,
            regions: regions,
            primarySubject: primarySubject,
            relationships: relationships,
            scene: scene,
            quality: quality,
            timings: timings
        )
    }

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

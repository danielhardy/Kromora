import Foundation
import XCTest

@testable import KromoraKit

/// Scene-classification evidence and per-signal confidence (KRMA-344).
///
/// Every test works from synthetic scalar facts — no image files, no live Vision calls — plus a
/// stub classifier for the unavailable-labels path and a garbage-data source for the adapter
/// failure path. Likelihoods are asserted as continuous evidence ranges, never as winning labels.
final class SceneEvidenceTests: XCTestCase {
    // MARK: - Fixtures

    private func tone(
        mean: Float, p05: Float, p25: Float, p50: Float, p75: Float, p90: Float, p95: Float,
        highlightClipping: Float = 0
    ) -> ToneStatistics {
        ToneStatistics(
            variant: .perceptual, minimum: p05, maximum: p95, mean: mean,
            p05: p05, p25: p25, p50: p50, p75: p75, p90: p90, p95: p95,
            highlightClippingFraction: highlightClipping
        )
    }

    private func color(
        r: Float, g: Float, b: Float,
        saturationMedian: Float, colorfulness: Float, neutrality: Float,
        isMixed: Bool = false, hueEntropy: Float? = nil
    ) -> SceneColorFacts {
        SceneColorFacts(
            meanR: r, meanG: g, meanB: b, saturationMedian: saturationMedian,
            colorfulness: colorfulness, estimatedNeutrality: neutrality,
            isMixed: isMixed, hueEntropy: hueEntropy
        )
    }

    private func region(
        kind: RegionKind, mean: Float, coverage: Float, confidence: Float
    ) -> AnalyzedRegion {
        let key = MaskCacheKey(
            assetID: PhotoAssetID.data(Data("scene-evidence".utf8)),
            sourceFingerprint: PhotoSourceFingerprint.data(Data("scene-evidence".utf8)),
            kind: kind
        )
        return AnalyzedRegion(
            id: UUID(), kind: kind,
            mask: RegionMaskReference(
                cacheKey: key, size: PixelDimensions(width: 4, height: 4)
            ),
            confidence: confidence, importance: confidence * coverage,
            tone: tone(
                mean: mean, p05: mean, p25: mean, p50: mean, p75: mean, p90: mean, p95: mean
            ),
            color: .neutral, coverage: coverage
        )
    }

    private func analyze(
        tone: ToneStatistics,
        color: SceneColorFacts,
        regions: [AnalyzedRegion] = [],
        classifications: [SceneClassificationObservation]? = nil
    ) -> SceneCharacteristics {
        let primary = PrimarySubjectSelector.select(from: regions)
        return SceneCharacteristicsAnalyzer.analyze(
            globalTone: tone, color: color, regions: regions,
            relationships: RegionRelationships.make(
                globalTone: tone, regions: regions, primarySubject: primary
            ),
            primarySubject: primary, classifications: classifications
        )
    }

    private func daylightTone() -> ToneStatistics {
        tone(mean: 0.48, p05: 0.15, p25: 0.30, p50: 0.48, p75: 0.65, p90: 0.80, p95: 0.86)
    }

    private func daylightColor() -> SceneColorFacts {
        color(
            r: 0.48, g: 0.47, b: 0.45, saturationMedian: 0.08, colorfulness: 0.30,
            neutrality: 0.80
        )
    }

    // MARK: - Scene evidence ranges

    func testNightFixtureProducesNightEvidenceWithoutAPreset() {
        let scene = analyze(
            tone: tone(mean: 0.12, p05: 0.02, p25: 0.06, p50: 0.10, p75: 0.18, p90: 0.30, p95: 0.38),
            color: daylightColor()
        )

        XCTAssertGreaterThan(scene.nightLikelihood, 0.5)
        XCTAssertLessThan(scene.daylightLikelihood, 0.3)
        XCTAssertLessThan(scene.snowLikelihood, 0.3)
        XCTAssertTrue((0...1).contains(scene.sceneConfidence))
    }

    func testSunsetWarmFixtureRespondsToWarmthAndCoolFrameDoesNot() {
        let warm = analyze(
            tone: tone(mean: 0.42, p05: 0.10, p25: 0.25, p50: 0.40, p75: 0.58, p90: 0.70, p95: 0.80),
            color: color(
                r: 0.55, g: 0.40, b: 0.28, saturationMedian: 0.25, colorfulness: 0.50,
                neutrality: 0.30
            )
        )
        let cool = analyze(
            tone: tone(mean: 0.42, p05: 0.10, p25: 0.25, p50: 0.40, p75: 0.58, p90: 0.70, p95: 0.80),
            color: color(
                r: 0.35, g: 0.42, b: 0.48, saturationMedian: 0.20, colorfulness: 0.45,
                neutrality: 0.35
            )
        )

        XCTAssertGreaterThan(warm.sunsetWarmLikelihood, 0.4)
        XCTAssertLessThan(cool.sunsetWarmLikelihood, 0.2)
    }

    func testSnowFixtureIsSnowyAndFogFixtureIsFoggy() {
        let snow = analyze(
            tone: tone(mean: 0.80, p05: 0.55, p25: 0.65, p50: 0.80, p75: 0.88, p90: 0.93, p95: 0.96),
            color: color(
                r: 0.80, g: 0.80, b: 0.79, saturationMedian: 0.04, colorfulness: 0.10,
                neutrality: 0.90
            )
        )
        let fog = analyze(
            tone: tone(mean: 0.55, p05: 0.40, p25: 0.48, p50: 0.55, p75: 0.62, p90: 0.68, p95: 0.70),
            color: color(
                r: 0.55, g: 0.55, b: 0.54, saturationMedian: 0.05, colorfulness: 0.15,
                neutrality: 0.70
            )
        )

        XCTAssertGreaterThan(snow.snowLikelihood, 0.4)
        XCTAssertGreaterThan(snow.snowLikelihood, snow.fogLikelihood)
        XCTAssertGreaterThan(fog.fogLikelihood, 0.4)
        XCTAssertLessThan(fog.snowLikelihood, 0.3)
    }

    func testMonochromeRespondsToColorlessnessNotTone() {
        let mono = analyze(
            tone: daylightTone(),
            color: color(
                r: 0.48, g: 0.48, b: 0.48, saturationMedian: 0.01, colorfulness: 0.02,
                neutrality: 0.95
            )
        )
        let colorful = analyze(
            tone: daylightTone(),
            color: color(
                r: 0.55, g: 0.40, b: 0.30, saturationMedian: 0.30, colorfulness: 0.60,
                neutrality: 0.20
            )
        )

        XCTAssertGreaterThan(mono.monochromeLikelihood, 0.5)
        XCTAssertLessThan(colorful.monochromeLikelihood, 0.2)
    }

    func testMixedLightRequiresHueEvidenceAndIsNeverInvented() {
        let mixed = analyze(
            tone: daylightTone(),
            color: color(
                r: 0.48, g: 0.46, b: 0.44, saturationMedian: 0.15, colorfulness: 0.40,
                neutrality: 0.40, isMixed: true, hueEntropy: 0.85
            )
        )
        let unknown = analyze(tone: daylightTone(), color: daylightColor())

        XCTAssertGreaterThan(mixed.mixedLightLikelihood, 0.5)
        XCTAssertEqual(unknown.mixedLightLikelihood, 0)
    }

    func testOrdinaryDaylightIsPositiveEvidenceNotAResidual() {
        let subject = region(kind: .subject, mean: 0.50, coverage: 0.25, confidence: 0.85)
        let background = region(kind: .background, mean: 0.46, coverage: 0.75, confidence: 0.9)
        let scene = analyze(
            tone: daylightTone(), color: daylightColor(), regions: [subject, background]
        )

        XCTAssertGreaterThan(scene.daylightLikelihood, 0.4)
        XCTAssertLessThan(scene.nightLikelihood, 0.3)
        XCTAssertLessThan(scene.sunsetWarmLikelihood, 0.3)
        XCTAssertTrue(scene.provenance.usedRegions)
    }

    // MARK: - Vision labels refine but never decide

    func testMatchingLabelsBoostEvidenceAndUnrelatedLabelsDoNot() {
        let base = daylightTone()
        let baseColor = daylightColor()
        let without = analyze(tone: base, color: baseColor, classifications: nil)
        let sunsetLabels = [SceneClassificationObservation(identifier: "sunset", confidence: 0.9)]
        let withMatch = analyze(
            tone: base, color: baseColor, classifications: sunsetLabels
        )
        let unrelated = [SceneClassificationObservation(identifier: "tabby_cat", confidence: 0.9)]
        let withUnrelated = analyze(
            tone: base, color: baseColor, classifications: unrelated
        )

        XCTAssertGreaterThan(
            withMatch.sunsetWarmLikelihood, without.sunsetWarmLikelihood
        )
        XCTAssertEqual(
            withUnrelated.sunsetWarmLikelihood, without.sunsetWarmLikelihood, accuracy: 0.001
        )
        // Labels refine: the capped contribution can never push an unsupported cue over one half.
        XCTAssertLessThan(withMatch.sunsetWarmLikelihood, 0.5)
        XCTAssertTrue(withMatch.provenance.usedVisionLabels)
        XCTAssertTrue(withMatch.provenance.visionLabelsAvailable)
        XCTAssertFalse(without.provenance.visionLabelsAvailable)
    }

    func testContradictedLabelsReduceConfidenceWithoutOverridingMeasurement() {
        let labels = [SceneClassificationObservation(identifier: "night", confidence: 0.9)]
        let agreed = analyze(
            tone: tone(
                mean: 0.80, p05: 0.55, p25: 0.65, p50: 0.80, p75: 0.88, p90: 0.93, p95: 0.96
            ),
            color: color(
                r: 0.80, g: 0.80, b: 0.79, saturationMedian: 0.04, colorfulness: 0.10,
                neutrality: 0.90
            ),
            classifications: [
                SceneClassificationObservation(identifier: "snowfield", confidence: 0.9),
            ]
        )
        let contradicted = analyze(
            tone: daylightTone(), color: daylightColor(), classifications: labels
        )
        // Agreement keeps confidence at the no-regions level; contradiction scales it further.
        XCTAssertEqual(agreed.sceneConfidence, 0.8, accuracy: 0.001)
        XCTAssertLessThan(contradicted.sceneConfidence, agreed.sceneConfidence)
        // The measurement still wins: daylight pixels are not relabeled night.
        XCTAssertLessThan(contradicted.nightLikelihood, 0.5)
        XCTAssertGreaterThan(contradicted.daylightLikelihood, contradicted.nightLikelihood)
    }

    func testMissingLabelsAndRegionsDegradeConfidenceWithoutInvalidatingGlobals() {
        let subject = region(kind: .subject, mean: 0.50, coverage: 0.25, confidence: 0.85)
        let full = analyze(
            tone: daylightTone(), color: daylightColor(), regions: [subject],
            classifications: [SceneClassificationObservation(identifier: "beach", confidence: 0.7)]
        )
        let degraded = analyze(tone: daylightTone(), color: daylightColor())

        XCTAssertEqual(full.sceneConfidence, 1.0, accuracy: 0.001)
        XCTAssertLessThan(degraded.sceneConfidence, full.sceneConfidence)
        XCTAssertGreaterThan(degraded.sceneConfidence, 0)
        // Global facts are untouched by the degradation.
        XCTAssertEqual(degraded.tonalKey, full.tonalKey)
        XCTAssertEqual(degraded.daylightLikelihood, full.daylightLikelihood, accuracy: 0.001)
    }

    // MARK: - Per-signal confidence

    func testFullSignalsReportHighOverallAndPerProviderEvidence() {
        let subject = region(kind: .subject, mean: 0.50, coverage: 0.25, confidence: 0.85)
        let face = region(kind: .face, mean: 0.52, coverage: 0.04, confidence: 0.9)
        let regions = [subject, face]
        let primary = PrimarySubjectSelector.select(from: regions)
        let labels = [SceneClassificationObservation(identifier: "beach", confidence: 0.7)]
        let confidence = AutoSignalConfidence.make(
            globalToneAvailable: true, color: daylightColor(), sceneConfidence: 1,
            regions: regions, primarySubject: primary, classifications: labels,
            detailAvailable: true
        )

        XCTAssertEqual(confidence.globalTone, 1)
        XCTAssertGreaterThan(confidence.overall, 0.7)
        XCTAssertEqual(confidence.detail, 1)
        XCTAssertNotNil(confidence.providers.attention)
        XCTAssertNotNil(confidence.providers.face)
        XCTAssertNil(confidence.providers.person)
        XCTAssertNotNil(confidence.providers.sceneClassifier)
    }

    func testMissingSignalsReduceOverallWithoutErasingUsableMeasurements() {
        let subject = region(kind: .subject, mean: 0.50, coverage: 0.25, confidence: 0.85)
        let primary = PrimarySubjectSelector.select(from: [subject])
        let full = AutoSignalConfidence.make(
            globalToneAvailable: true, color: daylightColor(), sceneConfidence: 1,
            regions: [subject], primarySubject: primary,
            classifications: [SceneClassificationObservation(
                identifier: "beach", confidence: 0.7
            )],
            detailAvailable: true
        )
        let degraded = AutoSignalConfidence.make(
            globalToneAvailable: true, color: daylightColor(), sceneConfidence: 0.65,
            regions: [], primarySubject: .none, classifications: nil, detailAvailable: nil
        )

        XCTAssertLessThan(degraded.overall, full.overall)
        XCTAssertEqual(degraded.globalTone, 1)
        XCTAssertGreaterThan(degraded.colorNeutral, 0)
        XCTAssertNil(degraded.detail)
        XCTAssertEqual(degraded.providers.availableCount, 0)
    }

    func testFailedMasksAndMixedColorReduceOnlyTheirOwnTerms() {
        let subject = region(kind: .subject, mean: 0.50, coverage: 0.25, confidence: 0.85)
        let primary = PrimarySubjectSelector.select(from: [subject])
        let clean = AutoSignalConfidence.make(
            globalToneAvailable: true, color: daylightColor(), sceneConfidence: 1,
            regions: [subject], primarySubject: primary, classifications: nil,
            detailAvailable: nil
        )
        let withFailures = AutoSignalConfidence.make(
            globalToneAvailable: true, color: daylightColor(), sceneConfidence: 1,
            regions: [subject], primarySubject: primary, classifications: nil,
            detailAvailable: nil, failedMaskCount: 2
        )
        let mixedColor = color(
            r: 0.48, g: 0.46, b: 0.44, saturationMedian: 0.15, colorfulness: 0.40,
            neutrality: 0.40, isMixed: true, hueEntropy: 0.85
        )
        let mixed = AutoSignalConfidence.make(
            globalToneAvailable: true, color: mixedColor, sceneConfidence: 1,
            regions: [subject], primarySubject: primary, classifications: nil,
            detailAvailable: nil
        )

        XCTAssertLessThan(withFailures.subjectRegions, clean.subjectRegions)
        XCTAssertEqual(withFailures.globalTone, clean.globalTone)
        XCTAssertEqual(withFailures.colorNeutral, clean.colorNeutral)
        XCTAssertLessThan(mixed.colorNeutral, clean.colorNeutral)
        XCTAssertEqual(mixed.globalTone, clean.globalTone)
    }

    // MARK: - Current-render bridge

    func testMeasurementBridgeDerivesSceneFromRenderedFacts() {
        let fingerprint = PhotoSourceFingerprint.data(Data("bridge".utf8))
        let perceptual = tone(
            mean: 0.48, p05: 0.15, p25: 0.30, p50: 0.48, p75: 0.65, p90: 0.80, p95: 0.86
        )
        let measurement = CurrentEditMeasurement(
            sourceFingerprint: fingerprint, documentHash: "doc", effectiveDocumentHash: "doc",
            configurationFingerprint: "config", space: .sRGB, isAnalysisView: true,
            isBaseline: true,
            globalTone: LuminanceDistribution(linear: .neutral, perceptual: perceptual),
            color: PixelCorrelatedColor(
                meanRGB: SIMD3<Float>(0.48, 0.47, 0.45),
                medianRGB: SIMD3<Float>(0.48, 0.47, 0.45),
                saturationMedian: 0.08, estimatedNeutrality: 0.80, colorfulness: 0.30
            ),
            highlightHeadroom: HighlightHeadroom(displayHighlightClipping: 0),
            localContrast: 0.1, localContrastConfidence: 0.5
        )

        let scene = SceneCharacteristicsAnalyzer.analyze(measurement: measurement)

        XCTAssertGreaterThan(scene.daylightLikelihood, 0.4)
        XCTAssertLessThan(scene.nightLikelihood, 0.3)
        // No regions and no labels: reduced confidence, usable facts.
        XCTAssertLessThan(scene.sceneConfidence, 1)
        XCTAssertGreaterThan(scene.sceneConfidence, 0)
    }

    func testMeasurementBridgeCarriesMixedLightEvidence() {
        let fingerprint = PhotoSourceFingerprint.data(Data("bridge-mixed".utf8))
        let perceptual = daylightTone()
        let measurement = CurrentEditMeasurement(
            sourceFingerprint: fingerprint, documentHash: "doc", effectiveDocumentHash: "doc",
            configurationFingerprint: "config", space: .sRGB, isAnalysisView: true,
            isBaseline: false,
            globalTone: LuminanceDistribution(linear: .neutral, perceptual: perceptual),
            color: PixelCorrelatedColor(
                meanRGB: SIMD3<Float>(0.48, 0.46, 0.44),
                medianRGB: SIMD3<Float>(0.48, 0.46, 0.44),
                saturationMedian: 0.15, hueEntropy: 0.85, estimatedNeutrality: 0.40,
                colorfulness: 0.40, isMixed: true
            ),
            highlightHeadroom: HighlightHeadroom(displayHighlightClipping: 0),
            localContrast: 0.1, localContrastConfidence: 0.5
        )

        XCTAssertGreaterThan(
            SceneCharacteristicsAnalyzer.analyze(measurement: measurement).mixedLightLikelihood, 0.5
        )
    }

    // MARK: - Adapter failure paths

    func testStubClassifierUnavailableKeepsAnalysisUsable() async throws {
        struct NilClassifier: SceneClassifierProviding {
            func classifications(for image: AnalysisImage) async -> [SceneClassificationObservation]? {
                nil
            }
        }
        let source = ImageSource(
            data: Data("not-an-image".utf8), nativeExtent: CGSize(width: 64, height: 64)
        )
        let image = try AnalysisImageFactory.make(from: source)
        let observations = await NilClassifier().classifications(for: image)

        XCTAssertNil(observations)
        // The analyzer treats `nil` as missing evidence, not an error.
        let scene = analyze(tone: daylightTone(), color: daylightColor(), classifications: observations)
        XCTAssertGreaterThan(scene.daylightLikelihood, 0.4)
        XCTAssertFalse(scene.provenance.visionLabelsAvailable)
    }

    func testVisionAdapterReturnsMissingEvidenceForUndecodableSource() async throws {
        let source = ImageSource(
            data: Data("not-an-image".utf8), nativeExtent: CGSize(width: 64, height: 64)
        )
        let image = try AnalysisImageFactory.make(from: source)
        let observations = await VisionSceneClassifier().classifications(for: image)

        XCTAssertNil(observations)
    }

    // MARK: - Cache backward compatibility

    func testLegacySceneJSONDecodesToNeutralDefaults() throws {
        let subject = region(kind: .subject, mean: 0.50, coverage: 0.25, confidence: 0.85)
        let current = analyze(
            tone: daylightTone(), color: daylightColor(), regions: [subject],
            classifications: [SceneClassificationObservation(identifier: "beach", confidence: 0.7)]
        )
        var dictionary = try JSONDecoder().decode(
            [String: AnyDecodableJSON].self, from: JSONEncoder().encode(current)
        )
        for key in [
            "nightLikelihood", "sunsetWarmLikelihood", "snowLikelihood", "fogLikelihood",
            "monochromeLikelihood", "mixedLightLikelihood", "daylightLikelihood",
            "sceneConfidence", "provenance",
        ] {
            dictionary.removeValue(forKey: key)
        }
        let legacy = try JSONDecoder().decode(
            SceneCharacteristics.self,
            from: JSONEncoder().encode(dictionary)
        )

        XCTAssertEqual(legacy.nightLikelihood, 0)
        XCTAssertEqual(legacy.daylightLikelihood, 0)
        XCTAssertEqual(legacy.sceneConfidence, SceneCharacteristics.legacyConfidence)
        XCTAssertFalse(legacy.provenance.visionLabelsAvailable)
        // Pre-existing likelihoods survive the migration untouched.
        XCTAssertEqual(legacy.backlightingLikelihood, current.backlightingLikelihood)
        XCTAssertEqual(legacy.highKeyLikelihood, current.highKeyLikelihood)
        XCTAssertEqual(legacy.lowKeyLikelihood, current.lowKeyLikelihood)
    }

    func testStoredLabelsKeepSceneReproducibleFromPersistedFacts() throws {
        let subject = region(kind: .subject, mean: 0.50, coverage: 0.25, confidence: 0.85)
        let primary = PrimarySubjectSelector.select(from: [subject])
        let labels = [SceneClassificationObservation(identifier: "snowfield", confidence: 0.9)]
        let analysis = PhotoAnalysis(
            globalTone: daylightTone(), colorStatistics: .neutral, regions: [subject],
            primarySubject: primary, classifications: labels,
            quality: AnalysisQuality(globalToneAvailable: true, overallConfidence: 1)
        )
        let roundTripped = try JSONDecoder().decode(
            PhotoAnalysis.self, from: JSONEncoder().encode(analysis)
        )

        XCTAssertEqual(roundTripped.sceneClassifications, labels)
        XCTAssertEqual(roundTripped.scene, SceneCharacteristicsAnalyzer.analyze(roundTripped))
        XCTAssertEqual(roundTripped.signalConfidence.providers.sceneClassifier, 0.9)
    }

    func testLegacyAnalysisJSONDecodesWithDerivedConfidenceAndSameVersion() throws {
        let subject = region(kind: .subject, mean: 0.50, coverage: 0.25, confidence: 0.85)
        let primary = PrimarySubjectSelector.select(from: [subject])
        let vivid = ColorStatistics(
            meanRGB: SIMD3<Float>(0.48, 0.47, 0.45),
            saturationMedian: 0.08, estimatedNeutrality: 0.80, colorfulness: 0.30
        )
        let current = PhotoAnalysis(
            globalTone: daylightTone(), colorStatistics: vivid, regions: [subject],
            primarySubject: primary,
            quality: AnalysisQuality(globalToneAvailable: true, overallConfidence: 1)
        )
        var dictionary = try JSONDecoder().decode(
            [String: AnyDecodableJSON].self, from: JSONEncoder().encode(current)
        )
        dictionary.removeValue(forKey: "scene")
        dictionary.removeValue(forKey: "sceneClassifications")
        dictionary.removeValue(forKey: "signalConfidence")
        let legacy = try JSONDecoder().decode(
            PhotoAnalysis.self, from: JSONEncoder().encode(dictionary)
        )

        // Pre-KRMA-344 caches remain readable under the same schema version.
        XCTAssertEqual(legacy.version, .current)
        XCTAssertEqual(legacy.globalTone, current.globalTone)
        XCTAssertEqual(legacy.regions, current.regions)
        // Missing values are re-derived from the persisted facts with no Vision labels and no
        // native detail — neutral provenance, not invented evidence.
        XCTAssertGreaterThan(legacy.scene.daylightLikelihood, 0.4)
        XCTAssertFalse(legacy.scene.provenance.visionLabelsAvailable)
        XCTAssertEqual(legacy.signalConfidence.globalTone, 1)
        XCTAssertNil(legacy.signalConfidence.detail)
        XCTAssertGreaterThan(legacy.signalConfidence.overall, 0)
        // A current value still round-trips exactly.
        XCTAssertEqual(
            try JSONDecoder().decode(
                PhotoAnalysis.self, from: JSONEncoder().encode(current)
            ),
            current
        )
    }
}

/// Type-erased JSON value so tests can drop keys to simulate pre-KRMA-344 caches.
private struct AnyDecodableJSON: Codable {
    let value: Any

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let bool = try? container.decode(Bool.self) { value = bool } else if let int = try? container.decode(Int.self) { value = int } else if let double = try? container.decode(Double.self) { value = double } else if let string = try? container.decode(String.self) { value = string } else if let array = try? container.decode([AnyDecodableJSON].self) { value = array } else if let object = try? container.decode([String: AnyDecodableJSON].self) { value = object } else if container.decodeNil() { value = NSNull() } else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "unsupported JSON value"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let bool as Bool: try container.encode(bool)
        case let int as Int: try container.encode(int)
        case let double as Double: try container.encode(double)
        case let string as String: try container.encode(string)
        case let array as [AnyDecodableJSON]: try container.encode(array)
        case let object as [String: AnyDecodableJSON]: try container.encode(object)
        case is NSNull: try container.encodeNil()
        default:
            throw EncodingError.invalidValue(
                value, EncodingError.Context(
                    codingPath: encoder.codingPath, debugDescription: "unsupported JSON value"
                )
            )
        }
    }
}

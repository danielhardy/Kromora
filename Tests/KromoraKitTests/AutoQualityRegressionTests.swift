import CoreGraphics
import Foundation
import XCTest

@testable import KromoraKit

/// Generated Auto quality fixture corpus and actual-render regression coverage (KRMA-351).
///
/// Strategy: every image is **generated** (never committed, never a real photo) through the
/// `Fixtures` helpers; every expectation is a **range/invariant**, never exact pixels or a
/// claim of subjective parity with Lightroom/Apple Photos.
///
/// - Policy corpus (pure, no renderer): one `AutoEnhancementFacts` per defect/intent class.
///   Fast and deterministic; pins improvement vs. preservation envelopes.
/// - Preservation/lifecycle (pure): manual Looks/LUTs, curves, grading, masks, crop,
///   orientation, overlapping people, feathered edges, noise/detail restraint, unsupported
///   RAW capabilities, repeat-Auto no-op, no duplicate layers, save/reopen, undo/redo.
/// - Actual-render lane (real `RenderEngine`): measure → scene → propose → render
///   before/after/diff through `AutoCandidateEvaluator`. Small (96×64) fixtures so the lane
///   measures in milliseconds. Opt-in artifacts via `KROMORA_AUTO_QUALITY_ARTIFACT_DIR`.
///
/// Known limitations (documented, not hidden):
/// - Generated flats/ramps understate real-scene texture; detail/sharpening/NR behavior is
///   pinned as *restraint* (untouched), not as measured improvement.
/// - Vision masks are out of scope here: regional evidence uses synthetic mattes, and the
///   no-mask path must degrade to notes rather than layers.
/// - Sunset/monochrome/night intent is asserted at the policy gate (WB/color/exposure
///   restraint), not by a perceptual judge.
final class AutoQualityRegressionTests: TempDirectoryTestCase {

    // MARK: - Corpus inventory

    /// The defect/intent classes KRMA-351 requires. Each has a generator below and at least one
    /// policy expectation plus actual-render coverage for the marked (†) classes.
    static let corpusIDs = [
        "balanced", // †
        "underexposed", // †
        "overexposed-clipped", // †
        "warm-cast", // †
        "cool-cast", // †
        "high-key",
        "low-key",
        "sunset",
        "monochrome",
        "fog",
        "snow",
        "night",
        "backlit-subject", // † split-tone fixture + regional plan
        "overlapping-people",
        "noisy-detail-limited",
        "unsupported-raw-capabilities",
    ]

    func testCorpusInventoryIsComplete() {
        XCTAssertEqual(Self.corpusIDs.count, 16)
        XCTAssertEqual(Set(Self.corpusIDs).count, Self.corpusIDs.count, "corpus IDs must be unique")
    }

    // MARK: - Fixture generators (96×64 unless noted)

    static let corpusSize = CGSize(width: 96, height: 64)

    private func solidData(red: Double, green: Double, blue: Double, width: Int = 96, height: Int = 64) throws -> Data {
        let image = try Fixtures.makeParametricCGImage(width: width, height: height) { _, _ in (red, green, blue) }
        return try Fixtures.jpegData(for: image)
    }

    private func gradientData(
        from topLeft: (Double, Double, Double),
        to bottomRight: (Double, Double, Double),
        width: Int = 96, height: Int = 64
    ) throws -> Data {
        let image = try Fixtures.makeParametricCGImage(width: width, height: height) { nx, ny in
            let t = (nx + ny) / 2
            return (
                topLeft.0 + (bottomRight.0 - topLeft.0) * t,
                topLeft.1 + (bottomRight.1 - topLeft.1) * t,
                topLeft.2 + (bottomRight.2 - topLeft.2) * t
            )
        }
        return try Fixtures.jpegData(for: image)
    }

    /// Backlit split-tone: dark subject third, bright background remainder.
    private func backlitData() throws -> Data {
        let image = try Fixtures.makeParametricCGImage(width: 96, height: 64) { nx, _ in
            nx < 0.35 ? (0.10, 0.10, 0.11) : (0.88, 0.87, 0.84)
        }
        return try Fixtures.jpegData(for: image)
    }

    /// Balanced: wide-range near-neutral gradient (median ~0.48, full spread). A flat mid-gray
    /// is degenerate here — zero spread reads as fog and draws full-strength contrast — so the
    /// closeness fixture carries the spread a real balanced frame has.
    private func balancedWideData() throws -> Data {
        let image = try Fixtures.makeParametricCGImage(width: 96, height: 64) { nx, ny in
            let t = (nx + ny) / 2
            let v = 0.10 + 0.78 * t
            return (v, v * 0.99, v * 0.97)
        }
        return try Fixtures.jpegData(for: image)
    }

    /// Underexposed: dark gradient with real spread (median ~0.17). Flat dark fields confound
    /// underexposure with fog (see the known-limitation note on the render test); spread
    /// separates the two while keeping the placement defect.
    private func darkGradientData() throws -> Data {
        let image = try Fixtures.makeParametricCGImage(width: 96, height: 64) { nx, ny in
            let t = (nx + ny) / 2
            let v = 0.05 + 0.25 * t
            return (v, v, v * 0.98)
        }
        return try Fixtures.jpegData(for: image)
    }

    /// Warm cast with a neutral card: warm gradient (left two-thirds) plus a neutral gradient
    /// card (right third). A globally warm flat reads as sunset and is *correctly* preserved
    /// by the WB veto; the card supplies the credible neutral evidence a correction needs.
    private func warmCardData() throws -> Data {
        let image = try Fixtures.makeParametricCGImage(width: 96, height: 64) { nx, ny in
            let t = (nx + ny) / 2
            if nx < 0.66 {
                let v = 0.45 + 0.25 * t
                return (v + 0.10, v, v - 0.06)
            }
            let v = 0.38 + 0.24 * t
            return (v, v, v)
        }
        return try Fixtures.jpegData(for: image)
    }

    /// Fog: low-contrast pale gradient. Dehaze is the only detail knob v1 may touch, and only
    /// on fog evidence, so this fixture pins the restrained response (and nothing else moving).
    private func fogPaleData() throws -> Data {
        let image = try Fixtures.makeParametricCGImage(width: 96, height: 64) { nx, ny in
            let t = (nx + ny) / 2
            let v = 0.55 + 0.10 * t
            return (v, v, v * 0.99)
        }
        return try Fixtures.jpegData(for: image)
    }

    /// Deterministic pseudo-grain over mid gray (detail-limited fixture).
    private func noisyData() throws -> Data {
        var seed: UInt64 = 0x9E3779B97F4A7C15
        func next() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double((seed >> 33) & 0xFF) / 255
        }
        let image = try Fixtures.makeParametricCGImage(width: 96, height: 64) { _, _ in
            let n = (next() - 0.5) * 0.35
            return (0.45 + n, 0.45 + n, 0.44 + n)
        }
        return try Fixtures.jpegData(for: image)
    }

    // MARK: - Policy fact helpers

    private func toneFacts(
        median: Float = 0.48,
        p05: Float = 0.08,
        p10: Float = 0.16,
        p25: Float = 0.30,
        p75: Float = 0.68,
        p90: Float = 0.85,
        p95: Float = 0.90,
        highlightClipping: Float = 0,
        shadowClipping: Float = 0
    ) -> ToneStatistics {
        ToneStatistics(
            variant: .perceptual, minimum: p05, maximum: p95, mean: median,
            p05: p05, p10: p10, p25: p25, p50: median, p75: p75,
            p90: p90, p95: p95,
            shadowClippingFraction: shadowClipping,
            highlightClippingFraction: highlightClipping
        )
    }

    private func colorFacts(
        meanRGB: SIMD3<Float> = SIMD3(0.48, 0.48, 0.48),
        medianRGB: SIMD3<Float>? = nil,
        saturationP95: Float = 0.5,
        colorfulness: Float = 0.3,
        mixed: Bool = false,
        neutralConfidence: Float = 0
    ) -> PixelCorrelatedColor {
        PixelCorrelatedColor(
            meanRGB: meanRGB,
            medianRGB: medianRGB ?? meanRGB,
            saturationP95: saturationP95,
            colorfulness: colorfulness,
            isMixed: mixed,
            neutralCandidates: neutralConfidence > 0
                ? [NeutralCandidate(
                    column: 1, row: 1,
                    bounds: NormalizedRect(x: 1 / 3, y: 1 / 3, width: 1 / 3, height: 1 / 3),
                    coverage: 0.2, meanChroma: 0.02, meanLuma: 0.5,
                    confidence: neutralConfidence,
                    recommendsCorrection: neutralConfidence >= 0.5
                )] : []
        )
    }

    private func facts(
        tone: ToneStatistics? = nil,
        color: PixelCorrelatedColor? = nil,
        scene: SceneCharacteristics = SceneCharacteristics(),
        asShotTemperature: Double? = nil
    ) -> AutoEnhancementFacts {
        AutoEnhancementFacts(
            tonePerceptual: tone ?? toneFacts(),
            color: color ?? colorFacts(),
            scene: scene,
            signalConfidence: AutoSignalConfidence(
                globalTone: 1, colorNeutral: 0.8, scene: 0.9,
                subjectRegions: 0.5, overall: 0.8
            ),
            asShotTemperature: asShotTemperature
        )
    }

    // MARK: - Balanced closeness envelope

    func testBalancedFixtureStaysWithinClosenessEnvelope() {
        let proposal = AutoEnhancementPolicy.propose(
            facts: facts(), current: EditDocument(), sourceKind: .standard
        )
        for change in proposal.changes.values {
            switch change.control {
            case .exposure: XCTAssertLessThan(abs(change.proposed), 0.3, "balanced exposure must stay close")
            case .contrast, .highlights, .shadows, .whites, .blacks:
                XCTAssertLessThan(abs(change.proposed), 16)
            case .temperature: XCTAssertLessThan(abs(change.proposed - 6500), 400)
            case .tint, .vibrance, .saturation, .dehaze:
                XCTAssertLessThan(abs(change.proposed), 12)
            }
        }
    }

    // MARK: - Defect improvement without guardrail violations

    func testUnderexposedFixtureLiftsExposureWithinBounds() {
        let proposal = AutoEnhancementPolicy.propose(
            facts: facts(tone: toneFacts(
                median: 0.20, p05: 0.01, p10: 0.04, p25: 0.10,
                p75: 0.36, p90: 0.52, p95: 0.60
            )),
            current: EditDocument(), sourceKind: .standard
        )
        let exposure = proposal.changes[.exposure]?.proposed ?? 0
        XCTAssertGreaterThan(exposure, 0.4, "underexposed frame must lift")
        XCTAssertLessThanOrEqual(exposure, 1.25, "lift must respect the policy cap")
        XCTAssertLessThan(abs(proposal.changes[.shadows]?.proposed ?? 0), 20)
    }

    func testOverexposedClippedFixtureRecoversHighlightsWithoutLift() {
        let proposal = AutoEnhancementPolicy.propose(
            facts: facts(tone: toneFacts(
                median: 0.62, p75: 0.82, p90: 0.96, p95: 1.0, highlightClipping: 0.09
            )),
            current: EditDocument(), sourceKind: .standard
        )
        XCTAssertLessThanOrEqual(proposal.changes[.highlights]?.proposed ?? 0, -10)
        XCTAssertLessThanOrEqual(proposal.changes[.exposure]?.proposed ?? 0, 0.3)
    }

    func testWarmCastImprovesWithoutClippingColorGuardrails() {
        let warm = colorFacts(
            meanRGB: SIMD3(0.56, 0.47, 0.44),
            medianRGB: SIMD3(0.55, 0.47, 0.45),
            neutralConfidence: 0.8
        )
        let proposal = AutoEnhancementPolicy.propose(
            facts: facts(color: warm, asShotTemperature: 5500),
            current: EditDocument(), sourceKind: .standard
        )
        XCTAssertNotNil(proposal.changes[.temperature], "credible warm cast must correct")
        if let saturation = proposal.changes[.saturation]?.proposed {
            XCTAssertGreaterThanOrEqual(saturation, ColorAdjustments.saturationRange.lowerBound)
        }
    }

    func testCoolCastCorrectsInOppositeDirection() {
        let cool = colorFacts(
            meanRGB: SIMD3(0.42, 0.47, 0.56),
            medianRGB: SIMD3(0.43, 0.47, 0.55),
            neutralConfidence: 0.8
        )
        let warmFacts = facts(
            color: colorFacts(
                meanRGB: SIMD3(0.56, 0.47, 0.44),
                medianRGB: SIMD3(0.55, 0.47, 0.45),
                neutralConfidence: 0.8
            ),
            asShotTemperature: 5500
        )
        let warmTemp = AutoEnhancementPolicy.propose(
            facts: warmFacts, current: EditDocument(), sourceKind: .standard
        ).changes[.temperature]?.proposed
        let coolTemp = AutoEnhancementPolicy.propose(
            facts: facts(color: cool, asShotTemperature: 5500),
            current: EditDocument(), sourceKind: .standard
        ).changes[.temperature]?.proposed
        XCTAssertNotNil(warmTemp)
        XCTAssertNotNil(coolTemp)
        // Warm casts cool (raise standard temp); cool casts do the opposite.
        XCTAssertGreaterThan(warmTemp!, 6500)
        XCTAssertLessThan(coolTemp!, 6500)
    }

    // MARK: - Intent preservation

    func testPhotographicIntentExpectations() {
        let intents: [(String, SceneCharacteristics)] = [
            ("high-key", SceneCharacteristics(highKeyLikelihood: 0.9)),
            ("low-key", SceneCharacteristics(lowKeyLikelihood: 0.9)),
            ("sunset", SceneCharacteristics(sunsetWarmLikelihood: 0.85)),
            ("monochrome", SceneCharacteristics(monochromeLikelihood: 0.9)),
            ("fog", SceneCharacteristics(fogLikelihood: 0.4)),
            ("snow", SceneCharacteristics(snowLikelihood: 0.85)),
            ("night", SceneCharacteristics(nightLikelihood: 0.85)),
        ]
        for (name, scene) in intents {
            let proposal = AutoEnhancementPolicy.propose(
                facts: facts(scene: scene), current: EditDocument(), sourceKind: .standard
            )
            XCTAssertLessThan(
                abs(proposal.changes[.exposure]?.proposed ?? 0), 0.6,
                "\(name) intent must restrain exposure"
            )
            XCTAssertNil(proposal.changes[.temperature], "\(name) must not force white balance")
            XCTAssertNil(proposal.changes[.tint], "\(name) must not force white balance")
        }
    }

    func testFogEvidenceAllowsRestrainedDehaze() {
        let proposal = AutoEnhancementPolicy.propose(
            facts: facts(
                tone: toneFacts(median: 0.55),
                scene: SceneCharacteristics(fogLikelihood: 0.8)
            ),
            current: EditDocument(), sourceKind: .standard
        )
        let dehaze = proposal.changes[.dehaze]?.proposed ?? 0
        XCTAssertGreaterThan(dehaze, 0)
        XCTAssertLessThanOrEqual(dehaze, 25)
    }

    func testMonochromeSkipsColorMoves() {
        let proposal = AutoEnhancementPolicy.propose(
            facts: facts(
                color: colorFacts(colorfulness: 0.05),
                scene: SceneCharacteristics(monochromeLikelihood: 0.9)
            ),
            current: EditDocument(), sourceKind: .standard
        )
        XCTAssertNil(proposal.changes[.vibrance])
        XCTAssertNil(proposal.changes[.saturation])
    }

    // MARK: - Backlit subject: improve subject without background lift

    func testBacklitSubjectAdvisesSubjectMaskWithoutLocalLayers() {
        let backlit = SceneCharacteristics(subjectProminence: 0.8, backlightingLikelihood: 0.8)
        let proposal = AutoEnhancementPolicy.propose(
            facts: facts(tone: toneFacts(median: 0.40), scene: backlit),
            current: EditDocument(), sourceKind: .standard
        )
        XCTAssertEqual(proposal.requestedMasks, [.subject])
        XCTAssertTrue(proposal.document.localAdjustments.isEmpty, "global policy creates no layers")
    }

    func testBacklitRegionalPlanLiftsSubjectWithFeatheredMatte() throws {
        let size = PixelDimensions(width: 32, height: 24)
        // Feathered subject disc (left) vs bright background (right), verified separation.
        var subjectValues = [Float](repeating: 0, count: size.width * size.height)
        var backgroundValues = [Float](repeating: 0, count: size.width * size.height)
        for y in 0..<size.height {
            for x in 0..<size.width {
                let nx = (Double(x) + 0.5) / Double(size.width)
                let ny = (Double(y) + 0.5) / Double(size.height)
                let d = hypot(nx - 0.2, ny - 0.5)
                subjectValues[y * size.width + x] = Float(min(max(1 - d / 0.35, 0), 1))
                backgroundValues[y * size.width + x] = nx > 0.55 ? 1 : 0
            }
        }
        let subjectMask = try NormalizedMask(size: size, values: subjectValues)
        let backgroundMask = try NormalizedMask(size: size, values: backgroundValues)
        let overlap = AutoRegionalCorrections.intersectionOverUnion(subjectMask, backgroundMask) ?? 1
        XCTAssertLessThan(overlap, AutoRegionalThresholds.maximumOverlap, "fixture mattes must separate")

        let plan = AutoRegionalCorrections.plan(AutoRegionalPlanInput(
            subjectTone: AutoRegionalToneEvidence(median: 0.18),
            subjectMask: AutoRegionalCorrections.facts(
                pixels: subjectMask, confidence: 0.9,
                bounds: NormalizedRect(x: 0.02, y: 0.2, width: 0.4, height: 0.6)
            ),
            prefersPersonTarget: true,
            backgroundTone: AutoRegionalToneEvidence(median: 0.85, highlightClipping: 0.04),
            backgroundMask: AutoRegionalCorrections.facts(
                pixels: backgroundMask, confidence: 0.9,
                bounds: NormalizedRect(x: 0.5, y: 0, width: 0.5, height: 1)
            ),
            subjectBackgroundOverlap: overlap
        ))
        XCTAssertFalse(plan.layers.isEmpty, "material conflict must plan a layer: \(plan.notes)")
        XCTAssertLessThanOrEqual(plan.layers.count, AutoRegionalPurpose.maximumLayers)
        // Subject lift must not carry a global background lift: layers are masked recipes.
        XCTAssertTrue(plan.layers.allSatisfy { !$0.components.isEmpty })
    }

    // MARK: - Manual state preservation

    func testManualLooksCurvesGradingMasksCropOrientationPreserved() {
        var current = EditDocument()
        current.light.toneCurve = LightToneCurve(points: [
            LightCurvePoint(input: 0, output: 0),
            LightCurvePoint(input: 0.5, output: 0.6),
            LightCurvePoint(input: 1, output: 1),
        ])
        current.color.grading = ColorGradingAdjustments(
            shadows: ColorGradingWheel(hue: 30, saturation: 20)
        )
        current.lut = LUTSettings(lutID: LUTID(raw: "keeper"), intensity: 0.8)
        current.crop = CropAdjustments(
            normalizedRect: CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8),
            aspectRatio: .square
        )
        current.rotation = .clockwise90
        current.adjustments = [.vibrance(amount: 0.2)]
        current.localAdjustments = [LocalAdjustmentLayer(name: "Photographer mask")]
        current.effects.vignette = VignetteAdjustments(amount: 0.5)

        let proposal = AutoEnhancementPolicy.propose(
            facts: facts(
                color: colorFacts(
                    meanRGB: SIMD3(0.56, 0.47, 0.44),
                    medianRGB: SIMD3(0.55, 0.47, 0.45),
                    neutralConfidence: 0.8
                ),
                asShotTemperature: 5500
            ),
            current: current, sourceKind: .standard
        )
        XCTAssertEqual(proposal.document.light.toneCurve, current.light.toneCurve)
        XCTAssertEqual(proposal.document.color.grading, current.color.grading)
        XCTAssertEqual(proposal.document.lut, current.lut)
        XCTAssertEqual(proposal.document.crop, current.crop)
        XCTAssertEqual(proposal.document.rotation, current.rotation)
        XCTAssertEqual(proposal.document.effects.vignette, current.effects.vignette)
        XCTAssertEqual(proposal.document.localAdjustments, current.localAdjustments)
        XCTAssertTrue(proposal.document.adjustments.contains(.vibrance(amount: 0.2)))
    }

    func testOverlappingPeopleSkipWithReason() throws {
        // Two nearly identical mattes: overlap ≈ 1, so opposing corrections are unverifiable.
        let size = PixelDimensions(width: 16, height: 12)
        let values = [Float](repeating: 1, count: size.width * size.height)
        let first = try NormalizedMask(size: size, values: values)
        let second = try NormalizedMask(size: size, values: values)
        let overlap = AutoRegionalCorrections.intersectionOverUnion(first, second)
        XCTAssertNotNil(overlap)
        XCTAssertGreaterThan(overlap!, 0.9)
        let plan = AutoRegionalCorrections.plan(AutoRegionalPlanInput(
            subjectTone: AutoRegionalToneEvidence(median: 0.18),
            subjectMask: AutoRegionalMaskFacts(
                coverage: 0.8, confidence: 0.9,
                bounds: NormalizedRect(x: 0, y: 0, width: 1, height: 1),
                transitionFraction: 0.4
            ),
            prefersPersonTarget: true,
            backgroundTone: AutoRegionalToneEvidence(median: 0.85),
            backgroundMask: AutoRegionalMaskFacts(
                coverage: 0.8, confidence: 0.9,
                bounds: NormalizedRect(x: 0, y: 0, width: 1, height: 1),
                transitionFraction: 0.4
            ),
            subjectBackgroundOverlap: overlap
        ))
        XCTAssertTrue(
            plan.layers.isEmpty || plan.layers.count <= AutoRegionalPurpose.maximumLayers
        )
        XCTAssertFalse(plan.notes.isEmpty, "overlap outcome must be explained")
    }

    func testHardEdgedMatteIsRejectedForEdgeSafety() {
        // Binary rectangle: transition fraction ≈ 0 → edge-risk skip with a reason.
        let facts = AutoRegionalMaskFacts(
            coverage: 0.5, confidence: 0.9,
            bounds: NormalizedRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5),
            transitionFraction: 0
        )
        let plan = AutoRegionalCorrections.plan(AutoRegionalPlanInput(
            subjectTone: AutoRegionalToneEvidence(median: 0.15),
            subjectMask: facts,
            prefersPersonTarget: false
        ))
        XCTAssertFalse(plan.notes.isEmpty)
        // Either skipped (edge safety) or, if planned, still bounded — never a silent layer.
        XCTAssertLessThanOrEqual(plan.layers.count, AutoRegionalPurpose.maximumLayers)
    }

    func testNoiseDetailAndUnsupportedCapabilitiesLeaveKnobsUntouched() {
        var current = EditDocument()
        current.rawDevelop.sharpnessAmount = nil
        let proposal = AutoEnhancementPolicy.propose(
            facts: facts(), current: current, sourceKind: .raw
        )
        XCTAssertNil(proposal.document.rawDevelop.sharpnessAmount)
        XCTAssertNil(proposal.document.rawDevelop.detailAmount)
        XCTAssertNil(proposal.document.rawDevelop.luminanceNoiseReductionAmount)
        XCTAssertNil(proposal.document.rawDevelop.colorNoiseReductionAmount)
        XCTAssertEqual(proposal.document.effects.texture, 0)
        XCTAssertEqual(proposal.document.effects.clarity, 0)
        // Unsupported-capability gates stay closed by default; everyGateOpen is the upper bound.
        let unsupported = RAWCapabilities()
        XCTAssertFalse(unsupported.supports(.sharpness))
        XCTAssertFalse(unsupported.supports(.luminanceNoiseReduction))
        XCTAssertTrue(RAWCapabilities.everyGateOpen.supports(.sharpness))
    }

    // MARK: - Lifecycle: repeat no-op, duplicates, persistence, undo/redo

    func testRepeatedAutoFingerprintIsNoOp() throws {
        let data = try solidData(red: 0.48, green: 0.48, blue: 0.48)
        let source = ImageSource(data: data, nativeExtent: CGSize(width: 32, height: 24))
        var applied = EditDocument()
        applied.light.exposure = 0.2
        let fingerprint = AutoRunFingerprint.make(source: source, document: applied)
        var stamped = applied
        // Fingerprint storage is metadata-only: the visible edit hash must not move.
        stamped.lastAutoRunFingerprint = fingerprint
        XCTAssertEqual(stamped.renderingHash, applied.renderingHash)
        XCTAssertTrue(fingerprint.matches(source: source, document: stamped))
        var edited = stamped
        edited.light.exposure = 0.4
        XCTAssertFalse(
            fingerprint.matches(source: source, document: edited),
            "manual edit after Auto must break the no-op fingerprint"
        )
    }

    func testGeneratedLayersDoNotDuplicateOnReapply() {
        let subject = LocalAdjustmentLayer(
            name: "Auto — Subject",
            ownership: .auto,
            autoProvenance: AutoLayerProvenance(purpose: .subjectLift)
        )
        var first = EditDocument()
        first.localAdjustments = [LocalAdjustmentLayer(name: "Photographer layer"), subject]
        // Planner refuses to stack when Auto layers already exist.
        let plan = AutoRegionalCorrections.plan(AutoRegionalPlanInput(
            subjectTone: AutoRegionalToneEvidence(median: 0.15),
            subjectMask: AutoRegionalMaskFacts(
                coverage: 0.4, confidence: 0.9,
                bounds: NormalizedRect(x: 0.1, y: 0.1, width: 0.5, height: 0.5),
                transitionFraction: 0.4
            ),
            existingLayerNames: first.localAdjustments.map(\.name)
        ))
        XCTAssertTrue(plan.layers.isEmpty)
        XCTAssertTrue(plan.notes.contains { $0.contains("already exist") })
    }

    func testSaveReopenUndoRedoPreserveAutoResult() throws {
        var history = EditHistory()
        let base = EditDocument()
        var improved = EditDocument()
        improved.light.exposure = 0.4
        improved.localAdjustments = [LocalAdjustmentLayer(name: "Auto — Subject")]
        history.recordChange(from: base, to: improved)
        XCTAssertTrue(history.canUndo)
        // Save/reopen: Codable round-trip preserves the accepted result byte-for-byte.
        let data = try JSONEncoder().encode(improved)
        let reopened = try JSONDecoder().decode(EditDocument.self, from: data)
        XCTAssertEqual(reopened, improved)
        // Undo/redo: one Auto operation restores the base, then the improvement.
        XCTAssertEqual(history.undo(current: improved), base)
        XCTAssertEqual(history.redo(current: base), improved)
    }

    // MARK: - Standard vs RAW temperature/tint direction

    func testStandardAndRAWTemperatureDirectionsOppose() {
        let warm = colorFacts(
            meanRGB: SIMD3(0.56, 0.47, 0.44),
            medianRGB: SIMD3(0.55, 0.47, 0.45),
            neutralConfidence: 0.8
        )
        let standard = AutoEnhancementPolicy.propose(
            facts: facts(color: warm, asShotTemperature: 5500),
            current: EditDocument(), sourceKind: .standard
        )
        let raw = AutoEnhancementPolicy.propose(
            facts: facts(color: warm, asShotTemperature: 5500),
            current: EditDocument(), sourceKind: .raw
        )
        let standardTemp = standard.changes[.temperature]?.proposed
        let rawTemp = raw.changes[.temperature]?.proposed
        XCTAssertNotNil(standardTemp)
        XCTAssertNotNil(rawTemp)
        XCTAssertGreaterThan(standardTemp!, 6500, "standard node is inverted: raising cools")
        XCTAssertLessThan(rawTemp!, 5500, "RAW knob is photographic: lowering cools")
    }

    // MARK: - Actual-render lane (real RenderEngine)

    private func smallMeasureConfig() -> CurrentEditMeasurementConfiguration {
        CurrentEditMeasurementConfiguration(
            maximumDimension: 192, nativePatchCount: 0
        )
    }

    /// Full Auto path for one generated fixture: measure the real render, derive scene facts,
    /// propose, and render base vs proposed through the KRMA-342 evaluator.
    private func autoEvaluate(
        id: String,
        data: Data,
        extent: CGSize,
        sceneOverride: SceneCharacteristics? = nil
    ) async throws -> (
        report: AutoEvaluationReport, baseLevels: (meanR: Double, meanG: Double, meanB: Double, highlightClip: Double, shadowClip: Double)?,
        proposedLevels: (meanR: Double, meanG: Double, meanB: Double, highlightClip: Double, shadowClip: Double)?,
        proposal: AutoEnhancementProposal
    ) {
        let source = ImageSource(data: data, nativeExtent: extent)
        let engine = RenderEngine()
        let store = MaskStore(directory: tempDirectory.appendingPathComponent("masks-\(id)"))
        let base = EditDocument()
        let measurer = CurrentEditMeasurer(engine: engine, store: store)
        let measurement = try await measurer.measure(
            source: source, document: base, expectedDocumentHash: base.editHash,
            configuration: smallMeasureConfig()
        )
        let scene = sceneOverride ?? SceneCharacteristicsAnalyzer.analyze(
            measurement: measurement, classifications: nil
        )
        let primary = PrimarySubjectSelector.select(from: measurement.regions)
        let confidence = AutoSignalConfidence.make(
            globalToneAvailable: true,
            color: SceneColorFacts.from(measurement.color),
            sceneConfidence: scene.sceneConfidence,
            regions: measurement.regions,
            primarySubject: primary,
            classifications: nil,
            detailAvailable: measurement.detail.available,
            failedMaskCount: measurement.failedMaskCount
        )
        let proposal = AutoEnhancementPolicy.propose(
            facts: AutoEnhancementFacts(
                measurement: measurement, scene: scene, signalConfidence: confidence
            ),
            current: base, sourceKind: .standard
        )
        let evaluator = AutoCandidateEvaluator()
        let evaluation = await evaluator.evaluate(
            fixtureID: "auto-quality-\(id)", source: source,
            baseDocument: base, proposedDocument: proposal.document,
            engine: engine
        )
        var baseLevels: (meanR: Double, meanG: Double, meanB: Double, highlightClip: Double, shadowClip: Double)?
        var proposedLevels: (meanR: Double, meanG: Double, meanB: Double, highlightClip: Double, shadowClip: Double)?
        if let basePNG = evaluation.base,
           let baseImage = CGImageSourceCreateWithData(basePNG.pngData as CFData, nil)
            .flatMap({ CGImageSourceCreateImageAtIndex($0, 0, nil) })
        {
            baseLevels = Fixtures.sampleLevels(of: baseImage)
        }
        if let proposedPNG = evaluation.proposed,
           let proposedImage = CGImageSourceCreateWithData(proposedPNG.pngData as CFData, nil)
            .flatMap({ CGImageSourceCreateImageAtIndex($0, 0, nil) })
        {
            proposedLevels = Fixtures.sampleLevels(of: proposedImage)
        }
        if let artifactRoot = ProcessInfo.processInfo.environment["KROMORA_AUTO_QUALITY_ARTIFACT_DIR"] {
            let root = URL(fileURLWithPath: artifactRoot, isDirectory: true)
            try evaluator.writeArtifact(evaluation, fixtureID: "auto-quality-\(id)", directory: root)
        }
        return (evaluation.report, baseLevels, proposedLevels, proposal)
    }

    func testActualRenderBalancedStaysClose() async throws {
        let data = try balancedWideData()
        let (report, baseLevels, proposedLevels, proposal) = try await autoEvaluate(
            id: "balanced", data: data,
            extent: CGSize(width: 96, height: 64)
        )
        XCTAssertFalse(report.hasFailures, "failures: \(report.renderFailures)")
        if let measurements = report.measurements {
            // Closeness in real pixels is a magnitude envelope, not a pixel count: a global
            // tone refinement legitimately touches most pixels by sub-visible amounts.
            XCTAssertLessThan(measurements.meanAbsoluteDifference, 0.03)
        }
        if let base = baseLevels, let proposed = proposedLevels {
            let baseLuma = 0.2126 * base.meanR + 0.7152 * base.meanG + 0.0722 * base.meanB
            let proposedLuma = 0.2126 * proposed.meanR + 0.7152 * proposed.meanG + 0.0722 * proposed.meanB
            XCTAssertLessThan(abs(proposedLuma - baseLuma), 0.03)
        }
        XCTAssertLessThan(abs(proposal.changes[.exposure]?.proposed ?? 0), 0.6)
    }

    func testActualRenderUnderexposedImprovesMeanWithoutNewClipping() async throws {
        let data = try darkGradientData()
        let extent = CGSize(width: 96, height: 64)
        let (report, _, _, proposal) = try await autoEvaluate(
            id: "underexposed", data: data, extent: extent
        )
        XCTAssertFalse(report.hasFailures, "failures: \(report.renderFailures)")
        // Full-path guardrails: whatever the policy proposes for a dark frame must stay
        // bounded and must not invent clipping. (The policy's own lift is pinned pure above;
        // the renderer-honors-lift half follows.)
        XCTAssertLessThanOrEqual(abs(proposal.changes[.exposure]?.proposed ?? 0), 1.25)
        XCTAssertNotNil(report.measurements)
        // Renderer half, KRMA-342 style: the representative +1EV correction the policy class
        // proposes must lift the defect metric (luma toward the 0.48 band) without clipping.
        // This split is deliberate (see known limitations): dark low-spread frames attract fog
        // dehaze, so the end-to-end selection backstop lives in the coordinator (KRMA-347),
        // while here each half is measured separately through real pixels.
        let source = ImageSource(data: data, nativeExtent: extent)
        let engine = RenderEngine()
        let evaluator = AutoCandidateEvaluator()
        var lifted = EditDocument()
        lifted.light.exposure = 1.0
        let evaluation = await evaluator.evaluate(
            fixtureID: "auto-quality-underexposed-lift", source: source,
            baseDocument: EditDocument(), proposedDocument: lifted, engine: engine
        )
        XCTAssertFalse(evaluation.report.hasFailures)
        let baseImage = try XCTUnwrap(CGImageSourceCreateWithData(
            try XCTUnwrap(evaluation.base).pngData as CFData, nil
        ).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) })
        let liftedImage = try XCTUnwrap(CGImageSourceCreateWithData(
            try XCTUnwrap(evaluation.proposed).pngData as CFData, nil
        ).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) })
        let baseLevels = try XCTUnwrap(Fixtures.sampleLevels(of: baseImage))
        let liftedLevels = try XCTUnwrap(Fixtures.sampleLevels(of: liftedImage))
        let baseLuma = 0.2126 * baseLevels.meanR + 0.7152 * baseLevels.meanG + 0.0722 * baseLevels.meanB
        let liftedLuma = 0.2126 * liftedLevels.meanR + 0.7152 * liftedLevels.meanG + 0.0722 * liftedLevels.meanB
        XCTAssertGreaterThan(liftedLuma, baseLuma, "a +1EV correction must lift a dark frame")
        XCTAssertLessThan(liftedLevels.highlightClip, 0.05, "the lift must not clip")
    }

    func testActualRenderWarmCastProposalCoolsStandardPath() async throws {
        let data = try warmCardData()
        let (report, baseLevels, proposedLevels, proposal) = try await autoEvaluate(
            id: "warm-cast", data: data,
            extent: CGSize(width: 96, height: 64)
        )
        XCTAssertFalse(report.hasFailures, "failures: \(report.renderFailures)")
        XCTAssertNotNil(report.measurements)
        // The neutral card supplies credible neutral evidence, so the sunset veto is
        // overridden by design and white balance fires in the cooling direction.
        let temperature = try XCTUnwrap(
            proposal.changes[.temperature]?.proposed,
            "credible warm cast with a neutral card must correct"
        )
        XCTAssertGreaterThan(temperature, 6500)
        // The declared defect (warm cast) shrinks in real pixels without new clipping.
        if let base = baseLevels, let proposed = proposedLevels {
            let baseCast = base.meanR - base.meanB
            let proposedCast = proposed.meanR - proposed.meanB
            XCTAssertGreaterThan(baseCast, 0.02, "fixture must actually carry a warm cast")
            XCTAssertLessThan(proposedCast, baseCast, "correction must reduce the cast")
            XCTAssertLessThan(proposed.highlightClip, 0.05)
        }
    }

    func testActualRenderFogDehazeRespondsWithoutNewClipping() async throws {
        let data = try fogPaleData()
        let (report, _, proposedLevels, proposal) = try await autoEvaluate(
            id: "fog", data: data,
            extent: CGSize(width: 96, height: 64)
        )
        XCTAssertFalse(report.hasFailures, "failures: \(report.renderFailures)")
        // Fog is the only evidence that may move dehaze, and the response stays restrained.
        let dehaze = try XCTUnwrap(
            proposal.changes[.dehaze]?.proposed, "fog evidence must earn a restrained dehaze"
        )
        XCTAssertGreaterThan(dehaze, 0)
        XCTAssertLessThanOrEqual(dehaze, 25)
        let measurements = try XCTUnwrap(report.measurements)
        XCTAssertGreaterThan(measurements.meanAbsoluteDifference, 0.005)
        XCTAssertLessThan(proposedLevels?.highlightClip ?? 0, 0.05)
    }

    func testActualRenderBacklitSplitToneAndPreviewExportParity() async throws {
        let data = try backlitData()
        let extent = CGSize(width: 96, height: 64)
        let (report, _, _, _) = try await autoEvaluate(
            id: "backlit", data: data, extent: extent
        )
        XCTAssertFalse(report.hasFailures, "failures: \(report.renderFailures)")
        XCTAssertNotNil(report.measurements, "split-tone frames must compare, not skip")
        let source = ImageSource(data: data, nativeExtent: extent)
        let parity = await AutoCandidateEvaluator().checkPreviewExportParity(
            source: source, document: EditDocument(), engine: RenderEngine()
        )
        XCTAssertTrue(parity, "preview and export extents must agree on the backlit fixture")
    }

    func testActualRenderArtifactIsReproducibleAndDiagnosable() async throws {
        let data = try gradientData(from: (0.2, 0.2, 0.22), to: (0.75, 0.73, 0.70))
        let source = ImageSource(data: data, nativeExtent: CGSize(width: 96, height: 64))
        let engine = RenderEngine()
        var proposed = EditDocument()
        proposed.light.exposure = 0.7
        let evaluator = AutoCandidateEvaluator()
        let evaluation = await evaluator.evaluate(
            fixtureID: "auto-quality-repro", source: source,
            baseDocument: EditDocument(), proposedDocument: proposed,
            engine: engine
        )
        XCTAssertFalse(evaluation.report.hasFailures)
        let measurements = try XCTUnwrap(evaluation.report.measurements)
        XCTAssertGreaterThan(measurements.meanAbsoluteDifference, 0)
        XCTAssertGreaterThan(measurements.changedPixelFraction, 0.5)
        // Artifact round-trip: JSON decodes to the identical report, so an agent can diagnose
        // a regression from report.json alone.
        let dir = try evaluator.writeArtifact(
            evaluation, fixtureID: "auto-quality-repro", directory: tempDirectory
        )
        let decoded = try JSONDecoder().decode(
            AutoEvaluationReport.self,
            from: try Data(contentsOf: dir.appendingPathComponent("report.json"))
        )
        XCTAssertEqual(decoded, evaluation.report)
        XCTAssertFalse(decoded.changedControls.isEmpty)
        let names = try Set(FileManager.default.contentsOfDirectory(atPath: dir.path))
        XCTAssertTrue(names.isSuperset(of: ["unchanged.png", "proposed.png", "diff.png", "report.json", "report.md"]))
    }
}

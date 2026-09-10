import XCTest

@testable import KromoraKit

/// Planner and matte tests for KRMA-348 selective Auto-owned regional correction layers.
///
/// Everything here exercises the pure planning seam: post-global evidence in, ordinary editable
/// layers (or explained skips) out. No Vision, render, or store participation.
final class AutoRegionalCorrectionsTests: XCTestCase {

    // MARK: - Fixture builders

    private static let size = PixelDimensions(width: 40, height: 40)

    /// A soft disc matte: full weight at the center dissolving to zero at the edge, so the
    /// transition fraction reads like a feathered segmentation matte.
    private func softDisc(
        center: (Double, Double) = (0.5, 0.5), radius: Double = 0.3
    ) throws -> NormalizedMask {
        var values = [Float](repeating: 0, count: Self.size.width * Self.size.height)
        for y in 0..<Self.size.height {
            for x in 0..<Self.size.width {
                let nx = (Double(x) + 0.5) / Double(Self.size.width)
                let ny = (Double(y) + 0.5) / Double(Self.size.height)
                let distance = sqrt(pow(nx - center.0, 2) + pow(ny - center.1, 2))
                values[y * Self.size.width + x] = Float(min(max(1 - distance / radius, 0), 1))
            }
        }
        return try NormalizedMask(size: Self.size, values: values)
    }

    /// A hard rectangle matte with no transition band, standing in for any rectangle-only
    /// treatment that must never reach the Auto path.
    private func hardBox(
        x: Range<Int> = 8..<24, y: Range<Int> = 8..<24
    ) throws -> NormalizedMask {
        var values = [Float](repeating: 0, count: Self.size.width * Self.size.height)
        for row in y {
            for column in x {
                values[row * Self.size.width + column] = 1
            }
        }
        return try NormalizedMask(size: Self.size, values: values)
    }

    private func facts(
        for mask: NormalizedMask, confidence: Float = 0.8, bounds: NormalizedRect? = nil
    ) -> AutoRegionalMaskFacts {
        let resolvedBounds = bounds ?? NormalizedRect(x: 0.2, y: 0.2, width: 0.4, height: 0.4)
        return AutoRegionalCorrections.facts(
            pixels: mask, confidence: confidence, bounds: resolvedBounds
        )
    }

    private func conflictingInput() throws -> AutoRegionalPlanInput {
        // Dark subject on the left, bright background on the right: the global proposal cannot
        // serve both, which is exactly the material regional conflict these layers exist for.
        let subject = try softDisc(center: (0.3, 0.5), radius: 0.28)
        let background = try softDisc(center: (0.75, 0.5), radius: 0.28)
        let overlap = AutoRegionalCorrections.intersectionOverUnion(subject, background) ?? -1
        return AutoRegionalPlanInput(
            subjectTone: AutoRegionalToneEvidence(median: 0.22),
            subjectMask: facts(
                for: subject,
                bounds: NormalizedRect(x: 0.05, y: 0.25, width: 0.45, height: 0.5)
            ),
            backgroundTone: AutoRegionalToneEvidence(median: 0.75, highlightClipping: 0.05),
            backgroundMask: facts(
                for: background,
                bounds: NormalizedRect(x: 0.5, y: 0.25, width: 0.45, height: 0.5)
            ),
            subjectBackgroundOverlap: overlap,
            colorCast: 0
        )
    }

    // MARK: - No-mask degradation

    func testEmptyEvidencePlansNoLayersWithExplanations() {
        let plan = AutoRegionalCorrections.plan(AutoRegionalPlanInput())
        XCTAssertTrue(plan.layers.isEmpty, "no evidence must never produce a layer")
        XCTAssertFalse(plan.notes.isEmpty, "every skipped purpose needs an explanation")
        let unchanged = AutoRegionalCorrections.applying(plan, to: EditDocument())
        XCTAssertEqual(unchanged, EditDocument())
    }

    func testUnverifiableSeparationPlansNoLayers() throws {
        var input = try conflictingInput()
        input.subjectBackgroundOverlap = nil
        let plan = AutoRegionalCorrections.plan(input)
        XCTAssertTrue(plan.layers.isEmpty)
        XCTAssertTrue(plan.notes.joined(separator: " ").contains("separation"))
    }

    // MARK: - Regional improvement without background damage

    func testMaterialConflictPlansSubjectLiftAndBackgroundProtection() throws {
        let plan = AutoRegionalCorrections.plan(try conflictingInput())
        XCTAssertEqual(plan.layers.count, 2)
        XCTAssertLessThanOrEqual(
            plan.layers.count, AutoRegionalPurpose.maximumLayers
        )

        let subject = try XCTUnwrap(plan.layers.first { $0.name == "Auto — Subject" })
        XCTAssertGreaterThan(subject.adjustments.exposure, 0, "subject lift must lift")
        XCTAssertGreaterThan(subject.adjustments.shadows, 0)
        XCTAssertTrue(subject.hasVisibleLook)

        let background = try XCTUnwrap(plan.layers.first { $0.name == "Auto — Background" })
        XCTAssertLessThan(background.adjustments.highlights, 0, "protection must compress")
        XCTAssertLessThan(background.adjustments.whites, 0)
        XCTAssertEqual(
            background.adjustments.exposure, 0,
            "protection must carry no lift component that could brighten the background"
        )
        XCTAssertEqual(background.adjustments.shadows, 0)
        XCTAssertTrue(background.hasVisibleLook)
    }

    func testGlobalSuccessNeedsNoLayers() throws {
        var input = try conflictingInput()
        input.subjectTone = AutoRegionalToneEvidence(median: 0.45)
        input.backgroundTone = AutoRegionalToneEvidence(median: 0.5, highlightClipping: 0)
        let plan = AutoRegionalCorrections.plan(input)
        XCTAssertTrue(plan.layers.isEmpty, "a global proposal that fixed both regions earns nothing")
        XCTAssertEqual(plan.notes.count, 3)
    }

    func testPlannedLayersAppendAsEditableRecipesAndRoundTrip() throws {
        let plan = AutoRegionalCorrections.plan(try conflictingInput())
        XCTAssertFalse(plan.layers.isEmpty)
        let updated = AutoRegionalCorrections.applying(plan, to: EditDocument())
        XCTAssertEqual(updated.localAdjustments, plan.layers)
        for layer in updated.localAdjustments {
            XCTAssertTrue(layer.isEnabled)
            XCTAssertFalse(layer.isInverted)
            let targets = layer.components.compactMap(\.source.semanticDefinition?.target)
            XCTAssertFalse(targets.isEmpty, "Auto layers must reuse semantic recipes, not pixels")
        }
        let data = try JSONEncoder().encode(updated)
        let restored = try JSONDecoder().decode(EditDocument.self, from: data)
        XCTAssertEqual(restored.localAdjustments, plan.layers, "layers must survive save/reopen")
    }

    // MARK: - Overlapping people

    func testOverlappingSubjectAndBackgroundSkipsWithReason() throws {
        let matte = try softDisc()
        let overlap = AutoRegionalCorrections.intersectionOverUnion(matte, matte)
        XCTAssertEqual(overlap, 1, "identical mattes are the overlap ceiling")
        var input = try conflictingInput()
        input.backgroundMask = facts(for: matte)
        input.subjectBackgroundOverlap = overlap
        let plan = AutoRegionalCorrections.plan(input)
        XCTAssertTrue(plan.layers.isEmpty, "overlapping people must not earn opposing corrections")
        XCTAssertTrue(plan.notes.joined(separator: " ").contains("overlap"))
    }

    func testIntersectionOverUnionReturnsNilForMismatchedSizes() throws {
        let small = try NormalizedMask(
            size: PixelDimensions(width: 4, height: 4),
            values: [Float](repeating: 1, count: 16)
        )
        let large = try softDisc()
        XCTAssertNil(AutoRegionalCorrections.intersectionOverUnion(small, large))
    }

    // MARK: - Feathered boundaries

    func testHardEdgedMatteIsRejected() throws {
        let box = try hardBox()
        XCTAssertLessThan(
            AutoRegionalCorrections.transitionFraction(of: box),
            AutoRegionalThresholds.minimumTransitionFraction
        )
        var input = try conflictingInput()
        input.subjectMask = facts(
            for: box, bounds: NormalizedRect(x: 0.2, y: 0.2, width: 0.4, height: 0.4)
        )
        let plan = AutoRegionalCorrections.plan(input)
        XCTAssertNil(plan.layers.first { $0.name == "Auto — Subject" })
        XCTAssertTrue(plan.notes.joined(separator: " ").contains("feathered"))
    }

    func testFeatheredMattePassesTransitionCheck() throws {
        let disc = try softDisc()
        XCTAssertGreaterThanOrEqual(
            AutoRegionalCorrections.transitionFraction(of: disc),
            AutoRegionalThresholds.minimumTransitionFraction
        )
    }

    func testTinyAndGlobalMattesAreRejected() throws {
        let tiny = AutoRegionalMaskFacts(
            coverage: 0.005, confidence: 0.9,
            bounds: NormalizedRect(x: 0.4, y: 0.4, width: 0.1, height: 0.1),
            transitionFraction: 0.5
        )
        XCTAssertFalse(AutoRegionalCorrections.validate(tiny, role: "subject", crop: nil).usable)
        let global = AutoRegionalMaskFacts(
            coverage: 0.95, confidence: 0.9,
            bounds: NormalizedRect(x: 0, y: 0, width: 1, height: 1),
            transitionFraction: 0.5
        )
        XCTAssertFalse(AutoRegionalCorrections.validate(global, role: "subject", crop: nil).usable)
        let diffident = AutoRegionalMaskFacts(
            coverage: 0.2, confidence: 0.1,
            bounds: NormalizedRect(x: 0.2, y: 0.2, width: 0.4, height: 0.4),
            transitionFraction: 0.5
        )
        let validation = AutoRegionalCorrections.validate(diffident, role: "subject", crop: nil)
        XCTAssertFalse(validation.usable)
        XCTAssertFalse(validation.reasons.isEmpty)
    }

    // MARK: - Crop/orientation alignment

    func testCropThatDiscardsTheMaskSkipsWithReason() throws {
        var input = try conflictingInput()
        // The photographer cropped to the bottom-right; the subject matte up top no longer
        // describes this framing.
        input.crop = NormalizedRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5)
        let plan = AutoRegionalCorrections.plan(input)
        XCTAssertNil(plan.layers.first { $0.name == "Auto — Subject" })
        XCTAssertTrue(plan.notes.joined(separator: " ").contains("crop"))
    }

    func testCropAlignedBoundsCheck() {
        let bounds = NormalizedRect(x: 0.1, y: 0.1, width: 0.3, height: 0.3)
        XCTAssertTrue(AutoRegionalCorrections.cropAligned(
            bounds: bounds, crop: NormalizedRect(x: 0, y: 0, width: 1, height: 1)
        ))
        XCTAssertFalse(AutoRegionalCorrections.cropAligned(
            bounds: bounds, crop: NormalizedRect(x: 0.6, y: 0.6, width: 0.4, height: 0.4)
        ))
        XCTAssertFalse(AutoRegionalCorrections.cropAligned(
            bounds: NormalizedRect(x: 0, y: 0, width: 0, height: 0),
            crop: NormalizedRect(x: 0, y: 0, width: 1, height: 1)
        ))
    }

    // MARK: - Duplicate prevention

    func testExistingAutoLayersSuppressPlanning() throws {
        var input = try conflictingInput()
        input.existingLayerNames = ["Auto — Subject", "My vignette"]
        XCTAssertTrue(AutoRegionalCorrections.hasAutoLayers(
            existingLayerNames: input.existingLayerNames
        ))
        let plan = AutoRegionalCorrections.plan(input)
        XCTAssertTrue(plan.layers.isEmpty, "repeated Auto runs must never stack layers")
        XCTAssertTrue(plan.notes.joined(separator: " ").contains("already exist"))
    }

    func testUserLayersDoNotSuppressPlanning() throws {
        var input = try conflictingInput()
        input.existingLayerNames = ["My vignette"]
        XCTAssertFalse(AutoRegionalCorrections.hasAutoLayers(
            existingLayerNames: input.existingLayerNames
        ))
        let plan = AutoRegionalCorrections.plan(input)
        XCTAssertFalse(plan.layers.isEmpty)
    }

    // MARK: - Localized color

    func testMaterialCastPlansColorCorrectionTowardNeutral() throws {
        var input = try conflictingInput()
        input.colorCast = 0.4
        let plan = AutoRegionalCorrections.plan(input)
        XCTAssertEqual(plan.layers.count, 3, "color is the third and final Auto-owned layer")
        let color = try XCTUnwrap(plan.layers.first { $0.name == "Auto — Color" })
        XCTAssertLessThan(color.adjustments.temperature, 6500, "a warm cast steers cool")
        XCTAssertTrue(color.hasVisibleLook)
    }

    func testNegligibleCastSkipsColor() throws {
        var input = try conflictingInput()
        input.colorCast = 0.05
        let plan = AutoRegionalCorrections.plan(input)
        XCTAssertNil(plan.layers.first { $0.name == "Auto — Color" })
    }

    // MARK: - Person preference and saliency discipline

    func testPersonEvidenceSelectsPersonTarget() throws {
        var input = try conflictingInput()
        input.prefersPersonTarget = true
        let plan = AutoRegionalCorrections.plan(input)
        let subject = try XCTUnwrap(plan.layers.first { $0.name == "Auto — Subject" })
        XCTAssertEqual(
            subject.components.compactMap(\.source.semanticDefinition?.target),
            [.person]
        )
    }

    func testDefaultSubjectTargetWithoutPersonEvidence() throws {
        let plan = AutoRegionalCorrections.plan(try conflictingInput())
        let subject = try XCTUnwrap(plan.layers.first { $0.name == "Auto — Subject" })
        XCTAssertEqual(
            subject.components.compactMap(\.source.semanticDefinition?.target),
            [.subject]
        )
    }

    // MARK: - Landmark-derived face mattes

    private func landmarkPoints() -> [NormalizedPoint] {
        // Inner-feature cluster: brows, eyes, nose, mouth.
        var points: [NormalizedPoint] = []
        for row in 0..<4 {
            for column in 0..<5 {
                points.append(NormalizedPoint(
                    x: 0.42 + Double(column) * 0.04,
                    y: 0.40 + Double(row) * 0.05
                ))
            }
        }
        return points
    }

    func testLandmarkMatteIsFeatheredAndCentered() throws {
        let matte = try FaceLandmarkMask.rasterize(
            points: landmarkPoints(), size: Self.size
        )
        XCTAssertEqual(matte.size, Self.size)
        let center = matte.values[(Self.size.height / 2) * Self.size.width + Self.size.width / 2]
        XCTAssertGreaterThan(center, 0.9, "the face center carries full weight")
        XCTAssertEqual(matte.values[0], 0, "the far corner carries no weight")
        let facts = AutoRegionalCorrections.facts(
            pixels: matte, confidence: 0.8,
            bounds: NormalizedRect(x: 0.3, y: 0.3, width: 0.4, height: 0.4)
        )
        XCTAssertGreaterThanOrEqual(
            facts.transitionFraction, AutoRegionalThresholds.minimumTransitionFraction,
            "landmark mattes must read as feathered to the planner"
        )
        XCTAssertGreaterThanOrEqual(facts.coverage, AutoRegionalThresholds.minimumCoverage)
        XCTAssertLessThanOrEqual(facts.coverage, AutoRegionalThresholds.maximumCoverage)
    }

    func testLandmarkMatteRejectsDegenerateInput() {
        XCTAssertThrowsError(try FaceLandmarkMask.rasterize(
            points: [NormalizedPoint(x: 0.5, y: 0.5)], size: Self.size
        ))
        XCTAssertThrowsError(try FaceLandmarkMask.rasterize(
            points: landmarkPoints(),
            size: PixelDimensions(width: 0, height: 0)
        ))
    }

    func testSupportIntersectionKeepsResolutionMismatchesOut() throws {
        let matte = try FaceLandmarkMask.rasterize(
            points: landmarkPoints(), size: Self.size
        )
        let otherSize = try NormalizedMask(
            size: PixelDimensions(width: 8, height: 8),
            values: [Float](repeating: 1, count: 64)
        )
        XCTAssertNil(AutoRegionalCorrections.intersectedWithSupport(matte, support: otherSize))
        let support = try softDisc()
        let combined = try XCTUnwrap(
            AutoRegionalCorrections.intersectedWithSupport(matte, support: support)
        )
        XCTAssertEqual(combined.size, Self.size)
        for index in matte.values.indices {
            XCTAssertLessThanOrEqual(
                combined.values[index],
                min(matte.values[index], support.values[index]) + 0.0001
            )
        }
    }
}

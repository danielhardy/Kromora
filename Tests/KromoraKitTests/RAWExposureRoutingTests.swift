import CoreImage
import XCTest

@testable import KromoraKit

/// KRMA-1174: the one global Exposure control reaches a RAW through `CIRAWFilter.exposure`.
///
/// This file holds the deterministic half — the routing rule, its identity/cache consequences and
/// the document lifecycle. The real-decoder half lives in `RAWExposureRoutingRenderTests`.
final class RAWExposureRoutingTests: XCTestCase {

    // MARK: - The routing rule

    func testRAWMovesSliderExposureIntoTheDecoderExactlyOnce() {
        let document = EditDocument(light: LightAdjustments(exposure: 2))
        let routed = document.routedForRendering(source: .raw)

        XCTAssertEqual(routed.light.exposure, 0, "the RGB stage must have nothing left to apply")
        XCTAssertEqual(
            try XCTUnwrap(routed.rawDevelop.exposure),
            2 * RAWExposureRouting.decoderStopsPerSliderStop, accuracy: 1e-12)
    }

    func testStandardImagesKeepRGBExposure() {
        let document = EditDocument(
            rawDevelop: RAWDevelopSettings(exposure: 0.5), light: LightAdjustments(exposure: 2))
        XCTAssertEqual(document.routedForRendering(source: .standard), document)
    }

    func testZeroSliderLeavesTheDecoderAtItsDefaultOrExplicitValue() {
        XCTAssertEqual(EditDocument().routedForRendering(source: .raw), EditDocument())
        let explicit = EditDocument(rawDevelop: RAWDevelopSettings(exposure: 0.4))
        XCTAssertEqual(explicit.routedForRendering(source: .raw), explicit)
        XCTAssertNil(
            EditDocument().routedForRendering(source: .raw).rawDevelop.exposure,
            "an untouched RAW must keep `nil` so it stays byte-identical to the neutral develop")
    }

    func testExistingExplicitDecoderExposureCombinesWithTheSliderInDecoderStops() throws {
        let document = EditDocument(
            rawDevelop: RAWDevelopSettings(exposure: 0.5), light: LightAdjustments(exposure: -1))
        let routed = document.routedForRendering(source: .raw)
        XCTAssertEqual(
            try XCTUnwrap(routed.rawDevelop.exposure),
            0.5 - RAWExposureRouting.decoderStopsPerSliderStop, accuracy: 1e-12)
        XCTAssertEqual(routed.light.exposure, 0)
    }

    func testRoutingPreservesEveryOtherControl() throws {
        var document = EditDocument(
            rawDevelop: RAWDevelopSettings(boostAmount: 0.5, neutralTemperature: 5200, neutralTint: 4),
            light: LightAdjustments(exposure: 1, contrast: 20, highlights: -30),
            color: ColorAdjustments(vibrance: 10),
            adjustments: [.exposure(ev: 0.25)],
            localAdjustments: [
                LocalAdjustmentLayer(
                    name: "Local", components: [], adjustments: LocalAdjustments(exposure: 0.7))
            ])
        document.rawDevelop.exposure = nil
        let routed = document.routedForRendering(source: .raw)

        var expected = document
        expected.rawDevelop.exposure = 0.75
        expected.light.exposure = 0
        XCTAssertEqual(routed, expected)
        XCTAssertEqual(
            try XCTUnwrap(routed.localAdjustments.first).adjustments.exposure,
            try XCTUnwrap(document.localAdjustments.first).adjustments.exposure,
            "local-mask exposure stays RGB")
        XCTAssertEqual(routed.adjustments, [.exposure(ev: 0.25)], "ordered RGB nodes stay RGB")
    }

    func testCalibrationIsMonotonicAndOriginPreserving() {
        XCTAssertEqual(RAWExposureRouting.decoderExposure(forSliderEV: 0), 0)
        let range = LightAdjustments.exposureRange
        var previous = RAWExposureRouting.decoderExposure(forSliderEV: range.lowerBound)
        for step in 1...20 {
            let ev = range.lowerBound + (range.upperBound - range.lowerBound) * Double(step) / 20
            let next = RAWExposureRouting.decoderExposure(forSliderEV: ev)
            XCTAssertGreaterThan(next, previous)
            previous = next
        }
    }

    // MARK: - Per-family calibration (KRMA-1180)

    private let toneCurveDecoder = RAWCapabilities(isLocalToneMapSupported: false)
    private let linearDecoder = RAWCapabilities(isLocalToneMapSupported: true)

    func testToneCurveAndUnknownDecodersUseTheMeasuredSonyRatio() throws {
        let document = EditDocument(light: LightAdjustments(exposure: 2))
        for decoder in [nil, toneCurveDecoder] {
            let routed = document.routedForRendering(source: .raw, decoder: decoder)
            XCTAssertEqual(try XCTUnwrap(routed.rawDevelop.exposure), 1.5, accuracy: 1e-12)
        }
        XCTAssertEqual(RAWExposureRouting.decoderStopsPerSliderStop, 0.75)
    }

    func testLocalToneMapDecodersMapOneSliderStopToOneDecoderStop() throws {
        let document = EditDocument(light: LightAdjustments(exposure: -2.5))
        let routed = document.routedForRendering(source: .raw, decoder: linearDecoder)
        XCTAssertEqual(try XCTUnwrap(routed.rawDevelop.exposure), -2.5, accuracy: 1e-12)
        XCTAssertEqual(routed.light.exposure, 0, "still applied exactly once")
    }

    func testExplicitDecoderExposureCombinesInDecoderStopsForEveryFamily() throws {
        let document = EditDocument(
            rawDevelop: RAWDevelopSettings(exposure: 0.4), light: LightAdjustments(exposure: 1))
        XCTAssertEqual(
            try XCTUnwrap(
                document.routedForRendering(source: .raw, decoder: toneCurveDecoder).rawDevelop.exposure),
            1.15, accuracy: 1e-12)
        XCTAssertEqual(
            try XCTUnwrap(
                document.routedForRendering(source: .raw, decoder: linearDecoder).rawDevelop.exposure),
            1.4, accuracy: 1e-12)
    }

    func testFamilySelectionIsMonotonicAndOriginPreservingForBoth() {
        for decoder in [toneCurveDecoder, linearDecoder] {
            XCTAssertEqual(RAWExposureRouting.decoderExposure(forSliderEV: 0, decoder: decoder), 0)
            let range = LightAdjustments.exposureRange
            var previous = RAWExposureRouting.decoderExposure(
                forSliderEV: range.lowerBound, decoder: decoder)
            for step in 1...20 {
                let ev = range.lowerBound + (range.upperBound - range.lowerBound) * Double(step) / 20
                let next = RAWExposureRouting.decoderExposure(forSliderEV: ev, decoder: decoder)
                XCTAssertGreaterThan(next, previous)
                previous = next
            }
        }
    }

    func testFamiliesShareNoDevelopKeyWhenTheirCalibrationsDiffer() {
        let document = EditDocument(light: LightAdjustments(exposure: 1))
        XCTAssertNotEqual(
            RenderDocumentIdentity(document.routedForRendering(source: .raw, decoder: toneCurveDecoder))
                .rawDevelop,
            RenderDocumentIdentity(document.routedForRendering(source: .raw, decoder: linearDecoder))
                .rawDevelop)
    }

    func testDecoderStateIsNeededOnlyForExposureOrLuminanceNoise() {
        XCTAssertFalse(RAWExposureRouting.needsDecoderState(EditDocument()))
        XCTAssertFalse(
            RAWExposureRouting.needsDecoderState(EditDocument(light: LightAdjustments(contrast: 20))))
        XCTAssertTrue(
            RAWExposureRouting.needsDecoderState(EditDocument(light: LightAdjustments(exposure: 0.1))))
    }

    func testRoutingARoutedDocumentChangesNothingForEveryFamily() {
        let document = EditDocument(
            rawDevelop: RAWDevelopSettings(exposure: 0.3), light: LightAdjustments(exposure: 1))
        for decoder in [toneCurveDecoder, linearDecoder] {
            let once = document.routedForRendering(source: .raw, decoder: decoder)
            XCTAssertEqual(once.routedForRendering(source: .raw, decoder: decoder), once)
        }
    }

    // MARK: - Identity and cache keys

    func testSliderTickChangesTheDevelopKeyAndNotTheRGBPrefixForRAW() {
        let a = EditDocument(light: LightAdjustments(exposure: 0.5, contrast: 10))
        let b = EditDocument(light: LightAdjustments(exposure: 1.0, contrast: 10))
        let idA = RenderDocumentIdentity(a.routedForRendering(source: .raw))
        let idB = RenderDocumentIdentity(b.routedForRendering(source: .raw))

        XCTAssertNotEqual(idA.rawDevelop, idB.rawDevelop, "decoder exposure must invalidate the source")
        XCTAssertNotEqual(idA.sessionKey, idB.sessionKey)
        XCTAssertEqual(
            idA.prefixUpstream, idB.prefixUpstream,
            "the RGB prefix no longer depends on an exposure the decoder applied")
    }

    /// KRMA-1176: Highlights, Shadows, Whites, Blacks and Contrast deliberately stay RGB curves for a
    /// RAW. Measured on four Sony ARWs, no decoder control (recovery, EDR, boost, shadow boost, local
    /// tone map) is a defensible equivalent (`docs/RAW_PIPELINE_INSPECTION.md`), so these sliders
    /// must neither reach the decoder nor invalidate the developed source while they are dragged.
    func testToneSlidersStayRGBAndNeverRedevelopTheRAW() {
        let base = EditDocument(rawDevelop: RAWDevelopSettings(boostAmount: 0.5))
        for light in [
            LightAdjustments(highlights: -80), LightAdjustments(shadows: 60),
            LightAdjustments(whites: -40), LightAdjustments(blacks: 30),
            LightAdjustments(contrast: 25),
        ] {
            var edited = base
            edited.light = light
            let routed = edited.routedForRendering(source: .raw)
            XCTAssertEqual(routed, edited, "\(light) must not be rerouted for a RAW")
            XCTAssertEqual(routed.rawDevelop, base.rawDevelop)
            XCTAssertEqual(
                RenderDocumentIdentity(routed).rawDevelop,
                RenderDocumentIdentity(base.routedForRendering(source: .raw)).rawDevelop,
                "an RGB tone slider must keep the developed-source key")
        }
    }

    func testStandardSourceExposureNeverInvalidatesTheDevelopedSource() {
        let a = EditDocument(light: LightAdjustments(exposure: 0.5))
        let b = EditDocument(light: LightAdjustments(exposure: 1.0))
        let idA = RenderDocumentIdentity(a.routedForRendering(source: .standard))
        let idB = RenderDocumentIdentity(b.routedForRendering(source: .standard))
        XCTAssertEqual(idA.rawDevelop, idB.rawDevelop)
        XCTAssertNotEqual(idA.prefixUpstream, idB.prefixUpstream)
    }

    func testEquivalentStoredSpellingsOfTheSameDecoderExposureShareAKey() {
        // 0.75 explicit decoder stops == 1 slider stop: one decoder exposure, one cache entry.
        let viaSlider = EditDocument(light: LightAdjustments(exposure: 1))
        let viaDevelop = EditDocument(rawDevelop: RAWDevelopSettings(exposure: 0.75))
        XCTAssertEqual(
            RenderDocumentIdentity(viaSlider.routedForRendering(source: .raw)).rawDevelop,
            RenderDocumentIdentity(viaDevelop.routedForRendering(source: .raw)).rawDevelop)
    }

    func testPixelEpochWasAdvancedForTheRoutingChange() {
        XCTAssertGreaterThanOrEqual(RenderPipeline.pixelEpoch, 42)
    }

    // MARK: - Document lifecycle

    func testRoutingNeverMutatesTheStoredDocumentAndSurvivesCodableRoundTrip() throws {
        let stored = EditDocument(
            rawDevelop: RAWDevelopSettings(exposure: 0.25), light: LightAdjustments(exposure: 1.5))
        _ = stored.routedForRendering(source: .raw)
        XCTAssertEqual(stored.light.exposure, 1.5)
        XCTAssertEqual(stored.rawDevelop.exposure, 0.25)

        let data = try JSONEncoder().encode(stored)
        let reopened = try JSONDecoder().decode(EditDocument.self, from: data)
        XCTAssertEqual(reopened, stored)
        XCTAssertEqual(
            reopened.routedForRendering(source: .raw), stored.routedForRendering(source: .raw))
    }

    func testResetThenUndoRestoreTheSameRoutedRendering() {
        let original = EditDocument(light: LightAdjustments(exposure: 1))
        var edited = original
        edited.light.exposure = 0  // slider reset
        XCTAssertNil(edited.routedForRendering(source: .raw).rawDevelop.exposure)
        edited = original  // undo restores the value document
        XCTAssertEqual(
            edited.routedForRendering(source: .raw).rawDevelop.exposure, 0.75)
    }

    func testPastingLightAndDevelopTogetherRoutesOneCombinedExposure() throws {
        let source = EditDocument(
            rawDevelop: RAWDevelopSettings(exposure: 0.5), light: LightAdjustments(exposure: 1))
        let payload = EditClipboardPayload(document: source)
        let pasted = payload.applying(to: EditDocument(), destinationIsRAW: true)
        XCTAssertEqual(pasted.light.exposure, 1)
        XCTAssertEqual(pasted.rawDevelop.exposure, 0.5)
        XCTAssertEqual(
            try XCTUnwrap(pasted.routedForRendering(source: .raw).rawDevelop.exposure), 1.25,
            accuracy: 1e-12)

        // A standard destination takes no decoder settings; its exposure stays RGB.
        let toStandard = payload.applying(to: EditDocument(), destinationIsRAW: false)
        XCTAssertNil(toStandard.rawDevelop.exposure)
        XCTAssertEqual(toStandard.routedForRendering(source: .standard).light.exposure, 1)
    }

    func testComparisonBaselineRoutesLikeTheEditedDocument() {
        // The comparison "before" frame is rendered through the same funnel, so a baseline that
        // carries exposure routes identically and the two frames differ only by the slider move.
        let baseline = EditDocument(light: LightAdjustments(exposure: 0.5))
        var edited = baseline
        edited.light.exposure = 1.5
        let b = baseline.routedForRendering(source: .raw)
        let e = edited.routedForRendering(source: .raw)
        XCTAssertNotEqual(b.rawDevelop.exposure, e.rawDevelop.exposure)
        var bNormalized = b
        bNormalized.rawDevelop.exposure = e.rawDevelop.exposure
        XCTAssertEqual(bNormalized, e)
    }
}

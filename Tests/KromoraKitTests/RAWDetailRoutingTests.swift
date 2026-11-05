import XCTest

@testable import KromoraKit

/// KRMA-1175: global Luminance/Colour noise reduction reaches a RAW through `CIRAWFilter` where the
/// file's decoder supports it. This is the deterministic half — the mapping, the routing rule and
/// its identity/lifecycle consequences. The real-decoder half is `RAWDetailRoutingRenderTests`.
final class RAWDetailRoutingTests: XCTestCase {

    /// A decoder shaped like the measured ISO 2000 Sony file: luminance default 0.712, colour 0.5.
    private let highISO = RAWCapabilities(
        isSharpnessSupported: true, isLuminanceNoiseReductionSupported: true,
        isColorNoiseReductionSupported: true, luminanceNoiseReductionAmount: 0.712,
        colorNoiseReductionAmount: 0.5)

    private func document(
        luminance: Double = 0, colour: Double = 0, sharpening: Double = 0
    ) -> EditDocument {
        var document = EditDocument()
        document.effects.detail = DetailAdjustments(
            sharpeningAmount: sharpening, luminanceNoise: luminance, colorNoise: colour)
        return document
    }

    // MARK: - The mapping

    func testSliderZeroLeavesTheDecoderAtItsDefaultAndNothingIsRouted() {
        let routed = document().routedForRendering(source: .raw, decoder: highISO)
        XCTAssertNil(routed.rawDevelop.luminanceNoiseReductionAmount)
        XCTAssertNil(routed.rawDevelop.colorNoiseReductionAmount)
        XCTAssertEqual(routed, document())
    }

    func testMappingAddsToTheDecoderDefaultNeverBelowIt() {
        for base in [0.0015, 0.5, 0.712, 1.0] {
            var previous = base
            for noise in stride(from: 1.0, through: 100, by: 11) {
                let amount = RAWDetailRouting.decoderAmount(base: base, noise: noise, detail: 50, contrast: 0)
                XCTAssertGreaterThanOrEqual(amount, previous, "monotonic at base \(base)")
                XCTAssertGreaterThanOrEqual(amount, base, "never below the decoder default")
                XCTAssertLessThanOrEqual(amount, 1)
                previous = amount
            }
            XCTAssertEqual(RAWDetailRouting.decoderAmount(base: base, noise: 100, detail: 50, contrast: 0), 1, accuracy: 1e-12)
        }
    }

    func testContrastRetainsPartOfTheUnfilteredSourceLikeTheRGBBlend() {
        let full = RAWDetailRouting.decoderAmount(base: 0.5, noise: 80, detail: 50, contrast: 0)
        let retained = RAWDetailRouting.decoderAmount(base: 0.5, noise: 80, detail: 50, contrast: 100)
        XCTAssertEqual(full, 0.5 + 0.5 * 0.8, accuracy: 1e-12)
        XCTAssertEqual(retained, 0.5 + 0.5 * 0.8 * 0.35, accuracy: 1e-12)
    }

    func testDetailTradesSmoothingForRetainedDetailAroundItsDefault() {
        func amount(_ detail: Double) -> Double {
            RAWDetailRouting.decoderAmount(base: 0.5, noise: 40, detail: detail, contrast: 0)
        }
        XCTAssertEqual(amount(50), 0.5 + 0.5 * 0.4, accuracy: 1e-12, "the default Detail is neutral")
        XCTAssertGreaterThan(amount(0), amount(50))
        XCTAssertLessThan(amount(100), amount(50))
        XCTAssertEqual(amount(100), 0.5 + 0.5 * 0.2, accuracy: 1e-12)
        XCTAssertLessThanOrEqual(RAWDetailRouting.decoderAmount(base: 0.9, noise: 100, detail: 0, contrast: 0), 1)
    }

    func testLuminanceIsRoutedAndColourStaysRGB() throws {
        let luminance = document(luminance: 50).routedForRendering(source: .raw, decoder: highISO)
        XCTAssertEqual(try XCTUnwrap(luminance.rawDevelop.luminanceNoiseReductionAmount), 0.712 + 0.288 * 0.5, accuracy: 1e-6)
        XCTAssertEqual(luminance.effects.detail.luminanceNoise, 0, "a routed channel leaves the RGB stage")

        let colour = document(colour: 50).routedForRendering(source: .raw, decoder: highISO)
        XCTAssertNil(colour.rawDevelop.colorNoiseReductionAmount, "Colour NR stays RGB; see RAWDetailRouting")
        XCTAssertNil(colour.rawDevelop.luminanceNoiseReductionAmount)
        XCTAssertEqual(colour, document(colour: 50))

        let both = document(luminance: 50, colour: 30).routedForRendering(source: .raw, decoder: highISO)
        XCTAssertEqual(both.effects.detail.colorNoise, 30, "Colour NR must not follow Luminance")
        XCTAssertEqual(both.effects.detail.luminanceNoise, 0)
    }

    func testAnExplicitDecoderAmountIsTheBaseNotTheDefault() throws {
        var stored = document(luminance: 50)
        stored.rawDevelop.luminanceNoiseReductionAmount = 0.2
        let routed = stored.routedForRendering(source: .raw, decoder: highISO)
        XCTAssertEqual(try XCTUnwrap(routed.rawDevelop.luminanceNoiseReductionAmount), 0.2 + 0.8 * 0.5, accuracy: 1e-6)
    }

    // MARK: - What is not routed

    func testStandardImagesKeepRGBNoiseReduction() {
        let stored = document(luminance: 60, colour: 40, sharpening: 30)
        XCTAssertEqual(stored.routedForRendering(source: .standard, decoder: highISO), stored)
    }

    func testAnUnsupportedControlStaysRGBAndWritesNothing() {
        var decoder = highISO
        decoder.isLuminanceNoiseReductionSupported = false
        let routed = document(luminance: 60, colour: 40).routedForRendering(source: .raw, decoder: decoder)
        XCTAssertNil(routed.rawDevelop.luminanceNoiseReductionAmount, "no write to an unsupported property")
        XCTAssertNil(routed.rawDevelop.colorNoiseReductionAmount)
        XCTAssertEqual(routed.effects.detail.luminanceNoise, 60, "RGB must still denoise it")

        let none = document(luminance: 60, colour: 40).routedForRendering(source: .raw, decoder: RAWCapabilities())
        XCTAssertEqual(none, document(luminance: 60, colour: 40))
    }

    func testRoutingARoutedDocumentChangesNothing() {
        let once = document(luminance: 50, colour: 30).routedForRendering(source: .raw, decoder: highISO)
        XCTAssertEqual(once.routedForRendering(source: .raw, decoder: highISO), once)
    }

    func testWithoutDecoderStateNoiseReductionStaysRGB() {
        let stored = document(luminance: 60)
        XCTAssertEqual(stored.routedForRendering(source: .raw), stored)
    }

    func testSharpeningLocalAdjustmentsAndOtherDetailControlsAreNeverRouted() {
        var stored = document(luminance: 40, sharpening: 80)
        stored.effects.detail.sharpeningRadius = 2
        stored.effects.detail.sharpeningMasking = 30
        stored.effects.detail.luminanceDetail = 70
        stored.effects.detail.luminanceContrast = 20
        stored.localAdjustments = [
            LocalAdjustmentLayer(
                name: "Local", components: [],
                adjustments: LocalAdjustments(sharpness: 50, noiseReduction: 50))
        ]
        let routed = stored.routedForRendering(source: .raw, decoder: highISO)
        XCTAssertNil(routed.rawDevelop.sharpnessAmount, "decoder sharpness has no radius or mask")
        XCTAssertEqual(routed.effects.detail.sharpeningAmount, 80)
        XCTAssertEqual(routed.effects.detail.sharpeningRadius, 2)
        XCTAssertEqual(routed.effects.detail.sharpeningMasking, 30)
        XCTAssertEqual(routed.effects.detail.luminanceDetail, 50, "a routed channel's sub-controls are consumed")
        XCTAssertEqual(routed.effects.detail.luminanceContrast, 0)
        XCTAssertEqual(routed.localAdjustments, stored.localAdjustments)
    }

    func testExposureAndNoiseReductionRouteTogetherWithoutDisturbingEachOther() throws {
        var stored = document(luminance: 50)
        stored.light.exposure = 1
        let routed = stored.routedForRendering(source: .raw, decoder: highISO)
        XCTAssertEqual(try XCTUnwrap(routed.rawDevelop.exposure), 0.75, accuracy: 1e-12)
        XCTAssertEqual(routed.light.exposure, 0)
        XCTAssertNotNil(routed.rawDevelop.luminanceNoiseReductionAmount)
    }

    // MARK: - Identity and cache keys

    func testANoiseTickInvalidatesTheDevelopedSourceAndASharpeningTickDoesNot() {
        func key(_ document: EditDocument) -> RenderDocumentIdentity {
            RenderDocumentIdentity(document.routedForRendering(source: .raw, decoder: highISO))
        }
        let a = key(document(luminance: 30))
        let b = key(document(luminance: 31))
        XCTAssertNotEqual(a.rawDevelop, b.rawDevelop, "decoder NR must re-develop the source")
        XCTAssertNotEqual(a.sessionKey, b.sessionKey)

        let sharpA = key(document(luminance: 30, sharpening: 20))
        let sharpB = key(document(luminance: 30, sharpening: 60))
        XCTAssertEqual(sharpA.rawDevelop, sharpB.rawDevelop, "sharpening stays RGB: no re-development")
        XCTAssertNotEqual(sharpA.sessionKey, sharpB.sessionKey)
    }

    func testDetailAndContrastTicksAlsoRedevelopBecauseTheyReachTheDecoder() {
        func key(_ detail: Double) -> String {
            var document = document(luminance: 40)
            document.effects.detail.luminanceDetail = detail
            return RenderDocumentIdentity(
                document.routedForRendering(source: .raw, decoder: highISO)).rawDevelop
        }
        XCTAssertNotEqual(key(40), key(60))
    }

    func testTheRoutedFormIsDistinctFromTheRGBFormInEveryCacheKey() {
        let stored = document(luminance: 30)
        let routed = RenderDocumentIdentity(stored.routedForRendering(source: .raw, decoder: highISO))
        let rgb = RenderDocumentIdentity(stored.routedForRendering(source: .raw))
        XCTAssertNotEqual(routed.sessionKey, rgb.sessionKey)
        XCTAssertNotEqual(routed.rawDevelop, rgb.rawDevelop)
        XCTAssertNotEqual(routed.prefixUpstream, rgb.prefixUpstream, "the RGB Detail stage changed")
    }

    // MARK: - Lifecycle

    func testRoutingNeverMutatesTheStoredDocumentAndSurvivesReopen() throws {
        let stored = document(luminance: 45, colour: 25)
        let routed = stored.routedForRendering(source: .raw, decoder: highISO)
        XCTAssertNotEqual(routed, stored)
        XCTAssertEqual(stored.effects.detail.luminanceNoise, 45)
        XCTAssertNil(stored.rawDevelop.luminanceNoiseReductionAmount)

        let reopened = try JSONDecoder().decode(
            EditDocument.self, from: try JSONEncoder().encode(stored))
        XCTAssertEqual(reopened, stored)
        XCTAssertEqual(
            reopened.routedForRendering(source: .raw, decoder: highISO), routed,
            "a reopened edit routes exactly as before")
    }

    func testResetUndoAndPasteRouteFromTheValueDocument() throws {
        let original = document(luminance: 40)
        var edited = original
        edited.effects.detail = .neutral  // reset
        XCTAssertNil(edited.routedForRendering(source: .raw, decoder: highISO).rawDevelop.luminanceNoiseReductionAmount)
        edited = original  // undo
        XCTAssertNotNil(edited.routedForRendering(source: .raw, decoder: highISO).rawDevelop.luminanceNoiseReductionAmount)

        // The decoder default is per image, so the same stored edit routes per destination file.
        let lowISO = RAWCapabilities(
            isLuminanceNoiseReductionSupported: true, luminanceNoiseReductionAmount: 0.0015)
        let onLow = try XCTUnwrap(original.routedForRendering(source: .raw, decoder: lowISO).rawDevelop.luminanceNoiseReductionAmount)
        let onHigh = try XCTUnwrap(original.routedForRendering(source: .raw, decoder: highISO).rawDevelop.luminanceNoiseReductionAmount)
        XCTAssertEqual(onLow, 0.0015 + 0.9985 * 0.4, accuracy: 1e-9)
        XCTAssertEqual(onHigh, 0.712 + 0.288 * 0.4, accuracy: 1e-9)
    }

    func testPixelEpochWasAdvancedForTheNoiseRoutingChange() {
        XCTAssertGreaterThanOrEqual(RenderPipeline.pixelEpoch, 41)
    }
}

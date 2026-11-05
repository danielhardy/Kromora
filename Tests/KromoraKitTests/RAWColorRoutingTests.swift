import XCTest

@testable import KromoraKit

/// KRMA-1179: which global Color controls reach the RAW decoder, and which do not.
///
/// The decision (`docs/RAW_PIPELINE_INSPECTION.md`, "RAW colour headroom"): only global white balance
/// is decoder-based, as before. Saturation, Vibrance, the HSL mixer and colour grading stay on
/// developed RGB because `CIRAWFilter` has no equivalent, and decoder gamut mapping / EDR stay at the
/// decoder defaults because neither measurably preserves more colour at delivery. These tests pin
/// that so a colour slider can never silently re-develop the RAW, stack a decoder operation on an RGB
/// one, or lose a stored decoder setting; the real-decoder half is `RAWColorRoutingRenderTests`.
final class RAWColorRoutingTests: XCTestCase {

    private static let colorEdits: [(String, ColorAdjustments)] = [
        ("saturation", ColorAdjustments(saturation: 60)),
        ("vibrance", ColorAdjustments(vibrance: -40)),
        ("mixer", ColorAdjustments(mixer: ColorMixerAdjustments(red: ColorMixerChannel(saturation: 50)))),
        (
            "grading",
            ColorAdjustments(
                grading: ColorGradingAdjustments(highlights: ColorGradingWheel(hue: 40, saturation: 60)))
        ),
    ]

    /// Every decoder setting a colour edit must leave alone, all set explicitly.
    private static let explicitDecoder = RAWDevelopSettings(
        neutralTemperature: 4800, neutralTint: 12, gamutMappingEnabled: false,
        extendedDynamicRangeAmount: 1)

    // MARK: - Routing

    func testColorControlsStayRGBForRAWAndNeverTouchTheDecoderSettings() {
        for (name, color) in Self.colorEdits {
            var document = EditDocument(rawDevelop: Self.explicitDecoder)
            document.color = color
            for decoder in [nil, RAWCapabilities.everyGateOpen] {
                let routed = document.routedForRendering(source: .raw, decoder: decoder)
                XCTAssertEqual(routed, document, "\(name) must not be rerouted for a RAW")
                XCTAssertEqual(routed.rawDevelop, Self.explicitDecoder, name)
                XCTAssertEqual(routed.color, color, "\(name) must stay in the RGB colour stage")
            }
        }
    }

    func testStandardImagesRenderTheSameColorDocument() {
        for (name, color) in Self.colorEdits {
            let document = EditDocument(color: color)
            XCTAssertEqual(document.routedForRendering(source: .standard), document, name)
        }
    }

    func testRoutingDoesNotNeedDecoderStateForColor() {
        for (name, color) in Self.colorEdits {
            XCTAssertFalse(
                RAWExposureRouting.needsDecoderState(EditDocument(color: color)),
                "\(name) must not make the engine probe the decoder")
        }
    }

    func testMaskedColorStaysOnTheLocalLayer() {
        var adjustments = LocalAdjustments.neutral
        adjustments.saturation = 40
        adjustments.vibrance = 20
        adjustments.temperature = 5200
        adjustments.tint = 10
        let local = LocalAdjustmentLayer(name: "Sky", components: [], adjustments: adjustments)
        let document = EditDocument(
            rawDevelop: Self.explicitDecoder, localAdjustments: [local])
        XCTAssertEqual(document.routedForRendering(source: .raw), document)
    }

    // MARK: - Global white balance stays decoder-based

    func testRAWWhiteBalanceRemainsInTheDecoderSettingsAndSurvivesColorEdits() {
        var document = EditDocument(
            rawDevelop: RAWDevelopSettings(neutralTemperature: 3200, neutralTint: -20))
        document.color = ColorAdjustments(vibrance: 20, saturation: 30)
        let routed = document.routedForRendering(source: .raw, decoder: .everyGateOpen)
        XCTAssertEqual(routed.rawDevelop.neutralTemperature, 3200)
        XCTAssertEqual(routed.rawDevelop.neutralTint, -20)
        XCTAssertTrue(routed.adjustments.isEmpty, "no RGB white-balance node may stack on the decoder's")
    }

    func testAsShotIsTheAbsenceOfAnOverride() {
        // "As shot" / reset is nil (the file's own value), never a stored copy of it.
        let reset = RAWDevelopSettings(neutralTemperature: nil, neutralTint: nil)
        XCTAssertTrue(reset.isNeutral)
        XCTAssertTrue(EditDocument(rawDevelop: reset).isIdentity)
    }

    // MARK: - Cache identity

    func testColorSlidersKeepTheDevelopedSourceKey() {
        let base = EditDocument(rawDevelop: Self.explicitDecoder)
        let baseIdentity = RenderDocumentIdentity(base.routedForRendering(source: .raw))
        for (name, color) in Self.colorEdits {
            var edited = base
            edited.color = color
            let identity = RenderDocumentIdentity(edited.routedForRendering(source: .raw))
            XCTAssertEqual(identity.rawDevelop, baseIdentity.rawDevelop, "\(name) must not re-develop")
            XCTAssertNotEqual(
                identity.prefixUpstream, baseIdentity.prefixUpstream,
                "\(name) must still invalidate the processing prefix")
        }
    }

    func testEveryEffectiveDecoderColorSettingChangesTheDevelopedSourceKey() {
        let baseline = RenderDocumentIdentity(EditDocument().routedForRendering(source: .raw)).rawDevelop
        var seen: Set<String> = [baseline]
        let variants: [(String, RAWDevelopSettings)] = [
            ("gamut off", RAWDevelopSettings(gamutMappingEnabled: false)),
            ("EDR 1", RAWDevelopSettings(extendedDynamicRangeAmount: 1)),
            ("EDR 2", RAWDevelopSettings(extendedDynamicRangeAmount: 2)),
            ("gamut off + EDR 1", RAWDevelopSettings(gamutMappingEnabled: false, extendedDynamicRangeAmount: 1)),
            ("temperature", RAWDevelopSettings(neutralTemperature: 4300)),
            ("tint", RAWDevelopSettings(neutralTint: 30)),
        ]
        for (name, settings) in variants {
            let key = RenderDocumentIdentity(
                EditDocument(rawDevelop: settings).routedForRendering(source: .raw)
            ).rawDevelop
            XCTAssertTrue(seen.insert(key).inserted, "\(name) must have its own developed-source key")
        }
    }

    // MARK: - Persistence and lifecycle

    func testDecoderColorSettingsRoundTripAndLegacyDocumentsReadAsDecoderDefaults() throws {
        let stored = EditDocument(rawDevelop: Self.explicitDecoder, color: ColorAdjustments(saturation: 25))
        let decoded = try JSONDecoder().decode(EditDocument.self, from: JSONEncoder().encode(stored))
        XCTAssertEqual(decoded, stored)
        XCTAssertEqual(decoded.rawDevelop.gamutMappingEnabled, false)
        XCTAssertEqual(decoded.rawDevelop.extendedDynamicRangeAmount, 1)

        // A document written before any decoder colour setting existed leaves them at the decoder default.
        let legacy = try JSONDecoder().decode(EditDocument.self, from: Data("{\"version\":1}".utf8))
        XCTAssertNil(legacy.rawDevelop.gamutMappingEnabled)
        XCTAssertNil(legacy.rawDevelop.extendedDynamicRangeAmount)
        XCTAssertTrue(legacy.rawDevelop.isNeutral)
    }

    func testRoutingDoesNotMutateTheStoredColorDocument() {
        var stored = EditDocument(rawDevelop: Self.explicitDecoder)
        stored.color = ColorAdjustments(vibrance: 10, saturation: 80)
        let snapshot = stored
        _ = stored.routedForRendering(source: .raw, decoder: .everyGateOpen)
        XCTAssertEqual(stored, snapshot)
    }

    // MARK: - Capability gating

    func testGamutMappingAndEDRAreUngatedAndColorControlsAreNotDecoderControls() {
        // Gamut mapping and EDR exist on every decodable RAW; there is no per-camera flag to gate on.
        for capabilities in [RAWCapabilities(), .everyGateOpen] {
            XCTAssertTrue(capabilities.supports(.gamutMapping))
            XCTAssertTrue(capabilities.supports(.extendedDynamicRange))
            XCTAssertTrue(capabilities.supports(.whiteBalance))
        }
        // The decoder control set has no saturation, vibrance, mixer or grading entry to route to.
        let titles = Set(DevelopControl.allCases.map { $0.title.lowercased() })
        for forbidden in ["saturation", "vibrance", "mixer", "grading"] {
            XCTAssertFalse(titles.contains { $0.contains(forbidden) }, forbidden)
        }
    }
}

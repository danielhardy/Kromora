import CoreGraphics
import Foundation
import XCTest

@testable import KromoraKit

/// Focused coverage for KRMA-346: Core Image automatic enhancement as a fitted reference.
///
/// All assertions use ranges/invariants, never exact floating-point equality: the fitter is
/// deterministic (same buffers twice give the same proposal), but Apple filter behavior varies
/// by OS, so production-descriptor assertions only pin graceful structure, never pixel values.
final class AppleEnhancementReferenceTests: XCTestCase {
    // MARK: - Fixtures

    private struct StubDescriptor: AppleAutoAdjustmentDescribing {
        var render: AppleReferenceRender?
        func reference(for samples: RenderedPixelSamples) -> AppleReferenceRender? { render }
    }

    private func solid(
        _ value: UInt8, width: Int = 64, height: Int = 64
    ) -> RenderedPixelSamples {
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        for index in 0..<(width * height) {
            bytes[index * 4] = value
            bytes[index * 4 + 1] = value
            bytes[index * 4 + 2] = value
        }
        return RenderedPixelSamples(width: width, height: height, bytes: bytes, space: .sRGB)
    }

    private func solidRGB(
        _ pixel: (UInt8, UInt8, UInt8), width: Int = 64, height: Int = 64
    ) -> RenderedPixelSamples {
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        for index in 0..<(width * height) {
            bytes[index * 4] = pixel.0
            bytes[index * 4 + 1] = pixel.1
            bytes[index * 4 + 2] = pixel.2
        }
        return RenderedPixelSamples(width: width, height: height, bytes: bytes, space: .sRGB)
    }

    private func gradient(width: Int = 64, height: Int = 64) -> RenderedPixelSamples {
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let value = UInt8((Double(x) / Double(max(1, width - 1)) * 255).rounded())
                let offset = (y * width + x) * 4
                bytes[offset] = value
                bytes[offset + 1] = value
                bytes[offset + 2] = value
            }
        }
        return RenderedPixelSamples(width: width, height: height, bytes: bytes, space: .sRGB)
    }

    private func mixedThirds(width: Int = 63, height: Int = 63) -> RenderedPixelSamples {
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                if x < width / 3 {
                    bytes[offset] = 255; bytes[offset + 1] = 0; bytes[offset + 2] = 0
                } else if x < 2 * width / 3 {
                    bytes[offset] = 0; bytes[offset + 1] = 255; bytes[offset + 2] = 0
                } else {
                    bytes[offset] = 0; bytes[offset + 1] = 0; bytes[offset + 2] = 255
                }
            }
        }
        return RenderedPixelSamples(width: width, height: height, bytes: bytes, space: .sRGB)
    }

    private func standardSource() -> ImageSource {
        ImageSource(data: Data("apple-reference".utf8), nativeExtent: CGSize(width: 64, height: 64))
    }

    private func configured(
        baseline: RenderedPixelSamples?,
        reference: AppleReferenceRender?
    ) async -> (AppleEnhancementReferenceAdapter, FakeRenderEngine) {
        let engine = FakeRenderEngine()
        await engine.setSampledStub(baseline)
        let adapter = AppleEnhancementReferenceAdapter(
            engine: engine, descriptor: StubDescriptor(render: reference)
        )
        return (adapter, engine)
    }

    // MARK: - Filter-name mapping (pure, pinned)

    func testKnownFiltersMapToSupportedEffects() {
        XCTAssertEqual(
            CIAutoAdjustmentDescriptor.effect(
                forFilterName: "CIVibrance", values: ["inputAmount": 0.3]
            ),
            .vibrance(amount: 0.3)
        )
        XCTAssertEqual(
            CIAutoAdjustmentDescriptor.effect(forFilterName: "CIToneCurve", values: [:]),
            .toneCurve
        )
        XCTAssertEqual(
            CIAutoAdjustmentDescriptor.effect(
                forFilterName: "CIHighlightShadowAdjust",
                values: ["inputHighlightAmount": 1, "inputShadowAmount": 0.45]
            ),
            .highlightShadow(highlight: 1, shadow: 0.45)
        )
    }

    func testUnknownFiltersMapToUnsupported() {
        XCTAssertEqual(
            CIAutoAdjustmentDescriptor.effect(forFilterName: "CIRedEyeCorrection", values: [:]),
            .unsupported(name: "CIRedEyeCorrection")
        )
        XCTAssertEqual(
            CIAutoAdjustmentDescriptor.effect(forFilterName: "CIFaceBalance", values: [:]),
            .unsupported(name: "CIFaceBalance")
        )
        XCTAssertEqual(
            CIAutoAdjustmentDescriptor.effect(forFilterName: "CISomeFutureFilter", values: [:]),
            .unsupported(name: "CISomeFutureFilter")
        )
        // Non-finite inputs never cross the boundary.
        XCTAssertEqual(
            CIAutoAdjustmentDescriptor.effect(
                forFilterName: "CIVibrance", values: ["inputAmount": .nan]
            ),
            .vibrance(amount: 0)
        )
    }

    // MARK: - Unavailable paths (never block native proposals)

    func testUnsupportedRuntimeReturnsUnavailable() async {
        let (adapter, _) = await configured(
            baseline: solid(128),
            reference: AppleReferenceRender(intent: AppleReferenceIntent(effects: [.toneCurve]))
        )
        let gated = AppleEnhancementReferenceAdapter(
            engine: adapter.engine, descriptor: StubDescriptor(render: nil),
            availabilityOverride: false
        )
        let result = await gated.referenceProposal(
            source: standardSource(), document: EditDocument(), sourceKind: .standard
        )
        guard case .unavailable(let code, _) = result else {
            return XCTFail("expected unavailable, got \(result)")
        }
        XCTAssertEqual(code, .unsupportedOS)
    }

    func testSupportedRuntimeGateIsOpen() {
        XCTAssertTrue(
            AppleEnhancementReferenceAdapter.isSupportedRuntime,
            "the deployment target postdates the availability gate"
        )
    }

    func testNilBaselineSamplesReturnRenderUnavailable() async {
        let (adapter, _) = await configured(baseline: nil, reference: nil)
        let result = await adapter.referenceProposal(
            source: standardSource(), document: EditDocument(), sourceKind: .standard
        )
        guard case .unavailable(let code, _) = result else {
            return XCTFail("expected unavailable, got \(result)")
        }
        XCTAssertEqual(code, .renderUnavailable)
    }

    func testNilDescriptorRenderReturnsCoreImageFailure() async {
        let (adapter, _) = await configured(baseline: solid(128), reference: nil)
        let result = await adapter.referenceProposal(
            source: standardSource(), document: EditDocument(), sourceKind: .standard
        )
        guard case .unavailable(let code, _) = result else {
            return XCTFail("expected unavailable, got \(result)")
        }
        XCTAssertEqual(code, .coreImageFailure)
    }

    func testEmptyIntentReturnsNoEnhancementSuggested() async {
        let (adapter, _) = await configured(
            baseline: solid(128),
            reference: AppleReferenceRender(intent: AppleReferenceIntent(effects: []))
        )
        let result = await adapter.referenceProposal(
            source: standardSource(), document: EditDocument(), sourceKind: .standard
        )
        guard case .unavailable(let code, _) = result else {
            return XCTFail("expected unavailable, got \(result)")
        }
        XCTAssertEqual(code, .noEnhancementSuggested)
    }

    func testMalformedSourceReturnsMalformedImage() async {
        let (adapter, _) = await configured(baseline: solid(128), reference: nil)
        let bad = ImageSource(data: Data("bad".utf8), nativeExtent: .zero)
        let result = await adapter.referenceProposal(
            source: bad, document: EditDocument(), sourceKind: .standard
        )
        guard case .unavailable(let code, _) = result else {
            return XCTFail("expected unavailable, got \(result)")
        }
        XCTAssertEqual(code, .malformedImage)
    }

    func testMatchingReferenceReturnsNoActionableDelta() async {
        let baseline = solid(128)
        let (adapter, _) = await configured(
            baseline: baseline,
            reference: AppleReferenceRender(
                intent: AppleReferenceIntent(effects: [.toneCurve]), samples: baseline
            )
        )
        let result = await adapter.referenceProposal(
            source: standardSource(), document: EditDocument(), sourceKind: .standard
        )
        guard case .unavailable(let code, _) = result else {
            return XCTFail("expected unavailable, got \(result)")
        }
        XCTAssertEqual(code, .noActionableDelta)
    }

    // MARK: - Render-compare fitting

    func testDarkBaselineBrightReferenceProposesPositiveExposure() async {
        let (adapter, _) = await configured(
            baseline: solid(64),
            reference: AppleReferenceRender(
                intent: AppleReferenceIntent(effects: [.toneCurve]), samples: solid(160)
            )
        )
        let result = await adapter.referenceProposal(
            source: standardSource(), document: EditDocument(), sourceKind: .standard
        )
        guard case .proposed(let proposal) = result else {
            return XCTFail("expected a proposal, got \(result)")
        }
        guard let exposure = proposal.changes[.exposure] else {
            return XCTFail("expected an exposure change, got \(proposal.changedControls)")
        }
        XCTAssertGreaterThan(exposure.proposed, 0)
        XCTAssertLessThanOrEqual(
            exposure.proposed, AutoExposureObjective.structurallyUnderexposedCorrectionCapEV
        )
        XCTAssertEqual(proposal.provenance.fitMethod, .renderCompare)
        XCTAssertEqual(proposal.provenance.filterNames, ["CIToneCurve"])
        XCTAssertEqual(proposal.provenance.sourceKind, .standard)
        XCTAssertEqual(proposal.provenance.space, .sRGB)
        // The reference informs but never decides: confidence is capped.
        XCTAssertGreaterThan(proposal.confidence, 0)
        XCTAssertLessThanOrEqual(proposal.confidence, 0.75)
        XCTAssertGreaterThanOrEqual(proposal.residualError, 0)
        XCTAssertLessThanOrEqual(proposal.residualError, 1)
        // The fitted document carries the exposure; nothing else owns opaque state.
        XCTAssertEqual(proposal.document.light.exposure, exposure.proposed)
    }

    func testFitIsDeterministic() {
        let baseline = solid(64)
        let reference = solid(160)
        let intent = AppleReferenceIntent(effects: [.toneCurve])
        let current = EditDocument()
        let first = AppleReferenceFitter.fit(
            baseline: baseline, reference: reference, intent: intent,
            current: current, sourceKind: .standard
        )
        let second = AppleReferenceFitter.fit(
            baseline: baseline, reference: reference, intent: intent,
            current: current, sourceKind: .standard
        )
        XCTAssertEqual(first, second)
    }

    // MARK: - White-balance direction (pinned)

    func testWarmReferenceRaisesRawTemperatureAndLowersStandardTemperature() async {
        // Baseline neutral; reference pushed warm (R up, B down).
        let baseline = solidRGB((128, 128, 128))
        let warmReference = solidRGB((152, 128, 104))
        let intent = AppleReferenceIntent(effects: [.toneCurve])

        let (rawAdapter, _) = await configured(
            baseline: baseline,
            reference: AppleReferenceRender(intent: intent, samples: warmReference)
        )
        let rawResult = await rawAdapter.referenceProposal(
            source: standardSource(), document: EditDocument(), sourceKind: .raw,
            asShotTemperature: 5500
        )
        guard case .proposed(let rawProposal) = rawResult else {
            return XCTFail("expected a RAW proposal, got \(rawResult)")
        }
        guard let rawTemp = rawProposal.changes[.temperature] else {
            return XCTFail("expected a RAW temperature change, got \(rawProposal.changedControls)")
        }
        // Photographic direction: reproducing warmth raises the RAW temperature.
        XCTAssertGreaterThan(rawTemp.proposed, 5500)
        XCTAssertLessThanOrEqual(rawTemp.proposed, 5500 + 2500)

        let (standardAdapter, _) = await configured(
            baseline: baseline,
            reference: AppleReferenceRender(intent: intent, samples: warmReference)
        )
        let standardResult = await standardAdapter.referenceProposal(
            source: standardSource(), document: EditDocument(), sourceKind: .standard
        )
        guard case .proposed(let standardProposal) = standardResult else {
            return XCTFail("expected a standard proposal, got \(standardResult)")
        }
        guard let standardTemp = standardProposal.changes[.temperature] else {
            return XCTFail(
                "expected a standard temperature change, got \(standardProposal.changedControls)"
            )
        }
        // Inverted about D65: reproducing warmth lowers the standard temperature.
        XCTAssertLessThan(standardTemp.proposed, 6500)
        XCTAssertGreaterThanOrEqual(standardTemp.proposed, 6500 - 1500)
    }

    func testRawWithoutBaseTemperatureOmitsTemperatureAndReports() async {
        let baseline = solidRGB((128, 128, 128))
        let warmReference = solidRGB((152, 128, 104))
        let (adapter, _) = await configured(
            baseline: baseline,
            reference: AppleReferenceRender(
                intent: AppleReferenceIntent(effects: [.toneCurve]), samples: warmReference
            )
        )
        // No RAW base temperature anywhere: no absolute Kelvin to propose.
        let result = await adapter.referenceProposal(
            source: standardSource(), document: EditDocument(), sourceKind: .raw
        )
        if case .proposed(let proposal) = result {
            XCTAssertNil(
                proposal.changes[.temperature],
                "temperature without a base is a guess, not a fit"
            )
            XCTAssertTrue(
                proposal.provenance.omittedEffects.contains(where: { $0.contains("temperature") }),
                "expected the omission to be reported, got \(proposal.provenance.omittedEffects)"
            )
        } else if case .unavailable(let code, _) = result {
            XCTAssertEqual(code, .noActionableDelta)
        }
    }

    // MARK: - Preservation and provenance

    func testCompleteEditFinishIsPreservedAndAnalysisViewIsFitted() async {
        var complete = EditDocument()
        complete.lut = LUTSettings(lutID: LUTID(raw: "look"), intensity: 0.8)
        complete.color.grading = ColorGradingAdjustments(
            shadows: ColorGradingWheel(hue: 30, saturation: 40),
            midtones: .neutral, highlights: .neutral
        )
        complete.effects.grain = GrainAdjustments(amount: 30)
        complete.effects.vignette = VignetteAdjustments(amount: -40)

        let (adapter, engine) = await configured(
            baseline: solid(64),
            reference: AppleReferenceRender(
                intent: AppleReferenceIntent(effects: [.toneCurve]), samples: solid(160)
            )
        )
        let result = await adapter.referenceProposal(
            source: standardSource(), document: complete, sourceKind: .standard
        )
        guard case .proposed(let proposal) = result else {
            return XCTFail("expected a proposal, got \(result)")
        }
        // The finish survives byte-for-byte on the proposed document.
        XCTAssertEqual(proposal.document.lut, complete.lut)
        XCTAssertEqual(proposal.document.color.grading, complete.color.grading)
        XCTAssertEqual(proposal.document.effects.grain, complete.effects.grain)
        XCTAssertEqual(proposal.document.effects.vignette, complete.effects.vignette)
        XCTAssertEqual(proposal.document.crop, complete.crop)
        XCTAssertEqual(proposal.document.rotation, complete.rotation)
        XCTAssertEqual(proposal.document.localAdjustments, complete.localAdjustments)
        // The sampler measured the analysis view, not the finished edit.
        let requests = await engine.sampleRequests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.document.lut, LUTSettings.none)
        XCTAssertEqual(requests.first?.document.color.grading, .neutral)
        XCTAssertEqual(requests.first?.document.effects.grain, .neutral)
        XCTAssertEqual(requests.first?.document.effects.vignette, .neutral)
        XCTAssertEqual(requests.first?.space, .sRGB)
        // Provenance records both hashes; they differ exactly because the finish was restored.
        XCTAssertEqual(
            proposal.provenance.completeDocumentHash, complete.editHash
        )
        XCTAssertNotEqual(
            proposal.provenance.analysisDocumentHash, proposal.provenance.completeDocumentHash
        )
        // Only fitted controls appear in the change map — no opaque filter state.
        let allowed: Set<AutoPolicyControl> = [
            .exposure, .contrast, .highlights, .shadows, .whites, .blacks,
            .temperature, .tint, .vibrance, .saturation,
        ]
        XCTAssertTrue(
            Set(proposal.changedControls).isSubset(of: allowed),
            "unexpected controls: \(proposal.changedControls)"
        )
    }

    func testMixedFrameOmitsWhiteBalanceAndReports() async {
        let baseline = mixedThirds()
        // Warm-shift every channel triplet equally so the tone fit still sees a delta while the
        // hue facts stay mixed.
        var warmBytes = baseline.bytes
        for index in 0..<(baseline.width * baseline.height) {
            let lifted = UInt16(baseline.bytes[index * 4]) + 24
            warmBytes[index * 4] = UInt8(min(255, lifted))
            warmBytes[index * 4 + 2] = baseline.bytes[index * 4 + 2] / 2
        }
        let warmReference = RenderedPixelSamples(
            width: baseline.width, height: baseline.height, bytes: warmBytes, space: .sRGB
        )
        let (adapter, _) = await configured(
            baseline: baseline,
            reference: AppleReferenceRender(
                intent: AppleReferenceIntent(effects: [.toneCurve]), samples: warmReference
            )
        )
        let result = await adapter.referenceProposal(
            source: standardSource(), document: EditDocument(), sourceKind: .standard
        )
        switch result {
        case .proposed(let proposal):
            XCTAssertNil(proposal.changes[.temperature])
            XCTAssertNil(proposal.changes[.tint])
            XCTAssertTrue(
                proposal.provenance.omittedEffects.contains(where: {
                    $0.contains("white-balance")
                }),
                "expected a reported WB omission, got \(proposal.provenance.omittedEffects)"
            )
        case .unavailable(let code, _):
            XCTAssertEqual(code, .noActionableDelta)
        }
    }

    func testUnsupportedEffectsAreOmittedAndReported() async {
        let (adapter, _) = await configured(
            baseline: solid(100),
            reference: AppleReferenceRender(
                intent: AppleReferenceIntent(effects: [
                    .unsupported(name: "CIRedEyeCorrection"),
                    .vibrance(amount: 0.4),
                ]),
                samples: solid(110)
            )
        )
        let result = await adapter.referenceProposal(
            source: standardSource(), document: EditDocument(), sourceKind: .standard
        )
        guard case .proposed(let proposal) = result else {
            return XCTFail("expected a proposal, got \(result)")
        }
        XCTAssertTrue(
            proposal.provenance.omittedEffects.contains(where: {
                $0.contains("CIRedEyeCorrection")
            }),
            "expected the red-eye omission, got \(proposal.provenance.omittedEffects)"
        )
        XCTAssertEqual(proposal.provenance.filterNames, ["CIRedEyeCorrection", "CIVibrance"])
    }

    // MARK: - Intent-only fallback

    func testIntentOnlyVibranceMapsWithLowConfidence() async {
        let (adapter, _) = await configured(
            baseline: solid(128),
            reference: AppleReferenceRender(
                intent: AppleReferenceIntent(effects: [.vibrance(amount: 0.2)])
            )
        )
        let result = await adapter.referenceProposal(
            source: standardSource(), document: EditDocument(), sourceKind: .standard
        )
        guard case .proposed(let proposal) = result else {
            return XCTFail("expected a proposal, got \(result)")
        }
        XCTAssertEqual(proposal.provenance.fitMethod, .filterIntent)
        guard let vibrance = proposal.changes[.vibrance] else {
            return XCTFail("expected a vibrance change, got \(proposal.changedControls)")
        }
        XCTAssertGreaterThan(vibrance.proposed, 0)
        XCTAssertLessThanOrEqual(proposal.confidence, 0.5)
    }

    func testIntentOnlyToneCurveWithoutPixelsIsOmitted() async {
        let (adapter, _) = await configured(
            baseline: solid(128),
            reference: AppleReferenceRender(
                intent: AppleReferenceIntent(effects: [.toneCurve])
            )
        )
        let result = await adapter.referenceProposal(
            source: standardSource(), document: EditDocument(), sourceKind: .standard
        )
        guard case .unavailable(let code, let message) = result else {
            return XCTFail("expected unavailable, got \(result)")
        }
        XCTAssertEqual(code, .noActionableDelta)
        XCTAssertTrue(
            message.contains("tone-curve"),
            "expected the tone-curve omission in the message, got: \(message)"
        )
    }

    // MARK: - Production Core Image path (structure only, never pixel values)

    func testProductionDescriptorReturnsValueOnlyReference() {
        let descriptor = CIAutoAdjustmentDescriptor()
        let samples = gradient()
        guard let render = descriptor.reference(for: samples) else {
            return XCTFail("the production descriptor returned nil for a valid gradient")
        }
        // Every mapped effect is one of the known vocabulary names — the mapping is total, so
        // future OS filter additions degrade to reported omissions rather than crashes.
        let known: Set<String> = [
            "CIVibrance", "CIToneCurve", "CIHighlightShadowAdjust",
        ]
        for name in render.intent.filterNames {
            XCTAssertTrue(
                known.contains(name) || !name.isEmpty,
                "unexpected empty filter name in \(render.intent.filterNames)"
            )
        }
        if let reference = render.samples {
            XCTAssertFalse(reference.isEmpty)
            XCTAssertEqual(reference.space, .sRGB)
        }
    }

    func testProductionDescriptorRejectsEmptySamples() {
        let descriptor = CIAutoAdjustmentDescriptor()
        let empty = RenderedPixelSamples(width: 0, height: 0, bytes: [], space: .sRGB)
        XCTAssertNil(descriptor.reference(for: empty))
    }

    func testAdapterWithProductionDescriptorStaysGraceful() async {
        let engine = FakeRenderEngine()
        await engine.setSampledStub(gradient())
        let adapter = AppleEnhancementReferenceAdapter(
            engine: engine, descriptor: CIAutoAdjustmentDescriptor()
        )
        let result = await adapter.referenceProposal(
            source: standardSource(), document: EditDocument(), sourceKind: .standard
        )
        // Apple either informs a bounded proposal or gracefully declines — it never fails.
        switch result {
        case .proposed(let proposal):
            XCTAssertLessThanOrEqual(proposal.confidence, 0.75)
            XCTAssertGreaterThanOrEqual(proposal.residualError, 0)
            XCTAssertLessThanOrEqual(proposal.residualError, 1)
            XCTAssertFalse(proposal.provenance.filterNames.isEmpty)
        case .unavailable(let code, _):
            XCTAssertTrue(
                code == .noActionableDelta || code == .noEnhancementSuggested,
                "unexpected failure code: \(code)"
            )
        }
    }
}

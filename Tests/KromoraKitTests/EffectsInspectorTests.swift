import XCTest
@testable import KromoraKit

@MainActor
final class EffectsInspectorTests: TempDirectoryTestCase {

    private func waitUntil(
        _ description: String,
        timeout: TimeInterval = 5,
        _ condition: @MainActor () async -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while await !condition() {
            if Date() > deadline { return XCTFail("timed out waiting for \(description)") }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    private func openStandardImage(_ viewModel: AppViewModel) async throws {
        let url = try Fixtures.writeGradientPNG(width: 32, height: 24, named: "effects.png", in: tempDirectory)
        viewModel.openImage(url: url)
        try await waitUntil("the image to load") { viewModel.sourceImage != nil }
    }

    func testEveryControlMapsItsOwnValueAndKeepsSiblingValues() {
        var effects = EffectsAdjustments(
            texture: 12, clarity: -20, dehaze: 34,
            vignette: VignetteAdjustments(amount: 50, midpoint: 42),
            grain: GrainAdjustments(amount: 30, size: 22)
        )

        for control in EffectsControl.allCases {
            let value: Double = control == .texture ? 71 : control == .clarity ? -63 : 48
            effects = control.setting(value, in: effects)
            XCTAssertEqual(control.value(in: effects), value)
        }
        for control in VignetteControl.allCases {
            effects.vignette = control.setting(control.neutral, in: effects.vignette)
            XCTAssertEqual(control.value(in: effects.vignette), control.neutral)
        }
        for control in GrainControl.allCases {
            effects.grain = control.setting(control.neutral, in: effects.grain)
            XCTAssertEqual(control.value(in: effects.grain), control.neutral)
        }

        XCTAssertEqual(effects.texture, 71)
        XCTAssertEqual(effects.clarity, -63)
        XCTAssertEqual(effects.dehaze, 48)
    }

    func testEffectsValuesRoundToWholeNumbersAtTheValueBoundary() throws {
        let effects = EffectsAdjustments(
            texture: 37.4,
            clarity: -37.5,
            dehaze: 99.6,
            vignette: VignetteAdjustments(
                amount: -12.4,
                midpoint: 42.5,
                roundness: 18.6,
                feather: 67.4,
                highlights: 8.5
            ),
            grain: GrainAdjustments(amount: 21.4, size: 54.5, roughness: 88.6)
        )

        XCTAssertEqual(effects.texture, 37)
        XCTAssertEqual(effects.clarity, -38)
        XCTAssertEqual(effects.dehaze, 100)
        XCTAssertEqual(effects.vignette, VignetteAdjustments(
            amount: -12, midpoint: 43, roundness: 19, feather: 67, highlights: 9
        ))
        XCTAssertEqual(effects.grain, GrainAdjustments(amount: 21, size: 55, roughness: 89))

        let data = Data(#"""
        {
            "texture": 12.4,
            "clarity": -18.6,
            "dehaze": 31.5,
            "vignette": {"amount": 10.4, "midpoint": 49.6, "roundness": -7.5, "feather": 62.4, "highlights": 3.5},
            "grain": {"amount": 20.4, "size": 44.6, "roughness": 75.5}
        }
        """#.utf8)
        let decoded = try JSONDecoder().decode(EffectsAdjustments.self, from: data)

        XCTAssertEqual(decoded.texture, 12)
        XCTAssertEqual(decoded.clarity, -19)
        XCTAssertEqual(decoded.dehaze, 32)
        XCTAssertEqual(decoded.vignette, VignetteAdjustments(
            amount: 10, midpoint: 50, roundness: -8, feather: 62, highlights: 4
        ))
        XCTAssertEqual(decoded.grain, GrainAdjustments(amount: 20, size: 45, roughness: 76))
    }

    func testBindingsRoundTripAndIndividualResetsPreserveOtherEffects() async throws {
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())
        try await openStandardImage(viewModel)

        viewModel.effectsBinding(for: .texture).wrappedValue = 72.5
        viewModel.effectsBinding(for: .clarity).wrappedValue = -18.4
        viewModel.vignetteBinding(for: .amount).wrappedValue = 65
        viewModel.vignetteBinding(for: .midpoint).wrappedValue = 40.6
        viewModel.grainBinding(for: .amount).wrappedValue = 55
        viewModel.grainBinding(for: .size).wrappedValue = 24.4

        XCTAssertEqual(viewModel.effectsValue(for: .texture), 73, accuracy: 1e-12)
        XCTAssertEqual(viewModel.effectsValue(for: .clarity), -18, accuracy: 1e-12)
        XCTAssertEqual(viewModel.vignetteValue(for: .amount), 65, accuracy: 1e-12)
        XCTAssertEqual(viewModel.vignetteValue(for: .midpoint), 41, accuracy: 1e-12)
        XCTAssertEqual(viewModel.grainValue(for: .size), 24, accuracy: 1e-12)
        XCTAssertTrue(viewModel.hasEffects)

        viewModel.resetVignette(.amount)
        viewModel.resetGrain(.amount)
        viewModel.resetEffects(.texture)

        XCTAssertEqual(viewModel.effectsValue(for: .texture), 0)
        XCTAssertEqual(viewModel.effectsValue(for: .clarity), -18)
        XCTAssertEqual(viewModel.vignetteValue(for: .amount), 0)
        XCTAssertEqual(viewModel.vignetteValue(for: .midpoint), 40)
        XCTAssertEqual(viewModel.grainValue(for: .amount), 0)
        XCTAssertEqual(viewModel.grainValue(for: .size), 24)
        XCTAssertTrue(viewModel.hasEffects)
    }

    func testRetainedSubordinateValuesKeepEffectsResettableAtZeroAmount() async throws {
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())
        try await openStandardImage(viewModel)

        viewModel.vignetteBinding(for: .midpoint).wrappedValue = 30
        viewModel.grainBinding(for: .size).wrappedValue = 20

        XCTAssertTrue(viewModel.document.effects.isIdentity,
                      "the render remains identity while both amount gates are off")
        XCTAssertTrue(viewModel.hasEffects,
                      "the retained recipe still needs a reset affordance")
        XCTAssertTrue(viewModel.hasVignetteAdjustments)
        XCTAssertTrue(viewModel.hasGrainAdjustments)

        viewModel.resetAllVignette()
        viewModel.resetAllGrain()
        XCTAssertFalse(viewModel.hasEffects)
        XCTAssertEqual(viewModel.document.effects, .neutral)
    }

    func testResetAllEffectsIsIsolatedFromOtherPanels() async throws {
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())
        try await openStandardImage(viewModel)

        viewModel.effectsBinding(for: .dehaze).wrappedValue = 60
        viewModel.lightBinding(for: .exposure).wrappedValue = 1
        viewModel.resetAllEffects()

        XCTAssertTrue(viewModel.document.effects.isIdentity)
        XCTAssertEqual(viewModel.document.light.exposure, 1)
    }

    func testSliderGestureUsesInteractiveRenderingAndOneUndoEntry() async throws {
        let fake = FakeRenderEngine()
        let viewModel = makeAppViewModel(engine: fake)
        try await openStandardImage(viewModel)
        try await waitUntil("the opening render") { await !fake.previewRequests.isEmpty }
        let atRest = await fake.previewRequests.count

        viewModel.beginPreviewInteraction()
        for value in stride(from: 0.0, through: 70.0, by: 5.0) {
            viewModel.effectsBinding(for: .clarity).wrappedValue = value
        }
        viewModel.endPreviewInteraction()

        try await waitUntil("the settled Effects render") {
            await fake.previewRequests.contains { $0.document.effects.clarity == 70 }
        }
        let issued = await fake.previewRequests.count - atRest
        XCTAssertLessThan(issued, 10, "interactive Effects edits should be coalesced")

        viewModel.undo()
        XCTAssertEqual(viewModel.effectsValue(for: .clarity), 0,
                       "one completed gesture should undo as one edit")
        XCTAssertTrue(viewModel.canRedo)
        viewModel.redo()
        XCTAssertEqual(viewModel.effectsValue(for: .clarity), 70)
    }

    func testEffectsDocumentRoundTripsAsCopyableValue() throws {
        let document = EditDocument(effects: EffectsAdjustments(
            texture: 30, clarity: -12, dehaze: 55,
            vignette: VignetteAdjustments(amount: 70, midpoint: 35, roundness: -20, feather: 80, highlights: 45),
            grain: GrainAdjustments(amount: 65, size: 25, roughness: 85)
        ))
        let data = try JSONEncoder().encode(document)
        let copy = try JSONDecoder().decode(EditDocument.self, from: data)
        XCTAssertEqual(copy, document)
        XCTAssertNotEqual(copy.editHash, EditDocument().editHash)
    }
}

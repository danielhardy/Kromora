import XCTest

@testable import KromoraKit

final class LocalAdjustmentControlTests: XCTestCase {
    func testAllSupportedLocalControlsUseTheirGlobalStageContract() {
        XCTAssertEqual(LocalAdjustmentControl.allCases.count, 13)
        XCTAssertEqual(LocalAdjustmentControl.exposure.range, LightControl.exposure.range)
        XCTAssertEqual(LocalAdjustmentControl.contrast.range, LightControl.contrast.range)
        XCTAssertEqual(LocalAdjustmentControl.highlights.range, LightControl.highlights.range)
        XCTAssertEqual(LocalAdjustmentControl.shadows.range, LightControl.shadows.range)
        XCTAssertEqual(LocalAdjustmentControl.whites.range, LightControl.whites.range)
        XCTAssertEqual(LocalAdjustmentControl.blacks.range, LightControl.blacks.range)
        XCTAssertEqual(
            LocalAdjustmentControl.temperature.range, AdjustmentControl.temperature.range)
        XCTAssertEqual(LocalAdjustmentControl.tint.range, AdjustmentControl.tint.range)
        XCTAssertEqual(LocalAdjustmentControl.saturation.range, ColorGlobalControl.saturation.range)
        XCTAssertEqual(LocalAdjustmentControl.vibrance.range, ColorGlobalControl.vibrance.range)
        XCTAssertEqual(LocalAdjustmentControl.texture.range, EffectsControl.texture.range)
        XCTAssertEqual(LocalAdjustmentControl.clarity.range, EffectsControl.clarity.range)
        XCTAssertEqual(LocalAdjustmentControl.dehaze.range, EffectsControl.dehaze.range)

        for control in LocalAdjustmentControl.allCases {
            XCTAssertTrue(control.range.contains(control.neutral), "\(control) neutral drifted")
        }
    }

    func testEveryLocalControlRoundTripsItsExactValueAndPreservesSiblings() throws {
        var adjustments = LocalAdjustments.neutral
        let values: [LocalAdjustmentControl: Double] = [
            .exposure: 1.234567,
            .contrast: -42.25,
            .highlights: 17.75,
            .shadows: -63.5,
            .whites: 28.125,
            .blacks: -11.875,
            .temperature: 9000.125,
            .tint: -37.5,
            .saturation: 72.5,
            .vibrance: -18.25,
            .texture: 44.75,
            .clarity: -23.125,
            .dehaze: 9.875,
        ]

        for control in LocalAdjustmentControl.allCases {
            let expected = try XCTUnwrap(values[control])
            control.setting(expected, in: &adjustments)
            XCTAssertEqual(control.value(in: adjustments), expected, accuracy: 1e-12)
        }

        let reopened = try JSONDecoder().decode(
            LocalAdjustments.self,
            from: JSONEncoder().encode(adjustments)
        )
        XCTAssertEqual(reopened, adjustments)
    }

    func testLocalReadoutsKeepUnitsPrecisionAndSignConvention() {
        XCTAssertEqual(LocalAdjustmentControl.exposure.readout(1.234), "+1.23 EV")
        XCTAssertEqual(LocalAdjustmentControl.temperature.readout(6500.4), "6500 K")
        XCTAssertEqual(LocalAdjustmentControl.contrast.readout(-12.5), "-12")
        XCTAssertEqual(LocalAdjustmentControl.saturation.readout(12), "+12")
    }
}

@MainActor
final class LocalAdjustmentBindingTests: TempDirectoryTestCase {
    func testBindingIsLayerScopedUndoableAndDoesNotTouchGlobalAdjustments() throws {
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())
        viewModel.updateDocument {
            $0.light = LightAdjustments(exposure: 0.75)
            $0.color = ColorAdjustments(vibrance: 18)
            $0.effects = EffectsAdjustments(texture: -12)
            $0.adjustments = [.exposure(ev: 0.25)]
        }
        let globalBefore = viewModel.document
        viewModel.createMask(.brush)
        viewModel.createMask(.brush)
        let firstID = try XCTUnwrap(viewModel.document.localAdjustments.first?.id)
        let secondID = try XCTUnwrap(viewModel.document.localAdjustments.last?.id)
        viewModel.updateMask(firstID) {
            $0.amount = 0.61
            $0.isInverted = true
        }
        let firstBefore = try XCTUnwrap(viewModel.document.localAdjustments.first)

        viewModel.beginPreviewInteraction()
        viewModel.localAdjustmentBinding(.exposure, in: firstID).wrappedValue = 1.234567
        viewModel.localAdjustmentBinding(.exposure, in: firstID).wrappedValue = 2.345678
        viewModel.endPreviewInteraction()

        XCTAssertEqual(
            viewModel.localAdjustmentValue(.exposure, in: firstID), 2.345678, accuracy: 1e-12)
        XCTAssertEqual(viewModel.localAdjustmentValue(.exposure, in: secondID), 0, accuracy: 1e-12)
        XCTAssertEqual(viewModel.document.light, globalBefore.light)
        XCTAssertEqual(viewModel.document.color, globalBefore.color)
        XCTAssertEqual(viewModel.document.effects, globalBefore.effects)
        XCTAssertEqual(viewModel.document.adjustments, globalBefore.adjustments)
        var expectedFirst = firstBefore
        expectedFirst.adjustments.exposure = 2.345678
        XCTAssertEqual(viewModel.document.localAdjustments.first, expectedFirst)
        XCTAssertEqual(viewModel.document.localAdjustments.last?.adjustments, .neutral)

        viewModel.undo()
        XCTAssertEqual(viewModel.localAdjustmentValue(.exposure, in: firstID), 0, accuracy: 1e-12)
        viewModel.redo()
        XCTAssertEqual(
            viewModel.localAdjustmentValue(.exposure, in: firstID), 2.345678, accuracy: 1e-12)

        viewModel.resetMaskAdjustment(.exposure, in: firstID)
        XCTAssertEqual(viewModel.localAdjustmentValue(.exposure, in: firstID), 0, accuracy: 1e-12)
        XCTAssertEqual(viewModel.localAdjustmentValue(.exposure, in: secondID), 0, accuracy: 1e-12)
        XCTAssertEqual(viewModel.document.light, globalBefore.light)
        XCTAssertEqual(viewModel.document.color, globalBefore.color)
        XCTAssertEqual(viewModel.document.effects, globalBefore.effects)
        XCTAssertEqual(viewModel.document.adjustments, globalBefore.adjustments)
        XCTAssertEqual(viewModel.document.localAdjustments.first?.amount, firstBefore.amount)
        XCTAssertEqual(
            viewModel.document.localAdjustments.first?.isInverted, firstBefore.isInverted)
    }
}

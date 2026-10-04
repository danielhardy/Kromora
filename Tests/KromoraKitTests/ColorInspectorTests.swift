import AppKit
import SwiftUI
import XCTest
@testable import KromoraKit

@MainActor
final class ColorInspectorTests: TempDirectoryTestCase {

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
        let url = try Fixtures.writeGradientPNG(width: 32, height: 24, named: "color.png", in: tempDirectory)
        viewModel.openImage(url: url)
        try await waitUntil("the image to load") { viewModel.sourceImage != nil }
    }

    func testColorControlsRoundTripThroughBindingsWithoutDrift() async throws {
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())
        try await openStandardImage(viewModel)

        viewModel.colorBinding(for: .vibrance).wrappedValue = 37.5
        viewModel.colorBinding(for: .saturation).wrappedValue = -42.25

        XCTAssertEqual(viewModel.colorValue(for: .vibrance), 37.5, accuracy: 1e-12)
        XCTAssertEqual(viewModel.colorValue(for: .saturation), -42.25, accuracy: 1e-12)
        XCTAssertEqual(viewModel.document.color.vibrance, 37.5, accuracy: 1e-12)
        XCTAssertEqual(viewModel.document.color.saturation, -42.25, accuracy: 1e-12)
    }

    func testWhiteBalancePresetsUseTheEditableDocumentAndUndoHistory() async throws {
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())
        try await openStandardImage(viewModel)
        viewModel.whiteBalanceBinding(for: .tint).wrappedValue = 24

        viewModel.applyWhiteBalancePreset(.tungsten)

        XCTAssertEqual(viewModel.adjustmentValue(for: .temperature), 3200, accuracy: 0.001)
        XCTAssertEqual(viewModel.adjustmentValue(for: .tint), 0, accuracy: 0.001)
        viewModel.undo()
        XCTAssertEqual(viewModel.adjustmentValue(for: .tint), 24, accuracy: 0.001)
        XCTAssertEqual(viewModel.adjustmentValue(for: .temperature), 6500, accuracy: 0.001)

        viewModel.applyWhiteBalancePreset(.asShot)
        XCTAssertEqual(viewModel.adjustmentValue(for: .temperature), 6500, accuracy: 0.001)
        XCTAssertEqual(viewModel.adjustmentValue(for: .tint), 0, accuracy: 0.001)
    }

    func testMixerAndGradingBindingsEditOnlyTheirNestedValues() async throws {
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())
        try await openStandardImage(viewModel)

        viewModel.mixerBinding(for: .blue, control: .hue).wrappedValue = -18
        viewModel.mixerBinding(for: .blue, control: .luminance).wrappedValue = 23
        viewModel.gradingBinding(for: .shadows, control: .hue).wrappedValue = 220
        viewModel.gradingBinding(for: .shadows, control: .saturation).wrappedValue = 40
        viewModel.gradingGlobalBinding(for: .balance).wrappedValue = -15

        XCTAssertEqual(viewModel.mixerChannelValue(.blue), ColorMixerChannel(hue: -18, luminance: 23))
        XCTAssertEqual(viewModel.mixerChannelValue(.red), .neutral)
        XCTAssertEqual(viewModel.gradingWheelValue(.shadows), ColorGradingWheel(hue: 220, saturation: 40))
        XCTAssertEqual(viewModel.gradingWheelValue(.highlights), .neutral)
        XCTAssertEqual(viewModel.gradingGlobalValue(for: .balance), -15, accuracy: 1e-12)
    }

    func testSectionResetsPreserveOtherColorSections() async throws {
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())
        try await openStandardImage(viewModel)

        viewModel.colorBinding(for: .vibrance).wrappedValue = 25
        viewModel.mixerBinding(for: .green, control: .saturation).wrappedValue = 45
        viewModel.gradingBinding(for: .highlights, control: .saturation).wrappedValue = 35
        viewModel.adjustmentBinding(for: .temperature).wrappedValue = 9000
        viewModel.adjustmentBinding(for: .tint).wrappedValue = 18

        viewModel.resetAllMixer()
        viewModel.resetAllGrading()
        viewModel.resetAllColor()

        XCTAssertTrue(viewModel.document.color.isIdentity)
        XCTAssertEqual(viewModel.adjustmentValue(for: .temperature), 9000, accuracy: 1e-12)
        XCTAssertEqual(viewModel.adjustmentValue(for: .tint), 18, accuracy: 1e-12)
        XCTAssertFalse(viewModel.document.adjustments.isEmpty)
    }

    func testColorResetsPreserveLegacyAdjustmentNodes() async throws {
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())
        try await openStandardImage(viewModel)
        let legacyNodes: [AdjustmentNode] = [
            .exposure(ev: 0.8),
            .colorControls(brightness: 0.1, contrast: 1.35, saturation: 0.75),
            .highlightShadow(highlights: 0.65, shadows: 0.3),
            .temperatureTint(temp: 7200, tint: 14),
            .vibrance(amount: 0.25),
        ]

        viewModel.updateDocument {
            $0.adjustments = legacyNodes
            $0.color.vibrance = 35
            $0.color.saturation = -20
        }

        viewModel.resetAllMixer()
        viewModel.resetAllGrading()
        viewModel.resetAllColor()

        XCTAssertEqual(
            viewModel.document.adjustments,
            legacyNodes,
            "resetting supported Color state must not discard hidden legacy adjustment nodes"
        )
    }

    func testRowResetsPreserveSiblingMixerAndGradingValues() async throws {
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())
        try await openStandardImage(viewModel)

        viewModel.mixerBinding(for: .red, control: .hue).wrappedValue = 20
        viewModel.mixerBinding(for: .red, control: .saturation).wrappedValue = 45
        viewModel.gradingBinding(for: .midtones, control: .hue).wrappedValue = 120
        viewModel.gradingBinding(for: .midtones, control: .saturation).wrappedValue = 30

        viewModel.resetMixer(.red, .hue)
        viewModel.resetGrading(.midtones, .saturation)

        XCTAssertEqual(viewModel.mixerChannelValue(.red), ColorMixerChannel(saturation: 45))
        XCTAssertEqual(viewModel.gradingWheelValue(.midtones), ColorGradingWheel(hue: 120))
    }

    func testVisualWheelBindingMapsGestureValuesAndUsesInteractivePreview() async throws {
        let fake = FakeRenderEngine()
        let viewModel = makeAppViewModel(engine: fake)
        try await openStandardImage(viewModel)
        try await waitUntil("the opening render") { await !fake.previewRequests.isEmpty }

        viewModel.beginPreviewInteraction()
        let wheel = ColorGradingWheelMapping.wheel(at: .init(x: 0, y: 0.6))
        viewModel.gradingWheelBinding(for: .midtones).wrappedValue = wheel
        viewModel.endPreviewInteraction()

        try await waitUntil("the wheel preview") {
            await fake.previewRequests.contains {
                $0.document.color.grading.midtones == ColorGradingWheel(hue: 90, saturation: 60)
            }
        }
        XCTAssertEqual(viewModel.gradingWheelValue(.midtones), wheel)
        viewModel.resetGrading(.midtones)
        XCTAssertEqual(viewModel.gradingWheelValue(.midtones), .neutral)
    }

    func testRenderedGradingWheelDiscMatchesStoredHueDirections() throws {
        let side = 256
        let hostingView = NSHostingView(
            rootView: ColorGradingWheelDisc()
                .frame(width: CGFloat(side), height: CGFloat(side))
        )
        hostingView.frame = CGRect(x: 0, y: 0, width: side, height: side)
        hostingView.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(
            hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds))
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)

        let samples: [(hue: Double, expected: String)] = [
            (0, "red"),
            (120, "green"),
            (180, "cyan"),
            (240, "blue"),
        ]

        for sample in samples {
            let radians = sample.hue * .pi / 180
            let point = ColorGradingWheelPoint(x: cos(radians), y: sin(radians))
            let radius = Double(side) * 0.42
            let x = Int((Double(side) / 2 + point.x * radius).rounded())
            let topOriginY = Int((Double(side) / 2 - point.y * radius).rounded())
            let color = try XCTUnwrap(bitmap.colorAt(x: x, y: topOriginY))
                .usingColorSpace(.deviceRGB)
            let red = try XCTUnwrap(color?.redComponent)
            let green = try XCTUnwrap(color?.greenComponent)
            let blue = try XCTUnwrap(color?.blueComponent)

            switch sample.expected {
            case "red":
                XCTAssertGreaterThan(red, green + 0.35)
                XCTAssertGreaterThan(red, blue + 0.35)
            case "green":
                XCTAssertGreaterThan(green, red + 0.35)
                XCTAssertGreaterThan(green, blue + 0.35)
            case "blue":
                XCTAssertGreaterThan(blue, red + 0.35)
                XCTAssertGreaterThan(blue, green + 0.35)
            default:
                XCTAssertLessThan(red, 0.2)
                XCTAssertGreaterThan(green, 0.8)
                XCTAssertGreaterThan(blue, 0.8)
            }
        }

        let greenHandle = ColorGradingWheelMapping.point(
            for: ColorGradingWheel(hue: 120, saturation: 100)
        )
        let greenSample = ColorGradingWheelPoint(
            x: cos(120 * .pi / 180),
            y: sin(120 * .pi / 180)
        )
        XCTAssertEqual(greenHandle.x, greenSample.x, accuracy: 1e-12)
        XCTAssertEqual(greenHandle.y, greenSample.y, accuracy: 1e-12)
    }

    func testColorSliderUsesInteractiveRenderAndSettlesLatestValue() async throws {
        let fake = FakeRenderEngine()
        let viewModel = makeAppViewModel(engine: fake)
        try await openStandardImage(viewModel)
        try await waitUntil("the opening render") { await !fake.previewRequests.isEmpty }
        let atRest = await fake.previewRequests.count

        viewModel.beginPreviewInteraction()
        for value in stride(from: 0.0, through: 50.0, by: 5.0) {
            viewModel.colorBinding(for: .vibrance).wrappedValue = value
        }
        viewModel.endPreviewInteraction()

        try await waitUntil("the settled color render") {
            await fake.previewRequests.contains { $0.document.color.vibrance == 50 }
        }
        let issued = await fake.previewRequests.count - atRest
        XCTAssertLessThan(issued, 8, "interactive color edits should be coalesced")
    }

    func testWhiteBalanceResetRestoresBothRowsAsOneNeutralOperation() async throws {
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())
        try await openStandardImage(viewModel)

        viewModel.adjustmentBinding(for: .temperature).wrappedValue = 9000
        viewModel.adjustmentBinding(for: .tint).wrappedValue = 22
        XCTAssertTrue(viewModel.hasWhiteBalanceAdjustments)

        viewModel.resetWhiteBalance()

        XCTAssertFalse(viewModel.hasWhiteBalanceAdjustments)
        XCTAssertEqual(viewModel.adjustmentValue(for: .temperature), AdjustmentControl.temperature.neutral)
        XCTAssertEqual(viewModel.adjustmentValue(for: .tint), AdjustmentControl.tint.neutral)
    }
}

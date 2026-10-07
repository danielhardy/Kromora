import AppKit
import SwiftUI
import XCTest
@testable import KromoraKit

@MainActor
final class LightInspectorTests: TempDirectoryTestCase {
    func testLightControlsExposePhotographerRangesInPanelOrder() {
        XCTAssertEqual(LightControl.allCases, [.exposure, .contrast, .highlights, .shadows, .whites, .blacks])
        XCTAssertEqual(LightControl.exposure.range, -5...5)
        XCTAssertEqual(LightControl.contrast.range, -100...100)
        XCTAssertEqual(LightControl.highlights.range, -100...100)
        XCTAssertEqual(LightControl.shadows.range, -100...100)
        XCTAssertEqual(LightControl.whites.range, -100...100)
        XCTAssertEqual(LightControl.blacks.range, -100...100)
        XCTAssertEqual(LightControl.allCases.map(\.title), [
            "Exposure", "Contrast", "Highlights", "Shadows", "Whites", "Blacks"
        ])
    }

    func testLightBindingRoundTripsAndDoesNotTouchOtherDocumentSections() {
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())
        viewModel.updateDocument {
            $0.rawDevelop.exposure = 0.25
            $0.adjustments = [.exposure(ev: 0.5)]
            $0.lut.intensity = 0.4
        }

        viewModel.lightBinding(for: .highlights).wrappedValue = 42

        XCTAssertEqual(viewModel.lightValue(for: .highlights), 42)
        XCTAssertEqual(viewModel.document.rawDevelop.exposure, 0.25)
        XCTAssertEqual(viewModel.document.adjustments, [.exposure(ev: 0.5)])
        XCTAssertEqual(viewModel.document.lut.intensity, 0.4)
    }

    func testIndividualAndPanelResetsAreScopedAndUndoable() {
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())
        viewModel.updateDocument {
            $0.light.exposure = 1
            $0.light.whites = 20
            $0.adjustments = [.exposure(ev: 0.5)]
        }

        viewModel.resetLight(.exposure)
        XCTAssertEqual(viewModel.document.light.exposure, 0)
        XCTAssertEqual(viewModel.document.light.whites, 20)
        XCTAssertEqual(viewModel.document.adjustments, [.exposure(ev: 0.5)])
        viewModel.undo()
        XCTAssertEqual(viewModel.document.light.exposure, 1)
        XCTAssertEqual(viewModel.document.light.whites, 20)

        viewModel.resetAllLight()
        XCTAssertTrue(viewModel.document.light.isIdentity)
        XCTAssertEqual(viewModel.document.adjustments, [.exposure(ev: 0.5)])
        viewModel.undo()
        XCTAssertEqual(viewModel.document.light.exposure, 1)
        XCTAssertEqual(viewModel.document.light.whites, 20)
    }

    func testToneCurveResetClearsOnlySelectedChannelAndIsUndoable() {
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())
        let masterCurve = LightToneCurve(points: [
            LightCurvePoint(input: 0.25, output: 0.3),
            LightCurvePoint(input: 0.75, output: 0.7),
        ])
        let redCurve = LightToneCurve(points: [
            LightCurvePoint(input: 0.25, output: 0.35),
            LightCurvePoint(input: 0.75, output: 0.8),
        ])
        let blueCurve = LightToneCurve(points: [
            LightCurvePoint(input: 0.25, output: 0.2),
            LightCurvePoint(input: 0.75, output: 0.65),
        ])
        viewModel.updateDocument {
            $0.light.setToneCurve(masterCurve, for: .master)
            $0.light.setToneCurve(redCurve, for: .red)
            $0.light.setToneCurve(blueCurve, for: .blue)
        }

        viewModel.resetToneCurve(.red)

        XCTAssertEqual(viewModel.document.light.toneCurve(for: .master), masterCurve)
        XCTAssertTrue(viewModel.document.light.toneCurve(for: .red).isIdentity)
        XCTAssertEqual(viewModel.document.light.toneCurve(for: .blue), blueCurve)
        viewModel.undo()
        XCTAssertEqual(viewModel.document.light.toneCurve(for: .master), masterCurve)
        XCTAssertEqual(viewModel.document.light.toneCurve(for: .red), redCurve)
        XCTAssertEqual(viewModel.document.light.toneCurve(for: .blue), blueCurve)
    }

    func testToneCurveEditingRoutesEveryOperationToSelectedChannel() throws {
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())
        let masterCurve = LightToneCurve(points: [
            LightCurvePoint(input: 0.3, output: 0.4),
        ])
        let redCurve = LightToneCurve(points: [
            LightCurvePoint(input: 0.3, output: 0.25),
        ])
        let blueCurve = LightToneCurve(points: [
            LightCurvePoint(input: 0.7, output: 0.8),
        ])
        let greenCurve = LightToneCurve(points: [
            LightCurvePoint(input: 0.25, output: 0.25),
            LightCurvePoint(input: 0.75, output: 0.75),
        ])
        viewModel.updateDocument {
            $0.light.setToneCurve(masterCurve, for: .master)
            $0.light.setToneCurve(redCurve, for: .red)
            $0.light.setToneCurve(greenCurve, for: .green)
            $0.light.setToneCurve(blueCurve, for: .blue)
        }

        viewModel.addToneCurvePoint(input: 0.5, output: 0.55, channel: .green)
        let addedPoint = try XCTUnwrap(
            viewModel.document.light.toneCurve(for: .green).points.first { $0.input == 0.5 }
        )
        XCTAssertEqual(addedPoint.output, 0.55, accuracy: 0.000_001)

        viewModel.setToneCurvePoint(addedPoint, input: 0.52, output: 0.58, channel: .green)
        let movedPoint = try XCTUnwrap(
            viewModel.document.light.toneCurve(for: .green).points.first { $0.input == 0.52 }
        )
        XCTAssertEqual(movedPoint.output, 0.58, accuracy: 0.000_001)

        let actualInput = viewModel.moveToneCurvePoint(
            fromInput: 0.52, input: 0.6, output: 0.62, channel: .green
        )
        XCTAssertEqual(actualInput ?? -1, 0.6, accuracy: 0.000_001)
        viewModel.removeToneCurvePoint(atInput: 0.25, channel: .green)

        let editedGreenCurve = viewModel.document.light.toneCurve(for: .green)
        XCTAssertEqual(editedGreenCurve.points.dropFirst().dropLast().count, 2)
        XCTAssertEqual(editedGreenCurve.points[1].input, 0.6, accuracy: 0.000_001)
        XCTAssertEqual(editedGreenCurve.points[1].output, 0.62, accuracy: 0.000_001)
        XCTAssertEqual(editedGreenCurve.points[2], LightCurvePoint(input: 0.75, output: 0.75))
        XCTAssertEqual(viewModel.document.light.toneCurve(for: .master), masterCurve)
        XCTAssertEqual(viewModel.document.light.toneCurve(for: .red), redCurve)
        XCTAssertEqual(viewModel.document.light.toneCurve(for: .blue), blueCurve)
    }

    func testToneCurveResetUsesAccessibleTrailingDisclosureAction() throws {
        let source = try lightInspectorSource()
        let toneCurveStart = try XCTUnwrap(
            source.range(of: "InspectorDisclosure(\n                    \"Tone Curve\"")
        )
        let advancedCurveStart = try XCTUnwrap(
            source.range(of: "InspectorDisclosure(\"Advanced Curve\"")
        )
        let toneCurveSection = source[toneCurveStart.lowerBound..<advancedCurveStart.lowerBound]

        XCTAssertTrue(toneCurveSection.contains("trailingActionTitle: \"Reset "))
        XCTAssertTrue(toneCurveSection.contains(
            "viewModel.resetToneCurve(selectedToneCurveChannel)"
        ))
        XCTAssertFalse(toneCurveSection.contains("Button(\"Reset\")"))

        let disclosureSource = try inspectorDisclosureSource()
        XCTAssertTrue(disclosureSource.contains("Image(systemName: \"arrow.counterclockwise\")"))
        XCTAssertTrue(disclosureSource.contains(".accessibilityLabel(trailingActionTitle)"))
    }

    func testAdvancedCurveControlsAreCollapsedUntilExpanded() throws {
        let source = try lightInspectorSource()
        XCTAssertTrue(source.contains("@State private var advancedCurveSectionExpanded = false"))
        XCTAssertTrue(source.contains(
            "InspectorDisclosure(\"Advanced Curve\", isExpanded: $advancedCurveSectionExpanded)"
        ))

        let curveEditor = try XCTUnwrap(source.range(of: "private struct ToneCurveEditor"))
        let parametricControls = try XCTUnwrap(source.range(of: "struct ParametricToneCurveControls"))
        let editorSource = source[curveEditor.lowerBound..<parametricControls.lowerBound]
        XCTAssertTrue(editorSource.contains("channelTabs"))
        XCTAssertFalse(editorSource.contains("Picker(\"Channel\""))
        XCTAssertTrue(editorSource.contains("curveGraph(size: size)"))
        XCTAssertFalse(editorSource.contains("Parametric regions"))
        XCTAssertFalse(editorSource.contains("Region splits"))

        let viewModel = makeAppViewModel(engine: FakeRenderEngine())
        var isExpanded = false
        let binding = Binding(get: { isExpanded }, set: { isExpanded = $0 })
        let hosting = NSHostingView(rootView: InspectorDisclosure("Advanced Curve", isExpanded: binding) {
            ParametricToneCurveControls(viewModel: viewModel)
        })
        let collapsedHeight = hosting.fittingSize.height

        isExpanded = true
        hosting.rootView = InspectorDisclosure("Advanced Curve", isExpanded: binding) {
            ParametricToneCurveControls(viewModel: viewModel)
        }
        let expandedHeight = hosting.fittingSize.height

        XCTAssertGreaterThan(expandedHeight, collapsedHeight)
        XCTAssertTrue(source.contains("[\"Highlights\", \"Lights\", \"Darks\", \"Shadows\"]"))
        XCTAssertTrue(source.contains(
            "[\"Shadow split\", \"Dark split\", \"Light split\", \"Highlight split\"]"
        ))
    }

    func testToneCurveGraphPinsItsVerticalSizeInsideTheScrollingInspector() throws {
        let source = try lightInspectorSource()
        let sizingComment = try XCTUnwrap(source.range(of: "// Keep the graph square and exactly"))
        let notificationHandler = try XCTUnwrap(
            source.range(
                of: ".onReceive(NotificationCenter.default.publisher",
                range: sizingComment.lowerBound..<source.endIndex
            )
        )
        let sizing = source[sizingComment.lowerBound..<notificationHandler.lowerBound]

        XCTAssertTrue(sizing.contains(".aspectRatio(1, contentMode: .fit)"))
        // KRMA-716: the map fills the tab width (equal gutters) instead of a leading-aligned cap.
        XCTAssertFalse(sizing.contains(".frame(maxWidth: 220"))
        XCTAssertTrue(sizing.contains(".frame(maxWidth: .infinity)"))
        XCTAssertTrue(sizing.contains(".fixedSize(horizontal: false, vertical: true)"))

        // The channel tabs are plain SwiftUI (no AppKit segmented control with its own intrinsic
        // width), so they always take exactly the width offered.
        XCTAssertFalse(source.contains(".pickerStyle(.segmented)"))
        XCTAssertTrue(source.contains("private var channelTabs: some View"))

        // Visual check: with Light > Tone Curve expanded, move between photos with the arrow keys,
        // then drag Exposure and Contrast through several values. The header, tabs, graph, and
        // section chrome should stay inside the inspector rail as the preview updates. The graph
        // should also keep the same size and y-position while the loading indicator appears/clears.
    }

    func testInspectorRetainsViewportWidthDuringUnspecifiedScrollMeasurements() throws {
        let source = try inspectorDisclosureSource()

        XCTAssertTrue(source.contains("var lastProposedWidth: CGFloat?"))
        XCTAssertTrue(source.contains("cache.lastProposedWidth = proposedWidth"))
        XCTAssertTrue(source.contains("} else if let lastProposedWidth = cache.lastProposedWidth {"))
        XCTAssertTrue(source.contains("width = child.sizeThatFits(.unspecified).width"))
        // Probe proposals (.infinity / 0) are never a viewport width, and placement uses the
        // granted bounds rather than a cached proposal a later probe may have overwritten.
        XCTAssertTrue(source.contains("proposedWidth.isFinite, proposedWidth > 0"))
        // Each disclosure section is clamped too, so an over-wide child cannot overflow the rail.
        XCTAssertTrue(source.contains("FitsProposedWidth(reportsProposedHeight: false)"))
        XCTAssertTrue(source.contains("ProposedViewSize(width: bounds.width, height: cache.proposal.height)"))
    }

    func testLightSliderGestureIsOneUndoOperation() {
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())
        viewModel.beginPreviewInteraction()
        for value in stride(from: 0.1, through: 0.8, by: 0.1) {
            viewModel.lightBinding(for: .exposure).wrappedValue = value
        }
        viewModel.endPreviewInteraction()

        XCTAssertEqual(viewModel.document.light.exposure, 0.8, accuracy: 0.000_001)
        viewModel.undo()
        XCTAssertEqual(viewModel.document.light.exposure, 0, accuracy: 0.000_001)
        XCTAssertFalse(viewModel.canUndo)
        viewModel.redo()
        XCTAssertEqual(viewModel.document.light.exposure, 0.8, accuracy: 0.000_001)
    }

    func testComparisonBaselineRemovesLightButKeepsDevelop() {
        let document = EditDocument(
            rawDevelop: RAWDevelopSettings(exposure: 0.5),
            light: LightAdjustments(exposure: 1),
            color: ColorAdjustments(vibrance: 25)
        )
        XCTAssertTrue(document.originalForComparison.light.isIdentity)
        XCTAssertTrue(document.originalForComparison.color.isIdentity)
        XCTAssertEqual(document.originalForComparison.rawDevelop.exposure, 0.5)
        XCTAssertTrue(document.originalForComparison.adjustments.isEmpty)
        XCTAssertTrue(document.originalForComparison.lut.isIdentity)
    }

    func testPhotoHandoffRestoresTheLightDocumentAndHistory() async throws {
        let first = try Fixtures.writeGradientPNG(width: 16, height: 12, named: "first.png", in: tempDirectory)
        let second = try Fixtures.writeGradientPNG(width: 16, height: 12, named: "second.png", in: tempDirectory)
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())

        viewModel.openImage(url: first)
        try await waitUntil { viewModel.sourceName == "first.png" }
        viewModel.updateDocument { $0.light.exposure = 1.25 }

        viewModel.openImage(url: second)
        try await waitUntil { viewModel.sourceName == "second.png" }
        XCTAssertTrue(viewModel.document.light.isIdentity)

        viewModel.openImage(url: first)
        try await waitUntil { viewModel.sourceName == "first.png" }
        XCTAssertEqual(viewModel.document.light.exposure, 1.25)
        viewModel.undo()
        XCTAssertTrue(viewModel.document.light.isIdentity)
    }

    func testAccessibilityAdjustableActionAddsTheFirstCurvePoint() {
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())
        XCTAssertTrue(viewModel.document.light.toneCurve.points.dropFirst().dropLast().isEmpty)

        let synthetic = LightCurvePoint(input: 0.5, output: viewModel.document.light.toneCurve.value(at: 0.5))
        viewModel.setToneCurvePoint(synthetic, output: synthetic.output + 0.01)

        let interior = viewModel.document.light.toneCurve.points.dropFirst().dropLast()
        XCTAssertEqual(interior.count, 1)
        XCTAssertEqual(interior.first?.output ?? -1, synthetic.output + 0.01, accuracy: 0.000_001)
    }

    func testCurveAddAndRemoveEachUseOneUndoStep() {
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())

        viewModel.addToneCurvePoint(input: 0.25)
        XCTAssertEqual(
            viewModel.document.light.toneCurve.value(at: 0.25), 0.25, accuracy: 0.000_001
        )

        viewModel.removeToneCurvePoint(atInput: 0.25)
        XCTAssertTrue(viewModel.document.light.toneCurve.isIdentity)

        viewModel.undo()
        XCTAssertEqual(viewModel.document.light.toneCurve.points.dropFirst().dropLast().count, 1)
        viewModel.undo()
        XCTAssertTrue(viewModel.document.light.toneCurve.isIdentity)
    }

    func testCurveDragCoalescesEveryTickIntoOneUndoStep() {
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())
        viewModel.beginPreviewInteraction()

        for output in [0.55, 0.60, 0.65, 0.70, 0.75, 0.80, 0.85] {
            viewModel.moveToneCurvePoint(fromInput: 0.5, input: 0.5, output: output)
        }
        viewModel.endPreviewInteraction()

        XCTAssertEqual(
            viewModel.document.light.toneCurve.value(at: 0.5), 0.85, accuracy: 0.000_001
        )
        viewModel.undo()
        XCTAssertTrue(viewModel.document.light.toneCurve.isIdentity,
                      "all curve drag ticks should undo as one gesture")
        XCTAssertFalse(viewModel.canUndo)
    }

    private func lightInspectorSource() throws -> String {
        try inspectorSource(named: "LightInspectorView.swift")
    }

    private func inspectorDisclosureSource() throws -> String {
        try inspectorSource(named: "InspectorDisclosure.swift")
    }

    private func inspectorSource(named fileName: String) throws -> String {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: packageRoot.appendingPathComponent("Sources/KromoraKit/Views/\(fileName)"),
            encoding: .utf8
        )
    }

    func testCurveDragKeepsMonotonicControlPointsOrderedAndBounded() {
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())
        viewModel.updateDocument {
            $0.light.toneCurve = LightToneCurve(points: [
                LightCurvePoint(input: 0.25, output: 0.25),
                LightCurvePoint(input: 0.5, output: 0.5),
                LightCurvePoint(input: 0.75, output: 0.75),
            ])
        }

        viewModel.beginPreviewInteraction()
        let actualInput = viewModel.moveToneCurvePoint(fromInput: 0.5, input: 0.99, output: 1)
        viewModel.endPreviewInteraction()

        XCTAssertNotNil(actualInput)
        XCTAssertEqual(actualInput ?? -1, 0.749, accuracy: 0.000_001)
        let points = viewModel.document.light.toneCurve.points
        XCTAssertTrue(zip(points, points.dropFirst()).allSatisfy { $0.input < $1.input })
        XCTAssertTrue(viewModel.document.light.toneCurve.isMonotonic)
        XCTAssertEqual(points[2].output, 0.75, accuracy: 0.000_001,
                       "a drag must not invert the tone curve past its upper neighbor")
    }

    func testCurveDragMovesBothEndpointsInBothDimensions() {
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())
        viewModel.beginPreviewInteraction()
        let leftInput = viewModel.moveToneCurvePoint(fromInput: 0, input: 0.12, output: 0.1)
        let rightInput = viewModel.moveToneCurvePoint(fromInput: 1, input: 0.88, output: 0.9)
        viewModel.endPreviewInteraction()

        let curve = viewModel.document.light.toneCurve
        XCTAssertEqual(leftInput ?? -1, 0.12, accuracy: 0.000_001)
        XCTAssertEqual(rightInput ?? -1, 0.88, accuracy: 0.000_001)
        XCTAssertEqual(curve.points.first?.output ?? -1, 0.1, accuracy: 0.000_001)
        XCTAssertEqual(curve.points.last?.output ?? -1, 0.9, accuracy: 0.000_001)
        XCTAssertTrue(zip(curve.points, curve.points.dropFirst()).allSatisfy { $0.input < $1.input })
        XCTAssertEqual(curve.value(at: 0), 0.1, accuracy: 0.000_001)
        XCTAssertEqual(curve.value(at: 1), 0.9, accuracy: 0.000_001)
        XCTAssertTrue((0...100).allSatisfy { curve.value(at: Double($0) / 100).isFinite })
    }

    func testCurveHitTestingUsesTheSameNormalizedToleranceForSelectionAndRemoval() {
        let curve = LightToneCurve(points: [
            LightCurvePoint(input: 0.4, output: 0.4),
            LightCurvePoint(input: 0.7, output: 0.7),
        ])

        XCTAssertEqual(curve.interiorPoint(nearInput: 0.425)?.input, 0.4)
        XCTAssertNil(curve.interiorPoint(nearInput: 0.431))
        XCTAssertEqual(curve.removingPoint(at: 0.425).points.dropFirst().dropLast().count, 1)
        XCTAssertEqual(curve.removingPoint(at: 0.431), curve)
    }

    func testNearestPointIncludesEndpointsSoAPressOnAHandleStartsADragNotAnAdd() {
        let curve = LightToneCurve(points: [
            LightCurvePoint(input: 0.4, output: 0.4),
            LightCurvePoint(input: 0.7, output: 0.7),
        ])

        // interiorPoint deliberately excludes endpoints (removal must never target them), but the
        // graph gesture's drag-start check needs endpoints to be recognized as existing handles.
        XCTAssertNil(curve.interiorPoint(nearInput: 0.01))
        XCTAssertEqual(curve.nearestPoint(toInput: 0.01)?.input, 0)
        XCTAssertEqual(curve.nearestPoint(toInput: 0.99)?.input, 1)
        XCTAssertEqual(curve.nearestPoint(toInput: 0.425)?.input, 0.4)
        XCTAssertNil(curve.nearestPoint(toInput: 0.2))
    }

    func testToneCurveHandleHitTestingUsesRenderedPositionsAtInspectorSizes() {
        let curve = LightToneCurve(points: [
            LightCurvePoint(input: 0.08, output: 0.18),
            LightCurvePoint(input: 0.12, output: 0.72),
            LightCurvePoint(input: 0.55, output: 0.5),
            LightCurvePoint(input: 0.88, output: 0.82),
            LightCurvePoint(input: 0.92, output: 0.25),
        ], preserveEndpointPositions: true)

        for edge in [CGFloat(120), 180, 260] {
            let size = CGSize(width: edge, height: edge)
            // A point 9 pt from the moved-in black handle remains within its 12 pt hit radius.
            // At the largest size, its input is outside the old 0.03 endpoint tolerance, while
            // its rendered position is still closest to the endpoint rather than its neighbor.
            let blackHandleCenter = CGPoint(x: 0.08 * edge, y: (1 - 0.18) * edge)
            let blackPress = CGPoint(x: blackHandleCenter.x + 9, y: blackHandleCenter.y)
            XCTAssertEqual(curve.nearestHandle(to: blackPress, in: size), curve.points.first)

            let whiteHandleCenter = CGPoint(x: 0.92 * edge, y: (1 - 0.25) * edge)
            let whitePress = CGPoint(x: whiteHandleCenter.x - 9, y: whiteHandleCenter.y)
            XCTAssertEqual(curve.nearestHandle(to: whitePress, in: size), curve.points.last)

            XCTAssertNil(curve.nearestHandle(to: CGPoint(x: 0, y: edge / 2), in: size))
        }
    }

    func testEndpointHandlesStayHitTestableAfterReturningToTheCorner() {
        let size = CGSize(width: 120, height: 120)
        let curve = LightToneCurve(points: [
            LightCurvePoint(input: 0, output: 0),
            LightCurvePoint(input: 0.02, output: 0.02),
            LightCurvePoint(input: 0.98, output: 0.98),
            LightCurvePoint(input: 1, output: 1),
        ], preserveEndpointPositions: true)

        XCTAssertEqual(curve.nearestHandle(to: CGPoint(x: 0, y: size.height), in: size), curve.points.first)
        XCTAssertEqual(curve.nearestHandle(to: CGPoint(x: size.width, y: 0), in: size), curve.points.last)
    }

    func testToneCurveEndHandlesDrawAboveInteriorHandles() throws {
        let source = try lightInspectorSource()
        XCTAssertTrue(source.contains(".zIndex(index == 0 || index == editablePoints.count - 1 ? 1 : 0)"))
    }

    func testVisibleEndpointsWinOverCloserInteriorHandles() {
        let size = CGSize(width: 102, height: 102)
        let curve = LightToneCurve(points: [
            LightCurvePoint(input: 0, output: 0),
            LightCurvePoint(input: 0.02, output: 0.02),
            LightCurvePoint(input: 0.98, output: 0.98),
            LightCurvePoint(input: 1, output: 1),
        ], preserveEndpointPositions: true)

        // These presses are inside the visible 6 pt endpoint radius, but nearer the interior
        // handles beneath them. Selection must agree with the endpoint's higher drawing order.
        XCTAssertEqual(curve.nearestHandle(to: CGPoint(x: 3, y: 99), in: size), curve.points.first)
        XCTAssertEqual(curve.nearestHandle(to: CGPoint(x: 99, y: 3), in: size), curve.points.last)

        // The endpoint's expanded target must not swallow an exposed neighboring handle, and
        // callers requesting a smaller hit radius must still get that smaller radius.
        XCTAssertEqual(curve.nearestHandle(to: CGPoint(x: 7, y: 95), in: size), curve.points[1])
        XCTAssertEqual(curve.nearestHandle(to: CGPoint(x: 95, y: 7), in: size), curve.points[2])
        XCTAssertEqual(curve.nearestHandle(to: CGPoint(x: 3, y: 99), in: size, hitRadius: 2), curve.points[1])

        // When the two endpoints themselves overlap, the last slot draws above the first.
        let overlappingEndpoints = LightToneCurve(points: [
            LightCurvePoint(input: 0.49, output: 0.5),
            LightCurvePoint(input: 0.51, output: 0.5),
        ], preserveEndpointPositions: true)
        XCTAssertEqual(overlappingEndpoints.nearestHandle(to: CGPoint(x: 50, y: 51), in: size),
                       overlappingEndpoints.points.last)
    }

    func testBothEndpointHandlesCanBeDraggedAwayAndBackRepeatedlyOnEveryChannel() throws {
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())
        let size = CGSize(width: 162, height: 162)
        for channel in ToneCurveChannel.allCases {
            for _ in 0..<3 {
                for (corner, moved) in [
                    (LightCurvePoint(input: 0, output: 0), LightCurvePoint(input: 0.12, output: 0.15)),
                    (LightCurvePoint(input: 1, output: 1), LightCurvePoint(input: 0.88, output: 0.85)),
                ] {
                    let curve = viewModel.document.light.toneCurve(for: channel)
                    let press = CGPoint(x: corner.input * size.width, y: (1 - corner.output) * size.height)
                    let selected = try XCTUnwrap(curve.nearestHandle(to: press, in: size))
                    XCTAssertEqual(selected, corner)
                    viewModel.beginPreviewInteraction()
                    let movedInput = try XCTUnwrap(viewModel.moveToneCurvePoint(
                        fromInput: selected.input, input: moved.input, output: moved.output, channel: channel
                    ))
                    XCTAssertEqual(movedInput, moved.input, accuracy: 0.000_001)
                    XCTAssertTrue(viewModel.document.light.toneCurve(for: channel).points.contains(moved))
                    viewModel.moveToneCurvePoint(
                        fromInput: movedInput, input: corner.input, output: corner.output, channel: channel
                    )
                    viewModel.endPreviewInteraction()
                    XCTAssertEqual(viewModel.document.light.toneCurve(for: channel).nearestHandle(
                        to: press, in: size
                    ), corner)
                }
            }
        }
    }

    func testDoubleClickEndpointResetPreservesInteriorPointsAndGroupsUndo() throws {
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())
        let redCurve = LightToneCurve(points: [
            LightCurvePoint(input: 0.08, output: 0.12),
            LightCurvePoint(input: 0.3, output: 0.42),
            LightCurvePoint(input: 0.7, output: 0.76),
            LightCurvePoint(input: 0.91, output: 0.88),
        ], preserveEndpointPositions: true)
        viewModel.updateDocument { $0.light.setToneCurve(redCurve, for: .red) }

        let black = try XCTUnwrap(redCurve.points.first)
        viewModel.beginPreviewInteraction()
        viewModel.setToneCurvePoint(black, input: 0, output: 0, channel: .red)
        viewModel.endPreviewInteraction()
        let afterBlackReset = viewModel.document.light.toneCurve(for: .red)
        XCTAssertEqual(afterBlackReset.points.first, LightCurvePoint(input: 0, output: 0))
        XCTAssertEqual(Array(afterBlackReset.points.dropFirst().dropLast()),
                       Array(redCurve.points.dropFirst().dropLast()))
        viewModel.undo()
        XCTAssertEqual(viewModel.document.light.toneCurve(for: .red), redCurve)

        let white = try XCTUnwrap(redCurve.points.last)
        viewModel.beginPreviewInteraction()
        viewModel.setToneCurvePoint(white, input: 1, output: 1, channel: .red)
        viewModel.endPreviewInteraction()
        let afterWhiteReset = viewModel.document.light.toneCurve(for: .red)
        XCTAssertEqual(afterWhiteReset.points.last, LightCurvePoint(input: 1, output: 1))
        XCTAssertEqual(Array(afterWhiteReset.points.dropFirst().dropLast()),
                       Array(redCurve.points.dropFirst().dropLast()))

        let source = try lightInspectorSource()
        XCTAssertTrue(source.contains(".onEnded { _ in doubleClickPoint(point) }"))
        XCTAssertTrue(source.contains("private func doubleClickPoint(_ point: LightCurvePoint)"))
    }

    func testEmptyCurveDragCreatesOnePointAndUndoRedoKeepTheWholeGestureTogether() {
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())
        let curve = viewModel.document.light.toneCurve
        let input = 0.35

        viewModel.beginPreviewInteraction()
        // This mirrors the graph gesture's first update: add the sampled point, then apply the
        // pointer's exact output. Subsequent updates use the returned input as the stable target.
        viewModel.addToneCurvePoint(input: input)
        var sourceInput = input
        for output in [0.42, 0.5, 0.63, 0.78] {
            sourceInput = viewModel.moveToneCurvePoint(
                fromInput: sourceInput, input: input, output: output
            ) ?? sourceInput
        }
        viewModel.endPreviewInteraction()

        let interior = viewModel.document.light.toneCurve.points.dropFirst().dropLast()
        XCTAssertEqual(interior.count, 1)
        XCTAssertEqual(interior.first?.input ?? -1, input, accuracy: 0.000_001)
        XCTAssertEqual(interior.first?.output ?? -1, 0.78, accuracy: 0.000_001)

        viewModel.undo()
        XCTAssertEqual(viewModel.document.light.toneCurve, curve)
        XCTAssertFalse(viewModel.canUndo)
        viewModel.redo()
        XCTAssertEqual(viewModel.document.light.toneCurve.points.dropFirst().dropLast().count, 1)
        XCTAssertEqual(viewModel.document.light.toneCurve.value(at: input), 0.78, accuracy: 0.000_001)
    }

    func testNearExistingPointMovesThatPointWithoutAddingADuplicate() {
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())
        viewModel.updateDocument {
            $0.light.toneCurve = LightToneCurve(points: [
                LightCurvePoint(input: 0.3, output: 0.3),
                LightCurvePoint(input: 0.7, output: 0.7),
            ])
        }

        viewModel.beginPreviewInteraction()
        let movedInput = viewModel.moveToneCurvePoint(fromInput: 0.325, input: 0.5, output: 0.55)
        viewModel.endPreviewInteraction()

        XCTAssertEqual(movedInput ?? -1, 0.5, accuracy: 0.000_001)
        XCTAssertEqual(viewModel.document.light.toneCurve.points.dropFirst().dropLast().count, 2)
        XCTAssertEqual(viewModel.document.light.toneCurve.points[1].input, 0.5, accuracy: 0.000_001)
        XCTAssertEqual(viewModel.document.light.toneCurve.points[1].output, 0.55, accuracy: 0.000_001)
    }

    func testCurveDragPublishesAnIntermediatePreviewBeforeRelease() async throws {
        let image = try Fixtures.writeGradientPNG(
            width: 16, height: 12, named: "curve-drag.png", in: tempDirectory
        )
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())
        viewModel.openImage(url: image)
        try await waitUntil { viewModel.previewSurface.image != nil }
        let initialSurfaceRevision = viewModel.previewSurface.revision

        viewModel.beginPreviewInteraction()
        viewModel.moveToneCurvePoint(fromInput: 0.5, input: 0.5, output: 0.8)

        try await waitUntil {
            viewModel.previewSurface.revision > initialSurfaceRevision
        }
        XCTAssertEqual(viewModel.document.light.toneCurve.value(at: 0.5), 0.8, accuracy: 0.000_001)

        viewModel.endPreviewInteraction()
    }

    private func waitUntil(
        timeout: TimeInterval = 2,
        _ condition: @escaping @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline { return XCTFail("timed out waiting for image load") }
            try await Task.sleep(for: .milliseconds(5))
        }
    }
}

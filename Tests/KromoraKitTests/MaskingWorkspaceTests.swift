import CoreGraphics
import Foundation
import XCTest

@testable import KromoraKit

@MainActor
final class MaskingWorkspaceTests: TempDirectoryTestCase {
    private func waitUntil(
        _ description: String,
        timeout: TimeInterval = 5,
        _ condition: @MainActor () -> Bool,
        diagnostics: @MainActor () -> String = { "" }
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline {
                let detail = diagnostics()
                return XCTFail(
                    "timed out waiting for \(description)"
                        + (detail.isEmpty ? "" : "; \(detail)")
                )
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    func testMaskingIsAnInspectorTabAndReturnsToThePreviousEditControl() {
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())

        viewModel.inspectorState.select(.effects)
        viewModel.inspectorState.select(.masking)

        XCTAssertEqual(viewModel.inspectorTab, .masking)
        XCTAssertTrue(viewModel.inspectorState.isMaskingWorkspacePresented)
        XCTAssertEqual(AppViewModel.InspectorTab.masking.title, "Masking")
        XCTAssertEqual(
            AppViewModel.InspectorTab.masking.helpText,
            "Masking: Create and edit local masks"
        )

        viewModel.closeMaskingWorkspace()

        XCTAssertEqual(viewModel.inspectorTab, .effects)
        XCTAssertFalse(viewModel.inspectorState.isMaskingWorkspacePresented)
    }

    func testMaskingInspectorTabStaysWithTheActivePhotoAndRestoresItsDocument() async throws {
        let directory = try Fixtures.makeTempDirectory("MaskingInspectorNavigation")
        defer { try? FileManager.default.removeItem(at: directory) }
        let firstURL = try Fixtures.writeGradientPNG(
            width: 16, height: 12, named: "first.png", in: directory)
        let secondURL = try Fixtures.writeGradientPNG(
            width: 16, height: 12, named: "second.png", in: directory)
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())

        viewModel.openImage(url: firstURL)
        try await waitUntil("the first photo to load") { viewModel.maskingSource != nil }
        XCTAssertTrue(viewModel.availableInspectorTabs.contains(.masking))
        viewModel.inspectorTab = .effects
        viewModel.selectInspectorTab(.masking)
        viewModel.createMask(.brush)
        let firstLayerID = try XCTUnwrap(viewModel.document.localAdjustments.first?.id)

        viewModel.openImage(url: secondURL)
        try await waitUntil("the second photo to load") {
            viewModel.maskingSource?.cacheFingerprint != nil
                && viewModel.sourceName == "second.png"
        }

        XCTAssertEqual(viewModel.inspectorTab, .masking)
        XCTAssertTrue(viewModel.document.localAdjustments.isEmpty)

        viewModel.closeMaskingWorkspace()
        XCTAssertEqual(viewModel.inspectorTab, .effects)

        viewModel.openImage(url: firstURL)
        try await waitUntil("the first photo to restore") {
            viewModel.sourceName == "first.png"
                && viewModel.document.localAdjustments.contains(where: { $0.id == firstLayerID })
        }
        XCTAssertEqual(viewModel.inspectorTab, .effects)
    }

    func testMaskOverlayIsScopedToMaskingTabAndEditorWorkspace() async throws {
        let directory = try Fixtures.makeTempDirectory("MaskOverlayWorkspaceVisibility")
        defer { try? FileManager.default.removeItem(at: directory) }
        let imageURL = try Fixtures.writeGradientPNG(
            width: 16, height: 12, named: "overlay.png", in: directory)
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())

        viewModel.openImage(url: imageURL)
        try await waitUntil("the photo to load") { viewModel.maskingSource != nil }
        viewModel.selectInspectorTab(.masking)
        viewModel.createMask(.brush)

        XCTAssertTrue(viewModel.isMaskingWorkspaceActive)
        XCTAssertTrue(viewModel.maskingState.showOverlay)
        let layerID = try XCTUnwrap(viewModel.maskingState.selectedLayerID)

        viewModel.selectInspectorTab(.effects)
        XCTAssertFalse(viewModel.isMaskingWorkspaceActive)
        XCTAssertEqual(viewModel.maskingState.selectedLayerID, layerID)
        XCTAssertTrue(viewModel.maskingState.showOverlay)

        viewModel.navigate(to: .grid)
        XCTAssertFalse(viewModel.isMaskingWorkspaceActive)

        XCTAssertTrue(viewModel.navigate(to: .edit))
        XCTAssertFalse(viewModel.isMaskingWorkspaceActive)
        XCTAssertEqual(viewModel.inspectorTab, .effects)

        viewModel.selectInspectorTab(.masking)
        XCTAssertTrue(viewModel.isMaskingWorkspaceActive)
        XCTAssertEqual(viewModel.maskingState.selectedLayerID, layerID)
    }

    func testLayerActionsPersistThroughTheDocumentAndUndo() throws {
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())

        viewModel.createMask(.linear)
        viewModel.beginMaskGesture(at: CGPoint(x: 0.2, y: 0.5))
        viewModel.updateMaskGesture(to: CGPoint(x: 0.8, y: 0.5))
        viewModel.endMaskGesture()
        let original = try XCTUnwrap(viewModel.document.localAdjustments.first)
        XCTAssertEqual(original.name, "Linear Gradient")

        viewModel.renameMask(original.id, name: "Sky")
        viewModel.updateMask(original.id) { layer in
            layer.amount = 0.6
            layer.adjustments.exposure = 1.25
        }
        viewModel.duplicateMask(original.id)

        XCTAssertEqual(viewModel.document.localAdjustments.count, 2)
        XCTAssertEqual(viewModel.document.localAdjustments.first?.name, "Sky")
        XCTAssertEqual(viewModel.document.localAdjustments.first?.amount, 0.6)
        XCTAssertEqual(viewModel.document.localAdjustments.first?.adjustments.exposure, 1.25)

        viewModel.undo()
        XCTAssertEqual(viewModel.document.localAdjustments.count, 1)
        XCTAssertEqual(viewModel.document.localAdjustments.first?.adjustments.exposure, 1.25)

        viewModel.selectMaskLayer(original.id)
        viewModel.resetSelectedMask()
        XCTAssertEqual(viewModel.document.localAdjustments.first?.amount, 1)
        XCTAssertEqual(viewModel.document.localAdjustments.first?.adjustments, .neutral)
    }

    func testGestureEditsTheSelectedComponentNotJustTheFirstEnabledOne() throws {
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())

        viewModel.createMask(.linear)
        viewModel.beginMaskGesture(at: CGPoint(x: 0.1, y: 0.5))
        viewModel.updateMaskGesture(to: CGPoint(x: 0.9, y: 0.5))
        viewModel.endMaskGesture()
        let layerID = try XCTUnwrap(viewModel.document.localAdjustments.first?.id)
        viewModel.addMaskComponent(to: layerID, source: .brush(BrushMaskDefinition()))
        let brushComponentID = try XCTUnwrap(
            viewModel.document.localAdjustments.first?.components.last?.id)

        // addMaskComponent already selects the new component; the brush tool should therefore
        // draw into it, not into the pre-existing linear component at index 0.
        viewModel.setMaskTool(.brush)
        viewModel.beginMaskGesture(at: CGPoint(x: 0.2, y: 0.3))
        viewModel.endMaskGesture()

        let layer = try XCTUnwrap(viewModel.document.localAdjustments.first)
        XCTAssertEqual(layer.components.count, 2)
        guard case .linear = layer.components[0].source else {
            return XCTFail("Linear component at index 0 should be untouched")
        }
        guard case .brush(let definition) = layer.components[1].source else {
            return XCTFail("Selected brush component should have received the stroke")
        }
        XCTAssertEqual(layer.components[1].id, brushComponentID)
        XCTAssertFalse(definition.strokes.isEmpty)
    }

    func testBrushGestureCommitsOneCompactStrokeWithSettings() throws {
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())
        viewModel.createMask(.brush)
        viewModel.maskingState.brushRadius = 0.03
        viewModel.maskingState.brushFeather = 0.25
        viewModel.maskingState.brushFlow = 0.6
        viewModel.maskingState.brushDensity = 0.8
        viewModel.setMaskTool(.brush)
        viewModel.beginMaskGesture(
            at: CGPoint(x: 0.1, y: 0.5), sourceSize: CGSize(width: 6_000, height: 4_000))
        for index in 1...10_000 {
            viewModel.updateMaskGesture(
                to: CGPoint(x: 0.1 + Double(index) / 12_500, y: 0.5),
                pressure: index.isMultiple(of: 2) ? 0.5 : nil)
        }
        viewModel.endMaskGesture()

        let layer = try XCTUnwrap(viewModel.document.localAdjustments.first)
        let stroke = try XCTUnwrap(layer.components.first?.source.brushDefinition?.strokes.first)
        XCTAssertEqual(stroke.radius, 0.03, accuracy: 0.000_001)
        XCTAssertEqual(stroke.feather, 0.25, accuracy: 0.000_001)
        XCTAssertEqual(stroke.flow, 0.6, accuracy: 0.000_001)
        XCTAssertEqual(stroke.density, 0.8, accuracy: 0.000_001)
        XCTAssertLessThanOrEqual(stroke.samples.count, 4_096)
        XCTAssertEqual(viewModel.document.localAdjustments.count, 1)
    }

    func testSeparateBrushGesturesAppendStrokesWithoutRewritingHistory() throws {
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())
        viewModel.createMask(.brush)
        viewModel.setMaskTool(.brush)

        viewModel.beginMaskGesture(at: CGPoint(x: 0.1, y: 0.5))
        viewModel.updateMaskGesture(to: CGPoint(x: 0.2, y: 0.5))
        viewModel.endMaskGesture()
        viewModel.beginMaskGesture(at: CGPoint(x: 0.7, y: 0.5))
        viewModel.updateMaskGesture(to: CGPoint(x: 0.8, y: 0.5))
        viewModel.endMaskGesture()

        let definition = try XCTUnwrap(
            viewModel.document.localAdjustments.first?.components.first?.source.brushDefinition)
        XCTAssertEqual(definition.strokes.count, 2)
        XCTAssertEqual(definition.strokes[0].samples.first?.point, CGPoint(x: 0.1, y: 0.5))
        XCTAssertEqual(definition.strokes[1].samples.first?.point, CGPoint(x: 0.7, y: 0.5))
    }

    func testEraseBrushIsASeparateSubtractingComponent() throws {
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())
        viewModel.createMask(.erase)
        let component = try XCTUnwrap(viewModel.document.localAdjustments.first?.components.first)
        XCTAssertEqual(component.mode, .subtract)
        XCTAssertEqual(viewModel.maskingState.activeTool, .erase)
    }

    func testAddingEraseBrushToSelectedMaskTargetsThatLayer() throws {
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())
        viewModel.createMask(.foreground)
        let layerID = try XCTUnwrap(viewModel.maskingState.selectedLayerID)

        viewModel.createMask(.erase)

        let layer = try XCTUnwrap(viewModel.document.localAdjustments.first)
        XCTAssertEqual(layer.id, layerID)
        XCTAssertEqual(viewModel.document.localAdjustments.count, 1)
        XCTAssertEqual(layer.components.count, 2)
        XCTAssertEqual(layer.components.last?.mode, .subtract)
        XCTAssertNotNil(layer.components.last?.source.brushDefinition)
    }

    func testEraseGesturePreservesEachExistingMaskSourceAndAppendsSubtractBrushIntent() throws {
        for kind in [MaskCreationKind.linear, .radial, .foreground, .brush] {
            let viewModel = makeAppViewModel(engine: FakeRenderEngine())
            viewModel.createMask(.foreground)
            let componentID = try XCTUnwrap(viewModel.maskingState.selectedComponentID)
            let layerID = try XCTUnwrap(viewModel.maskingState.selectedLayerID)
            let replacement: MaskSource
            switch kind {
            case .linear: replacement = .linear(LinearGradientDefinition())
            case .radial: replacement = .radial(RadialGradientDefinition())
            case .foreground: replacement = .semantic(SemanticMaskDefinition(target: .foreground))
            case .brush: replacement = .brush(BrushMaskDefinition())
            default: fatalError("Unexpected source fixture")
            }
            viewModel.updateMaskComponent(componentID, in: layerID) { $0.source = replacement }
            let sourceBefore = try XCTUnwrap(
                viewModel.document.localAdjustments.first?.components.first?.source)

            viewModel.setMaskTool(.erase)
            viewModel.maskingState.brushRadius = 0.025
            viewModel.maskingState.brushFeather = 0.4
            viewModel.maskingState.brushFlow = 0.7
            viewModel.maskingState.brushDensity = 0.8
            viewModel.beginMaskGesture(
                at: CGPoint(x: 0.2, y: 0.5),
                sourceSize: CGSize(width: 1_000, height: 1_000))
            viewModel.updateMaskGesture(to: CGPoint(x: 0.8, y: 0.5))
            viewModel.endMaskGesture()

            let layer = try XCTUnwrap(viewModel.document.localAdjustments.first)
            XCTAssertEqual(layer.components.count, 2, "\(kind) must retain its existing component")
            XCTAssertEqual(layer.components[0].source, sourceBefore)
            XCTAssertEqual(layer.components[1].mode, .subtract)
            let stroke = try XCTUnwrap(layer.components[1].source.brushDefinition?.strokes.last)
            XCTAssertEqual(stroke.radius, 0.025, accuracy: 0.000_001)
            XCTAssertEqual(stroke.feather, 0.4, accuracy: 0.000_001)
            XCTAssertEqual(stroke.flow, 0.7, accuracy: 0.000_001)
            XCTAssertEqual(stroke.density, 0.8, accuracy: 0.000_001)
            XCTAssertGreaterThan(stroke.samples.count, 2, "sparse endpoints must be filled")
        }
    }

    func testActiveBrushSettingsAreCapturedOnceEvenIfControlsChangeMidStroke() throws {
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())
        viewModel.createMask(.brush)
        viewModel.maskingState.brushRadius = 0.03
        viewModel.maskingState.brushFeather = 0.2
        viewModel.beginMaskGesture(at: CGPoint(x: 0.2, y: 0.5))
        viewModel.maskingState.brushRadius = 0.12
        viewModel.maskingState.brushFeather = 0.9
        viewModel.updateMaskGesture(to: CGPoint(x: 0.8, y: 0.5))
        viewModel.endMaskGesture()

        let stroke = try XCTUnwrap(
            viewModel.document.localAdjustments.first?.components.first?.source.brushDefinition?
                .strokes.last)
        XCTAssertEqual(stroke.radius, 0.03, accuracy: 0.000_001)
        XCTAssertEqual(stroke.feather, 0.2, accuracy: 0.000_001)
    }

    func testComponentCreationSupportsEverySourceAndOperationWithExplicitFirstReplace() throws {
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())
        viewModel.createMask(.foreground)
        let layerID = try XCTUnwrap(viewModel.document.localAdjustments.first?.id)

        let sources: [MaskSource] = [
            .semantic(SemanticMaskDefinition(target: .background)),
            .brush(BrushMaskDefinition()),
            .linear(LinearGradientDefinition()),
            .radial(RadialGradientDefinition()),
        ]
        let modes: [MaskCombineMode] = [.add, .subtract, .intersect, .add]
        for (source, mode) in zip(sources, modes) {
            viewModel.addMaskComponent(to: layerID, source: source, mode: mode)
        }

        let components = try XCTUnwrap(viewModel.document.localAdjustments.first?.components)
        XCTAssertEqual(components.map(\.mode), [.replace, .add, .subtract, .intersect, .add])
        XCTAssertEqual(components.map(\.source.maskingTypeTitle), [
            "Foreground", "Background", "Brush", "Linear Gradient", "Radial Gradient",
        ])
    }

    func testComponentActionsPreserveOrderNamesAndSoloInspection() throws {
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())
        viewModel.createMask(.foreground)
        let layerID = try XCTUnwrap(viewModel.document.localAdjustments.first?.id)
        viewModel.addMaskComponent(
            to: layerID, source: .brush(BrushMaskDefinition()), mode: .subtract)
        let brushID = try XCTUnwrap(viewModel.document.localAdjustments.first?.components.last?.id)

        viewModel.renameMaskComponent(brushID, in: layerID, name: "Sky Brush")
        viewModel.moveMaskComponent(brushID, in: layerID, by: -1)
        XCTAssertEqual(viewModel.document.localAdjustments.first?.components.first?.name, "Sky Brush")
        XCTAssertEqual(viewModel.document.localAdjustments.first?.components.first?.mode, .replace)
        XCTAssertEqual(viewModel.document.localAdjustments.first?.maskingSummary, "Sky Brush · replace Foreground")

        viewModel.maskingState.toggleSolo(componentID: brushID, layerID: layerID)
        XCTAssertEqual(viewModel.maskingState.soloComponentID, brushID)
        XCTAssertEqual(viewModel.maskingState.soloLayerID, layerID)
        viewModel.deleteMaskComponent(brushID, from: layerID)
        XCTAssertNil(viewModel.maskingState.soloComponentID)
        XCTAssertEqual(viewModel.document.localAdjustments.first?.components.count, 1)
    }

    func testLinearDragCreatesAndSelectsATransientLayerUntilMouseUp() throws {
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())
        viewModel.setMaskTool(.linear)
        viewModel.beginMaskGesture(at: CGPoint(x: 0.2, y: 0.3))
        XCTAssertTrue(viewModel.document.localAdjustments.isEmpty)
        XCTAssertNotNil(viewModel.maskInteractionState.selectedLayerID)

        viewModel.updateMaskGesture(to: CGPoint(x: 0.8, y: 0.7))
        viewModel.endMaskGesture()

        let layer = try XCTUnwrap(viewModel.document.localAdjustments.first)
        XCTAssertEqual(viewModel.maskInteractionState.selectedLayerID, layer.id)
        guard case .linear(let definition) = try XCTUnwrap(layer.components.first).source else {
            return XCTFail("linear drag should create a linear component")
        }
        XCTAssertEqual(definition.zeroStrengthPoint, CGPoint(x: 0.2, y: 0.3))
        XCTAssertEqual(definition.fullStrengthPoint, CGPoint(x: 0.8, y: 0.7))
    }

    func testLinearHandleEditsKeepOppositeEdgeAndCenterStable() throws {
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())
        viewModel.createMask(.linear)
        let layerID = try XCTUnwrap(viewModel.maskInteractionState.selectedLayerID)
        let componentID = try XCTUnwrap(viewModel.maskInteractionState.selectedComponentID)

        viewModel.setMaskTool(.linear)
        viewModel.beginMaskGesture(at: CGPoint(x: 0.2, y: 0.5))
        viewModel.updateMaskGesture(to: CGPoint(x: 0.8, y: 0.5))
        viewModel.endMaskGesture()
        let original = try XCTUnwrap(viewModel.document.localAdjustments.first?.components.first?.source.linearDefinition)

        viewModel.beginMaskGesture(at: original.fullStrengthPoint, linearHandle: .fullStrength)
        viewModel.updateMaskGesture(to: CGPoint(x: 0.75, y: 0.5))
        viewModel.endMaskGesture()
        let resized = try XCTUnwrap(viewModel.document.localAdjustments.first?.components.first?.source.linearDefinition)
        XCTAssertEqual(resized.zeroStrengthPoint, original.zeroStrengthPoint)
        XCTAssertEqual(resized.angle, original.angle, accuracy: 0.000_001)

        viewModel.beginMaskGesture(at: resized.centerPoint, linearHandle: .center)
        viewModel.updateMaskGesture(to: CGPoint(x: resized.centerPoint.x + 0.1, y: resized.centerPoint.y + 0.1))
        viewModel.endMaskGesture()
        let moved = try XCTUnwrap(viewModel.document.localAdjustments.first?.components.first?.source.linearDefinition)
        XCTAssertEqual(moved.centerPoint, CGPoint(x: resized.centerPoint.x + 0.1, y: resized.centerPoint.y + 0.1))
        XCTAssertEqual(moved.falloff, resized.falloff, accuracy: 0.000_001)
        XCTAssertEqual(viewModel.maskInteractionState.selectedComponentID, componentID)
        XCTAssertEqual(viewModel.maskInteractionState.selectedLayerID, layerID)
    }

    func testLinearZeroStrengthHandleResizesWithoutReplacingDefinition() throws {
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())
        viewModel.createMask(.linear)
        viewModel.beginMaskGesture(at: CGPoint(x: 0.2, y: 0.2))
        viewModel.updateMaskGesture(to: CGPoint(x: 0.8, y: 0.8))
        viewModel.endMaskGesture()

        let originalLayer = try XCTUnwrap(viewModel.document.localAdjustments.first)
        let originalComponent = try XCTUnwrap(originalLayer.components.first)
        let original = try XCTUnwrap(originalComponent.source.linearDefinition)

        viewModel.beginMaskGesture(at: original.zeroStrengthPoint, linearHandle: .zeroStrength)
        viewModel.updateMaskGesture(to: CGPoint(x: 0.35, y: 0.35))
        viewModel.endMaskGesture()

        let updatedLayer = try XCTUnwrap(viewModel.document.localAdjustments.first)
        let updatedComponent = try XCTUnwrap(updatedLayer.components.first)
        let updated = try XCTUnwrap(updatedComponent.source.linearDefinition)
        XCTAssertEqual(updatedLayer.id, originalLayer.id)
        XCTAssertEqual(updatedComponent.id, originalComponent.id)
        XCTAssertEqual(updatedComponent.mode, originalComponent.mode)
        XCTAssertEqual(updatedComponent.source.linearDefinition?.density, original.density)
        XCTAssertEqual(updated.fullStrengthPoint, original.fullStrengthPoint)
        XCTAssertEqual(updated.angle, original.angle, accuracy: 0.000_001)
        XCTAssertEqual(updated.falloff, hypot(0.8 - 0.35, 0.8 - 0.35), accuracy: 0.000_001)
    }

    func testLinearFullStrengthHandleResizesWithoutReplacingDefinition() throws {
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())
        viewModel.createMask(.linear)
        viewModel.beginMaskGesture(at: CGPoint(x: 0.2, y: 0.2))
        viewModel.updateMaskGesture(to: CGPoint(x: 0.8, y: 0.8))
        viewModel.endMaskGesture()

        let originalLayer = try XCTUnwrap(viewModel.document.localAdjustments.first)
        let originalComponent = try XCTUnwrap(originalLayer.components.first)
        let original = try XCTUnwrap(originalComponent.source.linearDefinition)

        viewModel.beginMaskGesture(at: original.fullStrengthPoint, linearHandle: .fullStrength)
        viewModel.updateMaskGesture(to: CGPoint(x: 0.65, y: 0.65))
        viewModel.endMaskGesture()

        let updatedLayer = try XCTUnwrap(viewModel.document.localAdjustments.first)
        let updatedComponent = try XCTUnwrap(updatedLayer.components.first)
        let updated = try XCTUnwrap(updatedComponent.source.linearDefinition)
        XCTAssertEqual(updatedLayer.id, originalLayer.id)
        XCTAssertEqual(updatedComponent.id, originalComponent.id)
        XCTAssertEqual(updatedComponent.mode, originalComponent.mode)
        XCTAssertEqual(updatedComponent.source.linearDefinition?.density, original.density)
        XCTAssertEqual(updated.zeroStrengthPoint, original.zeroStrengthPoint)
        XCTAssertEqual(updated.angle, original.angle, accuracy: 0.000_001)
        XCTAssertEqual(updated.falloff, hypot(0.65 - 0.2, 0.65 - 0.2), accuracy: 0.000_001)
    }

    func testNewLinearLayerStartsWithCreationDragEvenWhenDefaultGuideIsUnderPointer() throws {
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())
        viewModel.createMask(.linear)
        viewModel.beginMaskGesture(at: CGPoint(x: 0.25, y: 0.25))
        viewModel.updateMaskGesture(to: CGPoint(x: 0.75, y: 0.75))
        viewModel.endMaskGesture()

        let definition = try XCTUnwrap(
            viewModel.document.localAdjustments.first?.components.first?.source.linearDefinition)
        XCTAssertEqual(definition.zeroStrengthPoint, CGPoint(x: 0.25, y: 0.25))
        XCTAssertEqual(definition.fullStrengthPoint, CGPoint(x: 0.75, y: 0.75))
    }

    func testInspectorChangesFollowTheLiveLinearDraftUntilMouseUp() throws {
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())
        viewModel.createMask(.linear)
        let layerID = try XCTUnwrap(viewModel.maskInteractionState.selectedLayerID)
        let componentID = try XCTUnwrap(viewModel.maskInteractionState.selectedComponentID)

        viewModel.setMaskTool(.linear)
        viewModel.beginMaskGesture(at: CGPoint(x: 0.2, y: 0.5))
        viewModel.updateMaskComponent(componentID, in: layerID) { component in
            if case .linear(var definition) = component.source {
                definition.density = 0.4
                component.source = .linear(definition)
            }
        }

        XCTAssertEqual(
            viewModel.document.localAdjustments.first?.components.first?.source.linearDefinition?.density,
            nil
        )
        XCTAssertEqual(
            viewModel.maskInteractionState.draftLayer?.components.first?.source.linearDefinition?.density,
            0.4
        )

        viewModel.updateMaskGesture(to: CGPoint(x: 0.8, y: 0.5))
        viewModel.endMaskGesture()
        XCTAssertEqual(
            viewModel.document.localAdjustments.first?.components.first?.source.linearDefinition?.density,
            0.4
        )
    }

    func testCancellingLinearCreationDoesNotPersistAnEmptyLayer() {
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())
        viewModel.createMask(.linear)
        XCTAssertTrue(viewModel.document.localAdjustments.isEmpty)
        XCTAssertTrue(viewModel.maskInteractionState.linearCreationPending)
        viewModel.cancelMaskGesture()
        XCTAssertTrue(viewModel.document.localAdjustments.isEmpty)
        XCTAssertNil(viewModel.maskInteractionState.selectedLayerID)
        XCTAssertFalse(viewModel.maskInteractionState.hasDraft)
    }

    func testFreshLinearCreationSelectsLayerAndComponentAndCommitsOneUndoableMask() throws {
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())

        viewModel.createMask(.linear)
        let pendingLayerID = try XCTUnwrap(viewModel.maskInteractionState.selectedLayerID)
        let pendingComponentID = try XCTUnwrap(viewModel.maskInteractionState.selectedComponentID)
        XCTAssertTrue(viewModel.maskInteractionState.linearCreationPending)
        XCTAssertTrue(viewModel.document.localAdjustments.isEmpty)

        viewModel.beginMaskGesture(at: CGPoint(x: 0.2, y: 0.3))
        viewModel.updateMaskGesture(to: CGPoint(x: 0.8, y: 0.7))
        viewModel.endMaskGesture()

        let layer = try XCTUnwrap(viewModel.document.localAdjustments.first)
        let component = try XCTUnwrap(layer.components.first)
        XCTAssertEqual(layer.id, pendingLayerID)
        XCTAssertEqual(component.id, pendingComponentID)
        XCTAssertEqual(viewModel.maskInteractionState.selectedLayerID, layer.id)
        XCTAssertEqual(viewModel.maskInteractionState.selectedComponentID, component.id)
        XCTAssertGreaterThan(component.source.linearDefinition?.falloff ?? 0, 0)
        XCTAssertEqual(viewModel.undoDepth, 1)

        viewModel.undo()
        XCTAssertTrue(viewModel.document.localAdjustments.isEmpty)
    }

    func testLinearCreationAfterExistingSelectionDoesNotEditPreviousLayer() throws {
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())
        viewModel.createMask(.foreground)
        let existing = try XCTUnwrap(viewModel.document.localAdjustments.first)

        viewModel.createMask(.linear)
        XCTAssertEqual(viewModel.document.localAdjustments.count, 1)
        XCTAssertNotEqual(viewModel.maskInteractionState.selectedLayerID, existing.id)
        XCTAssertEqual(viewModel.maskInteractionState.draftLayer?.components.count, 1)

        viewModel.beginMaskGesture(at: CGPoint(x: 0.15, y: 0.5))
        viewModel.updateMaskGesture(to: CGPoint(x: 0.85, y: 0.5))
        viewModel.endMaskGesture()

        XCTAssertEqual(viewModel.document.localAdjustments.count, 2)
        XCTAssertEqual(viewModel.document.localAdjustments.first?.id, existing.id)
        XCTAssertEqual(viewModel.maskInteractionState.selectedLayerID,
                       viewModel.document.localAdjustments.last?.id)
        XCTAssertEqual(viewModel.maskInteractionState.selectedComponentID,
                       viewModel.document.localAdjustments.last?.components.first?.id)
    }

    func testClickWithoutAValidLinearDragLeavesDocumentAndHistoryUnchanged() {
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())
        viewModel.createMask(.foreground)
        let before = viewModel.document
        let undoBefore = viewModel.undoDepth

        viewModel.createMask(.linear)
        viewModel.beginMaskGesture(at: CGPoint(x: 0.5, y: 0.5))
        viewModel.endMaskGesture()

        XCTAssertEqual(viewModel.document, before)
        XCTAssertEqual(viewModel.undoDepth, undoBefore)
        XCTAssertFalse(viewModel.maskInteractionState.hasDraft)
        XCTAssertEqual(viewModel.maskInteractionState.selectedLayerID,
                       before.localAdjustments.first?.id)
    }

    func testRadialDragCreatesAndSelectsATransientLayerUntilMouseUp() throws {
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())
        viewModel.setMaskTool(.radial)
        viewModel.beginMaskGesture(
            at: CGPoint(x: 0.3, y: 0.4), sourceSize: CGSize(width: 400, height: 200))
        XCTAssertTrue(viewModel.document.localAdjustments.isEmpty)

        viewModel.updateMaskGesture(
            to: CGPoint(x: 0.55, y: 0.65), modifiers: [])
        viewModel.endMaskGesture()

        let layer = try XCTUnwrap(viewModel.document.localAdjustments.first)
        XCTAssertEqual(layer.name, "Radial Gradient")
        guard case .radial(let definition) = try XCTUnwrap(layer.components.first).source else {
            return XCTFail("radial drag should create a radial component")
        }
        XCTAssertEqual(definition.center, CGPoint(x: 0.3, y: 0.4))
        XCTAssertEqual(definition.horizontalRadius, 0.25, accuracy: 0.000_001)
        XCTAssertEqual(definition.verticalRadius, 0.25, accuracy: 0.000_001)
        XCTAssertEqual(viewModel.maskInteractionState.selectedLayerID, layer.id)
    }

    func testRadialHandlesResizeTranslateRotateAndOptionShiftModifiers() throws {
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())
        viewModel.createMask(.radial)
        let layerID = try XCTUnwrap(viewModel.maskInteractionState.selectedLayerID)
        let componentID = try XCTUnwrap(viewModel.maskInteractionState.selectedComponentID)
        let original = try XCTUnwrap(
            viewModel.document.localAdjustments.first?.components.first?.source.radialDefinition)
        let sourceSize = CGSize(width: 400, height: 200)
        viewModel.setMaskTool(.radial)
        // The Add-mask action leaves the first canvas drag in creation mode. Consume that
        // presentation-only pending state here so the following gestures exercise re-editing.
        viewModel.maskInteractionState.consumeRadialCreationPending()

        let right = CGPoint(x: original.center.x + original.horizontalRadius, y: original.center.y)
        viewModel.beginMaskGesture(
            at: right, radialHandle: .horizontalRadius, sourceSize: sourceSize)
        viewModel.updateMaskGesture(
            to: CGPoint(x: 0.8, y: original.center.y), modifiers: [])
        viewModel.endMaskGesture()
        let resized = try XCTUnwrap(
            viewModel.document.localAdjustments.first?.components.first?.source.radialDefinition)
        XCTAssertEqual(resized.center.x, 0.4, accuracy: 0.000_001)
        XCTAssertEqual(resized.horizontalRadius, 0.4, accuracy: 0.000_001)
        XCTAssertEqual(resized.verticalRadius, original.verticalRadius, accuracy: 0.000_001)

        let center = resized.center
        viewModel.beginMaskGesture(at: center, radialHandle: .center, sourceSize: sourceSize)
        viewModel.updateMaskGesture(to: CGPoint(x: center.x + 0.1, y: center.y - 0.05))
        viewModel.endMaskGesture()
        let moved = try XCTUnwrap(
            viewModel.document.localAdjustments.first?.components.first?.source.radialDefinition)
        XCTAssertEqual(moved.center.x, center.x + 0.1, accuracy: 0.000_001)
        XCTAssertEqual(moved.center.y, center.y - 0.05, accuracy: 0.000_001)

        let movedRight = CGPoint(x: moved.center.x + moved.horizontalRadius, y: moved.center.y)
        viewModel.beginMaskGesture(
            at: movedRight, radialHandle: .horizontalRadius, sourceSize: sourceSize)
        viewModel.updateMaskGesture(
            to: CGPoint(x: moved.center.x + 0.2, y: moved.center.y),
            modifiers: [.option, .shift])
        viewModel.endMaskGesture()
        let constrained = try XCTUnwrap(
            viewModel.document.localAdjustments.first?.components.first?.source.radialDefinition)
        XCTAssertEqual(
            constrained.horizontalRadius * sourceSize.width,
            constrained.verticalRadius * sourceSize.height,
            accuracy: 0.000_001)
        XCTAssertEqual(constrained.center, moved.center)

        viewModel.beginMaskGesture(
            at: CGPoint(x: constrained.center.x, y: constrained.center.y - constrained.verticalRadius),
            radialHandle: .rotation, sourceSize: sourceSize)
        viewModel.updateMaskGesture(to: CGPoint(
            x: constrained.center.x + 0.1, y: constrained.center.y), modifiers: [])
        viewModel.endMaskGesture()
        let rotated = try XCTUnwrap(
            viewModel.document.localAdjustments.first?.components.first?.source.radialDefinition)
        XCTAssertEqual(rotated.rotation, .pi / 2, accuracy: 0.000_001)
        XCTAssertEqual(viewModel.maskInteractionState.selectedComponentID, componentID)
        XCTAssertEqual(viewModel.maskInteractionState.selectedLayerID, layerID)
    }

    func testRadialCenterDragUsesTheViewportDeltaAtZoomAndPreservesDefinition() throws {
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())
        viewModel.createMask(.radial)
        let layerID = try XCTUnwrap(viewModel.maskInteractionState.selectedLayerID)
        let componentID = try XCTUnwrap(viewModel.maskInteractionState.selectedComponentID)
        let original = RadialGradientDefinition(
            center: CGPoint(x: 0.42, y: 0.58), horizontalRadius: 0.18,
            verticalRadius: 0.11, rotation: 0.37, feather: 0.29,
            density: 0.63, isInside: false
        )
        viewModel.updateMaskComponent(componentID, in: layerID) { component in
            component.source = .radial(original)
        }
        viewModel.setMaskTool(.radial)
        viewModel.maskingState.consumeRadialCreationPending()

        var navigation = CanvasNavigation()
        navigation.fill()
        navigation.setZoom(2.75)
        let transform = CanvasMaskTransform(
            sourceSize: CGSize(width: 2400, height: 1200), navigation: navigation,
            viewportSize: CGSize(width: 640, height: 420), backingScale: 2
        )
        let startViewport = try XCTUnwrap(transform.viewportPoint(forSourceNormalized: original.center))
        let viewportDelta = CGSize(width: 10, height: -6)
        let sourceDelta = try XCTUnwrap(
            transform.sourceNormalizedDelta(forViewportDelta: viewportDelta)
        )
        let startSource = try XCTUnwrap(
            transform.sourceNormalizedPoint(forViewport: startViewport)
        )
        let endSource = CGPoint(x: startSource.x + sourceDelta.x, y: startSource.y + sourceDelta.y)

        viewModel.beginMaskGesture(
            at: startSource, radialHandle: .center,
            sourceSize: CGSize(width: 2400, height: 1200)
        )
        viewModel.updateMaskGesture(to: endSource, sourceDelta: sourceDelta)
        viewModel.endMaskGesture()

        let moved = try XCTUnwrap(
            viewModel.document.localAdjustments.first?.components.first?.source.radialDefinition
        )
        XCTAssertEqual(moved.center.x - original.center.x, sourceDelta.x, accuracy: 0.000_000_001)
        XCTAssertEqual(moved.center.y - original.center.y, sourceDelta.y, accuracy: 0.000_000_001)
        XCTAssertEqual(moved.horizontalRadius, original.horizontalRadius, accuracy: 0.000_001)
        XCTAssertEqual(moved.verticalRadius, original.verticalRadius, accuracy: 0.000_001)
        XCTAssertEqual(moved.rotation, original.rotation, accuracy: 0.000_001)
        XCTAssertEqual(moved.feather, original.feather, accuracy: 0.000_001)
        XCTAssertEqual(moved.density, original.density, accuracy: 0.000_001)
        XCTAssertEqual(moved.isInside, original.isInside)

        let movedViewport = try XCTUnwrap(transform.viewportPoint(forSourceNormalized: moved.center))
        XCTAssertEqual(movedViewport.x - startViewport.x, viewportDelta.width, accuracy: 0.000_001)
        XCTAssertEqual(movedViewport.y - startViewport.y, viewportDelta.height, accuracy: 0.000_001)
    }

    func testCancellingRadialCreationDoesNotPersistAnEmptyLayer() {
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())
        viewModel.setMaskTool(.radial)
        viewModel.beginMaskGesture(at: CGPoint(x: 0.2, y: 0.3))
        viewModel.cancelMaskGesture()
        XCTAssertTrue(viewModel.document.localAdjustments.isEmpty)
        XCTAssertNil(viewModel.maskInteractionState.selectedLayerID)
    }

    func testSourceSwitchResetClearsTransientMaskPresentationState() {
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())
        viewModel.createMask(.brush)
        let layerID = viewModel.document.localAdjustments[0].id
        viewModel.maskInteractionState.toggleSolo(layerID: layerID)
        viewModel.maskInteractionState.beginDraft(viewModel.document.localAdjustments[0])

        viewModel.maskInteractionState.resetForSource()

        XCTAssertNil(viewModel.maskInteractionState.selectedLayerID)
        XCTAssertNil(viewModel.maskInteractionState.soloLayerID)
        XCTAssertFalse(viewModel.maskInteractionState.hasDraft)
    }

    func testOverlayPresentationControlsDoNotChangeDocumentOrUndoHistory() throws {
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())
        viewModel.createMask(.brush)
        let before = viewModel.document
        let undoBefore = viewModel.undoDepth
        let layerID = try XCTUnwrap(viewModel.maskInteractionState.selectedLayerID)

        viewModel.maskInteractionState.showOverlay = false
        viewModel.maskInteractionState.overlayInspection = .grayscale
        viewModel.maskInteractionState.overlayColor = .blue
        viewModel.maskInteractionState.overlayOpacity = 0.08
        viewModel.maskInteractionState.toggleSolo(layerID: layerID)

        XCTAssertEqual(viewModel.document, before)
        XCTAssertEqual(viewModel.undoDepth, undoBefore)
        XCTAssertEqual(viewModel.maskInteractionState.soloLayerID, layerID)
    }

    func testProductionCreationExposesEverySupportedSmartKindAndPersistsIt() throws {
        XCTAssertEqual(MaskCreationKind.smartKinds, [
            .subject, .person, .face, .foreground, .background,
        ])

        let viewModel = makeAppViewModel(engine: FakeRenderEngine())
        for kind in MaskCreationKind.smartKinds {
            viewModel.createMask(kind)
        }

        let layers = viewModel.document.localAdjustments
        XCTAssertEqual(layers.count, MaskCreationKind.smartKinds.count)
        XCTAssertEqual(
            layers.compactMap { $0.components.first?.source.semanticDefinition?.target },
            MaskCreationKind.smartKinds.compactMap(\.semanticTarget)
        )

        let reopened = try JSONDecoder().decode(
            EditDocument.self, from: JSONEncoder().encode(viewModel.document)
        )
        XCTAssertEqual(reopened.localAdjustments, layers)
    }

    func testSmartCreationFailureWithoutSupportedSourceDoesNotCreateAnInertLayer() {
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())

        viewModel.createSmartMask(.subject)

        XCTAssertTrue(viewModel.document.localAdjustments.isEmpty)
        XCTAssertEqual(
            viewModel.maskingState.resolutionState,
            .unavailable("Smart masks require an open photo with supported analysis.")
        )
    }

    func testSmartActionPreflightsSharedProviderThenSelectsDurableMask() async throws {
        let directory = try Fixtures.makeTempDirectory("ProductionSmartMask")
        defer { try? FileManager.default.removeItem(at: directory) }
        let imageURL = try Fixtures.writeGradientPNG(
            width: 16, height: 12, named: "smart.png", in: directory)
        let store = MaskStore(directory: directory.appendingPathComponent("masks"))
        let editFixture = makeEditPackageFixture()
        try editFixture.register(imageURL)
        let coordinator = PhotoAnalysisCoordinator(
            maskStore: store,
            maskProvider: ProductionSmartMaskProvider(store: store),
            stages: [:]
        )
        let viewModel = makeAppViewModel(
            engine: FakeRenderEngine(),
            editStore: editFixture.store(),
            photoAnalysisCoordinator: coordinator
        )

        viewModel.openImage(url: imageURL)
        try await waitUntil("the photo to load") { viewModel.sourceImage != nil }
        if let assetID = viewModel.maskingAssetID {
            try editFixture.register(assetID: assetID, url: imageURL)
        }
        viewModel.createSmartMask(.subject)
        try await waitUntil("the smart mask to be created") {
            viewModel.document.localAdjustments.count == 1
        }

        let component = try XCTUnwrap(viewModel.document.localAdjustments.first?.components.first)
        XCTAssertEqual(component.source.semanticDefinition?.target, .subject)
        XCTAssertEqual(viewModel.maskingState.selectedComponentID, component.id)
        XCTAssertEqual(viewModel.maskingState.resolutionState, .ready)
    }

    func testRetryingFailedSmartComponentReattemptsTheOriginalLayerAdd() async throws {
        let directory = try Fixtures.makeTempDirectory("SmartMaskComponentRetry")
        defer { try? FileManager.default.removeItem(at: directory) }
        let imageURL = try Fixtures.writeGradientPNG(
            width: 16, height: 12, named: "retry.png", in: directory)
        let store = MaskStore(directory: directory.appendingPathComponent("masks"))
        let editFixture = makeEditPackageFixture()
        try editFixture.register(imageURL)
        let provider = RetryingSmartMaskProvider(store: store)
        let coordinator = PhotoAnalysisCoordinator(
            maskStore: store, maskProvider: provider, stages: [:]
        )
        let viewModel = makeAppViewModel(
            engine: FakeRenderEngine(),
            editStore: editFixture.store(),
            photoAnalysisCoordinator: coordinator
        )

        viewModel.openImage(url: imageURL)
        try await waitUntil("the photo to load") { viewModel.maskingSource != nil }
        if let assetID = viewModel.maskingAssetID {
            try editFixture.register(assetID: assetID, url: imageURL)
        }
        viewModel.createMask(.brush)
        let layerID = try XCTUnwrap(viewModel.document.localAdjustments.first?.id)

        viewModel.addSmartMaskComponent(to: layerID, kind: .subject, mode: .add)
        try await waitUntil("the first component analysis to fail") {
            if case .unavailable = viewModel.maskingState.resolutionState { return true }
            return false
        }
        let firstCallCount = await provider.callCount
        XCTAssertEqual(firstCallCount, 1)
        XCTAssertEqual(viewModel.document.localAdjustments.count, 1)
        XCTAssertEqual(viewModel.document.localAdjustments.first?.components.count, 1)

        viewModel.retryMaskAnalysis()
        try await waitUntil("the retried component to resolve") {
            viewModel.maskingState.resolutionState == .ready
                && viewModel.document.localAdjustments.first?.components.count == 2
        }

        let retryCallCount = await provider.callCount
        XCTAssertEqual(retryCallCount, 2)
        XCTAssertEqual(viewModel.document.localAdjustments.count, 1)
        let layer = try XCTUnwrap(viewModel.document.localAdjustments.first)
        XCTAssertEqual(layer.id, layerID)
        XCTAssertEqual(layer.components.last?.source.semanticDefinition?.target, .subject)
        XCTAssertEqual(layer.components.last?.mode, .add)
    }

    func testInfoAnalysisMaskCreatesAndReusesTheDemonstratedSemanticMask() async throws {
        let directory = tempDirectory!
        let imageURL = try Fixtures.writeGradientPNG(
            width: 16, height: 12, named: "info.png", in: directory)
        let secondURL = try Fixtures.writeGradientPNG(
            width: 16, height: 12, named: "other.png", in: directory)
        let packageURL = directory.appendingPathComponent("InfoMask.kromoralibrary")
        let session = try PortableLibrarySession(at: packageURL)
        _ = try session.importURLs([imageURL, secondURL], duplicatePolicy: .importAnyway)
        let viewModel = makeAppViewModel(
            engine: FakeRenderEngine(), portablePackageURL: packageURL,
            portableLibrarySession: session
        )

        viewModel.collection.loadPortableAssets(try session.materializedAssets())
        await viewModel.collection.scanCompletion()
        let initialIndex = try XCTUnwrap(
            viewModel.collection.items.firstIndex { $0.displayName == imageURL.lastPathComponent }
        )
        viewModel.collection.setSelection(at: initialIndex)
        viewModel.openActiveCollectionImage()
        try await waitUntil("the photo to load") { viewModel.maskingSource != nil }
        let source = try XCTUnwrap(viewModel.maskingSource)
        let assetID = try XCTUnwrap(viewModel.maskingAssetID)
        let size = PixelDimensions(width: 4, height: 4)
        let pixels = try NormalizedMask(size: size, values: Array(repeating: 1, count: 16))
        let key = MaskCacheKey(
            assetID: assetID,
            sourceFingerprint: PhotoAnalysisCoordinator.sourceFingerprint(for: source),
            kind: .subject, quality: .preview, providerVersion: "info-test-1"
        )
        let result = RegionMask(
            kind: .subject,
            bounds: NormalizedRect(x: 0, y: 0, width: 1, height: 1),
            quality: .preview,
            reference: RegionMaskReference(cacheKey: key, size: size),
            confidence: 1,
            coverage: pixels.coverage
        )

        viewModel.useInfoAnalysisMask(.subject, demonstrated: result, pixels: pixels)
        let firstLayer = try XCTUnwrap(viewModel.document.localAdjustments.first)
        let firstComponent = try XCTUnwrap(firstLayer.components.first)
        XCTAssertEqual(firstComponent.source.semanticDefinition?.target, .subject)
        XCTAssertEqual(viewModel.maskingState.selectedLayerID, firstLayer.id)
        XCTAssertEqual(viewModel.maskingState.selectedComponentID, firstComponent.id)
        XCTAssertTrue(viewModel.inspectorState.isMaskingWorkspacePresented)

        viewModel.useInfoAnalysisMask(.subject, demonstrated: result, pixels: pixels)
        XCTAssertEqual(viewModel.document.localAdjustments.count, 1)
        XCTAssertEqual(viewModel.maskingState.selectedLayerID, firstLayer.id)
        XCTAssertEqual(viewModel.maskingState.selectedComponentID, firstComponent.id)

        let flushResult = await viewModel.flushPendingWrites()
        XCTAssertEqual(flushResult, .success)
        await viewModel.shutdown()
        let relaunchedSession = try PortableLibrarySession(at: packageURL)
        let reopened = makeAppViewModel(
            engine: FakeRenderEngine(), portablePackageURL: packageURL,
            portableLibrarySession: relaunchedSession
        )
        reopened.collection.loadPortableAssets(try relaunchedSession.materializedAssets())
        await reopened.collection.scanCompletion()
        let reopenedInitialIndex = try XCTUnwrap(
            reopened.collection.items.firstIndex { $0.displayName == imageURL.lastPathComponent }
        )
        reopened.collection.setSelection(at: reopenedInitialIndex)
        reopened.openActiveCollectionImage()
        try await waitUntil("the persisted mask to reopen") {
            reopened.document.localAdjustments.count == 1
        }
        XCTAssertEqual(
            reopened.document.localAdjustments.first?.components.first?.source.semanticDefinition?.target,
            .subject
        )

        let firstSourceRevision = reopened.maskingSourceRevision
        let secondIndex = try XCTUnwrap(
            reopened.collection.items.firstIndex { $0.displayName == secondURL.lastPathComponent }
        )
        reopened.collection.setSelection(at: secondIndex)
        reopened.openActiveCollectionImage()
        try await waitUntil("the second source to publish") {
            reopened.maskingSource != nil
                && reopened.maskingSource?.cacheFingerprint != source.cacheFingerprint
                && reopened.sourceImage != nil
                && reopened.sourceName == secondURL.lastPathComponent
                && reopened.maskingSourceRevision > firstSourceRevision
        } diagnostics: {
            "sourceName=\(reopened.sourceName), sourceRevision=\(reopened.maskingSourceRevision), "
                + "hasSource=\(reopened.maskingSource != nil), hasImage=\(reopened.sourceImage != nil), "
                + "editStoreStatus=\(reopened.editStoreStatus ?? "nil"), status=\(reopened.statusMessage)"
        }
        XCTAssertTrue(reopened.document.localAdjustments.isEmpty)

        let secondSource = try XCTUnwrap(reopened.maskingSource)
        let secondAssetID = try XCTUnwrap(reopened.maskingAssetID)
        let secondKey = MaskCacheKey(
            assetID: secondAssetID,
            sourceFingerprint: PhotoAnalysisCoordinator.sourceFingerprint(for: secondSource),
            kind: .subject, quality: .preview, providerVersion: "info-test-1"
        )
        let secondResult = RegionMask(
            kind: .subject,
            bounds: NormalizedRect(x: 0, y: 0, width: 1, height: 1),
            quality: .preview,
            reference: RegionMaskReference(cacheKey: secondKey, size: size),
            confidence: 1,
            coverage: pixels.coverage
        )
        reopened.useInfoAnalysisMask(.subject, demonstrated: secondResult, pixels: pixels)
        XCTAssertEqual(
            reopened.document.localAdjustments.first?.components.first?.source.semanticDefinition?.target,
            .subject
        )

        reopened.collection.setSelection(at: reopenedInitialIndex)
        reopened.openActiveCollectionImage()
        try await waitUntil("the first source mask to restore") {
            reopened.sourceName == imageURL.lastPathComponent
                && reopened.maskingSource?.cacheFingerprint == source.cacheFingerprint
                && reopened.document.localAdjustments.count == 1
        }
        XCTAssertEqual(
            reopened.document.localAdjustments.first?.components.first?.source.semanticDefinition?.target,
            .subject
        )
    }

    func testInfoAnalysisMaskRejectsAResultFromAnotherSourceWithoutCreatingARecipe() async throws {
        let directory = try Fixtures.makeTempDirectory("InfoStaleSemanticMask")
        defer { try? FileManager.default.removeItem(at: directory) }
        let imageURL = try Fixtures.writeGradientPNG(
            width: 16, height: 12, named: "info-stale.png", in: directory)
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())
        viewModel.openImage(url: imageURL)
        try await waitUntil("the photo to load") { viewModel.maskingSource != nil }
        let source = try XCTUnwrap(viewModel.maskingSource)
        let assetID = try XCTUnwrap(viewModel.maskingAssetID)
        let size = PixelDimensions(width: 4, height: 4)
        let key = MaskCacheKey(
            assetID: assetID,
            sourceFingerprint: PhotoSourceFingerprint.data(Data("different".utf8)),
            kind: .person, quality: .preview, providerVersion: "info-test-1"
        )
        let result = RegionMask(
            kind: .person,
            bounds: NormalizedRect(x: 0, y: 0, width: 1, height: 1),
            quality: .preview,
            reference: RegionMaskReference(cacheKey: key, size: size),
            confidence: 1,
            coverage: 1
        )

        let pixels = try NormalizedMask(size: size, values: Array(repeating: 1, count: 16))
        viewModel.useInfoAnalysisMask(.person, demonstrated: result, pixels: pixels)

        XCTAssertTrue(viewModel.document.localAdjustments.isEmpty)
        XCTAssertEqual(
            viewModel.maskingState.resolutionState,
            .unavailable("The demonstrated Person result is no longer available for this photo.")
        )
        XCTAssertFalse(viewModel.inspectorState.isMaskingWorkspacePresented)
        _ = source // Keep the active source assertion explicit for this identity-focused test.
    }

    func testInfoAnalysisMaskRejectsALowConfidenceResultWithoutCreatingARecipe() async throws {
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())
        let directory = try Fixtures.makeTempDirectory("InfoLowConfidenceSemanticMask")
        defer { try? FileManager.default.removeItem(at: directory) }
        let imageURL = try Fixtures.writeGradientPNG(
            width: 16, height: 12, named: "info-low-confidence.png", in: directory)
        viewModel.openImage(url: imageURL)
        try await waitUntil("the photo to load") { viewModel.maskingSource != nil }
        let source = try XCTUnwrap(viewModel.maskingSource)
        let assetID = try XCTUnwrap(viewModel.maskingAssetID)
        let size = PixelDimensions(width: 4, height: 4)
        let pixels = try NormalizedMask(size: size, values: Array(repeating: 1, count: 16))
        let key = MaskCacheKey(
            assetID: assetID,
            sourceFingerprint: PhotoAnalysisCoordinator.sourceFingerprint(for: source),
            kind: .subject, quality: .preview, providerVersion: "info-test-1"
        )
        let result = RegionMask(
            kind: .subject,
            bounds: NormalizedRect(x: 0, y: 0, width: 1, height: 1),
            quality: .preview,
            reference: RegionMaskReference(cacheKey: key, size: size),
            confidence: 0.1,
            coverage: pixels.coverage
        )

        viewModel.useInfoAnalysisMask(.subject, demonstrated: result, pixels: pixels)

        XCTAssertTrue(viewModel.document.localAdjustments.isEmpty)
        XCTAssertEqual(
            viewModel.maskingState.resolutionState,
            .unavailable("The demonstrated Subject result is no longer available for this photo.")
        )
        XCTAssertFalse(viewModel.inspectorState.isMaskingWorkspacePresented)
    }
}

private actor ProductionSmartMaskProvider: SemanticMaskProviding {
    private let store: MaskStore

    init(store: MaskStore) { self.store = store }

    func mask(for kind: SemanticMaskKind, image: AnalysisImage, quality: MaskQuality) async throws -> RegionMask {
        let pixels = try NormalizedMask(
            size: image.dimensions,
            values: Array(repeating: 1, count: image.dimensions.width * image.dimensions.height)
        )
        let assetID = image.assetID ?? PhotoAnalysisCoordinator.assetID(for: image.source)
        let key = MaskCacheKey(
            assetID: assetID,
            sourceFingerprint: PhotoAnalysisCoordinator.sourceFingerprint(for: image.source),
            kind: kind,
            quality: quality,
            providerVersion: "production-test-1"
        )
        let reference = try await store.store(pixels, for: key, quality: quality)
        return RegionMask(
            kind: kind,
            bounds: NormalizedRect(x: 0, y: 0, width: 1, height: 1),
            quality: quality,
            reference: reference,
            confidence: 1,
            coverage: pixels.coverage
        )
    }
}

private enum RetryingSmartMaskProviderError: Error {
    case transient
}

private actor RetryingSmartMaskProvider: SemanticMaskProviding {
    private(set) var callCount = 0
    private let store: MaskStore

    init(store: MaskStore) { self.store = store }

    func mask(for kind: SemanticMaskKind, image: AnalysisImage, quality: MaskQuality) async throws -> RegionMask {
        callCount += 1
        guard callCount > 1 else { throw RetryingSmartMaskProviderError.transient }

        let pixels = try NormalizedMask(
            size: image.dimensions,
            values: Array(repeating: 1, count: image.dimensions.width * image.dimensions.height)
        )
        let assetID = image.assetID ?? PhotoAnalysisCoordinator.assetID(for: image.source)
        let key = MaskCacheKey(
            assetID: assetID,
            sourceFingerprint: PhotoAnalysisCoordinator.sourceFingerprint(for: image.source),
            kind: kind,
            quality: quality,
            providerVersion: "retry-test-1"
        )
        let reference = try await store.store(pixels, for: key, quality: quality)
        return RegionMask(
            kind: kind,
            bounds: NormalizedRect(x: 0, y: 0, width: 1, height: 1),
            quality: quality,
            reference: reference,
            confidence: 1,
            coverage: pixels.coverage
        )
    }
}

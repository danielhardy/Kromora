import XCTest

@testable import LumoKit

@MainActor
final class MaskingWorkspaceTests: XCTestCase {
    func testLayerActionsPersistThroughTheDocumentAndUndo() throws {
        let viewModel = AppViewModel(engine: FakeRenderEngine())

        viewModel.createMask(.linear)
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
        let viewModel = AppViewModel(engine: FakeRenderEngine())

        viewModel.createMask(.linear)
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

    func testSourceSwitchResetClearsTransientMaskPresentationState() {
        let viewModel = AppViewModel(engine: FakeRenderEngine())
        viewModel.createMask(.brush)
        let layerID = viewModel.document.localAdjustments[0].id
        viewModel.maskInteractionState.toggleSolo(layerID: layerID)
        viewModel.maskInteractionState.beginDraft(viewModel.document.localAdjustments[0])

        viewModel.maskInteractionState.resetForSource()

        XCTAssertNil(viewModel.maskInteractionState.selectedLayerID)
        XCTAssertNil(viewModel.maskInteractionState.soloLayerID)
        XCTAssertFalse(viewModel.maskInteractionState.hasDraft)
    }
}

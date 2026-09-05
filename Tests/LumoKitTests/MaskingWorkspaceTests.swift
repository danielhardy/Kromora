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

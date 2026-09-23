import CoreGraphics
import XCTest

@testable import KromoraKit

@MainActor
final class CanvasWorkflowCoordinatorTests: XCTestCase {
    private final class FakeDestination: CanvasWorkflowDestination {
        var canvasWorkflowHasSource = true
        var canvasWorkflowDocument = EditDocument()
        var canvasWorkflowSourceSize = CGSize(width: 1200, height: 800)
        var canvasWorkflowImageExtent: CGRect? = CGRect(x: 0, y: 0, width: 1200, height: 800)
        var canvasWorkflowPreviewInteractionActive = false
        var canvasWorkflowHasCropAdjustments: Bool { !canvasWorkflowDocument.crop.isIdentity }
        private(set) var status: [String] = []
        private(set) var previewCount = 0
        private(set) var cropEntryPreviewCount = 0
        private(set) var interactivePreviewCount = 0
        private(set) var undoGroupingEndCount = 0
        private(set) var navigationChanges: [CanvasNavigationChange] = []
        private(set) var presentation = CropWorkflowPresentation(
            isInspectorPresented: false, inspectorTab: AppViewModel.InspectorTab.info.rawValue,
            isSourceBrowserPresented: true
        )
        private var savedPresentation: CropWorkflowPresentation?

        func updateCanvasWorkflowDocument(_ transform: (inout EditDocument) -> Void) {
            transform(&canvasWorkflowDocument)
        }
        func endCanvasWorkflowUndoGrouping() { undoGroupingEndCount += 1 }
        func setCanvasWorkflowStatus(_ message: String) { status.append(message) }
        func captureCropWorkflowPresentation() -> CropWorkflowPresentation { presentation }
        func prepareCropWorkflowPresentation() {
            savedPresentation = presentation
            presentation = CropWorkflowPresentation(
                isInspectorPresented: true, inspectorTab: AppViewModel.InspectorTab.info.rawValue,
                isSourceBrowserPresented: false
            )
        }
        func restoreCropWorkflowPresentation(_ presentation: CropWorkflowPresentation) {
            self.presentation = presentation
            savedPresentation = nil
        }
        func scheduleCanvasWorkflowPreview() { previewCount += 1 }
        func scheduleCanvasWorkflowCropEntryPreview() { cropEntryPreviewCount += 1 }
        func scheduleCanvasWorkflowInteractivePreview() { interactivePreviewCount += 1 }
        func canvasNavigationDidChange(_ change: CanvasNavigationChange) {
            navigationChanges.append(change)
        }
        func setCanvasWorkflowOriginalVisible(_ visible: Bool) {}
    }

    private func makeCoordinator() -> (CanvasWorkflowCoordinator, FakeDestination) {
        let destination = FakeDestination()
        return (CanvasWorkflowCoordinator(destination: destination), destination)
    }

    func testCropCancelRestoresPresentationWithoutChangingDocument() {
        let (coordinator, destination) = makeCoordinator()
        let original = destination.canvasWorkflowDocument

        coordinator.beginCrop()
        XCTAssertTrue(coordinator.interactionState.isCropToolActive)
        XCTAssertEqual(destination.cropEntryPreviewCount, 1)
        XCTAssertFalse(destination.presentation.isSourceBrowserPresented)
        coordinator.updateCropDraft(CGRect(x: 0.1, y: 0.1, width: 0.5, height: 0.5))
        coordinator.cancelCrop()

        XCTAssertEqual(destination.canvasWorkflowDocument, original)
        XCTAssertFalse(coordinator.interactionState.isCropToolActive)
        XCTAssertTrue(destination.presentation.isSourceBrowserPresented)
        XCTAssertEqual(destination.previewCount, 1)
        XCTAssertEqual(destination.status.last, "Crop cancelled")
    }

    func testCropApplyCommitsDraftAndRotationAsOneDocumentMutation() {
        let (coordinator, destination) = makeCoordinator()
        coordinator.beginCrop()
        coordinator.updateCropDraft(CGRect(x: 0.1, y: 0.2, width: 0.6, height: 0.5))
        coordinator.rotateClockwise()
        coordinator.commitCrop()

        XCTAssertEqual(destination.canvasWorkflowDocument.rotation, .clockwise90)
        let cropRect = try! XCTUnwrap(destination.canvasWorkflowDocument.crop.normalizedRect)
        XCTAssertEqual(cropRect.origin.x, 0.2, accuracy: 0.000_001)
        XCTAssertEqual(cropRect.origin.y, 0.3, accuracy: 0.000_001)
        XCTAssertEqual(cropRect.width, 0.5, accuracy: 0.000_001)
        XCTAssertEqual(cropRect.height, 0.6, accuracy: 0.000_001)
        XCTAssertFalse(coordinator.interactionState.isCropToolActive)
        XCTAssertEqual(destination.status.last, "Crop applied")
    }

    func testRotationOutsideCropPreservesCropContentAndUsesDocumentPath() {
        let (coordinator, destination) = makeCoordinator()
        let crop = CropAdjustments(normalizedRect: CGRect(x: 0.1, y: 0.2, width: 0.5, height: 0.4))
        destination.canvasWorkflowDocument.crop = crop

        coordinator.rotateCounterClockwise()

        XCTAssertEqual(destination.canvasWorkflowDocument.rotation, .counterClockwise90)
        XCTAssertEqual(
            destination.canvasWorkflowDocument.crop,
            crop.rotated(byClockwiseQuarterTurns: -1)
        )
        XCTAssertEqual(destination.undoGroupingEndCount, 1)
    }

    func testCanvasNavigationChangesPresentationWithoutChangingDocument() {
        let (coordinator, destination) = makeCoordinator()
        let original = destination.canvasWorkflowDocument

        coordinator.setCanvasZoom(2)
        coordinator.panCanvas(by: CGSize(width: 10, height: 5), viewportSize: CGSize(width: 600, height: 400))

        XCTAssertEqual(destination.canvasWorkflowDocument, original)
        XCTAssertEqual(destination.navigationChanges.count, 2)
    }
}

import XCTest

@testable import KromoraKit

@MainActor
final class ExportWorkflowCoordinatorTests: XCTestCase {
    private final class Destination: ExportWorkflowDestination {
        var exportSelectionCount = 0
        var exportActiveAssetID: PhotoAssetID?
        var exportSourceName = ""
        var exportSingleRequest: ExportSingleRequest?
        var batch = ExportBatchRequest(items: [], document: EditDocument(), lut: nil)
        var selectedOnlyCalls: [Bool] = []
        var statuses: [String] = []
        var errors: [String] = []

        func exportBatchRequest(selectedOnly: Bool) -> ExportBatchRequest {
            selectedOnlyCalls.append(selectedOnly)
            return batch
        }
        func setExportStatus(_ message: String) { statuses.append(message) }
        func presentExportError(_ message: String) { errors.append(message) }
    }

    private func makeWorkflow() -> (ExportWorkflowCoordinator, Destination) {
        let destination = Destination()
        let workflow = ExportWorkflowCoordinator(
            export: ExportCoordinator(engine: FakeRenderEngine(), photosDelivery: nil),
            destination: destination
        )
        return (workflow, destination)
    }

    func testShareDialogModeSwitchesAtMultipleSelection() {
        XCTAssertEqual(ExportWorkflowCoordinator.shareDialogMode(for: 0), .singlePhoto)
        XCTAssertEqual(ExportWorkflowCoordinator.shareDialogMode(for: 1), .singlePhoto)
        XCTAssertEqual(ExportWorkflowCoordinator.shareDialogMode(for: 2), .selectedPhotos)
    }

    func testSinglePhotoCommandsReportMissingImage() {
        let (workflow, destination) = makeWorkflow()
        workflow.exportDialog()
        workflow.editInExternalEditor()
        workflow.exportOriginalWithSettings()
        workflow.shareDialog()
        XCTAssertEqual(destination.statuses, Array(repeating: "Open an image first", count: 4))
        XCTAssertNil(workflow.pendingShareURL)
        XCTAssertNil(workflow.externalEditorHandoffURL)
    }

    func testSelectedExportAndShareRequireSelectionAndUseSelectedRequest() {
        let (workflow, destination) = makeWorkflow()
        workflow.exportSelectedDialog()
        destination.exportSelectionCount = 3
        workflow.shareDialog()
        XCTAssertEqual(destination.selectedOnlyCalls, [true, true])
        XCTAssertEqual(destination.statuses, [
            "Select at least one photo to export", "Select at least one photo to share",
        ])
    }

    func testUnrelatedCompletionAndFailureLeaveNoHandoffState() {
        let (workflow, _) = makeWorkflow()
        workflow.exportCompleted(at: URL(fileURLWithPath: "/tmp/unrelated.tiff"))
        workflow.exportFailed()
        XCTAssertNil(workflow.pendingShareURL)
        XCTAssertNil(workflow.externalEditorHandoffURL)
    }
}

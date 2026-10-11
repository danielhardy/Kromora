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

    private func makeWorkflow(shareRoot: URL? = nil) -> (ExportWorkflowCoordinator, Destination) {
        let destination = Destination()
        let workflow = ExportWorkflowCoordinator(
            export: ExportCoordinator(engine: FakeRenderEngine(), photosDelivery: nil),
            destination: destination,
            shareRoot: shareRoot ?? FileManager.default.temporaryDirectory
                .appendingPathComponent("KromoraShareTests-\(UUID().uuidString)", isDirectory: true)
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

    private func makeShareRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("KromoraShareTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }

    func testStartingShareCleansAbandonedFilesWithoutTouchingUserExports() throws {
        let root = try makeShareRoot()
        let userFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("user-export-\(UUID().uuidString).tiff")
        try Data([1]).write(to: userFile)
        addTeardownBlock { try? FileManager.default.removeItem(at: userFile) }
        let stale = root.appendingPathComponent("abandoned", isDirectory: true)
        try FileManager.default.createDirectory(at: stale, withIntermediateDirectories: true)
        try Data([1]).write(to: stale.appendingPathComponent("a.tiff"))

        let (workflow, destination) = makeWorkflow(shareRoot: root)
        destination.exportSingleRequest = ExportSingleRequest(
            source: ImageSource(backing: .data(Data([1])), kind: .standard, nativeExtent: CGSize(width: 1, height: 1)),
            document: EditDocument(), lut: nil, baseName: "Photo"
        )
        workflow.shareDialog()

        let pending = try XCTUnwrap(workflow.pendingShareURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: pending.deletingLastPathComponent().path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: stale.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: userFile.path))
    }

    func testStartingAnotherSharePreservesEarlierInFlightDirectory() throws {
        let root = try makeShareRoot()
        let (workflow, destination) = makeWorkflow(shareRoot: root)
        destination.exportSingleRequest = ExportSingleRequest(
            source: ImageSource(backing: .data(Data([1])), kind: .standard, nativeExtent: CGSize(width: 1, height: 1)),
            document: EditDocument(), lut: nil, baseName: "Photo"
        )

        workflow.shareDialog()
        let firstURL = try XCTUnwrap(workflow.pendingShareURL)
        let firstDirectory = firstURL.deletingLastPathComponent()
        workflow.shareDialog()
        let secondURL = try XCTUnwrap(workflow.pendingShareURL)

        XCTAssertNotEqual(firstDirectory, secondURL.deletingLastPathComponent())
        XCTAssertTrue(FileManager.default.fileExists(atPath: firstDirectory.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: secondURL.deletingLastPathComponent().path))

        workflow.exportFailed()
        XCTAssertFalse(FileManager.default.fileExists(atPath: firstDirectory.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: secondURL.deletingLastPathComponent().path))
    }

    func testFailedShareExportRemovesTemporaryFilesAndPendingState() throws {
        let root = try makeShareRoot()
        let directory = root.appendingPathComponent("pending", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let (workflow, destination) = makeWorkflow(shareRoot: root)
        destination.exportSingleRequest = ExportSingleRequest(
            source: ImageSource(backing: .data(Data([1])), kind: .standard, nativeExtent: CGSize(width: 1, height: 1)),
            document: EditDocument(), lut: nil, baseName: "Photo"
        )
        workflow.shareDialog()
        XCTAssertNotNil(workflow.pendingShareURL)

        workflow.exportFailed()

        XCTAssertNil(workflow.pendingShareURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
    }

    func testPickerDismissalAndShareServiceTerminalCallbacksReleaseTheirExports() {
        let picker = NSSharingServicePicker(items: [])
        var dismissalFinished = false
        let dismissalDelegate = SharePickerDelegate { dismissalFinished = true }
        dismissalDelegate.sharingServicePicker(picker, didChoose: nil)
        XCTAssertTrue(dismissalFinished)

        let service = NSSharingService(
            title: "Test",
            image: NSImage(size: NSSize(width: 1, height: 1)),
            alternateImage: nil,
            handler: {}
        )
        var shared = false
        let completionDelegate = SharePickerDelegate { shared = true }
        completionDelegate.sharingService(service, didShareItems: [])
        XCTAssertTrue(shared)

        var failed = false
        let failureDelegate = SharePickerDelegate { failed = true }
        failureDelegate.sharingService(service, didFailToShareItems: [], error: CocoaError(.fileReadUnknown))
        XCTAssertTrue(failed)
    }

    func testCompletionWithoutKeyWindowCleansUpAndReportsStatus() throws {
        try XCTSkipIf(NSApplication.shared.keyWindow != nil, "A key window is present")
        let root = try makeShareRoot()
        let directory = root.appendingPathComponent("ready", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("Photo_share.tiff")
        try Data([1]).write(to: file)
        let (workflow, destination) = makeWorkflow(shareRoot: root)

        workflow.exportCompleted(at: file)  // not pending: ignored
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))

        destination.exportSingleRequest = ExportSingleRequest(
            source: ImageSource(backing: .data(Data([1])), kind: .standard, nativeExtent: CGSize(width: 1, height: 1)), document: EditDocument(), lut: nil, baseName: "Photo"
        )
        workflow.shareDialog()
        let pending = try XCTUnwrap(workflow.pendingShareURL)
        workflow.exportCompleted(at: pending)

        XCTAssertNil(workflow.pendingShareURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
        XCTAssertEqual(destination.statuses.last, "Share unavailable: no window to present the sharing menu")
    }
}

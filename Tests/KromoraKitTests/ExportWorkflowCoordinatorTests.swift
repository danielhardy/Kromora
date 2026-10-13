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

    private func makeWorkflow(
        shareRoot: URL? = nil, sheets: any SheetPresenting = FakeSheets()
    ) -> (ExportWorkflowCoordinator, Destination) {
        let destination = Destination()
        let workflow = ExportWorkflowCoordinator(
            export: ExportCoordinator(engine: FakeRenderEngine(), photosDelivery: nil),
            sheets: sheets,
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

    func testSinglePhotoCommandsReportMissingImage() async {
        let (workflow, destination) = makeWorkflow()
        workflow.exportDialog()
        await workflow.editInExternalEditor().value
        await workflow.exportOriginalWithSettings().value
        workflow.shareDialog()
        XCTAssertEqual(destination.statuses, Array(repeating: "Open an image first", count: 4))
        XCTAssertNil(workflow.externalEditorHandoffURL)
    }

    private func openPhoto(on destination: Destination) {
        destination.exportSingleRequest = ExportSingleRequest(
            source: ImageSource(backing: .data(Data([1])), kind: .standard, nativeExtent: CGSize(width: 1, height: 1)),
            document: EditDocument(), lut: nil, baseName: "Photo"
        )
    }

    func testCancelledExternalEditorSheetLeavesNoHandoff() async {
        let sheets = FakeSheets()
        let (workflow, destination) = makeWorkflow(sheets: sheets)
        openPhoto(on: destination)

        await workflow.editInExternalEditor().value

        XCTAssertEqual(sheets.saveCalls, 1)
        XCTAssertEqual(sheets.lastSavePanel?.title, "Edit in External Editor")
        XCTAssertEqual(sheets.lastSavePanel?.nameFieldStringValue, "Photo_external.tiff")
        XCTAssertNil(workflow.externalEditorHandoffURL)
        XCTAssertTrue(destination.statuses.isEmpty)
    }

    func testAcceptedExternalEditorSheetRecordsTheHandoff() async {
        let sheets = FakeSheets()
        sheets.saveURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("KromoraHandoff-\(UUID().uuidString).tiff")
        let (workflow, destination) = makeWorkflow(sheets: sheets)
        openPhoto(on: destination)

        await workflow.editInExternalEditor().value

        XCTAssertEqual(workflow.externalEditorHandoffURL, sheets.saveURL)
    }

    func testDecliningTheMetadataConfirmationSkipsTheFolderSheet() async {
        let sheets = FakeSheets()
        sheets.confirmResult = false
        let (workflow, destination) = makeWorkflow(sheets: sheets)
        openPhoto(on: destination)

        await workflow.exportOriginalWithSettings().value

        XCTAssertEqual(sheets.confirmCalls, 1)
        XCTAssertEqual(sheets.lastConfirmButtons, ["Keep Original Metadata", "Cancel"])
        XCTAssertEqual(sheets.openCalls, 0)
        XCTAssertTrue(destination.statuses.isEmpty)
    }

    func testCancellingTheBundleFolderSheetStartsNoBundle() async {
        let sheets = FakeSheets()
        let (workflow, destination) = makeWorkflow(sheets: sheets)
        openPhoto(on: destination)

        await workflow.exportOriginalWithSettings().value

        XCTAssertEqual(sheets.openCalls, 1)
        XCTAssertEqual(sheets.lastOpenPanel?.prompt, "Export Bundle")
        XCTAssertTrue(destination.statuses.isEmpty)
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
        XCTAssertNil(workflow.externalEditorHandoffURL)
    }

    private func makeShareRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("KromoraShareTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }

    func testShareOptionsAreMessageSizedHEICNeverTIFFOrFullSize() {
        for format in [ShareExportPolicy.preferredFormat, ShareExportPolicy.fallbackFormat] {
            let options = ShareExportPolicy.options(format: format)
            XCTAssertNotEqual(options.format, .tiff)
            XCTAssertEqual(options.sizing, .longEdge(4096))
            XCTAssertEqual(options.quality, 0.85)
            XCTAssertEqual(options.colorSpace, .current)
            XCTAssertNoThrow(try options.validate())
        }
        XCTAssertEqual(ShareExportPolicy.preferredFormat, .heif)
        XCTAssertEqual(ShareExportPolicy.fallbackFormat, .jpeg)
    }

    func testShareRendersLazilyIntoItsDirectoryAndRemovalLeavesNothing() async throws {
        let root = try makeShareRoot()
        let (workflow, destination) = makeWorkflow(shareRoot: root)
        openPhoto(on: destination)
        let request = try XCTUnwrap(destination.exportSingleRequest)
        let directory = root.appendingPathComponent("render", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let url = try await workflow.renderShareFile(request, assetID: nil, into: directory)

        XCTAssertNotEqual(url.pathExtension.lowercased(), "tif")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        try FileManager.default.removeItem(at: directory)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    }

    func testStartingShareCleansAbandonedFilesWithoutTouchingUserExports() throws {
        try XCTSkipIf(NSApplication.shared.keyWindow != nil, "A key window is present")
        let root = try makeShareRoot()
        let userFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("user-export-\(UUID().uuidString).tiff")
        try Data([1]).write(to: userFile)
        addTeardownBlock { try? FileManager.default.removeItem(at: userFile) }
        let stale = root.appendingPathComponent("abandoned", isDirectory: true)
        try FileManager.default.createDirectory(at: stale, withIntermediateDirectories: true)
        try Data([1]).write(to: stale.appendingPathComponent("a.tiff"))

        let (workflow, destination) = makeWorkflow(shareRoot: root)
        openPhoto(on: destination)
        workflow.shareDialog()

        XCTAssertFalse(FileManager.default.fileExists(atPath: stale.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: userFile.path))
    }

    func testShareWithoutWindowRemovesTemporaryDirectoryAndReportsStatus() throws {
        try XCTSkipIf(NSApplication.shared.keyWindow != nil, "A key window is present")
        let root = try makeShareRoot()
        let (workflow, destination) = makeWorkflow(shareRoot: root)
        openPhoto(on: destination)

        workflow.shareDialog()

        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
        XCTAssertEqual(destination.statuses.last, "Share unavailable: no window to present the sharing menu")
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
}

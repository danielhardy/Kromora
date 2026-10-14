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
        XCTAssertTrue(
            ShareExportPolicy.preferredFormat.utType.conforms(to: ShareExportPolicy.providerContentType)
        )
        XCTAssertTrue(
            ShareExportPolicy.fallbackFormat.utType.conforms(to: ShareExportPolicy.providerContentType)
        )
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

    private func makeMultiShare(
        engine: FakeRenderEngine, root: URL
    ) -> (ExportWorkflowCoordinator, Destination, NSWindow) {
        let destination = Destination()
        let workflow = ExportWorkflowCoordinator(
            export: ExportCoordinator(engine: engine, photosDelivery: nil),
            sheets: FakeSheets(), destination: destination, shareRoot: root
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: [.titled], backing: .buffered, defer: true
        )
        let anchor = NSView(frame: NSRect(x: 0, y: 0, width: 40, height: 20))
        window.contentView?.addSubview(anchor)
        workflow.shareAnchorView = anchor
        destination.exportSelectionCount = 2
        destination.batch = ExportBatchRequest(
            items: [
                ExportCoordinator.BatchItem(url: nil, data: Data([1]), name: "A.dng"),
                ExportCoordinator.BatchItem(url: nil, data: Data([2]), name: "A.cr3"),
            ],
            document: EditDocument(), lut: nil
        )
        return (workflow, destination, window)
    }

    private func loadFile(_ provider: NSItemProvider) async throws -> Data {
        let type = ShareExportPolicy.providerContentType.identifier
        return try await withCheckedThrowingContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: type) { url, error in
                guard let url else {
                    continuation.resume(throwing: error ?? CocoaError(.fileReadUnknown))
                    return
                }
                // The loaded copy is deleted when the callback returns, so read it here.
                continuation.resume(with: Result { try Data(contentsOf: url) })
            }
        }
    }

    private func shareFileExtensions(in root: URL) throws -> [String] {
        let fileManager = FileManager.default
        let directories = try fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        return try directories.flatMap { directory in
            try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                .map(\.pathExtension)
        }.sorted()
    }

    func testMultiPhotoSharePresentsPickerBeforeAnyRenderAndCleansUpAfterSuccess() async throws {
        let root = try makeShareRoot()
        let engine = FakeRenderEngine()
        let (workflow, destination, window) = makeMultiShare(engine: engine, root: root)
        var items: [Any] = []
        var anchor: NSView?
        var shown: NSSharingServicePicker?
        var rendersAtPresentation = -1
        workflow.showPicker = { pickerItems, picker, view in
            items = pickerItems
            anchor = view
            shown = picker
        }
        workflow.shareDialog()
        rendersAtPresentation = await engine.encodeRequests.count

        XCTAssertEqual(rendersAtPresentation, 0)
        XCTAssertTrue(anchor === workflow.shareAnchorView)
        XCTAssertEqual(items.count, 2)
        let providers = try XCTUnwrap(items as? [NSItemProvider])
        XCTAssertEqual(providers.map(\.suggestedName), ["A", "A 2"])
        XCTAssertTrue(providers.allSatisfy { provider in
            provider.registeredTypeIdentifiers.contains(
                ShareExportPolicy.providerContentType.identifier
            )
        })

        for provider in providers {
            _ = try await loadFile(provider)
        }
        XCTAssertEqual(try shareFileExtensions(in: root), ["heic", "heic"])
        let requests = await engine.encodeRequests
        XCTAssertEqual(requests.count, 2)
        XCTAssertTrue(requests.allSatisfy { $0.format == .heif })

        // Finishing the share removes the directory.
        let service = NSSharingService(
            title: "T", image: NSImage(size: NSSize(width: 1, height: 1)),
            alternateImage: nil, handler: {}
        )
        XCTAssertNotEqual(try FileManager.default.contentsOfDirectory(atPath: root.path).count, 0)
        let delegate = try XCTUnwrap(shown?.delegate as? SharePickerDelegate)
        delegate.sharingService(service, didShareItems: [])
        withExtendedLifetime((window, destination)) {}
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
    }

    func testMultiPhotoShareDisambiguatesCaseInsensitiveFilenameCollisions() async throws {
        let root = try makeShareRoot()
        let engine = FakeRenderEngine()
        let (workflow, destination, window) = makeMultiShare(engine: engine, root: root)
        destination.batch = ExportBatchRequest(
            items: [
                ExportCoordinator.BatchItem(url: nil, data: Data([1]), name: "Photo.dng"),
                ExportCoordinator.BatchItem(url: nil, data: Data([2]), name: "photo.cr3"),
            ],
            document: EditDocument(), lut: nil
        )
        var items: [Any] = []
        workflow.showPicker = { pickerItems, _, _ in items = pickerItems }

        workflow.shareDialog()

        let providers = try XCTUnwrap(items as? [NSItemProvider])
        XCTAssertEqual(providers.map(\.suggestedName), ["Photo", "photo 2"])
        for provider in providers {
            _ = try await loadFile(provider)
        }
        XCTAssertEqual(try shareFileExtensions(in: root), ["heic", "heic"])
        withExtendedLifetime((window, destination)) {}
    }

    func testMultiPhotoShareRetriesJPEGWhenHEIFFailsWithoutDroppingItems() async throws {
        let root = try makeShareRoot()
        let engine = FakeRenderEngine()
        await engine.setFailingEncodeFormats([.heif])
        let (workflow, destination, window) = makeMultiShare(engine: engine, root: root)
        var items: [Any] = []
        workflow.showPicker = { pickerItems, _, _ in items = pickerItems }
        workflow.shareDialog()

        let providers = try XCTUnwrap(items as? [NSItemProvider])
        XCTAssertEqual(providers.count, 2)
        for provider in providers {
            // The provider has a generic image type because the concrete format is chosen lazily.
            let data = try await loadFile(provider)
            XCTAssertEqual(data, Data("fake-\(ExportFormat.jpeg.rawValue)".utf8))
        }
        XCTAssertEqual(try shareFileExtensions(in: root), ["jpg", "jpg"])
        let formats = await engine.encodeRequests.map(\.format)
        XCTAssertEqual(formats, [.heif, .jpeg, .heif, .jpeg])
        withExtendedLifetime((window, destination)) {}
    }

    func testMultiPhotoShareCancellationRemovesTheShareDirectory() throws {
        let root = try makeShareRoot()
        let (workflow, destination, window) = makeMultiShare(engine: FakeRenderEngine(), root: root)
        var shown: NSSharingServicePicker?
        workflow.showPicker = { _, picker, _ in shown = picker }
        workflow.shareDialog()
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.path))

        let picker = try XCTUnwrap(shown)
        (picker.delegate as? SharePickerDelegate)?.sharingServicePicker(picker, didChoose: nil)

        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
        withExtendedLifetime((window, destination)) {}
    }

    func testMultiPhotoShareFailureRemovesTheShareDirectory() async throws {
        let root = try makeShareRoot()
        let engine = FakeRenderEngine()
        await engine.setShouldFailEncode(true)
        let (workflow, destination, window) = makeMultiShare(engine: engine, root: root)
        var items: [Any] = []
        var shown: NSSharingServicePicker?
        workflow.showPicker = { pickerItems, picker, _ in
            items = pickerItems
            shown = picker
        }
        workflow.shareDialog()
        let provider = try XCTUnwrap((items as? [NSItemProvider])?.first)

        do {
            _ = try await loadFile(provider)
            XCTFail("Both encodes fail, so loading must fail")
        } catch {}
        let service = NSSharingService(
            title: "T", image: NSImage(size: NSSize(width: 1, height: 1)),
            alternateImage: nil, handler: {}
        )
        let delegate = try XCTUnwrap(shown?.delegate as? SharePickerDelegate)
        delegate.sharingService(service, didFailToShareItems: items, error: CocoaError(.fileReadUnknown))

        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
        withExtendedLifetime((window, destination)) {}
    }

    func testShareWithoutAnchorNeverFallsBackToTheKeyWindow() throws {
        let root = try makeShareRoot()
        let (workflow, destination, window) = makeMultiShare(engine: FakeRenderEngine(), root: root)
        workflow.shareAnchorView = nil
        var presented = false
        workflow.showPicker = { _, _, _ in presented = true }
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }

        workflow.shareDialog()

        XCTAssertFalse(presented)
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

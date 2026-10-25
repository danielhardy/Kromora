import AppKit
import SwiftUI
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

    func testBundleRenderKeepsAssetIdentitySnapshottedBeforeConfirmation() async throws {
        let sheets = FakeSheets()
        let engine = FakeRenderEngine()
        let export = ExportCoordinator(engine: engine, photosDelivery: nil)
        let destination = Destination()
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("KromoraBundleTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        sheets.openURLs = [root]
        let requestedAssetID = PhotoAssetID(rawValue: "requested-asset")
        destination.exportActiveAssetID = requestedAssetID
        destination.exportSourceName = "Photo.png"
        openPhoto(on: destination)
        sheets.confirmHandler = {
            destination.exportActiveAssetID = PhotoAssetID(rawValue: "different-active-asset")
        }
        let workflow = ExportWorkflowCoordinator(
            export: export, sheets: sheets, destination: destination
        )

        await workflow.exportOriginalWithSettings().value

        let requests = await engine.encodeRequests
        XCTAssertEqual(requests.last?.assetID, requestedAssetID)
        XCTAssertTrue(destination.errors.isEmpty)
        XCTAssertTrue(destination.statuses.last?.contains("bundle exported") == true)
    }

    func testSelectedExportAndShareRequireSelectionAndUseSelectedRequest() {
        let (workflow, destination) = makeWorkflow()
        workflow.exportDialog()
        destination.exportSelectionCount = 3
        workflow.shareDialog()
        XCTAssertEqual(destination.selectedOnlyCalls, [true, true])
        XCTAssertEqual(destination.statuses, [
            "Open an image first", "Select at least one photo to share",
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

    func testCancelledShareRenderDoesNotWriteEncodedData() async throws {
        let (workflow, _) = makeWorkflow()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("KromoraShareCancel-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let render = Task {
            try await workflow.renderShareFile(name: "Photo", into: directory) { _ in
                withUnsafeCurrentTask { $0?.cancel() }
                return Data("encoded bytes".utf8)
            }
        }
        do {
            _ = try await render.value
            XCTFail("cancelled Share render must not create a file")
        } catch is CancellationError {
        }

        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), [])
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
        var placementRect: NSRect?
        var shown: NSSharingServicePicker?
        var rendersAtPresentation = -1
        workflow.showPicker = { pickerItems, picker, placement in
            items = pickerItems
            anchor = placement.view
            placementRect = placement.rect
            shown = picker
        }
        workflow.shareDialog()
        rendersAtPresentation = await engine.encodeRequests.count

        XCTAssertEqual(rendersAtPresentation, 0)
        XCTAssertTrue(anchor === workflow.shareAnchorView)
        XCTAssertEqual(placementRect, NSRect(x: 0, y: 0, width: 40, height: 20))
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

    func testCopyServiceWritesDecodableJPEGImagesAndSurvivesCleanup() async throws {
        let root = try makeShareRoot()
        let engine = FakeRenderEngine()
        let (workflow, destination, window) = makeMultiShare(engine: engine, root: root)
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("kromora-test-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        workflow.sharePasteboard = pasteboard
        var shown: NSSharingServicePicker?
        workflow.showPicker = { _, picker, _ in shown = picker }
        workflow.shareDialog()

        let picker = try XCTUnwrap(shown)
        let delegate = try XCTUnwrap(picker.delegate as? SharePickerDelegate)
        let system = NSSharingService(
            title: ShareCopyPolicy.serviceTitle, image: NSImage(size: NSSize(width: 1, height: 1)),
            alternateImage: nil, handler: {}
        )
        let services = delegate.sharingServicePicker(
            picker, sharingServicesForItems: [], proposedSharingServices: [system]
        )
        XCTAssertEqual(services.count, 1)
        XCTAssertFalse(services[0] === system, "the system Copy must be replaced")

        let request = ShareCopyPolicy.options
        XCTAssertEqual(request.format, .jpeg)
        XCTAssertEqual(request.sizing, ShareExportPolicy.options().sizing)

        services[0].perform(withItems: [])
        for _ in 0..<200 where !FileManager.default.fileExists(atPath: root.path) == false {
            try await Task.sleep(for: .milliseconds(10))
        }

        // Cleanup removed the temporary directory, yet the clipboard still holds the images.
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
        let items = try XCTUnwrap(pasteboard.pasteboardItems)
        XCTAssertEqual(items.count, 2)
        for item in items {
            XCTAssertEqual(item.types, [ShareCopyPolicy.pasteboardType])
            XCTAssertNotNil(item.data(forType: ShareCopyPolicy.pasteboardType))
        }
        let requests = await engine.encodeRequests
        XCTAssertEqual(requests.count, 2)
        XCTAssertTrue(requests.allSatisfy { $0.format == .jpeg })
        withExtendedLifetime((window, destination)) {}
    }

    func testLocalizedSystemCopyIsReplacedByASingleJPEGCopy() async throws {
        let root = try makeShareRoot()
        let engine = FakeRenderEngine()
        let bitmap = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 3, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        let jpeg = try XCTUnwrap(bitmap.representation(using: .jpeg, properties: [:]))
        await engine.setEncodedData(jpeg, for: .jpeg)
        let (workflow, destination, window) = makeMultiShare(engine: engine, root: root)
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("kromora-test-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        workflow.sharePasteboard = pasteboard
        workflow.nativeCopyTitles = ["Copier"]
        var shown: NSSharingServicePicker?
        workflow.showPicker = { _, picker, _ in shown = picker }
        workflow.shareDialog()

        let picker = try XCTUnwrap(shown)
        let delegate = try XCTUnwrap(picker.delegate as? SharePickerDelegate)
        let system = NSSharingService(
            title: "Copier", image: NSImage(size: NSSize(width: 1, height: 1)),
            alternateImage: nil, handler: {}
        )
        let other = NSSharingService(
            title: "Mail", image: NSImage(size: NSSize(width: 1, height: 1)),
            alternateImage: nil, handler: {}
        )
        let services = delegate.sharingServicePicker(
            picker, sharingServicesForItems: [], proposedSharingServices: [system, other]
        )
        XCTAssertEqual(services.count, 2)
        XCTAssertFalse(services[0] === system, "the system Copy must be replaced")
        XCTAssertEqual(services[0].title, "Copier")
        XCTAssertTrue(services[1] === other, "other proposed services must be preserved")
        XCTAssertEqual(services.filter { $0.title == "Copier" }.count, 1)

        let request = ShareCopyPolicy.options
        XCTAssertEqual(request.format, .jpeg)
        XCTAssertEqual(request.sizing, ShareExportPolicy.options().sizing)

        services[0].perform(withItems: [])
        for _ in 0..<200 where !FileManager.default.fileExists(atPath: root.path) == false {
            try await Task.sleep(for: .milliseconds(10))
        }

        // Cleanup removed the temporary directory, yet the clipboard still holds the images.
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
        let items = try XCTUnwrap(pasteboard.pasteboardItems)
        XCTAssertEqual(items.count, 2)
        for item in items {
            XCTAssertEqual(item.types, [ShareCopyPolicy.pasteboardType])
            let data = try XCTUnwrap(item.data(forType: ShareCopyPolicy.pasteboardType))
            let decoded = try XCTUnwrap(NSBitmapImageRep(data: data))
            XCTAssertEqual(decoded.pixelsWide, 4)
            XCTAssertEqual(decoded.pixelsHigh, 3)
        }
        let requests = await engine.encodeRequests
        XCTAssertEqual(requests.count, 2)
        XCTAssertTrue(requests.allSatisfy { $0.format == .jpeg })
        withExtendedLifetime((window, destination)) {}
    }

    func testCopyStopsRenderingAndLeavesClipboardUntouchedPastByteLimit() async throws {
        let root = try makeShareRoot()
        let (workflow, destination, window) = makeMultiShare(engine: FakeRenderEngine(), root: root)
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("kromora-test-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        workflow.sharePasteboard = pasteboard
        pasteboard.clearContents()
        pasteboard.setString("previous", forType: .string)

        var encoded = 0
        let items = (0..<5).map { _ in
            ShareCopyItem { _ in
                encoded += 1
                return Data(count: 100)
            }
        }

        await workflow.copyToPasteboard(items, byteLimit: 250)

        XCTAssertEqual(encoded, 3, "rendering stops at the first image that crosses the limit")
        XCTAssertEqual(pasteboard.string(forType: .string), "previous")
        XCTAssertNil(pasteboard.pasteboardItems?.first?.data(forType: ShareCopyPolicy.pasteboardType))

        encoded = 0
        await workflow.copyToPasteboard(Array(items.prefix(2)), byteLimit: 250)
        XCTAssertEqual(encoded, 2)
        XCTAssertEqual(pasteboard.pasteboardItems?.count, 2)
        withExtendedLifetime((window, destination)) {}
    }

    func testPasteboardWriterAdvertisesImageTypeWithDecodableBytes() throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("kromora-test-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        let rep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 3, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        let jpeg = try XCTUnwrap(rep.representation(using: .jpeg, properties: [:]))

        XCTAssertTrue(SharePasteboardWriter.write([jpeg], to: pasteboard))
        XCTAssertFalse(SharePasteboardWriter.write([], to: pasteboard) )
        let data = try XCTUnwrap(pasteboard.pasteboardItems?.first?.data(forType: ShareCopyPolicy.pasteboardType))
        let decoded = try XCTUnwrap(NSBitmapImageRep(data: data))
        XCTAssertEqual(decoded.pixelsWide, 4)
        XCTAssertEqual(decoded.pixelsHigh, 3)
        XCTAssertNil(pasteboard.string(forType: .fileURL))
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

    func testShareWithoutAnchorFallsBackToTheKeyWindow() throws {
        let root = try makeShareRoot()
        let (workflow, destination, window) = makeMultiShare(engine: FakeRenderEngine(), root: root)
        workflow.shareAnchorView = nil
        var presentedIn: NSView?
        workflow.showPicker = { _, _, placement in presentedIn = placement.view }
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        try XCTSkipIf(NSApplication.shared.keyWindow !== window, "Window did not become key")

        workflow.shareDialog()

        XCTAssertTrue(presentedIn === window.contentView)
        XCTAssertNotEqual(destination.statuses.last, "Share unavailable: no window to present the sharing menu")
    }

    func testZeroSizeAnchorFallsBackToTheKeyWindowRatherThanAnchoringAtTheEdge() throws {
        let root = try makeShareRoot()
        let (workflow, _, window) = makeMultiShare(engine: FakeRenderEngine(), root: root)
        let anchor = try XCTUnwrap(workflow.shareAnchorView)
        XCTAssertNotNil(SharePickerPlacement(anchor: anchor))
        anchor.frame = .zero
        XCTAssertNil(SharePickerPlacement(anchor: anchor))
        var placement: SharePickerPlacement?
        workflow.showPicker = { _, _, value in placement = value }
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        try XCTSkipIf(NSApplication.shared.keyWindow !== window, "Window did not become key")

        workflow.shareDialog()

        XCTAssertTrue(placement?.view === window.contentView)
    }

    func testDetachedAnchorFallsBackToTheKeyWindow() throws {
        let root = try makeShareRoot()
        let (workflow, _, window) = makeMultiShare(engine: FakeRenderEngine(), root: root)
        let anchor = try XCTUnwrap(workflow.shareAnchorView)
        anchor.removeFromSuperview()
        var presentedIn: NSView?
        workflow.showPicker = { _, _, placement in presentedIn = placement.view }
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        try XCTSkipIf(NSApplication.shared.keyWindow !== window, "Window did not become key")

        workflow.shareDialog()

        XCTAssertTrue(presentedIn === window.contentView)
    }

    func testShareAnchorTracksItsHostMovingBetweenWindows() throws {
        let root = try makeShareRoot()
        let (workflow, destination) = makeWorkflow(shareRoot: root)
        destination.exportSelectionCount = 1
        openPhoto(on: destination)
        let host = NSHostingView(rootView: ShareAnchorView(workflow: workflow))
        host.frame = NSRect(x: 0, y: 0, width: 40, height: 20)
        host.layoutSubtreeIfNeeded()

        let firstWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: [], backing: .buffered, defer: true
        )
        firstWindow.isReleasedWhenClosed = false
        defer {
            host.removeFromSuperview()
            firstWindow.close()
        }
        firstWindow.contentView?.addSubview(host)
        firstWindow.contentView?.layoutSubtreeIfNeeded()
        host.layoutSubtreeIfNeeded()
        drainMainActor()

        let firstAnchor = try XCTUnwrap(workflow.shareAnchorView)
        XCTAssertTrue(firstAnchor.window === firstWindow)

        host.removeFromSuperview()
        XCTAssertNil(workflow.shareAnchorView)

        let secondWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: [], backing: .buffered, defer: true
        )
        secondWindow.isReleasedWhenClosed = false
        defer { secondWindow.close() }
        secondWindow.contentView?.addSubview(host)
        secondWindow.contentView?.layoutSubtreeIfNeeded()
        host.layoutSubtreeIfNeeded()
        drainMainActor()

        let secondAnchor = try XCTUnwrap(workflow.shareAnchorView)
        XCTAssertTrue(secondAnchor.window === secondWindow)
        XCTAssertTrue(firstAnchor === secondAnchor)

        var presentedItems: [Any] = []
        var presentedIn: NSView?
        workflow.showPicker = { items, _, placement in
            presentedItems = items
            presentedIn = placement.view
        }
        workflow.shareDialog()
        XCTAssertTrue(presentedIn === secondAnchor)
        XCTAssertEqual(presentedItems.count, 1)

        destination.exportSelectionCount = 2
        destination.batch = ExportBatchRequest(
            items: [
                ExportCoordinator.BatchItem(url: nil, data: Data([1]), name: "A.dng"),
                ExportCoordinator.BatchItem(url: nil, data: Data([2]), name: "B.dng"),
            ],
            document: EditDocument(), lut: nil
        )
        workflow.shareDialog()
        XCTAssertTrue(presentedIn === secondAnchor)
        XCTAssertEqual(presentedItems.count, 2)

        host.removeFromSuperview()
        XCTAssertNil(workflow.shareAnchorView)
        firstWindow.close()
        secondWindow.close()
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

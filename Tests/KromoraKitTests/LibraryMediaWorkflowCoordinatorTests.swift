import Foundation
import UniformTypeIdentifiers
import XCTest
import os.lock
@testable import KromoraKit

@MainActor
final class LibraryMediaWorkflowCoordinatorTests: XCTestCase {
    func testScannedRemovableSelectionIsPublishedAsAValueRequest() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("kromora-library-media-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let image = directory.appendingPathComponent("card-shot.jpg")
        try Data([0xFF, 0xD8, 0xFF, 0xD9]).write(to: image)
        let volume = MediaVolume(name: "Card", url: directory)
        let file = MediaVolumeFile(url: image)
        let provider = WorkflowMediaProvider(
            volumes: [volume], result: .success(MediaVolumeScanResult(files: [file], warnings: []))
        )
        let coordinator = LibraryMediaWorkflowCoordinator(
            provider: provider, fileDialog: WorkflowFileDialog()
        )
        var request: RemovableMediaImportRequest?
        coordinator.onImportRequest = { request = $0 }

        coordinator.openRemovableMedia(volume)
        try await waitUntil { !coordinator.isRemovableMediaScanning }
        try FileManager.default.removeItem(at: image)
        coordinator.importSelectedRemovableMedia()
        try await waitUntil { request != nil }

        XCTAssertEqual(request?.volume, volume)
        XCTAssertEqual(request?.files, [file])
        XCTAssertEqual(coordinator.removableMediaImportProgress?.imported, 0)
        XCTAssertEqual(coordinator.removableMediaImportProgress?.processed, 0)
        await coordinator.shutdown()
    }

    func testStreamedScanFillsSelectorProgressivelyAndKeepsSelectionAndOrder() async throws {
        let volume = MediaVolume(name: "Card", url: FileManager.default.temporaryDirectory)
        func file(_ name: String, _ seconds: TimeInterval) -> MediaVolumeFile {
            MediaVolumeFile(
                url: URL(fileURLWithPath: "/Volumes/Card/\(name)"),
                captureDate: Date(timeIntervalSince1970: seconds)
            )
        }
        let first = [file("c.jpg", 300), file("a.jpg", 100)]
        let second = [file("b.jpg", 200), file("d.jpg", 400)]
        let provider = StreamingWorkflowMediaProvider()
        let coordinator = LibraryMediaWorkflowCoordinator(
            provider: provider, fileDialog: WorkflowFileDialog()
        )

        coordinator.openRemovableMedia(volume)
        provider.send(.init(files: first, warnings: ["first warning"]))
        try await waitUntil { coordinator.removableMediaFiles.count == 2 }

        // Images are visible and selectable while the card is still being read.
        XCTAssertTrue(coordinator.isRemovableMediaScanning)
        XCTAssertEqual(coordinator.removableMediaFiles.map(\.filename), ["a.jpg", "c.jpg"])
        XCTAssertEqual(coordinator.selectedRemovableMediaFiles.count, 2)
        let c = first[0], a = first[1]
        coordinator.toggleRemovableMediaSelection(a)        // deselect a.jpg; anchor a
        coordinator.selectRemovableMediaRange(to: c)        // reselect a…c
        coordinator.toggleRemovableMediaSelection(a)        // deselect a.jpg again

        provider.send(.init(files: second, warnings: []))
        try await waitUntil { coordinator.removableMediaFiles.count == 4 }

        // Arrivals merge into capture-time order; the user's choices are not overridden.
        XCTAssertEqual(
            coordinator.removableMediaFiles.map(\.filename), ["a.jpg", "b.jpg", "c.jpg", "d.jpg"]
        )
        XCTAssertTrue(coordinator.isRemovableMediaScanning)
        XCTAssertEqual(coordinator.selectedRemovableMediaFiles.map(\.filename), ["c.jpg"])
        XCTAssertEqual(coordinator.removableMediaWarnings, ["first warning"])

        provider.finish()
        try await waitUntil { !coordinator.isRemovableMediaScanning }
        XCTAssertEqual(
            coordinator.removableMediaFiles.map(\.filename), ["a.jpg", "b.jpg", "c.jpg", "d.jpg"]
        )
        await coordinator.shutdown()
    }

    func testStreamedScanSelectsArrivalsUntilTheUserTakesOverSelection() async throws {
        let volume = MediaVolume(name: "Card", url: FileManager.default.temporaryDirectory)
        let a = MediaVolumeFile(url: URL(fileURLWithPath: "/Volumes/Card/a.jpg"))
        let b = MediaVolumeFile(url: URL(fileURLWithPath: "/Volumes/Card/b.jpg"))
        let provider = StreamingWorkflowMediaProvider()
        let coordinator = LibraryMediaWorkflowCoordinator(
            provider: provider, fileDialog: WorkflowFileDialog()
        )

        coordinator.openRemovableMedia(volume)
        provider.send(.init(files: [a], warnings: []))
        try await waitUntil { coordinator.removableMediaFiles.count == 1 }
        XCTAssertEqual(coordinator.selectedRemovableMediaFiles, [a])
        provider.send(.init(files: [b], warnings: []))
        try await waitUntil { coordinator.removableMediaFiles.count == 2 }
        XCTAssertEqual(coordinator.selectedRemovableMediaFiles.count, 2)

        provider.finish()
        try await waitUntil { !coordinator.isRemovableMediaScanning }
        await coordinator.shutdown()
    }

    func testLibraryMembersAreTaggedProgressivelyAndLeftOutOfDefaultSelection() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("kromora-library-tags-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        func make(_ name: String, _ byte: UInt8) throws -> MediaVolumeFile {
            let url = directory.appendingPathComponent(name)
            try Data(repeating: byte, count: 64).write(to: url)
            return MediaVolumeFile(url: url)
        }
        let known = try make("known.jpg", 1), touched = try make("touched.jpg", 1)
        let new = try make("new.jpg", 2)
        let hash = try XCTUnwrap(LibraryMembershipMatcher.contentHash(of: known.url))
        let provider = StreamingWorkflowMediaProvider()
        let coordinator = LibraryMediaWorkflowCoordinator(
            provider: provider, fileDialog: WorkflowFileDialog()
        )
        coordinator.libraryMatcherLoader = { LibraryMembershipMatcher(knownHashes: [hash]) }

        coordinator.openRemovableMedia(MediaVolume(name: "Card", url: directory))
        provider.send(.init(files: [known, touched, new], warnings: []))
        try await waitUntil { coordinator.removableMediaLibraryChecked == 3 }
        XCTAssertEqual(coordinator.removableMediaInLibrary, [known.id, touched.id])
        XCTAssertEqual(coordinator.selectedRemovableMediaFiles, [new])

        // Select All keeps matched items out; an explicit click selects one for re-import.
        coordinator.selectAllRemovableMedia()
        XCTAssertEqual(coordinator.selectedRemovableMediaFiles, [new])
        coordinator.toggleRemovableMediaSelection(touched)
        XCTAssertEqual(Set(coordinator.selectedRemovableMediaFiles.map(\.id)), [touched.id, new.id])

        coordinator.hidesInLibraryRemovableMedia = true
        XCTAssertEqual(coordinator.visibleRemovableMediaFiles, [new])

        provider.finish()
        try await waitUntil { !coordinator.isCheckingRemovableMediaLibrary }
        await coordinator.shutdown()
    }

    func testClosingSelectorMidScanCancelsTheStreamAndKeepsPartialListFromGrowing() async throws {
        let volume = MediaVolume(name: "Card", url: FileManager.default.temporaryDirectory)
        let a = MediaVolumeFile(url: URL(fileURLWithPath: "/Volumes/Card/a.jpg"))
        let provider = StreamingWorkflowMediaProvider()
        let coordinator = LibraryMediaWorkflowCoordinator(
            provider: provider, fileDialog: WorkflowFileDialog()
        )

        coordinator.openRemovableMedia(volume)
        provider.send(.init(files: [a], warnings: []))
        try await waitUntil { coordinator.removableMediaFiles.count == 1 }
        coordinator.cancelRemovableMediaImport()
        try await waitUntil { provider.wasTerminated }

        provider.send(.init(files: [MediaVolumeFile(url: URL(fileURLWithPath: "/Volumes/Card/late.jpg"))], warnings: []))
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(coordinator.removableMediaFiles.count, 1)
        XCTAssertFalse(coordinator.isRemovableMediaScanning)
        XCTAssertFalse(coordinator.isRemovableMediaSelectorPresented)
        await coordinator.shutdown()
    }

    func testScanErrorAfterPartialResultsKeepsFoundImagesAndReportsTheError() async throws {
        let volume = MediaVolume(name: "Card", url: FileManager.default.temporaryDirectory)
        let a = MediaVolumeFile(url: URL(fileURLWithPath: "/Volumes/Card/a.jpg"))
        let provider = StreamingWorkflowMediaProvider()
        let coordinator = LibraryMediaWorkflowCoordinator(
            provider: provider, fileDialog: WorkflowFileDialog()
        )

        coordinator.openRemovableMedia(volume)
        provider.send(.init(files: [a], warnings: []))
        try await waitUntil { coordinator.removableMediaFiles.count == 1 }
        provider.finish(throwing: MediaVolumeError.volumeRemoved("Card"))
        try await waitUntil { !coordinator.isRemovableMediaScanning }

        XCTAssertEqual(coordinator.removableMediaFiles, [a])
        XCTAssertTrue(coordinator.removableMediaWarnings.contains("Card is no longer available."))
        await coordinator.shutdown()
    }

    func testDialogAndDropRouteOutsideTheDestinationPolicy() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("kromora-source-folder-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let image = folder.appendingPathComponent("shot.jpg")
        try Data([0xFF, 0xD8, 0xFF, 0xD9]).write(to: image)
        let dialog = WorkflowFileDialog(folder: folder)
        let coordinator = LibraryMediaWorkflowCoordinator(
            provider: WorkflowMediaProvider(volumes: [], result: .success(.init(files: [], warnings: []))),
            fileDialog: dialog
        )
        var selectedFolder: URL?
        var selectedImage: URL?
        coordinator.onSourceFolder = { url, _ in selectedFolder = url }
        coordinator.onImageURL = { url, _ in selectedImage = url }

        coordinator.chooseSourceFolder(startingAt: nil)
        coordinator.handleDroppedURL(folder)
        coordinator.handleDroppedURL(image)

        XCTAssertEqual(selectedFolder, folder)
        XCTAssertEqual(selectedImage, image)
    }

    func testRemovableMediaPanelGrantSurvivesPreflightAndMovesToImportRequest() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("kromora-removable-grant-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let image = directory.appendingPathComponent("card-shot.jpg")
        try Data([0xFF, 0xD8, 0xFF, 0xD9]).write(to: image)
        let rawVolume = MediaVolume(name: "Card", url: directory, requiresAccessGrant: true)
        let file = MediaVolumeFile(url: image)
        let provider = AccessGrantWorkflowMediaProvider(
            result: .init(files: [file], warnings: [])
        )
        let coordinator = LibraryMediaWorkflowCoordinator(
            provider: provider, fileDialog: WorkflowFileDialog(folder: directory)
        )
        var request: RemovableMediaImportRequest?
        coordinator.onImportRequest = { request = $0 }

        coordinator.openRemovableMedia(rawVolume)
        try await waitUntil { !coordinator.isRemovableMediaScanning }
        XCTAssertEqual(coordinator.removableMediaFiles, [file])
        XCTAssertEqual(provider.accessObservations.withLock { $0 }, [false, true])

        coordinator.importSelectedRemovableMedia()
        try await waitUntil { request != nil }
        XCTAssertNotNil(request?.access)
        XCTAssertEqual(request?.files, [file])

        await coordinator.shutdown()
        request?.access?.release()
    }

    private func waitUntil(
        _ predicate: @escaping @MainActor () -> Bool
    ) async throws {
        for _ in 0..<100 {
            if predicate() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for coordinator state")
    }
}

private struct WorkflowMediaProvider: MediaVolumeProviding {
    let volumes: [MediaVolume]
    let result: Result<MediaVolumeScanResult, MediaVolumeError>

    func discover() async -> [MediaVolume] { volumes }

    func scan(_ volume: MediaVolume) async throws -> MediaVolumeScanResult {
        try result.get()
    }
}

/// A provider whose scan stays open until the test sends batches, so progressive arrival is
/// observable between them. The stream exists from construction, so a batch sent before the
/// coordinator starts iterating is buffered rather than lost.
private final class StreamingWorkflowMediaProvider: MediaVolumeProviding {
    private let stream: AsyncThrowingStream<MediaVolumeScanBatch, Error>
    private let continuation: AsyncThrowingStream<MediaVolumeScanBatch, Error>.Continuation
    private let terminated = OSAllocatedUnfairLock(initialState: false)

    init() {
        (stream, continuation) = AsyncThrowingStream.makeStream()
        continuation.onTermination = { [terminated] _ in terminated.withLock { $0 = true } }
    }

    var wasTerminated: Bool { terminated.withLock { $0 } }

    func discover() async -> [MediaVolume] { [] }

    func scan(_ volume: MediaVolume) async throws -> MediaVolumeScanResult {
        MediaVolumeScanResult(files: [], warnings: [])
    }

    func scanBatches(
        _ volume: MediaVolume,
        access: SecurityScopedResourceAccess?
    ) -> AsyncThrowingStream<MediaVolumeScanBatch, Error> {
        stream
    }

    func send(_ batch: MediaVolumeScanBatch) { continuation.yield(batch) }

    func finish(throwing error: Error? = nil) { continuation.finish(throwing: error) }
}

private struct AccessGrantWorkflowMediaProvider: MediaVolumeProviding {
    let supportsInteractiveAccessGrant = true
    let result: MediaVolumeScanResult
    let accessObservations = OSAllocatedUnfairLock(initialState: [Bool]())

    func discover() async -> [MediaVolume] { [] }

    func scan(_ volume: MediaVolume) async throws -> MediaVolumeScanResult {
        throw MediaVolumeError.permissionDenied(volume.name)
    }

    func scan(
        _ volume: MediaVolume,
        access: SecurityScopedResourceAccess?
    ) async throws -> MediaVolumeScanResult {
        accessObservations.withLock { $0.append(access != nil) }
        guard access != nil else { throw MediaVolumeError.permissionDenied(volume.name) }
        return result
    }
}

@MainActor
private final class WorkflowFileDialog: FileDialogProviding {
    let folder: URL?

    init(folder: URL? = nil) { self.folder = folder }

    func chooseFiles(
        title: String, allowedContentTypes: [UTType], allowsMultipleSelection: Bool,
        startingAt directoryURL: URL?
    ) -> [URL]? { nil }

    func chooseFolder(
        title: String, prompt: String, startingAt directoryURL: URL?, canCreateDirectories: Bool
    ) -> URL? { folder }
}

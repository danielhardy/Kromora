import Foundation
import UniformTypeIdentifiers
import XCTest
import os.lock
@testable import KromoraKit

@MainActor
final class LibraryMediaWorkflowCoordinatorTests: XCTestCase {
    func testValidatedRemovableSelectionIsPublishedAsAValueRequest() async throws {
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
        coordinator.importSelectedRemovableMedia()
        try await waitUntil { request != nil }

        XCTAssertEqual(request?.volume, volume)
        XCTAssertEqual(request?.files, [file])
        XCTAssertEqual(coordinator.removableMediaImportProgress?.imported, 1)
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

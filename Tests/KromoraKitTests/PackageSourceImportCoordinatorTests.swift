import XCTest
import os

@testable import KromoraKit

@MainActor
final class PackageSourceImportCoordinatorTests: XCTestCase {
    private final class Destination: PackageSourceImportDestination {
        var isShuttingDown = false
        var isPackageAvailable = true
        var unavailableReports = 0
        var merges = 0
        var reloads = 0
        var opened: [PortablePhotoAssetID] = []
        var outcomes: [(summary: ImportOutcomeSummary, prefix: String)] = []
        var statuses: [String] = []
        var errors: [String] = []
        var mediaFinishes: [(summary: ImportOutcomeSummary, operationID: UUID)] = []
        var mediaCancels = 0
        var onTerminal: (() -> Void)?

        func reportPackageUnavailable() { unavailableReports += 1 }
        func mergeCommittedImports() { merges += 1 }
        func reloadCollection() throws { reloads += 1 }
        func openAsset(_ assetID: PortablePhotoAssetID) { opened.append(assetID) }
        func presentOutcome(_ summary: ImportOutcomeSummary, prefix: String) {
            outcomes.append((summary, prefix))
            onTerminal?()
        }
        func presentStatus(_ message: String) {
            statuses.append(message)
            onTerminal?()
        }
        func presentError(_ message: String) { errors.append(message) }
        func openImages(
            urls: [URL], operationID: UUID,
            completion: @escaping @MainActor (ImportOutcomeSummary?) -> Void
        ) { completion(nil) }
        func finishMediaImport(_ summary: ImportOutcomeSummary, operationID: UUID) {
            mediaFinishes.append((summary, operationID))
            onTerminal?()
        }
        func cancelMediaImport() { mediaCancels += 1 }
    }

    private struct Harness {
        let directory: URL
        let imports: LibraryImportCoordinator
        let destination: Destination
        let coordinator: PackageSourceImportCoordinator
    }

    private func makeHarness(withPackage: Bool = true) throws -> Harness {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("kromora-source-import-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let session = withPackage
            ? try PortableLibrarySession(
                at: directory.appendingPathComponent("Test.kromoralibrary"),
                scheduler: ImageWorkScheduler())
            : nil
        let imports = LibraryImportCoordinator(
            package: session, isShuttingDown: { false },
            publishProgress: { _ in }, publishStatus: { _ in }
        )
        let destination = Destination()
        let coordinator = PackageSourceImportCoordinator(
            imports: imports, destination: destination,
            receivePromises: { _, _ in .init(urls: [], failures: []) }
        )
        return Harness(
            directory: directory, imports: imports, destination: destination,
            coordinator: coordinator)
    }

    private func makeFolder(in directory: URL, name: String, count: Int) throws -> URL {
        let folder = directory.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for index in 0..<count {
            try Data(repeating: UInt8(index + 1), count: 4096)
                .write(to: folder.appendingPathComponent("p-\(index).dng"))
        }
        return folder
    }

    private func awaitTerminal(
        _ destination: Destination, _ body: () -> Void
    ) async {
        let done = expectation(description: "terminal")
        done.assertForOverFulfill = false
        destination.onTerminal = { done.fulfill() }
        body()
        await fulfillment(of: [done], timeout: 10)
    }

    func testFolderImportOpensFirstImportedAssetAndReportsOutcome() async throws {
        let h = try makeHarness()
        let folder = try makeFolder(in: h.directory, name: "src", count: 3)

        await awaitTerminal(h.destination) { h.coordinator.openSourceFolder(url: folder) }

        XCTAssertEqual(h.destination.reloads, 1)
        XCTAssertEqual(h.destination.opened.count, 1)
        XCTAssertEqual(h.destination.outcomes.count, 1)
        XCTAssertEqual(h.destination.outcomes[0].prefix, "Folder import")
        XCTAssertEqual(h.destination.outcomes[0].summary.imported, 3)
    }

    func testDuplicateOnlyFolderImportStillOpensExistingAsset() async throws {
        let h = try makeHarness()
        let folder = try makeFolder(in: h.directory, name: "src", count: 2)
        await awaitTerminal(h.destination) { h.coordinator.openSourceFolder(url: folder) }
        h.destination.opened.removeAll()
        h.destination.outcomes.removeAll()

        await awaitTerminal(h.destination) { h.coordinator.openSourceFolder(url: folder) }

        XCTAssertEqual(h.destination.opened.count, 1)
        let summary = try XCTUnwrap(h.destination.outcomes.first?.summary)
        XCTAssertEqual(summary.imported, 0)
        XCTAssertEqual(summary.duplicates, 2)
    }

    func testSupersededFolderImportReportsNothing() async throws {
        let h = try makeHarness()
        let folder = try makeFolder(in: h.directory, name: "src", count: 3)

        h.coordinator.openSourceFolder(url: folder)
        _ = h.imports.beginOperation()
        try await Task.sleep(for: .milliseconds(500))

        XCTAssertTrue(h.destination.outcomes.isEmpty)
        XCTAssertTrue(h.destination.opened.isEmpty)
        XCTAssertEqual(h.destination.reloads, 0)
    }

    func testFolderImportFailureIsReportedAndReturned() async throws {
        let h = try makeHarness(withPackage: false)
        let folder = try makeFolder(in: h.directory, name: "src", count: 2)

        let summary = h.coordinator.openSourceFolder(url: folder)

        XCTAssertEqual(summary?.imported, 0)
        XCTAssertEqual(summary?.failureReasons.count, 1)
        XCTAssertEqual(summary?.total, 2)
        XCTAssertEqual(h.destination.outcomes.count, 1)
        XCTAssertEqual(h.destination.outcomes[0].summary, summary)
        XCTAssertTrue(h.destination.opened.isEmpty)
    }

    func testUnavailablePackageReportsAndReleasesAccess() throws {
        let h = try makeHarness(withPackage: false)
        h.destination.isPackageAvailable = false
        let stops = OSAllocatedUnfairLock(initialState: 0)
        let access = SecurityScopedResourceAccess.systemGranted(for: h.directory) { _ in stops.withLock { $0 += 1 } }

        h.coordinator.openSourceFolder(url: h.directory, access: access)

        XCTAssertEqual(h.destination.unavailableReports, 1)
        XCTAssertEqual(stops.withLock { $0 }, 1)
    }

    func testEmptyFolderReleasesSecurityScopedAccessAndReportsStatus() throws {
        let h = try makeHarness()
        let empty = try makeFolder(in: h.directory, name: "empty", count: 0)
        let stops = OSAllocatedUnfairLock(initialState: 0)
        let access = SecurityScopedResourceAccess.systemGranted(for: empty) { _ in stops.withLock { $0 += 1 } }

        let summary = h.coordinator.openSourceFolder(url: empty, access: access)

        XCTAssertNil(summary)
        XCTAssertEqual(stops.withLock { $0 }, 1)
        XCTAssertEqual(h.destination.statuses, ["No supported images were found in empty."])
    }

    func testRemovableMediaImportFinishesWithPreflightSkipsAndOperationID() async throws {
        let h = try makeHarness()
        let folder = try makeFolder(in: h.directory, name: "card", count: 2)
        let volume = MediaVolume(name: "card", url: folder)
        let files = Self.supported(in: folder).map { MediaVolumeFile(url: $0) }
        let request = RemovableMediaImportRequest(
            volume: volume, files: files, totalSelected: files.count + 1)

        await awaitTerminal(h.destination) { h.coordinator.importRemovableMedia(request) }

        XCTAssertEqual(h.destination.mediaFinishes.count, 1)
        XCTAssertEqual(h.destination.mediaFinishes[0].operationID, request.operationID)
        XCTAssertEqual(h.destination.mediaFinishes[0].summary.imported, 2)
        XCTAssertEqual(h.destination.mediaFinishes[0].summary.skipped, 1)
        XCTAssertEqual(h.destination.opened.count, 1)
    }

    func testRemovableMediaImportCancelsSelectorWhenPackageUnavailable() throws {
        let h = try makeHarness()
        h.destination.isPackageAvailable = false
        let request = RemovableMediaImportRequest(
            volume: MediaVolume(name: "v", url: h.directory), files: [])

        h.coordinator.importRemovableMedia(request)

        XCTAssertEqual(h.destination.unavailableReports, 1)
        XCTAssertEqual(h.destination.mediaCancels, 1)
        XCTAssertTrue(h.destination.mediaFinishes.isEmpty)
    }

    func testEmptyPhotosDropReportsZeroOutcome() async throws {
        let h = try makeHarness()

        await awaitTerminal(h.destination) { h.coordinator.importDroppedPromises([]) }

        XCTAssertEqual(
            h.destination.statuses.last,
            "Photos drop complete — 0 imported, 0 duplicate, 0 skipped, 0 failed")
    }

    private static func supported(in folder: URL) -> [URL] {
        PackageSourceImportCoordinator.supportedImageURLs(in: folder)
    }
}

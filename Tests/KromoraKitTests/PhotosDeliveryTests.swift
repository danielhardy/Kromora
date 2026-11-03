import Synchronization
import XCTest
@testable import KromoraKit

@MainActor
final class PhotosDeliveryTests: TempDirectoryTestCase {

    @MainActor
    private final class FakePhotosDelivery: PhotosDelivering {
        struct Call: Equatable {
            let fileURL: URL
            /// The file's bytes when delivery was called, so a test can prove the file was
            /// complete and still present while the transaction ran.
            let fileContents: Data?
            let scopeReleasedDuringCall: Bool
            let filename: String
            let format: ExportFormat
            let options: PhotosExportOptions
        }

        var calls: [Call] = []
        var result = PhotosDeliveryResult(assetAdded: true)
        var error: Error?
        var isScopeReleased: () -> Bool = { false }

        func deliver(
            fileURL: URL,
            filename: String,
            format: ExportFormat,
            options: PhotosExportOptions
        ) async throws -> PhotosDeliveryResult {
            calls.append(Call(
                fileURL: fileURL,
                fileContents: try? Data(contentsOf: fileURL),
                scopeReleasedDuringCall: isScopeReleased(),
                filename: filename, format: format, options: options
            ))
            // Yield so a premature release would be observable after the suspension too.
            await Task.yield()
            calls[calls.count - 1] = Call(
                fileURL: fileURL,
                fileContents: calls[calls.count - 1].fileContents,
                scopeReleasedDuringCall: calls[calls.count - 1].scopeReleasedDuringCall || isScopeReleased(),
                filename: filename, format: format, options: options
            )
            if let error { throw error }
            return result
        }
    }

    private func source() throws -> ImageSource {
        let url = try Fixtures.writeGradientPNG(
            width: 16, height: 16, named: "source.png", in: tempDirectory
        )
        return ImageSource(url: url, nativeExtent: CGSize(width: 16, height: 16))
    }

    private func waitUntil(
        _ description: String, timeout: TimeInterval = 5,
        _ condition: @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline { return XCTFail("timed out waiting for \(description)") }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    func testPhotosOptionsTrimAlbumNamesAndRoundTrip() throws {
        let options = PhotosExportOptions(albumName: "  Kromora Exports  ")
        XCTAssertEqual(options.albumName, "Kromora Exports")
        XCTAssertNil(PhotosExportOptions(albumName: " \n\t ").albumName)

        let encoded = try JSONEncoder().encode(options)
        XCTAssertEqual(try JSONDecoder().decode(PhotosExportOptions.self, from: encoded), options)
        XCTAssertEqual(PhotosAuthorizationState.denied.recoveryMessage?.contains("System Settings"), true)
        XCTAssertEqual(PhotosAuthorizationState.limited.recoveryMessage?.contains("limited"), true)
    }

    func testSinglePhotosFailureLeavesCommittedFileAndReportsSeparateFailure() async throws {
        let photos = FakePhotosDelivery()
        photos.error = PhotosDeliveryError.authorization(.denied)
        let coordinator = ExportCoordinator(engine: FakeRenderEngine(), photosDelivery: photos)
        var statuses: [String] = []
        var errors: [String] = []
        coordinator.onStatus = { statuses.append($0) }
        coordinator.onError = { errors.append($0) }
        let destination = tempDirectory.appendingPathComponent("safe.jpg")

        coordinator.performExport(
            source: try source(),
            document: EditDocument(),
            lut: nil,
            options: ExportOptions(
                format: .jpeg,
                destination: .file(destination),
                photos: PhotosExportOptions(albumName: "Kromora")
            ),
            to: destination
        )
        try await waitUntil("the export") { !coordinator.isExporting }

        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertEqual(photos.calls.count, 1)
        XCTAssertTrue(statuses.contains("Exported: safe.jpg"))
        XCTAssertEqual(errors.count, 1)
        XCTAssertTrue(errors[0].contains("Photos delivery failed"), errors[0])
        XCTAssertTrue(errors[0].contains("file is safe"), errors[0])
        XCTAssertFalse(errors[0].hasPrefix("Export failed:"), errors[0])
    }

    func testSinglePhotosDeliveryReceivesTheCommittedFileURLAndAlbum() async throws {
        let photos = FakePhotosDelivery()
        photos.result = PhotosDeliveryResult(assetAdded: true, albumAdded: true)
        let coordinator = ExportCoordinator(engine: FakeRenderEngine(), photosDelivery: photos)
        coordinator.onError = { XCTFail("unexpected error: \($0)") }
        let destination = tempDirectory.appendingPathComponent("graded.jpg")

        coordinator.performExport(
            source: try source(), document: EditDocument(), lut: nil,
            options: ExportOptions(
                format: .jpeg,
                destination: .file(destination),
                photos: PhotosExportOptions(albumName: "Kromora Exports")
            ),
            to: destination
        )
        try await waitUntil("the export") { !coordinator.isExporting }

        XCTAssertEqual(photos.calls.count, 1)
        let call = try XCTUnwrap(photos.calls.first)
        XCTAssertEqual(call.fileURL, destination)
        XCTAssertFalse(try Data(contentsOf: destination).isEmpty)
        XCTAssertEqual(call.fileContents, try Data(contentsOf: destination))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path), "export is retained")
        XCTAssertEqual(call.filename, "graded.jpg")
        XCTAssertEqual(call.format, .jpeg)
        XCTAssertEqual(call.options.albumName, "Kromora Exports")
    }

    func testSingleDeliveryHoldsTheDestinationScopeUntilTheTransactionSettles() async throws {
        let photos = FakePhotosDelivery()
        let released = Mutex(0)
        photos.isScopeReleased = { released.withLock { $0 } > 0 }
        let coordinator = ExportCoordinator(engine: FakeRenderEngine(), photosDelivery: photos)
        coordinator.onError = { XCTFail("unexpected error: \($0)") }
        let destination = tempDirectory.appendingPathComponent("scoped.jpg")
        let access = SecurityScopedResourceAccess.systemGranted(for: destination) { _ in
            released.withLock { $0 += 1 }
        }

        coordinator.performExport(
            source: try source(), document: EditDocument(), lut: nil,
            options: ExportOptions(
                format: .jpeg, destination: .file(destination), photos: PhotosExportOptions()
            ),
            to: destination, access: access
        )
        try await waitUntil("the export") { !coordinator.isExporting }

        let call = try XCTUnwrap(photos.calls.first)
        XCTAssertFalse(call.scopeReleasedDuringCall, "scope was released before Photos settled")
        XCTAssertEqual(released.withLock { $0 }, 1, "scope is released once after delivery")
    }

    func testPhotosCancellationLeavesTheCommittedFileInPlace() async throws {
        let photos = FakePhotosDelivery()
        photos.error = CancellationError()
        let coordinator = ExportCoordinator(engine: FakeRenderEngine(), photosDelivery: photos)
        var errors: [String] = []
        coordinator.onError = { errors.append($0) }
        let destination = tempDirectory.appendingPathComponent("cancelled.jpg")

        coordinator.performExport(
            source: try source(), document: EditDocument(), lut: nil,
            options: ExportOptions(
                format: .jpeg, destination: .file(destination), photos: PhotosExportOptions()
            ),
            to: destination
        )
        try await waitUntil("the export") { !coordinator.isExporting }

        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertEqual(errors.count, 1)
        XCTAssertTrue(errors[0].contains("file is safe"), errors[0])
    }

    func testBatchPhotosDeliveryUsesTheCommittedFileAndKeepsIt() async throws {
        let photos = FakePhotosDelivery()
        let coordinator = ExportCoordinator(engine: FakeRenderEngine(), photosDelivery: photos)
        let folder = tempDirectory.appendingPathComponent("batch-ok")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = try Fixtures.writeGradientPNG(
            width: 16, height: 16, named: "ok-source.png", in: tempDirectory
        )

        let outcome = await coordinator.performBatchExport(
            [ExportCoordinator.BatchItem(url: url, data: nil, name: "ok-source")],
            document: EditDocument(), lut: nil,
            options: ExportOptions(
                format: .png, destination: .folder(folder), photos: PhotosExportOptions()
            ),
            to: folder
        )

        let exported = folder.appendingPathComponent("ok-source.png")
        XCTAssertEqual(outcome, .init(exported: 1, failed: 0, total: 1, photosFailed: 0))
        XCTAssertEqual(photos.calls.map(\.fileURL), [exported])
        XCTAssertFalse(try XCTUnwrap(photos.calls.first?.fileContents).isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: exported.path))
    }

    /// The file overload must not load the export into memory, and the file must not be moved.
    func testPhotoKitFileDeliveryDoesNotReadTheFileOrMoveIt() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        for path in ["Models/PhotosDelivery.swift", "ViewModels/ExportCoordinator.swift"] {
            let text = try String(
                contentsOf: sourceURL.appendingPathComponent("Sources/KromoraKit/\(path)"),
                encoding: .utf8
            )
            XCTAssertFalse(text.contains("Data(contentsOf: dest"), path)
            XCTAssertFalse(text.contains("deliver(\n                            data:"), path)
        }
        let delivery = try String(
            contentsOf: sourceURL.appendingPathComponent("Sources/KromoraKit/Models/PhotosDelivery.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(delivery.contains("addResource(with: .photo, fileURL: url"))
        XCTAssertTrue(delivery.contains("shouldMoveFile = false"))
    }

    func testBatchPhotosFailuresAreCountedSeparatelyFromRenderFailures() async throws {
        let photos = FakePhotosDelivery()
        photos.error = PhotosDeliveryError.authorization(.restricted)
        let coordinator = ExportCoordinator(engine: FakeRenderEngine(), photosDelivery: photos)
        coordinator.onError = { XCTFail("unexpected render error: \($0)") }
        let folder = tempDirectory.appendingPathComponent("batch")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = try Fixtures.writeGradientPNG(
            width: 16, height: 16, named: "batch-source.png", in: tempDirectory
        )

        let outcome = await coordinator.performBatchExport(
            [ExportCoordinator.BatchItem(url: url, data: nil, name: "batch-source")],
            document: EditDocument(),
            lut: nil,
            options: ExportOptions(
                format: .png,
                destination: .folder(folder),
                photos: PhotosExportOptions()
            ),
            to: folder
        )

        XCTAssertEqual(outcome, .init(exported: 1, failed: 0, total: 1, photosFailed: 1))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: folder.appendingPathComponent("batch-source.png").path
        ))
        XCTAssertTrue(ExportCoordinator.summary(for: outcome, folder: folder).contains("Photos: 1 failed"))
    }

    func testBatchPhotosCancellationLeavesCommittedFileAndCountsAsPhotosFailure() async throws {
        let photos = FakePhotosDelivery()
        photos.error = CancellationError()
        let coordinator = ExportCoordinator(engine: FakeRenderEngine(), photosDelivery: photos)
        let folder = tempDirectory.appendingPathComponent("batch-cancelled-photos")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = try Fixtures.writeGradientPNG(
            width: 16, height: 16, named: "cancelled-photos-source.png", in: tempDirectory
        )

        let outcome = await coordinator.performBatchExport(
            [ExportCoordinator.BatchItem(url: url, data: nil, name: "cancelled-photos-source")],
            document: EditDocument(),
            lut: nil,
            options: ExportOptions(
                format: .png,
                destination: .folder(folder),
                photos: PhotosExportOptions()
            ),
            to: folder
        )

        let exported = folder.appendingPathComponent("cancelled-photos-source.png")
        XCTAssertEqual(outcome, .init(exported: 1, failed: 0, total: 1, photosFailed: 1))
        XCTAssertTrue(FileManager.default.fileExists(atPath: exported.path))
        XCTAssertTrue(ExportCoordinator.summary(for: outcome, folder: folder).contains("Photos: 1 failed"))
    }

    func testLimitedAuthorizationFailureLeavesBatchExportAndCountsPhotosFailure() async throws {
        let photos = FakePhotosDelivery()
        photos.error = PhotosDeliveryError.authorization(.limited)
        let coordinator = ExportCoordinator(engine: FakeRenderEngine(), photosDelivery: photos)
        let folder = tempDirectory.appendingPathComponent("batch-limited-photos")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = try Fixtures.writeGradientPNG(
            width: 16, height: 16, named: "limited-photos-source.png", in: tempDirectory
        )

        let outcome = await coordinator.performBatchExport(
            [ExportCoordinator.BatchItem(url: url, data: nil, name: "limited-photos-source")],
            document: EditDocument(),
            lut: nil,
            options: ExportOptions(
                format: .png,
                destination: .folder(folder),
                photos: PhotosExportOptions()
            ),
            to: folder
        )

        XCTAssertEqual(outcome, .init(exported: 1, failed: 0, total: 1, photosFailed: 1))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: folder.appendingPathComponent("limited-photos-source.png").path
        ))
    }

    func testBatchPhotosAlbumWarningIsCountedAndKeepsCommittedFile() async throws {
        let photos = FakePhotosDelivery()
        photos.result = PhotosDeliveryResult(
            assetAdded: true, warning: "The requested album could not be updated."
        )
        let coordinator = ExportCoordinator(engine: FakeRenderEngine(), photosDelivery: photos)
        var statuses: [String] = []
        coordinator.onStatus = { statuses.append($0) }
        let folder = tempDirectory.appendingPathComponent("batch-album-warning")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = try Fixtures.writeGradientPNG(
            width: 16, height: 16, named: "album-warning-source.png", in: tempDirectory
        )

        let outcome = await coordinator.performBatchExport(
            [ExportCoordinator.BatchItem(url: url, data: nil, name: "album-warning-source")],
            document: EditDocument(),
            lut: nil,
            options: ExportOptions(
                format: .png,
                destination: .folder(folder),
                photos: PhotosExportOptions(albumName: "Kromora")
            ),
            to: folder
        )

        let exported = folder.appendingPathComponent("album-warning-source.png")
        XCTAssertEqual(outcome, .init(exported: 1, failed: 0, total: 1, photosFailed: 1))
        XCTAssertTrue(FileManager.default.fileExists(atPath: exported.path))
        XCTAssertTrue(statuses.contains { $0.contains("Photos warning") })
        XCTAssertTrue(statuses.contains { $0.contains("requested album could not be updated") })
    }

    func testBatchDeliveryHoldsFolderScopeUntilPhotosTransactionSettles() async throws {
        let photos = FakePhotosDelivery()
        let released = Mutex(0)
        photos.isScopeReleased = { released.withLock { $0 } > 0 }
        let coordinator = ExportCoordinator(engine: FakeRenderEngine(), photosDelivery: photos)
        let folder = tempDirectory.appendingPathComponent("batch-scoped")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = try Fixtures.writeGradientPNG(
            width: 16, height: 16, named: "scoped-source.png", in: tempDirectory
        )
        let access = SecurityScopedResourceAccess.systemGranted(for: folder) { _ in
            released.withLock { $0 += 1 }
        }

        let outcome = await coordinator.performBatchExport(
            [ExportCoordinator.BatchItem(url: url, data: nil, name: "scoped-source")],
            document: EditDocument(),
            lut: nil,
            options: ExportOptions(
                format: .png,
                destination: .folder(folder),
                photos: PhotosExportOptions()
            ),
            to: folder,
            access: access
        )

        let call = try XCTUnwrap(photos.calls.first)
        XCTAssertEqual(outcome, .init(exported: 1, failed: 0, total: 1, photosFailed: 0))
        XCTAssertFalse(call.scopeReleasedDuringCall, "folder scope was released before Photos settled")
        XCTAssertEqual(released.withLock { $0 }, 1, "folder scope is released once after delivery")
    }

    /// Structural guard for PhotoKit's transaction rule: each album request and its mutation
    /// must stay inside a `performChanges` closure. Behavior needs real Photos authorization and
    /// a live library, so it is not exercised here.
    func testAlbumChangeRequestsAndMutationsStayInsidePerformChanges() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/KromoraKit/Models/PhotosDelivery.swift")
        let lines = try String(contentsOf: sourceURL, encoding: .utf8)
            .components(separatedBy: "\n")
        let transactionOperations = [
            "PHAssetCollectionChangeRequest(for:",
            "creationRequestForAssetCollection(",
            "change.addAssets(",
            "creation.addAssets("
        ]

        var openBlocks: [Int] = []  // brace depth at which each `performChanges {` opened
        var depth = 0
        var found = 0
        for line in lines {
            let code = line.trimmingCharacters(in: .whitespaces)
            if code.hasPrefix("//") { continue }
            if transactionOperations.contains(where: code.contains) {
                found += 1
                XCTAssertFalse(openBlocks.isEmpty, "album operation outside performChanges: \(code)")
            }
            if code.contains("performChanges {") { openBlocks.append(depth) }
            depth += code.filter { $0 == "{" }.count - code.filter { $0 == "}" }.count
            while let last = openBlocks.last, depth <= last { openBlocks.removeLast() }
        }
        XCTAssertEqual(found, transactionOperations.count, "expected both factories and both mutations")
    }
}

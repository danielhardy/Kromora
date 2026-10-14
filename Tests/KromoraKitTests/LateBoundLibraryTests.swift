import Foundation
import XCTest

@testable import KromoraKit

@MainActor
final class LateBoundLibraryTests: TempDirectoryTestCase {
    private var packageURL: URL {
        tempDirectory.appendingPathComponent("Late Library.kromoralibrary", isDirectory: true)
    }

    private func makePackage() throws -> (PortableLibraryPackage, PortablePackageLease) {
        let root = tempDirectory.appendingPathComponent("Bound.kromoralibrary")
        let package = try PortableLibraryPackage.create(at: root)
        return (package, try PortablePackageLease.acquire(at: root))
    }

    private func reference() -> EditSourceReference {
        EditSourceReference(assetID: PhotoAssetID(rawValue: "portable:missing"))
    }

    func testDeferredModelConstructsWithoutOpeningPackage() async {
        let store = EditDocumentStore.makeUnboundStore()
        let viewModel = makeAppViewModel(
            editStore: store, portablePackageURL: packageURL, defersLibraryOpen: true
        )

        XCTAssertNil(viewModel.portableLibrary)
        XCTAssertFalse(viewModel.canImportIntoPortableLibrary)
        XCTAssertFalse(FileManager.default.fileExists(atPath: packageURL.path))
        _ = await store.load(for: reference())
        let status = await store.status
        XCTAssertEqual(status, .opening)
        XCTAssertFalse(status.isActionable)
    }

    func testOpenLibraryBindsStoreAndSession() async throws {
        _ = try PortableLibraryPackage.create(at: packageURL)
        let store = EditDocumentStore.makeUnboundStore()
        let viewModel = makeAppViewModel(
            editStore: store, portablePackageURL: packageURL, defersLibraryOpen: true
        )

        await viewModel.openLibrary()

        XCTAssertNotNil(viewModel.portableLibrary)
        XCTAssertTrue(viewModel.canImportIntoPortableLibrary)
        let result = await store.load(for: reference())
        XCTAssertNotEqual(result.status, .opening)
    }

    func testStoreBindsOnceAndRejectsSecondBind() async throws {
        let (package, lease) = try makePackage()
        defer { try? lease.release() }
        let store = EditDocumentStore.makeUnboundStore()

        let first = await store.bind(package: package, lease: lease)
        let second = await store.bind(package: package, lease: lease)

        XCTAssertTrue(first)
        XCTAssertFalse(second)
    }

    func testBoundConstructedStoreRejectsBind() async throws {
        let (package, lease) = try makePackage()
        defer { try? lease.release() }
        let store = EditDocumentStore(package: package, lease: lease)
        let rebound = await store.bind(package: package, lease: lease)
        XCTAssertFalse(rebound)
    }

    func testUnboundStoreFailsClosedForReadWriteFlushAndShutdown() async throws {
        let store = EditDocumentStore.makeUnboundStore()

        let loaded = await store.load(for: reference())
        XCTAssertFalse(loaded.found)
        XCTAssertEqual(loaded.status, .opening)

        do {
            try await store.save(EditDocument(adjustments: [.exposure(ev: 0.2)]), for: reference())
            XCTFail("an unbound store must not accept writes")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("still opening"))
        }
        let status = await store.status
        let worst = await store.worstActionableStatus
        XCTAssertEqual(status, .opening)
        XCTAssertNil(worst)
        let writes = await store.writeCount
        XCTAssertEqual(writes, 0)

        await store.awaitEmbeddedLooks()
        _ = await store.cancelEmbeddedLookLoading()
    }

    func testFailedOpenStoreStillReportsActionablePackageFailure() async {
        let store = EditDocumentStore.makeInMemoryProjectionStore()
        let loaded = await store.load(for: reference())
        guard case .packageFailure = loaded.status else {
            return XCTFail("expected packageFailure, got \(loaded.status)")
        }
    }
}

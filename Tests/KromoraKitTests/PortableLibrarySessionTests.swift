import Foundation
import XCTest

@testable import KromoraKit

@MainActor
final class PortableLibrarySessionTests: TempDirectoryTestCase {
    func testDefaultPackageLivesInPicturesWithCanonicalName() {
        let packageURL = KromoraStorage.defaultPortableLibraryPackageURL
        XCTAssertEqual(packageURL.lastPathComponent, KromoraStorage.portableLibraryPackageName)
        XCTAssertEqual(
            packageURL.deletingLastPathComponent().lastPathComponent,
            "Pictures"
        )
    }

    func testStoragePolicyKeepsProjectionAndCachesOutsidePackage() {
        let packageURL = tempDirectory.appendingPathComponent("Library.kromoralibrary")
        let indexURL = KromoraStorage.indexURL(
            for: UUID(uuidString: "D90B0CF5-85E5-4E5E-AD66-3E3B44F9B8B0")!
        )
        XCTAssertTrue(indexURL.path.contains("Application Support/Kromora/Indexes"))
        XCTAssertFalse(indexURL.path.hasPrefix(packageURL.path))
        XCTAssertTrue(
            KromoraStorage.cacheDirectory(named: "Masks").path.contains("Caches/Kromora/Masks")
        )
        XCTAssertTrue(
            PreviewDiskCache.packageDirectory(for: packageURL).path.hasPrefix(packageURL.path)
        )
        XCTAssertFalse(PreviewDiskCache.defaultDirectory().path.hasPrefix(packageURL.path))
    }

    func testPackageReopensAfterDisposableProjectionAndDerivedDataAreRemoved() async throws {
        let packageURL = tempDirectory.appendingPathComponent("Disposable.kromoralibrary")
        let indexURL = tempDirectory.appendingPathComponent("Index/LibraryIndex.store")
        let sourceURL = try Fixtures.writeJPEG(
            width: 16, height: 12, orientation: 1, named: "source.jpg", in: tempDirectory
        )
        let session = try PortableLibrarySession(at: packageURL, indexURL: indexURL)
        let result = try session.importURLs([sourceURL])
        let assetID = try XCTUnwrap(result.imported.first?.assetID)
        let materialized = try XCTUnwrap(session.materializedAssets().first)
        let store = EditDocumentStore(package: session.package, lease: session.lease)
        try await store.save(
            EditDocument(adjustments: [.exposure(ev: 0.5)]),
            for: EditSourceReference(
                assetID: .file(try XCTUnwrap(materialized.url)),
                portableIdentity: materialized.source.portableIdentity,
                url: materialized.url
            )
        )
        try session.lease.release()

        try? FileManager.default.removeItem(at: packageURL.appendingPathComponent("Derived"))
        try FileManager.default.removeItem(at: indexURL)

        let reopened = try PortableLibrarySession(at: packageURL, indexURL: indexURL)
        let restored = try XCTUnwrap(reopened.materializedAssets().first)
        XCTAssertEqual(restored.source.portableIdentity.assetID, assetID)
        let reopenedStore = EditDocumentStore(package: reopened.package, lease: reopened.lease)
        let loaded = await reopenedStore.load(for: EditSourceReference(
            assetID: .file(try XCTUnwrap(restored.url)),
            portableIdentity: restored.source.portableIdentity,
            url: restored.url
        ))
        XCTAssertEqual(loaded.document.adjustments, [.exposure(ev: 0.5)])
        XCTAssertTrue(loaded.found)
        try reopened.lease.release()
    }

    func testFirstLaunchReopenAndPackageCopyPreserveImportedOriginals() async throws {
        let packageURL = tempDirectory.appendingPathComponent(
            KromoraStorage.portableLibraryPackageName
        )
        let sourceURL = try Fixtures.writeJPEG(
            width: 16, height: 12, orientation: 1, named: "imported.jpg", in: tempDirectory
        )
        let assetID: PortablePhotoAssetID

        do {
            let session = try PortableLibrarySession(at: packageURL)
            XCTAssertTrue(FileManager.default.fileExists(atPath: packageURL.appendingPathComponent("manifest.json").path))
            let result = try session.importURLs([sourceURL])
            assetID = try XCTUnwrap(result.imported.first?.assetID)
            XCTAssertEqual(session.assetCount, 1)
            let materialized = try XCTUnwrap(session.materializedAssets().first)
            let materializedURL = try XCTUnwrap(materialized.url)
            XCTAssertTrue(materializedURL.path.hasPrefix(packageURL.path))
            XCTAssertNotEqual(materializedURL, sourceURL)
            try session.updateLibraryState(for: assetID, rating: 4, flag: .pick)
            let store = EditDocumentStore(
                package: session.package,
                lease: session.lease,
                modelContainer: makeInMemoryEditContainer()
            )
            let reference = EditSourceReference(
                assetID: .file(materializedURL),
                portableIdentity: materialized.source.portableIdentity,
                url: materializedURL
            )
            try await store.save(
                EditDocument(adjustments: [.exposure(ev: 0.75)]),
                for: reference
            )
            try session.lease.release()
        }

        let reopened = try PortableLibrarySession(at: packageURL)
        XCTAssertEqual(reopened.assetCount, 1)
        XCTAssertEqual(reopened.page(at: 0).items.first?.assetID, assetID)
        let reopenedAssets = try reopened.materializedAssets()
        XCTAssertEqual(reopenedAssets.first?.rating, 4)
        XCTAssertEqual(reopenedAssets.first?.flag, .pick)
        let reopenedAsset = try XCTUnwrap(reopenedAssets.first)
        let reopenedURL = try XCTUnwrap(reopenedAsset.url)
        let reopenedReference = EditSourceReference(
            assetID: .file(reopenedURL),
            portableIdentity: reopenedAsset.source.portableIdentity,
            url: reopenedURL
        )
        let reopenedStore = EditDocumentStore(
            package: reopened.package,
            lease: reopened.lease,
            modelContainer: makeInMemoryEditContainer()
        )
        let loaded = await reopenedStore.load(for: reopenedReference)
        XCTAssertEqual(loaded.document.adjustments, [.exposure(ev: 0.75)])
        XCTAssertTrue(loaded.found)
        try reopened.lease.release()

        let copyURL = tempDirectory.appendingPathComponent("Copied.kromoralibrary")
        try FileManager.default.copyItem(at: packageURL, to: copyURL)
        let copied = try PortableLibrarySession(at: copyURL)
        let copiedAsset = try XCTUnwrap(copied.materializedAssets().first)
        let copiedURL = try XCTUnwrap(copiedAsset.url)
        XCTAssertTrue(copiedURL.path.hasPrefix(copyURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: copiedURL.path))
        try copied.lease.release()
    }

    func testExistingInvalidPackageFailsClosedWithoutReplacement() throws {
        let packageURL = tempDirectory.appendingPathComponent("Broken.kromoralibrary")
        try FileManager.default.createDirectory(at: packageURL, withIntermediateDirectories: true)
        let sentinelURL = packageURL.appendingPathComponent("do-not-replace")
        try Data("preserve me".utf8).write(to: sentinelURL)

        XCTAssertThrowsError(try PortableLibrarySession(at: packageURL))
        XCTAssertEqual(try Data(contentsOf: sentinelURL), Data("preserve me".utf8))
    }

    func testExpiredWriterLeaseStaysClosedUntilRecoveryIsRequested() throws {
        let packageURL = tempDirectory.appendingPathComponent("Expired.kromoralibrary")
        let sourceURL = try Fixtures.writeJPEG(
            width: 16, height: 12, orientation: 1, named: "keep.jpg", in: tempDirectory
        )
        let indexURL = tempDirectory.appendingPathComponent("ExpiredIndex/LibraryIndex.store")
        let session = try PortableLibrarySession(at: packageURL, indexURL: indexURL)
        _ = try session.importURLs([sourceURL])
        try session.lease.release()

        let stale = try PortablePackageLease.acquire(
            at: packageURL, deviceName: "killed-swift-run", duration: -1
        )
        XCTAssertThrowsError(
            try PortableLibrarySession(at: packageURL, indexURL: indexURL)
        ) { error in
            guard case .expired(let info) = error as? PortablePackageLeaseError else {
                return XCTFail("expected expired lease, got \(error)")
            }
            XCTAssertEqual(info.deviceName, "killed-swift-run")
            XCTAssertEqual(
                (error as Error).localizedDescription,
                "The previous session on killed-swift-run (pid \(info.processID)) did not close cleanly, so the package writer lease has expired"
            )
        }

        let recovered = try PortableLibrarySession(
            at: packageURL, indexURL: indexURL, recoverExpiredLease: true
        )
        XCTAssertEqual(recovered.assetCount, 1)
        try recovered.lease.release()
        _ = stale
    }
}

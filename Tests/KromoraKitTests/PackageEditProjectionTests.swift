import Foundation
import XCTest

@testable import KromoraKit

final class PackageEditProjectionTests: TempDirectoryTestCase {
    func testPackageIsCanonicalAndProjectionRebuildPreservesExactDocument() async throws {
        let packageURL = tempDirectory.appendingPathComponent("Canonical.kromoralibrary")
        let package = try PortableLibraryPackage.create(at: packageURL)
        let sourceURL = tempDirectory.appendingPathComponent("source.jpg")
        try Data("package source".utf8).write(to: sourceURL)
        let lease = try PortablePackageLease.acquire(at: packageURL)
        defer { try? lease.release() }

        let imported = try package.importSources([.init(url: sourceURL)], lease: lease)
        let asset = try XCTUnwrap(imported.imported.first)
        let identity = PortablePhotoIdentity(
            assetID: asset.assetID,
            sourceFingerprint: .data(Data("package source".utf8), decoderVersion: "test")
        )
        let reference = EditSourceReference(
            assetID: .file(sourceURL), portableIdentity: identity, url: sourceURL
        )
        var document = EditDocument(
            rawDevelop: RAWDevelopSettings(exposure: 0.73),
            adjustments: [.exposure(ev: 0.41)],
            lut: LUTSettings(lutID: LUTID(raw: "look.cube"), intensity: 0.37)
        )
        document.crop = CropAdjustments(
            normalizedRect: CGRect(x: 0.12, y: 0.08, width: 0.7, height: 0.81),
            aspectRatio: .freeform
        )

        let store = EditDocumentStore(package: package, lease: lease)
        try await store.save(document, for: reference)

        let sidecar = try package.readEditSidecar(for: asset.assetID)
        XCTAssertEqual(sidecar.native.document, document)
        XCTAssertEqual(sidecar.xmp.document, document)

        // Evicting the bounded cache does not affect the canonical package.
        try await store.delete(for: reference)
        let fromPackage = await store.load(for: reference)
        XCTAssertEqual(fromPackage.document, document)
        XCTAssertTrue(fromPackage.found)
        let cacheCount = await store.cacheCount
        XCTAssertEqual(cacheCount, 1)
    }

    func testNamedSnapshotAndDurableHistorySurviveStoreReload() async throws {
        let packageURL = tempDirectory.appendingPathComponent("Snapshots.kromoralibrary")
        let package = try PortableLibraryPackage.create(at: packageURL)
        let sourceURL = tempDirectory.appendingPathComponent("snapshot.jpg")
        try Data("snapshot source".utf8).write(to: sourceURL)
        let lease = try PortablePackageLease.acquire(at: packageURL)
        defer { try? lease.release() }
        let imported = try package.importSources([.init(url: sourceURL)], lease: lease)
        let asset = try XCTUnwrap(imported.imported.first)
        let identity = PortablePhotoIdentity(
            assetID: asset.assetID,
            sourceFingerprint: .data(Data("snapshot source".utf8), decoderVersion: "test")
        )
        let reference = EditSourceReference(assetID: .file(sourceURL), portableIdentity: identity)
        let store = EditDocumentStore(package: package, lease: lease)
        let document = EditDocument(light: .init(exposure: 0.8))
        try await store.saveSnapshot(document, named: "Warm sunset", for: reference)

        let history = try await store.history(for: reference)
        XCTAssertEqual(history.count, 1)
        XCTAssertEqual(history[0].snapshotName, "Warm sunset")
        XCTAssertEqual(history[0].document, document)

        let reopened = try PortableLibraryPackage.open(at: packageURL)
        let reopenedHistory = try reopened.readEditHistory(for: asset.assetID)
        XCTAssertEqual(reopenedHistory, history)
    }

    @MainActor
    func testVirtualCopyHasIndependentIdentityAndEditHistory() async throws {
        let packageURL = tempDirectory.appendingPathComponent("VirtualCopies.kromoralibrary")
        let package = try PortableLibraryPackage.create(at: packageURL)
        let sourceURL = tempDirectory.appendingPathComponent("portrait.jpg")
        try Data("portable portrait".utf8).write(to: sourceURL)
        let importLease = try PortablePackageLease.acquire(at: packageURL)
        let imported = try package.importSources([.init(url: sourceURL)], lease: importLease)
        try importLease.release()
        let original = try XCTUnwrap(imported.imported.first)

        let session = try PortableLibrarySession(at: packageURL)
        let copy = try session.createVirtualCopy(of: original.assetID)
        XCTAssertNotEqual(copy.assetID, original.assetID)
        XCTAssertTrue(copy.displayName.contains("Copy"))
        XCTAssertEqual(
            try package.readAssetRecord(for: copy.assetID).copyOfAssetID, original.assetID
        )
        XCTAssertEqual(
            try Data(contentsOf: package.embeddedSourceURL(
                for: package.readAssetRecord(for: copy.assetID)
            )),
            Data("portable portrait".utf8)
        )

        let store = EditDocumentStore(package: package, lease: session.lease)
        let originalDocument = EditDocument(light: .init(exposure: -0.4))
        let copiedDocument = EditDocument(light: .init(exposure: 0.9))
        try await store.save(originalDocument, for: EditSourceReference(
            portableIdentity: try package.readAssetRecord(for: original.assetID).identity
        ))
        try await store.save(copiedDocument, for: EditSourceReference(portableIdentity: copy.identity))

        XCTAssertEqual(try package.readEditHistory(for: original.assetID).map(\.document), [originalDocument])
        XCTAssertEqual(try package.readEditHistory(for: copy.assetID).map(\.document), [copiedDocument])
        let membership = try package.readMembershipShard(PortableLibraryPackage.shard(for: copy.assetID))
        XCTAssertEqual(
            membership.entries.first(where: { $0.assetID == copy.assetID })?.summary.displayName,
            copy.displayName
        )
        await session.shutdown()
    }

    func testPackagePersistenceCoordinatorStillCoalescesToOneRevision() async throws {
        let packageURL = tempDirectory.appendingPathComponent("Coalesced.kromoralibrary")
        let package = try PortableLibraryPackage.create(at: packageURL)
        let sourceURL = tempDirectory.appendingPathComponent("coalesced.jpg")
        try Data("source".utf8).write(to: sourceURL)
        let lease = try PortablePackageLease.acquire(at: packageURL)
        defer { try? lease.release() }
        let imported = try package.importSources([.init(url: sourceURL)], lease: lease)
        let asset = try XCTUnwrap(imported.imported.first)
        let reference = EditSourceReference(
            assetID: .file(sourceURL),
            portableIdentity: PortablePhotoIdentity(
                assetID: asset.assetID,
                sourceFingerprint: .data(Data("source".utf8), decoderVersion: "test")
            ),
            url: sourceURL
        )
        let store = EditDocumentStore(package: package, lease: lease)
        let coordinator = await MainActor.run { EditPersistenceCoordinator(store: store) }
        let first = EditDocument(adjustments: [.exposure(ev: 0.1)])
        let latest = EditDocument(adjustments: [.exposure(ev: 0.9)])
        await MainActor.run {
            coordinator.enqueue(first, for: reference, reportsStatus: false)
            coordinator.enqueue(latest, for: reference, reportsStatus: false)
        }
        let flushResult = await coordinator.flush()
        XCTAssertEqual(flushResult, .success)

        let record = try package.readAssetRecord(for: asset.assetID)
        XCTAssertEqual(record.editHistory.edits.count, 1)
        XCTAssertEqual(try package.readEditRevision(for: asset.assetID).document, latest)
    }
}

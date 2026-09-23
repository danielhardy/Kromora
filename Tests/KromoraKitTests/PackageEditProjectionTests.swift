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

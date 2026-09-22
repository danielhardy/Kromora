import Foundation
import XCTest

@testable import KromoraKit

final class EditDocumentStoreTests: TempDirectoryTestCase {
    private func makePackage(
        names: [String] = ["photo.jpg"]
    ) throws -> (PortableLibraryPackage, PortablePackageLease, [PortablePhotoAssetID]) {
        let root = tempDirectory.appendingPathComponent("Library.kromoralibrary")
        let package = try PortableLibraryPackage.create(at: root)
        let urls = try names.map { name -> URL in
            let url = tempDirectory.appendingPathComponent(name)
            try Data("source-\(name)".utf8).write(to: url)
            return url
        }
        let lease = try PortablePackageLease.acquire(at: root)
        let result = try package.importSources(urls.map { .init(url: $0) }, lease: lease)
        return (package, lease, result.imported.map(\.assetID))
    }

    private func reference(for assetID: PortablePhotoAssetID) -> EditSourceReference {
        EditSourceReference(
            assetID: PhotoAssetID(rawValue: "portable:\(assetID.raw)"),
            portableIdentity: PortablePhotoIdentity(
                assetID: assetID,
                sourceFingerprint: .data(Data("source".utf8), decoderVersion: "test")
            )
        )
    }

    func testPackageRoundTripLeavesOriginalUntouched() async throws {
        let (package, lease, assets) = try makePackage()
        defer { try? lease.release() }
        let store = EditDocumentStore(package: package, lease: lease)
        let document = EditDocument(adjustments: [.exposure(ev: 0.4)])

        try await store.save(document, for: reference(for: assets[0]))
        let loaded = await store.load(for: reference(for: assets[0]))

        XCTAssertTrue(loaded.found)
        XCTAssertEqual(loaded.document, document)
        XCTAssertEqual(try package.readEditRevision(for: assets[0]).document, document)
    }

    func testCacheIsBoundedAndEvictionReadsThePackageAgain() async throws {
        let (package, lease, assets) = try makePackage(names: ["one.jpg", "two.jpg", "three.jpg"])
        defer { try? lease.release() }
        let store = EditDocumentStore(package: package, lease: lease, cacheCapacity: 2)

        for (index, assetID) in assets.enumerated() {
            try await store.save(
                EditDocument(adjustments: [.exposure(ev: Double(index))]),
                for: reference(for: assetID)
            )
        }

        let cacheCount = await store.cacheCount
        XCTAssertEqual(cacheCount, 2)
        let first = await store.load(for: reference(for: assets[0]))
        XCTAssertEqual(first.document.adjustments, [.exposure(ev: 0)])
        let finalCacheCount = await store.cacheCount
        XCTAssertLessThanOrEqual(finalCacheCount, 2)
    }

    func testCorruptRevisionReportsCorruptWithoutInventingEdits() async throws {
        let (package, lease, assets) = try makePackage()
        defer { try? lease.release() }
        let store = EditDocumentStore(package: package, lease: lease)
        try await store.save(
            EditDocument(adjustments: [.exposure(ev: 0.8)]), for: reference(for: assets[0])
        )

        let record = try package.readAssetRecord(for: assets[0])
        let pointer = try XCTUnwrap(record.editHistory.edits.first)
        try Data("corrupt revision".utf8).write(
            to: package.rootURL.appendingPathComponent(pointer.relativePath)
        )
        let freshStore = EditDocumentStore(package: package, lease: lease)
        let result = await freshStore.load(for: reference(for: assets[0]))

        XCTAssertTrue(result.document.isIdentity)
        guard case .corrupt = result.status else {
            return XCTFail("expected a corrupt package revision status")
        }
        XCTAssertFalse(result.isUsableForPrefetch)
    }

    func testPackageFailureLeavesTheLastKnownDocumentInTheCacheOnlyUntilReload() async throws {
        let (package, lease, assets) = try makePackage()
        defer { try? lease.release() }
        let store = EditDocumentStore(package: package, lease: lease)
        let document = EditDocument(adjustments: [.exposure(ev: 0.3)])
        try await store.save(document, for: reference(for: assets[0]))
        let loaded = await store.load(for: reference(for: assets[0]))
        XCTAssertEqual(loaded.document, document)

        let recordURL = package.assetRecordURL(for: assets[0])
        try FileManager.default.removeItem(at: recordURL)
        let result = await store.load(for: reference(for: assets[0]))

        guard case .packageFailure = result.status else {
            return XCTFail("a missing asset record must be reported as a package failure")
        }
        XCTAssertTrue(result.document.isIdentity)
    }

    func testRelaunchReadsTheDurablePackageRevision() async throws {
        let (package, lease, assets) = try makePackage()
        let document = EditDocument(adjustments: [.exposure(ev: 0.75)])
        let first = EditDocumentStore(package: package, lease: lease)
        try await first.save(document, for: reference(for: assets[0]))
        try lease.release()

        let reopenedLease = try PortablePackageLease.acquire(at: package.rootURL)
        defer { try? reopenedLease.release() }
        let reopened = EditDocumentStore(package: package, lease: reopenedLease)
        let result = await reopened.load(for: reference(for: assets[0]))

        XCTAssertTrue(result.found)
        XCTAssertEqual(result.document, document)
    }
}

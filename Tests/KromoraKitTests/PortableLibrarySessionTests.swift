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
}

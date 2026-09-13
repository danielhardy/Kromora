import Foundation
import XCTest

@testable import KromoraKit

final class PortablePackageTrashTests: TempDirectoryTestCase {
    func testRemoveQuarantinesAndRestoreRecoversOriginalAndRecord() throws {
        let (package, assetID, originalURL) = try makeEmbeddedAsset()
        let lease = try PortablePackageLease.acquire(at: package.rootURL)
        defer { try? lease.release() }

        let removal = try package.removeFromLibrary(assetID, lease: lease)
        XCTAssertFalse(removal.wasReferenced)
        XCTAssertFalse(FileManager.default.fileExists(atPath: originalURL.path))
        let quarantineOriginal = package.quarantineDirectoryURL(for: assetID)
            .appendingPathComponent("Original/source.jpg")
        XCTAssertEqual(try Data(contentsOf: quarantineOriginal), Data("original".utf8))
        let quarantinedRecord = try package.readAssetRecord(
            atRelativePath: "Recovery/Quarantine/\(assetID.raw)/asset.json")
        XCTAssertTrue(quarantinedRecord.isRemoved)
        let tombstone = try XCTUnwrap(
            package.readMembershipShard(PortableLibraryPackage.shard(for: assetID)).entries.first)
        XCTAssertTrue(tombstone.isTombstone)

        _ = try package.restoreFromQuarantine(assetID, lease: lease)
        XCTAssertEqual(try Data(contentsOf: originalURL), Data("original".utf8))
        XCTAssertFalse(
            try package.readAssetRecord(for: assetID).isRemoved)
        XCTAssertFalse(
            try package.readMembershipShard(PortableLibraryPackage.shard(for: assetID))
                .entries[0].isTombstone)
        XCTAssertFalse(FileManager.default.fileExists(atPath: quarantineOriginal.path))
    }

    func testReclaimRequiresConfirmationAndPermanentlyRemovesOnlyQuarantine() throws {
        let (package, assetID, originalURL) = try makeEmbeddedAsset()
        let lease = try PortablePackageLease.acquire(at: package.rootURL)
        defer { try? lease.release() }
        _ = try package.removeFromLibrary(assetID, lease: lease)

        XCTAssertThrowsError(try package.reclaimSpace(confirmed: false, lease: lease)) { error in
            XCTAssertEqual(error as? PortablePackageTrashError, .confirmationRequired)
        }
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: package.quarantineDirectoryURL(for: assetID).path))

        let result = try package.reclaimSpace(confirmed: true, lease: lease)
        XCTAssertEqual(result.reclaimedAssetIDs, [assetID])
        XCTAssertGreaterThanOrEqual(result.bytesReclaimed, UInt64(Data("original".utf8).count))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: package.quarantineDirectoryURL(for: assetID).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: originalURL.path))
        XCTAssertTrue(try package.readMembershipShard(PortableLibraryPackage.shard(for: assetID))
            .entries[0].isTombstone)
    }

    func testReferencedAssetIsTombstonedButNeverQuarantinedOrReclaimed() throws {
        let packageURL = tempDirectory.appendingPathComponent("Referenced.kromoralibrary")
        let package = try PortableLibraryPackage.create(at: packageURL)
        let assetID = PortablePhotoAssetID(uuid: UUID(uuidString: "bb000000-0000-4000-8000-000000000001")!)
        let record = PortablePackageAssetRecord(
            identity: .init(assetID: assetID, sourceFingerprint: .data(Data("external".utf8), decoderVersion: "test")),
            source: .referenced(bookmark: Data("external-bookmark".utf8))
        )
        try package.writeAssetRecord(record)
        var shard = try package.readMembershipShard(PortableLibraryPackage.shard(for: assetID))
        shard.entries = [.init(
            assetID: assetID,
            recordPath: "Assets/bb/\(assetID.raw)/asset.json",
            summary: .init(displayName: "external.jpg")
        )]
        try package.writeMembershipShard(shard)
        let lease = try PortablePackageLease.acquire(at: packageURL)
        defer { try? lease.release() }

        _ = try package.removeFromLibrary(assetID, lease: lease)
        XCTAssertTrue(FileManager.default.fileExists(atPath: package.assetDirectoryURL(for: assetID).path))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: package.quarantineDirectoryURL(for: assetID).path))
        let reclaim = try package.reclaimSpace(confirmed: true, lease: lease)
        XCTAssertTrue(reclaim.reclaimedAssetIDs.isEmpty)
        XCTAssertEqual(reclaim.skippedReferencedAssetIDs, [assetID])
        XCTAssertTrue(FileManager.default.fileExists(atPath: package.assetDirectoryURL(for: assetID).path))
        XCTAssertTrue(try package.readAssetRecord(for: assetID).isRemoved)
    }

    func testInterruptedQuarantineTransactionRestoresDirectoryAndMembership() throws {
        let (package, assetID, originalURL) = try makeEmbeddedAsset()
        let lease = try PortablePackageLease.acquire(at: package.rootURL)
        defer { try? lease.release() }
        let injector = PortablePackageFaultInjector(failingAt: .publish)

        XCTAssertThrowsError(try package.removeFromLibrary(
            assetID, lease: lease, faultInjector: injector))
        XCTAssertTrue(FileManager.default.fileExists(atPath: originalURL.path))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: package.quarantineDirectoryURL(for: assetID).path))
        XCTAssertFalse(try package.readMembershipShard(PortableLibraryPackage.shard(for: assetID))
            .entries[0].isTombstone)
        XCTAssertTrue(try PortablePackageTransaction.recover(at: package.rootURL)
            .recoveredTransactionIDs.isEmpty)
    }

    private func makeEmbeddedAsset() throws -> (
        package: PortableLibraryPackage, assetID: PortablePhotoAssetID, originalURL: URL
    ) {
        let packageURL = tempDirectory.appendingPathComponent("Embedded-\(UUID().uuidString).kromoralibrary")
        let package = try PortableLibraryPackage.create(at: packageURL)
        let assetID = PortablePhotoAssetID(uuid: UUID(uuidString: "aa000000-0000-4000-8000-000000000001")!)
        let relativePath = "Assets/aa/\(assetID.raw)/Original/source.jpg"
        let record = PortablePackageAssetRecord(
            identity: .init(assetID: assetID, sourceFingerprint: .data(Data("original".utf8), decoderVersion: "test")),
            source: .embedded(relativePath: relativePath)
        )
        try package.writeAssetRecord(record)
        let originalURL = package.rootURL.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: originalURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("original".utf8).write(to: originalURL)
        var shard = try package.readMembershipShard("aa")
        shard.entries = [.init(
            assetID: assetID, recordPath: "Assets/aa/\(assetID.raw)/asset.json",
            summary: .init(displayName: "source.jpg")
        )]
        try package.writeMembershipShard(shard)
        return (package, assetID, originalURL)
    }
}

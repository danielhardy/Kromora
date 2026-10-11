import Foundation
import XCTest

@testable import KromoraKit

final class CaptureMetadataBackfillTests: TempDirectoryTestCase {
    func testBackfillFillsLegacySummariesOnceAndPreservesOtherFields() throws {
        let packageURL = tempDirectory.appendingPathComponent("Backfill.kromoralibrary")
        let package = try PortableLibraryPackage.create(at: packageURL)
        let lease = try PortablePackageLease.acquire(at: packageURL)
        defer { try? lease.release() }
        let sourceURL = try Fixtures.writeJPEG(
            width: 24, height: 12, orientation: 1, named: "a.jpg", in: tempDirectory)
        let imported = try package.importSources([.init(url: sourceURL)], lease: lease)
        let assetID = try XCTUnwrap(imported.imported.first?.assetID)
        let shardName = PortableLibraryPackage.shard(for: assetID)

        // Simulate a package written before these summary fields existed.
        var shard = try package.readMembershipShard(shardName)
        let index = try XCTUnwrap(shard.entries.firstIndex { $0.assetID == assetID })
        shard.entries[index].summary.captureSettings = nil
        shard.entries[index].summary.coarseLocation = nil
        shard.entries[index].summary.rating = 4
        try package.writeMembershipShard(shard)

        let repaired = try package.repairCaptureMetadataShard(shardName, lease: lease)
        XCTAssertEqual(repaired.map(\.assetID), [assetID])

        let summary = try XCTUnwrap(
            package.readMembershipShard(shardName).entries.first { $0.assetID == assetID }?.summary)
        XCTAssertEqual(summary.captureSettings, PortablePackageCaptureSettings())
        XCTAssertEqual(summary.coarseLocation, "")
        XCTAssertEqual(summary.rating, 4)

        // Resumable and idempotent: a repaired shard has nothing left to do.
        XCTAssertTrue(try package.repairCaptureMetadataShard(shardName, lease: lease).isEmpty)
    }

    func testCancelledBackfillLeavesSummariesForNextOpen() throws {
        let packageURL = tempDirectory.appendingPathComponent("Cancelled.kromoralibrary")
        let package = try PortableLibraryPackage.create(at: packageURL)
        let lease = try PortablePackageLease.acquire(at: packageURL)
        defer { try? lease.release() }
        let sourceURL = try Fixtures.writeJPEG(
            width: 24, height: 12, orientation: 1, named: "b.jpg", in: tempDirectory)
        let imported = try package.importSources([.init(url: sourceURL)], lease: lease)
        let assetID = try XCTUnwrap(imported.imported.first?.assetID)
        let shardName = PortableLibraryPackage.shard(for: assetID)
        var shard = try package.readMembershipShard(shardName)
        for index in shard.entries.indices { shard.entries[index].summary.captureSettings = nil }
        try package.writeMembershipShard(shard)

        XCTAssertThrowsError(
            try package.repairCaptureMetadataShard(shardName, lease: lease, isCancelled: { true })
        ) { XCTAssertTrue($0 is CancellationError) }
        let after = try package.readMembershipShard(shardName).entries
        XCTAssertTrue(after.allSatisfy { $0.summary.captureSettings == nil })
    }
}

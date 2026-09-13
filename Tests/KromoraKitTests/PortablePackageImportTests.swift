import Foundation
import XCTest
import os.lock

@testable import KromoraKit

final class PortablePackageImportTests: TempDirectoryTestCase {
    func testImportHashesStagesAndPublishesEachAssetWithProgress() throws {
        let packageURL = tempDirectory.appendingPathComponent("Import.kromoralibrary")
        let package = try PortableLibraryPackage.create(at: packageURL)
        let firstURL = try makeSource(named: "first.raw", contents: Data(repeating: 0x11, count: 4097))
        let secondURL = try makeSource(named: "second.jpg", contents: Data("second".utf8))
        let firstBefore = try Data(contentsOf: firstURL)
        let secondBefore = try Data(contentsOf: secondURL)
        let lease = try PortablePackageLease.acquire(at: packageURL)
        defer { try? lease.release() }

        let progressValues = OSAllocatedUnfairLock<[PortablePackageImportProgress]>(initialState: [])
        let sourceReads = OSAllocatedUnfairLock<[URL]>(initialState: [])
        let result = try package.importSources(
            [
                .init(url: firstURL),
                .init(url: secondURL),
            ],
            lease: lease,
            options: .init(chunkSize: 3, copyMode: .streamed),
            progress: { value in progressValues.withLock { $0.append(value) } },
            sourceReadObserver: { source in sourceReads.withLock { $0.append(source.url) } }
        )
        let progress = progressValues.withLock { $0 }

        XCTAssertFalse(result.cancelled)
        XCTAssertEqual(result.imported.count, 2)
        XCTAssertTrue(result.duplicates.isEmpty)
        XCTAssertTrue(result.failures.isEmpty)
        XCTAssertEqual(result.imported.map { $0.byteCount }, [4097, 6])
        XCTAssertEqual(result.imported.map { $0.usedClonefile }, [false, false])
        XCTAssertEqual(progress.first?.phase, .preparing)
        XCTAssertGreaterThanOrEqual(progress.filter { $0.phase == .committing }.count, 2)
        XCTAssertEqual(progress.last?.processed, 2)
        XCTAssertEqual(progress.last?.imported, 2)
        XCTAssertEqual(sourceReads.withLock { $0 }, [firstURL, secondURL])
        XCTAssertEqual(try Data(contentsOf: firstURL), firstBefore)
        XCTAssertEqual(try Data(contentsOf: secondURL), secondBefore)

        for imported in result.imported {
            let record = try package.readAssetRecord(for: imported.assetID)
            XCTAssertEqual(record.identity.sourceFingerprint.contentHash, imported.contentHash)
            XCTAssertEqual(try Data(contentsOf: package.embeddedSourceURL(for: record)),
                           imported.source.url == firstURL ? firstBefore : secondBefore)
        }
    }

    func testDuplicateContentIsReportedAndSkippedWithoutSecondAsset() throws {
        let packageURL = tempDirectory.appendingPathComponent("Duplicate.kromoralibrary")
        let package = try PortableLibraryPackage.create(at: packageURL)
        let sourceURL = try makeSource(named: "same.jpg", contents: Data("same bytes".utf8))
        let lease = try PortablePackageLease.acquire(at: packageURL)
        defer { try? lease.release() }

        let result = try package.importSources(
            [.init(url: sourceURL), .init(url: sourceURL, name: "renamed.jpg")],
            lease: lease,
            options: .init(copyMode: .streamed)
        )

        XCTAssertEqual(result.imported.count, 1)
        XCTAssertEqual(result.duplicates.count, 1)
        XCTAssertNil(result.duplicates[0].importedAssetID)
        let shard = try package.readMembershipShard(
            PortableLibraryPackage.shard(for: result.imported[0].assetID))
        XCTAssertEqual(shard.entries.filter { !$0.isTombstone }.count, 1)
    }

    func testCancellationRollsBackStagingAndLeavesSourceUntouched() throws {
        let packageURL = tempDirectory.appendingPathComponent("Cancelled.kromoralibrary")
        let package = try PortableLibraryPackage.create(at: packageURL)
        let original = Data(repeating: 0x5a, count: 32 * 1024)
        let sourceURL = try makeSource(named: "cancelled.raw", contents: original)
        let lease = try PortablePackageLease.acquire(at: packageURL)
        defer { try? lease.release() }
        let checks = OSAllocatedUnfairLock(initialState: 0)

        let result = try package.importSources(
            [.init(url: sourceURL)],
            lease: lease,
            options: .init(chunkSize: 1, copyMode: .streamed),
            isCancelled: {
                checks.withLock { value in
                    value += 1
                    return value > 5
                }
            }
        )

        XCTAssertTrue(result.cancelled)
        XCTAssertTrue(result.imported.isEmpty)
        XCTAssertTrue(result.failures.isEmpty)
        XCTAssertEqual(try Data(contentsOf: sourceURL), original)
        for shardName in PortableLibraryPackage.allShards {
            XCTAssertTrue(try package.readMembershipShard(shardName).entries.isEmpty)
        }
        let recovery = try PortablePackageTransaction.recover(at: packageURL)
        XCTAssertTrue(recovery.recoveredTransactionIDs.isEmpty)
    }

    private func makeSource(named name: String, contents: Data) throws -> URL {
        let url = tempDirectory.appendingPathComponent(name)
        try contents.write(to: url)
        return url
    }
}

import Foundation
import CryptoKit
import XCTest
import os.lock

@testable import KromoraKit

final class PortablePackageImportTests: TempDirectoryTestCase {
    func testImportPersistsCameraAndLensMetadataInMembershipSummary() throws {
        let packageURL = tempDirectory.appendingPathComponent("ImportMetadata.kromoralibrary")
        let package = try PortableLibraryPackage.create(at: packageURL)
        let sourceURL = try Fixtures.writeJPEG(
            named: "camera.jpg",
            in: tempDirectory,
            exif: [kCGImagePropertyExifLensModel: "Kromora Prime 35mm"],
            tiff: [
                kCGImagePropertyTIFFMake: "Kromora",
                kCGImagePropertyTIFFModel: "Test Body",
            ]
        )
        let lease = try PortablePackageLease.acquire(at: packageURL)
        defer { try? lease.release() }

        let result = try package.importSources([.init(url: sourceURL)], lease: lease)
        let imported = try XCTUnwrap(result.imported.first)
        let summary = try XCTUnwrap(
            package.readMembershipShard(PortableLibraryPackage.shard(for: imported.assetID))
                .entries.first { $0.assetID == imported.assetID }?.summary
        )

        XCTAssertEqual(summary.cameraMake, "Kromora")
        XCTAssertEqual(summary.cameraModel, "Test Body")
        XCTAssertEqual(summary.lens, "Kromora Prime 35mm")
    }

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
        XCTAssertEqual(result.imported.map { $0.contentHash }, [firstBefore, secondBefore].map {
            SHA256.hash(data: $0).map { String(format: "%02x", $0) }.joined()
        })
        XCTAssertEqual(progress.first?.phase, .preparing)
        XCTAssertGreaterThanOrEqual(progress.filter { $0.phase == .committing }.count, 2)
        XCTAssertEqual(progress.last?.processed, 2)
        XCTAssertEqual(progress.last?.imported, 2)
        XCTAssertTrue(progress.contains { $0.phase == .staging && $0.bytesRead > 0 && $0.bytesRead < 4097 })
        XCTAssertEqual(progress.map(\.bytesRead), progress.map(\.bytesRead).sorted())
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

    func testCommittedCallbackFiresPerSourceAndCancellationKeepsCommittedAssets() throws {
        let packageURL = tempDirectory.appendingPathComponent("Committed.kromoralibrary")
        let package = try PortableLibraryPackage.create(at: packageURL)
        let urls = try (0..<4).map {
            try makeSource(named: "c\($0).raw", contents: Data(repeating: UInt8($0 + 1), count: 64))
        }
        let lease = try PortablePackageLease.acquire(at: packageURL)
        defer { try? lease.release() }

        let committed = OSAllocatedUnfairLock<[LibraryIndexEntry]>(initialState: [])
        let result = try package.importSources(
            urls.map { .init(url: $0) }, lease: lease,
            isCancelled: { committed.withLock { $0.count } >= 2 },
            committed: { entry in committed.withLock { $0.append(entry) } }
        )

        // The callback fires after each source's transaction commits, so cancelling after the
        // second leaves exactly those two in the package and in the delta.
        XCTAssertTrue(result.cancelled)
        let entries = committed.withLock { $0 }
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries.map(\.assetID), result.imported.map(\.assetID))
        XCTAssertEqual(Set(entries.map(\.assetID)), Set(result.indexDelta.upserts.map(\.assetID)))
        var members = 0
        for shard in PortableLibraryPackage.allShards {
            members += try package.readMembershipShard(shard).entries.filter { !$0.isTombstone }.count
        }
        XCTAssertEqual(members, 2)
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

    func testFailureIsIsolatedAndImportAnywayRetainsDuplicateIdentity() throws {
        let package = try PortableLibraryPackage.create(at: tempDirectory.appendingPathComponent("Isolation.kromoralibrary"))
        let lease = try PortablePackageLease.acquire(at: package.rootURL)
        defer { try? lease.release() }
        let source = try makeSource(named: "same.raw", contents: Data(repeating: 0x3a, count: 4097))
        let result = try package.importSources([
            .init(url: source), .init(url: tempDirectory.appendingPathComponent("missing.raw")),
            .init(url: source, name: "copy.raw"),
        ], lease: lease, options: .init(duplicatePolicy: .importAnyway, chunkSize: 1024, copyMode: .streamed))
        XCTAssertEqual(result.imported.count, 2)
        XCTAssertEqual(result.failures.count, 1)
        XCTAssertEqual(result.duplicates.count, 1)
        XCTAssertEqual(result.duplicates.first?.existingAssetID, result.imported.first?.assetID)
        XCTAssertEqual(result.duplicates.first?.importedAssetID, result.imported.last?.assetID)
        XCTAssertEqual(result.imported.first?.contentHash, result.imported.last?.contentHash)
    }

    func testCancellationPreservesPreviouslyCommittedSource() throws {
        let package = try PortableLibraryPackage.create(at: tempDirectory.appendingPathComponent("Partial.kromoralibrary"))
        let lease = try PortablePackageLease.acquire(at: package.rootURL)
        defer { try? lease.release() }
        let first = try makeSource(named: "first.raw", contents: Data("first".utf8))
        let second = try makeSource(named: "second.raw", contents: Data("second".utf8))
        let cancellation = PortablePackageImportCancellation()
        let result = try package.importSources(
            [.init(url: first), .init(url: second)], lease: lease,
            options: .init(copyMode: .streamed), isCancelled: { cancellation.isCancelled },
            progress: { if $0.processed == 1 { cancellation.cancel() } })
        XCTAssertTrue(result.cancelled)
        XCTAssertEqual(result.imported.count, 1)
        let imported = try XCTUnwrap(result.imported.first)
        let record = try package.readAssetRecord(for: imported.assetID)
        XCTAssertEqual(try Data(contentsOf: package.embeddedSourceURL(for: record)), Data("first".utf8))
        XCTAssertEqual(result.indexDelta.upserts.count, 1)
        XCTAssertTrue(try PortablePackageTransaction.recover(at: package.rootURL).recoveredTransactionIDs.isEmpty)
    }

    func testCancelledCopyRetainsItsPartialByteProgress() throws {
        let package = try PortableLibraryPackage.create(at: tempDirectory.appendingPathComponent("Bytes.kromoralibrary"))
        let lease = try PortablePackageLease.acquire(at: package.rootURL)
        defer { try? lease.release() }
        let source = try makeSource(named: "cancelled.raw", contents: Data(repeating: 0x5a, count: 4096))
        let cancellation = PortablePackageImportCancellation()
        let snapshots = OSAllocatedUnfairLock<[PortablePackageImportProgress]>(initialState: [])
        let result = try package.importSources(
            [.init(url: source)], lease: lease,
            options: .init(chunkSize: 1024, copyMode: .streamed), isCancelled: { cancellation.isCancelled },
            progress: { value in
                snapshots.withLock { $0.append(value) }
                if value.bytesRead == 1024 { cancellation.cancel() }
            })
        XCTAssertTrue(result.cancelled)
        XCTAssertTrue(result.imported.isEmpty)
        let values = snapshots.withLock { $0 }
        XCTAssertEqual(values.last?.phase, .finished)
        XCTAssertEqual(values.last?.bytesRead, 1024)
        XCTAssertEqual(values.map(\.bytesRead), values.map(\.bytesRead).sorted())
    }

    @MainActor
    func testProgressSinkLimitsPublicationAndAlwaysDeliversFinalTotals() async {
        let sink = PortablePackageImportProgressSink()
        let stream = AsyncStream<PortablePackageImportProgress> { sink.install($0) }
        let start = ContinuousClock.now
        var value = PortablePackageImportProgress(
            total: 1000, processed: 0, imported: 0, duplicates: 0, failed: 0,
            bytesRead: 0, totalBytes: 1000, currentName: nil, phase: .preparing)
        sink.yield(value, now: start)
        for ordinal in 1...1000 {
            value.phase = .staging
            value.processed = ordinal
            value.bytesRead = UInt64(ordinal)
            sink.yield(value, now: start.advanced(by: .milliseconds(ordinal)))
        }
        value.phase = .finished
        sink.yield(value, now: start.advanced(by: .seconds(1)))
        sink.finish()
        var snapshots: [PortablePackageImportProgress] = []
        for await snapshot in stream { snapshots.append(snapshot) }
        XCTAssertEqual(snapshots.count, 12)
        XCTAssertEqual(snapshots.first?.phase, .preparing)
        XCTAssertEqual(snapshots.last?.phase, .finished)
        XCTAssertEqual(snapshots.last?.processed, 1000)
        XCTAssertEqual(snapshots.last?.bytesRead, 1000)
    }

    @MainActor
    func testBusyProgressConsumerRetainsOnlyTheLatestSnapshot() async {
        let sink = PortablePackageImportProgressSink()
        let stream = AsyncStream<PortablePackageImportProgress>(bufferingPolicy: .bufferingNewest(1)) {
            sink.install($0)
        }
        let start = ContinuousClock.now
        var value = PortablePackageImportProgress(
            total: 1000, processed: 0, imported: 0, duplicates: 0, failed: 0,
            bytesRead: 0, totalBytes: 1000, currentName: nil, phase: .staging)
        for ordinal in 1...1000 {
            value.processed = ordinal
            sink.yield(value, now: start.advanced(by: .milliseconds(ordinal * 100)))
        }
        value.phase = .finished
        sink.yield(value, now: start.advanced(by: .seconds(101)))
        sink.finish()
        var snapshots: [PortablePackageImportProgress] = []
        for await snapshot in stream { snapshots.append(snapshot) }
        XCTAssertEqual(snapshots, [value])
    }

    private func makeSource(named name: String, contents: Data) throws -> URL {
        let url = tempDirectory.appendingPathComponent(name)
        try contents.write(to: url)
        return url
    }
}

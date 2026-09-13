import Foundation
import XCTest
import os.lock

@testable import KromoraKit

final class PortableLibraryBackupTests: TempDirectoryTestCase {
    func testBackupFlushesBeforeSnapshotPublishesAndExcludesDerived() throws {
        let packageURL = tempDirectory.appendingPathComponent("Source.kromoralibrary")
        let package = try PortableLibraryPackage.create(at: packageURL)
        let sourceURL = tempDirectory.appendingPathComponent("photo.jpg")
        try Data("original bytes".utf8).write(to: sourceURL)
        let lease = try PortablePackageLease.acquire(at: packageURL)
        let imported = try package.importSources([.init(url: sourceURL)], lease: lease)
        try lease.release()

        let derivedURL = packageURL.appendingPathComponent("Derived/Previews/photo.jpg")
        try FileManager.default.createDirectory(
            at: derivedURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data("rebuildable".utf8).write(to: derivedURL)

        var flushCount = 0
        let destination = tempDirectory.appendingPathComponent("Backup.kromoralibrary")
        let result = try package.backup(to: destination, flushPendingEdits: { flushCount += 1 })

        XCTAssertEqual(flushCount, 1)
        XCTAssertEqual(result.copiedFiles, result.totalFiles)
        XCTAssertEqual(result.reusedFiles, 0)
        XCTAssertTrue(PortableLibraryBackup.isVerifiedBackup(at: destination))
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: destination.appendingPathComponent("Derived").path)
        )

        let backup = try PortableLibraryPackage.open(at: destination)
        let assetID = try XCTUnwrap(imported.imported.first?.assetID)
        let record = try backup.readAssetRecord(for: assetID)
        XCTAssertEqual(try Data(contentsOf: backup.embeddedSourceURL(for: record)), Data("original bytes".utf8))
    }

    func testChangedBackupReusesUnchangedFilesAndPublishesOnlyAfterVerification() throws {
        let packageURL = tempDirectory.appendingPathComponent("Incremental.kromoralibrary")
        let package = try PortableLibraryPackage.create(at: packageURL)
        let sourceURL = tempDirectory.appendingPathComponent("incremental.jpg")
        try Data("before".utf8).write(to: sourceURL)
        let lease = try PortablePackageLease.acquire(at: packageURL)
        let imported = try package.importSources([.init(url: sourceURL)], lease: lease)
        try lease.release()

        let destination = tempDirectory.appendingPathComponent("IncrementalBackup.kromoralibrary")
        let first = try package.backup(to: destination)

        let editLease = try PortablePackageLease.acquire(at: packageURL)
        _ = try package.appendEditRevision(
            for: try XCTUnwrap(imported.imported.first?.assetID),
            document: EditDocument(light: .init(exposure: 0.25)), lease: editLease
        )
        try editLease.release()

        let second = try package.backup(to: destination)
        XCTAssertTrue(second.resumed == false)
        XCTAssertGreaterThan(second.reusedFiles, 0)
        XCTAssertLessThan(second.copiedFiles, first.copiedFiles)
        XCTAssertTrue(PortableLibraryBackup.isVerifiedBackup(at: destination))
        XCTAssertEqual(
            try PortableLibraryPackage.open(at: destination)
                .readEditRevision(for: try XCTUnwrap(imported.imported.first?.assetID)).revision,
            1
        )
    }

    func testCancellationLeavesDestinationAbsentAndResumeUsesStaging() throws {
        let packageURL = tempDirectory.appendingPathComponent("Cancellable.kromoralibrary")
        let package = try PortableLibraryPackage.create(at: packageURL)
        let sourceURL = tempDirectory.appendingPathComponent("large.raw")
        try Data(repeating: 0x42, count: 64 * 1024).write(to: sourceURL)
        let lease = try PortablePackageLease.acquire(at: packageURL)
        _ = try package.importSources([.init(url: sourceURL)], lease: lease)
        try lease.release()

        let destination = tempDirectory.appendingPathComponent("CancellableBackup.kromoralibrary")
        let cancellation = OSAllocatedUnfairLock(initialState: false)
        XCTAssertThrowsError(
            try package.backup(
                to: destination,
                options: .init(chunkSize: 97, copyMode: .streamed),
                isCancelled: { cancellation.withLock { $0 } },
                progress: { update in
                    if update.phase == .copying && update.completedFiles >= 3 {
                        cancellation.withLock { $0 = true }
                    }
                }
            )
        ) { error in
            XCTAssertTrue(error is CancellationError, "expected cancellation, got \(error)")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: PortableLibraryBackup.stagingURL(for: destination).path)
        )

        let resumed = try package.backup(to: destination)
        XCTAssertTrue(resumed.resumed)
        XCTAssertTrue(PortableLibraryBackup.isVerifiedBackup(at: destination))
    }

    func testDiskFullLeavesResumableStagingWithoutPublishing() throws {
        let packageURL = tempDirectory.appendingPathComponent("DiskFull.kromoralibrary")
        let package = try PortableLibraryPackage.create(at: packageURL)
        let sourceURL = tempDirectory.appendingPathComponent("disk-full.jpg")
        try Data(repeating: 0x2A, count: 16 * 1024).write(to: sourceURL)
        let lease = try PortablePackageLease.acquire(at: packageURL)
        _ = try package.importSources([.init(url: sourceURL)], lease: lease)
        try lease.release()

        let destination = tempDirectory.appendingPathComponent("DiskFullBackup.kromoralibrary")
        let injector = PortablePackageFaultInjector(failingAt: .diskFull)
        XCTAssertThrowsError(
            try package.backup(
                to: destination,
                options: .init(faultInjector: injector)
            )
        ) { error in
            XCTAssertEqual(
                error as? PortablePackageTransactionError,
                .injectedFailure(.diskFull)
            )
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertFalse(PortableLibraryBackup.isVerifiedBackup(at: destination))
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: PortableLibraryBackup.stagingURL(for: destination).path
            )
        )

        let resumed = try package.backup(to: destination)
        XCTAssertTrue(PortableLibraryBackup.isVerifiedBackup(at: destination))
        XCTAssertEqual(resumed.totalFiles, resumed.verifiedFiles)
    }
}

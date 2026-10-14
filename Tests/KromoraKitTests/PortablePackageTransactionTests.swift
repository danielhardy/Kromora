import Foundation
import XCTest
import os.lock

@testable import KromoraKit

final class PortablePackageTransactionTests: TempDirectoryTestCase {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    func testCommitJournalsStagesChecksumsAndPublishesAtomically() throws {
        let packageURL = try makePackage()
        let lease = try PortablePackageLease.acquire(at: packageURL, ownerID: UUID(), now: now)
        var transaction = try PortablePackageTransaction.begin(
            at: packageURL, lease: lease, now: now)

        try transaction.stage(data: Data("new asset".utf8), at: "Assets/aa/asset.json")
        try transaction.stage(data: Data("new membership".utf8), at: "Catalog/Membership/aa.json")
        try transaction.commit(now: now)

        XCTAssertEqual(
            try String(contentsOf: packageURL.appendingPathComponent("Assets/aa/asset.json"), encoding: .utf8),
            "new asset")
        XCTAssertEqual(
            try String(contentsOf: packageURL.appendingPathComponent("Catalog/Membership/aa.json"), encoding: .utf8),
            "new membership"
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: packageURL.appendingPathComponent("Recovery/Transactions")
                    .appendingPathComponent("\(transaction.transactionID.uuidString).json").path))
        try lease.release()
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: packageURL.appendingPathComponent("manifest.lock").path))
    }

    func testInjectedFailureAtEveryTransactionBoundaryRecoversWithoutPartialFiles() throws {
        for boundary in [
            PortablePackageTransactionBoundary.stage,
            .flush,
            .checksum,
            .publish,
        ] {
            let packageURL = try makePackage()
            let stateURL = packageURL.appendingPathComponent("State/a.txt")
            try FileManager.default.createDirectory(
                at: stateURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("old".utf8).write(to: stateURL)

            let lease = try PortablePackageLease.acquire(at: packageURL, now: now)
            let injector = PortablePackageFaultInjector(failingAt: boundary)
            var transaction = try PortablePackageTransaction.begin(
                at: packageURL, lease: lease, now: now, faultInjector: injector
            )
            if boundary == .stage {
                XCTAssertThrowsError(
                    try transaction.stage(data: Data("new".utf8), at: "State/a.txt")
                ) { error in
                    XCTAssertEqual(
                        error as? PortablePackageTransactionError,
                        .injectedFailure(.stage)
                    )
                }
            } else {
                try transaction.stage(data: Data("new".utf8), at: "State/a.txt")
                try transaction.stage(data: Data("second".utf8), at: "State/b.txt")
                XCTAssertThrowsError(try transaction.commit(now: now)) { error in
                    XCTAssertEqual(
                        error as? PortablePackageTransactionError,
                        .injectedFailure(boundary)
                    )
                }
            }
            try lease.release()
            let report = try PortablePackageTransaction.recover(at: packageURL)
            XCTAssertEqual(report.recoveredTransactionIDs.count, 1, "boundary \(boundary)")
            XCTAssertEqual(try String(contentsOf: stateURL, encoding: .utf8), "old", "boundary \(boundary)")
            XCTAssertFalse(
                FileManager.default.fileExists(
                    atPath: packageURL.appendingPathComponent("State/b.txt").path),
                "boundary \(boundary)"
            )
        }
    }

    func testLeaseContentionRenewalExpiryAndExplicitBreaking() throws {
        let packageURL = try makePackage()
        let first = try PortablePackageLease.acquire(
            at: packageURL, ownerID: UUID(), deviceName: "first-device", now: now, duration: 10
        )
        XCTAssertThrowsError(
            try PortablePackageLease.acquire(at: packageURL, ownerID: UUID(), now: now)
        ) { error in
            guard case .contended(let info) = error as? PortablePackageLeaseError else {
                return XCTFail("expected explicit lease contention, got \(error)")
            }
            XCTAssertEqual(info.deviceName, "first-device")
        }

        let injector = PortablePackageFaultInjector(failingAt: .leaseRenewal)
        XCTAssertThrowsError(try first.renew(now: now, faultInjector: injector)) { error in
            XCTAssertEqual(
                error as? PortablePackageTransactionError, .injectedFailure(.leaseRenewal))
        }
        XCTAssertTrue(first.isExpired(at: now.addingTimeInterval(11)))
        XCTAssertThrowsError(
            try PortablePackageLease.acquire(
                at: packageURL, ownerID: UUID(), now: now.addingTimeInterval(11))
        ) { error in
            guard case .expired = error as? PortablePackageLeaseError else {
                return XCTFail("expected explicit expired lease, got \(error)")
            }
        }
        try PortablePackageLease.breakExpired(at: packageURL, now: now.addingTimeInterval(11))
        let replacement = try PortablePackageLease.acquire(
            at: packageURL, ownerID: UUID(), now: now)
        try replacement.release()
    }

    func testRecoverExpiredWriterRollsBackThenAllowsANewLease() throws {
        let packageURL = try makePackage()
        let stateURL = packageURL.appendingPathComponent("State/value.txt")
        try FileManager.default.createDirectory(
            at: stateURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("old".utf8).write(to: stateURL)

        let stale = try acquireRemoteLease(at: packageURL, duration: 10)
        let injector = PortablePackageFaultInjector(failingAt: .publish)
        var transaction = try PortablePackageTransaction.begin(
            at: packageURL, lease: stale, now: now, faultInjector: injector
        )
        try transaction.stage(data: Data("new".utf8), at: "State/value.txt")
        XCTAssertThrowsError(try transaction.commit(now: now))

        let later = now.addingTimeInterval(11)
        try PortablePackageLease.recoverExpiredWriter(at: packageURL, now: later)
        XCTAssertEqual(try String(contentsOf: stateURL, encoding: .utf8), "old")
        let replacement = try PortablePackageLease.acquire(at: packageURL, now: later)
        try replacement.release()
        _ = stale
    }

    /// Stages an uncommitted transaction (commit fails at `.publish`) and returns the paths to watch.
    private func stageInterruptedTransaction(
        lease: PortablePackageLease, packageURL: URL
    ) throws -> (journalDirectory: URL, lockBytes: () throws -> Data) {
        let injector = PortablePackageFaultInjector(failingAt: .publish)
        var transaction = try PortablePackageTransaction.begin(
            at: packageURL, lease: lease, now: now, faultInjector: injector)
        try transaction.stage(data: Data("new".utf8), at: "State/value.txt")
        XCTAssertThrowsError(try transaction.commit(now: now))
        let lockURL = packageURL.appendingPathComponent("manifest.lock")
        return (
            packageURL.appendingPathComponent("Recovery/Transactions"),
            { try Data(contentsOf: lockURL) }
        )
    }

    private func journalCount(_ directory: URL) -> Int {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil)) ?? []
        return urls.filter { $0.pathExtension == "json" }.count
    }

    /// Simulates a writer on another host so expiry recovery tests do not classify this still-live
    /// test process as the package writer.
    private func acquireRemoteLease(
        at packageURL: URL, duration: TimeInterval = PortablePackageLease.defaultDuration
    ) throws -> PortablePackageLease {
        try PortablePackageLease.acquire(
            at: packageURL,
            processID: .max,
            writerHostID: "another-host",
            processStartedAt: "1:0",
            now: now,
            duration: duration
        )
    }

    func testRecoverExpiredWriterRejectsUnexpiredLeaseWithoutTouchingJournal() throws {
        let packageURL = try makePackage()
        let lease = try PortablePackageLease.acquire(at: packageURL, now: now, duration: 10)
        let watched = try stageInterruptedTransaction(lease: lease, packageURL: packageURL)
        let lockBefore = try watched.lockBytes()

        XCTAssertThrowsError(try PortablePackageLease.recoverExpiredWriter(at: packageURL, now: now)) {
            guard case .contended = $0 as? PortablePackageLeaseError else {
                return XCTFail("expected contention, got \($0)")
            }
        }
        XCTAssertEqual(journalCount(watched.journalDirectory), 1)
        XCTAssertEqual(try watched.lockBytes(), lockBefore)
        XCTAssertNoThrow(try lease.assertOwnership(at: now))
    }

    func testRecoverExpiredWriterDoesNotRollbackALiveLocalWriterAfterExpiry() throws {
        let packageURL = try makePackage()
        let lease = try PortablePackageLease.acquire(at: packageURL, now: now, duration: 10)
        XCTAssertEqual(lease.info.localWriterState, .live)
        let watched = try stageInterruptedTransaction(lease: lease, packageURL: packageURL)
        let lockBefore = try watched.lockBytes()
        let later = now.addingTimeInterval(11)

        XCTAssertThrowsError(
            try PortablePackageLease.recoverExpiredWriter(at: packageURL, now: later)
        ) {
            guard case .contended = $0 as? PortablePackageLeaseError else {
                return XCTFail("expected contention with a live local writer, got \($0)")
            }
        }
        XCTAssertEqual(journalCount(watched.journalDirectory), 1)
        XCTAssertEqual(try watched.lockBytes(), lockBefore)
    }

    /// Same-process, real package and lock files. The first read saw an expired lease; the owner
    /// then renewed, so the recoverer's own exclusive re-read must reject the takeover.
    func testRecoverExpiredWriterSparesOwnerThatRenewedAfterExpiryWasObserved() throws {
        let packageURL = try makePackage()
        let lease = try acquireRemoteLease(at: packageURL, duration: 10)
        let watched = try stageInterruptedTransaction(lease: lease, packageURL: packageURL)
        let later = now.addingTimeInterval(11)
        XCTAssertThrowsError(try PortablePackageLease.acquire(at: packageURL, now: later)) {
            guard case .expired = $0 as? PortablePackageLeaseError else {
                return XCTFail("expected expiry observation, got \($0)")
            }
        }
        try lease.renew(now: now.addingTimeInterval(9))
        let lockBefore = try watched.lockBytes()

        XCTAssertThrowsError(try PortablePackageLease.recoverExpiredWriter(at: packageURL, now: later)) {
            guard case .contended = $0 as? PortablePackageLeaseError else {
                return XCTFail("expected contention, got \($0)")
            }
        }
        XCTAssertEqual(journalCount(watched.journalDirectory), 1)
        XCTAssertEqual(try watched.lockBytes(), lockBefore)
        XCTAssertNoThrow(try lease.assertOwnership(at: later))
    }

    func testRecoverExpiredWriterFencesTheFormerOwnerDuringRollback() throws {
        let packageURL = try makePackage()
        let lease = try acquireRemoteLease(at: packageURL, duration: 10)
        _ = try stageInterruptedTransaction(lease: lease, packageURL: packageURL)
        let later = now.addingTimeInterval(11)

        try PortablePackageLease.recoverExpiredWriter(at: packageURL, now: later) {
            XCTAssertThrowsError(try lease.renew(now: later))
            XCTAssertThrowsError(
                try PortablePackageLease.acquire(at: packageURL, now: later)
            ) {
                guard case .contended = $0 as? PortablePackageLeaseError else {
                    return XCTFail("expected contention during rollback, got \($0)")
                }
            }
        }
        let replacement = try PortablePackageLease.acquire(at: packageURL, now: later)
        try replacement.release()
    }

    func testOnlyOneConcurrentRecovererRollsBackAnExpiredWriter() throws {
        let packageURL = try makePackage()
        let lease = try acquireRemoteLease(at: packageURL, duration: 10)
        let watched = try stageInterruptedTransaction(lease: lease, packageURL: packageURL)
        let later = now.addingTimeInterval(11)
        let successes = OSAllocatedUnfairLock(initialState: 0)

        DispatchQueue.concurrentPerform(iterations: 8) { _ in
            if (try? PortablePackageLease.recoverExpiredWriter(at: packageURL, now: later)) != nil {
                successes.withLock { $0 += 1 }
            }
        }
        XCTAssertGreaterThanOrEqual(successes.withLock { $0 }, 1)
        XCTAssertEqual(journalCount(watched.journalDirectory), 0)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: packageURL.appendingPathComponent("manifest.lock").path))
    }

    func testFailureAfterOwnershipCheckLeavesJournalVisibleToTheNextRecovery() throws {
        let packageURL = try makePackage()
        let stateURL = packageURL.appendingPathComponent("State/value.txt")
        try FileManager.default.createDirectory(
            at: stateURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("old".utf8).write(to: stateURL)
        let lease = try acquireRemoteLease(at: packageURL, duration: 10)
        let watched = try stageInterruptedTransaction(lease: lease, packageURL: packageURL)
        let later = now.addingTimeInterval(11)

        XCTAssertThrowsError(
            try PortablePackageLease.recoverExpiredWriter(at: packageURL, now: later) {
                throw PortablePackageTransactionError.injectedFailure(.publish)
            })
        XCTAssertEqual(journalCount(watched.journalDirectory), 1)
        XCTAssertThrowsError(try PortablePackageLease.acquire(at: packageURL, now: later)) {
            guard case .expired = $0 as? PortablePackageLeaseError else {
                return XCTFail("next opener must still see the expired writer, got \($0)")
            }
        }
        try PortablePackageLease.recoverExpiredWriter(at: packageURL, now: later)
        XCTAssertEqual(journalCount(watched.journalDirectory), 0)
        XCTAssertEqual(try String(contentsOf: stateURL, encoding: .utf8), "old")
    }

    func testDeadLocalWriterRecoversBeforeLeaseExpiryAndRollsBackFirst() throws {
        let packageURL = try makePackage()
        let stateURL = packageURL.appendingPathComponent("State/value.txt")
        try FileManager.default.createDirectory(
            at: stateURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("old".utf8).write(to: stateURL)
        let hostID = try XCTUnwrap(PortablePackageLeaseInfo.currentProcessIdentity.hostID)
        let deadLease = try PortablePackageLease.acquire(
            at: packageURL, deviceName: "same-mac", processID: .max,
            writerHostID: hostID, processStartedAt: "1:0", now: now, duration: 180
        )
        XCTAssertGreaterThan(deadLease.info.expiresAt, now)
        XCTAssertEqual(deadLease.info.localWriterState, .dead)

        let injector = PortablePackageFaultInjector(failingAt: .publish)
        var transaction = try PortablePackageTransaction.begin(
            at: packageURL, lease: deadLease, now: now, faultInjector: injector
        )
        try transaction.stage(data: Data("new".utf8), at: "State/value.txt")
        XCTAssertThrowsError(try transaction.commit(now: now))

        try PortablePackageLease.recoverDeadWriter(at: packageURL)
        XCTAssertEqual(try String(contentsOf: stateURL, encoding: .utf8), "old")
        let replacement = try PortablePackageLease.acquire(at: packageURL, now: now)
        try replacement.release()
        _ = deadLease
    }

    func testLiveRemoteAndReusedPIDIdentityClassification() throws {
        let packageURL = try makePackage()
        let hostID = try XCTUnwrap(PortablePackageLeaseInfo.currentProcessIdentity.hostID)
        let currentStart = try XCTUnwrap(PortablePackageLeaseInfo.currentProcessIdentity.startedAt)
        let live = try PortablePackageLease.acquire(
            at: packageURL, writerHostID: hostID, processStartedAt: currentStart, now: now)
        XCTAssertEqual(live.info.localWriterState, .live)
        XCTAssertThrowsError(try PortablePackageLease.acquire(at: packageURL, now: now)) { error in
            guard case .contended(let info) = error as? PortablePackageLeaseError else {
                return XCTFail("expected live writer contention, got \(error)")
            }
            XCTAssertEqual(info.localWriterState, .live)
        }
        try live.release()

        let remote = try PortablePackageLease.acquire(
            at: packageURL, processID: .max, writerHostID: "another-host",
            processStartedAt: "1:0", now: now
        )
        XCTAssertEqual(remote.info.localWriterState, .remoteOrUnknown)
        try remote.release()

        let reusedPID = try PortablePackageLease.acquire(
            at: packageURL, writerHostID: hostID, processStartedAt: "1:0", now: now
        )
        XCTAssertEqual(reusedPID.info.localWriterState, .dead)
        try reusedPID.release()
    }

    func testLeaseLossPreventsPublishAndRecoveryCanRollBack() throws {
        let packageURL = try makePackage()
        let lease = try PortablePackageLease.acquire(at: packageURL, now: now)
        let injector = PortablePackageFaultInjector(failingAt: .leaseLoss)
        var transaction = try PortablePackageTransaction.begin(
            at: packageURL, lease: lease, now: now, faultInjector: injector
        )
        try transaction.stage(data: Data("new".utf8), at: "State/value.txt")
        XCTAssertThrowsError(try transaction.commit(now: now)) { error in
            XCTAssertEqual(error as? PortablePackageTransactionError, .injectedFailure(.leaseLoss))
        }
        try lease.release()
        _ = try PortablePackageTransaction.recover(at: packageURL)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: packageURL.appendingPathComponent("State/value.txt").path))
    }

    func testRecoveryDiscardsUnflushedStagingAndPreservesExistingTarget() throws {
        let packageURL = try makePackage()
        let lease = try PortablePackageLease.acquire(at: packageURL, now: now)
        defer { try? lease.release() }
        let target = packageURL.appendingPathComponent("State/value.txt")
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("old".utf8).write(to: target)
        var transaction = try PortablePackageTransaction.begin(at: packageURL, lease: lease, now: now)
        try transaction.stage(data: Data("new".utf8), at: "State/value.txt")
        // Simulate restart before commit, using only the durable begin journal.
        let recovery = try PortablePackageTransaction.recover(at: packageURL)
        XCTAssertEqual(recovery.recoveredTransactionIDs, [transaction.transactionID])
        XCTAssertEqual(try Data(contentsOf: target), Data("old".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: packageURL
            .appendingPathComponent("Recovery/Staging/\(transaction.transactionID.uuidString)").path))
    }

    func testCommitStillDetectsStagedCorruptionBeforePublishing() throws {
        let packageURL = try makePackage()
        let lease = try PortablePackageLease.acquire(at: packageURL, now: now)
        defer { try? lease.release() }
        var transaction = try PortablePackageTransaction.begin(at: packageURL, lease: lease, now: now)
        let path = "State/value.txt"
        try transaction.stage(data: Data("good".utf8), at: path)
        try Data("evil".utf8).write(to: transaction.stagedURL(for: path))
        XCTAssertThrowsError(try transaction.commit(now: now)) { error in
            guard case .checksumMismatch = error as? PortablePackageTransactionError else {
                return XCTFail("expected checksum mismatch, got \(error)")
            }
        }
        try transaction.abort()
        XCTAssertFalse(FileManager.default.fileExists(atPath: packageURL.appendingPathComponent(path).path))
    }

    func testCancellationDuringCommitChecksumIsBoundedAndRollsBack() throws {
        let packageURL = try makePackage()
        let lease = try PortablePackageLease.acquire(at: packageURL, now: now)
        defer { try? lease.release() }
        var transaction = try PortablePackageTransaction.begin(at: packageURL, lease: lease, now: now)
        let path = "State/large.raw"
        try transaction.stage(data: Data(repeating: 0x52, count: 8 << 20), at: path)
        let cancellation = PortablePackageImportCancellation()
        let checks = OSAllocatedUnfairLock(initialState: 0)
        XCTAssertThrowsError(try transaction.commit(now: now, isCancelled: {
            let count = checks.withLock { $0 += 1; return $0 }
            if count == 6 { cancellation.cancel() }
            return cancellation.isCancelled
        })) { XCTAssertTrue($0 is CancellationError) }
        XCTAssertEqual(checks.withLock { $0 }, 6)
        try transaction.abort()
        XCTAssertFalse(FileManager.default.fileExists(atPath: packageURL.appendingPathComponent(path).path))
    }

    /// Staging can fail when the destination path is already a directory. The thrown CocoaError
    /// must keep `NSURLErrorKey` as a URL so `localizedDescription` can be read without aborting
    /// inside Foundation's Cocoa error formatter.
    func testStageFailureSurfacesReadableCocoaErrorDescription() throws {
        let packageURL = try makePackage()
        let lease = try PortablePackageLease.acquire(at: packageURL, ownerID: UUID(), now: now)
        var transaction = try PortablePackageTransaction.begin(
            at: packageURL, lease: lease, now: now)

        let blockingDirectory = packageURL
            .appendingPathComponent("Recovery/Staging")
            .appendingPathComponent(transaction.transactionID.uuidString)
            .appendingPathComponent("State/value.txt")
        try FileManager.default.createDirectory(
            at: blockingDirectory, withIntermediateDirectories: true)

        XCTAssertThrowsError(try transaction.stage(data: Data("new".utf8), at: "State/value.txt")) {
            error in
            let cocoa = error as? CocoaError
            XCTAssertEqual(cocoa?.code, .fileWriteUnknown)
            let reportedURL = cocoa?.userInfo[NSURLErrorKey] as? URL
            XCTAssertNotNil(reportedURL, "NSURLErrorKey must be a URL, not a path String")
            XCTAssertEqual(
                reportedURL?.standardizedFileURL.path, blockingDirectory.standardizedFileURL.path)
            // Accessing this used to abort when NSURLErrorKey held a path String.
            XCTAssertFalse(error.localizedDescription.isEmpty)
        }
        try lease.release()
    }

    private func makePackage() throws -> URL {
        let url = tempDirectory.appendingPathComponent(
            "Library-\(UUID().uuidString).kromoralibrary")
        _ = try PortableLibraryPackage.create(at: url)
        return url
    }
}

final class FullSyncDirectoryTests: TempDirectoryTestCase {
    func testMissingDirectoryThrows() {
        let missing = tempDirectory.appendingPathComponent("does-not-exist")
        XCTAssertThrowsError(try fullSyncDirectory(missing))
    }

    func testExistingDirectorySyncs() throws {
        XCTAssertNoThrow(try fullSyncDirectory(tempDirectory))
    }

    /// APFS will not fail a directory sync on demand, so the `sync` seam injects the failure.
    func testSyncFailureIsPropagated() {
        struct Injected: Error {}
        XCTAssertThrowsError(try fullSyncDirectory(tempDirectory, sync: { _ in throw Injected() })) {
            XCTAssertTrue($0 is Injected)
        }
    }
}

import Foundation
import XCTest
import os.lock

@testable import KromoraKit

/// Rollback must converge to the pre-transaction state however often and wherever it is
/// interrupted. The interruption points are explicit test seams, not process-kill timing.
final class PortablePackageTransactionTests_RollbackRetry: TempDirectoryTestCase {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    private struct Interrupted: Error {}

    private func makePackage() throws -> URL {
        let url = tempDirectory.appendingPathComponent(
            "Library-\(UUID().uuidString).kromoralibrary")
        _ = try PortableLibraryPackage.create(at: url)
        return url
    }

    private func read(_ package: URL, _ path: String) -> String? {
        try? String(contentsOf: package.appendingPathComponent(path), encoding: .utf8)
    }

    private func journalURLs(_ package: URL) -> [URL] {
        let directory = package.appendingPathComponent("Recovery/Transactions")
        return ((try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil)) ?? []).filter {
            $0.pathExtension == "json"
        }
    }

    /// A mixed file, move, and removal transaction, fully published but not committed.
    private func interruptedPackage() throws -> URL {
        let package = try makePackage()
        for (path, text) in [("State/a.txt", "oldA"), ("State/b.txt", "oldB")] {
            let url = package.appendingPathComponent(path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url)
        }
        let moveSource = package.appendingPathComponent("State/move-source.txt")
        try Data("move".utf8).write(to: moveSource)
        let removalTarget = package.appendingPathComponent("Recovery/Quarantine/trash.txt")
        try FileManager.default.createDirectory(
            at: removalTarget.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("trash".utf8).write(to: removalTarget)
        let lease = try PortablePackageLease.acquire(at: package, ownerID: UUID(), now: now)
        var transaction = try PortablePackageTransaction.begin(
            at: package, lease: lease, now: now)
        try transaction.stage(data: Data("newA".utf8), at: "State/a.txt")
        try transaction.stage(data: Data("newB".utf8), at: "State/b.txt")
        try transaction.stage(data: Data("newC".utf8), at: "State/c.txt")
        try transaction.stageMove(from: "State/move-source.txt", to: "State/move-target.txt")
        try transaction.stageRemoval(at: "Recovery/Quarantine/trash.txt")
        // Fail the final "committed" fence so every file is published but the journal is not.
        let calls = OSAllocatedUnfairLock(initialState: 0)
        XCTAssertThrowsError(
            try transaction.commit(now: now, afterOwnershipCheck: {
                let call = calls.withLock { n -> Int in n += 1; return n }
                if call == 8 { throw Interrupted() }
            }))
        XCTAssertEqual(read(package, "State/a.txt"), "newA")
        XCTAssertEqual(read(package, "State/c.txt"), "newC")
        XCTAssertEqual(read(package, "State/move-target.txt"), "move")
        XCTAssertNil(read(package, "State/move-source.txt"))
        XCTAssertNil(read(package, "Recovery/Quarantine/trash.txt"))
        XCTAssertEqual(journalURLs(package).count, 1)
        try lease.release()
        return package
    }

    private func assertPreTransaction(_ package: URL, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(read(package, "State/a.txt"), "oldA", file: file, line: line)
        XCTAssertEqual(read(package, "State/b.txt"), "oldB", file: file, line: line)
        XCTAssertNil(read(package, "State/c.txt"), file: file, line: line)
        XCTAssertEqual(read(package, "State/move-source.txt"), "move", file: file, line: line)
        XCTAssertNil(read(package, "State/move-target.txt"), file: file, line: line)
        XCTAssertEqual(read(package, "Recovery/Quarantine/trash.txt"), "trash", file: file, line: line)
    }

    /// The review's reproduction: rollback restored the file and stopped before journal cleanup.
    func testRetryAfterRestoreKeepsRestoredTargetWhenJournalRemains() throws {
        let package = try makePackage()
        let stateURL = package.appendingPathComponent("State/value.txt")
        try FileManager.default.createDirectory(
            at: stateURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("old".utf8).write(to: stateURL)
        let lease = try PortablePackageLease.acquire(at: package, ownerID: UUID(), now: now)
        var transaction = try PortablePackageTransaction.begin(
            at: package, lease: lease, now: now,
            faultInjector: PortablePackageFaultInjector(failingAt: .publish))
        try transaction.stage(data: Data("new".utf8), at: "State/value.txt")
        XCTAssertThrowsError(try transaction.commit(now: now))
        try lease.release()

        let journal = try XCTUnwrap(journalURLs(package).first)
        let decoded = try PackageJSONCoder.decode(
            PortablePackageTransactionJournal.self, from: Data(contentsOf: journal))
        let backup = try XCTUnwrap(decoded.files.first?.backupPath)
        try FileManager.default.removeItem(at: stateURL)
        try FileManager.default.moveItem(at: URL(fileURLWithPath: backup), to: stateURL)

        _ = try PortablePackageTransaction.recover(at: package)
        XCTAssertEqual(read(package, "State/value.txt"), "old")
    }

    func testInterruptionAtEveryRestorePointConvergesOnRetry() throws {
        // Count the points in one clean run first.
        let probe = try interruptedPackage()
        let seen = OSAllocatedUnfairLock(initialState: 0)
        _ = try PortablePackageTransaction.recover(at: probe) { _ in
            seen.withLock { $0 += 1 }
        }
        assertPreTransaction(probe)
        let total = seen.withLock { $0 }
        XCTAssertGreaterThan(total, 30)

        for failAt in 1...total {
            let package = try interruptedPackage()
            let count = OSAllocatedUnfairLock(initialState: 0)
            XCTAssertThrowsError(
                try PortablePackageTransaction.recover(at: package) { _ in
                    let n = count.withLock { n -> Int in n += 1; return n }
                    if n == failAt { throw Interrupted() }
                }, "interruption \(failAt)")
            XCTAssertEqual(journalURLs(package).count, 1, "journal kept after interruption \(failAt)")
            // Retry repeatedly: the second retry must also leave the same state.
            for _ in 0..<2 {
                _ = try PortablePackageTransaction.recover(at: package)
                assertPreTransaction(package)
            }
            XCTAssertEqual(journalURLs(package).count, 0)
        }
    }

    func testLegacyJournalWithIdenticalOldAndNewBytesPreservesRestoredTarget() throws {
        let package = try makePackage()
        let stateURL = package.appendingPathComponent("State/value.txt")
        try FileManager.default.createDirectory(
            at: stateURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("same".utf8).write(to: stateURL)
        let lease = try PortablePackageLease.acquire(at: package, ownerID: UUID(), now: now)
        var transaction = try PortablePackageTransaction.begin(
            at: package, lease: lease, now: now,
            faultInjector: PortablePackageFaultInjector(failingAt: .publish))
        try transaction.stage(data: Data("same".utf8), at: "State/value.txt")
        XCTAssertThrowsError(try transaction.commit(now: now))
        try lease.release()

        let journal = try XCTUnwrap(journalURLs(package).first)
        let decoded = try PackageJSONCoder.decode(
            PortablePackageTransactionJournal.self, from: Data(contentsOf: journal))
        let backup = try XCTUnwrap(decoded.files.first?.backupPath)
        try FileManager.default.removeItem(at: stateURL)
        try FileManager.default.moveItem(at: URL(fileURLWithPath: backup), to: stateURL)

        _ = try PortablePackageTransaction.recover(at: package)
        XCTAssertEqual(read(package, "State/value.txt"), "same")
    }

    func testRecoveryErrorRetainsJournalAndBackupEvidence() throws {
        let package = try makePackage()
        let stateURL = package.appendingPathComponent("State/value.txt")
        try FileManager.default.createDirectory(
            at: stateURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("old".utf8).write(to: stateURL)
        let lease = try PortablePackageLease.acquire(at: package, ownerID: UUID(), now: now)
        var transaction = try PortablePackageTransaction.begin(
            at: package, lease: lease, now: now,
            faultInjector: PortablePackageFaultInjector(failingAt: .publish))
        try transaction.stage(data: Data("new".utf8), at: "State/value.txt")
        XCTAssertThrowsError(try transaction.commit(now: now))
        try lease.release()

        let journal = try XCTUnwrap(journalURLs(package).first)
        var decoded = try PackageJSONCoder.decode(
            PortablePackageTransactionJournal.self, from: Data(contentsOf: journal))
        decoded.files[0].publicationState = .started
        try PackageJSONCoder.encode(decoded).write(to: journal)
        let backup = try XCTUnwrap(decoded.files.first?.backupPath)
        try FileManager.default.removeItem(at: stateURL)
        try FileManager.default.removeItem(at: URL(fileURLWithPath: backup))

        XCTAssertThrowsError(try PortablePackageTransaction.recover(at: package))
        XCTAssertEqual(journalURLs(package).count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: journal.path))
    }

    func testRetainedJournalAfterCompletedRollbackCannotDeleteRestoredTargets() throws {
        let package = try interruptedPackage()
        XCTAssertThrowsError(try PortablePackageTransaction.recover(at: package) { point in
            if case .beforeJournalCleanup = point {
                throw Interrupted()
            }
        })
        assertPreTransaction(package)
        XCTAssertEqual(journalURLs(package).count, 1)
        // The injected cleanup interruption leaves the fully restored journal on disk.
        for _ in 0..<2 {
            _ = try PortablePackageTransaction.recover(at: package)
            assertPreTransaction(package)
        }
    }
}

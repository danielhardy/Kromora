import Foundation
import XCTest
import os.lock

@testable import KromoraKit

/// Rollback must converge to the pre-transaction state however often and wherever it is
/// interrupted. The interruption points are explicit test seams, not process-kill timing.
final class PortablePackageRollbackRetryTests: TempDirectoryTestCase {
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

    /// Two replaced files and one new file, all published, with the journal still uncommitted.
    private func interruptedPackage() throws -> URL {
        let package = try makePackage()
        for (path, text) in [("State/a.txt", "oldA"), ("State/b.txt", "oldB")] {
            let url = package.appendingPathComponent(path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url)
        }
        let lease = try PortablePackageLease.acquire(at: package, ownerID: UUID(), now: now)
        var transaction = try PortablePackageTransaction.begin(
            at: package, lease: lease, now: now)
        try transaction.stage(data: Data("newA".utf8), at: "State/a.txt")
        try transaction.stage(data: Data("newB".utf8), at: "State/b.txt")
        try transaction.stage(data: Data("newC".utf8), at: "State/c.txt")
        // Fail the final "committed" fence so every file is published but the journal is not.
        let calls = OSAllocatedUnfairLock(initialState: 0)
        XCTAssertThrowsError(
            try transaction.commit(now: now, afterOwnershipCheck: {
                let call = calls.withLock { n -> Int in n += 1; return n }
                if call == 6 { throw Interrupted() }
            }))
        XCTAssertEqual(read(package, "State/a.txt"), "newA")
        XCTAssertEqual(read(package, "State/c.txt"), "newC")
        XCTAssertEqual(journalURLs(package).count, 1)
        try lease.release()
        return package
    }

    private func assertPreTransaction(_ package: URL, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(read(package, "State/a.txt"), "oldA", file: file, line: line)
        XCTAssertEqual(read(package, "State/b.txt"), "oldB", file: file, line: line)
        XCTAssertNil(read(package, "State/c.txt"), file: file, line: line)
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
        XCTAssertEqual(total, 8)  // four points for each of the two replaced files

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

    func testRetainedJournalAfterCompletedRollbackCannotDeleteRestoredTargets() throws {
        let package = try interruptedPackage()
        let retained = OSAllocatedUnfairLock<Data?>(initialState: nil)
        let journalURL = try XCTUnwrap(journalURLs(package).first)
        _ = try PortablePackageTransaction.recover(at: package) { point in
            if case .afterRestoredMarker = point {
                retained.withLock { $0 = try? Data(contentsOf: journalURL) }
            }
        }
        assertPreTransaction(package)
        // Journal cleanup failed: the journal from the end of rollback remains on disk.
        try XCTUnwrap(retained.withLock { $0 }).write(to: journalURL)
        for _ in 0..<2 {
            _ = try PortablePackageTransaction.recover(at: package)
            assertPreTransaction(package)
        }
    }
}

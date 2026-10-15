import Foundation
import XCTest
import os.lock

@testable import KromoraKit

/// KRMA-931: culling changes persist off the main actor, one transaction per membership shard,
/// ordered last-write-wins, and are flushed before shutdown.
@MainActor
final class CullingStateBatchWriteTests: TempDirectoryTestCase {
    private func makeSession(
        assetCount: Int, scheduler: ImageWorkScheduler? = nil
    ) throws -> (PortableLibrarySession, URL, [PortablePhotoAssetID]) {
        let packageURL = tempDirectory.appendingPathComponent("Culling.kromoralibrary")
        let indexURL = tempDirectory.appendingPathComponent("CullingIndex/LibraryIndex.store")
        let session = try PortableLibrarySession(
            at: packageURL, indexURL: indexURL, scheduler: scheduler
        )
        var sources: [URL] = []
        for ordinal in 0..<assetCount {
            sources.append(try Fixtures.writeJPEG(
                width: 16 + ordinal, height: 12 + ordinal, orientation: 1,
                named: "culling-\(ordinal).jpg", in: tempDirectory
            ))
        }
        let result = try session.importURLs(sources)
        XCTAssertEqual(result.imported.count, assetCount)
        return (session, packageURL, result.imported.map(\.assetID))
    }

    private func updates(_ ids: [PortablePhotoAssetID], rating: Int, flag: PhotoFlag)
        -> [PortableLibrarySession.LibraryStateUpdate]
    {
        ids.map { .init(assetID: $0, rating: rating, flag: flag) }
    }

    private func reopenedStates(_ packageURL: URL) throws -> [PortablePhotoAssetID: (Int?, String?)] {
        let package = try PortableLibraryPackage.open(at: packageURL)
        var states: [PortablePhotoAssetID: (Int?, String?)] = [:]
        let directory = try package.membershipURL(for: "00").deletingLastPathComponent()
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        for file in files where file.hasSuffix(".json") {
            let name = String(file.dropLast(".json".count))
            guard PortableLibraryPackage.isValidShard(name) else { continue }
            for entry in try package.readMembershipShard(name).entries where !entry.isTombstone {
                states[entry.assetID] = (entry.summary.rating, entry.summary.flag)
            }
        }
        return states
    }

    func testBatchCommitsOneTransactionPerShardAndPersists() throws {
        let (session, packageURL, ids) = try makeSession(assetCount: 50)
        let committed = ShardLog()
        _ = try PortableLibrarySession.writeLibraryState(
            updates(ids, rating: 4, flag: .pick),
            package: session.package, lease: session.lease, now: Date(),
            didCommitShard: { committed.append($0) }
        )
        let shards = Set(ids.map { PortableLibraryPackage.shard(for: $0) })
        XCTAssertGreaterThan(shards.count, 1)
        XCTAssertEqual(committed.values.sorted(), shards.sorted())
        try session.lease.release()

        let states = try reopenedStates(packageURL)
        for id in ids {
            XCTAssertEqual(states[id]?.0, 4)
            XCTAssertEqual(states[id]?.1, PhotoFlag.pick.rawValue)
        }
    }

    func testUnchangedBatchCommitsNothing() throws {
        let (session, _, ids) = try makeSession(assetCount: 5)
        try session.updateLibraryState(updates(ids, rating: 2, flag: .pick))
        let committed = ShardLog()
        _ = try PortableLibrarySession.writeLibraryState(
            updates(ids, rating: 2, flag: .pick),
            package: session.package, lease: session.lease, now: Date(),
            didCommitShard: { committed.append($0) }
        )
        XCTAssertTrue(committed.values.isEmpty)
    }

    func testClampedUnchangedBatchCommitsNothing() throws {
        let (session, _, ids) = try makeSession(assetCount: 1)
        try session.updateLibraryState(for: ids[0], rating: 5, flag: .pick)
        let committed = ShardLog()
        _ = try PortableLibrarySession.writeLibraryState(
            updates(ids, rating: 9, flag: .pick),
            package: session.package, lease: session.lease, now: Date(),
            didCommitShard: { committed.append($0) }
        )
        XCTAssertTrue(committed.values.isEmpty)
    }

    func testMissingAssetThrowsAssetNotFound() throws {
        let (session, _, _) = try makeSession(assetCount: 1)
        XCTAssertThrowsError(
            try session.updateLibraryState(for: PortablePhotoAssetID(uuid: UUID()), rating: 3, flag: .none)
        )
    }

    func testRatingIsClamped() throws {
        let (session, packageURL, ids) = try makeSession(assetCount: 1)
        try session.updateLibraryState(for: ids[0], rating: 9, flag: .none)
        try session.lease.release()
        XCTAssertEqual(try reopenedStates(packageURL)[ids[0]]?.0, 5)
    }

    func testRapidSuccessiveEnqueuesEndAtLastValue() async throws {
        let scheduler = ImageWorkScheduler()
        let (session, packageURL, ids) = try makeSession(assetCount: 3, scheduler: scheduler)
        session.enqueueLibraryStateUpdates(updates([ids[0]], rating: 1, flag: .none)) { _ in
            XCTFail("unexpected failure")
        }
        session.enqueueLibraryStateUpdates(updates([ids[0]], rating: 5, flag: .pick)) { _ in
            XCTFail("unexpected failure")
        }
        await session.flushPendingLibraryState()
        await session.shutdown()

        let states = try reopenedStates(packageURL)
        XCTAssertEqual(states[ids[0]]?.0, 5)
        XCTAssertEqual(states[ids[0]]?.1, PhotoFlag.pick.rawValue)
    }

    /// KRMA-1006: the shutdown projection write is awaited off the main actor and a failure is
    /// reported, not dropped. External-volume timing was not measured; these use a temp package.
    func testShutdownReportsIndexWriteFailure() async throws {
        let scheduler = ImageWorkScheduler()
        let (session, _, ids) = try makeSession(assetCount: 2, scheduler: scheduler)
        var reported: [String] = []
        session.onIndexWriteFailure = { reported.append($0) }
        session.enqueueLibraryStateUpdates(updates(ids, rating: 2, flag: .pick)) { _ in
            XCTFail("unexpected failure")
        }
        await session.flushPendingLibraryState()
        // Make the index directory read-only so the projection write fails.
        let indexDirectory = session.indexURL.deletingLastPathComponent()
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: indexDirectory.path)
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o700], ofItemAtPath: indexDirectory.path)
        }
        reported.removeAll()
        await session.shutdown()
        XCTAssertFalse(reported.isEmpty)
    }

    func testShutdownWritesIndexBeforeReturning() async throws {
        let scheduler = ImageWorkScheduler()
        let (session, _, ids) = try makeSession(assetCount: 2, scheduler: scheduler)
        session.enqueueLibraryStateUpdates(updates(ids, rating: 2, flag: .pick)) { _ in
            XCTFail("unexpected failure")
        }
        await session.flushPendingLibraryState()
        try? FileManager.default.removeItem(at: session.indexURL)
        await session.shutdown()
        XCTAssertTrue(FileManager.default.fileExists(atPath: session.indexURL.path))
    }

    func testShutdownFlushesPendingWrites() async throws {
        let scheduler = ImageWorkScheduler()
        let (session, packageURL, ids) = try makeSession(assetCount: 20, scheduler: scheduler)
        session.enqueueLibraryStateUpdates(updates(ids, rating: 3, flag: .reject)) { _ in
            XCTFail("unexpected failure")
        }
        await session.shutdown()

        let states = try reopenedStates(packageURL)
        for id in ids { XCTAssertEqual(states[id]?.0, 3) }
    }

    func testAppFlushWaitsForPendingCullingWriteBeforeQuit() async throws {
        let (seed, packageURL, ids) = try makeSession(assetCount: 1)
        try seed.lease.release()

        let scheduler = ImageWorkScheduler()
        let gate = CullingPackageIOGate()
        let blockerID = ImageWorkScheduler.JobID("culling-flush-test-blocker")
        scheduler.enqueuePackageIO(
            id: blockerID, lane: .leaseHeartbeat, priority: .packageIO,
            operation: { await gate.wait() }
        )
        let startDeadline = Date().addingTimeInterval(5)
        while !(await gate.started()), Date() < startDeadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        guard await gate.started() else {
            await gate.release()
            XCTFail("package-I/O blocker did not start")
            return
        }

        let indexURL = tempDirectory.appendingPathComponent("CullingIndex/LibraryIndex.store")
        let session = try PortableLibrarySession(
            at: packageURL, indexURL: indexURL, scheduler: scheduler
        )
        let viewModel = makeAppViewModel(portableLibrarySession: session)
        session.enqueueLibraryStateUpdates(updates(ids, rating: 5, flag: .pick)) { error in
            XCTFail("unexpected culling write failure: \(error)")
        }

        let probe = CullingFlushProbe()
        let flush = Task { @MainActor in
            await probe.record(viewModel.flushPendingWrites())
        }
        try await Task.sleep(for: .milliseconds(50))
        let resultBeforeWriteCanRun = await probe.result
        XCTAssertNil(resultBeforeWriteCanRun)

        await gate.release()
        await flush.value
        await scheduler.cancelAndWait(id: blockerID)

        let resultAfterWrite = await probe.result
        XCTAssertEqual(resultAfterWrite, .success)
        let shard = try session.package.readMembershipShard(
            PortableLibraryPackage.shard(for: ids[0])
        )
        XCTAssertEqual(
            shard.entries.first(where: { $0.assetID == ids[0] })?.summary.rating,
            5
        )
        XCTAssertEqual(
            shard.entries.first(where: { $0.assetID == ids[0] })?.summary.flag,
            PhotoFlag.pick.rawValue
        )
        await viewModel.shutdown()
    }

    /// KRMA-1020: a flag queued behind an unwritten rating must carry the new rating, not the
    /// stale index summary, for photos outside the loaded window.
    func testQueuedFlagKeepsQueuedRatingForUnloadedSelection() async throws {
        let scheduler = ImageWorkScheduler()
        let gate = CullingPackageIOGate()
        let blockerID = ImageWorkScheduler.JobID("culling-merge-test-blocker")
        scheduler.enqueuePackageIO(
            id: blockerID, lane: .leaseHeartbeat, priority: .packageIO,
            operation: { await gate.wait() }
        )
        let startDeadline = Date().addingTimeInterval(5)
        while !(await gate.started()), Date() < startDeadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        guard await gate.started() else {
            await gate.release()
            XCTFail("package-I/O blocker did not start")
            return
        }

        let packageURL = tempDirectory.appendingPathComponent("Merge.kromoralibrary")
        let indexURL = tempDirectory.appendingPathComponent("MergeIndex/LibraryIndex.store")
        let session = try PortableLibrarySession(
            at: packageURL, indexURL: indexURL, pageSize: 2, scheduler: scheduler
        )
        let urls = try (0..<3).map { ordinal in
            try Fixtures.writeJPEG(
                width: 16 + ordinal, height: 12, orientation: 1,
                named: "merge-\(ordinal).jpg", in: tempDirectory
            )
        }
        let imported = try session.importURLs(urls).imported.map(\.assetID)
        XCTAssertEqual(imported.count, 3)
        let viewModel = makeAppViewModel(portableLibrarySession: session)
        XCTAssertEqual(viewModel.collection.items.count, 2)
        viewModel.selectAllInGrid()

        _ = viewModel.setFocusedRating(4)
        _ = viewModel.setFocusedFlag(.pick)

        await gate.release()
        let flushed = await session.flushPendingLibraryState()
        await scheduler.cancelAndWait(id: blockerID)
        XCTAssertEqual(flushed, .success)

        let states = try reopenedStates(packageURL)
        for id in imported {
            XCTAssertEqual(states[id]?.0, 4)
            XCTAssertEqual(states[id]?.1, PhotoFlag.pick.rawValue)
        }
        await viewModel.shutdown()
    }

    /// KRMA-1019: one undo restores loaded and unloaded selected photos.
    func testUndoRestoresUnloadedSelectionRatingAndFlag() async throws {
        let packageURL = tempDirectory.appendingPathComponent("Undo.kromoralibrary")
        let indexURL = tempDirectory.appendingPathComponent("UndoIndex/LibraryIndex.store")
        let session = try PortableLibrarySession(
            at: packageURL, indexURL: indexURL, pageSize: 2, scheduler: ImageWorkScheduler()
        )
        let urls = try (0..<3).map { ordinal in
            try Fixtures.writeJPEG(
                width: 16 + ordinal, height: 12, orientation: 1,
                named: "undo-\(ordinal).jpg", in: tempDirectory
            )
        }
        let imported = try session.importURLs(urls).imported.map(\.assetID)
        XCTAssertEqual(imported.count, 3)
        // Give one photo a distinct starting state so undo must restore per-photo values.
        session.enqueueLibraryStateUpdates(
            [.init(assetID: imported[2], rating: 2, flag: .reject)], onFailure: { _ in }
        )
        let seeded = await session.flushPendingLibraryState()
        XCTAssertEqual(seeded, .success)

        let viewModel = makeAppViewModel(portableLibrarySession: session)
        XCTAssertEqual(viewModel.collection.items.count, 2)
        viewModel.selectAllInGrid()

        XCTAssertTrue(viewModel.setFocusedRating(4))
        XCTAssertTrue(viewModel.setFocusedFlag(.pick))
        XCTAssertFalse(viewModel.setFocusedRating(4), "unchanged targets must not add an undo step")
        let afterChange = try await reopenedAfterFlush(session, packageURL)
        for id in imported { XCTAssertEqual(afterChange[id]?.0, 4) }
        for id in imported { XCTAssertEqual(afterChange[id]?.1, PhotoFlag.pick.rawValue) }

        XCTAssertTrue(viewModel.undoCullingChange())
        let afterFlagUndo = try await reopenedAfterFlush(session, packageURL)
        for id in imported { XCTAssertEqual(afterFlagUndo[id]?.0, 4) }
        XCTAssertEqual(afterFlagUndo[imported[0]]?.1, PhotoFlag.none.rawValue)
        XCTAssertEqual(afterFlagUndo[imported[1]]?.1, PhotoFlag.none.rawValue)
        XCTAssertEqual(afterFlagUndo[imported[2]]?.1, PhotoFlag.reject.rawValue)

        XCTAssertTrue(viewModel.undoCullingChange())
        let restored = try await reopenedAfterFlush(session, packageURL)
        XCTAssertEqual(restored[imported[2]]?.0, 2)
        XCTAssertEqual(restored[imported[2]]?.1, PhotoFlag.reject.rawValue)
        for id in imported.prefix(2) {
            XCTAssertEqual(restored[id]?.0, 0)
            XCTAssertNotEqual(restored[id]?.1, PhotoFlag.pick.rawValue)
        }
        XCTAssertFalse(viewModel.undoCullingChange(), "only two actions were recorded")
        await viewModel.shutdown()
    }

    func testUnloadedCullingUndoRetriesFailedPackageWritesAndReportsError() async throws {
        let packageURL = tempDirectory.appendingPathComponent("UndoFailure.kromoralibrary")
        let indexURL = tempDirectory.appendingPathComponent("UndoFailureIndex/LibraryIndex.store")
        let session = try PortableLibrarySession(
            at: packageURL, indexURL: indexURL, pageSize: 2, scheduler: ImageWorkScheduler()
        )
        let urls = try (0..<3).map { ordinal in
            try Fixtures.writeJPEG(
                width: 16 + ordinal, height: 12, orientation: 1,
                named: "undo-failure-\(ordinal).jpg", in: tempDirectory
            )
        }
        let imported = try session.importURLs(urls).imported.map(\.assetID)
        session.enqueueLibraryStateUpdates(
            [.init(assetID: imported[2], rating: 2, flag: .reject)], onFailure: { _ in }
        )
        let seeded = await session.flushPendingLibraryState()
        XCTAssertEqual(seeded, .success)

        let viewModel = makeAppViewModel(portableLibrarySession: session)
        viewModel.selectAllInGrid()
        XCTAssertTrue(viewModel.setFocusedFlag(.pick))
        let changed = await session.flushPendingLibraryState()
        XCTAssertEqual(changed, .success)

        let shards = Set(imported.map(PortableLibraryPackage.shard(for:)))
        let repairs = try shards.map { try corruptShard(session, $0) }
        XCTAssertTrue(viewModel.undoCullingChange())
        guard case .failure = await session.flushPendingLibraryState() else {
            return XCTFail("expected the unloaded undo write to stay dirty after failure")
        }
        XCTAssertNotNil(viewModel.errorMessage, "failed undo writes must use the existing error path")

        for repair in repairs { try repair() }
        let retried = await session.flushPendingLibraryState()
        XCTAssertEqual(retried, .success)
        let restored = try reopenedStates(packageURL)
        XCTAssertEqual(restored[imported[0]]?.1, PhotoFlag.none.rawValue)
        XCTAssertEqual(restored[imported[1]]?.1, PhotoFlag.none.rawValue)
        XCTAssertEqual(restored[imported[2]]?.1, PhotoFlag.reject.rawValue)
        await viewModel.shutdown()
    }

    func testUndoRestoresLoadedTargetsAfterTheyLeaveTheWindow() async throws {
        let packageURL = tempDirectory.appendingPathComponent("UndoAcrossPages.kromoralibrary")
        let indexURL = tempDirectory.appendingPathComponent("UndoAcrossPagesIndex/LibraryIndex.store")
        let session = try PortableLibrarySession(
            at: packageURL, indexURL: indexURL, pageSize: 2, scheduler: ImageWorkScheduler()
        )
        let urls = try (0..<3).map { ordinal in
            try Fixtures.writeJPEG(
                width: 16 + ordinal, height: 12, orientation: 1,
                named: "undo-across-pages-\(ordinal).jpg", in: tempDirectory
            )
        }
        let imported = try session.importURLs(urls).imported.map(\.assetID)
        session.enqueueLibraryStateUpdates(
            [.init(assetID: imported[2], rating: 2, flag: .reject)], onFailure: { _ in }
        )
        let seeded = await session.flushPendingLibraryState()
        XCTAssertEqual(seeded, .success)

        let viewModel = makeAppViewModel(portableLibrarySession: session)
        viewModel.selectAllInGrid()
        XCTAssertTrue(viewModel.setFocusedRating(4))
        let changed = await session.flushPendingLibraryState()
        XCTAssertEqual(changed, .success)

        try viewModel.reloadPortableWindow(pageIndex: 1)
        XCTAssertEqual(viewModel.collection.items.count, 1)
        XCTAssertTrue(viewModel.undoCullingChange())
        let flushed = await session.flushPendingLibraryState()
        XCTAssertEqual(flushed, .success)

        let restored = try reopenedStates(packageURL)
        XCTAssertEqual(restored[imported[0]]?.0, 0)
        XCTAssertEqual(restored[imported[1]]?.0, 0)
        XCTAssertEqual(restored[imported[2]]?.0, 2)
        XCTAssertEqual(restored[imported[0]]?.1, PhotoFlag.none.rawValue)
        XCTAssertEqual(restored[imported[1]]?.1, PhotoFlag.none.rawValue)
        XCTAssertEqual(restored[imported[2]]?.1, PhotoFlag.reject.rawValue)
        await viewModel.shutdown()
    }

    private func reopenedAfterFlush(_ session: PortableLibrarySession, _ packageURL: URL) async throws
        -> [PortablePhotoAssetID: (Int?, String?)]
    {
        _ = await session.flushPendingLibraryState()
        return try reopenedStates(packageURL)
    }

    func testInlineFallbackWithoutScheduler() async throws {
        let (session, packageURL, ids) = try makeSession(assetCount: 4)
        session.enqueueLibraryStateUpdates(updates(ids, rating: 2, flag: .pick)) { _ in
            XCTFail("unexpected failure")
        }
        await session.flushPendingLibraryState()
        try session.lease.release()
        let states = try reopenedStates(packageURL)
        for id in ids { XCTAssertEqual(states[id]?.0, 2) }
    }

    func testRejectedPackageIOStillPersistsPendingWrites() async throws {
        let scheduler = ImageWorkScheduler(
            configuration: .init(maxConcurrentPackageIO: 0)
        )
        let (session, packageURL, ids) = try makeSession(assetCount: 4, scheduler: scheduler)
        session.enqueueLibraryStateUpdates(updates(ids, rating: 2, flag: .pick)) { _ in
            XCTFail("unexpected failure")
        }
        await session.flushPendingLibraryState()
        await session.shutdown()

        let states = try reopenedStates(packageURL)
        for id in ids { XCTAssertEqual(states[id]?.0, 2) }
    }

    func testFailureIsReportedOncePerBatch() async throws {
        let scheduler = ImageWorkScheduler()
        let (session, _, _) = try makeSession(assetCount: 1, scheduler: scheduler)
        var failures = 0
        session.enqueueLibraryStateUpdates(
            updates([PortablePhotoAssetID(uuid: UUID()), PortablePhotoAssetID(uuid: UUID())],
                    rating: 3, flag: .none)
        ) { _ in failures += 1 }
        await session.flushPendingLibraryState()
        XCTAssertEqual(failures, 1)
        // The same flush reports a failed save only while a change is still dirty; unknown assets
        // are gone from the library, so there is nothing left to retry.
        let retried = await session.flushPendingLibraryState()
        XCTAssertEqual(retried, .success)
        await session.shutdown()
    }

    /// Corrupt a shard, then restore the bytes, so a write fails and can later succeed.
    private func corruptShard(_ session: PortableLibrarySession, _ shard: String) throws -> () throws -> Void {
        let url = try session.package.membershipURL(for: shard)
        let original = try Data(contentsOf: url)
        try Data("not json".utf8).write(to: url)
        return { try original.write(to: url) }
    }

    func testFailedWriteStaysDirtyAndRetriesOnFlush() async throws {
        let (session, _, ids) = try makeSession(assetCount: 1)
        let shard = PortableLibraryPackage.shard(for: ids[0])
        let repair = try corruptShard(session, shard)
        var failures = 0
        session.enqueueLibraryStateUpdates(updates(ids, rating: 4, flag: .pick)) { _ in failures += 1 }
        let first = await session.flushPendingLibraryState()
        // One report for the queued write and one for the flush's retry of the dirty change.
        XCTAssertEqual(failures, 2)
        guard case .failure = first else { return XCTFail("expected failure, got \(first)") }

        try repair()
        let second = await session.flushPendingLibraryState()
        XCTAssertEqual(second, .success)
        let entry = try session.package.readMembershipShard(shard).entries
            .first { $0.assetID == ids[0] }
        XCTAssertEqual(entry?.summary.rating, 4)
        XCTAssertEqual(entry?.summary.flag, PhotoFlag.pick.rawValue)
        let third = await session.flushPendingLibraryState()
        XCTAssertEqual(third, .success)
        await session.shutdown()
    }

    func testDiscardPendingWritesDoesNotRetryFailedCullingChangesOnShutdown() async throws {
        let (session, _, ids) = try makeSession(assetCount: 1)
        let viewModel = makeAppViewModel(portableLibrarySession: session)
        let shard = PortableLibraryPackage.shard(for: ids[0])
        let initial = try XCTUnwrap(
            try session.package.readMembershipShard(shard).entries
                .first { $0.assetID == ids[0] }
        ).summary
        let repair = try corruptShard(session, shard)
        session.enqueueLibraryStateUpdates(updates(ids, rating: 4, flag: .pick)) { _ in }

        let failed = await viewModel.flushPendingWrites()
        guard case .failure = failed else {
            return XCTFail("expected the failed culling write to block a clean quit")
        }

        try repair()
        await viewModel.discardPendingWrites()
        await viewModel.shutdown()

        let stored = try session.package.readMembershipShard(shard).entries
            .first { $0.assetID == ids[0] }
        XCTAssertEqual(stored?.summary.rating, initial.rating)
        XCTAssertEqual(stored?.summary.flag, initial.flag)
    }

    func testNewerIntentReplacesFailedValue() async throws {
        let (session, _, ids) = try makeSession(assetCount: 1)
        let shard = PortableLibraryPackage.shard(for: ids[0])
        let repair = try corruptShard(session, shard)
        session.enqueueLibraryStateUpdates(updates(ids, rating: 4, flag: .pick)) { _ in }
        _ = await session.flushPendingLibraryState()

        try repair()
        session.enqueueLibraryStateUpdates(updates(ids, rating: 2, flag: .reject)) { _ in
            XCTFail("unexpected failure")
        }
        let result = await session.flushPendingLibraryState()
        XCTAssertEqual(result, .success)
        let entry = try session.package.readMembershipShard(shard).entries
            .first { $0.assetID == ids[0] }
        XCTAssertEqual(entry?.summary.rating, 2)
        XCTAssertEqual(entry?.summary.flag, PhotoFlag.reject.rawValue)
        await session.shutdown()
    }

    func testPartialShardFailureKeepsOnlyFailedAssetsDirty() async throws {
        let (session, _, ids) = try makeSession(assetCount: 24)
        let byShard = Dictionary(grouping: ids) { PortableLibraryPackage.shard(for: $0) }
        guard byShard.count >= 2, let badShard = byShard.keys.sorted().first else {
            return XCTFail("fixture needs at least two shards")
        }
        let repair = try corruptShard(session, badShard)
        session.enqueueLibraryStateUpdates(updates(ids, rating: 3, flag: .pick)) { _ in }
        let first = await session.flushPendingLibraryState()
        guard case .failure = first else { return XCTFail("expected failure, got \(first)") }

        for (shard, shardIDs) in byShard where shard != badShard {
            let stored = try session.package.readMembershipShard(shard).entries
            for id in shardIDs {
                XCTAssertEqual(stored.first { $0.assetID == id }?.summary.rating, 3)
            }
        }

        try repair()
        let second = await session.flushPendingLibraryState()
        XCTAssertEqual(second, .success)
        for id in byShard[badShard] ?? [] {
            let entry = try session.package.readMembershipShard(badShard).entries
                .first { $0.assetID == id }
            XCTAssertEqual(entry?.summary.rating, 3)
        }
        await session.shutdown()
    }
}

private final class ShardLog: Sendable {
    private let storage = OSAllocatedUnfairLock<[String]>(initialState: [])
    var values: [String] { storage.withLock { $0 } }
    func append(_ v: String) { storage.withLock { $0.append(v) } }
}

private actor CullingPackageIOGate {
    private var hasStarted = false
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        hasStarted = true
        await withCheckedContinuation { continuation = $0 }
    }

    func started() -> Bool { hasStarted }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}

private actor CullingFlushProbe {
    private(set) var result: PersistenceFlushResult?

    func record(_ result: PersistenceFlushResult) { self.result = result }
}

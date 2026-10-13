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
        let directory = package.membershipURL(for: "00").deletingLastPathComponent()
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

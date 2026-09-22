import Foundation
import XCTest

@testable import KromoraKit

final class PortablePackageMaintenanceTests: TempDirectoryTestCase {

    private actor Gate {
        private var waiters: [CheckedContinuation<Void, Never>] = []
        private var waitingObservers: [CheckedContinuation<Void, Never>] = []
        private var hasEnteredWait = false
        private var isReleased = false

        func wait() async {
            hasEnteredWait = true
            let observers = waitingObservers
            waitingObservers.removeAll()
            for observer in observers { observer.resume() }

            guard !isReleased else { return }
            await withCheckedContinuation { waiter in
                if isReleased {
                    waiter.resume()
                } else {
                    waiters.append(waiter)
                }
            }
        }

        func waitUntilEntered() async {
            guard !hasEnteredWait else { return }
            await withCheckedContinuation { observer in
                if hasEnteredWait {
                    observer.resume()
                } else {
                    waitingObservers.append(observer)
                }
            }
        }

        func releaseAll() {
            isReleased = true
            let parked = waiters
            waiters.removeAll()
            for waiter in parked { waiter.resume() }
        }
    }

    func testPackedThumbnailCompactionReclaimsStaleBytesAndKeepsLiveOffsets() throws {
        let packageURL = tempDirectory.appendingPathComponent("PackedMaintenance.kromoralibrary")
        _ = try PortableLibraryPackage.create(at: packageURL)
        let store = try PortablePackagePackedThumbnailStore(
            at: packageURL.appendingPathComponent("Derived/Thumbnails")
        )
        try store.append(records: [
            .init(key: "10-live", data: Data(repeating: 0x11, count: 17)),
            .init(key: "20-deleted", data: Data(repeating: 0x22, count: 19)),
            .init(key: "30-live", data: Data(repeating: 0x33, count: 23)),
        ])
        try store.append(.init(key: "10-live", data: Data(repeating: 0x44, count: 31)))
        try store.remove(keys: ["20-deleted"])
        try injectStalePackedThumbnailEntry(
            at: packageURL.appendingPathComponent("Derived/Thumbnails/index.json"),
            key: "40-stale"
        )
        let compactionStore = try PortablePackagePackedThumbnailStore(
            at: packageURL.appendingPathComponent("Derived/Thumbnails")
        )

        let lease = try PortablePackageLease.acquire(at: packageURL)
        defer { try? lease.release() }
        let before = compactionStore.physicalByteCount
        let result = try compactionStore.compact(
            package: try PortableLibraryPackage.open(at: packageURL), lease: lease
        )

        XCTAssertEqual(result.indexedEntriesBefore, 3)
        XCTAssertEqual(result.indexedEntriesAfter, 2)
        XCTAssertEqual(result.staleEntriesRemoved, 1)
        XCTAssertLessThan(result.bytesAfter, before)
        XCTAssertEqual(
            try compactionStore.lookup("10-live"),
            .found(Data(repeating: 0x44, count: 31))
        )
        XCTAssertEqual(
            try compactionStore.lookup("30-live"),
            .found(Data(repeating: 0x33, count: 23))
        )
        XCTAssertEqual(try compactionStore.lookup("20-deleted"), .missing)
        XCTAssertEqual(try compactionStore.lookup("40-stale"), .missing)
        XCTAssertEqual(try compactionStore.coldScan(), .init(indexedEntries: 2, validEntries: 2, staleEntries: 0))
    }

    func testRevisionCompactionRetainsCurrentNewestAndProtectedRevisions() throws {
        let packageURL = tempDirectory.appendingPathComponent("RevisionMaintenance.kromoralibrary")
        let package = try PortableLibraryPackage.create(at: packageURL)
        let sourceURL = tempDirectory.appendingPathComponent("revision-source.jpg")
        try Data("revision source".utf8).write(to: sourceURL)
        let lease = try PortablePackageLease.acquire(at: packageURL)
        let imported = try package.importSources([.init(url: sourceURL)], lease: lease)
        let assetID = try XCTUnwrap(imported.imported.first?.assetID)
        for index in 0..<4 {
            _ = try package.appendEditRevision(
                for: assetID,
                document: EditDocument(light: .init(exposure: Double(index))),
                lease: lease
            )
        }
        try lease.release()

        let policy = PortablePackageMaintenancePolicy(
            maximumEditRevisions: 2,
            protectedRevisions: [assetID.raw: [1]]
        )
        let result = try PortablePackageMaintenance.run(
            at: packageURL, options: .init(policy: policy)
        )

        XCTAssertEqual(result.revisions.revisionsBefore, 4)
        XCTAssertEqual(result.revisions.revisionsAfter, 3)
        XCTAssertEqual(result.revisions.revisionsRemoved, 1)
        let compacted = try PortableLibraryPackage.open(at: packageURL)
        let record = try compacted.readAssetRecord(for: assetID)
        XCTAssertEqual(record.editHistory.currentRevision, 4)
        XCTAssertEqual(record.editHistory.edits.map(\.revision), [1, 3, 4])
        XCTAssertEqual(try compacted.readEditRevision(for: assetID, revision: 1).revision, 1)
        XCTAssertEqual(try compacted.readEditRevision(for: assetID, revision: 4).revision, 4)
        XCTAssertThrowsError(try compacted.readEditRevision(for: assetID, revision: 2))
    }

    func testInterruptedMaintenanceRollsBackAndCanBeRetried() throws {
        let packageURL = tempDirectory.appendingPathComponent("RetryMaintenance.kromoralibrary")
        _ = try PortableLibraryPackage.create(at: packageURL)
        let store = try PortablePackagePackedThumbnailStore(
            at: packageURL.appendingPathComponent("Derived/Thumbnails")
        )
        let liveData = Data(repeating: 0x5a, count: 41)
        try store.append(.init(key: "00-live", data: liveData))
        try store.append(.init(key: "00-live", data: Data(repeating: 0x6b, count: 53)))
        let oldBytes = store.physicalByteCount

        XCTAssertThrowsError(
            try PortablePackageMaintenance.run(
                at: packageURL,
                options: .init(
                    faultInjector: PortablePackageFaultInjector(failingAt: .publish)
                )
            )
        )
        let afterInterruption = try PortablePackagePackedThumbnailStore(
            at: packageURL.appendingPathComponent("Derived/Thumbnails")
        )
        XCTAssertEqual(try afterInterruption.lookup("00-live"), .found(Data(repeating: 0x6b, count: 53)))
        XCTAssertEqual(try PortablePackageTransaction.recover(at: packageURL).recoveredTransactionIDs.count, 0)
        XCTAssertEqual(afterInterruption.physicalByteCount, oldBytes)

        let result = try PortablePackageMaintenance.run(at: packageURL)
        XCTAssertEqual(result.thumbnails.indexedEntriesAfter, 1)
        XCTAssertLessThan(result.thumbnails.bytesAfter, oldBytes)
        let retried = try PortablePackagePackedThumbnailStore(
            at: packageURL.appendingPathComponent("Derived/Thumbnails")
        )
        XCTAssertEqual(try retried.lookup("00-live"), .found(Data(repeating: 0x6b, count: 53)))
    }

    func testMaintenanceSweepsOrphanedQuarantineDirectoryFromAnInterruptedPass() throws {
        let packageURL = tempDirectory.appendingPathComponent("OrphanMaintenance.kromoralibrary")
        _ = try PortableLibraryPackage.create(at: packageURL)
        let orphanURL = packageURL.appendingPathComponent(
            "Recovery/Quarantine/Maintenance/interrupted-pass", isDirectory: true
        )
        try FileManager.default.createDirectory(at: orphanURL, withIntermediateDirectories: true)
        try Data("orphaned sidecar".utf8).write(
            to: orphanURL.appendingPathComponent("stale.json")
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: orphanURL.path))
        _ = try PortablePackageMaintenance.run(at: packageURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: orphanURL.path))
    }

    @MainActor
    func testMaintenanceCoordinatorRetriesFailureOnTheMaintenanceLane() async throws {
        let packageURL = tempDirectory.appendingPathComponent("ScheduledMaintenance.kromoralibrary")
        _ = try PortableLibraryPackage.create(at: packageURL)
        let scheduler = ImageWorkScheduler(configuration: .init(
            maxConcurrentThumbnails: 1,
            maxQueuedThumbnails: 1,
            maxConcurrentPackageIO: 1,
            maxQueuedPackageIO: 2
        ))
        let maintenance = PortablePackageMaintenance(scheduler: scheduler)
        let outcomes = OutcomeProbe()
        let admitted = maintenance.enqueue(
            packageURL: packageURL,
            options: .init(faultInjector: PortablePackageFaultInjector(failingAt: .stage)),
            retryLimit: 1
        ) { result in
            switch result {
            case .success: outcomes.record("success")
            case .failure: outcomes.record("failure")
            }
        }

        XCTAssertTrue(admitted)
        try await waitUntil("maintenance retry", timeout: 10) {
            scheduler.isIdle && outcomes.events.count == 2
        }
        XCTAssertEqual(outcomes.events, ["failure", "success"])
        XCTAssertEqual(
            scheduler.admissionLog.filter { $0.lane == .packageIO && $0.priority == .background }.count,
            2
        )
    }

    @MainActor
    func testMaintenanceCoordinatorRetriesSchedulerRejectionAfterQueueDrains() async throws {
        let packageURL = tempDirectory.appendingPathComponent("RejectedMaintenance.kromoralibrary")
        _ = try PortableLibraryPackage.create(at: packageURL)
        let scheduler = ImageWorkScheduler(configuration: .init(
            maxConcurrentThumbnails: 1,
            maxQueuedThumbnails: 1,
            maxConcurrentPackageIO: 1,
            maxQueuedPackageIO: 0
        ))
        let gate = Gate()
        scheduler.enqueuePackageIO(
            id: .init("package-blocker"), lane: .importCopyHash,
            operation: { await gate.wait() }
        )
        await gate.waitUntilEntered()

        let maintenance = PortablePackageMaintenance(scheduler: scheduler)
        let outcomes = OutcomeProbe()
        XCTAssertFalse(
            maintenance.enqueue(packageURL: packageURL, retryLimit: 1) { result in
                switch result {
                case .success: outcomes.record("success")
                case .failure: outcomes.record("failure")
                }
            }
        )
        XCTAssertEqual(outcomes.events, ["failure"])
        XCTAssertEqual(maintenance.failureLog.count, 1)

        await gate.releaseAll()
        try await waitUntil("rejected maintenance retry", timeout: 10) {
            scheduler.isIdle && outcomes.events == ["failure", "success"]
        }
    }

    private final class OutcomeProbe: @unchecked Sendable {
        var events: [String] = []
        func record(_ event: String) { events.append(event) }
    }

    @MainActor
    private func waitUntil(
        _ description: String,
        timeout: TimeInterval,
        _ condition: @escaping @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline { return XCTFail("timed out waiting for \(description)") }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}

private func injectStalePackedThumbnailEntry(at indexURL: URL, key: String) throws {
    struct Entry: Codable {
        let key: String
        let shard: Int
        let offset: UInt64
        let length: UInt64
    }
    struct IndexFile: Codable {
        let schemaVersion: Int
        var entries: [Entry]
    }

    let data = try Data(contentsOf: indexURL)
    var index = try JSONDecoder().decode(IndexFile.self, from: data)
    index.entries.append(Entry(key: key, shard: 0x40, offset: UInt64.max, length: 1))
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(index).write(to: indexURL, options: .atomic)
}

import Foundation
import XCTest

@testable import KromoraKit

/// A named snapshot is a history entry, never the current edit. These run the real coordinator
/// against the real package store, gating both the persistence flush and the snapshot write.
@MainActor
final class SnapshotCurrentRevisionTests: TempDirectoryTestCase {
    private actor WriteGate {
        private var armed = false
        private var entered: CheckedContinuation<Void, Never>?
        private var release: CheckedContinuation<Void, Never>?
        private var hasEntered = false

        func arm() { armed = true }
        func wait() async {
            guard armed else { return }
            armed = false
            hasEntered = true
            entered?.resume()
            entered = nil
            await withCheckedContinuation { release = $0 }
        }
        func waitUntilEntered() async {
            if hasEntered { return }
            await withCheckedContinuation { entered = $0 }
        }
        func open() {
            release?.resume()
            release = nil
        }
    }

    @MainActor private final class Host {
        var reference: EditSourceReference?
        var document = EditDocument()
        var adoptCount = 0
        var flushContinuation: CheckedContinuation<Bool, Never>?
        var gateFlush = false
        func flush() async -> Bool {
            guard gateFlush else { return true }
            gateFlush = false
            return await withCheckedContinuation { flushContinuation = $0 }
        }
        func releaseFlush() {
            flushContinuation?.resume(returning: true)
            flushContinuation = nil
        }
    }

    private struct Fixture {
        let package: PortableLibraryPackage
        let lease: PortablePackageLease
        let store: EditDocumentStore
        let gate: WriteGate
        let references: [EditSourceReference]
    }

    private func makeFixture(photoCount: Int = 1) async throws -> Fixture {
        let packageURL = tempDirectory.appendingPathComponent("Snap.kromoralibrary")
        let package = try PortableLibraryPackage.create(at: packageURL)
        let lease = try PortablePackageLease.acquire(at: packageURL)
        addTeardownBlock { try? lease.release() }
        var references: [EditSourceReference] = []
        for index in 0..<photoCount {
            let url = tempDirectory.appendingPathComponent("snap-\(index).jpg")
            try Data("snapshot source \(index)".utf8).write(to: url)
            let imported = try package.importSources([.init(url: url)], lease: lease)
            let asset = try XCTUnwrap(imported.imported.first)
            references.append(EditSourceReference(
                assetID: .file(url),
                portableIdentity: PortablePhotoIdentity(
                    assetID: asset.assetID,
                    sourceFingerprint: .data(Data("snapshot source \(index)".utf8), decoderVersion: "test")
                )
            ))
        }
        let gate = WriteGate()
        let store = EditDocumentStore(
            package: package, lease: lease, beforeEditCommitGate: { await gate.wait() })
        return Fixture(package: package, lease: lease, store: store, gate: gate, references: references)
    }

    private func makeCoordinator(_ fixture: Fixture, host: Host) -> EditHistoryCoordinator {
        EditHistoryCoordinator(
            store: fixture.store,
            environment: .init(
                activeSourceReference: { host.reference },
                currentDocument: { host.document },
                endUndoGrouping: {},
                flushPersistence: { await host.flush() },
                adoptRestoredRevision: { _, _ in host.adoptCount += 1 },
                reportStatus: { _ in }
            )
        )
    }

    private func document(_ exposure: Double) -> EditDocument {
        var document = EditDocument()
        document.light.exposure = exposure
        return document
    }

    private func assertReopenedState(
        _ fixture: Fixture, reference: EditSourceReference, current: Double, snapshot: Double,
        file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let reopened = try PortableLibraryPackage.open(at: fixture.package.rootURL)
        let assetID = reference.portableAssetID
        let record = try reopened.readAssetRecord(for: assetID)
        let currentRevision = try reopened.readEditRevision(for: assetID)
        XCTAssertEqual(currentRevision.document.light.exposure, current, file: file, line: line)
        XCTAssertEqual(currentRevision.revision, record.editHistory.currentRevision, file: file, line: line)
        XCTAssertNil(currentRevision.snapshotName, file: file, line: line)
        let history = try reopened.readEditHistory(for: assetID)
        let snapshots = history.filter { $0.snapshotName != nil }
        XCTAssertEqual(snapshots.map(\.snapshotName), ["Captured"], file: file, line: line)
        XCTAssertEqual(snapshots.map(\.document.light.exposure), [snapshot], file: file, line: line)
    }

    func testEditDuringFlushAndDuringSnapshotWriteKeepsNewestEditCurrent() async throws {
        let fixture = try await makeFixture()
        let reference = fixture.references[0]
        let host = Host()
        host.reference = reference
        host.document = document(0.1)
        try await fixture.store.save(host.document, for: reference)
        let coordinator = makeCoordinator(fixture, host: host)

        host.gateFlush = true
        let saving = try XCTUnwrap(coordinator.saveSnapshot(named: "Captured"))
        while host.flushContinuation == nil { await Task.yield() }

        // An edit accepted while the snapshot waits for its flush.
        host.document = document(0.9)
        try await fixture.store.save(host.document, for: reference)

        // Hold the snapshot at the package-commit boundary. A newer edit commits first, then the
        // snapshot transaction must append history without moving the current pointer.
        await fixture.gate.arm()
        host.releaseFlush()
        await fixture.gate.waitUntilEntered()
        host.document = document(0.95)
        try await fixture.store.save(host.document, for: reference)
        await fixture.gate.open()
        await saving.value
        await coordinator.refresh()?.value
        let reopenedRecord = try PortableLibraryPackage.open(at: fixture.package.rootURL)
            .readAssetRecord(for: reference.portableAssetID)
        XCTAssertEqual(coordinator.currentRevision, reopenedRecord.editHistory.currentRevision)
        XCTAssertEqual(
            coordinator.history.map(\.document.light.exposure).sorted(), [0.1, 0.1, 0.9, 0.95])
        await coordinator.shutdown()

        let loaded = await fixture.store.load(for: reference)
        XCTAssertEqual(loaded.document.light.exposure, 0.95)
        XCTAssertEqual(loaded.status, .ready)
        XCTAssertEqual(host.adoptCount, 0, "saving a snapshot never navigates the editor")
        XCTAssertEqual(host.document.light.exposure, 0.95)
        try assertReopenedState(fixture, reference: reference, current: 0.95, snapshot: 0.1)
    }

    func testSnapshotLeavesCurrentRevisionPointerUntouched() async throws {
        let fixture = try await makeFixture()
        let reference = fixture.references[0]
        try await fixture.store.save(document(0.2), for: reference)
        let before = try await fixture.store.currentRevision(for: reference)

        try await fixture.store.saveSnapshot(document(0.7), named: "Alt", for: reference)

        let after = try await fixture.store.currentRevision(for: reference)
        XCTAssertEqual(after, before)
        let history = try await fixture.store.history(for: reference)
        XCTAssertEqual(history.map(\.snapshotName), [nil, "Alt"])
        XCTAssertGreaterThan(history[1].revision, before)
        let loaded = await fixture.store.load(for: reference)
        XCTAssertEqual(loaded.document.light.exposure, 0.2)

        // The next ordinary edit keeps the snapshot and becomes current.
        try await fixture.store.save(document(0.3), for: reference)
        let next = try await fixture.store.history(for: reference)
        XCTAssertEqual(next.map(\.document.light.exposure), [0.2, 0.7, 0.3])
        let nextCurrent = try await fixture.store.currentRevision(for: reference)
        XCTAssertEqual(nextCurrent, next[2].revision)
    }

    func testHistorySnapshotReturnsRevisionsAndSelectedPointerTogether() async throws {
        let fixture = try await makeFixture()
        let reference = fixture.references[0]
        try await fixture.store.save(document(0.1), for: reference)
        try await fixture.store.save(document(0.2), for: reference)
        try await fixture.store.saveSnapshot(document(0.6), named: "Side", for: reference)
        let history = try await fixture.store.history(for: reference)
        try await fixture.store.selectRevision(history[0].revision, for: reference)

        let snapshot = try await fixture.store.historySnapshot(for: reference)

        XCTAssertEqual(snapshot.revisions, history)
        XCTAssertEqual(snapshot.currentRevision, history[0].revision)
    }

    func testSnapshotAfterHistoryNavigationKeepsSelectedRevisionCurrent() async throws {
        let fixture = try await makeFixture()
        let reference = fixture.references[0]
        try await fixture.store.save(document(0.1), for: reference)
        try await fixture.store.save(document(0.2), for: reference)
        let history = try await fixture.store.history(for: reference)
        try await fixture.store.selectRevision(history[0].revision, for: reference)

        try await fixture.store.saveSnapshot(document(0.6), named: "Side", for: reference)

        let all = try await fixture.store.history(for: reference)
        XCTAssertEqual(all.map(\.document.light.exposure), [0.1, 0.2, 0.6], "forward edit is not discarded")
        let current = try await fixture.store.currentRevision(for: reference)
        XCTAssertEqual(current, history[0].revision)
    }

    func testNavigatingAwayAndBackAroundSnapshotRequestKeepsInvariants() async throws {
        let fixture = try await makeFixture(photoCount: 2)
        let (a, b) = (fixture.references[0], fixture.references[1])
        let host = Host()
        host.reference = a
        host.document = document(0.1)
        try await fixture.store.save(host.document, for: a)
        let coordinator = makeCoordinator(fixture, host: host)

        host.gateFlush = true
        let saving = try XCTUnwrap(coordinator.saveSnapshot(named: "Captured"))
        while host.flushContinuation == nil { await Task.yield() }

        // A -> B -> A, with an edit to each while the snapshot waits.
        host.reference = b
        host.document = document(0.4)
        try await fixture.store.save(host.document, for: b)
        host.reference = a
        host.document = document(0.9)
        try await fixture.store.save(host.document, for: a)

        host.releaseFlush()
        await saving.value
        await coordinator.refresh()?.value
        await coordinator.shutdown()

        try assertReopenedState(fixture, reference: a, current: 0.9, snapshot: 0.1)
        let reopened = try PortableLibraryPackage.open(at: fixture.package.rootURL)
        XCTAssertEqual(try reopened.readEditRevision(for: b.portableAssetID).document.light.exposure, 0.4)
        XCTAssertTrue(try reopened.readEditHistory(for: b.portableAssetID).allSatisfy { $0.snapshotName == nil })
        XCTAssertEqual(coordinator.currentRevision, try reopened.readAssetRecord(for: a.portableAssetID).editHistory.currentRevision)
        XCTAssertEqual(coordinator.history.count, 3)
    }

    func testShutdownWhileSnapshotWaitsForCommitCompletesItBeforeTheBarrier() async throws {
        let fixture = try await makeFixture()
        let reference = fixture.references[0]
        let host = Host()
        host.reference = reference
        host.document = document(0.1)
        try await fixture.store.save(host.document, for: reference)
        let coordinator = makeCoordinator(fixture, host: host)

        host.gateFlush = true
        XCTAssertNotNil(coordinator.saveSnapshot(named: "Captured"))
        while host.flushContinuation == nil { await Task.yield() }
        host.document = document(0.9)
        try await fixture.store.save(host.document, for: reference)

        await fixture.gate.arm()
        host.releaseFlush()
        await fixture.gate.waitUntilEntered()

        coordinator.beginShutdown()
        XCTAssertNil(coordinator.saveSnapshot(named: "Late"))
        let shutdown = Task { await coordinator.shutdown() }
        await fixture.gate.open()
        await shutdown.value

        let writesAtBarrier = await fixture.store.writeCount
        for _ in 0..<10 { await Task.yield() }
        let writesAfter = await fixture.store.writeCount
        XCTAssertEqual(writesAfter, writesAtBarrier, "no write lands after the shutdown barrier")
        try assertReopenedState(fixture, reference: reference, current: 0.9, snapshot: 0.1)
    }
}

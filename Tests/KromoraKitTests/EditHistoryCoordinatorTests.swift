import Observation
import os
import XCTest

@testable import KromoraKit

/// The durable-history coordinator runs against a fake store and closures; no `AppViewModel`.
@MainActor
final class EditHistoryCoordinatorTests: XCTestCase {
    private final class Counter: Sendable {
        private let storage = OSAllocatedUnfairLock(initialState: 0)
        var value: Int { storage.withLock { $0 } }
        func increment() { storage.withLock { $0 += 1 } }
    }

    private actor FakeStore: EditHistoryStore {
        var revisions: [PortablePackageEditRevision] = []
        var current: UInt64 = 0
        var failReads = false
        var failSelect = false
        private(set) var calls: [String] = []
        private(set) var snapshots: [String] = []
        private(set) var savedDocuments: [EditDocument] = []
        private(set) var savedSources: [EditSourceReference] = []
        private var gate: CheckedContinuation<Void, Never>?
        private var gateEntered: CheckedContinuation<Void, Never>?
        private var gating = false

        func armGate() { gating = true }
        /// Suspends until the gated call (history read or snapshot write) has begun.
        func waitUntilGateEntered() async {
            if gate != nil { return }
            await withCheckedContinuation { gateEntered = $0 }
        }
        func releaseGate() {
            gate?.resume()
            gate = nil
        }
        private func passGate() async {
            guard gating else { return }
            gating = false
            await withCheckedContinuation { continuation in
                gate = continuation
                gateEntered?.resume()
                gateEntered = nil
            }
        }

        func set(revisions: [PortablePackageEditRevision], current: UInt64) {
            self.revisions = revisions
            self.current = current
        }
        func setFailReads(_ value: Bool) { failReads = value }
        func setFailSelect(_ value: Bool) { failSelect = value }

        func history(for source: EditSourceReference) async throws -> [PortablePackageEditRevision] {
            calls.append("history")
            await passGate()
            if failReads { throw CocoaError(.fileReadUnknown) }
            return revisions
        }
        func currentRevision(for source: EditSourceReference) async throws -> UInt64 {
            if failReads { throw CocoaError(.fileReadUnknown) }
            return current
        }
        func selectRevision(_ revision: UInt64, for source: EditSourceReference) async throws {
            calls.append("select")
            if failSelect { throw CocoaError(.fileWriteUnknown) }
            current = revision
        }
        func saveSnapshot(_ document: EditDocument, named name: String, for source: EditSourceReference) async throws {
            calls.append("snapshot")
            await passGate()
            snapshots.append(name)
        }
        func save(_ document: EditDocument, for source: EditSourceReference) async throws {
            calls.append("save")
            savedDocuments.append(document)
            savedSources.append(source)
        }
    }

    @MainActor
    private final class Host {
        var reference: EditSourceReference?
        var document = EditDocument()
        var flushResult = true
        var events: [String] = []
        var adopted: [(EditDocument, [EditDocument])] = []
        var statuses: [String] = []
        private var flushContinuation: CheckedContinuation<Void, Never>?
        private var flushEntered: CheckedContinuation<Void, Never>?
        var gateFlush = false

        func waitForFlush() async {
            if flushContinuation != nil { return }
            await withCheckedContinuation { flushEntered = $0 }
        }

        func releaseFlush() {
            flushContinuation?.resume()
            flushContinuation = nil
        }

        func flush() async -> Bool {
            events.append("flush")
            if gateFlush {
                gateFlush = false
                await withCheckedContinuation { continuation in
                    flushContinuation = continuation
                    flushEntered?.resume()
                    flushEntered = nil
                }
            }
            return flushResult
        }
    }

    private let referenceA = EditSourceReference(assetID: PhotoAssetID(rawValue: "a"))
    private let referenceB = EditSourceReference(assetID: PhotoAssetID(rawValue: "b"))

    private func revision(_ number: UInt64, exposure: Double, snapshot: String? = nil) -> PortablePackageEditRevision {
        var document = EditDocument()
        document.light.exposure = exposure
        return PortablePackageEditRevision(
            assetID: referenceA.portableAssetID, revision: number, document: document, snapshotName: snapshot
        )
    }

    private func makeCoordinator(
        store: FakeStore, host: Host
    ) -> EditHistoryCoordinator {
        EditHistoryCoordinator(
            store: store,
            environment: .init(
                activeSourceReference: { host.reference },
                currentDocument: { host.document },
                endUndoGrouping: { host.events.append("endGrouping") },
                flushPersistence: { await host.flush() },
                adoptRestoredRevision: { document, prior in host.adopted.append((document, prior)) },
                reportStatus: { host.statuses.append($0) }
            )
        )
    }

    func testRefreshPublishesHistoryAndNotifies() async throws {
        let store = FakeStore()
        await store.set(revisions: [revision(1, exposure: 0.1), revision(2, exposure: 0.2)], current: 2)
        let host = Host()
        host.reference = referenceA
        let coordinator = makeCoordinator(store: store, host: host)
        let changeCount = Counter()
        withObservationTracking { _ = coordinator.history } onChange: { changeCount.increment() }

        await coordinator.refresh()?.value

        XCTAssertEqual(coordinator.history.map(\.revision), [1, 2])
        XCTAssertEqual(coordinator.currentRevision, 2)
        XCTAssertGreaterThan(changeCount.value, 0)
    }

    func testRefreshIsIgnoredWhenActiveReferenceChangesDuringRead() async throws {
        let store = FakeStore()
        await store.set(revisions: [revision(1, exposure: 0.1)], current: 1)
        let host = Host()
        host.reference = referenceA
        let coordinator = makeCoordinator(store: store, host: host)

        let task = coordinator.refresh()
        host.reference = referenceB
        await task?.value

        XCTAssertTrue(coordinator.history.isEmpty)
        XCTAssertEqual(coordinator.currentRevision, 0)
    }

    func testStaleRefreshFailureDoesNotClearHistoryAfterReferenceChanges() async throws {
        let store = FakeStore()
        await store.set(revisions: [revision(1, exposure: 0.1)], current: 1)
        let host = Host()
        host.reference = referenceA
        let coordinator = makeCoordinator(store: store, host: host)
        await coordinator.refresh()?.value
        await store.setFailReads(true)

        let task = coordinator.refresh()
        host.reference = referenceB
        await task?.value

        XCTAssertEqual(coordinator.history.map(\.revision), [1])
        XCTAssertEqual(coordinator.currentRevision, 1)
    }

    func testRefreshWithoutActivePhotoAndOnReadFailureClearsState() async throws {
        let store = FakeStore()
        await store.set(revisions: [revision(1, exposure: 0.1)], current: 1)
        let host = Host()
        host.reference = referenceA
        let coordinator = makeCoordinator(store: store, host: host)
        await coordinator.refresh()?.value
        XCTAssertEqual(coordinator.currentRevision, 1)

        await store.setFailReads(true)
        await coordinator.refresh()?.value
        XCTAssertTrue(coordinator.history.isEmpty)
        XCTAssertEqual(coordinator.currentRevision, 0)

        await store.setFailReads(false)
        await coordinator.refresh()?.value
        host.reference = nil
        XCTAssertNil(coordinator.refresh())
        XCTAssertTrue(coordinator.history.isEmpty)
    }

    func testRestoreFlushesBeforeSelectingThenAdoptsWithPriorNonSnapshotDocuments() async throws {
        let store = FakeStore()
        await store.set(revisions: [
            revision(1, exposure: 0.1), revision(2, exposure: 0.2, snapshot: "keep"), revision(3, exposure: 0.3),
        ], current: 3)
        let host = Host()
        host.reference = referenceA
        let coordinator = makeCoordinator(store: store, host: host)
        await coordinator.refresh()?.value

        await coordinator.restore(3)?.value

        XCTAssertEqual(Array(host.events.prefix(2)), ["endGrouping", "flush"])
        XCTAssertEqual(host.adopted.count, 1)
        XCTAssertEqual(host.adopted[0].0.light.exposure, 0.3)
        XCTAssertEqual(host.adopted[0].1.map(\.light.exposure), [0.1])
        let calls = await store.calls
        XCTAssertEqual(calls.filter { $0 == "select" }.count, 1)
    }

    func testRestoreAbortsWithoutSelectingWhenFlushFails() async throws {
        let store = FakeStore()
        await store.set(revisions: [revision(1, exposure: 0.1), revision(2, exposure: 0.2)], current: 2)
        let host = Host()
        host.reference = referenceA
        let coordinator = makeCoordinator(store: store, host: host)
        await coordinator.refresh()?.value
        host.flushResult = false

        await coordinator.restore(1)?.value

        let calls = await store.calls
        XCTAssertFalse(calls.contains("select"))
        XCTAssertTrue(host.adopted.isEmpty)
        XCTAssertEqual(coordinator.currentRevision, 2)
    }

    func testRestoreSelectFailureReportsStatusAndKeepsRevision() async throws {
        let store = FakeStore()
        await store.set(revisions: [revision(1, exposure: 0.1), revision(2, exposure: 0.2)], current: 2)
        let host = Host()
        host.reference = referenceA
        let coordinator = makeCoordinator(store: store, host: host)
        await coordinator.refresh()?.value
        await store.setFailSelect(true)

        await coordinator.restore(1)?.value

        XCTAssertTrue(host.adopted.isEmpty)
        XCTAssertEqual(coordinator.currentRevision, 2)
        XCTAssertTrue(host.statuses.first?.hasPrefix("Could not navigate edit history") == true)
    }

    func testRestoreIsIgnoredWhenReferenceChangesDuringSelect() async throws {
        let store = FakeStore()
        await store.set(revisions: [revision(1, exposure: 0.1), revision(2, exposure: 0.2)], current: 2)
        let host = Host()
        host.reference = referenceA
        let coordinator = makeCoordinator(store: store, host: host)
        await coordinator.refresh()?.value

        let task = coordinator.restore(1)
        host.reference = referenceB
        await task?.value

        XCTAssertTrue(host.adopted.isEmpty)
        XCTAssertEqual(coordinator.currentRevision, 2)
    }

    func testRestoreOfUnknownRevisionDoesNothing() async throws {
        let store = FakeStore()
        let host = Host()
        host.reference = referenceA
        let coordinator = makeCoordinator(store: store, host: host)

        XCTAssertNil(coordinator.restore(9))
        XCTAssertTrue(host.events.isEmpty)
    }

    func testSnapshotFlushesSavesReportsAndRefreshes() async throws {
        let store = FakeStore()
        let host = Host()
        host.reference = referenceA
        let coordinator = makeCoordinator(store: store, host: host)

        await coordinator.saveSnapshot(named: "Final")?.value

        XCTAssertEqual(Array(host.events.prefix(2)), ["endGrouping", "flush"])
        let snapshots = await store.snapshots
        XCTAssertEqual(snapshots, ["Final"])
        XCTAssertEqual(host.statuses, ["Saved snapshot ‘Final’"])
    }

    func testSnapshotWithoutActivePhotoOrFailedFlushWritesNothing() async throws {
        let store = FakeStore()
        let host = Host()
        let coordinator = makeCoordinator(store: store, host: host)
        XCTAssertNil(coordinator.saveSnapshot(named: "x"))

        host.reference = referenceA
        host.flushResult = false
        await coordinator.saveSnapshot(named: "x")?.value
        let snapshots = await store.snapshots
        XCTAssertTrue(snapshots.isEmpty)
        XCTAssertTrue(host.statuses.isEmpty)
    }

    func testVirtualCopySavesDocumentThenHandsOffAndReportsFailures() async throws {
        let store = FakeStore()
        let host = Host()
        host.reference = referenceA
        host.document = EditDocument(light: .init(exposure: 0.42))
        let coordinator = makeCoordinator(store: store, host: host)
        let copy = EditHistoryCoordinator.VirtualCopy(
            sourceReference: referenceB, displayName: "Copy", assetID: PortablePhotoAssetID()
        )
        var created: [String] = []

        await coordinator.createVirtualCopy(
            of: referenceA, makeCopy: { copy }, didCreate: { created.append($0.displayName) }
        )?.value
        XCTAssertEqual(created, ["Copy"])
        let savedDocuments = await store.savedDocuments
        let savedSources = await store.savedSources
        XCTAssertEqual(savedDocuments, [host.document], "the active edits are saved onto the copy")
        XCTAssertEqual(savedSources, [referenceB], "the edits target the independent copy identity")
        let calls = await store.calls
        XCTAssertEqual(calls.filter { $0 == "save" }.count, 1)

        await coordinator.createVirtualCopy(
            of: referenceA, makeCopy: { throw CocoaError(.fileWriteUnknown) }, didCreate: { _ in
                XCTFail("must not hand off a failed copy")
            }
        )?.value
        XCTAssertTrue(host.statuses.last?.hasPrefix("Could not create virtual copy") == true)
    }

    @MainActor
    private final class CopyGate {
        private var entered: CheckedContinuation<Void, Never>?
        private var release: CheckedContinuation<Void, Never>?
        private var didEnter = false

        func pass() async {
            didEnter = true
            entered?.resume()
            entered = nil
            await withCheckedContinuation { release = $0 }
        }

        func waitUntilEntered() async {
            if didEnter { return }
            await withCheckedContinuation { entered = $0 }
        }

        func open() {
            release?.resume()
            release = nil
        }
    }

    func testVirtualCopyKeepsMainActorResponsiveRejectsSecondRequestAndClearsFlag() async throws {
        let store = FakeStore()
        let host = Host()
        host.reference = referenceA
        let coordinator = makeCoordinator(store: store, host: host)
        let gate = CopyGate()
        let copy = EditHistoryCoordinator.VirtualCopy(
            sourceReference: referenceB, displayName: "Copy", assetID: PortablePhotoAssetID()
        )
        var created = 0
        let task = coordinator.createVirtualCopy(
            of: referenceA, makeCopy: { await gate.pass(); return copy }, didCreate: { _ in created += 1 }
        )
        XCTAssertNotNil(task)
        XCTAssertTrue(coordinator.isCreatingVirtualCopy)
        await gate.waitUntilEntered()

        let hop = Task { @MainActor in true }
        let responsive = await withTaskGroup(of: Bool.self) { group in
            group.addTask { await hop.value }
            group.addTask { try? await Task.sleep(for: .seconds(2)); return false }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }
        XCTAssertTrue(responsive, "main actor stays responsive while the copy is in flight")
        XCTAssertNil(coordinator.createVirtualCopy(
            of: referenceA, makeCopy: { copy }, didCreate: { _ in XCTFail("second copy must not start") }
        ))

        gate.open()
        await task?.value
        XCTAssertEqual(created, 1)
        XCTAssertFalse(coordinator.isCreatingVirtualCopy)

        await coordinator.createVirtualCopy(
            of: referenceA, makeCopy: { throw CocoaError(.fileWriteUnknown) }, didCreate: { _ in }
        )?.value
        XCTAssertFalse(coordinator.isCreatingVirtualCopy, "failure clears the in-progress flag")
    }

    func testShutdownDuringVirtualCopySuppressesDidCreate() async throws {
        let store = FakeStore()
        let host = Host()
        host.reference = referenceA
        let coordinator = makeCoordinator(store: store, host: host)
        let gate = CopyGate()
        let copy = EditHistoryCoordinator.VirtualCopy(
            sourceReference: referenceB, displayName: "Copy", assetID: PortablePhotoAssetID()
        )
        var created = 0
        XCTAssertNotNil(coordinator.createVirtualCopy(
            of: referenceA, makeCopy: { await gate.pass(); return copy }, didCreate: { _ in created += 1 }
        ))
        await gate.waitUntilEntered()

        let shutdown = Task { await coordinator.shutdown() }
        await Task.yield()
        gate.open()
        await shutdown.value

        XCTAssertEqual(created, 0, "shutdown lets the copy finish but suppresses didCreate")
        XCTAssertFalse(coordinator.isCreatingVirtualCopy)
    }

    func testShutdownSuppressesGatedRefreshPublication() async throws {
        let store = FakeStore()
        await store.set(revisions: [revision(1, exposure: 0.1)], current: 1)
        let host = Host()
        host.reference = referenceA
        let coordinator = makeCoordinator(store: store, host: host)
        let changeCount = Counter()
        withObservationTracking {
            _ = coordinator.history
            _ = coordinator.currentRevision
        } onChange: { changeCount.increment() }
        await store.armGate()
        _ = coordinator.refresh()
        await store.waitUntilGateEntered()

        let shutdown = Task { await coordinator.shutdown() }
        await Task.yield()
        XCTAssertNil(coordinator.refresh(), "new work is rejected once shutdown starts")
        await store.releaseGate()
        await shutdown.value

        XCTAssertTrue(coordinator.history.isEmpty)
        XCTAssertEqual(coordinator.currentRevision, 0)
        XCTAssertEqual(changeCount.value, 0)
    }

    func testShutdownDrainsAcceptedSnapshotWithoutPublishing() async throws {
        let store = FakeStore()
        let host = Host()
        host.reference = referenceA
        let coordinator = makeCoordinator(store: store, host: host)
        await store.armGate()
        XCTAssertNotNil(coordinator.saveSnapshot(named: "Keep"))
        await store.waitUntilGateEntered()

        var finished = false
        let shutdown = Task {
            await coordinator.shutdown()
            finished = true
        }
        await Task.yield()
        XCTAssertFalse(finished, "shutdown waits for the accepted write")
        await store.releaseGate()
        await shutdown.value

        let snapshots = await store.snapshots
        XCTAssertEqual(snapshots, ["Keep"], "accepted snapshot is not lost")
        XCTAssertTrue(host.statuses.isEmpty)
        let calls = await store.calls
        XCTAssertEqual(calls.filter { $0 == "history" }.count, 0, "no nested refresh after shutdown")
        await coordinator.shutdown()
        XCTAssertNil(coordinator.saveSnapshot(named: "Late"))
        XCTAssertNil(coordinator.createVirtualCopy(of: referenceA, makeCopy: { throw CocoaError(.fileReadUnknown) }, didCreate: { _ in }))
    }

    func testShutdownDoesNotCancelAcceptedSnapshotWhileItWaitsForFlush() async throws {
        let store = FakeStore()
        let host = Host()
        host.reference = referenceA
        host.gateFlush = true
        let coordinator = makeCoordinator(store: store, host: host)
        XCTAssertNotNil(coordinator.saveSnapshot(named: "Keep"))
        await host.waitForFlush()

        let shutdown = Task { await coordinator.shutdown() }
        await Task.yield()
        host.releaseFlush()
        await shutdown.value

        let snapshots = await store.snapshots
        XCTAssertEqual(snapshots, ["Keep"])
        let calls = await store.calls
        XCTAssertTrue(calls.contains("snapshot"))
        XCTAssertFalse(calls.contains("history"), "shutdown rejects the snapshot's nested refresh")
    }
}

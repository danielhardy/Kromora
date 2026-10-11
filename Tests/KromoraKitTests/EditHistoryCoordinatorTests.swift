import XCTest

@testable import KromoraKit

/// The durable-history coordinator runs against a fake store and closures; no `AppViewModel`.
@MainActor
final class EditHistoryCoordinatorTests: XCTestCase {
    private actor FakeStore: EditHistoryStore {
        var revisions: [PortablePackageEditRevision] = []
        var current: UInt64 = 0
        var failReads = false
        var failSelect = false
        private(set) var calls: [String] = []
        private(set) var snapshots: [String] = []

        func set(revisions: [PortablePackageEditRevision], current: UInt64) {
            self.revisions = revisions
            self.current = current
        }
        func setFailReads(_ value: Bool) { failReads = value }
        func setFailSelect(_ value: Bool) { failSelect = value }

        func history(for source: EditSourceReference) async throws -> [PortablePackageEditRevision] {
            calls.append("history")
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
            snapshots.append(name)
        }
        func save(_ document: EditDocument, for source: EditSourceReference) async throws {
            calls.append("save")
        }
    }

    private final class Host {
        var reference: EditSourceReference?
        var flushResult = true
        var events: [String] = []
        var adopted: [(EditDocument, [EditDocument])] = []
        var statuses: [String] = []
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
        store: FakeStore, host: Host, changes: @escaping @MainActor () -> Void = {}
    ) -> EditHistoryCoordinator {
        EditHistoryCoordinator(
            store: store,
            environment: .init(
                activeSourceReference: { host.reference },
                currentDocument: { EditDocument() },
                endUndoGrouping: { host.events.append("endGrouping") },
                flushPersistence: {
                    host.events.append("flush")
                    return host.flushResult
                },
                adoptRestoredRevision: { document, prior in host.adopted.append((document, prior)) },
                reportStatus: { host.statuses.append($0) }
            ),
            willChange: changes
        )
    }

    func testRefreshPublishesHistoryAndNotifies() async throws {
        let store = FakeStore()
        await store.set(revisions: [revision(1, exposure: 0.1), revision(2, exposure: 0.2)], current: 2)
        let host = Host()
        host.reference = referenceA
        var changeCount = 0
        let coordinator = makeCoordinator(store: store, host: host) { changeCount += 1 }

        await coordinator.refresh()?.value

        XCTAssertEqual(coordinator.history.map(\.revision), [1, 2])
        XCTAssertEqual(coordinator.currentRevision, 2)
        XCTAssertGreaterThan(changeCount, 0)
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
        let coordinator = makeCoordinator(store: store, host: host)
        let copy = EditHistoryCoordinator.VirtualCopy(
            sourceReference: referenceB, displayName: "Copy", assetID: PortablePhotoAssetID()
        )
        var created: [String] = []

        await coordinator.createVirtualCopy(
            of: referenceA, makeCopy: { copy }, didCreate: { created.append($0.displayName) }
        ).value
        XCTAssertEqual(created, ["Copy"])
        let calls = await store.calls
        XCTAssertEqual(calls.filter { $0 == "save" }.count, 1)

        await coordinator.createVirtualCopy(
            of: referenceA, makeCopy: { throw CocoaError(.fileWriteUnknown) }, didCreate: { _ in
                XCTFail("must not hand off a failed copy")
            }
        ).value
        XCTAssertTrue(host.statuses.last?.hasPrefix("Could not create virtual copy") == true)
    }
}

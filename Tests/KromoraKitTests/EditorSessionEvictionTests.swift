import Foundation
import XCTest

@testable import KromoraKit

/// KRMA-1060: the bounded clean-session working set, driven through the real
/// `EditorDocumentCoordinator` and `EditPersistenceCoordinator` with the same wiring
/// `AppViewModel` installs (dirty state from persistence, eviction after each acknowledgement).
@MainActor
final class EditorSessionEvictionTests: TempDirectoryTestCase {
    private struct Rig {
        let editor: EditorDocumentCoordinator
        let persistence: EditPersistenceCoordinator
        let fixture: EditPackageFixture
        let store: EditDocumentStore
    }

    private func reference(_ index: Int) throws -> (EditSourceReference, PhotoAssetID) {
        let url = tempDirectory.appendingPathComponent("evict-\(index).png")
        let reference = EditSourceReference(assetID: .file(url), url: url)
        return (reference, reference.assetID)
    }

    /// `maximumResidentSessions` is injected small; `pinned` stands in for outstanding requests.
    private func makeRig(
        sessions: Int = 3,
        bytes: Int = 1 << 30,
        artificialWriteDelay: Duration = .zero,
        failuresBeforeSuccess: Int = 0,
        writeStartSignal: AsyncStream<Void>.Continuation? = nil,
        pinned: @escaping () -> Set<PhotoAssetID> = { [] }
    ) -> Rig {
        let fixture = makeEditPackageFixture()
        let store = fixture.store(
            artificialWriteDelay: artificialWriteDelay,
            failuresBeforeSuccess: failuresBeforeSuccess,
            writeStartSignal: writeStartSignal)
        let editor = EditorDocumentCoordinator(
            maximumResidentSessions: sessions, maximumResidentSessionBytes: bytes)
        let persistence = EditPersistenceCoordinator(store: store, waitForCheckpoint: {})
        editor.pinnedAssetIDs = pinned
        editor.isDirty = { persistence.isDirty($0) }
        persistence.onDurableWrite = { [weak editor] _ in editor?.evictIfNeeded() }
        return Rig(editor: editor, persistence: persistence, fixture: fixture, store: store)
    }

    private func document(_ exposure: Double, samples: Int = 0) -> EditDocument {
        var document = EditDocument()
        document.light.exposure = exposure
        if samples > 0 {
            let stroke = BrushStroke(samples: (0..<samples).map {
                BrushSample(point: CGPoint(x: Double($0) / Double(samples), y: 0.5), pressure: 1)
            })
            document.localAdjustments = [LocalAdjustmentLayer(
                components: [MaskComponent(source: .brush(BrushMaskDefinition(strokes: [stroke])))])]
        }
        return document
    }

    /// Edit an inactive photo the way batch paste does: apply, enqueue, then evict.
    private func paste(
        _ document: EditDocument, to index: Int, in rig: Rig, force: Bool = true
    ) throws {
        let (reference, assetID) = try reference(index)
        try rig.fixture.register(reference)
        XCTAssertTrue(rig.editor.apply(document, to: assetID))
        rig.persistence.enqueue(document, for: reference, reportsStatus: false, force: force)
        rig.editor.evictIfNeeded()
    }

    // MARK: Plateau

    func testResidentSetPlateausWhileEveryPhotoStaysDurable() async throws {
        let rig = makeRig(sessions: 3)
        for index in 0..<20 {
            try paste(document(Double(index) / 100 + 0.01), to: index, in: rig)
            _ = await rig.persistence.flush()
            XCTAssertLessThanOrEqual(rig.editor.retainedSessionCount, 3)
        }
        XCTAssertEqual(rig.editor.retainedSessionCount, 3)
        // Newest three stay; the rest reopen from the package.
        for index in 17..<20 { XCTAssertNotNil(rig.editor.session(for: try reference(index).1)) }
        let (oldReference, oldID) = try reference(0)
        XCTAssertNil(rig.editor.session(for: oldID))
        let reopened = await rig.store.load(for: oldReference)
        XCTAssertEqual(reopened.document, document(0.01))
    }

    func testByteBudgetTripsBeforeCountBudget() async throws {
        // A pasted session holds the new document plus one undo entry (the neutral base).
        let probe = EditorDocumentCoordinator()
        probe.apply(document(0.5, samples: 4_000), to: try reference(900).1)
        let perSession = probe.estimatedResidentBytes
        let budget = perSession * 2 + perSession / 2
        let rig = makeRig(sessions: 100, bytes: budget)
        for index in 0..<6 {
            try paste(document(Double(index) / 10 + 0.5, samples: 4_000), to: index, in: rig)
            _ = await rig.persistence.flush()
        }
        XCTAssertLessThanOrEqual(rig.editor.estimatedResidentBytes, budget)
        XCTAssertEqual(rig.editor.retainedSessionCount, 2)
    }

    // MARK: Active undo and grouping

    func testActiveSessionKeepsUndoAndOpenGroupAcrossEvictionPasses() async throws {
        let rig = makeRig(sessions: 1)
        let (activeReference, activeID) = try reference(100)
        try rig.fixture.register(activeReference)
        var current = document(0.1)
        rig.editor.activate(session: nil, for: activeID)
        rig.editor.commit(document: current, for: activeID)
        let next = document(0.2)
        rig.editor.recordChange(from: current, to: next)
        rig.editor.commit(document: next, for: activeID)
        current = next
        rig.editor.beginGrouping(document: current)
        let withGroup = rig.editor.estimatedResidentBytes
        XCTAssertGreaterThan(withGroup, 0)

        for index in 0..<4 {
            try paste(document(Double(index) + 0.5), to: index, in: rig)
            _ = await rig.persistence.flush()
        }

        XCTAssertNotNil(rig.editor.session(for: activeID))
        XCTAssertTrue(rig.editor.isGrouping)
        XCTAssertEqual(rig.editor.undoDepth, 1)
        XCTAssertEqual(rig.editor.undo(current: current), document(0.1))
        // The grouped point is charged while open and released when the group ends.
        rig.editor.endGrouping(document: current)
        XCTAssertLessThan(rig.editor.estimatedResidentBytes, withGroup + 1)
    }

    // MARK: Dirty pinning and acknowledgement ordering

    func testDirtyPhotoIsPinnedUntilItsAcknowledgement() async throws {
        let rig = makeRig(sessions: 1, artificialWriteDelay: .milliseconds(150))
        try paste(document(0.3), to: 0, in: rig)
        try paste(document(0.4), to: 1, in: rig)

        XCTAssertEqual(rig.editor.retainedSessionCount, 2, "both are dirty, so nothing is evictable")
        XCTAssertGreaterThan(rig.editor.evictionDeferrals, 0)
        _ = await rig.persistence.flush()
        XCTAssertEqual(rig.editor.retainedSessionCount, 1)
        XCTAssertNotNil(rig.editor.session(for: try reference(1).1), "most recent stays")
    }

    func testOldAcknowledgementDoesNotMakeNewerQueuedEditEvictable() async throws {
        let (started, signal) = AsyncStream<Void>.makeStream()
        let rig = makeRig(
            sessions: 1, artificialWriteDelay: .milliseconds(200), writeStartSignal: signal)
        var iterator = started.makeAsyncIterator()
        let (reference, assetID) = try reference(0)
        try rig.fixture.register(reference)

        // Edit N goes in flight, then N+1 is queued while N's save is still running.
        _ = rig.editor.apply(document(0.1), to: assetID)
        rig.persistence.enqueue(document(0.1), for: reference, reportsStatus: false, force: true)
        _ = await iterator.next()
        _ = rig.editor.apply(document(0.2), to: assetID)
        rig.persistence.enqueue(document(0.2), for: reference, reportsStatus: false)
        // Make the single session the only candidate over budget.
        try paste(document(0.9), to: 1, in: rig, force: false)

        // N's acknowledgement lands via onDurableWrite; N+1 is still queued.
        for _ in 0..<100 {
            if await rig.store.writeCount >= 1 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertNotNil(rig.editor.session(for: assetID))
        XCTAssertEqual(rig.editor.session(for: assetID)?.document, document(0.2))
        XCTAssertTrue(rig.persistence.isDirty(assetID), "N+1 is still queued after N's ack")

        _ = await rig.persistence.flush()
        XCTAssertFalse(rig.persistence.isDirty(assetID))
        XCTAssertLessThanOrEqual(rig.editor.retainedSessionCount, 1)
        let stored = await rig.store.load(for: reference)
        XCTAssertEqual(stored.document, document(0.2))
    }

    func testFailedSaveKeepsSessionResidentOverBudgetUntilRetrySucceeds() async throws {
        let rig = makeRig(sessions: 1, failuresBeforeSuccess: 1)
        try paste(document(0.3), to: 0, in: rig)
        let first = await rig.persistence.flush()
        guard case .failure = first else { return XCTFail("first save must fail") }
        try paste(document(0.4), to: 1, in: rig, force: false)

        let (failedReference, failedID) = try reference(0)
        XCTAssertNotNil(rig.editor.session(for: failedID), "unsaved value is never dropped")
        XCTAssertTrue(rig.persistence.isDirty(failedID))

        let retry = await rig.persistence.flush()
        XCTAssertEqual(retry, .success)
        XCTAssertEqual(rig.editor.retainedSessionCount, 1)
        let stored = await rig.store.load(for: failedReference)
        XCTAssertEqual(stored.document, document(0.3))
    }

    // MARK: Source-request pinning, revisions, deletion

    func testRequestPinnedAssetSurvivesAndRevisionsStayMonotonicAfterEviction() async throws {
        let (_, pinnedID) = try reference(0)
        var pinned: Set<PhotoAssetID> = [pinnedID]
        let rig = makeRig(sessions: 1, pinned: { pinned })
        try paste(document(0.1), to: 0, in: rig)
        _ = await rig.persistence.flush()
        let pinnedRevision = rig.editor.revision(for: pinnedID)
        try paste(document(0.2), to: 1, in: rig)
        _ = await rig.persistence.flush()
        // The pinned photo is older but ineligible, so the newer clean photo is evicted instead.
        XCTAssertNotNil(rig.editor.session(for: pinnedID))
        XCTAssertEqual(rig.editor.revision(for: pinnedID), pinnedRevision)
        XCTAssertNil(rig.editor.session(for: try reference(1).1))

        pinned = []
        try paste(document(0.3), to: 2, in: rig)
        _ = await rig.persistence.flush()
        XCTAssertNil(rig.editor.session(for: pinnedID))
        XCTAssertEqual(rig.editor.revision(for: pinnedID), 0, "absent means disk is authoritative")

        // An edit after eviction gets a revision above every earlier one.
        let latest = rig.editor.revision(for: try reference(2).1)
        try paste(document(0.7), to: 0, in: rig)
        XCTAssertGreaterThan(rig.editor.revision(for: pinnedID), latest)
        XCTAssertGreaterThan(rig.editor.revision(for: pinnedID), pinnedRevision)
    }

    func testDeletionRemovesResidentSessionsAndShutdownFlushKeepsDirtyOnes() async throws {
        let rig = makeRig(sessions: 1, artificialWriteDelay: .milliseconds(100))
        try paste(document(0.1), to: 0, in: rig)
        try paste(document(0.2), to: 1, in: rig)
        XCTAssertEqual(rig.editor.retainedSessionCount, 2)

        let flush = await rig.persistence.flush()
        XCTAssertEqual(flush, .success)
        let (reference0, id0) = try reference(0)
        let (_, id1) = try reference(1)
        let stored = await rig.store.load(for: reference0)
        XCTAssertEqual(stored.document, document(0.1), "the dirty photo reached disk before any eviction")
        rig.editor.removeSessions(for: [id0, id1])
        XCTAssertEqual(rig.editor.retainedSessionCount, 0)
    }
}

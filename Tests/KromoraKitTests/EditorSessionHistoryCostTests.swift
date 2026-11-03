import Foundation
import XCTest

@testable import KromoraKit

/// KRMA-1159: a resident session is charged for every document its history retains, not only
/// for the current one, so eviction honors the byte budget after a heavy edit is undone away.
@MainActor
final class EditorSessionHistoryCostTests: XCTestCase {
    private let asset = PhotoAssetID.photos(localIdentifier: "history-cost-0")
    private let other = PhotoAssetID.photos(localIdentifier: "history-cost-1")

    private func document(exposure: Double = 0, brushSamples: Int = 0) -> EditDocument {
        var document = EditDocument()
        document.light.exposure = exposure
        if brushSamples > 0 {
            let stroke = BrushStroke(samples: (0..<brushSamples).map {
                BrushSample(point: CGPoint(x: Double($0) / Double(brushSamples), y: 0.5), pressure: 1)
            })
            document.localAdjustments = [LocalAdjustmentLayer(
                components: [MaskComponent(source: .brush(BrushMaskDefinition(strokes: [stroke])))])]
        }
        return document
    }

    private func edit(
        _ editor: EditorDocumentCoordinator, from old: EditDocument, to new: EditDocument,
        asset: PhotoAssetID
    ) {
        editor.recordChange(from: old, to: new)
        editor.commit(document: new, for: asset)
    }

    func testRemovingHeavyMaskKeepsTheHeavyUndoEntryCharged() {
        let heavy = document(brushSamples: 4_000)
        let light = document(exposure: 0.1)
        let editor = EditorDocumentCoordinator()
        editor.activate(session: nil, for: asset)
        editor.commit(document: heavy, for: asset)
        edit(editor, from: heavy, to: light, asset: asset)

        XCTAssertEqual(
            editor.estimatedResidentBytes,
            light.estimatedRetentionBytes + heavy.estimatedRetentionBytes)
    }

    func testCostFollowsEntriesAcrossUndoAndRedo() {
        let heavy = document(brushSamples: 4_000)
        let light = document(exposure: 0.1)
        let editor = EditorDocumentCoordinator()
        editor.activate(session: nil, for: asset)
        editor.commit(document: heavy, for: asset)
        edit(editor, from: heavy, to: light, asset: asset)
        let sum = heavy.estimatedRetentionBytes + light.estimatedRetentionBytes

        // large -> small -> Undo -> Redo: one current document plus one retained document each time.
        let undone = editor.undo(current: light)
        XCTAssertEqual(undone, heavy)
        editor.commit(document: heavy, for: asset)
        XCTAssertEqual(editor.undoDepth, 0)
        XCTAssertTrue(editor.canRedo)
        XCTAssertEqual(editor.estimatedResidentBytes, sum)

        let redone = editor.redo(current: heavy)
        XCTAssertEqual(redone, light)
        editor.commit(document: light, for: asset)
        XCTAssertEqual(editor.estimatedResidentBytes, sum)
    }

    func testMixedPayloadHistoryChargesTheSumOfRetainedEstimates() {
        let documents = [
            document(exposure: 0.1, brushSamples: 2_000),
            document(exposure: 0.2),
            document(exposure: 0.3, brushSamples: 500),
            document(exposure: 0.4),
            document(exposure: 0.5, brushSamples: 1_000),
        ]
        let editor = EditorDocumentCoordinator()
        editor.activate(session: nil, for: asset)
        editor.commit(document: documents[0], for: asset)
        for (old, new) in zip(documents, documents.dropFirst()) {
            edit(editor, from: old, to: new, asset: asset)
        }
        // Undo twice so both stacks are populated.
        var current = documents[4]
        for _ in 0..<2 { current = editor.undo(current: current)! }
        editor.commit(document: current, for: asset)

        XCTAssertEqual(
            editor.estimatedResidentBytes,
            documents.reduce(0) { $0 + $1.estimatedRetentionBytes })
    }

    func testOpenGroupIsChargedAndCancelReleasesIt() {
        let base = document(exposure: 0.1, brushSamples: 3_000)
        let changed = document(exposure: 0.2)
        let editor = EditorDocumentCoordinator()
        editor.activate(session: nil, for: asset)
        editor.commit(document: base, for: asset)
        let ungrouped = editor.estimatedResidentBytes
        XCTAssertEqual(ungrouped, base.estimatedRetentionBytes)

        editor.beginGrouping(document: base)
        XCTAssertEqual(editor.estimatedResidentBytes, ungrouped + base.estimatedRetentionBytes)
        editor.recordChange(from: base, to: changed)
        editor.commit(document: changed, for: asset)
        XCTAssertEqual(
            editor.estimatedResidentBytes,
            base.estimatedRetentionBytes + changed.estimatedRetentionBytes)

        // Restoring the start document before ending the group is a cancel, so it adds no undo step.
        editor.recordChange(from: changed, to: base)
        editor.commit(document: base, for: asset)
        editor.endGrouping(document: base)
        XCTAssertEqual(editor.undoDepth, 0)
        XCTAssertEqual(editor.estimatedResidentBytes, ungrouped)
    }

    func testEvictsInactiveCleanSessionWhoseOnlyHeavyDocumentIsInHistory() {
        let heavy = document(brushSamples: 6_000)
        let light = document(exposure: 0.1)
        let budget = heavy.estimatedRetentionBytes
        let editor = EditorDocumentCoordinator(
            maximumResidentSessions: 8, maximumResidentSessionBytes: budget)
        editor.isDirty = { _ in false }
        editor.activate(session: nil, for: asset)
        editor.commit(document: heavy, for: asset)
        edit(editor, from: heavy, to: light, asset: asset)
        // The current document alone fits the budget; the retained history does not.
        XCTAssertLessThan(light.estimatedRetentionBytes, budget)
        editor.activate(session: nil, for: other)

        editor.evictIfNeeded()

        XCTAssertNil(editor.session(for: asset))
        XCTAssertLessThanOrEqual(editor.estimatedResidentBytes, budget)
    }

    func testActiveDirtyAndPinnedSessionsStayExemptWhenOverBudget() {
        let heavy = document(brushSamples: 6_000)
        let light = document(exposure: 0.1)
        let editor = EditorDocumentCoordinator(
            maximumResidentSessions: 8, maximumResidentSessionBytes: 1)
        let dirty = PhotoAssetID.photos(localIdentifier: "history-cost-dirty")
        let pinned = PhotoAssetID.photos(localIdentifier: "history-cost-pinned")
        editor.isDirty = { $0 == dirty }
        editor.pinnedAssetIDs = { [pinned] }
        for id in [asset, dirty, pinned] {
            editor.activate(session: nil, for: id)
            editor.commit(document: heavy, for: id)
            edit(editor, from: heavy, to: light, asset: id)
        }
        editor.activate(session: editor.session(for: asset), for: asset)

        editor.evictIfNeeded()

        for id in [asset, dirty, pinned] { XCTAssertNotNil(editor.session(for: id)) }
        XCTAssertEqual(editor.evictionDeferrals, 1)
    }

    func testRetainedBytesMatchesCachedEntryCosts() {
        var history = EditHistory()
        let heavy = document(brushSamples: 1_000)
        for step in 0..<10 { history.recordChange(from: heavy, to: document(exposure: Double(step + 1) / 20)) }
        XCTAssertEqual(history.retainedBytes, history.undoSnapshots.reduce(0) { $0 + $1.cost })
        XCTAssertGreaterThanOrEqual(history.retainedBytes, heavy.estimatedRetentionBytes)
    }
}

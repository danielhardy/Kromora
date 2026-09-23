import XCTest
@testable import KromoraKit

/// `RenderEngine.RevisionLedger` (KRMA-530) is a plain `Sendable` value type precisely so its
/// bounded-eviction arithmetic can be exercised here without an actor or a GPU.
final class RevisionLedgerTests: XCTestCase {
    func testRenderRevisionsAreBoundedAndEvictLeastRecentlyTouchedSourceFirst() {
        var ledger = RenderEngine.RevisionLedger(
            maximumTrackedRenderSources: 4, maximumTrackedMaskSources: 16,
            maximumTrackedMaskRequests: 64
        )
        for index in 1...4 {
            ledger.noteRenderRequest(sourceKey: "source-\(index)", revision: UInt64(index))
        }
        XCTAssertEqual(ledger.trackedRenderSourceCount, 4)

        // Touch source-1 so it is no longer the least recently seen.
        ledger.noteRenderRequest(sourceKey: "source-1", revision: 10)
        ledger.noteRenderRequest(sourceKey: "source-5", revision: 5)

        XCTAssertEqual(ledger.trackedRenderSourceCount, 4)
        XCTAssertEqual(ledger.latestRenderRevision(sourceKey: "source-2"), 0,
                        "the least recently touched source must be the one evicted")
        XCTAssertEqual(ledger.latestRenderRevision(sourceKey: "source-1"), 10)
        XCTAssertEqual(ledger.latestRenderRevision(sourceKey: "source-5"), 5)
    }

    func testIsCurrentRenderRequestRejectsALaggingRevisionAfterANewerOneIsNoted() {
        var ledger = RenderEngine.RevisionLedger()
        ledger.noteRenderRequest(sourceKey: "s", revision: 5)
        XCTAssertTrue(ledger.isCurrentRenderRequest(sourceKey: "s", revision: 5))
        XCTAssertTrue(ledger.isCurrentRenderRequest(sourceKey: "s", revision: 6))
        XCTAssertFalse(ledger.isCurrentRenderRequest(sourceKey: "s", revision: 4),
                        "a request behind the latest admitted revision must not be current")
    }

    func testActiveRenderFenceSurvivesSourceEvictionAndLaterSupersession() {
        var ledger = RenderEngine.RevisionLedger(maximumTrackedRenderSources: 2)
        ledger.beginRenderRequest(sourceKey: "a", revision: 1)
        ledger.noteRenderRequest(sourceKey: "b", revision: 1)
        ledger.noteRenderRequest(sourceKey: "c", revision: 1)
        XCTAssertEqual(ledger.trackedRenderSourceCount, 2)
        XCTAssertTrue(ledger.isCurrentRenderRequest(sourceKey: "a", revision: 1))

        ledger.beginRenderRequest(sourceKey: "a", revision: 2)
        XCTAssertFalse(ledger.isCurrentRenderRequest(sourceKey: "a", revision: 1))
        ledger.endRenderRequest(sourceKey: "a", revision: 2)
        XCTAssertFalse(ledger.isCurrentRenderRequest(sourceKey: "a", revision: 1),
                       "the newer active request's fence remains until the older work exits")
        ledger.endRenderRequest(sourceKey: "a", revision: 1)
        XCTAssertFalse(ledger.isCurrentRenderRequest(sourceKey: "a", revision: 1),
                       "the bounded latest revision remains after its in-flight fence is released")
    }

    func testActiveMaskFenceSurvivesRecipeAndSourceEviction() {
        var ledger = RenderEngine.RevisionLedger(
            maximumTrackedRenderSources: 2, maximumTrackedMaskSources: 1,
            maximumTrackedMaskRequests: 1
        )
        _ = ledger.beginMaskRequest(
            sourceKey: "a", revision: 1, maskIdentity: "recipe-a", documentIdentity: "doc-a"
        )
        // Keep A in flight, then age it out of every capped table.
        _ = ledger.noteMaskRequest(
            sourceKey: "b", revision: 2, maskIdentity: "recipe-b", documentIdentity: "doc-b"
        )
        _ = ledger.beginMaskRequest(
            sourceKey: "a", revision: 2, maskIdentity: "recipe-a", documentIdentity: "doc-a"
        )
        XCTAssertFalse(ledger.isCurrentMaskRequest(
            sourceKey: "a", revision: 1, maskIdentity: "recipe-a", documentIdentity: "doc-a"
        ), "an evicted active recipe cannot restore an old document's fence")
        ledger.endMaskRequest(sourceKey: "a", revision: 1)
        ledger.endMaskRequest(sourceKey: "a", revision: 2)
    }

    func testMaskRequestRevisionsEvictOldestDocumentKeyFirstRegardlessOfRevisionValue() {
        var ledger = RenderEngine.RevisionLedger(
            maximumTrackedRenderSources: 64, maximumTrackedMaskSources: 16,
            maximumTrackedMaskRequests: 3
        )
        // Three different documents under the same recipe/source, noted in ascending revision
        // order but the *smallest* current revision should not be assumed to be the oldest — the
        // old implementation's `.min(by:)` scan happened to agree here, but insertion order is
        // the real contract now.
        _ = ledger.noteMaskRequest(
            sourceKey: "src", revision: 100, maskIdentity: "recipe", documentIdentity: "doc-1"
        )
        _ = ledger.noteMaskRequest(
            sourceKey: "src", revision: 1, maskIdentity: "recipe", documentIdentity: "doc-2"
        )
        _ = ledger.noteMaskRequest(
            sourceKey: "src", revision: 50, maskIdentity: "recipe", documentIdentity: "doc-3"
        )
        XCTAssertEqual(ledger.trackedMaskRequestCount, 3)

        _ = ledger.noteMaskRequest(
            sourceKey: "src", revision: 200, maskIdentity: "recipe", documentIdentity: "doc-4"
        )
        XCTAssertEqual(ledger.trackedMaskRequestCount, 3)
        XCTAssertFalse(
            ledger.isCurrentMaskRequest(
                sourceKey: "src", revision: 100, maskIdentity: "recipe", documentIdentity: "doc-1"
            ),
            "the oldest-inserted document key must be evicted first"
        )
        XCTAssertTrue(ledger.isCurrentMaskRequest(
            sourceKey: "src", revision: 200, maskIdentity: "recipe", documentIdentity: "doc-4"
        ))
    }

    func testRecipeChangeReportsTrueOnceAndClearsThePreviousRecipesDocumentKeys() {
        var ledger = RenderEngine.RevisionLedger()
        let firstChanged = ledger.noteMaskRequest(
            sourceKey: "src", revision: 1, maskIdentity: "recipe-a", documentIdentity: "doc-1"
        )
        XCTAssertTrue(firstChanged, "a source's first recipe is always a change")

        let sameRecipe = ledger.noteMaskRequest(
            sourceKey: "src", revision: 2, maskIdentity: "recipe-a", documentIdentity: "doc-2"
        )
        XCTAssertFalse(sameRecipe)
        XCTAssertTrue(ledger.isCurrentMaskRequest(
            sourceKey: "src", revision: 1, maskIdentity: "recipe-a", documentIdentity: "doc-1"
        ), "an older document under the same recipe survives a global-only edit")

        let recipeChanged = ledger.noteMaskRequest(
            sourceKey: "src", revision: 3, maskIdentity: "recipe-b", documentIdentity: "doc-3"
        )
        XCTAssertTrue(recipeChanged)
        XCTAssertFalse(
            ledger.isCurrentMaskRequest(
                sourceKey: "src", revision: 1, maskIdentity: "recipe-a", documentIdentity: "doc-1"
            ),
            "a recipe change must invalidate every older document entry for that source"
        )
    }

    func testOverlayMaskRecencyQueueStaysBoundedWhenRecipeAndOverlayRecencyDiverge() {
        var ledger = RenderEngine.RevisionLedger(
            maximumTrackedRenderSources: 64, maximumTrackedMaskSources: 2,
            maximumTrackedMaskRequests: 64
        )
        _ = ledger.noteMaskRequest(
            sourceKey: "a", revision: 1, maskIdentity: "recipe-a", documentIdentity: "doc-a"
        )
        _ = ledger.noteMaskRequest(
            sourceKey: "b", revision: 2, maskIdentity: "recipe-b", documentIdentity: "doc-b"
        )
        // Same-recipe re-notes refresh overlay recency without touching recipe recency, so
        // the two queues disagree about which source is oldest from here on.
        _ = ledger.noteMaskRequest(
            sourceKey: "a", revision: 3, maskIdentity: "recipe-a", documentIdentity: "doc-a2"
        )
        _ = ledger.noteMaskRequest(
            sourceKey: "c", revision: 4, maskIdentity: "recipe-c", documentIdentity: "doc-c"
        )
        _ = ledger.noteMaskRequest(
            sourceKey: "b", revision: 5, maskIdentity: "recipe-b", documentIdentity: "doc-b2"
        )
        XCTAssertEqual(ledger.trackedMaskSourceCount, 2)
        XCTAssertLessThanOrEqual(
            ledger.trackedOverlayMaskOrderCount, 2,
            "recipe-table eviction must also drop the evicted source's overlay recency " +
                "entry, or the queue outgrows its cap and touch() stops being O(capacity)"
        )
    }

    func testRemoveAllClearsRenderAndMaskState() {
        var ledger = RenderEngine.RevisionLedger()
        ledger.beginRenderRequest(sourceKey: "s", revision: 1)
        _ = ledger.noteMaskRequest(
            sourceKey: "s", revision: 1, maskIdentity: "r", documentIdentity: "d"
        )
        ledger.removeAll()
        XCTAssertEqual(ledger.trackedRenderSourceCount, 0)
        XCTAssertEqual(ledger.trackedMaskRequestCount, 0)
        XCTAssertEqual(ledger.trackedMaskSourceKeys, [])
        XCTAssertFalse(ledger.isCurrentRenderRequest(sourceKey: "s", revision: 1),
                       "full invalidation must reject active work even after clearing the ledger")
        ledger.endRenderRequest(sourceKey: "s", revision: 1)
        XCTAssertTrue(ledger.isCurrentRenderRequest(sourceKey: "s", revision: 1),
                      "an exited request releases its temporary in-flight fence")
    }

    func testClearMaskRequestStateLeavesRenderRevisionsIntact() {
        var ledger = RenderEngine.RevisionLedger()
        ledger.noteRenderRequest(sourceKey: "s", revision: 7)
        _ = ledger.noteMaskRequest(
            sourceKey: "s", revision: 1, maskIdentity: "r", documentIdentity: "d"
        )
        ledger.clearMaskRequestState()
        XCTAssertEqual(ledger.latestRenderRevision(sourceKey: "s"), 7,
                       "memory-pressure/invalidateRenderCaches must not reset render supersession")
        XCTAssertEqual(ledger.trackedMaskSourceKeys, [])
    }
}

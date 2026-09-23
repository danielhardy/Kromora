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

    func testRemoveAllClearsRenderAndMaskState() {
        var ledger = RenderEngine.RevisionLedger()
        ledger.noteRenderRequest(sourceKey: "s", revision: 1)
        _ = ledger.noteMaskRequest(
            sourceKey: "s", revision: 1, maskIdentity: "r", documentIdentity: "d"
        )
        ledger.removeAll()
        XCTAssertEqual(ledger.trackedRenderSourceCount, 0)
        XCTAssertEqual(ledger.trackedMaskRequestCount, 0)
        XCTAssertEqual(ledger.trackedMaskSourceKeys, [])
        XCTAssertTrue(ledger.isCurrentRenderRequest(sourceKey: "s", revision: 1),
                      "a cleared ledger has no fence to reject a fresh request")
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

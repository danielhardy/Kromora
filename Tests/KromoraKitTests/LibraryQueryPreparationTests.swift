import Foundation
import XCTest

@testable import KromoraKit

/// KRMA-1163: query ordering is prepared off the main actor, installed against the index
/// generation it was built from, and never built while holding a lock a foreground reader takes.
@MainActor
final class LibraryQueryPreparationTests: TempDirectoryTestCase {
    private actor Gate {
        private var isOpen = false
        private var waiters: [CheckedContinuation<Void, Never>] = []
        var waiterCount: Int { waiters.count }

        func wait() async {
            if isOpen { return }
            await withCheckedContinuation { waiters.append($0) }
        }

        func open() {
            isOpen = true
            for waiter in waiters { waiter.resume() }
            waiters.removeAll()
        }
    }

    private func controller(count: Int, pageSize: Int = 50) throws -> LibraryQueryController {
        let entries = (0..<count).map { index in
            let assetID = PortablePhotoAssetID()
            return LibraryIndexEntry(from: .init(
                assetID: assetID,
                recordPath: "Assets/" + PortableLibraryPackage.shard(for: assetID)
                    + "/" + assetID.raw + "/asset.json",
                summary: .init(rating: index % 6, displayName: "Frame \(index * 7919 % count)")
            ))
        }
        return LibraryQueryController(
            index: try LibraryIndexProjection(libraryID: UUID(), entries: entries),
            pageSize: pageSize)
    }

    private let byName = LibraryQuery(sort: .init(key: .displayName, direction: .descending))
    private let byRating = LibraryQuery(sort: .init(key: .rating, direction: .ascending))

    /// How long the same sort takes when run inline, to scale the main-actor assertions.
    private func inlineSortSeconds(_ controller: LibraryQueryController, _ query: LibraryQuery) -> Double {
        let start = ContinuousClock.now
        _ = controller.orderedAssetIDs(query: query)
        return start.duration(to: .now).seconds
    }

    func testPreparedOrderingMakesTheSynchronousReadsCacheHits() async throws {
        let controller = try controller(count: 400)
        let installed = await controller.prepareOrdering(query: byName)
        XCTAssertTrue(installed)
        XCTAssertEqual(controller.orderedEntriesBuildCount, 1)

        let page = controller.page(at: 1, query: byName)
        _ = controller.pageIndex(of: try XCTUnwrap(page.items.first).assetID, query: byName)
        XCTAssertEqual(controller.orderedEntriesBuildCount, 1)
        let fresh = LibraryQueryController(index: controller.index, pageSize: controller.pageSize)
        XCTAssertEqual(page, fresh.page(at: 1, query: byName))
    }

    func testCancelledPreparationDoesNotEvictTheCachedOrdering() async throws {
        let controller = try controller(count: 400)
        _ = controller.page(at: 0, query: byName)
        XCTAssertEqual(controller.orderedEntriesBuildCount, 1)

        let task = Task { await controller.prepareOrdering(query: byRating) }
        task.cancel()
        let installed = await task.value

        XCTAssertFalse(installed)
        XCTAssertEqual(controller.orderedEntriesBuildCount, 1)
        _ = controller.page(at: 0, query: byName)
        XCTAssertEqual(controller.orderedEntriesBuildCount, 1, "the foreground ordering survived")
    }

    func testIdlePlannerOverlappingASortChangeLeavesThePreparedOrderingInPlace() async throws {
        let controller = try controller(count: 400)
        let planner = controller
        // The planner ranks the default order while the foreground prepares a sort change.
        async let planned = Task.detached { planner.orderedAssetIDs() }.value
        let installed = await controller.prepareOrdering(query: byName)
        let plannedIDs = await planned

        XCTAssertTrue(installed)
        XCTAssertEqual(plannedIDs.count, 400)
        XCTAssertEqual(controller.orderedEntriesBuildCount, 1)
        _ = controller.page(at: 0, query: byName)
        XCTAssertEqual(controller.orderedEntriesBuildCount, 1, "no rebuild after the planner ran")
    }

    func testRestrictingSelectionUsesThePreparedOrderingAndKeepsOnlyMatches() async throws {
        var controller = try controller(count: 120)
        let evenRating = LibraryQuery(filter: .init(flag: .all, rating: .minimum(4)))
        let ids = controller.orderedAssetIDs()
        controller.setSelection(ids, activeID: ids[0])
        _ = await controller.prepareOrdering(query: evenRating)
        let before = controller.orderedEntriesBuildCount

        controller.restrictSelection(to: evenRating)

        XCTAssertEqual(controller.orderedEntriesBuildCount, before)
        let expected = Set(controller.orderedAssetIDs(query: evenRating))
        XCTAssertEqual(controller.selectedIDs, expected)
        XCTAssertFalse(expected.isEmpty)
        XCTAssertTrue(expected.contains(try XCTUnwrap(controller.activeID)))
    }

    func testMainActorKeepsRunningWhileABackgroundSortIsInFlight() async throws {
        let controller = try controller(count: 30_000)
        let sortSeconds = inlineSortSeconds(controller, byName)
        XCTAssertGreaterThan(sortSeconds, 0.05, "the index is too small to show a stall")

        var ticks = 0
        var maxGap = 0.0
        var last = ContinuousClock.now
        let heartbeat = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(2))
                let now = ContinuousClock.now
                maxGap = max(maxGap, last.duration(to: now).seconds)
                last = now
                ticks += 1
            }
        }
        last = .now
        _ = await controller.prepareOrdering(query: byName)
        heartbeat.cancel()
        await heartbeat.value

        print("KRMA-1163 heartbeat: inline sort \(sortSeconds)s, max main-actor gap \(maxGap)s, ticks \(ticks)")
        XCTAssertGreaterThan(ticks, 5)
        XCTAssertLessThan(maxGap, sortSeconds / 2,
                          "the main actor was blocked for \(maxGap)s by a \(sortSeconds)s sort")
    }

    func testForegroundCacheHitDoesNotWaitBehindABackgroundSort() async throws {
        let controller = try controller(count: 30_000)
        _ = controller.page(at: 0, query: .all)
        let sortSeconds = inlineSortSeconds(controller, byName)
        let planner = controller

        let background = Task.detached { planner.orderedAssetIDs(query: planner.byNameForTest) }
        try await Task.sleep(for: .milliseconds(10))
        let start = ContinuousClock.now
        let page = controller.page(at: 0, query: .all)
        let waited = start.duration(to: .now).seconds
        _ = await background.value

        print("KRMA-1163 foreground: sort \(sortSeconds)s, cached read waited \(waited)s")
        XCTAssertEqual(page.items.count, 50)
        XCTAssertLessThan(waited, sortSeconds / 4,
                          "a cached foreground read waited \(waited)s behind a \(sortSeconds)s sort")
    }

    func testImportAndIndexRefreshNotifyIndexReplaced() throws {
        let packageURL = tempDirectory.appendingPathComponent("Notify.kromoralibrary")
        let indexURL = tempDirectory.appendingPathComponent("Index/LibraryIndex.store")
        let sourceURL = try Fixtures.writeJPEG(
            width: 40, height: 20, orientation: 1, named: "notify.jpg", in: tempDirectory)
        let session = try PortableLibrarySession(at: packageURL, indexURL: indexURL)
        let presentation = LibraryPresentationState()
        presentation.observeIndexReplacements(from: session)
        let initialRevision = presentation.indexRevision

        _ = try session.importURLs([sourceURL])
        XCTAssertGreaterThan(
            presentation.indexRevision, initialRevision,
            "an import changes the index with the query unchanged"
        )
        let afterImport = presentation.indexRevision
        _ = try session.refreshIndex()
        XCTAssertGreaterThan(presentation.indexRevision, afterImport)
        try session.lease.release()
    }

    func testIndexUpdateDuringPreparationRepeatsAgainstTheNewGeneration() async throws {
        let packageURL = tempDirectory.appendingPathComponent("Prepare.kromoralibrary")
        let indexURL = tempDirectory.appendingPathComponent("Index/LibraryIndex.store")
        let sourceURL = try Fixtures.writeJPEG(
            width: 40, height: 20, orientation: 1, named: "prepare.jpg", in: tempDirectory)
        let session = try PortableLibrarySession(at: packageURL, indexURL: indexURL)
        _ = try session.importURLs([sourceURL])
        let gate = Gate()
        session.orderingPreparationGate = { _ in await gate.wait() }
        let startGeneration = session.indexGeneration

        let preparation = Task { await session.prepareOrdering(query: self.byName) }
        while await gate.waiterCount == 0 { await Task.yield() }
        let staleController = session.queryController
        _ = try session.refreshIndex()
        XCTAssertGreaterThan(session.indexGeneration, startGeneration)
        await gate.open()
        await preparation.value

        XCTAssertEqual(staleController.orderedEntriesBuildCount, 1, "built for the generation it began on")
        XCTAssertEqual(session.queryController.orderedEntriesBuildCount, 1,
                       "and repeated for the generation that replaced it")
        XCTAssertEqual(session.page(at: 0, query: byName).totalCount, 1)
        XCTAssertEqual(session.queryController.orderedEntriesBuildCount, 1)
        try session.lease.release()
    }
}

private extension LibraryQueryController {
    var byNameForTest: LibraryQuery {
        LibraryQuery(sort: .init(key: .displayName, direction: .descending))
    }
}

private extension Duration {
    var seconds: Double {
        Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}

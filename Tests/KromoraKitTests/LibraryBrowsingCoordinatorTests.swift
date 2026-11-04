import AppKit
import CoreGraphics
import Foundation
import XCTest
import os.lock

@testable import KromoraKit

@MainActor
final class LibraryBrowsingCoordinatorTests: XCTestCase {
    private var collections: [ImageCollection] = []

    override func tearDown() async throws {
        for collection in collections { await collection.shutdown() }
        collections.removeAll()
        try await super.tearDown()
    }

    private actor PreparationGate {
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

    private final class FakeLibrary: LibraryBrowsingProviding {
        let assets: [PhotoAsset]
        let pageSize: Int
        var indexedAssetCount: Int
        /// How many of `assets` the index currently holds; raising it simulates an import
        /// committing more photos. `newestFirst` orders the newest at the head of the window.
        var committedCount: Int
        var newestFirst = false
        private(set) var selectedIDs = Set<PortablePhotoAssetID>()
        private(set) var activeID: PortablePhotoAssetID?
        private(set) var requestedPages: [Int] = []
        private(set) var requestedQueries: [LibraryQuery] = []
        private(set) var facetQueries: [LibraryQuery] = []
        /// Awaited by `prepareOrdering`, so a test decides when and in what order queries finish.
        var orderingGate: (@MainActor (LibraryQuery) async -> Void)?
        private(set) var rebuildCount = 0
        /// False after `replaceIndex()` until `prepareOrdering` runs, like a new index generation.
        private(set) var orderingReady = true
        /// Window or page reads served while the ordering was not prepared (they would sort inline).
        private(set) var unpreparedReads = 0
        private(set) var preparedQueries: [LibraryQuery] = []
        /// When set, preparation sorts this controller off-main and readiness follows its cache.
        var sortingController: LibraryQueryController?
        private(set) var persistedStates: [(PortablePhotoAssetID, Int, PhotoFlag)] = []
        /// Ids whose browsing projection throws, failing any lookup that includes them.
        var failingIDs = Set<PortablePhotoAssetID>()
        private(set) var lookupSizes: [Int] = []

        init(count: Int, pageSize: Int, presentedAspectRatio: Double? = nil) {
            self.pageSize = pageSize
            self.indexedAssetCount = count
            self.committedCount = count
            self.assets = (0..<count).map { index in
                let id = PortablePhotoAssetID(uuid: UUID())
                let identity = PortablePhotoIdentity(
                    assetID: id,
                    sourceFingerprint: PortablePhotoSourceFingerprint(
                        contentHash: String(repeating: "a", count: 64),
                        decoderVersion: "test-v1"
                    )
                )
                let source = PhotoAssetSource(
                    data: Data([UInt8(truncatingIfNeeded: index)]),
                    id: PhotoAssetID(rawValue: "portable:\(id.raw)"),
                    portableIdentity: identity
                )
                return PhotoAsset(
                    source: source, filename: "photo-\(index).jpg", fileType: "jpg",
                    presentedAspectRatio: presentedAspectRatio
                )
            }
        }

        var queryPageSize: Int { pageSize }
        var assetCount: Int { indexedAssetCount }
        var portableSelectedIDs: Set<PortablePhotoAssetID> { selectedIDs }
        var portableActiveID: PortablePhotoAssetID? { activeID }
        var libraryID = UUID()
        func launchHintAssets(for ids: [PortablePhotoAssetID]) -> [PhotoAsset] {
            assets.prefix(indexedAssetCount).filter { ids.contains($0.source.portableIdentity.assetID) }
        }

        private var committedAssets: [PhotoAsset] {
            let committed = Array(assets.prefix(committedCount))
            return newestFirst ? committed.reversed() : committed
        }

        func browsingWindow(pageIndex: Int, query: LibraryQuery) throws
            -> (assets: [PhotoAsset], totalCount: Int, pageSize: Int) {
            requestedPages.append(pageIndex)
            requestedQueries.append(query)
            noteRead(query)
            let visible = committedAssets
            let start = pageIndex * pageSize
            let end = min(start + pageSize, visible.count)
            return (start < visible.count ? Array(visible[start..<end]) : [], visible.count, pageSize)
        }

        func facetCounts(query: LibraryQuery) async -> LibraryFacetCounts {
            facetQueries.append(query)
            return LibraryFacetCounts()
        }

        func prepareOrdering(query: LibraryQuery) async {
            preparedQueries.append(query)
            await orderingGate?(query)
            if let sortingController { _ = await sortingController.prepareOrdering(query: query) }
            orderingReady = true
        }

        func hasPreparedOrdering(for query: LibraryQuery, pageIndex: Int) -> Bool {
            if let sortingController { return sortingController.hasCachedOrdering(for: query) }
            return orderingReady
        }

        /// A new index generation: the next synchronous read would filter and sort.
        func replaceIndex(with controller: LibraryQueryController? = nil) {
            orderingReady = false
            if let controller { sortingController = controller }
        }

        private func noteRead(_ query: LibraryQuery) {
            if !hasPreparedOrdering(for: query, pageIndex: 0) { unpreparedReads += 1 }
        }

        func pageIndex(of assetID: PortablePhotoAssetID, query: LibraryQuery) -> Int? {
            committedAssets.firstIndex { $0.source.portableIdentity.assetID == assetID }
                .map { $0 / pageSize }
        }

        func page(at pageIndex: Int, query: LibraryQuery) -> LibraryQueryPage {
            noteRead(query)
            let visible = committedAssets
            let start = pageIndex * pageSize
            let selected = start < visible.count ? Array(visible[start..<min(start + pageSize, visible.count)]) : []
            let items = selected.map { asset in
                let id = asset.source.portableIdentity.assetID
                return LibraryQueryItem(
                    assetID: id, recordPath: "unused",
                    summary: PortablePackageAssetSummary(displayName: asset.displayName),
                    isSelected: selectedIDs.contains(id)
                )
            }
            return LibraryQueryPage(
                pageIndex: pageIndex, pageSize: pageSize, totalCount: visible.count, items: items
            )
        }

        func browsingAssets(forIDs ids: [PortablePhotoAssetID]) throws -> [PhotoAsset] {
            lookupSizes.append(ids.count)
            if ids.contains(where: failingIDs.contains) { throw CocoaError(.fileReadCorruptFile) }
            return ids.compactMap { id in assets.first { $0.source.portableIdentity.assetID == id } }
        }
        func browsingAssets(for items: [LibraryQueryItem]) throws -> [PhotoAsset] {
            items.compactMap { item in
                assets.first { $0.source.portableIdentity.assetID == item.assetID }
            }
        }

        func select(_ assetID: PortablePhotoAssetID, additive: Bool = false) {
            if !additive { selectedIDs.removeAll() }
            selectedIDs.insert(assetID)
            activeID = assetID
        }

        func setPortableSelection(_ assetIDs: [PortablePhotoAssetID], activeID: PortablePhotoAssetID?) {
            selectedIDs = Set(assetIDs)
            self.activeID = activeID
        }

        func selectAllPortable(query: LibraryQuery) {
            selectedIDs = Set(assets.prefix(committedCount).map { $0.source.portableIdentity.assetID })
            activeID = selectedIDs.first
        }

        func restrictPortableSelection(to query: LibraryQuery) {}

        func togglePortableSelection(_ assetID: PortablePhotoAssetID) {
            if !selectedIDs.insert(assetID).inserted { selectedIDs.remove(assetID) }
            activeID = selectedIDs.contains(assetID) ? assetID : selectedIDs.first
        }

        func resolveEmbeddedSourceURL(for assetID: PortablePhotoAssetID) throws -> URL {
            URL(fileURLWithPath: "/virtual/\(assetID.raw).jpg")
        }

        func materializedAsset(for assetID: PortablePhotoAssetID) async throws -> PhotoAsset {
            try XCTUnwrap(assets.first {
                $0.source.portableIdentity.assetID == assetID
            })
        }

        func updateLibraryState(for assetID: PortablePhotoAssetID, rating: Int, flag: PhotoFlag) throws {
            persistedStates.append((assetID, rating, flag))
        }

        func enqueueLibraryStateUpdates(
            _ updates: [PortableLibrarySession.LibraryStateUpdate],
            onFailure: @escaping @MainActor (Error) -> Void
        ) {
            for update in updates { persistedStates.append((update.assetID, update.rating, update.flag)) }
        }

        func newestLibraryState(for assetID: PortablePhotoAssetID)
            -> PortableLibrarySession.LibraryStateUpdate? {
            persistedStates.last { $0.0 == assetID }.map { .init(assetID: $0.0, rating: $0.1, flag: $0.2) }
        }

        func rebuildIndex() throws { rebuildCount += 1 }
    }

    @MainActor
    private final class RasterAssignmentProbe {
        private(set) var images: [NSImage] = []
        func record(_ image: NSImage) { images.append(image) }
    }

    private actor FrameReadProbe: LaunchHintFrameReading {
        private(set) var identities: [PortablePhotoIdentity] = []
        var delay: Duration = .zero
        private var frames: [PortablePhotoIdentity: ThumbnailFrameStore.StoredFrames] = [:]

        func setDelay(_ delay: Duration) { self.delay = delay }
        func setFrames(_ frames: ThumbnailFrameStore.StoredFrames, for identity: PortablePhotoIdentity) {
            self.frames[identity] = frames
        }
        func readIdentities() -> [PortablePhotoIdentity] { identities }

        func readFrames(for identity: PortablePhotoIdentity) async -> ThumbnailFrameStore.StoredFrames {
            identities.append(identity)
            if delay > .zero { try? await Task.sleep(for: delay) }
            return frames[identity] ?? ThumbnailFrameStore.StoredFrames(original: nil, edited: nil)
        }
    }

    private final class FakeDestination: LibraryBrowsingDestination {
        var portableQuery = LibraryQuery.all
        var libraryDeletionConfirmation: LibraryDeletionConfirmation?
        var isLibraryGridShowing = true
        private(set) var opened: [(URL, PhotoAssetID)] = []
        private(set) var status: [String] = []
        private(set) var errors: [String] = []
        private(set) var selectedForEdit: [Int] = []
        private(set) var deletionRequests: [[ImageCollection.DeletionCandidate]] = []
        private(set) var showedGridCount = 0

        func showLibraryGridIfActive() { showedGridCount += 1 }
        func openPortableLibraryAsset(url: URL, assetID: PhotoAssetID) { opened.append((url, assetID)) }
        func selectCollectionImage(at index: Int) { selectedForEdit.append(index) }
        func setLibraryStatusMessage(_ message: String) { status.append(message) }
        func presentLibraryError(_ message: String) { errors.append(message) }
        func deleteLibraryItems(_ candidates: [ImageCollection.DeletionCandidate]) async
            -> LibraryDeletionResult {
            deletionRequests.append(candidates)
            return LibraryDeletionResult(deletedIDs: [], failures: [])
        }
    }

    private func makeCoordinator(
        count: Int = 5, pageSize: Int = 2, isGrid: Bool = true
    ) -> (LibraryBrowsingCoordinator, ImageCollection, FakeLibrary, FakeDestination) {
        let collection = ImageCollection(scheduler: ImageWorkScheduler())
        collections.append(collection)
        let library = FakeLibrary(count: count, pageSize: pageSize)
        let destination = FakeDestination()
        destination.isLibraryGridShowing = isGrid
        let coordinator = LibraryBrowsingCoordinator(
            collection: collection, library: library, destination: destination
        )
        return (coordinator, collection, library, destination)
    }

    private func replaceIndexWithSortingController(for library: FakeLibrary) throws {
        let entries = library.assets.map { asset in
            let assetID = asset.source.portableIdentity.assetID
            return LibraryIndexEntry(from: .init(
                assetID: assetID,
                recordPath: "Assets/\(PortableLibraryPackage.shard(for: assetID))/\(assetID.raw)/asset.json",
                summary: .init(displayName: asset.filename)
            ))
        }
        let index = try LibraryIndexProjection(libraryID: library.libraryID, entries: entries)
        library.replaceIndex(with: LibraryQueryController(index: index, pageSize: library.pageSize))
    }

    func testMergeCommittedImportsInsertsInOrderAndKeepsSelectionAndCells() throws {
        let (coordinator, collection, library, destination) = makeCoordinator(count: 6, pageSize: 4)
        defer { withExtendedLifetime(destination) {} }
        library.committedCount = 2
        library.newestFirst = true
        try coordinator.reloadPortableWindow()
        let originalIDs = collection.items.map(\.id)
        XCTAssertEqual(originalIDs.count, 2)
        coordinator.selectPortableItem(at: 1)
        let selectedID = try XCTUnwrap(collection.selectedItem?.id)
        let survivor = collection.items[1]

        // Two more photos commit; being newest-first they land at the head of the window.
        library.committedCount = 4
        try coordinator.mergeCommittedImports()

        XCTAssertEqual(collection.items.count, 4)
        XCTAssertEqual(collection.portableTotalCount, 4)
        XCTAssertEqual(
            collection.items.map(\.displayName),
            ["photo-3.jpg", "photo-2.jpg", "photo-1.jpg", "photo-0.jpg"]
        )
        // Existing cells are reused rather than rebuilt, and the selection follows its photo.
        XCTAssertTrue(collection.items[3] === survivor)
        XCTAssertEqual(collection.selectedItem?.id, selectedID)
        XCTAssertEqual(collection.selectedIndex, 3)
        // Arriving cells show the spinner state until their thumbnail lands.
        XCTAssertEqual(collection.items[0].asset.thumbnailState, .loading)
        XCTAssertEqual(collection.items[1].asset.thumbnailState, .loading)
        // The merge never reloads page zero.
        XCTAssertEqual(library.requestedPages, [0])
    }

    // MARK: KRMA-1163 index-generation updates

    func testReloadAfterIndexReplacementPreparesOffMainAndKeepsTheOldWindowMeanwhile() async throws {
        let (coordinator, collection, library, destination) = makeCoordinator(count: 6, pageSize: 4)
        defer { withExtendedLifetime(destination) {} }
        try coordinator.reloadPortableWindow()
        let before = collection.items.map(\.id)
        coordinator.selectPortableItem(at: 1)
        let selected = collection.selectedItem?.id

        let gate = PreparationGate()
        library.orderingGate = { _ in await gate.wait() }
        library.replaceIndex()
        library.committedCount = 5
        var failures = 0
        coordinator.publishIndexUpdate(.init(
            kind: .reload,
            apply: { try coordinator.reloadPortableWindow() },
            onFailure: { _ in failures += 1 }
        ))
        while await gate.waiterCount == 0 { await Task.yield() }

        // Mid-preparation: nothing was read, and the previous window and selection are intact.
        XCTAssertEqual(library.unpreparedReads, 0)
        XCTAssertEqual(library.requestedPages, [0])
        XCTAssertEqual(collection.items.map(\.id), before)
        XCTAssertEqual(collection.selectedItem?.id, selected)

        await gate.open()
        await coordinator.waitForIndexUpdate()

        XCTAssertEqual(library.unpreparedReads, 0, "the window was read from a prepared ordering")
        XCTAssertEqual(library.requestedPages, [0, 0])
        XCTAssertEqual(collection.portableTotalCount, 5)
        XCTAssertEqual(failures, 0)
    }

    func testPreparedReloadRepeatsWhenTheQueryChangesDuringPreparation() async throws {
        let (coordinator, _, library, destination) = makeCoordinator(count: 300, pageSize: 10)
        defer { withExtendedLifetime(destination) {} }
        try coordinator.reloadPortableWindow()
        try replaceIndexWithSortingController(for: library)

        let gate = PreparationGate()
        library.orderingGate = { _ in await gate.wait() }
        let firstQuery = LibraryQuery(searchText: "photo-0")
        let latestQuery = LibraryQuery(searchText: "photo-1")
        destination.portableQuery = firstQuery

        let reload = Task { try await coordinator.reloadPortableCollectionPrepared() }
        while await gate.waiterCount == 0 { await Task.yield() }
        destination.portableQuery = latestQuery
        await gate.open()
        try await reload.value

        XCTAssertEqual(library.requestedQueries.last, latestQuery)
        XCTAssertEqual(library.unpreparedReads, 0)
    }

    func testReadyOrderingPublishesTheIndexUpdateSynchronously() throws {
        let (coordinator, collection, library, destination) = makeCoordinator(count: 3, pageSize: 2)
        defer { withExtendedLifetime(destination) {} }
        coordinator.publishIndexUpdate(.init(
            kind: .reload, apply: { try coordinator.reloadPortableWindow() }, onFailure: { _ in }
        ))
        XCTAssertEqual(collection.items.count, 2, "no preparation hop when the ordering is cached")
        XCTAssertTrue(library.preparedQueries.isEmpty)
    }

    func testMergeAfterIndexReplacementPreparesBeforeReadingLoadedPages() async throws {
        let (coordinator, collection, library, destination) = makeCoordinator(count: 6, pageSize: 2)
        defer { withExtendedLifetime(destination) {} }
        library.committedCount = 4
        library.newestFirst = true
        try coordinator.reloadPortableWindow()
        collection.appendPortableWindow(
            assets: try library.browsingWindow(pageIndex: 1, query: .all).assets, pageIndex: 1)

        library.replaceIndex()
        library.committedCount = 6
        coordinator.publishIndexUpdate(.init(
            kind: .merge, apply: { try coordinator.mergeCommittedImports() }, onFailure: { _ in }
        ))
        XCTAssertEqual(library.requestedPages, [0, 1], "nothing was read before preparation")
        await coordinator.waitForIndexUpdate()

        XCTAssertEqual(library.unpreparedReads, 0)
        XCTAssertEqual(collection.portableTotalCount, 6)
        XCTAssertEqual(collection.items.count, 4)
    }

    func testIndexUpdatesDuringPreparationCoalesceAndAReloadSupersedesAMerge() async throws {
        let (coordinator, collection, library, destination) = makeCoordinator(count: 6, pageSize: 4)
        defer { withExtendedLifetime(destination) {} }
        library.committedCount = 2
        try coordinator.reloadPortableWindow()
        let gate = PreparationGate()
        library.orderingGate = { _ in await gate.wait() }
        library.replaceIndex()
        library.committedCount = 3

        var applied: [String] = []
        func merge() -> LibraryBrowsingCoordinator.IndexUpdate {
            .init(kind: .merge, apply: { applied.append("merge") }, onFailure: { _ in })
        }
        coordinator.publishIndexUpdate(merge())
        while await gate.waiterCount == 0 { await Task.yield() }
        coordinator.publishIndexUpdate(merge())
        coordinator.publishIndexUpdate(.init(
            kind: .reload,
            apply: { applied.append("reload"); try coordinator.reloadPortableWindow() },
            onFailure: { _ in }
        ))
        coordinator.publishIndexUpdate(merge())
        await gate.open()
        await coordinator.waitForIndexUpdate()

        XCTAssertEqual(applied.first, "merge", "the in-flight request keeps its place until superseded")
        XCTAssertEqual(applied.count, 1, "later requests coalesced into the pending update")
        XCTAssertEqual(library.preparedQueries.count, 1)
        _ = collection
    }

    func testIndexUpdateIsDiscardedWhenTheQueryChangesDuringPreparation() async throws {
        let (coordinator, _, library, destination) = makeCoordinator(count: 4, pageSize: 4)
        try coordinator.reloadPortableWindow()
        let gate = PreparationGate()
        library.orderingGate = { _ in await gate.wait() }
        library.replaceIndex()
        var applied = 0
        coordinator.publishIndexUpdate(.init(
            kind: .reload, apply: { applied += 1 }, onFailure: { _ in }
        ))
        while await gate.waiterCount == 0 { await Task.yield() }
        destination.portableQuery = LibraryQuery(searchText: "other")
        await gate.open()
        await coordinator.waitForIndexUpdate()

        XCTAssertEqual(applied, 0, "the query-change path republishes this window")
    }

    func testMainActorKeepsRunningWhileAnIndexUpdateSortsLargeLibraryOffMain() async throws {
        let (coordinator, collection, library, destination) = makeCoordinator(count: 4, pageSize: 4)
        defer { withExtendedLifetime(destination) {} }
        let byName = LibraryQuery(sort: .init(key: .displayName, direction: .descending))
        destination.portableQuery = byName
        let entries = (0..<30_000).map { index in
            let assetID = PortablePhotoAssetID()
            return LibraryIndexEntry(from: .init(
                assetID: assetID,
                recordPath: "Assets/" + PortableLibraryPackage.shard(for: assetID)
                    + "/" + assetID.raw + "/asset.json",
                summary: .init(rating: index % 6, displayName: "Frame \(index * 7919 % 30_000)")
            ))
        }
        let index = try LibraryIndexProjection(libraryID: UUID(), entries: entries)
        let inline = LibraryQueryController(index: index, pageSize: 4)
        let start = ContinuousClock.now
        _ = inline.orderedAssetIDs(query: byName)
        let sortSeconds = start.duration(to: .now).seconds
        XCTAssertGreaterThan(sortSeconds, 0.05, "the index is too small to show a stall")

        try coordinator.reloadPortableWindow()
        library.replaceIndex(with: LibraryQueryController(index: index, pageSize: 4))
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
        coordinator.publishReloadedWindow(
            apply: { try coordinator.reloadPortableWindow() }, onFailure: { _ in }
        )
        await coordinator.waitForIndexUpdate()
        heartbeat.cancel()
        await heartbeat.value

        print("KRMA-1163 index update: inline sort \(sortSeconds)s, max main-actor gap \(maxGap)s, ticks \(ticks)")
        XCTAssertEqual(library.unpreparedReads, 0)
        XCTAssertGreaterThan(ticks, 5)
        XCTAssertLessThan(maxGap, sortSeconds / 2,
                          "the main actor was blocked for \(maxGap)s by a \(sortSeconds)s sort")
        _ = collection
    }

    func testOffWindowOpenRepreparesWhenTheQueryChangesDuringIndexPreparation() async throws {
        let (coordinator, _, library, destination) = makeCoordinator(count: 300, pageSize: 2)
        defer { withExtendedLifetime(destination) {} }
        try coordinator.reloadPortableWindow()
        try replaceIndexWithSortingController(for: library)

        let gate = PreparationGate()
        library.orderingGate = { _ in await gate.wait() }
        let assetID = library.assets[10].source.portableIdentity.assetID
        coordinator.openPortableAsset(assetID)
        while await gate.waiterCount == 0 { await Task.yield() }

        destination.portableQuery = LibraryQuery(searchText: "photo-10")
        await gate.open()
        await coordinator.waitForIndexUpdate()

        XCTAssertEqual(library.unpreparedReads, 0)
        XCTAssertEqual(library.requestedQueries.last, destination.portableQuery)
        XCTAssertEqual(destination.opened.count, 1)
    }

    func testFacetCountsUseTheCapturedQuery() async {
        let (coordinator, _, library, destination) = makeCoordinator()
        defer { withExtendedLifetime(destination) {} }
        destination.portableQuery = LibraryQuery(searchText: "current")
        let capturedQuery = LibraryQuery(searchText: "captured")

        let result = await coordinator.portableFacetCounts(query: capturedQuery)

        XCTAssertNotNil(result)
        XCTAssertEqual(library.facetQueries, [capturedQuery])
    }

    func testMergeCommittedImportsKeepsLoadedPagesAndBoundsWindowToThem() throws {
        let (coordinator, collection, library, destination) = makeCoordinator(count: 6, pageSize: 2)
        defer { withExtendedLifetime(destination) {} }
        library.committedCount = 4
        library.newestFirst = true
        try coordinator.reloadPortableWindow()
        collection.appendPortableWindow(
            assets: try library.browsingWindow(pageIndex: 1, query: .all).assets, pageIndex: 1
        )
        XCTAssertEqual(collection.items.count, 4)

        library.committedCount = 6
        try coordinator.mergeCommittedImports()

        // Two loaded pages stay two loaded pages; the total reflects the whole import so far
        // and the tail pages in through the usual scroll path.
        XCTAssertEqual(collection.items.count, 4)
        XCTAssertEqual(collection.portableTotalCount, 6)
        XCTAssertTrue(collection.portableHasMorePages)
        XCTAssertEqual(
            collection.items.map(\.displayName),
            ["photo-5.jpg", "photo-4.jpg", "photo-3.jpg", "photo-2.jpg"]
        )
    }

    func testMergeCommittedImportsWithNoWindowLoadsPageZero() throws {
        let (coordinator, collection, library, destination) = makeCoordinator(count: 3, pageSize: 2)
        defer { withExtendedLifetime(destination) {} }
        XCTAssertFalse(collection.isPortableWindowed)
        try coordinator.mergeCommittedImports()
        XCTAssertEqual(library.requestedPages, [0])
        XCTAssertEqual(collection.items.count, 2)
        XCTAssertEqual(collection.portableTotalCount, 3)
    }

    func testFilterSortAndSearchReloadPageZeroAndSkipNoOp() async throws {
        let (coordinator, _, library, destination) = makeCoordinator()
        try coordinator.reloadPortableWindow()
        coordinator.setPortableFilter(LibraryFilter(flag: .picks))
        await coordinator.waitForQueryPreparation()
        coordinator.setPortableFilter(LibraryFilter(flag: .picks))
        await coordinator.waitForQueryPreparation()
        coordinator.setPortableSort(LibraryQuerySort(key: .rating, direction: .descending))
        await coordinator.waitForQueryPreparation()
        coordinator.setPortableSearch("  photo  ")
        await coordinator.waitForQueryPreparation()
        coordinator.setPortableSearch("photo")
        await coordinator.waitForQueryPreparation()

        XCTAssertEqual(library.requestedPages, [0, 0, 0, 0])
        XCTAssertEqual(destination.portableQuery.searchText, "photo")
    }

    func testBackToBackQueryChangesPublishOnlyTheNewestWindow() async throws {
        let (coordinator, _, library, destination) = makeCoordinator()
        try coordinator.reloadPortableWindow()
        coordinator.setPortableFilter(LibraryFilter(flag: .picks))
        coordinator.setPortableSort(LibraryQuerySort(key: .rating, direction: .descending))
        coordinator.setPortableSearch("photo")
        await coordinator.waitForQueryPreparation()

        XCTAssertEqual(library.requestedQueries, [.all, destination.portableQuery])
    }

    func testQueryChangeKeepsThePreviousWindowAndSelectionUntilOrderingIsPrepared() async throws {
        let (coordinator, collection, library, destination) = makeCoordinator()
        try coordinator.reloadPortableWindow()
        library.select(library.assets[0].source.portableIdentity.assetID)
        let shownBefore = collection.items.map(\.id)
        var release: CheckedContinuation<Void, Never>?
        library.orderingGate = { _ in await withCheckedContinuation { release = $0 } }

        let sort = LibraryQuerySort(key: .rating, direction: .descending)
        coordinator.setPortableSort(sort)
        for _ in 0..<5 { await Task.yield() }

        XCTAssertEqual(destination.portableQuery.sort, sort, "the request is recorded at once")
        XCTAssertEqual(collection.items.map(\.id), shownBefore, "the grid still shows the old window")
        XCTAssertEqual(collection.portableQuery, .all)
        XCTAssertEqual(library.requestedQueries, [.all])
        XCTAssertEqual(library.portableSelectedIDs.count, 1)

        // Paging while preparation is in flight continues the loaded window's own query.
        coordinator.loadMorePortableIfNeeded(currentIndex: collection.items.count - 1)
        XCTAssertEqual(library.requestedQueries, [.all, .all])

        try XCTUnwrap(release).resume()
        await coordinator.waitForQueryPreparation()
        XCTAssertEqual(collection.portableQuery, destination.portableQuery)
        XCTAssertEqual(library.requestedQueries.last, destination.portableQuery)
    }

    func testReverseCompletingQueryRequestsNeverInstallTheSupersededWindow() async throws {
        let (coordinator, collection, library, destination) = makeCoordinator()
        try coordinator.reloadPortableWindow()
        var releases: [LibraryQuerySort: CheckedContinuation<Void, Never>] = [:]
        library.orderingGate = { query in
            await withCheckedContinuation { releases[query.sort] = $0 }
        }
        let first = LibraryQuerySort(key: .rating, direction: .descending)
        let second = LibraryQuerySort(key: .displayName, direction: .ascending)

        coordinator.setPortableSort(first)
        for _ in 0..<5 { await Task.yield() }
        let firstRelease = try XCTUnwrap(releases[first])
        coordinator.setPortableSort(second)
        for _ in 0..<5 { await Task.yield() }
        let secondRelease = try XCTUnwrap(releases[second])

        // The newer request finishes first; the older one completes afterwards and must be dropped.
        secondRelease.resume()
        await coordinator.waitForQueryPreparation()
        XCTAssertEqual(collection.portableQuery.sort, second)
        let loads = library.requestedQueries.count
        firstRelease.resume()
        for _ in 0..<10 { await Task.yield() }

        XCTAssertEqual(library.requestedQueries.count, loads)
        XCTAssertEqual(collection.portableQuery.sort, second)
        XCTAssertEqual(destination.portableQuery.sort, second)
    }

    func testClearPortableFiltersResetsFiltersAndPreservesSort() async throws {
        let (coordinator, _, library, destination) = makeCoordinator()
        try coordinator.reloadPortableWindow()
        let sort = LibraryQuerySort(key: .rating, direction: .descending)
        coordinator.setPortableSort(sort)
        await coordinator.waitForQueryPreparation()
        coordinator.setPortableFilter(LibraryFilter(flag: .picks, rating: .minimum(3)))
        await coordinator.waitForQueryPreparation()
        coordinator.setPortableSearch("photo")
        await coordinator.waitForQueryPreparation()
        var facets = LibraryFacetSelection()
        facets.toggle("Sony A7", in: .camera)
        coordinator.setPortableFacets(facets)
        await coordinator.waitForQueryPreparation()
        let loads = library.requestedPages.count

        coordinator.clearPortableFilters()
        await coordinator.waitForQueryPreparation()
        XCTAssertEqual(destination.portableQuery, LibraryQuery(sort: sort))
        XCTAssertEqual(library.requestedPages.count, loads + 1)

        coordinator.clearPortableFilters()
        await coordinator.waitForQueryPreparation()
        XCTAssertEqual(library.requestedPages.count, loads + 1, "no-op when nothing is active")
    }

    func testPresentedAspectRatioDeltaTouchesOnlyGeometryAndDoesNotRequestPixels() async throws {
        let assetID = PortablePhotoAssetID()
        let summary = PortablePackageAssetSummary(
            rating: 4, flag: PhotoFlag.pick.rawValue,
            dimensions: PhotoPixelDimensions(width: 40, height: 20),
            aspectRatio: 2, displayName: "ratio-only.jpg", assetRevision: 7
        )
        let entry = LibraryIndexEntry(
            assetID: assetID,
            recordPath: "Assets/\(PortableLibraryPackage.shard(for: assetID))/\(assetID.raw)/asset.json",
            summary: summary
        )
        let index = try LibraryIndexProjection(libraryID: UUID(), entries: [entry])
        let ratioDelta = LibraryIndexDelta(
            presentedAspectRatioUpdates: [assetID: 1]
        )
        XCTAssertTrue(ratioDelta.upserts.isEmpty)
        let projected = try index.applying(ratioDelta)
        let projectedEntry = try XCTUnwrap(projected.entry(for: assetID))
        var expectedSummary = summary
        expectedSummary.presentedAspectRatio = 1
        XCTAssertEqual(projectedEntry.summary, expectedSummary)
        XCTAssertEqual(projectedEntry.recordPath, entry.recordPath)

        let scheduler = ImageWorkScheduler()
        let providerCalls = OSAllocatedUnfairLock(initialState: 0)
        let collection = ImageCollection(
            scheduler: scheduler,
            originalThumbnailProvider: { _, _, _, _, _, _, _ in
                providerCalls.withLock { $0 += 1 }
                return nil
            }
        )
        collections.append(collection)
        let identity = PortablePhotoIdentity(
            assetID: assetID,
            sourceFingerprint: .data(Data("ratio-only".utf8), decoderVersion: "test")
        )
        let source = PhotoAssetSource(
            data: Data([0x01]), id: PhotoAssetID(rawValue: "portable:\(assetID.raw)"),
            portableIdentity: identity
        )
        let item = ImageCollection.Item(asset: PhotoAsset(
            source: source, filename: summary.displayName, fileType: "jpg",
            metadata: PhotoAssetMetadata(dimensions: summary.dimensions),
            presentedAspectRatio: nil
        ))
        collection.items = [item]
        let thumbnailDemands = OSAllocatedUnfairLock(initialState: 0)
        collection.onThumbnailDemand = { _, _ in
            thumbnailDemands.withLock { $0 += 1 }
        }

        collection.applyPresentedAspectRatioUpdates([assetID: 1])

        XCTAssertEqual(item.asset.presentedAspectRatio, 1)
        XCTAssertEqual(item.libraryAspectRatio, 1)
        XCTAssertEqual(collection.cropGeneration, 1)
        XCTAssertEqual(thumbnailDemands.withLock { $0 }, 0)
        XCTAssertEqual(providerCalls.withLock { $0 }, 0)
        XCTAssertTrue(scheduler.admissionLog.isEmpty)
    }

    func testKeyboardNextAtWindowTailLoadsNextPageBeforeSelecting() throws {
        let (coordinator, collection, library, destination) = makeCoordinator()
        _ = destination
        try coordinator.reloadPortableWindow()
        coordinator.selectPortableItem(at: 1)

        coordinator.selectNextPortableInGrid()

        XCTAssertEqual(library.requestedPages, [0, 1])
        XCTAssertEqual(collection.portablePageIndex, 1)
        XCTAssertEqual(collection.selectedItem?.displayName, "photo-2.jpg")
    }

    func testOffWindowOpenFaultsItsPageAndMissingAssetDoesNotOpen() async throws {
        let (coordinator, collection, library, destination) = makeCoordinator()
        try coordinator.reloadPortableWindow()
        let offWindowID = library.assets[3].source.portableIdentity.assetID

        coordinator.openPortableAsset(offWindowID)

        XCTAssertEqual(collection.portablePageIndex, 1)
        XCTAssertEqual(destination.opened.count, 1)
        XCTAssertEqual(destination.opened.first?.1, library.assets[3].id)
        coordinator.openPortableAsset(PortablePhotoAssetID())
        await coordinator.waitForIndexUpdate()
        XCTAssertEqual(destination.opened.count, 1)
        XCTAssertEqual(destination.status.last, "The imported photo is not available in the package index.")
        XCTAssertEqual(library.rebuildCount, 1, "a miss rebuilds the disposable index exactly once")
    }

    func testVisibleViewportWritesHintsWithoutRestoringSelection() async throws {
        let collection = ImageCollection(scheduler: ImageWorkScheduler())
        collections.append(collection)
        let library = FakeLibrary(count: 3, pageSize: 3)
        let destination = FakeDestination()
        let root = try Fixtures.makeTempDirectory("LibraryBrowsingLaunchHints")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LaunchHintsStore(url: root.appendingPathComponent("hints.json"))
        let coordinator = LibraryBrowsingCoordinator(
            collection: collection, library: library, destination: destination,
            hintsStore: store
        )
        try coordinator.reloadPortableWindow()
        let visibleID = collection.items[1].id
        collection.requestVisibleThumbnails(for: [visibleID])
        try await Task.sleep(for: .milliseconds(20))
        await coordinator.shutdown()

        let persisted = await store.load(for: library.libraryID)
        guard case .valid(let hints) = persisted else {
            return XCTFail("the actual viewport should persist launch hints")
        }
        XCTAssertEqual(hints.visibleAssetIDs, [library.assets[1].source.portableIdentity.assetID])
        XCTAssertNil(hints.activeAssetID)
        XCTAssertTrue(library.selectedIDs.isEmpty, "launch hints do not become selection truth")
    }

    func testLaunchHintsWaitForIndexAndReadOnlyIndexedAssetsWithinPolicy() async throws {
        let collection = ImageCollection(scheduler: ImageWorkScheduler())
        collections.append(collection)
        let library = FakeLibrary(count: 5, pageSize: 2)
        library.indexedAssetCount = 0
        let destination = FakeDestination()
        let scheduler = ImageWorkScheduler()
        let reader = FrameReadProbe()
        let root = try Fixtures.makeTempDirectory("LibraryBrowsingPartialIndex")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LaunchHintsStore(url: root.appendingPathComponent("hints.json"))
        let ids = library.assets.map { $0.source.portableIdentity.assetID }
        await store.scheduleWrite(LaunchHints(libraryID: library.libraryID, activeAssetID: ids[4], visibleAssetIDs: ids))
        await store.flush()
        let coordinator = LibraryBrowsingCoordinator(
            collection: collection, library: library, destination: destination,
            scheduler: scheduler, frameStore: reader, hintsStore: store
        )

        coordinator.prepareLaunchHints()
        try await waitUntil("launch-hint validation") { coordinator.launchHydrationMetrics.validation == "valid" }
        let beforeIndexReads = await reader.readIdentities()
        XCTAssertTrue(beforeIndexReads.isEmpty, "hints wait for a published index")

        library.indexedAssetCount = 2
        try coordinator.reloadPortableWindow()
        try await waitUntil("indexed hint reads") { await reader.readIdentities().count == 2 }
        try await waitUntil("packed-frame read metrics") { coordinator.launchHydrationMetrics.readCount == 2 }
        let readIdentities = await reader.readIdentities()
        XCTAssertEqual(Set(readIdentities), Set(library.assets.prefix(2).map { $0.source.portableIdentity }))
        XCTAssertEqual(scheduler.admissionLog.filter { $0.id.rawValue.hasPrefix("launch-frame-read:") }.count, 2)
        XCTAssertTrue(scheduler.admissionLog.filter { $0.id.rawValue.hasPrefix("launch-frame-read:") }.allSatisfy {
            $0.lane == .frameRead && $0.priority == .background
        })
        collection.requestVisibleThumbnails(for: [collection.items[0].id])
        let metrics = coordinator.launchHydrationMetrics
        XCTAssertEqual(metrics.validation, "valid")
        XCTAssertEqual(metrics.usefulHits, 0)
        XCTAssertEqual(metrics.bytesRead, 0)
        XCTAssertEqual(metrics.readCount, 2)
        XCTAssertNotNil(metrics.timeToVisibleWindowMilliseconds)
        XCTAssertNotNil(metrics.timeToFirstIndexPageMilliseconds)
        await coordinator.shutdown()
    }

    func testFirstVisiblePublicationSupersedesHintsAndMetricsAreRecordedOnce() async throws {
        let collection = ImageCollection(scheduler: ImageWorkScheduler())
        collections.append(collection)
        let library = FakeLibrary(count: 5, pageSize: 5)
        let destination = FakeDestination()
        let scheduler = ImageWorkScheduler()
        let reader = FrameReadProbe()
        await reader.setDelay(.seconds(1))
        let root = try Fixtures.makeTempDirectory("LibraryBrowsingSupersession")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LaunchHintsStore(url: root.appendingPathComponent("hints.json"))
        let ids = library.assets.map { $0.source.portableIdentity.assetID }
        await store.scheduleWrite(LaunchHints(libraryID: library.libraryID, activeAssetID: ids[4], visibleAssetIDs: ids))
        await store.flush()
        let coordinator = LibraryBrowsingCoordinator(
            collection: collection, library: library, destination: destination,
            scheduler: scheduler, frameStore: reader, hintsStore: store
        )
        coordinator.prepareLaunchHints()
        try await waitUntil("launch-hint validation") { coordinator.launchHydrationMetrics.validation == "valid" }
        try coordinator.reloadPortableWindow()
        try await waitUntil("bounded launch reads") { scheduler.runningFrameReadCount == LaunchHintReadPolicy.maxConcurrentReads }
        let selectionBeforeViewport = library.portableSelectedIDs

        collection.requestVisibleThumbnails(for: [collection.items[3].id])
        let firstMetrics = coordinator.launchHydrationMetrics
        XCTAssertGreaterThan(firstMetrics.superseded, 0)
        XCTAssertLessThanOrEqual(firstMetrics.superseded, ids.count)
        XCTAssertNotNil(firstMetrics.timeToVisibleWindowMilliseconds)
        XCTAssertNotNil(firstMetrics.timeToFirstIndexPageMilliseconds)
        XCTAssertEqual(library.portableSelectedIDs, selectionBeforeViewport, "hinted active ID is never restored")
        XCTAssertEqual(scheduler.pendingFrameReadCount, 0, "hint-only queued work is canceled at first viewport")

        try await Task.sleep(for: .milliseconds(20))
        collection.requestVisibleThumbnails(for: [collection.items[4].id])
        XCTAssertEqual(coordinator.launchHydrationMetrics, firstMetrics, "later scrolling does not replace first-publication measurements")
        await coordinator.shutdown()
    }

    func testUsefulHintFramePublishesOnlyAfterViewportConfirmsAsset() async throws {
        let collection = ImageCollection(scheduler: ImageWorkScheduler())
        collections.append(collection)
        let library = FakeLibrary(count: 1, pageSize: 1)
        let assetID = library.assets[0].source.portableIdentity.assetID
        let identity = library.assets[0].source.portableIdentity
        let destination = FakeDestination()
        let reader = FrameReadProbe()
        let frame = PresentationFrame(
            metadata: FrameFixtures.metadata(
                identity: identity, edit: OriginalThumbnailSignature.editHash,
                kind: .originalThumbnail480
            ),
            rasterData: try FrameFixtures.jpeg()
        )
        let image = try PresentationFrameEnvelope.decodeRaster(of: frame)
        await reader.setFrames(
            ThumbnailFrameStore.StoredFrames(
                original: ThumbnailFrameStore.Hit(frame: frame, image: image), edited: nil
            ),
            for: identity
        )
        let root = try Fixtures.makeTempDirectory("LibraryBrowsingUsefulHint")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LaunchHintsStore(url: root.appendingPathComponent("hints.json"))
        await store.scheduleWrite(LaunchHints(
            libraryID: library.libraryID, activeAssetID: nil, visibleAssetIDs: [assetID]
        ))
        await store.flush()
        let coordinator = LibraryBrowsingCoordinator(
            collection: collection, library: library, destination: destination,
            scheduler: ImageWorkScheduler(), frameStore: reader, hintsStore: store
        )
        coordinator.prepareLaunchHints()
        try await waitUntil("launch-hint validation") { coordinator.launchHydrationMetrics.validation == "valid" }
        try coordinator.reloadPortableWindow()
        try await waitUntil("useful packed-frame read") { coordinator.launchHydrationMetrics.readCount == 1 }
        XCTAssertNil(collection.items[0].originalThumbnailForPresentation)

        collection.requestVisibleThumbnails(for: [collection.items[0].id])

        XCTAssertNotNil(collection.items[0].originalThumbnailForPresentation)
        XCTAssertEqual(coordinator.launchHydrationMetrics.usefulHits, 1)
        XCTAssertGreaterThan(coordinator.launchHydrationMetrics.bytesRead, 0)
        await coordinator.shutdown()
    }

    func testLaunchHintsAndViewportPublishTheSamePersistedFrame() async throws {
        enum HydrationPath: CaseIterable, Equatable { case viewport, launchHints }

        let root = try Fixtures.makeTempDirectory("LibraryBrowsingParity")
        defer { try? FileManager.default.removeItem(at: root) }
        let library = FakeLibrary(count: 1, pageSize: 1, presentedAspectRatio: 1.25)
        let asset = try XCTUnwrap(library.assets.first)
        let identity = asset.source.portableIdentity
        let editedFrame = PresentationFrame(
            metadata: FrameFixtures.metadata(
                identity: identity, edit: "saved-edit", kind: .editedThumbnail480
            ),
            rasterData: try FrameFixtures.jpeg(red: 0.72)
        )
        let originalFrame = PresentationFrame(
            metadata: FrameFixtures.metadata(
                identity: identity, edit: OriginalThumbnailSignature.editHash,
                kind: .originalThumbnail480
            ),
            rasterData: try FrameFixtures.jpeg(red: 0.28)
        )
        let frameStore = ThumbnailFrameStore(directory: root.appendingPathComponent("Frames"))
        await frameStore.enqueueWrite(originalFrame)
        await frameStore.enqueueWrite(editedFrame)
        await frameStore.flush()

        var viewportPixels: [UInt8]?
        var viewportOutcomes: [String] = []
        var viewportRatio = 0.0
        var viewportAssignments = 0
        var launchPixels: [UInt8]?
        var launchOutcomes: [String] = []
        var launchRatio = 0.0
        var launchAssignments = 0

        for path in HydrationPath.allCases {
            let scheduler = ImageWorkScheduler()
            let ledger = FrameLookupLedger()
            let collection = ImageCollection(scheduler: scheduler, frameLookupLedger: ledger)
            collections.append(collection)
            collection.thumbnailFrameStore = frameStore
            let item: ImageCollection.Item
            var browsingCoordinator: LibraryBrowsingCoordinator?

            if path == .launchHints {
                let destination = FakeDestination()
                let hintsStore = LaunchHintsStore(url: root.appendingPathComponent("LaunchHints.json"))
                await hintsStore.scheduleWrite(LaunchHints(
                    libraryID: library.libraryID, activeAssetID: nil,
                    visibleAssetIDs: [identity.assetID]
                ))
                await hintsStore.flush()
                let coordinator = LibraryBrowsingCoordinator(
                    collection: collection, library: library, destination: destination,
                    scheduler: scheduler, frameStore: frameStore, hintsStore: hintsStore
                )
                browsingCoordinator = coordinator
                coordinator.prepareLaunchHints()
                try await waitUntil("launch hints validated") {
                    coordinator.launchHydrationMetrics.validation == "valid"
                }
                try coordinator.reloadPortableWindow()
                try await waitUntil("launch frame read") {
                    coordinator.launchHydrationMetrics.readCount == 1
                }
                item = try XCTUnwrap(collection.items.first)
            } else {
                collection.loadPortableAssets([asset])
                await collection.scanCompletion()
                collection.beginThumbnailDemand()
                item = try XCTUnwrap(collection.items.first)
            }

            let assignments = RasterAssignmentProbe()
            item.onThumbnailAssignment = { assignments.record($0) }
            collection.requestVisibleThumbnails(for: [item.id])
            try await waitUntil("persisted cell frame") {
                let records = await ledger.snapshot()
                return item.thumbnail != nil && records.count >= 2
            }
            let image = try XCTUnwrap(item.thumbnail)
            var proposedRect = CGRect(origin: .zero, size: image.size)
            let cgImage = try XCTUnwrap(image.cgImage(
                forProposedRect: &proposedRect, context: nil, hints: nil
            ))
            let pixels = try Pixels.bytes(of: cgImage)
            let outcomes = Array(Set(await ledger.snapshot().map { $0.outcome.label })).sorted()
            XCTAssertEqual(outcomes, ["exact", "provisionalOnly"])
            XCTAssertEqual(assignments.images.count, 1,
                           "one stored edited raster should paint once on either hydration path")
            let expectedImage = try PresentationFrameEnvelope.decodeRaster(of: editedFrame)
            XCTAssertEqual(pixels, try Pixels.bytes(of: expectedImage))
            XCTAssertEqual(item.libraryAspectRatio, 1.25, accuracy: 0.000_001)
            XCTAssertTrue(item.shouldFillLibraryThumbnail)

            switch path {
            case .viewport:
                viewportPixels = pixels
                viewportOutcomes = outcomes
                viewportRatio = item.libraryAspectRatio
                viewportAssignments = assignments.images.count
            case .launchHints:
                launchPixels = pixels
                launchOutcomes = outcomes
                launchRatio = item.libraryAspectRatio
                launchAssignments = assignments.images.count
            }
            await browsingCoordinator?.shutdown()
            await collection.shutdown()
        }

        XCTAssertEqual(launchPixels, viewportPixels)
        XCTAssertEqual(launchOutcomes, viewportOutcomes)
        XCTAssertEqual(launchRatio, viewportRatio, accuracy: 0.000_001)
        XCTAssertEqual(launchAssignments, viewportAssignments)
    }

    func testHintFrameCannotPublishAfterSourceReplacementKeepsAssetID() throws {
        let collection = ImageCollection(scheduler: ImageWorkScheduler())
        collections.append(collection)
        let originalAsset = FakeLibrary(count: 1, pageSize: 1).assets[0]
        let oldIdentity = originalAsset.source.portableIdentity
        let frame = PresentationFrame(
            metadata: FrameFixtures.metadata(
                identity: oldIdentity, edit: OriginalThumbnailSignature.editHash,
                kind: .originalThumbnail480
            ),
            rasterData: try FrameFixtures.jpeg()
        )
        let hit = ThumbnailFrameStore.Hit(
            frame: frame, image: try PresentationFrameEnvelope.decodeRaster(of: frame)
        )
        collection.loadPortableAssets([originalAsset])

        let replacementIdentity = PortablePhotoIdentity(
            assetID: oldIdentity.assetID,
            sourceFingerprint: PortablePhotoSourceFingerprint(
                contentHash: String(repeating: "b", count: 64), decoderVersion: "test-v2"
            )
        )
        let replacement = PhotoAsset(
            source: PhotoAssetSource(
                data: Data([1]), id: originalAsset.id, portableIdentity: replacementIdentity
            ),
            filename: originalAsset.filename, fileType: originalAsset.fileType
        )
        collection.loadPortableAssets([replacement])
        collection.applyLaunchFrames([
            originalAsset.id: (oldIdentity, ThumbnailFrameStore.StoredFrames(original: hit, edited: nil))
        ])

        XCTAssertNil(collection.items.first?.originalThumbnailForPresentation)
    }

    func testInvalidAndWrongLibraryHintsRecordValidationWithoutReadingFrames() async throws {
        for (name, contents, expected) in [
            ("corrupt", Data("{".utf8), "invalid-or-wrong-library"),
            ("wrong-library", try JSONEncoder().encode(LaunchHints(
                libraryID: UUID(), activeAssetID: nil, visibleAssetIDs: [PortablePhotoAssetID()]
            )), "invalid-or-wrong-library"),
        ] {
            let collection = ImageCollection(scheduler: ImageWorkScheduler())
            collections.append(collection)
            let library = FakeLibrary(count: 1, pageSize: 1)
            let destination = FakeDestination()
            let reader = FrameReadProbe()
            let root = try Fixtures.makeTempDirectory("LibraryBrowsing-\(name)")
            defer { try? FileManager.default.removeItem(at: root) }
            let url = root.appendingPathComponent("hints.json")
            try contents.write(to: url, options: .atomic)
            let coordinator = LibraryBrowsingCoordinator(
                collection: collection, library: library, destination: destination,
                frameStore: reader, hintsStore: LaunchHintsStore(url: url)
            )
            coordinator.prepareLaunchHints()
            try await waitUntil("invalid launch hint validation") {
                coordinator.launchHydrationMetrics.validation == expected
            }
            try coordinator.reloadPortableWindow()
            let readIdentities = await reader.readIdentities()
            XCTAssertTrue(readIdentities.isEmpty)
            XCTAssertEqual(coordinator.launchHydrationMetrics.validation, expected)
            await coordinator.shutdown()
        }
    }

    func testCullingPersistsOnlyWhenStateChanges() throws {
        let (coordinator, _, library, destination) = makeCoordinator()
        _ = destination
        try coordinator.reloadPortableWindow()
        coordinator.selectPortableItem(at: 0)

        XCTAssertTrue(coordinator.setFocusedFlag(.pick))
        XCTAssertFalse(coordinator.setFocusedFlag(.pick))

        XCTAssertEqual(library.persistedStates.count, 1)
        XCTAssertEqual(library.persistedStates.first?.2, .pick)
    }

    func testBulkLookupIsolatesOneFailingIDAcrossChunks() throws {
        let (_, _, library, _) = makeCoordinator(count: 1_200)
        let ids = library.assets.map { $0.source.portableIdentity.assetID }
        library.failingIDs = [ids[10]]

        var resolved: [PhotoAsset] = []
        let unresolved = library.forEachBrowsingAssetChunk(forIDs: ids) { resolved += $0 }

        XCTAssertEqual(unresolved, [ids[10]])
        XCTAssertEqual(resolved.count, 1_199)
        XCTAssertEqual(Set(resolved.map { $0.source.portableIdentity.assetID }), Set(ids).subtracting([ids[10]]))
        XCTAssertLessThanOrEqual(library.lookupSizes.max() ?? 0, 500)
    }

    func testCullingAndDeletionReportUnresolvedSelectedIDs() throws {
        let (coordinator, _, library, destination) = makeCoordinator(count: 1_200)
        try coordinator.reloadPortableWindow()
        coordinator.selectAllInGrid()
        let bad = library.assets[700].source.portableIdentity.assetID
        library.failingIDs = [bad]

        XCTAssertTrue(coordinator.setFocusedFlag(.pick))
        XCTAssertEqual(destination.errors.count, 1)
        XCTAssertTrue(destination.errors[0].contains("1 selected photo"))
        XCTAssertFalse(destination.status.contains { $0.contains("Picked") })
        XCTAssertFalse(library.persistedStates.contains { $0.0 == bad })
        XCTAssertGreaterThan(library.persistedStates.count, 1_000)

        let candidates = coordinator.deletionCandidates()
        XCTAssertEqual(destination.errors.count, 2)
        XCTAssertFalse(candidates.contains { $0.portableIdentity?.assetID == bad })
    }

    func testDeletionConfirmationIsRefusedOutsideGrid() {
        let (coordinator, _, _, destination) = makeCoordinator(isGrid: false)

        coordinator.requestDeleteSelectedLibraryItems()

        XCTAssertNil(destination.libraryDeletionConfirmation)
        XCTAssertTrue(destination.status.isEmpty)
    }

    private func waitUntil(
        _ description: String, condition: @escaping @MainActor () async -> Bool
    ) async throws {
        for _ in 0..<200 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Timed out waiting for \(description)")
    }
}

private extension Duration {
    var seconds: Double {
        Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}

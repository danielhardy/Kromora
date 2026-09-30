import Foundation
import XCTest

@testable import KromoraKit

@MainActor
final class LibraryBrowsingCoordinatorTests: XCTestCase {
    private var collections: [ImageCollection] = []

    override func tearDown() async throws {
        for collection in collections { await collection.shutdown() }
        collections.removeAll()
        try await super.tearDown()
    }

    private final class FakeLibrary: LibraryBrowsingProviding {
        let assets: [PhotoAsset]
        let pageSize: Int
        var indexedAssetCount: Int
        private(set) var selectedIDs = Set<PortablePhotoAssetID>()
        private(set) var activeID: PortablePhotoAssetID?
        private(set) var requestedPages: [Int] = []
        private(set) var persistedStates: [(PortablePhotoAssetID, Int, PhotoFlag)] = []

        init(count: Int, pageSize: Int) {
            self.pageSize = pageSize
            self.indexedAssetCount = count
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
                    data: Data([UInt8(index)]),
                    id: PhotoAssetID(rawValue: "portable:\(id.raw)"),
                    portableIdentity: identity
                )
                return PhotoAsset(
                    source: source, filename: "photo-\(index).jpg", fileType: "jpg"
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

        func browsingWindow(pageIndex: Int, query: LibraryQuery) throws
            -> (assets: [PhotoAsset], totalCount: Int, pageSize: Int) {
            requestedPages.append(pageIndex)
            let start = pageIndex * pageSize
            let end = min(start + pageSize, assets.count)
            return (start < assets.count ? Array(assets[start..<end]) : [], assets.count, pageSize)
        }

        func page(at pageIndex: Int, query: LibraryQuery) -> LibraryQueryPage {
            let start = pageIndex * pageSize
            let selected = start < assets.count ? Array(assets[start..<min(start + pageSize, assets.count)]) : []
            let items = selected.map { asset in
                let id = asset.source.portableIdentity.assetID
                return LibraryQueryItem(
                    assetID: id, recordPath: "unused",
                    summary: PortablePackageAssetSummary(displayName: asset.displayName),
                    isSelected: selectedIDs.contains(id)
                )
            }
            return LibraryQueryPage(
                pageIndex: pageIndex, pageSize: pageSize, totalCount: assets.count, items: items
            )
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

        func togglePortableSelection(_ assetID: PortablePhotoAssetID) {
            if !selectedIDs.insert(assetID).inserted { selectedIDs.remove(assetID) }
            activeID = selectedIDs.contains(assetID) ? assetID : selectedIDs.first
        }

        func resolveEmbeddedSourceURL(for assetID: PortablePhotoAssetID) throws -> URL {
            URL(fileURLWithPath: "/virtual/\(assetID.raw).jpg")
        }

        func updateLibraryState(for assetID: PortablePhotoAssetID, rating: Int, flag: PhotoFlag) throws {
            persistedStates.append((assetID, rating, flag))
        }
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

    func testFilterSortAndSearchReloadPageZeroAndSkipNoOp() throws {
        let (coordinator, _, library, destination) = makeCoordinator()
        try coordinator.reloadPortableWindow()
        coordinator.setPortableFilter(LibraryFilter(flag: .picks))
        coordinator.setPortableFilter(LibraryFilter(flag: .picks))
        coordinator.setPortableSort(LibraryQuerySort(key: .rating, direction: .descending))
        coordinator.setPortableSearch("  photo  ")
        coordinator.setPortableSearch("photo")

        XCTAssertEqual(library.requestedPages, [0, 0, 0, 0])
        XCTAssertEqual(destination.portableQuery.searchText, "photo")
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

    func testOffWindowOpenFaultsItsPageAndMissingAssetDoesNotOpen() throws {
        let (coordinator, collection, library, destination) = makeCoordinator()
        try coordinator.reloadPortableWindow()
        let offWindowID = library.assets[3].source.portableIdentity.assetID

        coordinator.openPortableAsset(offWindowID)

        XCTAssertEqual(collection.portablePageIndex, 1)
        XCTAssertEqual(destination.opened.count, 1)
        XCTAssertEqual(destination.opened.first?.1, library.assets[3].id)
        coordinator.openPortableAsset(PortablePhotoAssetID())
        XCTAssertEqual(destination.opened.count, 1)
        XCTAssertEqual(destination.status.last, "The imported photo is not available in the package index.")
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

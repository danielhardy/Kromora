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
        private(set) var selectedIDs = Set<PortablePhotoAssetID>()
        private(set) var activeID: PortablePhotoAssetID?
        private(set) var requestedPages: [Int] = []
        private(set) var persistedStates: [(PortablePhotoAssetID, Int, PhotoFlag)] = []

        init(count: Int, pageSize: Int) {
            self.pageSize = pageSize
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
        var portableSelectedIDs: Set<PortablePhotoAssetID> { selectedIDs }
        var portableActiveID: PortablePhotoAssetID? { activeID }

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
}

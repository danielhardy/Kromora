import Foundation

/// The query and package operations needed by the bounded Library window. Keeping this seam
/// separate lets browsing behavior be tested without opening a package or constructing the app.
@MainActor
protocol LibraryBrowsingProviding: AnyObject {
    var queryPageSize: Int { get }
    var portableSelectedIDs: Set<PortablePhotoAssetID> { get }
    var portableActiveID: PortablePhotoAssetID? { get }
    func browsingWindow(pageIndex: Int, query: LibraryQuery) throws
        -> (assets: [PhotoAsset], totalCount: Int, pageSize: Int)
    func page(at pageIndex: Int, query: LibraryQuery) -> LibraryQueryPage
    func select(_ assetID: PortablePhotoAssetID, additive: Bool)
    func setPortableSelection(_ assetIDs: [PortablePhotoAssetID], activeID: PortablePhotoAssetID?)
    func togglePortableSelection(_ assetID: PortablePhotoAssetID)
    func resolveEmbeddedSourceURL(for assetID: PortablePhotoAssetID) throws -> URL
    func updateLibraryState(for assetID: PortablePhotoAssetID, rating: Int, flag: PhotoFlag) throws
}

extension PortableLibrarySession: LibraryBrowsingProviding {
    var queryPageSize: Int { queryController.pageSize }
}

@MainActor
protocol LibraryBrowsingDestination: AnyObject {
    var portableQuery: LibraryQuery { get set }
    var libraryDeletionConfirmation: LibraryDeletionConfirmation? { get set }
    var isLibraryGridShowing: Bool { get }
    func showLibraryGridIfActive()
    func openPortableLibraryAsset(url: URL, assetID: PhotoAssetID)
    func selectCollectionImage(at index: Int)
    func setLibraryStatusMessage(_ message: String)
    func presentLibraryError(_ message: String)
    func deleteLibraryItems(_ candidates: [ImageCollection.DeletionCandidate]) async
        -> LibraryDeletionResult
}

/// Owns the sequencing between the query authority and its bounded `ImageCollection` window.
/// The destination remains responsible for opening sources and cross-feature deletion cleanup.
@MainActor
final class LibraryBrowsingCoordinator {
    private let collection: ImageCollection
    private let library: (any LibraryBrowsingProviding)?
    weak var destination: (any LibraryBrowsingDestination)?

    init(
        collection: ImageCollection,
        library: (any LibraryBrowsingProviding)?,
        destination: (any LibraryBrowsingDestination)? = nil
    ) {
        self.collection = collection
        self.library = library
        self.destination = destination
    }

    func reloadPortableCollection() throws { try reloadPortableWindow(pageIndex: 0) }

    func reloadPortableWindow(pageIndex: Int = 0) throws {
        guard let library, let destination else { return }
        let query = destination.portableQuery
        let window = try library.browsingWindow(pageIndex: pageIndex, query: query)
        collection.loadPortableWindow(
            assets: window.assets, totalCount: window.totalCount,
            pageIndex: pageIndex, pageSize: window.pageSize, query: query
        )
        syncPortableSelection()
        destination.showLibraryGridIfActive()
        collection.beginThumbnailDemand()
    }

    func loadMorePortableIfNeeded(currentIndex: Int) {
        guard let library, let destination, collection.isPortableWindowed,
              collection.portableHasMorePages else { return }
        let loaded = collection.items.count
        guard currentIndex >= loaded - collection.portablePageSize else { return }
        let nextPage = collection.portablePageIndex + 1
        guard let window = try? library.browsingWindow(
            pageIndex: nextPage, query: destination.portableQuery
        ) else { return }
        collection.appendPortableWindow(assets: window.assets, pageIndex: nextPage)
    }

    func setPortableFilter(_ filter: LibraryFilter) {
        guard let destination, destination.portableQuery.filter != filter else { return }
        destination.portableQuery.filter = filter
        try? reloadPortableWindow(pageIndex: 0)
    }

    func setPortableSort(_ sort: LibraryQuerySort) {
        guard let destination, destination.portableQuery.sort != sort else { return }
        destination.portableQuery.sort = sort
        try? reloadPortableWindow(pageIndex: 0)
    }

    func setPortableSearch(_ text: String?) {
        guard let destination else { return }
        let normalized = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        let next = (normalized?.isEmpty == false) ? normalized : nil
        guard destination.portableQuery.searchText != next else { return }
        destination.portableQuery.searchText = next
        try? reloadPortableWindow(pageIndex: 0)
    }

    func selectPortableItem(at index: Int, modifiers: LibrarySelectionModel.Modifiers = []) {
        guard let library, collection.items.indices.contains(index) else { return }
        let photoID = collection.items[index].id
        guard let portableID = Self.portableID(for: photoID) else { return }
        if modifiers.contains(.shift) {
            collection.select(at: index, modifiers: modifiers)
            let selectedIDs = collection.selectedItems.compactMap { Self.portableID(for: $0.id) }
            let activeID = collection.selectedItem.flatMap { Self.portableID(for: $0.id) }
            library.setPortableSelection(selectedIDs, activeID: activeID)
        } else if modifiers.contains(.command) {
            library.togglePortableSelection(portableID)
            collection.select(at: index, modifiers: modifiers)
        } else {
            library.select(portableID, additive: false)
            collection.select(at: index, modifiers: modifiers)
        }
        syncPortableSelection()
    }

    func selectNextPortableInGrid() {
        if collection.portableHasMorePages, collection.selectedIndex >= collection.items.count - 1 {
            loadMorePortableIfNeeded(currentIndex: collection.items.count - 1)
        }
        let target = min(collection.selectedIndex + 1, collection.items.count - 1)
        guard collection.items.indices.contains(target), target != collection.selectedIndex else { return }
        selectPortableItem(at: target)
    }

    func selectPreviousPortableInGrid() {
        let target = max(collection.selectedIndex - 1, 0)
        guard collection.items.indices.contains(target), target != collection.selectedIndex else { return }
        selectPortableItem(at: target)
    }

    func selectLibraryItem(at index: Int, modifiers: LibrarySelectionModel.Modifiers = []) {
        collection.select(at: index, modifiers: modifiers)
    }

    func openPortableAsset(_ assetID: PortablePhotoAssetID) {
        guard let destination else { return }
        guard let library else {
            destination.setLibraryStatusMessage("The library package is not open.")
            return
        }
        library.select(assetID, additive: false)
        if let item = collection.items.first(where: {
            $0.asset.source.portableIdentity.assetID == assetID
        }) {
            if let url = try? library.resolveEmbeddedSourceURL(for: assetID) {
                destination.openPortableLibraryAsset(url: url, assetID: item.id)
            } else if let url = item.url {
                destination.openPortableLibraryAsset(url: url, assetID: item.id)
            } else {
                destination.setLibraryStatusMessage(
                    "The imported photo is not available in the package index."
                )
            }
            return
        }

        let query = destination.portableQuery
        let pageSize = library.queryPageSize
        var pageIndex = 0
        while true {
            let page = library.page(at: pageIndex, query: query)
            if page.items.contains(where: { $0.assetID == assetID }) {
                if let window = try? library.browsingWindow(pageIndex: pageIndex, query: query) {
                    collection.loadPortableWindow(
                        assets: window.assets, totalCount: window.totalCount,
                        pageIndex: pageIndex, pageSize: window.pageSize, query: query
                    )
                    syncPortableSelection()
                    if let item = collection.items.first(where: {
                        $0.asset.source.portableIdentity.assetID == assetID
                    }), let url = try? library.resolveEmbeddedSourceURL(for: assetID) {
                        destination.openPortableLibraryAsset(url: url, assetID: item.id)
                        return
                    }
                }
                break
            }
            guard page.hasNextPage else { break }
            pageIndex += 1
            if pageIndex * pageSize > 200_000 { break }
        }
        destination.setLibraryStatusMessage("The imported photo is not available in the package index.")
    }

    func requestDeleteSelectedLibraryItems() {
        guard let destination, destination.isLibraryGridShowing else { return }
        let candidates = collection.deletionCandidates
        guard !candidates.isEmpty else {
            destination.setLibraryStatusMessage("Select at least one photo to remove")
            return
        }
        destination.libraryDeletionConfirmation = LibraryDeletionConfirmation(candidates: candidates)
    }

    func confirmDeleteSelectedLibraryItems() {
        guard let destination, let confirmation = destination.libraryDeletionConfirmation else {
            return
        }
        destination.libraryDeletionConfirmation = nil
        Task { @MainActor [weak destination] in
            _ = await destination?.deleteLibraryItems(confirmation.candidates)
        }
    }

    func syncPortableSelection() {
        guard let library else { return }
        collection.syncPortableSelection(
            selectedIDs: library.portableSelectedIDs, activeID: library.portableActiveID
        )
    }

    @discardableResult
    func setFocusedFlag(_ flag: PhotoFlag, advance: Bool = false) -> Bool {
        let name = collection.selectedItem?.displayName
        let previousIndex = collection.selectedIndex
        let changed = collection.setFlag(flag, advance: advance)
        if changed { persistPortableLibraryStateIfNeeded() }
        if changed, let name {
            destination?.setLibraryStatusMessage(
                "\(name): \(flag == .pick ? "Picked" : flag == .reject ? "Rejected" : "Flag cleared")"
            )
        }
        if advance, destination?.isLibraryGridShowing == false,
           collection.selectedIndex != previousIndex {
            destination?.selectCollectionImage(at: collection.selectedIndex)
        }
        return changed
    }

    @discardableResult
    func setFocusedRating(_ rating: Int) -> Bool {
        let changed = collection.setRating(rating)
        if changed { persistPortableLibraryStateIfNeeded() }
        if changed, let item = collection.selectedItem {
            destination?.setLibraryStatusMessage(
                "\(item.displayName): \(rating == 0 ? "Rating cleared" : "Rated \(rating) stars")"
            )
        }
        return changed
    }

    @discardableResult
    func undoCullingChange() -> Bool {
        let changed = collection.undoLastCullingChange()
        if changed { persistPortableLibraryStateIfNeeded() }
        return changed
    }

    private func persistPortableLibraryStateIfNeeded() {
        guard let library, let assetID = collection.lastCullingAssetID,
            let item = collection.items.first(where: { $0.id == assetID })
        else { return }
        do {
            try library.updateLibraryState(
                for: item.asset.source.portableIdentity.assetID,
                rating: item.asset.rating, flag: item.asset.flag
            )
        } catch {
            destination?.presentLibraryError(
                "Kromora could not update the library catalog: \(error.localizedDescription)"
            )
        }
    }

    private static func portableID(for photoID: PhotoAssetID) -> PortablePhotoAssetID? {
        let prefix = "portable:"
        guard photoID.raw.hasPrefix(prefix),
            let uuid = UUID(uuidString: String(photoID.raw.dropFirst(prefix.count)))
        else { return nil }
        return PortablePhotoAssetID(uuid: uuid)
    }
}

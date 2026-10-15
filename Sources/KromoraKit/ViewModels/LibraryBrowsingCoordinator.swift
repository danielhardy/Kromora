import Foundation

/// The query and package operations needed by the bounded Library window. Keeping this seam
/// separate lets browsing behavior be tested without opening a package or constructing the app.
@MainActor
protocol LibraryBrowsingProviding: AnyObject {
    var queryPageSize: Int { get }
    var assetCount: Int { get }
    var portableSelectedIDs: Set<PortablePhotoAssetID> { get }
    var portableActiveID: PortablePhotoAssetID? { get }
    var libraryID: UUID { get }
    func launchHintAssets(for ids: [PortablePhotoAssetID]) -> [PhotoAsset]
    func browsingWindow(pageIndex: Int, query: LibraryQuery) throws
        -> (assets: [PhotoAsset], totalCount: Int, pageSize: Int)
    func page(at pageIndex: Int, query: LibraryQuery) -> LibraryQueryPage
    func facetCounts(query: LibraryQuery) async -> LibraryFacetCounts
    func browsingAssets(for items: [LibraryQueryItem]) throws -> [PhotoAsset]
    func browsingAssets(forIDs ids: [PortablePhotoAssetID]) throws -> [PhotoAsset]
    func select(_ assetID: PortablePhotoAssetID, additive: Bool)
    func setPortableSelection(_ assetIDs: [PortablePhotoAssetID], activeID: PortablePhotoAssetID?)
    /// Select every id matching `query`, loaded or not.
    func selectAllPortable(query: LibraryQuery)
    /// Narrow the selection to the ids `query` still matches.
    func restrictPortableSelection(to query: LibraryQuery)
    func togglePortableSelection(_ assetID: PortablePhotoAssetID)
    func resolveEmbeddedSourceURL(for assetID: PortablePhotoAssetID) throws -> URL
    func materializedAsset(for assetID: PortablePhotoAssetID) async throws -> PhotoAsset
    func updateLibraryState(for assetID: PortablePhotoAssetID, rating: Int, flag: PhotoFlag) throws
    /// Queue culling changes for a coalesced, serial, off-main write.
    func enqueueLibraryStateUpdates(
        _ updates: [PortableLibrarySession.LibraryStateUpdate],
        onFailure: @escaping @MainActor (Error) -> Void
    )
    /// The newest queued, in-flight, or still-dirty culling state for an asset, if any.
    func newestLibraryState(for assetID: PortablePhotoAssetID)
        -> PortableLibrarySession.LibraryStateUpdate?
    /// Rebuild the disposable index from package membership (the package is canonical).
    func rebuildIndex() throws
}

extension LibraryBrowsingProviding {
    /// Ids per index lookup when a bulk action resolves the metadata of an authoritative selection.
    static var bulkSelectionChunkSize: Int { 500 }

    /// Resolve `ids` to browsing assets one bounded chunk at a time, so a library-wide selection
    /// never materializes every asset in one call. Nothing is read or decoded from an original.
    /// When a chunk fails, its ids are retried one at a time so a single bad projection cannot
    /// hide the rest. Returns the ids that still could not be resolved; callers must report them.
    func forEachBrowsingAssetChunk(
        forIDs ids: [PortablePhotoAssetID], _ body: ([PhotoAsset]) -> Void
    ) -> [PortablePhotoAssetID] {
        let size = Self.bulkSelectionChunkSize
        var unresolved: [PortablePhotoAssetID] = []
        for start in stride(from: 0, to: ids.count, by: size) {
            let chunk = Array(ids[start..<min(ids.count, start + size)])
            if let assets = try? browsingAssets(forIDs: chunk) {
                body(assets)
                continue
            }
            var recovered: [PhotoAsset] = []
            for id in chunk {
                if let assets = try? browsingAssets(forIDs: [id]) {
                    recovered += assets
                } else {
                    unresolved.append(id)
                }
            }
            body(recovered)
        }
        return unresolved
    }
}

extension PortableLibrarySession: LibraryBrowsingProviding {
    var queryPageSize: Int { queryController.pageSize }
    func rebuildIndex() throws { _ = try refreshIndex() }
}

protocol LaunchHintFrameReading: Sendable {
    func readFrames(for identity: PortablePhotoIdentity) async -> ThumbnailFrameStore.StoredFrames
}

extension ThumbnailFrameStore: LaunchHintFrameReading {}

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
    private var library: (any LibraryBrowsingProviding)?
    private let scheduler: ImageWorkScheduler?
    private let frameStore: (any LaunchHintFrameReading)?
    private let hintsStore: LaunchHintsStore?
    weak var destination: (any LibraryBrowsingDestination)?
    private var launchHints: LaunchHints?
    private var hintsLoadStarted = false
    private var hintIDsAdmitted = false
    private var hintedAssets: [PortablePhotoAssetID: PhotoAsset] = [:]
    private var hintQueue: [PortablePhotoAssetID] = []
    private var hintJobs: [PortablePhotoAssetID: ImageWorkScheduler.JobID] = [:]
    private var completedHintFrames: [PhotoAssetID: (PortablePhotoIdentity, ThumbnailFrameStore.StoredFrames)] = [:]
    private var latestVisibleIDs: [PhotoAssetID] = []
    private var pendingLaunchHintsWrite: LaunchHints?
    private var launchHintsWriteTask: Task<Void, Never>?
    private var launchStartedAt = ContinuousClock.now
    private var metrics = LaunchHydrationMetrics()
    private var launchReadSuperseded = false
    private var hasPublishedVisibleIDs = false

    private(set) var hasPublishedFirstIndexPage = false
    private(set) var hasPublishedVisibleWindow = false
    var onViewportPublished: (@MainActor @Sendable ([PhotoAssetID]) -> Void)?

    var launchHintRecencyOrder: [PortablePhotoAssetID] {
        guard let launchHints else { return [] }
        var seen = Set<PortablePhotoAssetID>()
        return ([launchHints.activeAssetID].compactMap { $0 } + launchHints.visibleAssetIDs)
            .filter { seen.insert($0).inserted }
    }

    var launchHydrationMetrics: LaunchHydrationMetrics { metrics }

    init(
        collection: ImageCollection,
        library: (any LibraryBrowsingProviding)?,
        destination: (any LibraryBrowsingDestination)? = nil,
        scheduler: ImageWorkScheduler? = nil,
        frameStore: (any LaunchHintFrameReading)? = nil,
        hintsStore: LaunchHintsStore? = nil
    ) {
        self.collection = collection
        self.library = library
        self.destination = destination
        self.scheduler = scheduler
        self.frameStore = frameStore
        self.hintsStore = hintsStore
        collection.onVisibleIDsPublished = { [weak self] ids in self?.visibleIDsPublished(ids) }
    }

    func reloadPortableCollection() throws { try reloadPortableWindow(pageIndex: 0) }

    /// Rebuild the disposable index from package membership, then republish the first page. This
    /// is the recovery path for an index that disagrees with the package.
    func rebuildPortableIndex() throws {
        try library?.rebuildIndex()
        try reloadPortableWindow(pageIndex: 0)
    }

    /// Propagate a package ratio-only repair into retained cells without rebuilding their assets
    /// or admitting any new thumbnail work.
    func applyPresentedAspectRatioUpdates(_ updates: [PortablePhotoAssetID: Double]) {
        collection.applyPresentedAspectRatioUpdates(updates)
    }

    func reloadPortableWindow(pageIndex: Int = 0) throws {
        guard let library, let destination else { return }
        let query = destination.portableQuery
        let window = try library.browsingWindow(pageIndex: pageIndex, query: query)
        if pageIndex == 0, metrics.timeToFirstIndexPageMilliseconds == nil {
            hasPublishedFirstIndexPage = true
            metrics.timeToFirstIndexPageMilliseconds = elapsedMilliseconds
            KromoraObservability.event(.launchFirstIndexPage,
                detail: "first_index_ms=\(metrics.timeToFirstIndexPageMilliseconds ?? 0)")
        }
        collection.loadPortableWindow(
            assets: window.assets, totalCount: window.totalCount,
            pageIndex: pageIndex, pageSize: window.pageSize, query: query
        )
        syncPortableSelection()
        destination.showLibraryGridIfActive()
        collection.beginThumbnailDemand()
        if pageIndex == 0 { admitHintsAgainstPublishedIndex() }
    }

    /// Fold assets committed by a running import into the loaded window. Unlike
    /// `reloadPortableWindow`, this keeps every loaded page, the existing cells and their
    /// thumbnails, the selection, and the scroll position: only new cells are created.
    func mergeCommittedImports() throws {
        guard let library, let destination else { return }
        guard collection.isPortableWindowed else {
            try reloadPortableWindow(pageIndex: 0)
            return
        }
        let query = destination.portableQuery
        var ordered: [LibraryQueryItem] = []
        var totalCount = collection.portableTotalCount ?? 0
        for pageIndex in 0...collection.portablePageIndex {
            let page = library.page(at: pageIndex, query: query)
            ordered.append(contentsOf: page.items)
            totalCount = page.totalCount
        }
        let orderedIDs = ordered.map { PhotoAssetID(rawValue: "portable:\($0.assetID.raw)") }
        let known = Set(collection.items.map(\.id))
        let fresh = zip(ordered, orderedIDs).filter { !known.contains($0.1) }.map(\.0)
        let assets = try library.browsingAssets(for: fresh)
        collection.mergePortableWindow(
            orderedIDs: orderedIDs, newAssets: assets, totalCount: totalCount
        )
        syncPortableSelection()
        destination.showLibraryGridIfActive()
    }

    /// Supplies the opened library to a coordinator composed before the package was open.
    func bind(library: any LibraryBrowsingProviding) { self.library = library }

    func prepareLaunchHints() { loadLaunchHints() }

    private func loadLaunchHints() {
        guard let library, let hintsStore, !hintsLoadStarted, !launchReadSuperseded else { return }
        hintsLoadStarted = true
        let libraryID = library.libraryID
        Task { [weak self] in
            let result = await hintsStore.load(for: libraryID)
            guard let self, !self.launchReadSuperseded else { return }
            switch result {
            case .missing:
                self.metrics.validation = "missing"
                KromoraObservability.event(.launchHintsValidation, detail: "missing")
            case .invalid:
                self.metrics.validation = "invalid-or-wrong-library"
                KromoraObservability.event(.launchHintsValidation, detail: "invalid")
            case .valid(let hints):
                self.metrics.validation = "valid"
                self.launchHints = hints
                KromoraObservability.event(.launchHintsValidation, detail: "valid count=\(hints.visibleAssetIDs.count)")
                self.admitHintsAgainstPublishedIndex()
            }
        }
    }

    private func admitHintsAgainstPublishedIndex() {
        guard !hintIDsAdmitted, !launchReadSuperseded, let library, let hints = launchHints,
              library.assetCount > 0 else { return }
        hintIDsAdmitted = true
        let assets = library.launchHintAssets(
            for: Array(hints.visibleAssetIDs.prefix(LaunchHintReadPolicy.maximumHintedIDs))
        )
        hintedAssets = Dictionary(assets.map { asset in
            (PortablePhotoAssetID.compatibility(from: asset.id), asset)
        }, uniquingKeysWith: { first, _ in first })
        hintQueue = assets.map { PortablePhotoAssetID.compatibility(from: $0.id) }
        admitNextHintReads()
    }

    private func admitNextHintReads() {
        guard !launchReadSuperseded, let scheduler, let frameStore else { return }
        while hintJobs.count < LaunchHintReadPolicy.maxConcurrentReads, !hintQueue.isEmpty {
            let id = hintQueue.removeFirst()
            guard let asset = hintedAssets[id] else { continue }
            let jobID = ImageWorkScheduler.JobID("launch-frame-read:\(id.raw)")
            let identity = asset.source.portableIdentity
            hintJobs[id] = jobID
            _ = scheduler.enqueueFrameRead(
                id: jobID, priority: .background,
                onTerminal: { [weak self] outcome in
                    guard let self else { return }
                    self.hintJobs.removeValue(forKey: id)
                    if outcome == .completed, !self.launchReadSuperseded { self.admitNextHintReads() }
                },
                operation: { [weak self] in
                    let frames = await frameStore.readFrames(for: identity)
                    guard !Task.isCancelled else { return }
                    await MainActor.run {
                        guard let self, !self.launchReadSuperseded else { return }
                        self.metrics.readCount += 1
                        let frameBytes = UInt64((frames.edited?.frame.rasterData.count ?? 0)
                            + (frames.original?.frame.rasterData.count ?? 0))
                        self.metrics.bytesRead += frameBytes
                        if frames.edited != nil || frames.original != nil { self.metrics.usefulHits += 1 }
                        self.completedHintFrames[PhotoAssetID(rawValue: "portable:\(id.raw)")] = (identity, frames)
                    }
                }
            )
        }
    }

    private func visibleIDsPublished(_ ids: [PhotoAssetID]) {
        guard library != nil else { return }
        latestVisibleIDs = ids
        hasPublishedVisibleWindow = true
        onViewportPublished?(ids)
        guard !hasPublishedVisibleIDs else {
            scheduleLaunchHintsIfVisible()
            return
        }
        hasPublishedVisibleIDs = true
        // The viewport is canonical. Flush only already completed matching hints into the
        // collection, then cancel queued/running speculative reads before admitting normal work.
        launchReadSuperseded = true
        for jobID in hintJobs.values { scheduler?.cancel(id: jobID) }
        metrics.superseded += hintQueue.count + hintJobs.count
        hintJobs.removeAll()
        hintQueue.removeAll()
        let visible = Set(ids)
        let useful = completedHintFrames.filter { visible.contains($0.key) }
        collection.applyLaunchFrames(useful)
        completedHintFrames.removeAll()
        metrics.timeToVisibleWindowMilliseconds = elapsedMilliseconds
        KromoraObservability.event(.launchHintsSuperseded,
            detail: "superseded=\(metrics.superseded) useful=\(useful.count) bytes=\(metrics.bytesRead) reads=\(metrics.readCount)")
        KromoraObservability.event(.launchHydrationComplete,
            detail: "validation=\(metrics.validation) useful=\(metrics.usefulHits) superseded=\(metrics.superseded) bytes=\(metrics.bytesRead) reads=\(metrics.readCount) visible_ms=\(metrics.timeToVisibleWindowMilliseconds ?? 0) first_index_ms=\(metrics.timeToFirstIndexPageMilliseconds ?? 0)")
        scheduleLaunchHintsIfVisible()
    }

    private func scheduleLaunchHintsIfVisible() {
        guard !latestVisibleIDs.isEmpty, let library else { return }
        let hints = LaunchHints(
            libraryID: library.libraryID, activeAssetID: library.portableActiveID,
            visibleAssetIDs: latestVisibleIDs.compactMap(Self.portableID(for:))
        )
        pendingLaunchHintsWrite = hints
        guard launchHintsWriteTask == nil else { return }
        launchHintsWriteTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled, let self else { return }
            let latest = self.pendingLaunchHintsWrite
            self.pendingLaunchHintsWrite = nil
            if let latest { await self.hintsStoreWrite(latest) }
            self.launchHintsWriteTask = nil
        }
    }

    private var elapsedMilliseconds: Double {
        let elapsed = launchStartedAt.duration(to: .now).components
        return Double(elapsed.seconds) * 1_000
            + Double(elapsed.attoseconds) / 1_000_000_000_000_000
    }

    private func hintsStoreWrite(_ hints: LaunchHints) async {
        await hintsStore?.scheduleWrite(hints)
    }

    func shutdown() async {
        launchHintsWriteTask?.cancel()
        if let launchHintsWriteTask { await launchHintsWriteTask.value }
        launchHintsWriteTask = nil
        if let pendingLaunchHintsWrite { await hintsStoreWrite(pendingLaunchHintsWrite) }
        pendingLaunchHintsWrite = nil
        await hintsStore?.shutdown()
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
        library?.restrictPortableSelection(to: destination.portableQuery)
        try? reloadPortableWindow(pageIndex: 0)
    }

    func setPortableFacets(_ facets: LibraryFacetSelection) {
        guard let destination, destination.portableQuery.facets != facets else { return }
        destination.portableQuery.facets = facets
        library?.restrictPortableSelection(to: destination.portableQuery)
        try? reloadPortableWindow(pageIndex: 0)
    }

    func clearPortableFilters() {
        guard let destination, destination.portableQuery.hasActiveFilters else { return }
        destination.portableQuery = destination.portableQuery.clearingFilters()
        library?.restrictPortableSelection(to: destination.portableQuery)
        try? reloadPortableWindow(pageIndex: 0)
    }

    func portableFacetCounts() async -> LibraryFacetCounts? {
        guard let library, let destination else { return nil }
        return await library.facetCounts(query: destination.portableQuery)
    }

    func setPortableSort(_ sort: LibraryQuerySort) {
        guard let destination, destination.portableQuery.sort != sort else { return }
        destination.portableQuery.sort = sort
        library?.restrictPortableSelection(to: destination.portableQuery)
        try? reloadPortableWindow(pageIndex: 0)
    }

    func setPortableSearch(_ text: String?) {
        guard let destination else { return }
        let normalized = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        let next = (normalized?.isEmpty == false) ? normalized : nil
        guard destination.portableQuery.searchText != next else { return }
        destination.portableQuery.searchText = next
        library?.restrictPortableSelection(to: destination.portableQuery)
        try? reloadPortableWindow(pageIndex: 0)
    }

    /// The Select All command. A package-backed library selects every id the current query
    /// matches, whether or not its row is loaded, then mirrors that into the visible rows.
    func selectAllInGrid() {
        // No package authority (a collection without a bound library) keeps the loaded-item
        // Select All.
        guard let library, let destination, collection.isPortableWindowed else {
            collection.selectAll()
            return
        }
        library.selectAllPortable(query: destination.portableQuery)
        syncPortableSelection()
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
            let clock = ContinuousClock()
            let start = clock.now
            library.select(portableID, additive: false)
            let afterLibrary = clock.now
            collection.select(at: index, modifiers: modifiers)
            let afterCollection = clock.now
            syncPortableSelection()
            let afterSync = clock.now
            KromoraObservability.photoSwitchPhase(
                "selectPortableItem.steps", since: nil,
                detail: "librarySelectMs=\(Self.milliseconds(afterLibrary - start)) "
                    + "collectionSelectMs=\(Self.milliseconds(afterCollection - afterLibrary)) "
                    + "syncSelectionMs=\(Self.milliseconds(afterSync - afterCollection))"
            )
            return
        }
        syncPortableSelection()
    }

    private static func milliseconds(_ duration: Duration) -> Int {
        let parts = duration.components
        return Int(parts.seconds * 1000 + parts.attoseconds / 1_000_000_000_000_000)
    }

    func selectNextPortableInGrid() {
        selectPortableInGrid(rowDelta: 0, columnDelta: 1)
    }

    func selectPreviousPortableInGrid() {
        selectPortableInGrid(rowDelta: 0, columnDelta: -1)
    }

    func selectPortableRowBelowInGrid() {
        selectPortableInGrid(rowDelta: 1, columnDelta: 0)
    }

    func selectPortableRowAboveInGrid() {
        selectPortableInGrid(rowDelta: -1, columnDelta: 0)
    }

    /// Moves the grid selection by whole rows (`collection.libraryGridColumns` items) or single
    /// items. A downward step that would land past the tail faults in the next page first; if the
    /// target row is still short, it lands on the last item, but only when a later row exists.
    private func selectPortableInGrid(rowDelta: Int, columnDelta: Int) {
        let columns = max(1, collection.libraryGridColumns)
        let current = collection.selectedIndex
        var target = current + rowDelta * columns + columnDelta
        if target > collection.items.count - 1, collection.portableHasMorePages {
            loadMorePortableIfNeeded(currentIndex: collection.items.count - 1)
        }
        let last = collection.items.count - 1
        if rowDelta > 0, target > last, current / columns < last / columns {
            target = last
        }
        guard collection.items.indices.contains(target), target != current else { return }
        selectPortableItem(at: target)
    }

    func selectLibraryItem(at index: Int, modifiers: LibrarySelectionModel.Modifiers = []) {
        collection.select(at: index, modifiers: modifiers)
    }

    func openPortableAsset(_ assetID: PortablePhotoAssetID, allowIndexRebuild: Bool = true) {
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
        // The package committed this asset (the importer returned its id), so a miss means the
        // disposable index is stale. Rebuild it from membership once before reporting failure.
        if allowIndexRebuild, (try? library.rebuildIndex()) != nil {
            try? reloadPortableWindow(pageIndex: 0)
            openPortableAsset(assetID, allowIndexRebuild: false)
            return
        }
        destination.setLibraryStatusMessage("The imported photo is not available in the package index.")
    }

    func requestDeleteSelectedLibraryItems() {
        guard let destination, destination.isLibraryGridShowing else { return }
        let candidates = deletionCandidates()
        guard !candidates.isEmpty else {
            destination.setLibraryStatusMessage("Select at least one photo to remove")
            return
        }
        destination.libraryDeletionConfirmation = LibraryDeletionConfirmation(candidates: candidates)
    }

    /// The deletion targets: loaded selected rows plus package-selected photos outside the loaded
    /// window, resolved from the index in bounded chunks without reading any original.
    func deletionCandidates() -> [ImageCollection.DeletionCandidate] {
        var candidates = collection.deletionCandidates
        let unloadedIDs = collection.unloadedSelectedPortableIDs
        guard let library, !unloadedIDs.isEmpty else { return candidates }
        let unresolved = library.forEachBrowsingAssetChunk(forIDs: unloadedIDs) { assets in
            candidates += assets.map {
                ImageCollection.DeletionCandidate(
                    id: $0.id, displayName: $0.displayName, url: $0.url, sourceKind: .managed,
                    portableIdentity: $0.source.portableIdentity)
            }
        }
        if !unresolved.isEmpty {
            destination?.presentLibraryError(
                LibraryBrowsingCoordinator.unresolvedSelectionMessage(count: unresolved.count, action: "removal"))
        }
        return candidates
    }

    /// User-facing description of selected photos a bulk action could not resolve.
    static func unresolvedSelectionMessage(count: Int, action: String) -> String {
        let photos = count == 1 ? "1 selected photo" : "\(count) selected photos"
        return "Kromora could not read \(photos) from the library index, so \(action) did not include them."
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
        scheduleLaunchHintsIfVisible()
    }

    @discardableResult
    func setFocusedFlag(_ flag: PhotoFlag, advance: Bool = false) -> Bool {
        let unloaded = collection.unloadedSelectedPortableIDs
        let targetCount = collection.cullingTargetIDs.count + unloaded.count
        let name = collection.selectedItem?.displayName
        let previousIndex = collection.selectedIndex
        let loadedChanged = collection.setFlagForSelection(flag, advance: advance)
        let unloadedResult = persistUnloadedLibraryState(
            unloaded, joiningLoadedChange: loadedChanged
        ) { _ in (nil, flag) }
        let changed = loadedChanged || unloadedResult.changed
        if loadedChanged { persistPortableLibraryStateIfNeeded() }
        // A partial result already raised an error; a success message would contradict it.
        if changed, unloadedResult.unresolvedCount == 0 {
            let outcome = flag == .pick ? "Picked" : flag == .reject ? "Rejected" : "Flag cleared"
            if targetCount > 1 {
                destination?.setLibraryStatusMessage("\(targetCount) photos: \(outcome)")
            } else if let name {
                destination?.setLibraryStatusMessage("\(name): \(outcome)")
            }
        }
        if advance, destination?.isLibraryGridShowing == false,
           collection.selectedIndex != previousIndex {
            destination?.selectCollectionImage(at: collection.selectedIndex)
        }
        return changed
    }

    @discardableResult
    func setFocusedRating(_ rating: Int) -> Bool {
        let unloaded = collection.unloadedSelectedPortableIDs
        let targetCount = collection.cullingTargetIDs.count + unloaded.count
        let loadedChanged = collection.setRatingForSelection(rating)
        let clamped = min(max(rating, 0), 5)
        let unloadedResult = persistUnloadedLibraryState(
            unloaded, joiningLoadedChange: loadedChanged
        ) { _ in (clamped, nil) }
        let changed = loadedChanged || unloadedResult.changed
        if loadedChanged { persistPortableLibraryStateIfNeeded() }
        // A partial result already raised an error; a success message would contradict it.
        if changed, unloadedResult.unresolvedCount == 0 {
            let outcome = rating == 0 ? "Rating cleared" : "Rated \(rating) stars"
            if targetCount > 1 {
                destination?.setLibraryStatusMessage("\(targetCount) photos: \(outcome)")
            } else if let item = collection.selectedItem {
                destination?.setLibraryStatusMessage("\(item.displayName): \(outcome)")
            }
        }
        return changed
    }

    @discardableResult
    func undoCullingChange() -> Bool {
        let changed = collection.undoLastCullingChange()
        guard changed else { return false }
        persistPortableLibraryStateIfNeeded()
        restoreUnloadedLibraryState(collection.lastUndoneUnloadedChanges)
        return true
    }

    private func restoreUnloadedLibraryState(_ changes: [ImageCollection.UnloadedCullingChange]) {
        guard let library, !changes.isEmpty else { return }
        let size = type(of: library).bulkSelectionChunkSize
        for start in stride(from: 0, to: changes.count, by: size) {
            let updates = changes[start..<min(changes.count, start + size)].map {
                PortableLibrarySession.LibraryStateUpdate(
                    assetID: $0.assetID, rating: $0.rating, flag: $0.flag
                )
            }
            library.enqueueLibraryStateUpdates(updates) { [weak self] error in
                self?.destination?.presentLibraryError(
                    "Kromora could not update the library catalog: \(error.localizedDescription)"
                )
            }
        }
    }

    /// Apply a culling change to selected photos that have no loaded row. Their current rating and
    /// flag come from the index summary, one bounded chunk at a time; only photos whose value
    /// changes are queued. They go through the same coalesced, off-main write and failure handler
    /// as loaded rows. Their previous state joins the action's undo group.
    private func persistUnloadedLibraryState(
        _ ids: [PortablePhotoAssetID], joiningLoadedChange: Bool, newValue: (PhotoAsset) -> (rating: Int?, flag: PhotoFlag?)
    ) -> (changed: Bool, unresolvedCount: Int) {
        guard let library, !ids.isEmpty else { return (false, 0) }
        var changed = false
        var joining = joiningLoadedChange
        let unresolved = library.forEachBrowsingAssetChunk(forIDs: ids) { assets in
            var undo: [ImageCollection.UnloadedCullingChange] = []
            let updates = assets.compactMap { asset -> PortableLibrarySession.LibraryStateUpdate? in
                let assetID = asset.source.portableIdentity.assetID
                // The index summary lags queued writes; merge with the newest known state.
                let queued = library.newestLibraryState(for: assetID)
                let currentRating = queued?.rating ?? asset.rating
                let currentFlag = queued?.flag ?? asset.flag
                let value = newValue(asset)
                let rating = value.rating ?? currentRating
                let flag = value.flag ?? currentFlag
                guard rating != currentRating || flag != currentFlag else { return nil }
                undo.append(.init(assetID: assetID, rating: currentRating, flag: currentFlag))
                return .init(assetID: assetID, rating: rating, flag: flag)
            }
            guard !updates.isEmpty else { return }
            changed = true
            collection.recordUnloadedCullingChanges(undo, joiningLoadedChange: joining)
            joining = true
            library.enqueueLibraryStateUpdates(updates) { [weak self] error in
                self?.destination?.presentLibraryError(
                    "Kromora could not update the library catalog: \(error.localizedDescription)"
                )
            }
        }
        if !unresolved.isEmpty {
            destination?.presentLibraryError(
                Self.unresolvedSelectionMessage(count: unresolved.count, action: "this change"))
        }
        return (changed, unresolved.count)
    }

    private func persistPortableLibraryStateIfNeeded() {
        guard let library else { return }
        let ids = collection.lastCullingAssetIDs
        guard !ids.isEmpty else { return }
        let wanted = Set(ids)
        var itemsByID: [PhotoAssetID: ImageCollection.Item] = [:]
        for item in collection.items where wanted.contains(item.id) { itemsByID[item.id] = item }
        let updates = ids.compactMap { id -> PortableLibrarySession.LibraryStateUpdate? in
            guard let item = itemsByID[id] else { return nil }
            return .init(
                assetID: item.asset.source.portableIdentity.assetID,
                rating: item.asset.rating, flag: item.asset.flag
            )
        }
        library.enqueueLibraryStateUpdates(updates) { [weak self] error in
            self?.destination?.presentLibraryError(
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

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
    func select(_ assetID: PortablePhotoAssetID, additive: Bool)
    func setPortableSelection(_ assetIDs: [PortablePhotoAssetID], activeID: PortablePhotoAssetID?)
    func togglePortableSelection(_ assetID: PortablePhotoAssetID)
    func resolveEmbeddedSourceURL(for assetID: PortablePhotoAssetID) throws -> URL
    func materializedAsset(for assetID: PortablePhotoAssetID) async throws -> PhotoAsset
    func updateLibraryState(for assetID: PortablePhotoAssetID, rating: Int, flag: PhotoFlag) throws
}

extension PortableLibrarySession: LibraryBrowsingProviding {
    var queryPageSize: Int { queryController.pageSize }
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
    private let library: (any LibraryBrowsingProviding)?
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
        hintedAssets = Dictionary(uniqueKeysWithValues: assets.map { asset in
            (PortablePhotoAssetID.compatibility(from: asset.id), asset)
        })
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
        scheduleLaunchHintsIfVisible()
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

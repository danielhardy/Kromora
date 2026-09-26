import Foundation
import AppKit
import ImageIO
import Observation

/// Package-backed presentation state for the library.
///
/// Durable membership, originals, culling state, and import outcomes belong to
/// `PortableLibrarySession`. This type only owns the bounded window consumed by the
/// existing SwiftUI grid/filmstrip and its thumbnail admission policy.
///
/// Migrated to Observation (KRMA-521): thumbnail arrivals, metadata, and scan ticks publish
/// through this object's own observation boundary. Views observe the collection directly
/// through `@Bindable` instead of through AppViewModel's former objectWillChange fan-in.
@MainActor
@Observable
final class ImageCollectionPresentationModel {
    enum LibrarySourceKind: String, Sendable, Equatable { case managed }

    struct DeletionCandidate: Identifiable, Sendable, Equatable {
        let id: PhotoAssetID
        let displayName: String
        let url: URL?
        let sourceKind: LibrarySourceKind
        var isManaged: Bool { true }
    }

    struct PhotoImportItem: Sendable, Equatable {
        let name: String
        let data: Data
        let localIdentifier: String?
        let contentDigest: String

        init(
            name: String, data: Data, localIdentifier: String? = nil,
            contentDigest: String? = nil, calculateContentDigest: Bool = true
        ) {
            self.name = name
            self.data = data
            self.localIdentifier = localIdentifier
            self.contentDigest = contentDigest
                ?? (calculateContentDigest ? PhotoAssetID.contentDigest(data) : "")
        }
    }

    struct ThumbnailEntry: Identifiable, Equatable {
        let id: PhotoAssetID
        let itemIndex: Int?
        let aspectRatio: Double
        /// False while the entry is still using the 4:3 fallback because pixel dimensions
        /// have not arrived. The mosaic may replace that placeholder; a resolved entry stays put.
        let aspectResolved: Bool
        var isPlaceholder: Bool { false }
    }

    @Observable
    final class Item: Identifiable {
        var asset: PhotoAsset
        var thumbnail: NSImage?
        var metadata: ImageMetadata?
        var subfolder: String
        private var displayNameOverride: String?
        private var originalThumbnail: NSImage?
        private var editedThumbnailUsesFallback = false
        private(set) var editedThumbnailRevision: String?
        private var presentedCrop = CropAdjustments.neutral

        var id: PhotoAssetID { asset.id }
        var url: URL? { asset.url }
        var displayName: String { displayNameOverride ?? asset.displayName }
        var imageData: Data? { asset.source.data }
        var dataFingerprint: String? { asset.source.fingerprint.sampleDigest }
        var thumbnailNativeExtent: CGSize {
            guard let dimensions = asset.dimensions,
                  dimensions.width > 0, dimensions.height > 0 else { return .zero }
            return CGSize(width: dimensions.width, height: dimensions.height)
        }
        var hasResolvedLibraryAspect: Bool {
            guard let dimensions = asset.dimensions else { return false }
            return dimensions.width > 0 && dimensions.height > 0
        }
        var libraryAspectRatio: Double {
            guard hasResolvedLibraryAspect, let dimensions = asset.dimensions else { return 4.0 / 3.0 }
            return LibraryGridLayout.presentedAspectRatio(
                sourceAspectRatio: Double(dimensions.width) / Double(dimensions.height),
                crop: presentedCrop
            )
        }

        init(
            asset: PhotoAsset, thumbnail: NSImage? = nil,
            metadata: ImageMetadata? = nil, subfolder: String = ""
        ) {
            self.asset = asset
            self.thumbnail = thumbnail
            self.originalThumbnail = thumbnail
            self.metadata = metadata
            self.subfolder = subfolder
        }

        convenience init(
            url: URL?, displayName: String, thumbnail: NSImage? = nil,
            imageData: Data?, metadata: ImageMetadata? = nil, subfolder: String = ""
        ) {
            if let url {
                self.init(
                    asset: PhotoAsset(url: url, filename: displayName), thumbnail: thumbnail,
                    metadata: metadata, subfolder: subfolder
                )
            } else if let imageData {
                self.init(
                    asset: PhotoAsset(data: imageData, filename: displayName), thumbnail: thumbnail,
                    metadata: metadata, subfolder: subfolder
                )
            } else {
                preconditionFailure("An image item needs either a URL or image data")
            }
        }

        func setOriginalThumbnail(_ thumbnail: NSImage?) {
            originalThumbnail = thumbnail
            if editedThumbnailRevision == nil || editedThumbnailUsesFallback { self.thumbnail = thumbnail }
        }

        /// Open Image… historically presents selected files without their extensions. Keep that
        /// presentation-only convention separate from the package's durable source filename.
        func setDisplayNameOverride(_ name: String?) {
            displayNameOverride = name
        }

        func invalidateEditedThumbnail() {
            editedThumbnailRevision = nil
            editedThumbnailUsesFallback = false
            thumbnail = originalThumbnail
        }

        func applyEditedThumbnail(_ thumbnail: NSImage?, revision: String) {
            guard editedThumbnailRevision == nil || editedThumbnailRevision != revision else { return }
            editedThumbnailRevision = revision
            editedThumbnailUsesFallback = thumbnail == nil
            self.thumbnail = thumbnail ?? originalThumbnail
        }

        @discardableResult
        func setPresentedCrop(_ crop: CropAdjustments) -> Bool {
            guard presentedCrop != crop else { return false }
            presentedCrop = crop
            return true
        }
    }

    struct ScanWarning: Identifiable, Equatable, Sendable {
        let id: String
        let message: String
    }

    var items: [Item] = []
    var selectedIndex = 0
    private(set) var selection = LibrarySelectionModel()
    var isActive = false
    var isScanning = false
    private(set) var scanWarnings: [ScanWarning] = []
    private(set) var filter = LibraryFilter.all
    private(set) var portableTotalCount: Int?
    private(set) var portablePageIndex = 0
    private(set) var portablePageSize = 500
    private(set) var portableQuery = LibraryQuery.all
    private(set) var cropGeneration = 0

    var onThumbnailDemand: (@MainActor @Sendable (PhotoAssetID, ImageWorkScheduler.Priority) -> Void)?

    private var collectionRevision: UInt64 = 0
    private var filterRevision: UInt64 = 0
    private let projectionCache = CollectionProjection.Cache()
    private struct CullingChange {
        let itemID: PhotoAssetID
        let oldState: PhotoAssetLibraryState
        let activeIDBefore: PhotoAssetID?
    }
    private var cullingUndoStack: [CullingChange] = []
    private(set) var lastCullingAssetID: PhotoAssetID?
    private let scheduler: ImageWorkScheduler
    private var thumbnailJobIDs: Set<ImageWorkScheduler.JobID> = []
    private var thumbnailGeneration: UInt64 = 0
    private var isThumbnailDemandDriven = false
    private var thumbnailDemandIDs: Set<PhotoAssetID> = []
    private var thumbnailDemandPriorities: [PhotoAssetID: ImageWorkScheduler.Priority] = [:]
    private var preparedThumbnailIDs: Set<PhotoAssetID> = []
    /// Photos whose edited thumbnails the visible window asked for. Originals are queued
    /// immediately; edited renders are flushed on the next turn so they cannot occupy a
    /// thumbnail slot before the fast previews.
    private var visibleEditedThumbnailIDs: [PhotoAssetID] = []
    private var visibleEditedDemandScheduled = false
    private var metadataTask: Task<Void, Never>?
    private var metadataContinuation: AsyncStream<MetadataRequest>.Continuation?
    private var nextMetadataRequestID: UInt64 = 0
    private var pendingMetadataRequestIDs: Set<UInt64> = []
    private var metadataCompletionWaiters: [CheckedContinuation<Void, Never>] = []
    /// Dimensions that arrived during the current metadata burst. Published once when the
    /// burst drains so the mosaic corrects itself without rebuilding on every header.
    private var metadataAffectsMosaic = false
    private var scanGeneration: UInt64 = 0

    private struct MetadataRequest: Sendable {
        let id: UInt64
        let itemID: PhotoAssetID
        let generation: UInt64
        let name: String
        let source: ImageSource.Backing
    }
    private enum MetadataOutcome: Sendable {
        case success(ImageMetadata)
        case failure(String)
    }

    init(scheduler: ImageWorkScheduler = ImageWorkScheduler()) { self.scheduler = scheduler }

    // Teardown that needs the main actor belongs in `shutdown()`. `deinit` is nonisolated
    // and must not touch MainActor-isolated state (Swift 6 zero-opt-out policy).

    var selectedItem: Item? {
        guard isActive, let activeID = selection.activeID else { return nil }
        return items.first { $0.id == activeID }
    }
    var scanToken: UInt64 { scanGeneration }
    var selectedIndices: [Int] { CollectionProjection.selectedIndices(items: items, selection: selection) }
    var selectedItems: [Item] { selectedIndices.map { items[$0] } }

    var deletionCandidates: [DeletionCandidate] {
        let ids = selection.selectedIDs.isEmpty
            ? (selection.activeID.map { Set([$0]) } ?? []) : selection.selectedIDs
        // An empty selection must not walk `items`. Each item's id/name reads its observable
        // asset, and a view that only needed `.isEmpty` would subscribe to every photo and
        // keep the library update from finishing.
        guard !ids.isEmpty else { return [] }
        return items.filter { ids.contains($0.id) }.map {
            DeletionCandidate(id: $0.id, displayName: $0.displayName, url: $0.url, sourceKind: .managed)
        }
    }

    func sourceKind(for item: Item) -> LibrarySourceKind { .managed }
    var filteredItems: [Item] { collectionProjection.filteredIndices.map { items[$0] } }
    var filteredIndices: [Int] { collectionProjection.filteredIndices }
    var filteredItemCount: Int { filteredIndices.count }
    var projectionRebuildCount: Int { projectionCache.rebuildCount }

    func setFilter(_ filter: LibraryFilter) {
        guard self.filter != filter else { return }
        self.filter = filter
        filterRevision &+= 1
        reconcileFilteredSelection()
    }
    func clearFilter() { setFilter(.all) }

    @discardableResult
    func setFlag(
        _ flag: PhotoFlag, for id: PhotoAssetID? = nil, advance shouldAdvance: Bool = false
    ) -> Bool {
        guard let itemID = id ?? selectedItem?.id,
              let index = items.firstIndex(where: { $0.id == itemID }) else { return false }
        let oldState = items[index].asset.libraryState
        guard oldState.flag != flag else {
            if shouldAdvance { advance(from: index) }
            return false
        }
        recordCullingChange(itemID: itemID, oldState: oldState)
        lastCullingAssetID = itemID
        items[index].asset.flag = flag
        invalidateCollectionProjection(notify: true)
        if shouldAdvance { advance(from: index) }
        if !filteredIndices.contains(selectedIndex) { reconcileFilteredSelection() }
        return true
    }

    @discardableResult
    func setRating(_ rating: Int, for id: PhotoAssetID? = nil) -> Bool {
        guard let itemID = id ?? selectedItem?.id,
              let index = items.firstIndex(where: { $0.id == itemID }) else { return false }
        let clamped = min(max(rating, 0), 5)
        let oldState = items[index].asset.libraryState
        guard oldState.rating != clamped else { return false }
        recordCullingChange(itemID: itemID, oldState: oldState)
        lastCullingAssetID = itemID
        items[index].asset.rating = clamped
        invalidateCollectionProjection(notify: true)
        if !filteredIndices.contains(selectedIndex) { reconcileFilteredSelection() }
        return true
    }

    @discardableResult
    func undoLastCullingChange() -> Bool {
        guard let change = cullingUndoStack.popLast(),
              let index = items.firstIndex(where: { $0.id == change.itemID }) else { return false }
        lastCullingAssetID = change.itemID
        items[index].asset.libraryState = change.oldState
        invalidateCollectionProjection(notify: true)
        if let activeID = change.activeIDBefore,
           filteredIndices.contains(where: { items[$0].id == activeID }) {
            var next = selection
            next.focus(activeID, in: items.map(\.id))
            selection = next
            syncSelectedIndex()
        } else { reconcileFilteredSelection() }
        return true
    }

    func loadPortableAssets(_ assets: [PhotoAsset]) {
        loadPortableWindow(assets: assets, totalCount: assets.count, pageIndex: 0,
                           pageSize: max(1, assets.count), query: .all)
    }

    func loadPortableWindow(
        assets: [PhotoAsset], totalCount: Int, pageIndex: Int,
        pageSize: Int, query: LibraryQuery
    ) {
        scanGeneration &+= 1
        cancelThumbnailWork()
        stopMetadataLoading()
        items = assets.map { Item(asset: $0) }
        selectedIndex = 0
        selection.clear()
        portableTotalCount = totalCount
        portablePageIndex = max(0, pageIndex)
        portablePageSize = max(1, pageSize)
        portableQuery = query
        scanWarnings = []
        isScanning = false
        isActive = !items.isEmpty
        invalidateCollectionProjection()
        startMetadataLoading()
        for item in items { enqueueMetadata(for: item, generation: scanGeneration) }
        enqueueThumbnails()
    }

    @discardableResult
    func appendPortableWindow(assets: [PhotoAsset], pageIndex: Int) -> Bool {
        guard portableTotalCount != nil, pageIndex == portablePageIndex + 1, !assets.isEmpty else {
            return false
        }
        let existing = Set(items.map(\.id))
        let fresh = assets.filter { !existing.contains($0.id) }.map { Item(asset: $0) }
        items.append(contentsOf: fresh)
        portablePageIndex = pageIndex
        invalidateCollectionProjection()
        for item in fresh { enqueueMetadata(for: item, generation: scanGeneration) }
        enqueueThumbnails()
        return true
    }

    var isPortableWindowed: Bool { portableTotalCount != nil }
    var portableHasMorePages: Bool {
        guard let total = portableTotalCount else { return false }
        return (portablePageIndex + 1) * portablePageSize < total
    }

    func syncPortableSelection(
        selectedIDs: Set<PortablePhotoAssetID>, activeID: PortablePhotoAssetID?
    ) {
        guard portableTotalCount != nil else { return }
        let ordered = items.compactMap { item -> PhotoAssetID? in
            guard let id = Self.portableID(for: item.id), selectedIDs.contains(id) else { return nil }
            return item.id
        }
        var next = selection
        next.clear()
        for id in ordered { next.focus(id, in: items.map(\.id)) }
        if let activeID, items.contains(where: { $0.id == Self.photoID(for: activeID) }) {
            let photoID = Self.photoID(for: activeID)
            next.focus(photoID, in: items.map(\.id))
            selectedIndex = items.firstIndex(where: { $0.id == photoID }) ?? selectedIndex
        }
        selection = next
    }

    func refresh() { /* Package refreshes are explicit session/index reloads. */ }
    func scanCompletion() async {
        guard !pendingMetadataRequestIDs.isEmpty else { return }
        await withCheckedContinuation { continuation in
            metadataCompletionWaiters.append(continuation)
        }
    }

    func recordScanWarning(_ message: String) {
        guard !scanWarnings.contains(where: { $0.message == message }) else { return }
        scanWarnings.append(.init(id: message, message: message))
    }

    func shutdown() async {
        scanGeneration &+= 1
        cancelThumbnailWork()
        let task = metadataTask
        stopMetadataLoading()
        await task?.value
        isScanning = false
    }

    @discardableResult
    func removeItems(with ids: Set<PhotoAssetID>) -> [DeletionCandidate] {
        let removed = items.filter { ids.contains($0.id) }.map {
            DeletionCandidate(id: $0.id, displayName: $0.displayName, url: $0.url, sourceKind: .managed)
        }
        guard !removed.isEmpty else { return [] }
        for item in items where ids.contains(item.id) {
            let jobID = thumbnailJobID(for: item)
            scheduler.cancel(id: jobID)
            thumbnailJobIDs.remove(jobID)
            thumbnailDemandIDs.remove(item.id)
            thumbnailDemandPriorities.removeValue(forKey: item.id)
            preparedThumbnailIDs.remove(item.id)
        }
        items.removeAll { ids.contains($0.id) }
        cullingUndoStack.removeAll { ids.contains($0.itemID) }
        portableTotalCount = portableTotalCount.map { max(0, $0 - removed.count) }
        invalidateCollectionProjection()
        reconcileSelection()
        selectedIndex = min(selectedIndex, max(0, items.count - 1))
        isActive = !items.isEmpty
        return removed
    }

    var thumbnailEntries: [ThumbnailEntry] { collectionProjection.thumbnailEntries }
    func resolvedItem(for entry: ThumbnailEntry) -> (index: Int, item: Item)? {
        guard let index = entry.itemIndex else { return nil }
        if items.indices.contains(index), items[index].id == entry.id { return (index, items[index]) }
        guard let current = items.firstIndex(where: { $0.id == entry.id }) else { return nil }
        return (current, items[current])
    }

    func beginThumbnailDemand() {
        guard !isThumbnailDemandDriven else { return }
        isThumbnailDemandDriven = true
        cancelThumbnailWork()
        // Originals only. The grid admits edited thumbnails for the whole viewport after those
        // previews are queued; doing it here would start a handful of full renders first and
        // leave the rest of the window blank.
        prepareAdjacentThumbnails(around: selectedIndex, requestsEditedThumbnails: false)
        fillThumbnailQueue()
    }

    func requestThumbnail(
        for id: PhotoAssetID,
        priority: ImageWorkScheduler.Priority = .visibleGrid,
        requestsEditedThumbnail: Bool = true
    ) {
        guard isThumbnailDemandDriven, let index = items.firstIndex(where: { $0.id == id }) else { return }
        requestOriginalThumbnail(for: id, at: index, priority: priority)
        if requestsEditedThumbnail { onThumbnailDemand?(id, priority) }
    }

    /// Admit fast previews for the photos in the viewport, then their edited renders.
    ///
    /// Edited work is one turn behind the originals and uses background priority, so a free
    /// thumbnail slot keeps painting embedded previews until that window is queued. Calling
    /// this for the visible mosaic is what fills the grid without waiting for a click.
    func requestVisibleThumbnails(for ids: [PhotoAssetID]) {
        guard !ids.isEmpty else { return }
        if !isThumbnailDemandDriven { beginThumbnailDemand() }
        var indexByID: [PhotoAssetID: Int] = [:]
        indexByID.reserveCapacity(items.count)
        for (index, item) in items.enumerated() { indexByID[item.id] = index }
        var admitted: [PhotoAssetID] = []
        admitted.reserveCapacity(ids.count)
        for id in ids {
            guard let index = indexByID[id] else { continue }
            requestOriginalThumbnail(for: id, at: index, priority: priority(for: index))
            admitted.append(id)
        }
        visibleEditedThumbnailIDs = admitted
        scheduleVisibleEditedThumbnails()
    }

    func releaseThumbnail(for id: PhotoAssetID) {
        guard isThumbnailDemandDriven else { return }
        thumbnailDemandIDs.remove(id)
        thumbnailDemandPriorities.removeValue(forKey: id)
        visibleEditedThumbnailIDs.removeAll { $0 == id }
        guard !preparedThumbnailIDs.contains(id),
              let index = items.firstIndex(where: { $0.id == id }), items[index].thumbnail == nil else { return }
        let jobID = thumbnailJobID(for: items[index])
        scheduler.cancel(id: jobID)
        thumbnailJobIDs.remove(jobID)
        items[index].asset.thumbnailState = .notRequested
    }

    func selectAll() {
        var next = selection
        next.selectAll(in: filteredItems.map(\.id))
        selection = next
        syncSelectedIndex()
        prepareAdjacentThumbnails(around: selectedIndex)
        reprioritizeThumbnails()
    }

    func select(at index: Int, modifiers: LibrarySelectionModel.Modifiers = []) {
        guard isActive, items.indices.contains(index),
              filter.matches(flag: items[index].asset.flag, rating: items[index].asset.rating) else { return }
        var next = selection
        next.click(items[index].id, in: filteredItems.map(\.id), modifiers: modifiers)
        selection = next
        syncSelectedIndex()
        prepareAdjacentThumbnails(around: selectedIndex)
        reprioritizeThumbnails()
    }

    func select(at index: Int) { select(at: index, modifiers: []) }
    func focus(id: PhotoAssetID) {
        guard isActive, items.contains(where: { $0.id == id }) else { return }
        var next = selection
        next.focus(id, in: filteredItems.map(\.id))
        selection = next
        syncSelectedIndex()
        prepareAdjacentThumbnails(around: selectedIndex)
        reprioritizeThumbnails()
    }
    func setSelection(at index: Int, additive: Bool = false) {
        select(at: index, modifiers: additive ? [.command] : [])
    }
    func selectNext() {
        guard let index = filteredIndices.first(where: { $0 > selectedIndex }) else { return }
        select(at: index)
    }
    func selectPrevious() {
        guard let index = filteredIndices.last(where: { $0 < selectedIndex }) else { return }
        select(at: index)
    }

    func clear() {
        scanGeneration &+= 1
        cancelThumbnailWork()
        stopMetadataLoading()
        items = []
        portableTotalCount = 0
        portablePageIndex = 0
        selection.clear()
        selectedIndex = 0
        invalidateCollectionProjection()
        isActive = false
        isScanning = false
    }

    func invalidateEditedThumbnail(for id: PhotoAssetID) { items.first { $0.id == id }?.invalidateEditedThumbnail() }
    func applyEditedThumbnail(_ thumbnail: NSImage?, for id: PhotoAssetID, revision: String) {
        items.first { $0.id == id }?.applyEditedThumbnail(thumbnail, revision: revision)
    }
    func setPresentedCrop(_ crop: CropAdjustments, for id: PhotoAssetID) {
        guard let item = items.first(where: { $0.id == id }), item.setPresentedCrop(crop) else { return }
        cropGeneration += 1
        invalidateCollectionProjection(notify: true)
    }

    private var collectionProjection: CollectionProjection.Snapshot {
        projectionCache.snapshot(
            items: items, filter: filter, collectionRevision: collectionRevision,
            filterRevision: filterRevision
        )
    }
    private func invalidateCollectionProjection(notify: Bool = false) {
        // `notify` is retained for call-site compatibility. Observation publishes the
        // revision bump automatically; no manual objectWillChange fan-out is needed.
        _ = notify
        collectionRevision &+= 1
    }
    private func recordCullingChange(itemID: PhotoAssetID, oldState: PhotoAssetLibraryState) {
        cullingUndoStack.append(.init(itemID: itemID, oldState: oldState, activeIDBefore: selection.activeID))
        if cullingUndoStack.count > 100 { cullingUndoStack.removeFirst() }
    }
    private func reconcileSelection() {
        var next = selection
        next.reconcile(with: items.map(\.id))
        if next.isEmpty, let first = items.first { next.click(first.id, in: items.map(\.id)) }
        selection = next
        syncSelectedIndex()
    }
    private func reconcileFilteredSelection() {
        guard let first = filteredIndices.first, !filteredIndices.contains(selectedIndex) else { return }
        var next = selection
        next.focus(items[first].id, in: items.map(\.id))
        selection = next
        syncSelectedIndex()
        reprioritizeThumbnails()
    }
    private func syncSelectedIndex() {
        guard let id = selection.activeID, let index = items.firstIndex(where: { $0.id == id }) else {
            if items.isEmpty { selectedIndex = 0 }
            return
        }
        selectedIndex = index
    }
    private func advance(from index: Int) {
        if let next = filteredIndices.first(where: { $0 > index }) { select(at: next) }
    }
    private func stopMetadataLoading() {
        metadataContinuation?.finish()
        metadataContinuation = nil
        metadataTask?.cancel()
        metadataTask = nil
        metadataAffectsMosaic = false
        pendingMetadataRequestIDs.removeAll()
        let waiters = metadataCompletionWaiters
        metadataCompletionWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }
    private func startMetadataLoading() {
        let (stream, continuation) = AsyncStream<MetadataRequest>.makeStream()
        metadataContinuation = continuation
        metadataTask = Task.detached { [weak self] in
            for await request in stream {
                guard !Task.isCancelled else { return }
                let outcome = Self.readMetadata(request.source, name: request.name)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self?.applyMetadata(
                        outcome, itemID: request.itemID, generation: request.generation,
                        requestID: request.id
                    )
                }
            }
        }
    }
    private func enqueueMetadata(for item: Item, generation: UInt64) {
        guard let source = item.url.map(ImageSource.Backing.url) ?? item.imageData.map(ImageSource.Backing.data) else { return }
        guard let metadataContinuation else { return }
        nextMetadataRequestID &+= 1
        let request = MetadataRequest(
            id: nextMetadataRequestID, itemID: item.id, generation: generation,
            name: item.displayName, source: source
        )
        pendingMetadataRequestIDs.insert(request.id)
        switch metadataContinuation.yield(request) {
        case .enqueued:
            break
        case .dropped, .terminated:
            pendingMetadataRequestIDs.remove(request.id)
            finishMetadataWaitersIfIdle()
        @unknown default:
            pendingMetadataRequestIDs.remove(request.id)
            finishMetadataWaitersIfIdle()
        }
    }
    private nonisolated static func readMetadata(_ source: ImageSource.Backing, name: String) -> MetadataOutcome {
        switch source {
        case .url(let url):
            guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(imageSource) > 0 else {
                return .failure("Could not read metadata for \(name).")
            }
            return .success(ImageMetadata.read(from: url))
        case .data(let data):
            guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(imageSource) > 0 else {
                return .failure("Could not read metadata for \(name).")
            }
            return .success(ImageMetadata.read(from: data))
        }
    }
    private func applyMetadata(
        _ outcome: MetadataOutcome, itemID: PhotoAssetID, generation: UInt64, requestID: UInt64
    ) {
        pendingMetadataRequestIDs.remove(requestID)
        guard generation == scanGeneration, let index = items.firstIndex(where: { $0.id == itemID }) else {
            finishMetadataWaitersIfIdle()
            return
        }
        switch outcome {
        case .success(let metadata):
            let previousDimensions = items[index].asset.dimensions
            items[index].metadata = metadata
            items[index].asset.updateMetadata(from: metadata)
            if items[index].asset.dimensions != previousDimensions {
                metadataAffectsMosaic = true
            }
        case .failure(let warning):
            if !scanWarnings.contains(where: { $0.message == warning }) {
                scanWarnings.append(.init(id: warning, message: warning))
            }
        }
        finishMetadataWaitersIfIdle()
    }
    private func finishMetadataWaitersIfIdle() {
        guard pendingMetadataRequestIDs.isEmpty else { return }
        if metadataAffectsMosaic {
            metadataAffectsMosaic = false
            invalidateCollectionProjection(notify: true)
        }
        let waiters = metadataCompletionWaiters
        metadataCompletionWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }
    private func cancelThumbnailWork() {
        thumbnailGeneration &+= 1
        scheduler.cancel(ids: thumbnailJobIDs)
        thumbnailJobIDs.removeAll()
    }
    private func enqueueThumbnails() {
        if isThumbnailDemandDriven { fillThumbnailQueue(); return }
        for (index, item) in items.enumerated() where item.thumbnail == nil {
            guard scheduler.canQueueThumbnail else { return }
            enqueueThumbnail(for: item, at: index, generation: thumbnailGeneration)
        }
    }
    private func enqueueThumbnail(
        for item: Item, at index: Int, generation: UInt64,
        priority requested: ImageWorkScheduler.Priority? = nil
    ) {
        let id = thumbnailJobID(for: item)
        scheduler.enqueue(id: id, lane: .thumbnail, priority: requested ?? priority(for: index)) { [weak self] in
            let thumbnail: NSImage?
            if let url = item.url {
                let identity = item.asset.source.portableIdentity
                thumbnail = await Task.detached { PlatformThumbnailProvider.generate(from: url, portableIdentity: identity) }.value
            } else if let data = item.imageData {
                let identity = item.asset.source.portableIdentity
                let fingerprint = item.dataFingerprint
                thumbnail = await Task.detached {
                    PlatformThumbnailProvider.generate(
                        from: data, dataFingerprint: fingerprint, portableIdentity: identity
                    )
                }.value
            } else { thumbnail = nil }
            guard !Task.isCancelled else { return }
            self?.applyThumbnail(thumbnail, itemID: item.id, generation: generation)
        }
        if scheduler.contains(id) { thumbnailJobIDs.insert(id); item.asset.thumbnailState = .loading }
    }
    private func applyThumbnail(_ thumbnail: NSImage?, itemID: PhotoAssetID, generation: UInt64) {
        guard generation == thumbnailGeneration, let item = items.first(where: { $0.id == itemID }) else { return }
        thumbnailJobIDs.remove(thumbnailJobID(for: item))
        item.setOriginalThumbnail(thumbnail)
        item.asset.thumbnailState = thumbnail == nil ? .failed : .ready
        fillThumbnailQueue()
        // A full viewport can exceed the thumbnail queue. As each preview finishes, ask again
        // for the edited renders that were rejected while the queue held originals.
        let editedIDs = visibleEditedThumbnailIDs
        for id in editedIDs {
            onThumbnailDemand?(id, .background)
        }
    }
    private func requestOriginalThumbnail(
        for id: PhotoAssetID, at index: Int, priority: ImageWorkScheduler.Priority
    ) {
        guard items.indices.contains(index), items[index].thumbnail == nil else { return }
        thumbnailDemandIDs.insert(id)
        thumbnailDemandPriorities[id] = priority
        let jobID = thumbnailJobID(for: items[index])
        if !scheduler.contains(jobID) {
            enqueueThumbnail(
                for: items[index], at: index, generation: thumbnailGeneration, priority: priority
            )
        } else {
            scheduler.updatePriority(for: jobID, to: priority)
        }
    }
    private func scheduleVisibleEditedThumbnails() {
        guard !visibleEditedDemandScheduled else { return }
        visibleEditedDemandScheduled = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.visibleEditedDemandScheduled = false
            let ids = self.visibleEditedThumbnailIDs
            for id in ids {
                self.onThumbnailDemand?(id, .background)
            }
        }
    }
    private func fillThumbnailQueue() {
        let candidates = items.indices.filter {
            items[$0].thumbnail == nil && (!isThumbnailDemandDriven || thumbnailDemandIDs.contains(items[$0].id) || preparedThumbnailIDs.contains(items[$0].id))
        }.sorted { priority(for: $0).rawValue < priority(for: $1).rawValue }
        for index in candidates {
            guard scheduler.canQueueThumbnail else { return }
            let item = items[index]
            guard !scheduler.contains(thumbnailJobID(for: item)) else { continue }
            enqueueThumbnail(for: item, at: index, generation: thumbnailGeneration, priority: thumbnailDemandPriorities[item.id])
        }
    }
    private func prepareAdjacentThumbnails(
        around index: Int, requestsEditedThumbnails: Bool = true
    ) {
        guard isThumbnailDemandDriven else { return }
        preparedThumbnailIDs = Set(items.indices.filter { abs($0 - index) <= 2 }.map { items[$0].id })
        for id in preparedThumbnailIDs {
            thumbnailDemandPriorities[id] = .adjacentFilmstrip
        }
        fillThumbnailQueue()
        guard requestsEditedThumbnails else { return }
        for id in preparedThumbnailIDs { onThumbnailDemand?(id, .adjacentFilmstrip) }
    }
    private func reprioritizeThumbnails() { fillThumbnailQueue() }
    private func priority(for index: Int) -> ImageWorkScheduler.Priority {
        switch abs(index - selectedIndex) { case 0...2: return .adjacentFilmstrip; case 3...12: return .visibleGrid; default: return .background }
    }
    private func thumbnailJobID(for item: Item) -> ImageWorkScheduler.JobID {
        ImageWorkScheduler.JobID(item.url.map { "thumbnail:url:\($0.standardizedFileURL.path)" } ?? "thumbnail:item:\(item.id.raw)")
    }
    private static func portableID(for photoID: PhotoAssetID) -> PortablePhotoAssetID? {
        guard photoID.raw.hasPrefix("portable:"), let uuid = UUID(uuidString: String(photoID.raw.dropFirst(9))) else { return nil }
        return PortablePhotoAssetID(uuid: uuid)
    }
    private static func photoID(for portableID: PortablePhotoAssetID) -> PhotoAssetID {
        PhotoAssetID(rawValue: "portable:\(portableID.raw)")
    }
}

typealias ImageCollection = ImageCollectionPresentationModel

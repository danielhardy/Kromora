import CoreGraphics
import Foundation

/// The two records a photo can have in the packed thumbnail store.
///
/// A photo keeps at most one of each: the unedited `original` and the `latestEdited` frame. Stable
/// keys — derived from the asset UUID and the kind, never from an edit or Look — mean a replacement
/// appends new bytes and moves the index pointer instead of accumulating one live key per edit.
enum ThumbnailFrameKind: Sendable, Equatable, CaseIterable {
    case original
    case edited

    var presentationKind: PresentationFrameKind {
        switch self {
        case .original: return .originalThumbnail480
        case .edited: return .editedThumbnail480
        }
    }

    fileprivate var keySuffix: String {
        switch self {
        case .original: return "o"
        case .edited: return "e"
        }
    }
}

/// Bounds for visible-window frame reads. Named so a test can assert them and a change has one
/// place to land.
enum ThumbnailFrameReadPolicy {
    /// How many pack reads may be admitted at once. Enforced by `ImageWorkScheduler`'s frame-read
    /// lane, which also holds new reads while editor work is contended.
    static let maxConcurrentReads = 4
    /// Photos read beyond the visible set: one page of the photos that follow the window.
    static let prefetchPageSize = 24

    /// The most photos one window may read: everything visible plus one prefetch page.
    static func windowCap(visibleCount: Int) -> Int {
        max(0, visibleCount) + prefetchPageSize
    }

    /// The photos to read for a window: every visible ID, then at most one prefetch page of
    /// `following`, without duplicates and never above `windowCap`.
    static func window(
        visible: [PhotoAssetID], following: [PhotoAssetID]
    ) -> [PhotoAssetID] {
        var seen = Set<PhotoAssetID>()
        var result: [PhotoAssetID] = []
        result.reserveCapacity(windowCap(visibleCount: visible.count))
        for id in visible where seen.insert(id).inserted { result.append(id) }
        var prefetched = 0
        for id in following where prefetched < prefetchPageSize {
            guard seen.insert(id).inserted else { continue }
            result.append(id)
            prefetched += 1
        }
        return result
    }
}

/// How an unedited thumbnail is expressed in the shared frame model, so the same classifier answers
/// "may these pixels stand in for this photo?" for every frame kind.
enum OriginalThumbnailSignature {
    /// Stands in for the edit hash: an original has no edit.
    static let editHash = "original"

    static func signature(for identity: PortablePhotoIdentity) -> FrameSignature {
        FrameSignature(
            source: identity, editHash: editHash, look: .none,
            workingSpace: .current, pixelEpoch: RenderPipeline.pixelEpoch
        )
    }

    static func currentInputs(for identity: PortablePhotoIdentity) -> FrameCurrentInputs {
        FrameCurrentInputs(source: identity, editHash: editHash, look: LookSignature.none)
    }
}

/// Runtime facade over the package's packed thumbnail store (`Derived/Thumbnails`).
///
/// The store is rebuildable presentation cache, never package truth. Construction performs no I/O;
/// the packed store opens on first use, off the main actor. Every failure is scoped: a missing,
/// truncated, or corrupt pack, a stale offset, or an unreadable index is a miss — the affected
/// records regenerate from source — and nothing here can make a package fail to open or validate.
///
/// Writes are coalesced. The packed store rewrites its whole index per append, so records wait in
/// memory (and are readable there) and reach disk as one batch after a short quiet period, when the
/// batch reaches `maxPendingWrites`, or when `flush()` is called.
actor ThumbnailFrameStore {
    static let flushDelay: Duration = .milliseconds(250)
    static let maxPendingWrites = 32

    struct Hit: Sendable {
        let frame: PresentationFrame
        let image: CGImage
    }

    struct StoredFrames: Sendable {
        let original: Hit?
        let edited: Hit?
        let originalCorrupt: Bool
        let editedCorrupt: Bool

        init(
            original: Hit?, edited: Hit?, originalCorrupt: Bool = false,
            editedCorrupt: Bool = false
        ) {
            self.original = original
            self.edited = edited
            self.originalCorrupt = originalCorrupt
            self.editedCorrupt = editedCorrupt
        }
    }

    private let directory: URL
    private let workScheduler: ImageWorkScheduler?
    private let placeholderSweepJobID = ImageWorkScheduler.JobID(
        "placeholder-thumbnail-sweep-\(UUID().uuidString)"
    )
    private var store: PortablePackagePackedThumbnailStore?
    private var openFailed = false
    private var pending: [String: PresentationFrame] = [:]
    private var flushTask: Task<Void, Never>?
    private var placeholderSweepScheduled = false
    private var placeholderSweepHasMore = false
    private var placeholderSweepKeys: [String] = []
    private var placeholderSweepCursor = 0
    private(set) var placeholderSweepRecordsExamined = 0
    private(set) var placeholderSweepLargestBatch = 0
    var placeholderSweepIsScheduled: Bool { placeholderSweepScheduled }
    private(set) var placeholderWritesSkipped = 0
    private(set) var readCount = 0
    private(set) var writeCount = 0

    init(directory: URL, workScheduler: ImageWorkScheduler? = nil) {
        self.directory = directory
        self.workScheduler = workScheduler
    }

    nonisolated static func packageDirectory(for packageURL: URL) -> URL {
        KromoraStorage.packageDerivedDirectory(named: "Thumbnails", under: packageURL)
    }

    nonisolated static func key(_ kind: ThumbnailFrameKind, for assetID: PortablePhotoAssetID) -> String? {
        LatestPreviewFrameStore.assetHash(assetID).map { "\($0)-\(kind.keySuffix)" }
    }

    // MARK: Reads

    /// The stored frame for `identity`'s asset, whatever source revision or edit it depicts. The
    /// caller classifies it; this store guarantees only that the bytes are a well-formed frame of
    /// the requested kind for the same asset.
    func read(_ kind: ThumbnailFrameKind, for identity: PortablePhotoIdentity) -> Hit? {
        readWithOutcome(kind, for: identity).hit
    }

    func readWithOutcome(
        _ kind: ThumbnailFrameKind, for identity: PortablePhotoIdentity
    ) -> (hit: Hit?, corrupt: Bool) {
        guard let key = Self.key(kind, for: identity.assetID) else { return (nil, false) }
        readCount += 1
        if let frame = pending[key] {
            if Self.hasPlaceholderIdentity(frame) {
                pending.removeValue(forKey: key)
                return (nil, false)
            }
            guard let image = try? PresentationFrameEnvelope.decodeRaster(of: frame) else {
                return (nil, true)
            }
            return (Hit(frame: frame, image: image), false)
        }
        guard openStoreIfNeeded() else { return (nil, false) }
        refreshIfExternallyReplaced()
        var foundDamagedRecord = false
        for attempt in 0..<2 {
            guard let store else { return (nil, false) }
            let lookup: PortablePackagePackedThumbnailStore.LookupResult
            do { lookup = try store.lookup(key) } catch { return (nil, foundDamagedRecord) }
            switch lookup {
            case .missing:
                return (nil, foundDamagedRecord)
            case .stale:
                // The offsets no longer describe these packs. Re-reading the index is the repair
                // when another process compacted them; a second miss stays a miss.
                guard attempt == 0, reloadIndex() else { return (nil, foundDamagedRecord) }
            case .found(let data):
                do {
                    let frame = try PresentationFrameEnvelope.decode(
                        data, expectedAssetID: identity.assetID
                    )
                    if Self.hasPlaceholderIdentity(frame) {
                        removeIfSameRecord(key: key, data: data)
                        return (nil, false)
                    }
                    guard frame.kind == kind.presentationKind else { throw PresentationFrameEnvelope.DecodeError.identityMismatch }
                    let image = try PresentationFrameEnvelope.decodeRaster(of: frame)
                    return (Hit(frame: frame, image: image), false)
                } catch {
                    foundDamagedRecord = true
                    // Bytes that do not decode are either a damaged record or an offset into a
                    // replaced pack. Try a fresh index once; otherwise drop just this pointer.
                    if attempt == 0, reloadIndex() { continue }
                    try? store.remove(keys: [key])
                    return (nil, true)
                }
            }
        }
        return (nil, foundDamagedRecord)
    }

    /// Both records of a photo, for a visible-window hydration pass.
    func readFrames(for identity: PortablePhotoIdentity) -> StoredFrames {
        let original = readWithOutcome(.original, for: identity)
        let edited = readWithOutcome(.edited, for: identity)
        return StoredFrames(
            original: original.hit, edited: edited.hit,
            originalCorrupt: original.corrupt, editedCorrupt: edited.corrupt
        )
    }

    // MARK: Writes

    /// Queue a record. A later write for the same key supersedes one not yet on disk.
    func enqueueWrite(_ frame: PresentationFrame) {
        guard !Self.hasPlaceholderIdentity(frame) else {
            placeholderWritesSkipped += 1
            KromoraObservability.event(.frameWriteSkippedPlaceholder)
            return
        }
        guard let kind = ThumbnailFrameKind.allCases.first(where: { $0.presentationKind == frame.kind }),
              let key = Self.key(kind, for: frame.identity.assetID) else { return }
        pending[key] = frame
        if pending.count >= Self.maxPendingWrites {
            flushPending()
        } else {
            scheduleFlush()
        }
    }

    /// Write every queued record now.
    func flush() {
        flushTask?.cancel()
        flushTask = nil
        flushPending()
    }

    /// Drop a photo's record of one kind — for example the edited record after a reset to the
    /// original. The pointer is removed from the index; compaction reclaims the bytes.
    func remove(_ kind: ThumbnailFrameKind, for assetID: PortablePhotoAssetID) {
        guard let key = Self.key(kind, for: assetID) else { return }
        pending.removeValue(forKey: key)
        guard openStoreIfNeeded() else { return }
        refreshIfExternallyReplaced()
        try? store?.remove(keys: [key])
    }

    /// Drop both records of each photo (deletion, source replacement).
    func remove(assetIDs: Set<PortablePhotoAssetID>) {
        let keys = assetIDs.flatMap { id in
            ThumbnailFrameKind.allCases.compactMap { Self.key($0, for: id) }
        }
        for key in keys { pending.removeValue(forKey: key) }
        guard openStoreIfNeeded() else { return }
        refreshIfExternallyReplaced()
        try? store?.remove(keys: keys)
    }

    // MARK: Maintenance and diagnostics

    /// Compact through this instance so its in-memory index stays consistent with the packs it
    /// rewrote. Queued records are written first so none are lost to the rewrite.
    func compact(
        package: PortableLibraryPackage, lease: PortablePackageLease
    ) throws -> PortablePackagePackedThumbnailStore.CompactionResult {
        flush()
        guard openStoreIfNeeded(), let store else {
            throw PortablePackageError.invalidRelativePath("thumbnail store unavailable")
        }
        refreshIfExternallyReplaced()
        return try store.compact(package: package, lease: lease)
    }

    var liveEntryCount: Int {
        _ = openStoreIfNeeded()
        return store?.liveEntryCount ?? 0
    }

    var physicalByteCount: UInt64 {
        _ = openStoreIfNeeded()
        return store?.physicalByteCount ?? 0
    }

    var pendingWriteCount: Int { pending.count }

    /// Removes one bounded batch. Production cleanup is admitted through the shared scheduler;
    /// tests can call this to drive a specific number of idle ticks.
    func sweepPlaceholderFrames(maxRecords: Int = 8) {
        guard maxRecords > 0, openStoreIfNeeded() else { return }
        placeholderSweepHasMore = sweepPlaceholderBatch(maxRecords: maxRecords)
        if placeholderSweepHasMore { Task { await schedulePlaceholderSweep() } }
    }

    /// Write anything still queued and stop the flush timer. Call before the owner is released.
    func shutdown() {
        flush()
    }

    // MARK: Internals

    private func scheduleFlush() {
        guard flushTask == nil else { return }
        flushTask = Task { [weak self] in
            try? await Task.sleep(for: Self.flushDelay)
            guard !Task.isCancelled else { return }
            await self?.flushScheduled()
        }
    }

    private func flushScheduled() {
        flushTask = nil
        flushPending()
    }

    private func flushPending() {
        guard !pending.isEmpty else { return }
        let batch = pending
        pending.removeAll(keepingCapacity: true)
        var records: [PortablePackagePackedThumbnailStore.Record] = []
        records.reserveCapacity(batch.count)
        for (key, frame) in batch {
            guard let data = try? PresentationFrameEnvelope.encode(frame) else { continue }
            records.append(.init(key: key, data: data))
        }
        guard !records.isEmpty else { return }
        for attempt in 0..<2 {
            guard openStoreIfNeeded(), let store else { return }
            refreshIfExternallyReplaced()
            do {
                try store.append(records: records)
                writeCount += records.count
                return
            } catch {
                // A deleted `Derived/Thumbnails` or an unwritable pack: reopen from scratch once so
                // the directory is recreated, then give up quietly. The records regenerate.
                guard attempt == 0 else { return }
                self.store = nil
                openFailed = false
            }
        }
    }

    private func openStoreIfNeeded() -> Bool {
        if store != nil {
            Task { [weak self] in await self?.schedulePlaceholderSweep() }
            return true
        }
        guard !openFailed else { return false }
        do {
            store = try PortablePackagePackedThumbnailStore(at: directory)
            Task { [weak self] in await self?.schedulePlaceholderSweep() }
            return true
        } catch {
            // An unreadable or unsupported index is cache damage, not a package problem. Discard
            // the index; the orphaned pack bytes are reclaimed by compaction.
            try? FileManager.default.removeItem(at: directory.appendingPathComponent("index.json"))
            do {
                store = try PortablePackagePackedThumbnailStore(at: directory)
                Task { [weak self] in await self?.schedulePlaceholderSweep() }
                return true
            } catch {
                openFailed = true
                return false
            }
        }
    }

    private func removeIfSameRecord(key: String, data: Data) {
        guard let store,
              case .found(let current) = try? store.lookup(key), current == data else { return }
        try? store.remove(keys: [key])
    }

    private func sweepPlaceholderBatch(maxRecords: Int) -> Bool {
        guard let store else { return false }
        if placeholderSweepKeys.isEmpty {
            placeholderSweepKeys = store.keys.sorted()
            placeholderSweepCursor = 0
        }
        let start = min(placeholderSweepCursor, placeholderSweepKeys.count)
        let batch = Array(placeholderSweepKeys.dropFirst(start).prefix(maxRecords))
        placeholderSweepRecordsExamined += batch.count
        placeholderSweepLargestBatch = max(placeholderSweepLargestBatch, batch.count)
        for key in batch {
            guard case .found(let data) = try? store.lookup(key),
                  let frame = try? PresentationFrameEnvelope.decode(data, expectedAssetID: nil),
                  Self.hasPlaceholderIdentity(frame) else { continue }
            removeIfSameRecord(key: key, data: data)
        }
        placeholderSweepCursor = min(start + batch.count, placeholderSweepKeys.count)
        let hasMore = placeholderSweepCursor < placeholderSweepKeys.count
        if !hasMore {
            placeholderSweepKeys = []
            placeholderSweepCursor = 0
        }
        return hasMore
    }

    private func schedulePlaceholderSweep() async {
        guard !placeholderSweepScheduled, let workScheduler else { return }
        placeholderSweepScheduled = true
        let admitted = await workScheduler.enqueuePackageIO(
            id: placeholderSweepJobID, lane: .maintenance, priority: .background,
            onTerminal: { [weak self] outcome in
                Task { await self?.placeholderSweepFinished(outcome: outcome) }
            },
            operation: { [weak self] in
                guard let self else { return }
                await self.runScheduledPlaceholderSweep()
            }
        )
        if !admitted { placeholderSweepScheduled = false }
    }

    private func runScheduledPlaceholderSweep() {
        placeholderSweepHasMore = sweepPlaceholderBatch(maxRecords: 8)
    }

    private func placeholderSweepFinished(outcome: ImageWorkScheduler.TerminalOutcome) async {
        placeholderSweepScheduled = false
        if outcome == .completed, placeholderSweepHasMore { await schedulePlaceholderSweep() }
    }

    private static func hasPlaceholderIdentity(_ frame: PresentationFrame) -> Bool {
        frame.identity.sourceFingerprint.isBrowsingPlaceholder
            || frame.signature.source.sourceFingerprint.isBrowsingPlaceholder
    }

    private func refreshIfExternallyReplaced() {
        guard let store, store.indexChangedOnDisk else { return }
        _ = reloadIndex()
    }

    @discardableResult
    private func reloadIndex() -> Bool {
        guard let store else { return false }
        do {
            try store.reloadIndex()
            return true
        } catch {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent("index.json"))
            self.store = nil
            return openStoreIfNeeded()
        }
    }
}

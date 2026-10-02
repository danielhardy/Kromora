import CoreGraphics
import CryptoKit
import Foundation

/// Durable store for the latest presented 2048 px preview of each photo.
///
/// One atomically replaced `<asset-hash>.kframe` envelope exists per asset, so the most recent
/// presentation is what a relaunch shows and the store's budget is not spent on superseded edits.
/// The file name derives from the portable asset UUID only — never a path, URL, or fingerprint —
/// so a source replacement overwrites its own predecessor instead of accumulating beside it.
///
/// Construction performs no I/O. The first operation loads a size/recency index off the main
/// actor; later writes maintain it incrementally. Any damage is scoped to one entry: a corrupt
/// file is removed and reported as a miss, a file in an unsupported container version is ignored
/// until it is replaced, and nothing here ever wipes the directory.
actor LatestPreviewFrameStore {
    static let defaultCapBytes: Int64 = 1_000_000_000
    static let canonicalLongEdge = FrameClassifier.previewLongEdge

    /// A decoded frame. The JPEG is decoded inside the actor so presentation never pays for it on
    /// the main actor.
    struct Hit: Sendable {
        let frame: PresentationFrame
        let image: CGImage
    }

    private struct Entry {
        var size: Int64
        var lastAccess: Date
    }

    private let directory: URL
    private let capBytes: Int64
    private let workScheduler: ImageWorkScheduler?
    private let placeholderSweepJobID = ImageWorkScheduler.JobID(
        "placeholder-preview-sweep-\(UUID().uuidString)"
    )
    private var entries: [String: Entry] = [:]
    private var totalBytes: Int64 = 0
    private var didLoadIndex = false
    private var lastReadWasPlaceholder = false
    private var pinned: Set<String> = []
    private var pendingWrites: [String: (token: UInt64, task: Task<Void, Never>)] = [:]
    private var nextWriteToken: UInt64 = 0
    private var legacyCleanupTask: Task<Void, Never>?
    private var placeholderSweepScheduled = false
    private var placeholderSweepHasMore = false
    private var placeholderSweepCompletedPass = false
    private var placeholderSweepKeys: [String] = []
    private var placeholderSweepCursor = 0
    private(set) var placeholderSweepFilesExamined = 0
    private(set) var placeholderSweepLargestBatch = 0
    var placeholderSweepIsScheduled: Bool { placeholderSweepScheduled }
    private(set) var placeholderWritesSkipped = 0

    init(
        directory: URL, capBytes: Int64 = LatestPreviewFrameStore.defaultCapBytes,
        workScheduler: ImageWorkScheduler? = nil
    ) {
        self.directory = directory
        self.capBytes = max(0, capBytes)
        self.workScheduler = workScheduler
    }

    nonisolated static func packageDirectory(for packageURL: URL) -> URL {
        KromoraStorage.packageDerivedDirectory(named: "Previews", under: packageURL)
    }

    // MARK: Reads

    /// The stored frame for `identity`'s asset, whatever source revision it was made from. The
    /// caller classifies it; this store only guarantees the bytes are a well-formed frame for the
    /// same asset.
    func read(for identity: PortablePhotoIdentity) -> Hit? {
        lastReadWasPlaceholder = false
        guard loadIndex(), let hash = Self.assetHash(identity.assetID), entries[hash] != nil
        else { return nil }
        let url = fileURL(forHash: hash)
        let fileIdentity = Self.fileIdentity(at: url)
        do {
            let frame = try PresentationFrameEnvelope.read(
                from: url, expectedAssetID: identity.assetID
            )
            if Self.hasPlaceholderIdentity(frame) {
                lastReadWasPlaceholder = true
                removeIfSameFile(
                    url, hash: hash, metadata: frame.metadata, fileIdentity: fileIdentity
                )
                return nil
            }
            guard frame.kind == .preview2048 else { return nil }
            let image = try PresentationFrameEnvelope.decodeRaster(of: frame)
            touch(hash)
            return Hit(frame: frame, image: image)
        } catch {
            discardIfDamaged(error, hash: hash)
            return nil
        }
    }

    func readWithOutcome(for identity: PortablePhotoIdentity) -> (hit: Hit?, corrupt: Bool) {
        let existed = loadIndex()
            && Self.assetHash(identity.assetID).map { entries[$0] != nil } == true
        let hit = read(for: identity)
        let isMissing: Bool
        if case .none = hit { isMissing = true } else { isMissing = false }
        return (hit, existed && isMissing && !lastReadWasPlaceholder)
    }

    /// Metadata only, for callers that need to know what is stored without paying to decode it.
    func metadata(for identity: PortablePhotoIdentity) -> PresentationFrameMetadata? {
        guard loadIndex(), let hash = Self.assetHash(identity.assetID), entries[hash] != nil
        else { return nil }
        let url = fileURL(forHash: hash)
        let fileIdentity = Self.fileIdentity(at: url)
        do {
            let frame = try PresentationFrameEnvelope.read(
                from: url, expectedAssetID: identity.assetID,
                includeRaster: false
            )
            guard !Self.hasPlaceholderIdentity(frame) else {
                removeIfSameFile(url, hash: hash, metadata: frame.metadata, fileIdentity: fileIdentity)
                return nil
            }
            return frame.metadata
        } catch {
            discardIfDamaged(error, hash: hash)
            return nil
        }
    }

    func contains(_ identity: PortablePhotoIdentity) -> Bool {
        guard loadIndex(), let hash = Self.assetHash(identity.assetID) else { return false }
        return entries[hash] != nil
    }

    var currentSizeBytes: Int64 {
        _ = loadIndex()
        return totalBytes
    }

    // MARK: Writes

    /// Queue a serialized write. A later write for the same asset supersedes one that has not
    /// reached the filesystem yet, so a burst of settles leaves one file write, not one per tick.
    func enqueueWrite(_ frame: PresentationFrame) {
        guard !Self.hasPlaceholderIdentity(frame) else {
            placeholderWritesSkipped += 1
            KromoraObservability.event(.frameWriteSkippedPlaceholder)
            return
        }
        guard frame.kind == .preview2048,
              let hash = Self.assetHash(frame.identity.assetID) else { return }
        pendingWrites[hash]?.task.cancel()
        nextWriteToken &+= 1
        let token = nextWriteToken
        let task = Task { [weak self] in
            await Task.yield()
            guard !Task.isCancelled, let self else { return }
            await self.write(frame, hash: hash)
            await self.finishedWrite(hash: hash, token: token)
        }
        pendingWrites[hash] = (token, task)
    }

    func cancelPendingWrites() {
        for pending in pendingWrites.values { pending.task.cancel() }
        pendingWrites.removeAll()
    }

    /// Wait until every queued write has reached the filesystem.
    func waitForPendingWrites() async {
        for task in pendingWrites.values.map(\.task) { await task.value }
    }

    /// Wait for the lazy legacy cleanup started by the index load, if any.
    func waitForLegacyCleanup() async {
        _ = loadIndex()
        await legacyCleanupTask?.value
    }

    /// Processes one bounded batch. Production cleanup is admitted through the shared scheduler;
    /// tests can call this to drive a specific number of idle ticks.
    func sweepPlaceholderFrames(maxFiles: Int = 8) {
        guard maxFiles > 0, loadIndex() else { return }
        placeholderSweepHasMore = sweepPlaceholderBatch(maxFiles: maxFiles)
        if placeholderSweepHasMore { Task { await schedulePlaceholderSweep() } }
    }

    @discardableResult
    private func sweepPlaceholderBatch(maxFiles: Int) -> Bool {
        if placeholderSweepKeys.isEmpty {
            placeholderSweepKeys = entries.keys.sorted()
            placeholderSweepCursor = 0
        }
        let start = min(placeholderSweepCursor, placeholderSweepKeys.count)
        let batch = Array(placeholderSweepKeys.dropFirst(start).prefix(maxFiles))
        placeholderSweepFilesExamined += batch.count
        placeholderSweepLargestBatch = max(placeholderSweepLargestBatch, batch.count)
        for hash in batch {
            let url = fileURL(forHash: hash)
            let fileIdentity = Self.fileIdentity(at: url)
            guard let frame = try? PresentationFrameEnvelope.read(
                from: url, expectedAssetID: nil, includeRaster: false
            ), Self.hasPlaceholderIdentity(frame) else { continue }
            removeIfSameFile(
                url, hash: hash, metadata: frame.metadata, fileIdentity: fileIdentity
            )
        }
        placeholderSweepCursor = min(start + batch.count, placeholderSweepKeys.count)
        let hasMore = placeholderSweepCursor < placeholderSweepKeys.count
        if !hasMore {
            placeholderSweepCompletedPass = true
            placeholderSweepKeys = []
            placeholderSweepCursor = 0
        }
        return hasMore
    }

    // MARK: Invalidation and pinning

    /// Remove every frame belonging to these assets (deletion, source replacement).
    func invalidate(identities: Set<PortablePhotoIdentity>) {
        guard loadIndex() else { return }
        for identity in identities {
            guard let hash = Self.assetHash(identity.assetID) else { continue }
            pendingWrites[hash]?.task.cancel()
            pendingWrites.removeValue(forKey: hash)
            remove(hash: hash)
        }
    }

    /// Assets whose frames eviction must not remove — the active photo and the visible window.
    func setPinned(_ assetIDs: Set<PortablePhotoAssetID>) {
        pinned = Set(assetIDs.compactMap(Self.assetHash))
    }

    // MARK: Internals

    nonisolated static func assetHash(_ assetID: PortablePhotoAssetID) -> String? {
        SHA256.hash(data: Data(assetID.raw.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func fileURL(forHash hash: String) -> URL {
        directory.appendingPathComponent("\(hash).\(PresentationFrameEnvelope.fileExtension)")
    }

    private func finishedWrite(hash: String, token: UInt64) {
        if pendingWrites[hash]?.token == token { pendingWrites.removeValue(forKey: hash) }
    }

    private func write(_ frame: PresentationFrame, hash: String) {
        guard !Self.hasPlaceholderIdentity(frame) else {
            placeholderWritesSkipped += 1
            KromoraObservability.event(.frameWriteSkippedPlaceholder)
            return
        }
        guard !Task.isCancelled, loadIndex() else { return }
        do {
            let data = try PresentationFrameEnvelope.encode(frame)
            let url = fileURL(forHash: hash)
            try data.write(to: url, options: .atomic)
            let now = Date()
            try? FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: url.path)
            if let old = entries.updateValue(
                Entry(size: Int64(data.count), lastAccess: now), forKey: hash
            ) { totalBytes -= old.size }
            totalBytes += Int64(data.count)
            enforceCap(protecting: hash)
        } catch {
            // The store is an optimization and never a render prerequisite.
        }
    }

    private func touch(_ hash: String) {
        guard var entry = entries[hash] else { return }
        let now = Date()
        entry.lastAccess = now
        entries[hash] = entry
        try? FileManager.default.setAttributes(
            [.modificationDate: now], ofItemAtPath: fileURL(forHash: hash).path
        )
    }

    private func remove(hash: String) {
        guard let entry = entries.removeValue(forKey: hash) else { return }
        try? FileManager.default.removeItem(at: fileURL(forHash: hash))
        totalBytes -= entry.size
    }

    private func removeIfSameFile(
        _ url: URL, hash: String, metadata: PresentationFrameMetadata,
        fileIdentity: String?
    ) {
        guard let fileIdentity, Self.fileIdentity(at: url) == fileIdentity,
              entries[hash] != nil,
              let current = try? PresentationFrameEnvelope.read(
                from: url, expectedAssetID: nil, includeRaster: false
              ), current.metadata == metadata else { return }
        remove(hash: hash)
    }

    private static func fileIdentity(at url: URL) -> String? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let device = attributes[.systemNumber], let inode = attributes[.systemFileNumber]
        else { return nil }
        return "\(device):\(inode)"
    }

    private static func hasPlaceholderIdentity(_ frame: PresentationFrame) -> Bool {
        frame.identity.sourceFingerprint.isBrowsingPlaceholder
            || frame.signature.source.sourceFingerprint.isBrowsingPlaceholder
    }

    private static func hasPlaceholderIdentity(_ frame: PresentationFrameMetadata) -> Bool {
        frame.identity.sourceFingerprint.isBrowsingPlaceholder
            || frame.signature.source.sourceFingerprint.isBrowsingPlaceholder
    }

    /// Corruption removes exactly this entry. An unsupported container version or an unreadable
    /// file is left alone: the former is replaced by the next write, the latter may be transient.
    private func discardIfDamaged(_ error: PresentationFrameEnvelope.DecodeError, hash: String) {
        switch error {
        case .unsupportedVersion, .unreadable: return
        default: remove(hash: hash)
        }
    }

    private func discardIfDamaged(_ error: any Error, hash: String) {
        if let error = error as? PresentationFrameEnvelope.DecodeError {
            discardIfDamaged(error, hash: hash)
        }
    }

    private func enforceCap(protecting justWritten: String? = nil) {
        guard totalBytes > capBytes else { return }
        let candidates = entries
            .filter { $0.key != justWritten && !pinned.contains($0.key) }
            .sorted { $0.value.lastAccess < $1.value.lastAccess }
        for (hash, _) in candidates {
            guard totalBytes > capBytes else { break }
            remove(hash: hash)
        }
    }

    @discardableResult
    private func loadIndex() -> Bool {
        if didLoadIndex {
            Task { [weak self] in await self?.schedulePlaceholderSweep() }
            return true
        }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let files = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )
            var legacy: [URL] = []
            for url in files {
                let name = url.lastPathComponent
                if url.pathExtension == PresentationFrameEnvelope.fileExtension {
                    guard let values = try? url.resourceValues(
                        forKeys: [.fileSizeKey, .contentModificationDateKey]
                    ), let size = values.fileSize.map(Int64.init) else { continue }
                    let hash = url.deletingPathExtension().lastPathComponent
                    entries[hash] = Entry(
                        size: size, lastAccess: values.contentModificationDate ?? .distantPast
                    )
                    totalBytes += size
                } else if name == "version"
                    || (name.hasPrefix("preview-") && url.pathExtension.lowercased() == "jpg") {
                    legacy.append(url)
                }
            }
            didLoadIndex = true
            enforceCap()
            scheduleLegacyCleanup(legacy)
            Task { [weak self] in await self?.schedulePlaceholderSweep() }
            return true
        } catch {
            return false
        }
    }

    private func schedulePlaceholderSweep() async {
        guard !placeholderSweepScheduled, !placeholderSweepCompletedPass, let workScheduler
        else { return }
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
        placeholderSweepHasMore = sweepPlaceholderBatch(maxFiles: 8)
    }

    private func placeholderSweepFinished(outcome: ImageWorkScheduler.TerminalOutcome) async {
        placeholderSweepScheduled = false
        if outcome == .completed, placeholderSweepHasMore { await schedulePlaceholderSweep() }
    }

    /// Exact-key JPEGs from the previous cache are never read. They are deleted a few at a time,
    /// yielding to higher-priority scheduler work between batches.
    private func scheduleLegacyCleanup(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        legacyCleanupTask = Task {
            var remaining = urls[...]
            while !remaining.isEmpty, !Task.isCancelled {
                for url in remaining.prefix(16) { try? FileManager.default.removeItem(at: url) }
                remaining = remaining.dropFirst(16)
                await Task.yield()
            }
        }
    }
}

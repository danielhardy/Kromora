import Foundation
import Observation

/// Owns the value-only editor session boundary.
///
/// `AppViewModel` remains the composition root and the owner of the currently published
/// `EditDocument`, because render scheduling and source fences are presentation concerns. This
/// coordinator owns the state that makes an edit session durable and reversible: per-photo
/// in-memory sessions, undo/redo history, and session revisions.
///
/// No Core Image, AppKit, renderer, or persistence actor crosses this boundary. Callers provide
/// and receive `EditDocument`/`PhotoEditSession` values, which makes this workflow testable without
/// constructing the application model.
@MainActor
@Observable
final class EditorDocumentCoordinator {
    /// Named working-set defaults (docs/EDITOR_SESSION_RETENTION.md). Only clean, inactive,
    /// unpinned sessions are ever evicted, so the resident set may exceed these under pressure.
    static let defaultMaximumResidentSessions = 32
    static let defaultMaximumResidentSessionBytes = 192 * 1024 * 1024

    /// One resident photo: the session, its fence revision, its cached cost, and its recency.
    private struct Entry {
        var session: PhotoEditSession
        var revision: UInt64
        var documentCost: Int
        var tick: UInt64

        /// `(1 + undo + redo) x documentCost`; an open gesture group is charged separately.
        var cost: Int { (1 + session.history.undoCount + session.history.redoCount) * documentCost }
    }

    private(set) var activeHistory = EditHistory()
    @ObservationIgnored private var entries: [PhotoAssetID: Entry] = [:]
    @ObservationIgnored private var nextRevision: UInt64 = 0
    @ObservationIgnored private var nextTick: UInt64 = 0
    @ObservationIgnored private var activeAssetID: PhotoAssetID?
    /// Cost of the open gesture group's undo point, charged to the active (pinned) session.
    @ObservationIgnored private var activeGroupingCost = 0

    @ObservationIgnored let maximumResidentSessions: Int
    @ObservationIgnored let maximumResidentSessionBytes: Int
    /// Assets that must stay resident besides the active one (outstanding source requests).
    @ObservationIgnored var pinnedAssetIDs: () -> Set<PhotoAssetID> = { [] }
    /// Whether an asset has unsaved, queued, in-flight, or failed-save edits.
    @ObservationIgnored var isDirty: (PhotoAssetID) -> Bool = { _ in false }

    private(set) var peakResidentSessions = 0
    private(set) var evictionDeferrals = 0

    init(
        maximumResidentSessions: Int = EditorDocumentCoordinator.defaultMaximumResidentSessions,
        maximumResidentSessionBytes: Int = EditorDocumentCoordinator.defaultMaximumResidentSessionBytes
    ) {
        self.maximumResidentSessions = maximumResidentSessions
        self.maximumResidentSessionBytes = maximumResidentSessionBytes
    }

    var canUndo: Bool { activeHistory.canUndo }
    var canRedo: Bool { activeHistory.canRedo }
    var undoActionName: String? { activeHistory.undoActionName }
    var redoActionName: String? { activeHistory.redoActionName }
    var undoDepth: Int { activeHistory.undoCount }
    var isGrouping: Bool { activeHistory.isGrouping }

    /// Retention diagnostics: how many photos hold an in-memory session, and how many
    /// undo/redo entries those sessions retain in total (the active history included).
    var retainedSessionCount: Int { entries.count }
    var retainedHistoryEntryCount: Int {
        entries.reduce(0) { $0 + $1.value.session.history.undoCount + $1.value.session.history.redoCount }
    }
    /// Deterministic payload estimate across resident sessions plus any open gesture group.
    var estimatedResidentBytes: Int {
        entries.reduce(activeGroupingCost) { $0 + $1.value.cost }
    }

    func session(for assetID: PhotoAssetID) -> PhotoEditSession? {
        entries[assetID]?.session
    }

    /// The resident entry's revision; absent means `0` (the durable record is authoritative).
    func revision(for assetID: PhotoAssetID) -> UInt64 {
        entries[assetID]?.revision ?? 0
    }

    /// Select the in-memory history that belongs to a source. The published document itself stays
    /// in `AppViewModel`; this method only changes the value-state companion for that document.
    func activate(session: PhotoEditSession?, for assetID: PhotoAssetID? = nil) {
        activeHistory = session?.history ?? EditHistory()
        activeAssetID = assetID
        activeGroupingCost = 0
        if let assetID { touch(assetID) }
    }

    /// Adopt a durable document after a cold source load. Loading a persisted document starts a
    /// fresh in-memory undo stack, matching the historical AppViewModel behavior.
    func adoptStoredDocument(_ document: EditDocument, for assetID: PhotoAssetID) {
        activeHistory = EditHistory()
        activeGroupingCost = 0
        store(
            PhotoEditSession(document: document, history: activeHistory),
            revision: entries[assetID]?.revision ?? 0, for: assetID)
    }

    func adoptHistoryPosition(
        _ document: EditDocument,
        priorDocuments: [EditDocument],
        for assetID: PhotoAssetID
    ) {
        activeHistory = EditHistory()
        activeGroupingCost = 0
        activeHistory.adoptTimeline(before: priorDocuments)
        nextRevision &+= 1
        store(
            PhotoEditSession(document: document, history: activeHistory),
            revision: nextRevision, for: assetID)
    }

    func clearActiveHistory() {
        activeHistory = EditHistory()
        activeAssetID = nil
        activeGroupingCost = 0
    }

    /// Record the latest in-memory document for a photo and return its new session revision.
    /// Revision changes are used by source loading to reject a late durable read that would
    /// otherwise overwrite an edit made while decoding is still in flight.
    @discardableResult
    func commit(document: EditDocument, for assetID: PhotoAssetID) -> UInt64 {
        nextRevision &+= 1
        store(
            PhotoEditSession(document: document, history: activeHistory),
            revision: nextRevision, for: assetID)
        return nextRevision
    }

    func removeSession(for assetID: PhotoAssetID) {
        entries.removeValue(forKey: assetID)
    }

    func removeSessions(for assetIDs: some Sequence<PhotoAssetID>) {
        for assetID in assetIDs {
            removeSession(for: assetID)
        }
    }

    func beginGrouping(document: EditDocument) {
        if !activeHistory.isGrouping { activeGroupingCost = document.estimatedRetentionBytes }
        activeHistory.beginGrouping(document: document)
    }

    /// Ends a gesture group and reports whether it contained a change. The caller owns the
    /// application-level persistence boundary, so it can force a checkpoint at that exact point.
    @discardableResult
    func endGrouping(document: EditDocument) -> Bool {
        let wasGrouping = activeHistory.isGrouping
        activeHistory.endGrouping(document: document)
        activeGroupingCost = 0
        return wasGrouping
    }

    func recordChange(from old: EditDocument, to new: EditDocument) {
        activeHistory.recordChange(from: old, to: new)
    }

    /// Apply a copied document to a destination that is not currently open. This keeps the
    /// destination's history and session revision in the same owner as the active editor history.
    /// `durableBase` is the saved document of a non-resident photo, so history starts from it.
    /// The caller must queue persistence for the result and then call `evictIfNeeded()`.
    @discardableResult
    func apply(
        _ document: EditDocument, to assetID: PhotoAssetID, durableBase: EditDocument? = nil
    ) -> Bool {
        var session = entries[assetID]?.session
            ?? PhotoEditSession(document: durableBase ?? EditDocument(), history: EditHistory())
        session.history.endGrouping(document: session.document)
        guard session.document != document else { return false }
        session.history.recordChange(from: session.document, to: document)
        session.document = document
        nextRevision &+= 1
        store(session, revision: nextRevision, for: assetID)
        return true
    }

    // MARK: - Bounded working set

    private func touch(_ assetID: PhotoAssetID) {
        guard entries[assetID] != nil else { return }
        nextTick &+= 1
        entries[assetID]?.tick = nextTick
    }

    private func store(_ session: PhotoEditSession, revision: UInt64, for assetID: PhotoAssetID) {
        nextTick &+= 1
        entries[assetID] = Entry(
            session: session, revision: revision,
            documentCost: session.document.estimatedRetentionBytes, tick: nextTick)
        peakResidentSessions = max(peakResidentSessions, entries.count)
    }

    /// Evict the least recently used eligible sessions until both budgets hold. Eligible means
    /// clean, inactive, not grouping, and not pinned by an outstanding source request. Unsaved
    /// or pinned sessions are never dropped, so the set can stay over budget.
    func evictIfNeeded() {
        let pinned = pinnedAssetIDs()
        while entries.count > maximumResidentSessions
            || estimatedResidentBytes > maximumResidentSessionBytes
        {
            let candidate = entries
                .filter { assetID, entry in
                    assetID != activeAssetID && !pinned.contains(assetID)
                        && !entry.session.history.isGrouping && !isDirty(assetID)
                }
                .min { $0.value.tick < $1.value.tick }
            guard let candidate else {
                evictionDeferrals += 1
                return
            }
            entries.removeValue(forKey: candidate.key)
        }
    }

    func undo(current: EditDocument) -> EditDocument? {
        activeHistory.undo(current: current)
    }

    func redo(current: EditDocument) -> EditDocument? {
        activeHistory.redo(current: current)
    }
}

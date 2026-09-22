import Foundation
import Combine

/// Owns the value-only editor session boundary.
///
/// `AppViewModel` remains the composition root and the owner of the currently published
/// `EditDocument`, because render scheduling and source fences are presentation concerns. This
/// coordinator owns the state that makes an edit session durable and reversible: per-photo
/// in-memory sessions, undo/redo history, session revisions, and the copy/paste payload.
///
/// No Core Image, AppKit, renderer, or persistence actor crosses this boundary. Callers provide
/// and receive `EditDocument`/`PhotoEditSession` values, which makes this workflow testable without
/// constructing the application model.
@MainActor
final class EditorDocumentCoordinator: ObservableObject {
    @Published private(set) var clipboard: EditClipboardPayload?
    @Published private(set) var clipboardCategories: Set<EditClipboardPayload.Category> =
        Set(EditClipboardPayload.Category.allCases)

    private(set) var activeHistory = EditHistory()
    private var sessions: [PhotoAssetID: PhotoEditSession] = [:]
    private var sessionRevisions: [PhotoAssetID: UInt64] = [:]
    private var nextRevision: UInt64 = 0

    var canPaste: Bool { clipboard != nil }
    var canUndo: Bool { activeHistory.canUndo }
    var canRedo: Bool { activeHistory.canRedo }
    var undoDepth: Int { activeHistory.undoCount }

    func session(for assetID: PhotoAssetID) -> PhotoEditSession? {
        sessions[assetID]
    }

    func revision(for assetID: PhotoAssetID) -> UInt64 {
        sessionRevisions[assetID] ?? 0
    }

    /// Select the in-memory history that belongs to a source. The published document itself stays
    /// in `AppViewModel`; this method only changes the value-state companion for that document.
    func activate(session: PhotoEditSession?) {
        activeHistory = session?.history ?? EditHistory()
    }

    /// Adopt a durable document after a cold source load. Loading a persisted document starts a
    /// fresh in-memory undo stack, matching the historical AppViewModel behavior.
    func adoptStoredDocument(_ document: EditDocument, for assetID: PhotoAssetID) {
        activeHistory = EditHistory()
        sessions[assetID] = PhotoEditSession(document: document, history: activeHistory)
    }

    func clearActiveHistory() {
        activeHistory = EditHistory()
    }

    /// Record the latest in-memory document for a photo and return its new session revision.
    /// Revision changes are used by source loading to reject a late durable read that would
    /// otherwise overwrite an edit made while decoding is still in flight.
    @discardableResult
    func commit(document: EditDocument, for assetID: PhotoAssetID) -> UInt64 {
        sessions[assetID] = PhotoEditSession(document: document, history: activeHistory)
        nextRevision &+= 1
        sessionRevisions[assetID] = nextRevision
        return nextRevision
    }

    func removeSession(for assetID: PhotoAssetID) {
        sessions.removeValue(forKey: assetID)
        sessionRevisions.removeValue(forKey: assetID)
    }

    func removeSessions(for assetIDs: some Sequence<PhotoAssetID>) {
        for assetID in assetIDs {
            removeSession(for: assetID)
        }
    }

    func beginGrouping(document: EditDocument) {
        activeHistory.beginGrouping(document: document)
    }

    /// Ends a gesture group and reports whether it contained a change. The caller owns the
    /// application-level persistence boundary, so it can force a checkpoint at that exact point.
    @discardableResult
    func endGrouping(document: EditDocument) -> Bool {
        let wasGrouping = activeHistory.isGrouping
        activeHistory.endGrouping(document: document)
        return wasGrouping
    }

    func recordChange(from old: EditDocument, to new: EditDocument) {
        activeHistory.recordChange(from: old, to: new)
    }

    /// Apply a copied document to a destination that is not currently open. This keeps the
    /// destination's history and session revision in the same owner as the active editor history.
    @discardableResult
    func apply(_ document: EditDocument, to assetID: PhotoAssetID) -> Bool {
        var session = sessions[assetID] ?? PhotoEditSession()
        session.history.endGrouping(document: session.document)
        guard session.document != document else { return false }
        session.history.recordChange(from: session.document, to: document)
        session.document = document
        sessions[assetID] = session
        nextRevision &+= 1
        sessionRevisions[assetID] = nextRevision
        return true
    }

    func undo(current: EditDocument) -> EditDocument? {
        activeHistory.undo(current: current)
    }

    func redo(current: EditDocument) -> EditDocument? {
        activeHistory.redo(current: current)
    }

    func copy(
        document: EditDocument,
        categories: Set<EditClipboardPayload.Category> = Set(EditClipboardPayload.Category.allCases)
    ) {
        clipboard = EditClipboardPayload(document: document)
        clipboardCategories = categories
    }

}

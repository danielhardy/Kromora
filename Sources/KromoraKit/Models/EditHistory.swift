import Foundation

/// Bounded undo/redo state for one photo.
///
/// History stores only value-state documents. Rendered images and Core Image objects never enter
/// the history, so a long editing session has a predictable memory cost.
struct EditHistory: Sendable, Equatable {
    static let maximumDepth = 100

    /// A document to return to, plus the photographer-facing name of the edit that left it.
    /// `actionName` is nil when no single control or section describes the edit (and for history
    /// restored from durable revisions), so the menu falls back to plain "Undo"/"Redo".
    struct Entry: Sendable, Equatable {
        let document: EditDocument
        let actionName: String?
    }

    private(set) var undoSnapshots: [Entry] = []
    private(set) var redoSnapshots: [Entry] = []
    private var groupingStart: EditDocument?

    /// Name of the edit Undo would revert.
    var undoActionName: String? { undoSnapshots.last?.actionName }
    /// Name of the edit Redo would reapply.
    var redoActionName: String? { redoSnapshots.last?.actionName }

    var canUndo: Bool { !undoSnapshots.isEmpty }
    var canRedo: Bool { !redoSnapshots.isEmpty }
    var isGrouping: Bool { groupingStart != nil }
    var undoCount: Int { undoSnapshots.count }
    var redoCount: Int { redoSnapshots.count }

    mutating func beginGrouping(document: EditDocument) {
        if groupingStart == nil { groupingStart = document }
    }

    mutating func endGrouping(document: EditDocument) {
        guard let start = groupingStart else { return }
        groupingStart = nil
        guard start != document else { return }
        appendUndo(start, producing: document)
    }

    mutating func recordChange(from old: EditDocument, to new: EditDocument) {
        guard old != new else { return }
        redoSnapshots.removeAll(keepingCapacity: true)
        guard groupingStart == nil else { return }
        appendUndo(old, producing: new)
    }

    mutating func adoptTimeline(before documents: [EditDocument]) {
        undoSnapshots = documents.suffix(Self.maximumDepth).map { Entry(document: $0, actionName: nil) }
        redoSnapshots.removeAll(keepingCapacity: true)
        groupingStart = nil
    }

    mutating func undo(current: EditDocument) -> EditDocument? {
        guard let previous = undoSnapshots.popLast() else { return nil }
        appendRedo(current, named: previous.actionName)
        return previous.document
    }

    mutating func redo(current: EditDocument) -> EditDocument? {
        guard let next = redoSnapshots.popLast() else { return nil }
        undoSnapshots.append(Entry(document: current, actionName: next.actionName))
        trim(&undoSnapshots)
        return next.document
    }

    private mutating func appendUndo(_ document: EditDocument, producing edited: EditDocument) {
        undoSnapshots.append(Entry(document: document, actionName: EditActionName.make(from: document, to: edited)))
        trim(&undoSnapshots)
    }

    private mutating func appendRedo(_ document: EditDocument, named actionName: String?) {
        redoSnapshots.append(Entry(document: document, actionName: actionName))
        trim(&redoSnapshots)
    }

    private func trim(_ snapshots: inout [Entry]) {
        let excess = snapshots.count - Self.maximumDepth
        if excess > 0 { snapshots.removeFirst(excess) }
    }
}

/// The unsaved edit state retained for one photo while the app is open.
struct PhotoEditSession: Sendable, Equatable {
    var document = EditDocument()
    var history = EditHistory()
}

import Foundation
import Observation

/// Value snapshot of a selected destination; source classification stays at the library adapter.
struct EditClipboardTarget: Sendable {
    let sourceReference: EditSourceReference
    let isRAW: Bool
}

/// The published document and application side effects stay at the composition root. The active
/// source reference describes the document on screen even while selection starts another load.
@MainActor
protocol EditClipboardDestination: AnyObject {
    var clipboardHasCopySource: Bool { get }
    var clipboardSourceName: String { get }
    var clipboardDocument: EditDocument { get }
    var clipboardActiveSourceReference: EditSourceReference? { get }
    var clipboardActiveDestinationIsRAW: Bool? { get }
    var clipboardSelectedTargets: [EditClipboardTarget] { get }

    func updateDocument(_ transform: (inout EditDocument) -> Void)
    func endUndoGrouping()
    func activateClipboardAsset(_ assetID: PhotoAssetID)
    func setClipboardStatus(_ message: String)
    func persistInactiveClipboardDocument(_ document: EditDocument, for reference: EditSourceReference)
    /// The durable edit for a destination with no resident session. Paste applies to this base so
    /// a category-limited paste never replaces the saved categories with neutral values.
    func loadClipboardBase(for reference: EditSourceReference) async -> EditDocumentLoadResult
    func flushClipboardPersistence()
}

/// Owns clipboard values, selective-copy presentation/preferences, and single/batch paste routing.
/// Sessions and undo remain in `EditorDocumentCoordinator`; active edits always use updateDocument.
@MainActor
@Observable
final class EditClipboardCoordinator {
    private(set) var clipboard: EditClipboardPayload?
    private(set) var clipboardCategories: Set<EditClipboardPayload.Category> =
        Set(EditClipboardPayload.Category.allCases)
    var isSelectiveCopyDialogPresented = false
    var selectiveCopyCategories: Set<EditClipboardPayload.Category>

    @ObservationIgnored weak var destination: (any EditClipboardDestination)?
    @ObservationIgnored private let editor: EditorDocumentCoordinator
    @ObservationIgnored private let settings: KromoraSettings
    @ObservationIgnored private var pasteTask: Task<Void, Never>?

    init(
        editor: EditorDocumentCoordinator,
        settings: KromoraSettings,
        destination: (any EditClipboardDestination)? = nil
    ) {
        self.editor = editor
        self.settings = settings
        self.destination = destination
        self.selectiveCopyCategories = settings.lastCopyCategories
    }

    var canPaste: Bool { clipboard != nil }

    func presentSelectiveCopyDialog() {
        guard let destination else { return }
        guard destination.clipboardHasCopySource else {
            destination.setClipboardStatus("Open an image first")
            return
        }
        selectiveCopyCategories = settings.lastCopyCategories
        isSelectiveCopyDialogPresented = true
    }

    func confirmSelectiveCopy() {
        guard let destination else { return }
        guard destination.clipboardHasCopySource else {
            isSelectiveCopyDialogPresented = false
            destination.setClipboardStatus("Open an image first")
            return
        }
        settings.lastCopyCategories = selectiveCopyCategories
        copy(document: destination.clipboardDocument, categories: selectiveCopyCategories)
        isSelectiveCopyDialogPresented = false
        let summary = categorySummary(allCategories: "all edits")
        destination.setClipboardStatus("Copied \(summary) from \(destination.clipboardSourceName)")
    }

    func cancelSelectiveCopy() { isSelectiveCopyDialogPresented = false }

    /// Neutral optional RAW settings never transfer the source photo's as-shot decoder seed.
    func copyAllEdits() {
        guard let destination else { return }
        guard destination.clipboardHasCopySource else {
            destination.setClipboardStatus("Open an image first")
            return
        }
        copy(document: destination.clipboardDocument, categories: Set(EditClipboardPayload.Category.allCases))
        destination.setClipboardStatus("Copied all edits from \(destination.clipboardSourceName)")
    }

    private func copy(document: EditDocument, categories: Set<EditClipboardPayload.Category>) {
        clipboard = EditClipboardPayload(document: document)
        clipboardCategories = categories
    }

    /// Non-active destinations get their own session history and forced persistence snapshot,
    /// without opening a source or mutating the published active document.
    func pasteEdits() {
        guard let destination else { return }
        guard let clipboard else {
            destination.setClipboardStatus("Copy edits first")
            return
        }
        let targets = destination.clipboardSelectedTargets
        if targets.isEmpty {
            guard let isRAW = destination.clipboardActiveDestinationIsRAW else {
                destination.setClipboardStatus("Open an image first")
                return
            }
            destination.endUndoGrouping()
            applyToActiveDocument(clipboard, isRAW: isRAW, destination: destination)
            destination.setClipboardStatus(pasteCompletionMessage(photoCount: 1))
            return
        }

        destination.endUndoGrouping()
        var pastedCount = 0
        var deferred: [EditClipboardTarget] = []
        for target in targets {
            switch pasteOrDefer(target, clipboard: clipboard, destination: destination) {
            case .pasted: pastedCount += 1
            case .unchanged: break
            case .needsDurableBase: deferred.append(target)
            }
        }
        guard !deferred.isEmpty else {
            finishPaste(pastedCount: pastedCount, skipped: [], destination: destination)
            return
        }
        pasteTask = Task { [weak self] in
            var pasted = pastedCount
            var skipped: [String] = []
            for target in deferred {
                guard let self, let destination = self.destination else { return }
                let reference = target.sourceReference
                let result = await destination.loadClipboardBase(for: reference)
                guard !Task.isCancelled else { return }
                guard result.isUsableForPrefetch else {
                    skipped.append(reference.url?.lastPathComponent ?? reference.assetID.description)
                    continue
                }
                // A session may have appeared (or the photo become active) while the read was
                // in flight; the resident value is newer than the durable one.
                switch self.pasteOrDefer(
                    target, clipboard: clipboard, destination: destination,
                    durableBase: result.found ? result.document : EditDocument()
                ) {
                case .pasted: pasted += 1
                case .unchanged, .needsDurableBase: break
                }
            }
            guard let self, let destination = self.destination else { return }
            self.finishPaste(pastedCount: pasted, skipped: skipped, destination: destination)
        }
    }

    private enum PasteOutcome { case pasted, unchanged, needsDurableBase }

    /// Paste to one target. With no resident session and no `durableBase`, the target needs an
    /// asynchronous durable read first; a neutral or active-photo base is never substituted.
    private func pasteOrDefer(
        _ target: EditClipboardTarget, clipboard: EditClipboardPayload,
        destination: any EditClipboardDestination, durableBase: EditDocument? = nil
    ) -> PasteOutcome {
        let reference = target.sourceReference
        if destination.clipboardActiveSourceReference == reference {
            // Selection can advance before source preparation finishes. Restore the session
            // that owns the displayed source, rather than trusting the selected active ID.
            destination.activateClipboardAsset(reference.assetID)
            editor.activate(session: editor.session(for: reference.assetID), for: reference.assetID)
            applyToActiveDocument(clipboard, isRAW: target.isRAW, destination: destination)
            return .pasted
        }
        let base: EditDocument
        if let resident = editor.session(for: reference.assetID)?.document {
            base = resident
        } else if let durableBase {
            base = durableBase
        } else {
            return .needsDurableBase
        }
        let updated = clipboard.applying(
            to: base, destinationIsRAW: target.isRAW, categories: clipboardCategories)
        guard editor.apply(updated, to: reference.assetID, durableBase: base) else { return .unchanged }
        destination.persistInactiveClipboardDocument(updated, for: reference)
        return .pasted
    }

    private func finishPaste(
        pastedCount: Int, skipped: [String], destination: any EditClipboardDestination
    ) {
        var message = pasteCompletionMessage(photoCount: pastedCount)
        if !skipped.isEmpty {
            message += "; skipped \(skipped.count) whose saved edit could not be read: "
                + skipped.joined(separator: ", ")
        }
        destination.setClipboardStatus(message)
        destination.flushClipboardPersistence()
    }

    /// Suspends until a paste waiting on durable reads has finished.
    func waitForPendingPaste() async { await pasteTask?.value }

    /// Abandon a paste still waiting on durable reads; called by the owner during shutdown.
    func stop() {
        pasteTask?.cancel()
        pasteTask = nil
    }

    private func applyToActiveDocument(
        _ clipboard: EditClipboardPayload, isRAW: Bool,
        destination: any EditClipboardDestination
    ) {
        let updated = clipboard.applying(
            to: destination.clipboardDocument, destinationIsRAW: isRAW,
            categories: clipboardCategories
        )
        destination.updateDocument { $0 = updated }
    }

    private func pasteCompletionMessage(photoCount: Int) -> String {
        let destination = photoCount == 1 ? "1 photo" : "\(photoCount) photos"
        let summary = categorySummary(allCategories: "edits")
        let result = photoCount > 0 ? "Pasted \(summary) to \(destination)" : "Pasted \(summary)"
        return clipboardCategories.contains(.retouch)
            ? "\(result); retouch sources resolve per photo" : result
    }

    private func categorySummary(allCategories: String) -> String {
        if clipboardCategories == Set(EditClipboardPayload.Category.allCases) { return allCategories }
        return clipboardCategories.sorted { $0.title < $1.title }.map(\.title).joined(separator: ", ")
    }
}

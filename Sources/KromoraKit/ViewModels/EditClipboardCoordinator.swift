import Combine
import Foundation

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
    func flushClipboardPersistence()
}

/// Owns clipboard values, selective-copy presentation/preferences, and single/batch paste routing.
/// Sessions and undo remain in `EditorDocumentCoordinator`; active edits always use updateDocument.
@MainActor
final class EditClipboardCoordinator: ObservableObject {
    @Published private(set) var clipboard: EditClipboardPayload?
    @Published private(set) var clipboardCategories: Set<EditClipboardPayload.Category> =
        Set(EditClipboardPayload.Category.allCases)
    @Published var isSelectiveCopyDialogPresented = false
    @Published var selectiveCopyCategories: Set<EditClipboardPayload.Category>

    weak var destination: (any EditClipboardDestination)?
    private let editor: EditorDocumentCoordinator
    private let settings: KromoraSettings

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
        for target in targets {
            let reference = target.sourceReference
            if destination.clipboardActiveSourceReference == reference {
                // Selection can advance before source preparation finishes. Restore the session
                // that owns the displayed source, rather than trusting the selected active ID.
                destination.activateClipboardAsset(reference.assetID)
                editor.activate(session: editor.session(for: reference.assetID))
                applyToActiveDocument(clipboard, isRAW: target.isRAW, destination: destination)
            } else {
                let updated = clipboard.applying(
                    to: editor.session(for: reference.assetID)?.document ?? EditDocument(),
                    destinationIsRAW: target.isRAW, categories: clipboardCategories
                )
                guard editor.apply(updated, to: reference.assetID) else { continue }
                destination.persistInactiveClipboardDocument(updated, for: reference)
            }
            pastedCount += 1
        }
        destination.setClipboardStatus(pasteCompletionMessage(photoCount: pastedCount))
        destination.flushClipboardPersistence()
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

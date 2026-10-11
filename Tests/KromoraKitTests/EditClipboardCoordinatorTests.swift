import XCTest

@testable import KromoraKit

@MainActor
final class EditClipboardCoordinatorTests: TempDirectoryTestCase {
    private final class Destination: EditClipboardDestination {
        let editor: EditorDocumentCoordinator
        var clipboardHasCopySource = true
        var clipboardSourceName = "Source"
        var clipboardDocument = EditDocument()
        var clipboardActiveSourceReference: EditSourceReference?
        var clipboardActiveDestinationIsRAW: Bool? = false
        var clipboardSelectedTargets: [EditClipboardTarget] = []
        var selectedActiveID: PhotoAssetID?
        var status = ""
        var documentUpdates = 0
        var groupingEnds = 0
        var flushes = 0
        var persisted: [(document: EditDocument, reference: EditSourceReference)] = []

        init(editor: EditorDocumentCoordinator) { self.editor = editor }

        func updateDocument(_ transform: (inout EditDocument) -> Void) {
            let old = clipboardDocument
            transform(&clipboardDocument)
            editor.recordChange(from: old, to: clipboardDocument)
            if let assetID = clipboardActiveSourceReference?.assetID {
                editor.commit(document: clipboardDocument, for: assetID)
            }
            documentUpdates += 1
        }
        func endUndoGrouping() {
            editor.endGrouping(document: clipboardDocument)
            groupingEnds += 1
        }
        func activateClipboardAsset(_ assetID: PhotoAssetID) { selectedActiveID = assetID }
        func setClipboardStatus(_ message: String) { status = message }
        func persistInactiveClipboardDocument(_ document: EditDocument, for reference: EditSourceReference) {
            persisted.append((document, reference))
        }
        func flushClipboardPersistence() { flushes += 1 }
    }

    private func makeWorkflow() -> (EditClipboardCoordinator, Destination, KromoraSettings) {
        let editor = EditorDocumentCoordinator()
        let settings = KromoraSettings(
            preferences: makeTestUserDefaults(), userLookFolderURL: tempDirectory
        )
        let destination = Destination(editor: editor)
        let workflow = EditClipboardCoordinator(editor: editor, settings: settings, destination: destination)
        return (workflow, destination, settings)
    }

    private func reference(_ name: String) -> EditSourceReference {
        let url = tempDirectory.appendingPathComponent(name)
        return EditSourceReference(assetID: .file(url), url: url)
    }

    func testCopyRequiresSourceAndPasteRequiresClipboardAndDestination() {
        let (workflow, destination, _) = makeWorkflow()
        workflow.pasteEdits()
        XCTAssertEqual(destination.status, "Copy edits first")
        destination.clipboardHasCopySource = false
        workflow.presentSelectiveCopyDialog()
        XCTAssertFalse(workflow.isSelectiveCopyDialogPresented)
        workflow.copyAllEdits()
        XCTAssertNil(workflow.clipboard)
        XCTAssertEqual(destination.status, "Open an image first")

        destination.clipboardHasCopySource = true
        workflow.copyAllEdits()
        XCTAssertTrue(workflow.canPaste)
        destination.clipboardActiveDestinationIsRAW = nil
        workflow.pasteEdits()
        XCTAssertEqual(destination.status, "Open an image first")
        XCTAssertEqual(destination.groupingEnds, 0)
        XCTAssertEqual(destination.documentUpdates, 0)
        XCTAssertEqual(destination.flushes, 0)
    }

    func testSelectiveDialogReseedsPreferencesAndCancelPreservesClipboard() {
        let (workflow, destination, settings) = makeWorkflow()
        settings.lastCopyCategories = [.light, .crop]
        destination.clipboardDocument.light.exposure = 0.8
        workflow.presentSelectiveCopyDialog()
        XCTAssertEqual(workflow.selectiveCopyCategories, [.light, .crop])
        workflow.selectiveCopyCategories = [.light, .color]
        workflow.confirmSelectiveCopy()
        XCTAssertFalse(workflow.isSelectiveCopyDialogPresented)
        XCTAssertEqual(settings.lastCopyCategories, [.light, .color])
        XCTAssertEqual(workflow.clipboardCategories, [.light, .color])
        XCTAssertEqual(destination.status, "Copied Color, Light from Source")
        let copied = workflow.clipboard

        workflow.presentSelectiveCopyDialog()
        workflow.selectiveCopyCategories = [.lut]
        workflow.cancelSelectiveCopy()
        XCTAssertFalse(workflow.isSelectiveCopyDialogPresented)
        XCTAssertEqual(workflow.clipboard, copied)
        XCTAssertEqual(settings.lastCopyCategories, [.light, .color])
        workflow.presentSelectiveCopyDialog()
        XCTAssertEqual(workflow.selectiveCopyCategories, [.light, .color])
        destination.clipboardHasCopySource = false
        workflow.confirmSelectiveCopy()
        XCTAssertFalse(workflow.isSelectiveCopyDialogPresented)
        XCTAssertEqual(workflow.clipboard, copied)
        XCTAssertEqual(settings.lastCopyCategories, [.light, .color])
        XCTAssertEqual(destination.status, "Open an image first")
    }

    func testActivePasteUsesDocumentCommitAndKeepsUncheckedStagesAndUndo() {
        let (workflow, destination, _) = makeWorkflow()
        destination.clipboardDocument.light.exposure = 0.8
        destination.clipboardDocument.color.vibrance = 0.7
        workflow.presentSelectiveCopyDialog()
        workflow.selectiveCopyCategories = [.light]
        workflow.confirmSelectiveCopy()
        let copied = workflow.clipboard

        destination.clipboardActiveSourceReference = reference("active.png")
        destination.clipboardDocument.light.exposure = -0.4
        destination.clipboardDocument.color.vibrance = -0.3
        let before = destination.clipboardDocument
        workflow.pasteEdits()
        XCTAssertEqual(destination.clipboardDocument.light.exposure, 0.8)
        XCTAssertEqual(destination.clipboardDocument.color.vibrance, -0.3)
        XCTAssertEqual(destination.documentUpdates, 1)
        XCTAssertEqual(destination.groupingEnds, 1)
        XCTAssertEqual(destination.editor.undo(current: destination.clipboardDocument), before)
        XCTAssertEqual(workflow.clipboard, copied)
        XCTAssertEqual(destination.status, "Pasted Light to 1 photo")
        XCTAssertTrue(destination.persisted.isEmpty)
        XCTAssertEqual(destination.flushes, 0)
    }

    func testBatchUsesDisplayedSourceIdentityDuringSelectionTransitionAndPreservesPerPhotoHistory() {
        let (workflow, destination, _) = makeWorkflow()
        var sourceDocument = EditDocument(rawDevelop: RAWDevelopSettings(exposure: 1.25))
        sourceDocument.light.exposure = 0.8
        destination.clipboardDocument = sourceDocument
        workflow.copyAllEdits()
        let active = reference("displayed.png")
        let raw = reference("selected.dng")
        let unchanged = reference("unchanged.png")
        let unselected = reference("unselected.png")
        let rawBefore = EditDocument(rawDevelop: RAWDevelopSettings(baselineExposure: 0.42))
        var activeBefore = EditDocument()
        activeBefore.light.exposure = -0.2
        destination.editor.adoptStoredDocument(activeBefore, for: active.assetID)
        destination.editor.apply(rawBefore, to: raw.assetID)
        destination.editor.apply(sourceDocument, to: unchanged.assetID)
        destination.editor.apply(activeBefore, to: unselected.assetID)
        let rawRevision = destination.editor.revision(for: raw.assetID)
        let unchangedRevision = destination.editor.revision(for: unchanged.assetID)
        destination.clipboardDocument = activeBefore
        destination.clipboardActiveSourceReference = active
        destination.selectedActiveID = raw.assetID
        destination.editor.activate(session: destination.editor.session(for: raw.assetID))
        destination.clipboardSelectedTargets = [
            EditClipboardTarget(sourceReference: active, isRAW: false),
            EditClipboardTarget(sourceReference: raw, isRAW: true),
            EditClipboardTarget(sourceReference: unchanged, isRAW: false),
        ]

        workflow.pasteEdits()

        XCTAssertEqual(destination.selectedActiveID, active.assetID)
        XCTAssertEqual(destination.documentUpdates, 1)
        XCTAssertEqual(destination.clipboardDocument.light.exposure, 0.8)
        XCTAssertEqual(destination.clipboardDocument.rawDevelop, activeBefore.rawDevelop)
        XCTAssertEqual(destination.editor.undo(current: destination.clipboardDocument), activeBefore)
        let rawSession = destination.editor.session(for: raw.assetID)
        XCTAssertEqual(rawSession?.document, sourceDocument)
        var rawHistory = rawSession?.history
        XCTAssertEqual(rawHistory?.undo(current: sourceDocument), rawBefore)
        XCTAssertGreaterThan(destination.editor.revision(for: raw.assetID), rawRevision)
        XCTAssertEqual(destination.editor.revision(for: unchanged.assetID), unchangedRevision)
        XCTAssertEqual(destination.editor.session(for: unselected.assetID)?.document, activeBefore)
        XCTAssertEqual(destination.persisted.count, 1)
        XCTAssertEqual(destination.persisted.first?.reference, raw)
        XCTAssertEqual(destination.persisted.first?.document, sourceDocument)
        XCTAssertEqual(destination.groupingEnds, 1)
        XCTAssertEqual(destination.flushes, 1)
        XCTAssertEqual(destination.status, "Pasted edits to 2 photos; retouch sources resolve per photo")
    }

    func testBatchCanPasteUnopenedPhotoWithoutActiveSourceAndSkipsNoOpWrites() {
        let (workflow, destination, _) = makeWorkflow()
        destination.clipboardDocument.light.exposure = 0.6
        workflow.copyAllEdits()
        let unopened = reference("unopened.png")
        destination.clipboardHasCopySource = false
        destination.clipboardActiveDestinationIsRAW = nil
        destination.clipboardSelectedTargets = [EditClipboardTarget(sourceReference: unopened, isRAW: false)]
        workflow.pasteEdits()
        XCTAssertEqual(destination.editor.session(for: unopened.assetID)?.document.light.exposure, 0.6)
        XCTAssertEqual(destination.documentUpdates, 0)
        XCTAssertEqual(destination.persisted.count, 1)
        let revision = destination.editor.revision(for: unopened.assetID)
        workflow.pasteEdits()
        XCTAssertEqual(destination.persisted.count, 1)
        XCTAssertEqual(destination.editor.revision(for: unopened.assetID), revision)
        XCTAssertEqual(destination.status, "Pasted edits; retouch sources resolve per photo")
        XCTAssertEqual(destination.flushes, 2)
    }
}

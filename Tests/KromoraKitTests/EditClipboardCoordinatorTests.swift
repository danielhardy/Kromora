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
        var clipboardBaseLoads = 0

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
        var durableBases: [PhotoAssetID: EditDocumentLoadResult] = [:]
        func loadClipboardBase(for reference: EditSourceReference) async -> EditDocumentLoadResult {
            clipboardBaseLoads += 1
            return durableBases[reference.assetID]
                ?? EditDocumentLoadResult(document: EditDocument(), found: false, status: .ready)
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

    func testContextSourceDialogCopiesOnlyChosenCategoriesFromDurableEdit() async {
        let (workflow, destination, settings) = makeWorkflow()
        destination.clipboardActiveSourceReference = reference("active.jpg")
        let other = reference("other.jpg")
        var stored = EditDocument()
        stored.light.exposure = 0.4
        stored.color.vibrance = 0.6
        destination.durableBases[other.assetID] = EditDocumentLoadResult(
            document: stored, found: true, status: .ready)

        workflow.presentSelectiveCopyDialog(for: other, name: "other.jpg")
        XCTAssertTrue(workflow.isSelectiveCopyDialogPresented)
        XCTAssertEqual(workflow.selectiveCopySource?.name, "other.jpg")
        workflow.selectiveCopyCategories = [.light]
        workflow.confirmSelectiveCopy()
        XCTAssertFalse(workflow.isSelectiveCopyDialogPresented)
        XCTAssertNil(workflow.selectiveCopySource)
        XCTAssertEqual(settings.lastCopyCategories, [.light])
        let copyTask = Task { @MainActor in
            while workflow.clipboard == nil { await Task.yield() }
        }
        await copyTask.value

        XCTAssertEqual(workflow.clipboard, EditClipboardPayload(document: stored))
        XCTAssertEqual(workflow.clipboardCategories, [.light])
        XCTAssertEqual(destination.status, "Copied Light from other.jpg")
    }

    func testContextSourceDialogForActivePhotoUsesLiveDocument() {
        let (workflow, destination, _) = makeWorkflow()
        let active = reference("active.jpg")
        destination.clipboardActiveSourceReference = active
        destination.clipboardDocument.light.exposure = 0.9

        workflow.presentSelectiveCopyDialog(for: active, name: "active.jpg")
        XCTAssertNil(workflow.selectiveCopySource)
        workflow.selectiveCopyCategories = [.light]
        workflow.confirmSelectiveCopy()

        XCTAssertEqual(workflow.clipboard, EditClipboardPayload(document: destination.clipboardDocument))
        XCTAssertEqual(workflow.clipboardCategories, [.light])
    }

    func testNewActiveCopySupersedesPendingContextSourceRead() async {
        let (workflow, destination, _) = makeWorkflow()
        let active = reference("active.jpg")
        destination.clipboardActiveSourceReference = active
        destination.clipboardSourceName = "active.jpg"
        destination.clipboardDocument.color.vibrance = 0.7

        let other = reference("other.jpg")
        var stored = EditDocument()
        stored.light.exposure = 0.4
        destination.durableBases[other.assetID] = EditDocumentLoadResult(
            document: stored, found: true, status: .ready)
        workflow.presentSelectiveCopyDialog(for: other, name: "other.jpg")
        workflow.selectiveCopyCategories = [.light]
        workflow.confirmSelectiveCopy()

        workflow.presentSelectiveCopyDialog(for: active, name: "active.jpg")
        workflow.selectiveCopyCategories = [.color]
        workflow.confirmSelectiveCopy()
        for _ in 0..<100 where destination.clipboardBaseLoads == 0 { await Task.yield() }
        await Task.yield()

        XCTAssertEqual(destination.clipboardBaseLoads, 1)
        XCTAssertEqual(workflow.clipboard, EditClipboardPayload(document: destination.clipboardDocument))
        XCTAssertEqual(workflow.clipboardCategories, [.color])
        XCTAssertEqual(destination.status, "Copied Color from active.jpg")
    }

    func testContextSourceCancelAndReadFailureLeaveClipboardUnchanged() async {
        let (workflow, destination, _) = makeWorkflow()
        destination.clipboardDocument.light.exposure = 0.8
        workflow.copyAllEdits()
        let copied = workflow.clipboard
        let other = reference("other.jpg")

        workflow.presentSelectiveCopyDialog(for: other, name: "other.jpg")
        workflow.cancelSelectiveCopy()
        XCTAssertNil(workflow.selectiveCopySource)
        XCTAssertEqual(workflow.clipboard, copied)

        destination.durableBases[other.assetID] = EditDocumentLoadResult(
            document: EditDocument(), found: false, status: .corrupt("bad"))
        workflow.presentSelectiveCopyDialog(for: other, name: "other.jpg")
        workflow.confirmSelectiveCopy()
        let status = destination
        let wait = Task { @MainActor in
            while status.status.hasPrefix("Copied") { await Task.yield() }
        }
        await wait.value
        XCTAssertEqual(destination.status, "Could not read the edits of other.jpg")
        XCTAssertEqual(workflow.clipboard, copied)
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

    func testBatchCanPasteUnopenedPhotoWithoutActiveSourceAndSkipsNoOpWrites() async {
        let (workflow, destination, _) = makeWorkflow()
        destination.clipboardDocument.light.exposure = 0.6
        workflow.copyAllEdits()
        let unopened = reference("unopened.png")
        destination.clipboardHasCopySource = false
        destination.clipboardActiveDestinationIsRAW = nil
        destination.clipboardSelectedTargets = [EditClipboardTarget(sourceReference: unopened, isRAW: false)]
        workflow.pasteEdits()
        await workflow.waitForPendingPaste()
        XCTAssertEqual(destination.editor.session(for: unopened.assetID)?.document.light.exposure, 0.6)
        XCTAssertEqual(destination.documentUpdates, 0)
        XCTAssertEqual(destination.persisted.count, 1)
        let revision = destination.editor.revision(for: unopened.assetID)
        workflow.pasteEdits()
        await workflow.waitForPendingPaste()
        XCTAssertEqual(destination.persisted.count, 1)
        XCTAssertEqual(destination.editor.revision(for: unopened.assetID), revision)
        XCTAssertEqual(destination.status, "Pasted edits; retouch sources resolve per photo")
        XCTAssertEqual(destination.flushes, 2)
    }

    /// KRMA-1060: a category-limited paste to a non-resident photo applies to its saved edit.
    func testPasteToNonResidentPhotoUsesDurableBaseAndKeepsUndoAtSavedState() async {
        let (workflow, destination, _) = makeWorkflow()
        destination.clipboardDocument.light.exposure = 0.6
        workflow.presentSelectiveCopyDialog()
        workflow.selectiveCopyCategories = [.light]
        workflow.confirmSelectiveCopy()
        let target = reference("saved.png")
        var saved = EditDocument()
        saved.color.saturation = 33
        destination.durableBases[target.assetID] =
            EditDocumentLoadResult(document: saved, found: true, status: .ready)
        destination.clipboardHasCopySource = false
        destination.clipboardActiveDestinationIsRAW = nil
        destination.clipboardSelectedTargets = [EditClipboardTarget(sourceReference: target, isRAW: false)]

        workflow.pasteEdits()
        await workflow.waitForPendingPaste()

        let pasted = destination.persisted.first?.document
        XCTAssertEqual(pasted?.light.exposure, 0.6)
        XCTAssertEqual(pasted?.color.saturation, 33, "saved categories survive a limited paste")
        var history = destination.editor.session(for: target.assetID)?.history
        XCTAssertEqual(history?.undo(current: pasted ?? EditDocument()), saved)
    }

    func testPasteSkipsAndReportsPhotoWhoseSavedEditCannotBeRead() async {
        let (workflow, destination, _) = makeWorkflow()
        destination.clipboardDocument.light.exposure = 0.6
        workflow.copyAllEdits()
        let target = reference("corrupt.png")
        destination.durableBases[target.assetID] = EditDocumentLoadResult(
            document: EditDocument(), found: false, status: .corrupt("bad json"))
        destination.clipboardHasCopySource = false
        destination.clipboardActiveDestinationIsRAW = nil
        destination.clipboardSelectedTargets = [EditClipboardTarget(sourceReference: target, isRAW: false)]

        workflow.pasteEdits()
        await workflow.waitForPendingPaste()

        XCTAssertNil(destination.editor.session(for: target.assetID))
        XCTAssertTrue(destination.persisted.isEmpty)
        XCTAssertTrue(destination.status.contains("skipped 1"), destination.status)
    }
}

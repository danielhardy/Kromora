import XCTest

@testable import KromoraKit

/// KRMA-1080: context-menu target semantics, availability, and routing to the existing workflows.
@MainActor
final class LibraryContextMenuTests: TempDirectoryTestCase {
    private func id(_ name: String) -> PhotoAssetID { PhotoAssetID(rawValue: name) }

    // MARK: Target semantics

    func testContextOutsideSelectionReplacesSelectionWithOnePhoto() {
        let target = LibraryContextTarget.resolve(
            contextID: id("c"), selectedIDs: [id("a"), id("b")], activeID: id("a"))
        XCTAssertTrue(target.replacesSelection)
        XCTAssertEqual(target.selectionCount, 1)
    }

    func testContextInsideMultiSelectionPreservesSelection() {
        let target = LibraryContextTarget.resolve(
            contextID: id("b"), selectedIDs: [id("a"), id("b"), id("c")], activeID: id("a"))
        XCTAssertFalse(target.replacesSelection)
        XCTAssertEqual(target.selectionCount, 3)
    }

    func testSingleActivePhotoWithoutExplicitSelectionIsTheTarget() {
        let target = LibraryContextTarget.resolve(contextID: id("a"), selectedIDs: [], activeID: id("a"))
        XCTAssertFalse(target.replacesSelection)
        XCTAssertEqual(target.selectionCount, 1)
        let other = LibraryContextTarget.resolve(contextID: id("b"), selectedIDs: [], activeID: id("a"))
        XCTAssertTrue(other.replacesSelection)
    }

    // MARK: Availability

    private func state(
        isPackagePhoto: Bool = true, canPaste: Bool = true, isGrid: Bool = true,
        isExportBusy: Bool = false, isLibraryReady: Bool = true
    ) -> LibraryContextMenuState {
        var state = LibraryContextMenuState(
            target: .resolve(contextID: id("a"), selectedIDs: [id("a")], activeID: id("a")))
        state.isPackagePhoto = isPackagePhoto
        state.canPaste = canPaste
        state.isGrid = isGrid
        state.isExportBusy = isExportBusy
        state.isLibraryReady = isLibraryReady
        return state
    }

    func testPasteIsDisabledWithoutEditClipboard() {
        let state = state(canPaste: false)
        XCTAssertFalse(state.isEnabled(.pasteEditSettings))
        XCTAssertNotNil(state.disabledReason(for: .pasteEditSettings))
        XCTAssertTrue(self.state().isEnabled(.pasteEditSettings))
    }

    func testVirtualCopyRequiresPackagePhoto() {
        XCTAssertFalse(state(isPackagePhoto: false).isEnabled(.createVirtualCopy))
        XCTAssertTrue(state().isEnabled(.createVirtualCopy))
        var creating = state()
        creating.isCreatingVirtualCopy = true
        XCTAssertFalse(creating.isEnabled(.createVirtualCopy))
    }

    func testDeleteIsOnlyOfferedInTheLibraryGrid() {
        XCTAssertTrue(state().isEnabled(.deleteFromLibrary))
        XCTAssertFalse(state(isGrid: false).isEnabled(.deleteFromLibrary))
    }

    func testBusyExportBlocksCopyExportAndShareOnly() {
        let busy = state(isExportBusy: true)
        for action in [LibraryContextAction.copyImage, .export, .share] {
            XCTAssertFalse(busy.isEnabled(action))
        }
        XCTAssertTrue(busy.isEnabled(.setFlag(.pick)))
        XCTAssertTrue(busy.isEnabled(.openInEdit))
    }

    func testUnreadyLibraryDisablesEverything() {
        let notReady = state(isLibraryReady: false)
        XCTAssertFalse(notReady.isEnabled(.openInEdit))
        XCTAssertFalse(notReady.isEnabled(.deleteFromLibrary))
    }

    // MARK: Routing through the view model

    private func makeViewModel() throws -> (AppViewModel, PortableLibrarySession) {
        let packageURL = tempDirectory.appendingPathComponent("Context.kromoralibrary")
        let session = try PortableLibrarySession(at: packageURL, pageSize: 10)
        let urls = try ["alpha", "beta", "gamma"].enumerated().map { index, name in
            try Fixtures.writeJPEG(
                width: 16 + index, height: 12, orientation: 1, named: "\(name).jpg", in: tempDirectory)
        }
        _ = try session.importURLs(urls)
        let editStore = EditDocumentStore(package: session.package, lease: session.lease)
        let viewModel = makeAppViewModel(
            editStore: editStore, portableLibrarySession: session)
        XCTAssertTrue(viewModel.navigate(to: .grid))
        return (viewModel, session)
    }

    func testRetargetOutsideSelectionSelectsOnlyTheContextPhoto() throws {
        let (viewModel, _) = try makeViewModel()
        let ids = viewModel.collection.items.map(\.id)
        viewModel.selectPortableItem(at: 0)
        viewModel.selectPortableItem(at: 1, modifiers: [.command])
        XCTAssertEqual(viewModel.collection.selection.selectedIDs, [ids[0], ids[1]])

        viewModel.retargetLibrarySelection(toContext: ids[2])

        XCTAssertEqual(viewModel.collection.selection.selectedIDs, [ids[2]])
        XCTAssertEqual(viewModel.collection.selection.activeID, ids[2])
    }

    func testRetargetInFilmstripDoesNotOpenTheContextPhoto() async throws {
        let (viewModel, _) = try makeViewModel()
        let ids = viewModel.collection.items.map(\.id)
        viewModel.selectPortableItem(at: 0)
        XCTAssertTrue(viewModel.navigate(to: .edit))
        for _ in 0..<200 where viewModel.activeSourceReference?.assetID != ids[0] {
            try await Task.sleep(for: .milliseconds(25))
        }
        XCTAssertEqual(viewModel.activeSourceReference?.assetID, ids[0])

        viewModel.retargetLibrarySelection(toContext: ids[1])

        XCTAssertEqual(viewModel.collection.selection.selectedIDs, [ids[1]])
        XCTAssertEqual(viewModel.collection.selection.activeID, ids[1])
        XCTAssertEqual(
            viewModel.activeSourceReference?.assetID, ids[0],
            "opening the context menu must not switch the edit document"
        )
    }

    func testRetargetInsideSelectionKeepsTheSelection() throws {
        let (viewModel, _) = try makeViewModel()
        let ids = viewModel.collection.items.map(\.id)
        viewModel.selectPortableItem(at: 0)
        viewModel.selectPortableItem(at: 1, modifiers: [.command])
        let before = viewModel.collection.selection.selectedIDs

        viewModel.retargetLibrarySelection(toContext: ids[0])

        XCTAssertEqual(viewModel.collection.selection.selectedIDs, before)
    }

    func testFlagAndRatingActionsApplyToResolvedSelection() throws {
        let (viewModel, _) = try makeViewModel()
        let ids = viewModel.collection.items.map(\.id)
        viewModel.selectPortableItem(at: 0)
        viewModel.selectPortableItem(at: 1, modifiers: [.command])

        // Inside the selection: both selected photos change.
        viewModel.performLibraryContextAction(.setFlag(.pick), on: ids[1])
        XCTAssertEqual(viewModel.collection.items[0].asset.flag, .pick)
        XCTAssertEqual(viewModel.collection.items[1].asset.flag, .pick)
        XCTAssertEqual(viewModel.collection.items[2].asset.flag, PhotoFlag.none)

        // Outside the selection: only the context photo changes.
        viewModel.performLibraryContextAction(.setRating(4), on: ids[2])
        XCTAssertEqual(viewModel.collection.items[2].asset.rating, 4)
        XCTAssertEqual(viewModel.collection.items[0].asset.rating, 0)
    }

    func testPasteWithoutClipboardReportsAndDoesNotAct() throws {
        let (viewModel, _) = try makeViewModel()
        let ids = viewModel.collection.items.map(\.id)
        viewModel.performLibraryContextAction(.pasteEditSettings, on: ids[0])
        XCTAssertEqual(viewModel.statusMessage, "Copy edit settings first")
    }

    func testDeleteRequestCapturesTheContextTargetForConfirmation() throws {
        let (viewModel, _) = try makeViewModel()
        let ids = viewModel.collection.items.map(\.id)
        viewModel.selectPortableItem(at: 0)

        viewModel.performLibraryContextAction(.deleteFromLibrary, on: ids[2])

        let confirmation = try XCTUnwrap(viewModel.libraryDeletionConfirmation)
        XCTAssertEqual(confirmation.candidates.map(\.id), [ids[2]])
        XCTAssertFalse(viewModel.collection.items.isEmpty, "nothing is removed before confirmation")
    }

    func testVirtualCopyOfContextPhotoCreatesIndependentAssetAndLeavesSource() async throws {
        let (viewModel, session) = try makeViewModel()
        let ids = viewModel.collection.items.map(\.id)
        let item = try XCTUnwrap(viewModel.collection.items.first { $0.id == ids[1] })
        let source = EditSourceReference(
            assetID: item.id, portableIdentity: item.asset.source.portableIdentity, url: item.url)
        XCTAssertNoThrow(try session.package.readAssetRecord(for: source.portableAssetID))
        let storedEdit = await viewModel.loadClipboardBase(for: source)
        XCTAssertEqual(storedEdit.status, .ready)
        let before = session.assetCount

        viewModel.performLibraryContextAction(.createVirtualCopy, on: ids[1])
        for _ in 0..<200 where session.assetCount == before { try await Task.sleep(for: .milliseconds(25)) }

        XCTAssertEqual(session.assetCount, before + 1, "status: \(viewModel.statusMessage)")
        XCTAssertTrue(viewModel.collection.items.contains { $0.id == ids[1] })
    }

    // MARK: Action routing (KRMA-1084)

    @MainActor
    private struct RoutingFixture {
        let viewModel: AppViewModel
        let engine: FakeRenderEngine
        let sheets: FakeSheets
        let editStore: EditDocumentStore
        let pasteboard: NSPasteboard
        let ids: [PhotoAssetID]

        func reference(_ index: Int) -> EditSourceReference {
            let item = viewModel.collection.items[index]
            return EditSourceReference(
                assetID: item.id, portableIdentity: item.asset.source.portableIdentity, url: item.url)
        }
    }

    private func makeRoutingFixture() throws -> RoutingFixture {
        let session = try PortableLibrarySession(
            at: tempDirectory.appendingPathComponent("Routing.kromoralibrary"), pageSize: 10)
        let urls = try ["alpha", "beta", "gamma"].enumerated().map { index, name in
            try Fixtures.writeJPEG(
                width: 16 + index, height: 12, orientation: 1, named: "\(name).jpg", in: tempDirectory)
        }
        _ = try session.importURLs(urls)
        let editStore = EditDocumentStore(package: session.package, lease: session.lease)
        let engine = FakeRenderEngine()
        let sheets = FakeSheets()
        // Cancel at Export Step 1 so no folder panel or export job ever starts.
        sheets.setupResults = [false]
        let viewModel = makeAppViewModel(
            engine: engine, editStore: editStore, portableLibrarySession: session, sheets: sheets)
        XCTAssertTrue(viewModel.navigate(to: .grid))
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("kromora-test-\(UUID().uuidString)"))
        addTeardownBlock { pasteboard.releaseGlobally() }
        viewModel.exportWorkflow.sharePasteboard = pasteboard
        return RoutingFixture(
            viewModel: viewModel, engine: engine, sheets: sheets, editStore: editStore,
            pasteboard: pasteboard, ids: viewModel.collection.items.map(\.id))
    }

    private func poll(_ description: String, _ condition: @MainActor () async -> Bool) async throws {
        for _ in 0..<400 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("timed out waiting for \(description)")
    }

    private func storedDocument(_ fixture: RoutingFixture, _ index: Int) async -> EditDocument {
        await fixture.editStore.load(for: fixture.reference(index)).document
    }

    func testCopyImageOutsideSelectionRendersOnlyTheContextPhoto() async throws {
        let fixture = try makeRoutingFixture()
        let viewModel = fixture.viewModel
        viewModel.selectPortableItem(at: 0)
        viewModel.selectPortableItem(at: 1, modifiers: [.command])

        viewModel.performLibraryContextAction(.copyImage, on: fixture.ids[2])
        try await poll("the copy") { viewModel.statusMessage == "Copied photo" }

        let requests = await fixture.engine.encodeRequests
        XCTAssertEqual(requests.compactMap(\.assetID), [fixture.ids[2]])
        XCTAssertEqual(fixture.pasteboard.pasteboardItems?.count, 1)
    }

    func testCopyImageInsideSelectionRendersEverySelectedPhotoOnly() async throws {
        let fixture = try makeRoutingFixture()
        let viewModel = fixture.viewModel
        viewModel.selectPortableItem(at: 0)
        viewModel.selectPortableItem(at: 1, modifiers: [.command])

        viewModel.performLibraryContextAction(.copyImage, on: fixture.ids[1])
        try await poll("the copy") { viewModel.statusMessage == "Copied 2 photos" }

        let requests = await fixture.engine.encodeRequests
        XCTAssertEqual(Set(requests.compactMap(\.assetID)), [fixture.ids[0], fixture.ids[1]])
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(fixture.pasteboard.pasteboardItems?.count, 2)
    }

    func testCopyEditSettingsReadsThePhotoUnderThePointerNotTheActiveOne() async throws {
        let fixture = try makeRoutingFixture()
        let viewModel = fixture.viewModel
        let edited = EditDocument(adjustments: [.exposure(ev: 0.7)])
        try await fixture.editStore.save(edited, for: fixture.reference(1))
        viewModel.selectPortableItem(at: 0)
        XCTAssertEqual(viewModel.collection.selection.activeID, fixture.ids[0])

        viewModel.performLibraryContextAction(.copyEditSettings, on: fixture.ids[1])
        try await poll("the edit clipboard") { viewModel.canPasteEdits }

        XCTAssertEqual(viewModel.editClipboardWorkflow.clipboard, EditClipboardPayload(document: edited))
        XCTAssertEqual(viewModel.statusMessage, "Copied all edits from beta.jpg")
        XCTAssertEqual(viewModel.collection.selection.selectedIDs, [fixture.ids[1]])
    }

    func testPasteOutsideSelectionWritesDurableEditToTheContextPhotoOnly() async throws {
        let fixture = try makeRoutingFixture()
        let viewModel = fixture.viewModel
        let edited = EditDocument(adjustments: [.exposure(ev: 0.7)])
        try await fixture.editStore.save(edited, for: fixture.reference(0))
        viewModel.performLibraryContextAction(.copyEditSettings, on: fixture.ids[0])
        try await poll("the edit clipboard") { viewModel.canPasteEdits }
        viewModel.selectPortableItem(at: 1)

        viewModel.performLibraryContextAction(.pasteEditSettings, on: fixture.ids[2])
        await viewModel.editClipboardWorkflow.waitForPendingPaste()
        viewModel.flushClipboardPersistence()
        try await poll("the durable paste") { await self.storedDocument(fixture, 2) == edited }

        let untouched = await storedDocument(fixture, 1)
        XCTAssertEqual(untouched, EditDocument(), "the previously selected photo is not a paste target")
    }

    func testPasteInsideMultiSelectionWritesDurableEditToEverySelectedPhoto() async throws {
        let fixture = try makeRoutingFixture()
        let viewModel = fixture.viewModel
        let edited = EditDocument(adjustments: [.exposure(ev: 0.7)])
        try await fixture.editStore.save(edited, for: fixture.reference(0))
        viewModel.performLibraryContextAction(.copyEditSettings, on: fixture.ids[0])
        try await poll("the edit clipboard") { viewModel.canPasteEdits }
        viewModel.selectPortableItem(at: 1)
        viewModel.selectPortableItem(at: 2, modifiers: [.command])

        viewModel.performLibraryContextAction(.pasteEditSettings, on: fixture.ids[1])
        await viewModel.editClipboardWorkflow.waitForPendingPaste()
        viewModel.flushClipboardPersistence()
        try await poll("both durable pastes") {
            let first = await self.storedDocument(fixture, 1)
            let second = await self.storedDocument(fixture, 2)
            return first == edited && second == edited
        }
        XCTAssertEqual(viewModel.collection.selection.selectedIDs, [fixture.ids[1], fixture.ids[2]])
    }

    func testOpenInEditSwitchesToTheContextPhotoOnlyWhenChosen() async throws {
        let fixture = try makeRoutingFixture()
        let viewModel = fixture.viewModel
        viewModel.selectPortableItem(at: 0)

        // Retargeting and unrelated actions never open the photo.
        viewModel.performLibraryContextAction(.setFlag(.pick), on: fixture.ids[1])
        XCTAssertTrue(viewModel.navigation.isGrid)
        XCTAssertNil(viewModel.activeSourceReference)

        viewModel.performLibraryContextAction(.openInEdit, on: fixture.ids[1])
        try await poll("the context photo to open") {
            viewModel.activeSourceReference?.assetID == fixture.ids[1]
        }
        XCTAssertFalse(viewModel.navigation.isGrid)
    }

    func testExportReceivesOnlyTheContextPhotoOutsideTheSelection() async throws {
        let fixture = try makeRoutingFixture()
        let viewModel = fixture.viewModel
        viewModel.selectPortableItem(at: 0)
        viewModel.selectPortableItem(at: 1, modifiers: [.command])

        viewModel.performLibraryContextAction(.export, on: fixture.ids[2])
        try await poll("the export setup sheet") { fixture.sheets.setupCalls == 1 }

        XCTAssertEqual(fixture.sheets.lastSetupAccessory?.entries.map(\.name), ["gamma.jpg"])
        XCTAssertEqual(fixture.sheets.openCalls, 0, "cancelling Step 1 never reaches the folder panel")
    }

    func testExportInsideSelectionReceivesTheSelectionWithoutUnrelatedPhotos() async throws {
        let fixture = try makeRoutingFixture()
        let viewModel = fixture.viewModel
        viewModel.selectPortableItem(at: 0)
        viewModel.selectPortableItem(at: 1, modifiers: [.command])

        viewModel.performLibraryContextAction(.export, on: fixture.ids[0])
        try await poll("the export setup sheet") { fixture.sheets.setupCalls == 1 }

        XCTAssertEqual(
            Set(fixture.sheets.lastSetupAccessory?.entries.map(\.name) ?? []),
            ["alpha.jpg", "beta.jpg"])
    }

    func testShareOffersOnlyTheResolvedTargetAndOpensNoSystemPicker() async throws {
        let fixture = try makeRoutingFixture()
        let viewModel = fixture.viewModel
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 80, height: 40), styleMask: [.titled],
            backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        let anchor = NSView(frame: NSRect(x: 0, y: 0, width: 40, height: 20))
        window.contentView?.addSubview(anchor)
        viewModel.exportWorkflow.shareAnchorView = anchor
        var offered: [[NSItemProvider]] = []
        viewModel.exportWorkflow.showPicker = { items, _, _ in
            offered.append(items.compactMap { $0 as? NSItemProvider })
        }
        viewModel.selectPortableItem(at: 0)
        viewModel.selectPortableItem(at: 1, modifiers: [.command])

        viewModel.performLibraryContextAction(.share, on: fixture.ids[2])
        XCTAssertEqual(offered.count, 1)
        XCTAssertEqual(offered.first?.compactMap(\.suggestedName), ["gamma"])

        viewModel.selectPortableItem(at: 0)
        viewModel.selectPortableItem(at: 1, modifiers: [.command])
        viewModel.performLibraryContextAction(.share, on: fixture.ids[0])
        XCTAssertEqual(offered.count, 2)
        XCTAssertEqual(Set(offered[1].compactMap(\.suggestedName)), ["alpha", "beta"])
        let rendered = await fixture.engine.encodeRequests.count
        XCTAssertEqual(rendered, 0, "the picker opens before any render")
        window.close()
    }
}

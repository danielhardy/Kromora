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
}

import XCTest

@testable import KromoraKit

/// KRMA-1001: Select All and bulk actions read the package selection, not the loaded page.
@MainActor
final class LibrarySelectAllTests: TempDirectoryTestCase {
    private func makeViewModel(
        names: [String] = ["alpha", "beta", "gamma"], pageSize: Int = 2
    ) throws -> (AppViewModel, PortableLibrarySession) {
        let packageURL = tempDirectory.appendingPathComponent("SelectAll.kromoralibrary")
        let session = try PortableLibrarySession(at: packageURL, pageSize: pageSize)
        // Distinct sizes keep the imports from deduplicating by content.
        let urls = try names.enumerated().map { index, name in
            try Fixtures.writeJPEG(
                width: 16 + index, height: 12, orientation: 1, named: "\(name).jpg", in: tempDirectory)
        }
        _ = try session.importURLs(urls)
        return (makeAppViewModel(portableLibrarySession: session), session)
    }

    func testSelectAllSelectsEveryMatchingIDAcrossPagesAndSurvivesSync() throws {
        let (viewModel, session) = try makeViewModel()
        XCTAssertEqual(viewModel.collection.items.count, 2)
        XCTAssertEqual(session.assetCount, 3)
        let firstID = try XCTUnwrap(
            ImageCollection.portableID(for: try XCTUnwrap(viewModel.collection.items.first).id))
        session.setPortableSelection([firstID], activeID: firstID)

        viewModel.selectAllInGrid()

        XCTAssertEqual(session.portableSelectedIDs.count, 3)
        XCTAssertEqual(viewModel.collection.selectedAssetIDs.count, 3)
        XCTAssertEqual(viewModel.collection.items.count, 2, "no extra rows are materialized")

        // A presentation sync or a reload must not change the authoritative id set.
        try viewModel.reloadPortableWindow()
        XCTAssertEqual(session.portableSelectedIDs.count, 3)
        XCTAssertEqual(viewModel.collection.selectedAssetIDs.count, 3)
    }

    func testQueryChangeKeepsOnlyTheIntersection() throws {
        let (viewModel, session) = try makeViewModel()
        viewModel.selectAllInGrid()
        XCTAssertEqual(session.portableSelectedIDs.count, 3)

        session.restrictPortableSelection(to: LibraryQuery(searchText: "alpha"))
        XCTAssertEqual(session.portableSelectedIDs.count, 1)

        // Widening the query does not add the new matches back.
        session.restrictPortableSelection(to: .all)
        XCTAssertEqual(session.portableSelectedIDs.count, 1)
    }

    func testSelectedBatchExportIncludesUnloadedIDsWithoutPixelData() throws {
        let (viewModel, session) = try makeViewModel()
        viewModel.selectAllInGrid()

        let request = viewModel.selectedBatchExportRequest
        XCTAssertEqual(request.items.count, 3)
        let loaded = Set(viewModel.collection.items.map(\.id))
        let unloaded = request.items.filter { item in item.assetID.map { !loaded.contains($0) } ?? false }
        XCTAssertEqual(unloaded.count, 1)
        XCTAssertNil(unloaded.first?.data, "an unloaded photo carries a file URL, not a pixel buffer")
        XCTAssertNotNil(unloaded.first?.url)
        XCTAssertEqual(Set(request.items.compactMap(\.portableIdentity?.assetID)), session.portableSelectedIDs)
    }

    // MARK: - KRMA-1018: culling, paste and deletion use the authoritative selection

    private func unloadedID(_ viewModel: AppViewModel) throws -> PortablePhotoAssetID {
        let loaded = Set(viewModel.collection.items.map(\.id))
        let id = try XCTUnwrap(viewModel.collection.selection.selectedIDs.subtracting(loaded).first)
        return try XCTUnwrap(ImageCollection.portableID(for: id))
    }

    func testCullingAfterSelectAllReachesUnloadedID() async throws {
        let (viewModel, session) = try makeViewModel()
        viewModel.selectAllInGrid()
        let unloaded = try unloadedID(viewModel)
        XCTAssertEqual(viewModel.collection.cullingTargetIDs.count, 2, "only loaded rows have ids here")

        _ = viewModel.setFocusedRating(4)
        _ = viewModel.setFocusedFlag(.pick)
        let flushed = await session.flushPendingLibraryState()
        XCTAssertEqual(flushed, .success)

        let asset = try XCTUnwrap(session.browsingAssets(forIDs: [unloaded]).first)
        XCTAssertEqual(asset.rating, 4)
        XCTAssertEqual(asset.flag, .pick)
        for item in viewModel.collection.items {
            XCTAssertEqual(item.asset.rating, 4)
            XCTAssertEqual(item.asset.flag, .pick)
        }
    }

    func testPasteTargetsIncludeUnloadedIDWithoutPixelData() throws {
        let (viewModel, session) = try makeViewModel()
        viewModel.selectAllInGrid()

        let targets = viewModel.clipboardSelectedTargets
        XCTAssertEqual(targets.count, 3)
        XCTAssertEqual(
            Set(targets.map(\.sourceReference.portableAssetID)),
            session.portableSelectedIDs)
        let unloaded = try unloadedID(viewModel)
        let target = try XCTUnwrap(targets.first { $0.sourceReference.portableAssetID == unloaded })
        XCTAssertNotNil(target.sourceReference.url)
        XCTAssertFalse(target.isRAW)
    }

    func testDeletionAfterSelectAllIncludesUnloadedID() async throws {
        let (viewModel, session) = try makeViewModel()
        viewModel.selectAllInGrid()
        let unloaded = try unloadedID(viewModel)

        viewModel.requestDeleteSelectedLibraryItems()
        let confirmation = try XCTUnwrap(viewModel.libraryDeletionConfirmation)
        XCTAssertEqual(confirmation.candidates.count, 3)

        let result = await viewModel.deleteLibraryItems(confirmation.candidates)
        XCTAssertEqual(result.deletedIDs.count, 3)
        XCTAssertTrue(result.failures.isEmpty, "\(result.failures)")
        XCTAssertEqual(session.assetCount, 0)
        XCTAssertTrue(try session.browsingAssets(forIDs: [unloaded]).isEmpty)
    }
}

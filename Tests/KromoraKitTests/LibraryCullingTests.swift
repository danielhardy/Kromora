import XCTest

@testable import KromoraKit

@MainActor
final class LibraryCullingTests: TempDirectoryTestCase {
    private func makeDefaults() -> UserDefaults {
        makeTestUserDefaults()
    }

    private func makeCollection(defaults: UserDefaults) async throws -> ImageCollection {
        for name in ["a.jpg", "b.jpg", "c.jpg"] {
            try Fixtures.writeJPEG(
                width: 16, height: 12, orientation: 1, named: name, in: tempDirectory
            )
        }
        let collection = makeTestCollection(defaults: defaults)
        collection.loadFromFolder(tempDirectory)
        await collection.scanCompletion()
        return collection
    }

    func testCullingShortcutRoutingCoversPickRejectClearAndRatings() {
        XCTAssertEqual(LibraryCullingCommand.parse(characters: "p"), .pick)
        XCTAssertEqual(LibraryCullingCommand.parse(characters: "X"), .reject)
        XCTAssertEqual(LibraryCullingCommand.parse(characters: "u"), .clearFlag)
        XCTAssertEqual(LibraryCullingCommand.parse(characters: "0"), .clearRating)
        XCTAssertEqual(LibraryCullingCommand.parse(characters: "5"), .rating(5))
        XCTAssertNil(LibraryCullingCommand.parse(characters: "p", hasModifiers: true))
        XCTAssertNil(LibraryCullingCommand.parse(characters: "v"))
    }

    func testFlagAndRatingFiltersComposeWithoutChangingAssetState() async throws {
        let collection = try await makeCollection(defaults: makeDefaults())
        let firstID = try XCTUnwrap(collection.items.first?.id)
        let secondID = try XCTUnwrap(collection.items.dropFirst().first?.id)
        let thirdID = try XCTUnwrap(collection.items.dropFirst(2).first?.id)

        XCTAssertTrue(collection.setRating(3, for: firstID))
        XCTAssertTrue(collection.setFlag(.pick, for: firstID))
        XCTAssertTrue(collection.setRating(5, for: thirdID))
        XCTAssertTrue(collection.setFlag(.reject, for: secondID))

        collection.setFilter(LibraryFilter(flag: .picks, rating: .minimum(3)))
        XCTAssertEqual(collection.filteredItems.map(\.id), [firstID])
        XCTAssertEqual(collection.items.first { $0.id == firstID }?.asset.rating, 3)
        XCTAssertEqual(collection.items.first { $0.id == secondID }?.asset.flag, .reject)

        collection.setFilter(LibraryFilter(flag: .all, rating: .exact(5)))
        XCTAssertEqual(collection.filteredItems.map(\.id), [thirdID])
        XCTAssertEqual(collection.items.count, 3, "filtering must not remove underlying assets")

        collection.setFilter(LibraryFilter(flag: .unflagged))
        XCTAssertEqual(collection.filteredItems.map(\.id), [thirdID])
    }

    func testFilteredNavigationOnlyVisitsVisibleItems() async throws {
        let collection = try await makeCollection(defaults: makeDefaults())
        let firstID = try XCTUnwrap(collection.items.first?.id)
        let secondID = try XCTUnwrap(collection.items.dropFirst().first?.id)
        let thirdID = try XCTUnwrap(collection.items.dropFirst(2).first?.id)
        XCTAssertTrue(collection.setRating(2, for: firstID))
        XCTAssertTrue(collection.setRating(4, for: secondID))
        XCTAssertTrue(collection.setRating(5, for: thirdID))

        collection.setFilter(LibraryFilter(rating: .minimum(4)))
        XCTAssertEqual(
            collection.selectedItem?.id, secondID, "focus should move to the first visible item")
        collection.selectNext()
        XCTAssertEqual(collection.selectedItem?.id, thirdID)
        collection.selectPrevious()
        XCTAssertEqual(collection.selectedItem?.id, secondID)

        collection.select(at: 0)
        XCTAssertEqual(
            collection.selectedItem?.id, secondID, "an invisible item cannot be selected")
    }

    func testPickRejectAdvanceAndUndoRestoreFocusAndState() async throws {
        let collection = try await makeCollection(defaults: makeDefaults())
        let firstID = try XCTUnwrap(collection.items.first?.id)
        let secondID = try XCTUnwrap(collection.items.dropFirst().first?.id)

        XCTAssertTrue(collection.setFlag(.pick, advance: true))
        XCTAssertEqual(collection.items.first { $0.id == firstID }?.asset.flag, .pick)
        XCTAssertEqual(collection.selectedItem?.id, secondID)
        XCTAssertTrue(collection.undoLastCullingChange())
        XCTAssertEqual(collection.items.first { $0.id == firstID }?.asset.flag, PhotoFlag.none)
        XCTAssertEqual(collection.selectedItem?.id, firstID)
    }

    func testRapidCullAdvanceInEditLoadsTheNewFocusedPhoto() async throws {
        let defaults = makeDefaults()
        let viewModel = makeAppViewModel(
            engine: FakeRenderEngine(),
            editStore: makeInMemoryEditStore(),
            preferences: defaults,
            libraryFolderURL: tempDirectory.appendingPathComponent(
                "managed-library", isDirectory: true)
        )
        for name in ["a.jpg", "b.jpg", "c.jpg"] {
            try Fixtures.writeJPEG(
                width: 16, height: 12, orientation: 1, named: name, in: tempDirectory
            )
        }
        viewModel.collection.loadFromFolder(tempDirectory)
        await viewModel.collection.scanCompletion()

        let firstID = try XCTUnwrap(viewModel.collection.items.first?.id)
        let secondID = try XCTUnwrap(viewModel.collection.items.dropFirst().first?.id)
        XCTAssertTrue(viewModel.navigate(to: .edit))
        XCTAssertEqual(viewModel.maskingAssetID, firstID)

        XCTAssertTrue(viewModel.setFocusedFlag(.reject, advance: true))
        XCTAssertEqual(viewModel.collection.selectedItem?.id, secondID)
        XCTAssertEqual(
            viewModel.maskingAssetID, secondID,
            "the Edit canvas target must advance with browsing focus")
    }

    func testCullingStateSurvivesACollectionRecreation() async throws {
        let defaults = makeDefaults()
        for name in ["a.jpg", "b.jpg", "c.jpg"] {
            try Fixtures.writeJPEG(
                width: 16, height: 12, orientation: 1, named: name, in: tempDirectory
            )
        }
        let packageURL = tempDirectory.appendingPathComponent("culling.kromoralibrary")
        let original = makeAppViewModel(preferences: defaults, portablePackageURL: packageURL)
        let library = try XCTUnwrap(original.portableLibrary)
        let urls = ["a.jpg", "b.jpg", "c.jpg"].map { tempDirectory.appendingPathComponent($0) }
        _ = try library.importURLs(urls)
        original.collection.loadPortableAssets(try library.materializedAssets())
        original.collection.select(at: 0)
        let firstID = try XCTUnwrap(original.collection.items.first?.id)
        XCTAssertTrue(original.setFocusedRating(4))
        XCTAssertTrue(original.setFocusedFlag(.pick))
        await original.shutdown()

        let restored = makeAppViewModel(preferences: defaults, portablePackageURL: packageURL)
        await restored.collection.scanCompletion()
        restored.collection.select(at: 0)
        let item = try XCTUnwrap(restored.collection.items.first { $0.id == firstID })
        XCTAssertEqual(item.asset.rating, 4)
        XCTAssertEqual(item.asset.flag, .pick)
    }

    // MARK: - Multi-selection culling

    func testCullingActsOnEverySelectedPhotoAndUndoRestoresThemTogether() async throws {
        let collection = try await makeCollection(defaults: makeDefaults())
        let ids = collection.items.map(\.id)
        collection.select(at: 0)
        collection.select(at: 2, modifiers: [.shift])
        XCTAssertEqual(collection.selection.selectedIDs, Set(ids))
        let activeBefore = collection.selection.activeID

        XCTAssertTrue(collection.setFlagForSelection(.reject))
        XCTAssertEqual(collection.items.map(\.asset.flag), [.reject, .reject, .reject])
        XCTAssertEqual(Set(collection.lastCullingAssetIDs), Set(ids))
        XCTAssertEqual(collection.selection.selectedIDs, Set(ids), "marking keeps the selection")
        XCTAssertEqual(collection.selection.activeID, activeBefore)

        XCTAssertTrue(collection.setRatingForSelection(4))
        XCTAssertEqual(collection.items.map(\.asset.rating), [4, 4, 4])

        XCTAssertTrue(collection.undoLastCullingChange(), "one undo reverts the whole batch")
        XCTAssertEqual(collection.items.map(\.asset.rating), [0, 0, 0])
        XCTAssertEqual(collection.items.map(\.asset.flag), [.reject, .reject, .reject])
        XCTAssertTrue(collection.undoLastCullingChange())
        XCTAssertEqual(
            collection.items.map(\.asset.flag),
            [PhotoFlag.none, PhotoFlag.none, PhotoFlag.none]
        )
        XCTAssertEqual(collection.selection.selectedIDs, Set(ids))
    }

    func testBatchCullingOnlyRecordsPhotosThatActuallyChange() async throws {
        let collection = try await makeCollection(defaults: makeDefaults())
        collection.select(at: 0)
        XCTAssertTrue(collection.setRating(3))
        collection.select(at: 0)
        collection.select(at: 1, modifiers: [.shift])

        XCTAssertTrue(collection.setRatingForSelection(3), "the second photo still changes")
        XCTAssertEqual(collection.lastCullingAssetIDs.count, 1)
        XCTAssertFalse(collection.setRatingForSelection(3), "nothing left to change")
    }

    func testCullingKeyMarksWithoutAdvancingSoArrowsStayFreeForNavigation() async throws {
        let viewModel = makeAppViewModel(
            engine: FakeRenderEngine(),
            editStore: makeInMemoryEditStore(),
            preferences: makeDefaults(),
            libraryFolderURL: tempDirectory.appendingPathComponent(
                "managed-library", isDirectory: true)
        )
        for name in ["a.jpg", "b.jpg", "c.jpg"] {
            try Fixtures.writeJPEG(
                width: 16, height: 12, orientation: 1, named: name, in: tempDirectory
            )
        }
        viewModel.collection.loadFromFolder(tempDirectory)
        await viewModel.collection.scanCompletion()
        let firstID = try XCTUnwrap(viewModel.collection.items.first?.id)
        viewModel.collection.select(at: 0)

        for command in [LibraryCullingCommand.reject, .pick, .clearFlag] {
            viewModel.perform(command)
            XCTAssertEqual(
                viewModel.collection.selectedItem?.id, firstID, "\(command) must not advance"
            )
        }
        viewModel.perform(.reject)
        XCTAssertEqual(viewModel.collection.items.first?.asset.flag, .reject)
        XCTAssertEqual(viewModel.collection.selectedItem?.id, firstID)
    }

    func testCullingKeyAppliesToAMultiSelectionInTheViewModel() async throws {
        let viewModel = makeAppViewModel(
            engine: FakeRenderEngine(),
            editStore: makeInMemoryEditStore(),
            preferences: makeDefaults(),
            libraryFolderURL: tempDirectory.appendingPathComponent(
                "managed-library", isDirectory: true)
        )
        for name in ["a.jpg", "b.jpg", "c.jpg"] {
            try Fixtures.writeJPEG(
                width: 16, height: 12, orientation: 1, named: name, in: tempDirectory
            )
        }
        viewModel.collection.loadFromFolder(tempDirectory)
        await viewModel.collection.scanCompletion()
        viewModel.collection.select(at: 0)
        viewModel.collection.select(at: 1, modifiers: [.shift])

        XCTAssertTrue(viewModel.perform(.rating(5)))
        XCTAssertEqual(viewModel.collection.items.map(\.asset.rating), [5, 5, 0])
        XCTAssertTrue(viewModel.perform(.pick))
        XCTAssertEqual(
            viewModel.collection.items.map(\.asset.flag), [.pick, .pick, PhotoFlag.none]
        )
    }

    func testBatchCullingPersistsEverySelectedPhotoToThePackage() async throws {
        let defaults = makeDefaults()
        for name in ["a.jpg", "b.jpg", "c.jpg"] {
            try Fixtures.writeJPEG(
                width: 16, height: 12, orientation: 1, named: name, in: tempDirectory
            )
        }
        let packageURL = tempDirectory.appendingPathComponent("batch.kromoralibrary")
        let original = makeAppViewModel(preferences: defaults, portablePackageURL: packageURL)
        let library = try XCTUnwrap(original.portableLibrary)
        let urls = ["a.jpg", "b.jpg", "c.jpg"].map { tempDirectory.appendingPathComponent($0) }
        _ = try library.importURLs(urls)
        original.collection.loadPortableAssets(try library.materializedAssets())
        original.collection.select(at: 0)
        original.collection.select(at: 2, modifiers: [.shift])
        let ids = original.collection.items.map(\.id)
        XCTAssertTrue(original.perform(.rating(2)))
        XCTAssertTrue(original.perform(.reject))
        await original.shutdown()

        let restored = makeAppViewModel(preferences: defaults, portablePackageURL: packageURL)
        await restored.collection.scanCompletion()
        for id in ids {
            let item = try XCTUnwrap(restored.collection.items.first { $0.id == id })
            XCTAssertEqual(item.asset.rating, 2, "rating persisted for \(id)")
            XCTAssertEqual(item.asset.flag, .reject, "flag persisted for \(id)")
        }
    }
}

import XCTest
@testable import LumoKit

@MainActor
final class LibraryCullingTests: TempDirectoryTestCase {
    private func makeDefaults() -> UserDefaults {
        let suite = "LumoCullingTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func makeCollection(defaults: UserDefaults) async throws -> ImageCollection {
        for name in ["a.jpg", "b.jpg", "c.jpg"] {
            try Fixtures.writeJPEG(
                width: 16, height: 12, orientation: 1, named: name, in: tempDirectory
            )
        }
        let collection = ImageCollection(defaults: defaults)
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
        XCTAssertEqual(collection.selectedItem?.id, secondID, "focus should move to the first visible item")
        collection.selectNext()
        XCTAssertEqual(collection.selectedItem?.id, thirdID)
        collection.selectPrevious()
        XCTAssertEqual(collection.selectedItem?.id, secondID)

        collection.select(at: 0)
        XCTAssertEqual(collection.selectedItem?.id, secondID, "an invisible item cannot be selected")
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
        let viewModel = AppViewModel(
            engine: FakeRenderEngine(),
            editStore: makeInMemoryEditStore(),
            preferences: defaults,
            libraryFolderURL: tempDirectory.appendingPathComponent("managed-library", isDirectory: true)
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
        XCTAssertEqual(viewModel.maskingAssetID, secondID, "the Edit canvas target must advance with browsing focus")
    }

    func testCullingStateSurvivesACollectionRecreation() async throws {
        let defaults = makeDefaults()
        let collection = try await makeCollection(defaults: defaults)
        let firstID = try XCTUnwrap(collection.items.first?.id)
        XCTAssertTrue(collection.setRating(4, for: firstID))
        XCTAssertTrue(collection.setFlag(.pick, for: firstID))

        let restored = ImageCollection(defaults: defaults)
        restored.loadFromFolder(tempDirectory)
        await restored.scanCompletion()
        let item = try XCTUnwrap(restored.items.first { $0.id == firstID })
        XCTAssertEqual(item.asset.rating, 4)
        XCTAssertEqual(item.asset.flag, .pick)
    }
}

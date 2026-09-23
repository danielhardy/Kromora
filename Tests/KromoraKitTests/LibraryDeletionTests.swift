import XCTest

@testable import KromoraKit

@MainActor
final class LibraryDeletionTests: TempDirectoryTestCase {
    func testCancellationLeavesSelectionAndSourceUntouched() async throws {
        let defaults = makeTestUserDefaults()
        let sourceFolder = tempDirectory.appendingPathComponent("source", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceFolder, withIntermediateDirectories: true)
        let source = try Fixtures.writeJPEG(
            width: 16, height: 12, orientation: 1, named: "keep.jpg", in: sourceFolder
        )
        let viewModel = makeAppViewModel(
            preferences: defaults,
            libraryFolderURL: tempDirectory.appendingPathComponent("managed", isDirectory: true)
        )
        viewModel.collection.loadFromFolder(sourceFolder)
        await viewModel.collection.scanCompletion()
        XCTAssertTrue(viewModel.navigate(to: .grid))

        viewModel.requestDeleteSelectedLibraryItems()
        XCTAssertNotNil(viewModel.libraryDeletionConfirmation)
        viewModel.libraryDeletionConfirmation = nil

        XCTAssertEqual(viewModel.collection.items.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    func testReferencedDeletionRemovesEditsAndDoesNotReturnAfterRescan() async throws {
        let defaults = makeTestUserDefaults()
        let sourceFolder = tempDirectory.appendingPathComponent("source", isDirectory: true)
        let managedFolder = tempDirectory.appendingPathComponent("managed", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceFolder, withIntermediateDirectories: true)
        let source = try Fixtures.writeJPEG(
            width: 16, height: 12, orientation: 1, named: "referenced.jpg", in: sourceFolder
        )
        let editFixture = try EditPackageFixture()
        let store = editFixture.store()
        let viewModel = makeAppViewModel(
            editStore: store,
            preferences: defaults,
            libraryFolderURL: managedFolder,
            photoAnalysisCoordinator: PhotoAnalysisCoordinator(
                engine: FakeRenderEngine(),
                maskStore: MaskStore(directory: tempDirectory.appendingPathComponent("masks")),
                cache: PhotoAnalysisCache(
                    directory: tempDirectory.appendingPathComponent("analysis")
                )
            )
        )
        viewModel.collection.loadFromFolder(sourceFolder)
        await viewModel.collection.scanCompletion()
        let item = try XCTUnwrap(viewModel.collection.items.first)
        try editFixture.register(item)
        try await store.save(
            EditDocument(adjustments: [.exposure(ev: 0.5)]),
            for: EditSourceReference(assetID: item.id, url: source)
        )

        let result = await viewModel.deleteSelectedLibraryItems()
        XCTAssertEqual(result.deletedIDs, [item.id])
        XCTAssertTrue(result.failures.isEmpty)
        XCTAssertTrue(viewModel.collection.items.isEmpty)
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: source.path), "external originals survive"
        )
        let storedAfterDelete = await store.load(
            for: EditSourceReference(assetID: item.id, url: source)
        )
        XCTAssertFalse(storedAfterDelete.found, "the edit record is removed")

        let relaunchedCollection = ImageCollection()
        relaunchedCollection.loadFromFolder(sourceFolder)
        await relaunchedCollection.scanCompletion()
        XCTAssertTrue(relaunchedCollection.items.isEmpty, "the tombstone survives a rescan")
        await relaunchedCollection.shutdown()
    }

    func testMultiSelectionDeletesOnlyTheSelectedPhotos() async throws {
        let defaults = makeTestUserDefaults()
        let sourceFolder = tempDirectory.appendingPathComponent("source", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceFolder, withIntermediateDirectories: true)
        let first = try Fixtures.writeJPEG(
            width: 16, height: 12, orientation: 1, named: "first.jpg", in: sourceFolder
        )
        let second = try Fixtures.writeJPEG(
            width: 16, height: 12, orientation: 1, named: "second.jpg", in: sourceFolder
        )
        try Fixtures.writeJPEG(
            width: 16, height: 12, orientation: 1, named: "untouched.jpg", in: sourceFolder
        )
        let viewModel = makeAppViewModel(
            preferences: defaults,
            libraryFolderURL: tempDirectory.appendingPathComponent("managed", isDirectory: true),
            photoAnalysisCoordinator: PhotoAnalysisCoordinator(
                engine: FakeRenderEngine(),
                maskStore: MaskStore(directory: tempDirectory.appendingPathComponent("masks")),
                cache: PhotoAnalysisCache(
                    directory: tempDirectory.appendingPathComponent("analysis")
                )
            )
        )
        viewModel.collection.loadFromFolder(sourceFolder)
        await viewModel.collection.scanCompletion()
        let firstIndex = try XCTUnwrap(viewModel.collection.items.firstIndex { $0.url == first })
        let secondIndex = try XCTUnwrap(viewModel.collection.items.firstIndex { $0.url == second })
        viewModel.collection.select(at: firstIndex)
        viewModel.collection.select(at: secondIndex, modifiers: [.command])
        let deletedIDs = Set(viewModel.collection.deletionCandidates.map(\.id))

        let result = await viewModel.deleteSelectedLibraryItems()
        XCTAssertEqual(Set(result.deletedIDs), deletedIDs)
        XCTAssertEqual(viewModel.collection.items.map(\.displayName), ["untouched"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.path))
    }

    func testManagedCopyIsMovedOutOfLibraryWhileExternalSourceSurvives() async throws {
        let viewModel = makeAppViewModel(
            libraryFolderURL: tempDirectory.appendingPathComponent("managed", isDirectory: true),
            photoAnalysisCoordinator: PhotoAnalysisCoordinator(
                engine: FakeRenderEngine(),
                maskStore: MaskStore(directory: tempDirectory.appendingPathComponent("masks")),
                cache: PhotoAnalysisCache(
                    directory: tempDirectory.appendingPathComponent("analysis")
                )
            )
        )
        let source = try Fixtures.writeJPEG(
            width: 16, height: 12, orientation: 1, named: "managed-source.jpg", in: tempDirectory
        )
        let importedID = try XCTUnwrap(viewModel.collection.addFromURLs([source]).first)
        let managedURL = try XCTUnwrap(
            viewModel.collection.items.first(where: { $0.id == importedID })?.url
        )
        XCTAssertEqual(
            viewModel.collection.sourceKind(for: viewModel.collection.items[0]), .managed
        )

        let result = await viewModel.deleteSelectedLibraryItems()
        XCTAssertEqual(result.deletedIDs, [importedID])
        XCTAssertFalse(FileManager.default.fileExists(atPath: managedURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    func testPersistenceFailureLeavesTheReferencedItemAndOriginalIntact() async throws {
        let defaults = makeTestUserDefaults()
        let sourceFolder = tempDirectory.appendingPathComponent("source", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceFolder, withIntermediateDirectories: true)
        let source = try Fixtures.writeJPEG(
            width: 16, height: 12, orientation: 1, named: "blocked.jpg", in: sourceFolder
        )
        let id = PhotoAssetID.file(source)
        let reference = EditSourceReference(assetID: id, url: source)
        let editFixture = try EditPackageFixture()
        try editFixture.register(reference)
        let initialStore = editFixture.store()
        try await initialStore.save(
            EditDocument(adjustments: [.exposure(ev: 0.2)]),
            for: reference
        )
        let failingStore = editFixture.store(failuresBeforeSuccess: 1)
        let viewModel = makeAppViewModel(
            editStore: failingStore,
            preferences: defaults,
            libraryFolderURL: tempDirectory.appendingPathComponent("managed", isDirectory: true),
            photoAnalysisCoordinator: PhotoAnalysisCoordinator(
                engine: FakeRenderEngine(),
                maskStore: MaskStore(directory: tempDirectory.appendingPathComponent("masks")),
                cache: PhotoAnalysisCache(
                    directory: tempDirectory.appendingPathComponent("analysis")
                )
            )
        )
        viewModel.collection.loadFromFolder(sourceFolder)
        await viewModel.collection.scanCompletion()

        let result = await viewModel.deleteSelectedLibraryItems()
        XCTAssertTrue(result.deletedIDs.isEmpty)
        XCTAssertEqual(viewModel.collection.items.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        XCTAssertNotNil(viewModel.errorMessage)
    }
}

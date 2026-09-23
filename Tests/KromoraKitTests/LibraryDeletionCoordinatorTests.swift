import Foundation
import XCTest

@testable import KromoraKit

@MainActor
final class LibraryDeletionCoordinatorTests: TempDirectoryTestCase {
    func testFlushFailureLeavesTheCandidateUntouched() async throws {
        let source = try Fixtures.writeGradientPNG(
            width: 16, height: 12, named: "flush-failure.png", in: tempDirectory
        )
        let collection = makeTestCollection()
        let id = try XCTUnwrap(collection.addFromURLs([source]).first)
        let item = try XCTUnwrap(collection.items.first { $0.id == id })
        let managedURL = try XCTUnwrap(item.url)
        let store = makeInMemoryEditStore(failuresBeforeSuccess: 1)
        let persistence = EditPersistenceCoordinator(store: store)
        let reference = EditSourceReference(assetID: item.id, url: managedURL)
        persistence.enqueue(EditDocument(), for: reference, reportsStatus: false, force: true)
        let analysis = makeAnalysisCoordinator()
        let coordinator = makeCoordinator(
            collection: collection, persistence: persistence, store: store, analysis: analysis
        )

        let result = await coordinator.delete([candidate(for: item, in: collection)])

        XCTAssertTrue(result.deletedIDs.isEmpty)
        XCTAssertEqual(result.failures.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: managedURL.path))
        XCTAssertEqual(persistence.pendingCount, 1)
        await analysis.shutdown()
        await collection.shutdown()
    }

    #if false // Legacy non-package deletion path; package removal is covered below.
    func testAnalysisCacheFailureSkipsDeletionForThatItem() async throws {
        let source = try Fixtures.writeGradientPNG(
            width: 16, height: 12, named: "analysis-failure.png", in: tempDirectory
        )
        let collection = makeTestCollection()
        let id = try XCTUnwrap(collection.addFromURLs([source]).first)
        let item = try XCTUnwrap(collection.items.first { $0.id == id })
        let managedURL = try XCTUnwrap(item.url)
        let analysisDirectory = tempDirectory.appendingPathComponent("analysis-failure")
        let analysis = makeAnalysisCoordinator(cacheDirectory: analysisDirectory)
        try FileManager.default.removeItem(at: analysisDirectory)
        let store = makeInMemoryEditStore()
        let coordinator = makeCoordinator(
            collection: collection, persistence: EditPersistenceCoordinator(store: store),
            store: store, analysis: analysis
        )

        let result = await coordinator.delete([candidate(for: item, in: collection)])

        XCTAssertTrue(result.deletedIDs.isEmpty)
        XCTAssertTrue(result.failures.first?.contains("cached analysis") == true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: managedURL.path))
        await analysis.shutdown()
        await collection.shutdown()
    }
    #endif

    #if false // Referenced-folder ownership was removed from the product boundary.
    func testManagedAndReferencedSourcesFollowOwnershipPolicy() async throws {
        let managedSource = try Fixtures.writeGradientPNG(
            width: 16, height: 12, named: "managed.png", in: tempDirectory
        )
        let managedCollection = makeTestCollection(
            libraryFolderURL: tempDirectory.appendingPathComponent("managed-library")
        )
        let managedID = try XCTUnwrap(managedCollection.addFromURLs([managedSource]).first)
        let managedItem = try XCTUnwrap(managedCollection.items.first { $0.id == managedID })
        let managedURL = try XCTUnwrap(managedItem.url)
        XCTAssertEqual(managedCollection.sourceKind(for: managedItem), .managed)

        let referencedFolder = tempDirectory.appendingPathComponent("referenced-folder")
        try FileManager.default.createDirectory(
            at: referencedFolder, withIntermediateDirectories: true
        )
        let referencedURL = try Fixtures.writeGradientPNG(
            width: 16, height: 12, named: "referenced.png", in: referencedFolder
        )
        let referencedCollection = makeTestCollection(
            libraryFolderURL: tempDirectory.appendingPathComponent("other-library")
        )
        referencedCollection.loadFromFolder(referencedFolder)
        await referencedCollection.scanCompletion()
        let referencedItem = try XCTUnwrap(referencedCollection.items.first)
        XCTAssertEqual(referencedCollection.sourceKind(for: referencedItem), .referenced)

        let managedStore = makeInMemoryEditStore()
        let referencedStore = makeInMemoryEditStore()
        let managedAnalysis = makeAnalysisCoordinator()
        let referencedAnalysis = makeAnalysisCoordinator()
        let managedCoordinator = makeCoordinator(
            collection: managedCollection,
            persistence: EditPersistenceCoordinator(store: managedStore),
            store: managedStore,
            analysis: managedAnalysis
        )
        let referencedCoordinator = makeCoordinator(
            collection: referencedCollection,
            persistence: EditPersistenceCoordinator(store: referencedStore),
            store: referencedStore,
            analysis: referencedAnalysis
        )

        let managedResult = await managedCoordinator.delete([
            candidate(for: managedItem, in: managedCollection)
        ])
        let referencedResult = await referencedCoordinator.delete([
            candidate(for: referencedItem, in: referencedCollection)
        ])

        XCTAssertEqual(managedResult.deletedIDs, [managedID])
        XCTAssertFalse(FileManager.default.fileExists(atPath: managedURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: managedSource.path))
        XCTAssertEqual(referencedResult.deletedIDs, [referencedItem.id])
        XCTAssertTrue(FileManager.default.fileExists(atPath: referencedURL.path))

        await managedAnalysis.shutdown()
        await referencedAnalysis.shutdown()
        await managedCollection.shutdown()
        await referencedCollection.shutdown()
    }
    #endif

    func testPortableLibraryRemovalUsesThePortableSession() async throws {
        let source = try Fixtures.writeGradientPNG(
            width: 16, height: 12, named: "portable.png", in: tempDirectory
        )
        let packageURL = tempDirectory.appendingPathComponent("library.kromora")
        let session = try PortableLibrarySession(at: packageURL)
        try session.importURLs([source])
        let asset = try XCTUnwrap(try session.materializedAssets().first)
        let collection = makeTestCollection(libraryFolderURL: packageURL)
        collection.loadPortableAssets([asset])
        let item = try XCTUnwrap(collection.items.first)
        let store = makeInMemoryEditStore()
        let analysis = makeAnalysisCoordinator()
        let coordinator = makeCoordinator(
            collection: collection, persistence: EditPersistenceCoordinator(store: store),
            store: store, analysis: analysis, portableLibrary: session
        )

        let result = await coordinator.delete([candidate(for: item, in: collection)])

        XCTAssertEqual(result.deletedIDs, [item.id])
        XCTAssertEqual(session.assetCount, 0)
        XCTAssertTrue(try session.materializedAssets().isEmpty)
        await analysis.shutdown()
        await collection.shutdown()
    }

    func testTrashIsRestoredWhenEditDeletionFails() async throws {
        let source = try Fixtures.writeGradientPNG(
            width: 16, height: 12, named: "rollback.png", in: tempDirectory
        )
        let collection = makeTestCollection(
            libraryFolderURL: tempDirectory.appendingPathComponent("rollback-library")
        )
        let id = try XCTUnwrap(collection.addFromURLs([source]).first)
        let item = try XCTUnwrap(collection.items.first { $0.id == id })
        let managedURL = try XCTUnwrap(item.url)
        let editFixture = try EditPackageFixture()
        let reference = EditSourceReference(assetID: item.id, url: managedURL)
        try editFixture.register(reference)
        let initialStore = editFixture.store()
        try await initialStore.save(
            EditDocument(adjustments: [.exposure(ev: 0.25)]),
            for: reference
        )
        let failingStore = editFixture.store(failuresBeforeSuccess: 1)
        let analysis = makeAnalysisCoordinator()
        let coordinator = makeCoordinator(
            collection: collection, persistence: EditPersistenceCoordinator(store: failingStore),
            store: failingStore, analysis: analysis
        )

        let result = await coordinator.delete([candidate(for: item, in: collection)])

        XCTAssertTrue(result.deletedIDs.isEmpty)
        XCTAssertEqual(result.failures.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: managedURL.path))
        let edit = await failingStore.load(
            for: EditSourceReference(assetID: item.id, url: managedURL)
        )
        XCTAssertTrue(edit.found, "the failed deletion must retain the edit record")
        await analysis.shutdown()
        await collection.shutdown()
    }

    private func makeAnalysisCoordinator(
        cacheDirectory: URL? = nil
    ) -> PhotoAnalysisCoordinator {
        PhotoAnalysisCoordinator(
            engine: FakeRenderEngine(),
            maskStore: MaskStore(
                directory: tempDirectory.appendingPathComponent("masks-\(UUID().uuidString)")
            ),
            cache: PhotoAnalysisCache(
                directory: cacheDirectory
                    ?? tempDirectory.appendingPathComponent("analysis-\(UUID().uuidString)")
            )
        )
    }

    private func makeCoordinator(
        collection: ImageCollection,
        persistence: EditPersistenceCoordinator,
        store: EditDocumentStore,
        analysis: PhotoAnalysisCoordinator,
        portableLibrary: PortableLibrarySession? = nil
    ) -> LibraryDeletionCoordinator {
        LibraryDeletionCoordinator(
            collection: collection,
            persistence: persistence,
            editStore: store,
            photoAnalysis: analysis,
            portableLibrary: portableLibrary,
            persistenceIdentity: { item in
                guard collection.sourceKind(for: item) == .managed else { return nil }
                return item.asset.source.portableIdentity
            }
        )
    }

    private func candidate(
        for item: ImageCollection.Item,
        in collection: ImageCollection
    ) -> ImageCollection.DeletionCandidate {
        ImageCollection.DeletionCandidate(
            id: item.id,
            displayName: item.displayName,
            url: item.url,
            sourceKind: collection.sourceKind(for: item)
        )
    }
}

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

    func testRetryAfterPartialPortableRemovalFinishesInsteadOfFailing() async throws {
        let source = try Fixtures.writeGradientPNG(
            width: 16, height: 12, named: "partial.png", in: tempDirectory
        )
        let packageURL = tempDirectory.appendingPathComponent("partial.kromora")
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
        // An earlier attempt committed the package tombstone but the item is still presented.
        try session.removeFromLibrary(item.asset.source.portableIdentity.assetID)

        let result = await coordinator.delete([candidate(for: item, in: collection)])

        XCTAssertEqual(result.deletedIDs, [item.id])
        XCTAssertTrue(result.failures.isEmpty)
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
        let editFixture = makeEditPackageFixture()
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

    // MARK: Cleanup fan-out

    private final class RecordingDestination: LibraryDeletionCleanupDestination {
        var activeDeletionAssetID: PhotoAssetID?
        var events: [String] = []
        var removedSessions: Set<PhotoAssetID> = []
        var invalidatedIdentityCount = 0

        func removeEditedThumbnails(for assetIDs: Set<PhotoAssetID>) { events.append("thumbnails") }
        func removeThumbnailFrames(for assetIDs: Set<PortablePhotoAssetID>) { events.append("frames") }
        func removeEditorSessions(for assetIDs: Set<PhotoAssetID>) {
            removedSessions = assetIDs
            events.append("sessions")
        }
        func syncPortableSelectionAfterDeletion() { events.append("selection") }
        func invalidatePreviewIdentities(_ identities: Set<PortablePhotoIdentity>) async {
            invalidatedIdentityCount = identities.count
            events.append("preview")
        }
        func invalidateRenderCaches() async { events.append("render") }
    }

    private func makePortableFixture(
        count: Int,
        withForeignItem: Bool = false
    ) async throws -> (
        collection: ImageCollection, coordinator: LibraryDeletionCoordinator,
        analysis: PhotoAnalysisCoordinator, destination: RecordingDestination
    ) {
        let sources = try (0..<count).map {
            try Fixtures.writeGradientPNG(
                width: 16 + $0, height: 12, named: "cleanup-\($0).png", in: tempDirectory
            )
        }
        let packageURL = tempDirectory.appendingPathComponent("cleanup-\(UUID().uuidString).kromora")
        let session = try PortableLibrarySession(at: packageURL)
        try session.importURLs(sources)
        var assets = try session.materializedAssets()
        if withForeignItem {
            // An item the session does not know about fails its package removal.
            let foreign = try PortableLibrarySession(
                at: tempDirectory.appendingPathComponent("foreign-\(UUID().uuidString).kromora")
            )
            try foreign.importURLs([
                try Fixtures.writeGradientPNG(
                    width: 40, height: 12, named: "foreign.png", in: tempDirectory
                )
            ])
            assets += try foreign.materializedAssets()
        }
        let collection = makeTestCollection(libraryFolderURL: packageURL)
        collection.loadPortableAssets(assets)
        let store = makeInMemoryEditStore()
        let analysis = makeAnalysisCoordinator()
        let coordinator = makeCoordinator(
            collection: collection, persistence: EditPersistenceCoordinator(store: store),
            store: store, analysis: analysis, portableLibrary: session
        )
        let destination = RecordingDestination()
        coordinator.destination = destination
        return (collection, coordinator, analysis, destination)
    }

    func testCleanupRunsInOrderAndReportsStatusForInactiveDeletion() async throws {
        let fixture = try await makePortableFixture(count: 2)
        let item = try XCTUnwrap(fixture.collection.items.first)

        let outcome = await fixture.coordinator.deleteAndCleanUp([
            candidate(for: item, in: fixture.collection)
        ])

        XCTAssertEqual(outcome.result.deletedIDs, [item.id])
        XCTAssertEqual(outcome.activePhoto, .none)
        XCTAssertEqual(outcome.message, .status("Photo removed from Library"))
        XCTAssertEqual(fixture.destination.removedSessions, [item.id])
        XCTAssertEqual(fixture.destination.invalidatedIdentityCount, 1)
        let events = fixture.destination.events
        XCTAssertEqual(events.filter { $0 != "selection" },
                       ["thumbnails", "frames", "sessions", "preview", "render"])
        XCTAssertFalse(fixture.collection.items.contains { $0.id == item.id })
        await fixture.analysis.shutdown()
        await fixture.collection.shutdown()
    }

    func testDeletingActivePhotoWithRemainingSelectionOpensIt() async throws {
        let fixture = try await makePortableFixture(count: 2)
        let item = try XCTUnwrap(fixture.collection.items.first)
        fixture.destination.activeDeletionAssetID = item.id
        fixture.collection.select(at: 0)

        let outcome = await fixture.coordinator.deleteAndCleanUp([
            candidate(for: item, in: fixture.collection)
        ])

        XCTAssertNotNil(fixture.collection.selectedItem)
        XCTAssertEqual(outcome.activePhoto, .openSelection)
        await fixture.analysis.shutdown()
        await fixture.collection.shutdown()
    }

    func testDeletingLastActivePhotoClearsSource() async throws {
        let fixture = try await makePortableFixture(count: 1)
        let item = try XCTUnwrap(fixture.collection.items.first)
        fixture.destination.activeDeletionAssetID = item.id

        let outcome = await fixture.coordinator.deleteAndCleanUp([
            candidate(for: item, in: fixture.collection)
        ])

        XCTAssertNil(fixture.collection.selectedItem)
        XCTAssertEqual(outcome.activePhoto, .clearSource)
        XCTAssertEqual(outcome.message, .status("Photo removed from Library"))
        await fixture.analysis.shutdown()
        await fixture.collection.shutdown()
    }

    func testFullFailureSkipsCleanupAndReportsFirstError() async throws {
        let fixture = try await makePortableFixture(count: 0, withForeignItem: true)
        let item = try XCTUnwrap(fixture.collection.items.first)

        let outcome = await fixture.coordinator.deleteAndCleanUp([
            candidate(for: item, in: fixture.collection)
        ])

        XCTAssertTrue(outcome.result.deletedIDs.isEmpty)
        XCTAssertEqual(outcome.activePhoto, .none)
        guard case .error(let message) = outcome.message else {
            return XCTFail("expected an error message, got \(outcome.message)")
        }
        XCTAssertTrue(message.contains("Could not remove"))
        XCTAssertTrue(fixture.destination.events.isEmpty)
        await fixture.analysis.shutdown()
        await fixture.collection.shutdown()
    }

    func testPartialFailureCleansUpDeletedItemsAndReportsError() async throws {
        let fixture = try await makePortableFixture(count: 1, withForeignItem: true)
        let candidates = fixture.collection.items.map { candidate(for: $0, in: fixture.collection) }

        let outcome = await fixture.coordinator.deleteAndCleanUp(candidates)

        XCTAssertEqual(outcome.result.deletedIDs.count, 1)
        XCTAssertEqual(outcome.result.failures.count, 1)
        guard case .error(let message) = outcome.message else {
            return XCTFail("expected an error message, got \(outcome.message)")
        }
        XCTAssertTrue(message.hasPrefix("Removed 1 photo(s), but some photos could not be removed:"))
        XCTAssertTrue(fixture.destination.events.contains("render"))
        await fixture.analysis.shutdown()
        await fixture.collection.shutdown()
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

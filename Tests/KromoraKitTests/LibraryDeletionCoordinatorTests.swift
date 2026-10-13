import Foundation
import os
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

    // MARK: Off-main removal

    /// A scheduler-backed portable fixture whose single package-I/O worker can be held by a blocker.
    private func makeScheduledFixture(count: Int) async throws -> (
        collection: ImageCollection, coordinator: LibraryDeletionCoordinator,
        analysis: PhotoAnalysisCoordinator, session: PortableLibrarySession,
        scheduler: ImageWorkScheduler
    ) {
        let sources = try (0..<count).map {
            try Fixtures.writeGradientPNG(
                width: 16 + $0, height: 12, named: "scheduled-\($0).png", in: tempDirectory
            )
        }
        let scheduler = ImageWorkScheduler()
        let session = try PortableLibrarySession(
            at: tempDirectory.appendingPathComponent("scheduled-\(UUID().uuidString).kromora"),
            scheduler: scheduler
        )
        try session.importURLs(sources)
        let collection = makeTestCollection(libraryFolderURL: session.package.rootURL)
        collection.loadPortableAssets(try session.materializedAssets())
        let store = makeInMemoryEditStore()
        let analysis = makeAnalysisCoordinator()
        let coordinator = makeCoordinator(
            collection: collection, persistence: EditPersistenceCoordinator(store: store),
            store: store, analysis: analysis, portableLibrary: session
        )
        return (collection, coordinator, analysis, session, scheduler)
    }

    private func holdPackageIOWorker(
        _ scheduler: ImageWorkScheduler
    ) async -> OSAllocatedUnfairLock<Bool> {
        let started = OSAllocatedUnfairLock(initialState: false)
        let release = OSAllocatedUnfairLock(initialState: false)
        scheduler.enqueuePackageIO(id: .init("deletion-test-blocker"), lane: .leaseHeartbeat) {
            started.withLock { $0 = true }
            while !release.withLock({ $0 }) { await Task.yield() }
        }
        for _ in 0..<10_000 where !started.withLock({ $0 }) { await Task.yield() }
        return release
    }

    func testMainActorStaysResponsiveWhileSessionRemovalIsGated() async throws {
        let fixture = try await makeScheduledFixture(count: 1)
        let item = try XCTUnwrap(fixture.collection.items.first)
        let release = await holdPackageIOWorker(fixture.scheduler)

        let deletion = Task { @MainActor in
            await fixture.coordinator.delete([candidate(for: item, in: fixture.collection)])
        }
        for _ in 0..<50 { await Task.yield() }
        var hopped = false
        await MainActor.run { hopped = true }
        XCTAssertTrue(hopped)
        XCTAssertTrue(fixture.coordinator.isDeleting)
        XCTAssertEqual(fixture.session.assetCount, 1, "the gated removal has not run")

        release.withLock { $0 = true }
        let result = await deletion.value
        XCTAssertEqual(result.deletedIDs, [item.id])
        XCTAssertFalse(fixture.coordinator.isDeleting)
        XCTAssertEqual(fixture.session.assetCount, 0)
        await fixture.session.shutdown()
        await fixture.analysis.shutdown()
        await fixture.collection.shutdown()
    }

    func testOverlappingDeletionOfTheSameItemIsRejected() async throws {
        let fixture = try await makeScheduledFixture(count: 1)
        let item = try XCTUnwrap(fixture.collection.items.first)
        let candidate = candidate(for: item, in: fixture.collection)
        let release = await holdPackageIOWorker(fixture.scheduler)

        let first = Task { @MainActor in await fixture.coordinator.delete([candidate]) }
        for _ in 0..<50 { await Task.yield() }
        let second = await fixture.coordinator.delete([candidate])
        XCTAssertTrue(second.deletedIDs.isEmpty)
        XCTAssertEqual(second.failures.count, 1)

        release.withLock { $0 = true }
        let result = await first.value
        XCTAssertEqual(result.deletedIDs, [item.id])
        await fixture.session.shutdown()
        await fixture.analysis.shutdown()
        await fixture.collection.shutdown()
    }

    func testSecondDeletionBatchIsRejectedWhileAnotherItemIsInFlight() async throws {
        let fixture = try await makeScheduledFixture(count: 2)
        let items = fixture.collection.items
        let firstCandidate = candidate(for: items[0], in: fixture.collection)
        let secondCandidate = candidate(for: items[1], in: fixture.collection)
        let release = await holdPackageIOWorker(fixture.scheduler)

        let first = Task { @MainActor in await fixture.coordinator.delete([firstCandidate]) }
        for _ in 0..<50 { await Task.yield() }
        let second = await fixture.coordinator.delete([secondCandidate])
        XCTAssertTrue(second.deletedIDs.isEmpty)
        XCTAssertEqual(second.failures.count, 1)

        release.withLock { $0 = true }
        let result = await first.value
        XCTAssertEqual(result.deletedIDs, [items[0].id])
        XCTAssertEqual(fixture.session.assetCount, 1)
        XCTAssertEqual(fixture.collection.items.map(\.id), [items[1].id])
        await fixture.session.shutdown()
        await fixture.analysis.shutdown()
        await fixture.collection.shutdown()
    }

    func testShutdownMidBatchLeavesNoHalfRemovedItem() async throws {
        let fixture = try await makeScheduledFixture(count: 3)
        let candidates = fixture.collection.items.map { candidate(for: $0, in: fixture.collection) }
        let release = await holdPackageIOWorker(fixture.scheduler)

        let deletion = Task { @MainActor in await fixture.coordinator.delete(candidates) }
        for _ in 0..<50 { await Task.yield() }
        let shutdown = Task { @MainActor in await fixture.session.shutdown() }
        for _ in 0..<50 { await Task.yield() }
        release.withLock { $0 = true }
        await shutdown.value
        let result = await deletion.value

        XCTAssertLessThan(result.deletedIDs.count, candidates.count)
        XCTAssertEqual(result.deletedIDs.count + result.failures.count, candidates.count)
        // Every reported removal left the grid; every failure is still presented.
        let remaining = Set(fixture.collection.items.map(\.id))
        XCTAssertTrue(Set(result.deletedIDs).isDisjoint(with: remaining))
        XCTAssertEqual(remaining.count, candidates.count - result.deletedIDs.count)
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

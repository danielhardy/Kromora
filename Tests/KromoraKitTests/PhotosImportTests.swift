import XCTest
@testable import KromoraKit

@MainActor
private final class TestPhotosImportProvider: PhotosImportProviding {
    enum ProviderError: Error, Sendable {
        case unavailable
    }

    let names: [Int: String?]
    let responses: [Int: Result<Data?, ProviderError>]
    var requestedOrdinals: [Int] = []
    var blockingOrdinal: Int?
    var ignoresCancellation = false
    /// Transfer fractions reported per ordinal before the response resolves.
    var progressScript: [Int: [Double]] = [:]
    var progressHandlers: [Int: @MainActor @Sendable (Double) -> Void] = [:]
    /// When set, the provider pauses on this ordinal after reporting its script.
    var progressPauseOrdinal: Int?

    init(
        names: [Int: String?] = [:],
        responses: [Int: Result<Data?, ProviderError>]
    ) {
        self.names = names
        self.responses = responses
    }

    func originalFilename(for selection: PhotosImportSelection) -> String? {
        names[selection.ordinal] ?? nil
    }

    func transferData(
        for selection: PhotosImportSelection,
        progress: @escaping @MainActor @Sendable (Double) -> Void
    ) async throws -> Data? {
        progressHandlers[selection.ordinal] = progress
        for fraction in progressScript[selection.ordinal] ?? [] { progress(fraction) }
        if selection.ordinal == progressPauseOrdinal { try await Task.sleep(for: .seconds(30)) }
        return try await transferData(for: selection)
    }

    func transferData(for selection: PhotosImportSelection) async throws -> Data? {
        requestedOrdinals.append(selection.ordinal)
        if selection.ordinal == blockingOrdinal {
            if ignoresCancellation {
                try? await Task.sleep(for: .milliseconds(50))
            } else {
                try await Task.sleep(for: .seconds(30))
            }
        }
        switch responses[selection.ordinal] ?? .success(nil) {
        case .success(let data): return data
        case .failure(let error): throw error
        }
    }
}

@MainActor
private final class TestPhotosImportDestination: PhotosImportDestination {
    var outcomes: [Int: PhotosImportInsertionOutcome] = [:]
    var insertedOrdinals: [Int] = []
    var failureReasons: [String] = []
    var summaries: [ImportOutcomeSummary] = []

    func preparePhotosImport(totalCount: Int) {}

    func insertPhotosImport(
        _ item: ImageCollection.PhotoImportItem, ordinal: Int
    ) -> PhotosImportInsertionOutcome {
        let outcome = outcomes[ordinal] ?? .inserted("test-\(ordinal)")
        if case .inserted = outcome { insertedOrdinals.append(ordinal) }
        return outcome
    }

    func recordPhotosImportFailureDestination(name: String, ordinal: Int?, reason: String) {
        failureReasons.append(reason)
    }

    func finishPhotosImportDestination(summary: ImportOutcomeSummary) {
        summaries.append(summary)
    }
}

@MainActor
final class PhotosImportTests: TempDirectoryTestCase {

    func testCoordinatorImportsMultipleItemsThroughInjectedProvider() async throws {
        let firstURL = try Fixtures.writeJPEG(
            width: 32, height: 24, orientation: 1, named: "first.jpg", in: tempDirectory
        )
        let secondURL = try Fixtures.writeJPEG(
            width: 24, height: 32, orientation: 1, named: "second.jpg", in: tempDirectory
        )
        let firstData = try Data(contentsOf: firstURL)
        let secondData = try Data(contentsOf: secondURL)
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())
        let coordinator = PhotosImportCoordinator(destination: viewModel)
        let provider = TestPhotosImportProvider(
            names: [0: "IMG_0001.JPG", 1: "IMG_0002.JPG"],
            responses: [0: .success(firstData), 1: .success(secondData)]
        )

        coordinator.start(
            selections: [
                PhotosImportSelection(ordinal: 0, localIdentifier: "photos.first"),
                PhotosImportSelection(ordinal: 1, localIdentifier: "photos.second"),
            ],
            provider: provider
        )
        try await waitForCoordinator(coordinator)

        XCTAssertEqual(viewModel.collection.items.map(\.displayName), ["IMG_0001.JPG", "IMG_0002.JPG"])
        XCTAssertTrue(viewModel.collection.items.allSatisfy { $0.imageData == nil })
        XCTAssertTrue(viewModel.collection.items.allSatisfy {
            guard let url = $0.url else { return false }
            return FileManager.default.fileExists(atPath: url.path)
        })
        XCTAssertTrue(provider.requestedOrdinals == [0, 1])
        XCTAssertTrue(coordinator.failures.isEmpty)
    }

    func testPortablePhotosBatchDefersProjectionAndMaterializationUntilFinish() throws {
        let packageURL = tempDirectory.appendingPathComponent("Batch.kromoralibrary")
        let existingURLs = try (0..<3).map { index in
            try Fixtures.writeJPEG(
                width: 16 + index, height: 12, orientation: 1,
                named: "existing-\(index).jpg", in: tempDirectory
            )
        }
        let packageSession = try PortableLibrarySession(at: packageURL)
        _ = try packageSession.importURLs(existingURLs)
        try packageSession.lease.release()

        let viewModel = makeAppViewModel(
            engine: FakeRenderEngine(), portablePackageURL: packageURL
        )
        XCTAssertEqual(viewModel.portableLibrary?.assetCount, 3)
        XCTAssertEqual(viewModel.collection.items.count, 3)

        let batchData = try (0..<2).map { index in
            let url = try Fixtures.writeJPEG(
                width: 40 + index, height: 18, orientation: 1,
                named: "batch-\(index).jpg", in: tempDirectory
            )
            return try Data(contentsOf: url)
        }
        viewModel.beginPhotosImport(totalCount: batchData.count)
        for (index, data) in batchData.enumerated() {
            viewModel.appendPhotosImport(
                ImageCollection.PhotoImportItem(
                    name: "Batch \(index).jpg", data: data,
                    localIdentifier: "photos.batch.\(index)"
                ),
                ordinal: index
            )
            XCTAssertEqual(
                viewModel.portableLibrary?.assetCount, 3,
                "the portable projection must remain stable during the streamed batch"
            )
            XCTAssertEqual(
                viewModel.collection.items.count, 3,
                "the presentation bridge must not materialize the full library per item"
            )
        }

        viewModel.finishPhotosImport(cancelled: false)

        XCTAssertEqual(viewModel.portableLibrary?.assetCount, 5)
        XCTAssertEqual(viewModel.collection.items.count, 5)
        XCTAssertEqual(viewModel.photosImportProgress, nil)
    }

    func testPortablePhotosFirstBatchItemIsSelectedAfterDeferredRefresh() throws {
        let packageURL = tempDirectory.appendingPathComponent("FirstBatch.kromoralibrary")
        let sourceURL = try Fixtures.writeJPEG(
            width: 32, height: 24, orientation: 1, named: "first-batch.jpg", in: tempDirectory
        )
        let data = try Data(contentsOf: sourceURL)
        let viewModel = makeAppViewModel(
            engine: FakeRenderEngine(), portablePackageURL: packageURL
        )

        viewModel.beginPhotosImport(totalCount: 1)
        viewModel.appendPhotosImport(
            ImageCollection.PhotoImportItem(
                name: "First Batch.jpg", data: data, localIdentifier: "photos.first-batch"
            ),
            ordinal: 0
        )
        XCTAssertTrue(viewModel.collection.items.isEmpty)
        XCTAssertFalse(viewModel.isInspectorPresented)

        viewModel.finishPhotosImport(cancelled: false)

        XCTAssertEqual(viewModel.collection.items.count, 1)
        XCTAssertEqual(viewModel.collection.selection.activeID, viewModel.collection.items[0].id)
        XCTAssertTrue(viewModel.isInspectorPresented)
    }

    func testCoordinatorRecordsPartialFailureAndKeepsSuccessfulItems() async throws {
        let data = try Data(contentsOf: Fixtures.writeJPEG(
            width: 32, height: 24, orientation: 1, named: "partial.jpg", in: tempDirectory
        ))
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())
        let coordinator = PhotosImportCoordinator(destination: viewModel)
        let provider = TestPhotosImportProvider(
            names: [0: "First.jpg", 1: "Unavailable.heic", 2: "Third.jpg"],
            responses: [0: .success(data), 1: .failure(.unavailable), 2: .success(data)]
        )

        coordinator.start(
            selections: (0..<3).map {
                PhotosImportSelection(ordinal: $0, localIdentifier: "photos.\($0)")
            },
            provider: provider
        )
        try await waitForCoordinator(coordinator)

        XCTAssertEqual(viewModel.collection.items.map(\.displayName), ["First.jpg"])
        XCTAssertEqual(coordinator.failures.count, 1)
        XCTAssertEqual(coordinator.failures.first?.ordinal, 1)
        XCTAssertEqual(coordinator.failures.first?.name, "Unavailable.heic")
        XCTAssertFalse(coordinator.failures.first?.reason.isEmpty ?? true)
        XCTAssertNil(coordinator.progress)
    }

    func testCoordinatorUsesFallbackNameWhenProviderHasNoFilename() async throws {
        let data = try Data(contentsOf: Fixtures.writeJPEG(
            width: 32, height: 24, orientation: 1, named: "fallback.jpg", in: tempDirectory
        ))
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())
        let coordinator = PhotosImportCoordinator(destination: viewModel)
        let provider = TestPhotosImportProvider(responses: [0: .success(data)])

        coordinator.start(
            selections: [PhotosImportSelection(ordinal: 0, localIdentifier: nil)],
            provider: provider
        )
        try await waitForCoordinator(coordinator)

        let fallback = try XCTUnwrap(viewModel.collection.items.first?.displayName)
        XCTAssertTrue(fallback.hasPrefix("Photo 20"), "fallback derives from a timestamp, not an ordinal: \(fallback)")
    }

    func testTransferProgressIsSurfacedPerItemAndMonotonic() async throws {
        let data = try Data(contentsOf: Fixtures.writeJPEG(
            width: 32, height: 24, orientation: 1, named: "progress.jpg", in: tempDirectory
        ))
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())
        let coordinator = PhotosImportCoordinator(destination: viewModel)
        let provider = TestPhotosImportProvider(
            names: [0: "Cloud.jpg"], responses: [0: .success(data)]
        )
        provider.progressScript = [0: [0.25, 0.1, 0.5, 2.0]]
        var seen: [Double] = []
        var overall: [Double] = []
        coordinator.onProgress = { progress in
            guard let progress, let fraction = progress.transferFraction else { return }
            seen.append(fraction)
            overall.append(progress.fraction)
        }

        coordinator.start(
            selections: [PhotosImportSelection(ordinal: 0, localIdentifier: "photos.cloud")],
            provider: provider
        )
        try await waitForCoordinator(coordinator)

        XCTAssertEqual(seen, [0.25, 0.5, 1.0], "regressions are dropped and values are clamped")
        XCTAssertEqual(overall, [0.25, 0.5, 1.0])
        XCTAssertNil(coordinator.progress)
    }

    func testTransferProgressResetsBetweenItemsAndFailureStillCompletesLaterItems() async throws {
        let data = try Data(contentsOf: Fixtures.writeJPEG(
            width: 32, height: 24, orientation: 1, named: "progress2.jpg", in: tempDirectory
        ))
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())
        let coordinator = PhotosImportCoordinator(destination: viewModel)
        let provider = TestPhotosImportProvider(
            names: [0: "Fails.jpg", 1: "Next.jpg"],
            responses: [0: .failure(.unavailable), 1: .success(data)]
        )
        provider.progressScript = [0: [0.6], 1: [0.3]]
        var snapshots: [(name: String?, fraction: Double?)] = []
        coordinator.onProgress = { progress in
            if let progress { snapshots.append((progress.currentName, progress.transferFraction)) }
        }

        coordinator.start(
            selections: (0..<2).map { PhotosImportSelection(ordinal: $0, localIdentifier: "p.\($0)") },
            provider: provider
        )
        try await waitForCoordinator(coordinator)

        XCTAssertEqual(coordinator.failures.map(\.name), ["Fails.jpg"])
        XCTAssertEqual(viewModel.collection.items.map(\.displayName), ["Next.jpg"])
        XCTAssertTrue(snapshots.contains { $0.name == "Fails.jpg" && $0.fraction == 0.6 })
        XCTAssertTrue(snapshots.contains { $0.name == "Next.jpg" && $0.fraction == nil })
        XCTAssertTrue(snapshots.contains { $0.name == "Next.jpg" && $0.fraction == 0.3 })
    }

    func testCancelledTransferKeepsEarlierItemAndStopsProgress() async throws {
        let data = try Data(contentsOf: Fixtures.writeJPEG(
            width: 32, height: 24, orientation: 1, named: "progress3.jpg", in: tempDirectory
        ))
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())
        let coordinator = PhotosImportCoordinator(destination: viewModel)
        let provider = TestPhotosImportProvider(
            names: [0: "Kept.jpg", 1: "Downloading.jpg"],
            responses: [0: .success(data), 1: .success(data)]
        )
        provider.progressScript = [0: [0.1], 1: [0.4]]
        provider.progressPauseOrdinal = 1
        var lastFraction: Double?
        coordinator.onProgress = { lastFraction = $0?.transferFraction ?? lastFraction }

        coordinator.start(
            selections: (0..<2).map { PhotosImportSelection(ordinal: $0, localIdentifier: "p.\($0)") },
            provider: provider
        )
        try await waitUntil("the download to report progress") { lastFraction == 0.4 }
        provider.progressHandlers[0]?(0.8)
        XCTAssertEqual(lastFraction, 0.4, "a late update from a prior item is ignored")
        coordinator.cancel()
        provider.progressHandlers[1]?(0.8)
        XCTAssertEqual(lastFraction, 0.4, "updates after cancellation are ignored")
        try await waitForCoordinator(coordinator)

        XCTAssertTrue(coordinator.wasCancelled)
        XCTAssertEqual(viewModel.collection.items.map(\.displayName), ["Kept.jpg"])
        XCTAssertNil(coordinator.progress)
    }

    func testCoordinatorCancellationFinishesWithoutDiscardingEarlierItem() async throws {
        let data = try Data(contentsOf: Fixtures.writeJPEG(
            width: 32, height: 24, orientation: 1, named: "cancel.jpg", in: tempDirectory
        ))
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())
        let coordinator = PhotosImportCoordinator(destination: viewModel)
        let provider = TestPhotosImportProvider(
            names: [0: "Kept.jpg", 1: "Waiting.jpg"],
            responses: [0: .success(data), 1: .success(data)]
        )
        provider.blockingOrdinal = 1

        coordinator.start(
            selections: [
                PhotosImportSelection(ordinal: 0, localIdentifier: "photos.kept"),
                PhotosImportSelection(ordinal: 1, localIdentifier: "photos.waiting"),
            ],
            provider: provider
        )
        try await waitUntil("the second provider request") {
            provider.requestedOrdinals.contains(1)
        }
        coordinator.cancel()
        try await waitForCoordinator(coordinator)

        XCTAssertEqual(viewModel.collection.items.map(\.displayName), ["Kept.jpg"])
        XCTAssertTrue(coordinator.wasCancelled)
    }

    func testCoordinatorPropagatesOneComputedDigestToDurableSource() async throws {
        let data = try Data(contentsOf: Fixtures.writeJPEG(
            width: 32, height: 24, orientation: 1, named: "digest.jpg", in: tempDirectory
        ))
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())
        let coordinator = PhotosImportCoordinator(destination: viewModel)
        let provider = TestPhotosImportProvider(responses: [0: .success(data)])

        coordinator.start(
            selections: [PhotosImportSelection(ordinal: 0, localIdentifier: "photos.digest")],
            provider: provider
        )
        try await waitForCoordinator(coordinator)

        XCTAssertNotNil(viewModel.collection.items.first?.dataFingerprint)
    }

    func testCoordinatorPublishesInsertedDuplicateAndFailedPackageOutcomes() async throws {
        let data = try Data(contentsOf: Fixtures.writeJPEG(
            width: 32, height: 24, orientation: 1, named: "outcomes.jpg", in: tempDirectory
        ))
        let destination = TestPhotosImportDestination()
        destination.outcomes = [
            1: .duplicate("existing"), 2: .failed("package lease expired")
        ]
        let coordinator = PhotosImportCoordinator(destination: destination)
        let provider = TestPhotosImportProvider(
            responses: [0: .success(data), 1: .success(data), 2: .success(data)]
        )

        coordinator.start(
            selections: (0..<3).map { PhotosImportSelection(ordinal: $0, localIdentifier: "\($0)") },
            provider: provider
        )
        try await waitForCoordinator(coordinator)

        let summary = try XCTUnwrap(destination.summaries.last)
        XCTAssertEqual(summary.imported, 1)
        XCTAssertEqual(summary.duplicates, 1)
        XCTAssertEqual(summary.failed, 1)
        let reason = try XCTUnwrap(summary.failureReasons.first)
        XCTAssertEqual(summary.failureReasons.count, 1)
        XCTAssertTrue(reason.hasPrefix("Photo 20") && reason.hasSuffix(" 3: package lease expired"), reason)
        XCTAssertEqual(destination.insertedOrdinals, [0])
    }

    func testLateCancelledProviderResultCannotMutateNewOperation() async throws {
        let data = try Data(contentsOf: Fixtures.writeJPEG(
            width: 32, height: 24, orientation: 1, named: "fenced.jpg", in: tempDirectory
        ))
        let destination = TestPhotosImportDestination()
        let coordinator = PhotosImportCoordinator(destination: destination)
        let oldProvider = TestPhotosImportProvider(responses: [0: .success(data)])
        oldProvider.blockingOrdinal = 0
        oldProvider.ignoresCancellation = true
        coordinator.start(
            selections: [PhotosImportSelection(ordinal: 0, localIdentifier: "old")],
            provider: oldProvider
        )
        try await waitUntil("the old provider request") {
            oldProvider.requestedOrdinals == [0]
        }

        let newProvider = TestPhotosImportProvider(responses: [0: .success(data)])
        coordinator.start(
            selections: [PhotosImportSelection(ordinal: 0, localIdentifier: "new")],
            provider: newProvider
        )
        try await waitForCoordinator(coordinator)
        try await Task.sleep(for: .milliseconds(75))

        XCTAssertEqual(destination.insertedOrdinals, [0])
        XCTAssertEqual(destination.summaries.count, 1)
    }

    private func waitForCoordinator(
        _ coordinator: PhotosImportCoordinator,
        timeout: Duration = .seconds(5)
    ) async throws {
        try await waitUntil("Photos import completion", timeout: timeout) {
            coordinator.progress == nil
        }
    }

    private func waitUntil(
        _ description: String,
        timeout: Duration = .seconds(5),
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let deadline = ContinuousClock.now + timeout
        while !condition() {
            guard ContinuousClock.now < deadline else {
                XCTFail("timed out waiting for \(description)")
                return
            }
            try await Task.sleep(for: .milliseconds(1))
        }
    }

    #if false // Legacy collection reservation tests; package import outcomes are tested below.
    func testStreamingImportRetainsFullBytesAndUsesPhotosIdentity() throws {
        let url = try Fixtures.writeJPEG(
            width: 80, height: 60, orientation: 6, named: "portrait.jpg", in: tempDirectory
        )
        let data = try Data(contentsOf: url)
        let collection = makeTestCollection()

        collection.beginDataImport()
        let item = ImageCollection.PhotoImportItem(
            name: "Portrait", data: data, localIdentifier: "photos.local.portrait"
        )
        let id = collection.appendDataImport(item, ordinal: 0)
        collection.finishDataImport()

        XCTAssertEqual(id, collection.items[0].url.map(PhotoAssetID.file))
        XCTAssertEqual(collection.items.count, 1)
        XCTAssertEqual(collection.items[0].imageData, data,
                       "the collection must retain the original payload, not a preview")
        XCTAssertEqual(collection.items[0].asset.source.id, id)
    }

    func testImportedContentDigestIsSharedBySourceAndFallbackIdentity() throws {
        let url = try Fixtures.writeJPEG(
            width: 80, height: 60, orientation: 1, named: "digest.jpg", in: tempDirectory
        )
        let data = try Data(contentsOf: url)
        let item = ImageCollection.PhotoImportItem(name: "Digest", data: data)
        let collection = makeTestCollection()

        collection.beginDataImport()
        let id = collection.appendDataImport(item, ordinal: 0)

        XCTAssertEqual(item.contentDigest, PhotoAssetID.contentDigest(data))
        XCTAssertEqual(collection.items[0].dataFingerprint, item.contentDigest)
        XCTAssertEqual(id, collection.items[0].url.map(PhotoAssetID.file))
    }

    func testOriginalNameIncludingExtensionPropagatesToDurableAsset() throws {
        let url = try Fixtures.writeJPEG(
            width: 32, height: 24, orientation: 1, named: "source.jpg", in: tempDirectory
        )
        let data = try Data(contentsOf: url)
        let collection = makeTestCollection()

        collection.beginDataImport()
        _ = collection.appendDataImport(
            ImageCollection.PhotoImportItem(name: "IMG_0042.HEIC", data: data), ordinal: 0
        )

        XCTAssertEqual(collection.items[0].asset.filename, "IMG_0042.HEIC")
        XCTAssertTrue(collection.items[0].url?.lastPathComponent.hasSuffix("-IMG_0042.HEIC") == true)
    }

    func testImportReservationsReplaceByOrdinalWithoutReordering() throws {
        let url = try Fixtures.writeJPEG(
            width: 32, height: 24, orientation: 1, named: "reserved.jpg", in: tempDirectory
        )
        let data = try Data(contentsOf: url)
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())

        viewModel.beginPhotosImport(totalCount: 3)
        XCTAssertEqual(viewModel.collection.pendingImportSlots.count, 3)
        XCTAssertEqual(viewModel.collection.thumbnailEntries.count, 3)
        XCTAssertTrue(viewModel.collection.thumbnailEntries.allSatisfy(\.isPlaceholder))

        viewModel.appendPhotosImport(
            ImageCollection.PhotoImportItem(name: "Third", data: data, localIdentifier: "third"),
            ordinal: 2
        )
        var entries = viewModel.collection.thumbnailEntries
        XCTAssertEqual(entries.count, 3)
        XCTAssertTrue(entries[0].isPlaceholder)
        XCTAssertTrue(entries[1].isPlaceholder)
        XCTAssertFalse(entries[2].isPlaceholder)
        XCTAssertEqual(viewModel.collection.items.map(\.displayName), ["Third"])

        viewModel.appendPhotosImport(
            ImageCollection.PhotoImportItem(name: "First", data: data, localIdentifier: "first"),
            ordinal: 0
        )
        entries = viewModel.collection.thumbnailEntries
        XCTAssertFalse(entries[0].isPlaceholder)
        XCTAssertTrue(entries[1].isPlaceholder)
        XCTAssertFalse(entries[2].isPlaceholder)
        XCTAssertEqual(viewModel.collection.items.map(\.displayName), ["First", "Third"])
        XCTAssertEqual(entries[0].itemIndex, 0)
        XCTAssertEqual(entries[2].itemIndex, 1)
    }

    func testImportProjectionKeepsPlaceholdersButFiltersLoadedArrivals() throws {
        let url = try Fixtures.writeJPEG(
            width: 32, height: 24, orientation: 1, named: "filtered.jpg", in: tempDirectory
        )
        let data = try Data(contentsOf: url)
        let collection = makeTestCollection()

        collection.setFilter(LibraryFilter(flag: .picks, rating: .any))
        collection.beginDataImport(reservedCount: 3)
        let filteredIdentifier = "filtered-\(UUID().uuidString)"
        let filteredID = collection.appendDataImport(
            ImageCollection.PhotoImportItem(
                name: "Filtered", data: data, localIdentifier: filteredIdentifier
            ),
            ordinal: 0
        )

        var entries = collection.thumbnailEntries
        XCTAssertEqual(entries.compactMap(\.placeholder?.ordinal), [1, 2])
        XCTAssertFalse(entries.contains(where: { $0.id == filteredID }))

        let pickedID = collection.appendDataImport(
            ImageCollection.PhotoImportItem(
                name: "Picked", data: data, localIdentifier: "picked-\(UUID().uuidString)"
            ),
            ordinal: 2
        )
        XCTAssertTrue(collection.setFlag(.pick, for: pickedID))

        entries = collection.thumbnailEntries
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries.compactMap(\.placeholder?.ordinal), [1])
        XCTAssertEqual(entries.last?.id, pickedID)
        XCTAssertFalse(entries.last?.isPlaceholder ?? true)

        collection.finishDataImport()
        XCTAssertEqual(collection.thumbnailEntries.map(\.id), [pickedID])
    }

    func testUnreservedImportOrdinalAppearsAsLoadedTailEntry() throws {
        let url = try Fixtures.writeJPEG(
            width: 32, height: 24, orientation: 1, named: "overflow.jpg", in: tempDirectory
        )
        let data = try Data(contentsOf: url)
        let collection = makeTestCollection()

        collection.beginDataImport(reservedCount: 2)
        let overflowID = collection.appendDataImport(
            ImageCollection.PhotoImportItem(name: "Overflow", data: data, localIdentifier: "overflow"),
            ordinal: 2
        )

        var entries = collection.thumbnailEntries
        XCTAssertEqual(entries.count, 3)
        XCTAssertTrue(entries[0].isPlaceholder)
        XCTAssertTrue(entries[1].isPlaceholder)
        XCTAssertEqual(entries[2].id, overflowID)
        XCTAssertEqual(entries[2].itemIndex, 0)
        XCTAssertFalse(entries[2].isPlaceholder)

        let reservedID = collection.appendDataImport(
            ImageCollection.PhotoImportItem(name: "Reserved", data: data, localIdentifier: "reserved"),
            ordinal: 1
        )
        entries = collection.thumbnailEntries
        XCTAssertEqual(entries.map(\.isPlaceholder), [true, false, false])
        XCTAssertEqual(entries[1].id, reservedID)
        XCTAssertEqual(entries[2].id, overflowID)

        collection.finishDataImport()
        XCTAssertEqual(collection.thumbnailEntries.map(\.id), [reservedID, overflowID])
    }

    func testLoadedEntryIdentitySurvivesImportCompletion() throws {
        let url = try Fixtures.writeJPEG(
            width: 32, height: 24, orientation: 1, named: "stable-entry.jpg", in: tempDirectory
        )
        let data = try Data(contentsOf: url)
        let collection = makeTestCollection()

        collection.beginDataImport(reservedCount: 2)
        let firstID = collection.appendDataImport(
            ImageCollection.PhotoImportItem(name: "First", data: data, localIdentifier: "first"),
            ordinal: 0
        )
        let loadedEntryID = try XCTUnwrap(
            collection.thumbnailEntries.first(where: { !$0.isPlaceholder })?.id
        )

        XCTAssertEqual(loadedEntryID, firstID)
        collection.finishDataImport()

        XCTAssertEqual(collection.thumbnailEntries.map(\.id), [firstID])
    }

    func testFailureAndCancellationClearReservationsWithoutCreatingTargets() throws {
        let url = try Fixtures.writeJPEG(
            width: 32, height: 24, orientation: 1, named: "partial.jpg", in: tempDirectory
        )
        let data = try Data(contentsOf: url)
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())

        viewModel.beginPhotosImport(totalCount: 3)
        viewModel.recordPhotosImportFailure(name: "Unavailable", ordinal: 1)
        XCTAssertEqual(
            viewModel.collection.thumbnailEntries.compactMap(\.placeholder?.state),
            [.pending, .failed, .pending]
        )
        XCTAssertTrue(viewModel.collection.selectedItem == nil)

        viewModel.appendPhotosImport(
            ImageCollection.PhotoImportItem(name: "Kept", data: data, localIdentifier: "kept"),
            ordinal: 0
        )
        viewModel.finishPhotosImport(cancelled: false)
        XCTAssertTrue(viewModel.collection.pendingImportSlots.isEmpty)
        XCTAssertEqual(viewModel.collection.thumbnailEntries.count, 1)
        XCTAssertFalse(viewModel.collection.thumbnailEntries[0].isPlaceholder)

        viewModel.beginPhotosImport(totalCount: 2)
        viewModel.appendPhotosImport(
            ImageCollection.PhotoImportItem(name: "Cancelled", data: data, localIdentifier: "cancelled"),
            ordinal: 0
        )
        viewModel.finishPhotosImport(cancelled: true)
        XCTAssertTrue(viewModel.collection.pendingImportSlots.isEmpty)
        XCTAssertEqual(viewModel.collection.thumbnailEntries.count, 2)
        XCTAssertEqual(viewModel.collection.items.map(\.displayName), ["Kept", "Cancelled"])
    }

    func testEmptyImportHasNoReservationsOrActiveDestination() {
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())

        viewModel.beginPhotosImport(totalCount: 0)
        XCTAssertTrue(viewModel.collection.pendingImportSlots.isEmpty)
        XCTAssertTrue(viewModel.collection.thumbnailEntries.isEmpty)
        XCTAssertFalse(viewModel.collection.isActive)

        viewModel.finishPhotosImport(cancelled: false)
        XCTAssertTrue(viewModel.collection.pendingImportSlots.isEmpty)
        XCTAssertFalse(viewModel.collection.isActive)
    }
    #endif

    #if false // Legacy synchronous reservation assertions; package batch coverage is above.
    func testPartialImportKeepsSuccessfulItemsWhenOneItemFails() throws {
        let firstURL = try Fixtures.writeJPEG(
            width: 32, height: 24, orientation: 1, named: "first.jpg", in: tempDirectory
        )
        let secondURL = try Fixtures.writeJPEG(
            width: 32, height: 24, orientation: 1, named: "second.jpg", in: tempDirectory
        )
        let firstData = try Data(contentsOf: firstURL)
        let secondData = try Data(contentsOf: secondURL)
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())

        viewModel.beginPhotosImport(totalCount: 3)
        viewModel.appendPhotosImport(
            ImageCollection.PhotoImportItem(
                name: "First", data: firstData, localIdentifier: "photos.first"
            ),
            ordinal: 0
        )
        viewModel.recordPhotosImportFailure(name: "Unavailable")
        viewModel.appendPhotosImport(
            ImageCollection.PhotoImportItem(
                name: "Second", data: secondData, localIdentifier: "photos.second"
            ),
            ordinal: 2
        )

        XCTAssertTrue(viewModel.collection.items.allSatisfy {
            $0.url?.path.hasPrefix(viewModel.collection.libraryFolderURL.path + "/") == true
        })
        XCTAssertEqual(viewModel.collection.items.map(\.imageData), [firstData, secondData])
        XCTAssertEqual(viewModel.photosImportProgress?.processed, 3)
        XCTAssertEqual(viewModel.photosImportProgress?.imported, 2)
        XCTAssertEqual(viewModel.photosImportProgress?.failed, 1)

        viewModel.finishPhotosImport(cancelled: false)
        XCTAssertNil(viewModel.photosImportProgress)
        XCTAssertTrue(viewModel.statusMessage.contains("2 imported"))
        XCTAssertTrue(viewModel.statusMessage.contains("1 failed"))
    }

    func testCancellationLeavesAlreadyImportedOriginalsUsable() throws {
        let url = try Fixtures.writeJPEG(
            width: 32, height: 24, orientation: 1, named: "cancel.jpg", in: tempDirectory
        )
        let data = try Data(contentsOf: url)
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())

        viewModel.beginPhotosImport(totalCount: 2)
        viewModel.appendPhotosImport(
            ImageCollection.PhotoImportItem(
                name: "Kept", data: data, localIdentifier: "photos.kept"
            ),
            ordinal: 0
        )
        viewModel.finishPhotosImport(cancelled: true)

        XCTAssertEqual(viewModel.collection.items.count, 1)
        XCTAssertEqual(viewModel.collection.items[0].imageData, data)
        XCTAssertTrue(viewModel.statusMessage.contains("cancelled"))
    }

    func testFirstSuccessfulImportPresentsInspectorOnceAndPreservesInspectorState() throws {
        let url = try Fixtures.writeJPEG(
            width: 32, height: 24, orientation: 1, named: "inspector-import.jpg", in: tempDirectory
        )
        let data = try Data(contentsOf: url)
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())
        viewModel.inspectorTab = .effects
        viewModel.info.metadata.make = "stale camera"
        viewModel.info.histogram = HistogramData(
            red: [1], green: [1], blue: [1], luma: [1]
        )

        viewModel.beginPhotosImport(totalCount: 2)
        XCTAssertFalse(viewModel.isInspectorPresented)

        viewModel.appendPhotosImport(
            ImageCollection.PhotoImportItem(name: "First", data: data, localIdentifier: "first"),
            ordinal: 0
        )

        XCTAssertTrue(viewModel.isInspectorPresented)
        XCTAssertEqual(viewModel.inspectorTab, .effects)
        XCTAssertTrue(viewModel.info.metadata.isEmpty)
        XCTAssertNil(viewModel.info.histogram)

        viewModel.appendPhotosImport(
            ImageCollection.PhotoImportItem(name: "Second", data: data, localIdentifier: "second"),
            ordinal: 1
        )

        XCTAssertTrue(viewModel.isInspectorPresented)
        XCTAssertEqual(viewModel.inspectorTab, .effects)
        XCTAssertEqual(viewModel.collection.selection.activeID, viewModel.collection.items[0].id)
    }

    func testFirstImportFailureThenSuccessStillPresentsInspectorForTheSuccessfulItem() throws {
        let url = try Fixtures.writeJPEG(
            width: 32, height: 24, orientation: 1, named: "second-succeeds.jpg", in: tempDirectory
        )
        let data = try Data(contentsOf: url)
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())

        viewModel.beginPhotosImport(totalCount: 2)
        viewModel.recordPhotosImportFailure(name: "Unavailable", ordinal: 0)
        XCTAssertFalse(viewModel.isInspectorPresented)

        viewModel.appendPhotosImport(
            ImageCollection.PhotoImportItem(name: "Second", data: data, localIdentifier: "second"),
            ordinal: 1
        )

        XCTAssertTrue(viewModel.isInspectorPresented)
    }

    func testPhotosImportWithoutAnAcceptedItemLeavesInspectorPresentationUnchanged() throws {
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())

        viewModel.beginPhotosImport(totalCount: 2)
        viewModel.recordPhotosImportFailure(name: "Unavailable", ordinal: 0)
        viewModel.recordPhotosImportFailure(name: "Unavailable", ordinal: 1)
        viewModel.finishPhotosImport(cancelled: false)
        XCTAssertFalse(viewModel.isInspectorPresented)

        viewModel.beginPhotosImport(totalCount: 1)
        viewModel.finishPhotosImport(cancelled: true)
        XCTAssertFalse(viewModel.isInspectorPresented)

        viewModel.beginPhotosImport(totalCount: 0)
        viewModel.finishPhotosImport(cancelled: false)
        XCTAssertFalse(viewModel.isInspectorPresented)
    }

    func testRepeatedPhotosImportsDoNotReopenOrChangeInspectorTab() throws {
        let url = try Fixtures.writeJPEG(
            width: 32, height: 24, orientation: 1, named: "repeated-import.jpg", in: tempDirectory
        )
        let data = try Data(contentsOf: url)
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())
        viewModel.inspectorTab = .look

        viewModel.beginPhotosImport(totalCount: 1)
        viewModel.appendPhotosImport(
            ImageCollection.PhotoImportItem(name: "First", data: data, localIdentifier: "first"),
            ordinal: 0
        )
        viewModel.finishPhotosImport(cancelled: false)
        XCTAssertTrue(viewModel.isInspectorPresented)
        XCTAssertEqual(viewModel.inspectorTab, .look)

        viewModel.beginPhotosImport(totalCount: 1)
        viewModel.appendPhotosImport(
            ImageCollection.PhotoImportItem(name: "Second", data: data, localIdentifier: "second"),
            ordinal: 0
        )

        XCTAssertTrue(viewModel.isInspectorPresented)
        XCTAssertEqual(viewModel.inspectorTab, .look)
    }
    #endif
}

final class OriginalFileTypeCheckTests: XCTestCase {
    private let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0, 0, 0x10] + Array("JFIF".utf8) + [0, 1, 1, 0])
    private let tiffContainer = Data([0x49, 0x49, 0x2A, 0x00, 8, 0, 0, 0, 0, 0, 0, 0, 0, 0])

    func testJPEGBytesUnderRAWNameAreRejected() {
        XCTAssertNotNil(OriginalFileTypeCheck.mismatchReason(name: "DSC00160.ARW", data: jpeg))
    }

    func testTIFFContainerUnderRAWNameIsRejectedWhenItIsNotRecognizedAsRAW() {
        XCTAssertEqual(ImageSource.kind(forData: tiffContainer), .standard)
        XCTAssertNotNil(OriginalFileTypeCheck.mismatchReason(name: "DSC00160.ARW", data: tiffContainer))
    }

    func testJPEGNameWithJPEGBytesIsAcceptedAndPNGNameIsNot() {
        XCTAssertNil(OriginalFileTypeCheck.mismatchReason(name: "a.jpg", data: jpeg))
        XCTAssertNotNil(OriginalFileTypeCheck.mismatchReason(name: "a.png", data: jpeg))
    }

    func testHEICBrandUnderCR3NameIsRejectedButCanonBrandIsNot() {
        let heic = Data([0, 0, 0, 0x18] + Array("ftypheic".utf8) + [0, 0, 0, 0])
        let crx = Data([0, 0, 0, 0x18] + Array("ftypcrx ".utf8) + [0, 0, 0, 0])
        XCTAssertNotNil(OriginalFileTypeCheck.mismatchReason(name: "a.CR3", data: heic))
        XCTAssertNil(OriginalFileTypeCheck.mismatchReason(name: "a.CR3", data: crx))
    }

    @MainActor
    func testCoordinatorSkipsMismatchedOriginalAndReportsIt() async {
        let destination = MismatchDestination()
        let coordinator = PhotosImportCoordinator(destination: destination)
        let provider = MismatchProvider(data: jpeg)
        coordinator.start(selections: [.init(ordinal: 0, localIdentifier: nil)], provider: provider)
        for _ in 0..<200 where destination.summaries.isEmpty { try? await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(destination.inserted, 0)
        XCTAssertEqual(destination.summaries.first?.skipped, 1)
    }
}

@MainActor
private final class MismatchProvider: PhotosImportProviding {
    let data: Data
    init(data: Data) { self.data = data }
    func originalFilename(for selection: PhotosImportSelection) -> String? { "DSC00160.ARW" }
    func transferData(for selection: PhotosImportSelection) async throws -> Data? { data }
}

@MainActor
private final class MismatchDestination: PhotosImportDestination {
    var inserted = 0
    var summaries: [ImportOutcomeSummary] = []
    func preparePhotosImport(totalCount: Int) {}
    func insertPhotosImport(_ item: ImageCollection.PhotoImportItem, ordinal: Int) -> PhotosImportInsertionOutcome {
        inserted += 1
        return .inserted("x")
    }
    func recordPhotosImportFailureDestination(name: String, ordinal: Int?, reason: String) {}
    func finishPhotosImportDestination(summary: ImportOutcomeSummary) { summaries.append(summary) }
}

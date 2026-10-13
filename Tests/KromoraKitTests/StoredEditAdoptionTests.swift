import XCTest

@testable import KromoraKit

/// KRMA-755: the Edit panel binds to `AppViewModel.document`. The stored edit document is a small
/// read that starts at selection, so it must reach the panel as soon as it is read, not after the
/// (slow) source preparation that the pixels no longer wait on.
@MainActor
final class StoredEditAdoptionTests: TempDirectoryTestCase {
    private func waitUntil(
        _ description: String,
        timeout: Duration = .seconds(30),
        _ condition: @escaping @MainActor () -> Bool
    ) async throws {
        let deadline = ContinuousClock.now + timeout
        while !condition() {
            if ContinuousClock.now >= deadline {
                throw TestSynchronizationError.timedOut(description, "condition did not settle")
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    /// Imports photos, gives each a stored exposure edit, and returns the package URL so a second
    /// view model can reopen it the way a relaunch would.
    private func makePackage(storedExposures: [String: Double]) async throws -> URL {
        let names = storedExposures.keys.sorted()
        let photos = try names.map {
            try Fixtures.writeGradientPNG(width: 16, height: 12, named: $0, in: tempDirectory)
        }
        let packageURL = tempDirectory.appendingPathComponent("StoredEdit.kromoralibrary")
        let session = try PortableLibrarySession(at: packageURL)
        _ = try session.importURLs(photos, duplicatePolicy: .importAnyway)
        let viewModel = makeAppViewModel(
            engine: FakeRenderEngine(), portablePackageURL: packageURL,
            portableLibrarySession: session
        )
        viewModel.collection.loadPortableAssets(try session.materializedAssets())
        await viewModel.collection.scanCompletion()
        for name in names {
            let index = try XCTUnwrap(
                viewModel.collection.items.firstIndex { $0.displayName == name })
            viewModel.collection.setSelection(at: index)
            viewModel.openActiveCollectionImage()
            try await waitUntil("\(name) to open") {
                viewModel.sourceName == name && viewModel.previewState == .ready
            }
            viewModel.updateDocument { $0.light.exposure = storedExposures[name] ?? 0 }
        }
        let flushed = await viewModel.flushPendingWrites()
        XCTAssertEqual(flushed, .success)
        await viewModel.shutdown()
        return packageURL
    }

    /// Reopens the package with source preparation held open.
    private func reopen(
        _ packageURL: URL, freshFrameStore: Bool = false, browsingAssets: Bool = false,
        holdPreparation: Bool = true, scheduler: ImageWorkScheduler? = nil
    ) async throws -> (AppViewModel, FakeRenderEngine, PortableLibrarySession) {
        let session = try PortableLibrarySession(at: packageURL, scheduler: scheduler)
        let fake = FakeRenderEngine()
        if holdPreparation { await fake.gateSourcePreparation() }
        let viewModel = makeAppViewModel(
            engine: fake,
            previewFrameStoreDirectory: freshFrameStore
                ? tempDirectory.appendingPathComponent("empty-frames", isDirectory: true) : nil,
            portablePackageURL: packageURL, portableLibrarySession: session
        )
        // A failing assertion must not leave the gated preparation suspended, or the run never exits.
        addTeardownBlock {
            await fake.releaseSourcePreparation()
            await viewModel.shutdown()
        }
        viewModel.collection.loadPortableAssets(
            try browsingAssets ? session.browsingAssets() : session.materializedAssets()
        )
        await viewModel.collection.scanCompletion()
        return (viewModel, fake, session)
    }

    private func select(_ name: String, in viewModel: AppViewModel) throws {
        let index = try XCTUnwrap(
            viewModel.collection.items.firstIndex { $0.displayName == name })
        viewModel.collection.setSelection(at: index)
        viewModel.openActiveCollectionImage()
    }

    private func waitForPreparationToStart(_ fake: FakeRenderEngine) async throws {
        let deadline = Date().addingTimeInterval(5)
        while await fake.sourcePreparationCount == 0 {
            XCTAssertLessThan(Date(), deadline, "source preparation did not start")
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    func testStoredEditsReachThePanelWhileSourcePreparationIsStillPending() async throws {
        let packageURL = try await makePackage(storedExposures: ["one.png": 1.5])
        let (viewModel, fake, _) = try await reopen(packageURL)
        try select("one.png", in: viewModel)
        try await waitForPreparationToStart(fake)

        // Source preparation is held open. The stored document must still reach the panel.
        try await waitUntil("the stored exposure to reach the panel") {
            viewModel.document.light.exposure == 1.5
        }
        XCTAssertEqual(viewModel.previewState, .loading, "the source must still be preparing")
        XCTAssertTrue(
            viewModel.admissionStoredEditsResolved,
            "stored edit and Look identity must resolve before source preparation finishes"
        )

        await fake.releaseSourcePreparation()
        try await waitUntil("the photo to settle") { viewModel.previewState == .ready }
        XCTAssertEqual(viewModel.document.light.exposure, 1.5)
    }

    func testTheFirstRenderUsesTheStoredDocumentSoNoCorrectiveRenderFollows() async throws {
        let packageURL = try await makePackage(storedExposures: ["one.png": 1.5])
        // The first session stored an exact frame, which would skip the render this test inspects,
        // so reopen with an empty frame store.
        let (viewModel, fake, _) = try await reopen(packageURL, freshFrameStore: true)
        try select("one.png", in: viewModel)
        try await waitForPreparationToStart(fake)
        try await waitUntil("the stored exposure to reach the panel") {
            viewModel.document.light.exposure == 1.5
        }

        await fake.releaseSourcePreparation()
        try await waitUntil("the photo to settle") { viewModel.previewState == .ready }

        // The canvas reaches the engine through whichever seam the surface uses; look at all of them.
        let rendered =
            await fake.previewRequests.map(\.document.light.exposure)
            + fake.textureRequests.map(\.document.light.exposure)
            + fake.renderRequests.map(\.document.light.exposure)
        XCTAssertFalse(rendered.isEmpty, "a canvas render must have run")
        XCTAssertEqual(
            Set(rendered), [1.5],
            "no canvas render may use the identity document when the stored one was known first"
        )
    }

    func testASupersededSelectionNeverPublishesTheOldPhotosStoredValues() async throws {
        let packageURL = try await makePackage(
            storedExposures: ["one.png": 1.5, "two.png": -0.5])
        let (viewModel, fake, _) = try await reopen(packageURL)
        try select("one.png", in: viewModel)
        // B supersedes A before A's source preparation ever finishes.
        try select("two.png", in: viewModel)
        try await waitForPreparationToStart(fake)

        try await waitUntil("the second photo's stored exposure") {
            viewModel.document.light.exposure == -0.5
        }
        // Give a stale publication every chance to land, then require B's values to stay.
        for _ in 0..<30 {
            XCTAssertEqual(viewModel.document.light.exposure, -0.5)
            try await Task.sleep(for: .milliseconds(10))
        }
        await fake.releaseSourcePreparation()
        try await waitUntil("the second photo to settle") { viewModel.previewState == .ready }
        XCTAssertEqual(viewModel.sourceName, "two.png")
        XCTAssertEqual(viewModel.document.light.exposure, -0.5)
    }

    func testSettledPhotoWarmsItsBrowsingNeighboursWithoutCreatingTheirSessions() async throws {
        let packageURL = try await makePackage(
            storedExposures: ["one.png": 1.5, "two.png": -0.5, "three.png": 0.75])
        let (viewModel, fake, session) = try await reopen(
            packageURL, browsingAssets: true, holdPreparation: false)
        var recordReads: [PortablePhotoAssetID] = []
        session.assetRecordReadObserver = { recordReads.append($0) }

        try select("one.png", in: viewModel)
        try await waitUntil("the active photo to settle") {
            viewModel.sourceName == "one.png" && viewModel.previewState == .ready
                && viewModel.document.light.exposure == 1.5
                && !viewModel.durableEditHistory.isEmpty
        }
        let activeDocument = viewModel.document
        let activeHistory = viewModel.durableEditHistory
        let neighbourIDs = try ["two.png", "three.png"].map { name -> PhotoAssetID in
            let index = try XCTUnwrap(
                viewModel.collection.items.firstIndex { $0.displayName == name })
            return viewModel.collection.items[index].id
        }

        try await waitUntil("both nearest stored edit documents to warm") {
            neighbourIDs.allSatisfy { id in
                guard let item = viewModel.collection.items.first(where: { $0.id == id }) else {
                    return false
                }
                return !item.asset.source.portableIdentity.sourceFingerprint.isBrowsingPlaceholder
            }
        }
        XCTAssertEqual(viewModel.document, activeDocument)
        XCTAssertEqual(viewModel.durableEditHistory, activeHistory)
        for neighbourID in neighbourIDs {
            XCTAssertNil(viewModel.admissionDocument(for: neighbourID))
        }
        let cacheDeadline = ContinuousClock.now + .seconds(5)
        while await viewModel.editStore.cacheCount < 3 {
            if ContinuousClock.now >= cacheDeadline {
                throw TestSynchronizationError.timedOut(
                    "the neighbour edit documents to enter the cache",
                    "cache count stayed below three"
                )
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        let cacheCount = await viewModel.editStore.cacheCount
        XCTAssertEqual(cacheCount, 3, "the active document and two neighbours should be cached")

        let twoID = try XCTUnwrap(
            viewModel.collection.items.first { $0.displayName == "two.png" }?.id)
        let twoPortableID = try XCTUnwrap(
            viewModel.collection.items.first { $0.id == twoID }?.asset.source.portableIdentity
                .assetID)
        await fake.gateSourcePreparation()
        try select("two.png", in: viewModel)
        try await waitForPreparationToStart(fake)
        try await waitUntil("the warmed neighbour's stored value to reach the panel") {
            viewModel.document.light.exposure == -0.5
        }
        XCTAssertEqual(
            recordReads.filter { $0 == twoPortableID }.count, 0,
            "opening a neighbour with an indexed fingerprint must not resolve its record"
        )
        XCTAssertEqual(viewModel.previewState, .loading)

        await fake.releaseSourcePreparation()
        try await waitUntil("the warmed neighbour to settle") { viewModel.previewState == .ready }
    }

    func testPhotoSwitchMarksSliderPresentationPendingUntilIncomingDocumentArrives() async throws {
        let packageURL = try await makePackage(
            storedExposures: ["one.png": 1.5, "two.png": -0.5])
        let (viewModel, fake, _) = try await reopen(packageURL)
        try select("one.png", in: viewModel)
        try await waitForPreparationToStart(fake)
        try await waitUntil("the first photo's stored exposure") {
            viewModel.document.light.exposure == 1.5
        }
        await fake.releaseSourcePreparation()
        try await waitUntil("the first photo to settle") { viewModel.previewState == .ready }

        try select("two.png", in: viewModel)
        XCTAssertTrue(viewModel.isInspectorSourceDocumentPending)
        try await waitUntil("the second photo's stored exposure") {
            viewModel.document.light.exposure == -0.5
                && !viewModel.isInspectorSourceDocumentPending
        }
    }

    // MARK: - KRMA-904 placeholder materialization fencing

    /// Holds `materializedAsset` for chosen assets until released, ignoring cancellation, the way a
    /// worker read that has already crossed its cancellable boundary behaves.
    private actor MaterializationGate {
        private var held: Set<PortablePhotoAssetID>
        private var waiters: [PortablePhotoAssetID: CheckedContinuation<Void, Never>] = [:]
        private(set) var arrivals: [PortablePhotoAssetID] = []
        init(holding ids: Set<PortablePhotoAssetID>) { held = ids }

        func arrive(_ id: PortablePhotoAssetID) async {
            arrivals.append(id)
            guard held.contains(id) else { return }
            await withCheckedContinuation { waiters[id] = $0 }
        }

        func release(_ id: PortablePhotoAssetID) {
            held.remove(id)
            waiters.removeValue(forKey: id)?.resume()
        }

        /// Frees every held id so a failed test cannot leave `shutdown()` awaiting a gated read.
        func releaseAll() {
            held.removeAll()
            for continuation in waiters.values { continuation.resume() }
            waiters.removeAll()
        }
    }

    /// Reproduces a legacy package whose summaries predate persisted fingerprints, so the grid
    /// projects browsing placeholders that opening must resolve against the record.
    private func makeLegacyPlaceholders(in packageURL: URL) throws {
        let package = try PortableLibraryPackage.open(at: packageURL)
        for shardName in PortableLibraryPackage.allShards {
            var shard = try package.readMembershipShard(shardName)
            for index in shard.entries.indices {
                shard.entries[index].summary.sourceFingerprint = nil
            }
            try package.writeMembershipShard(shard)
        }
    }

    /// Installs a gate and registers its release for every exit path. Teardown blocks run last-in
    /// first-out, so this releases before `reopen`'s teardown awaits `shutdown()`.
    private func installGate(
        holding ids: Set<PortablePhotoAssetID>, on session: PortableLibrarySession
    ) -> MaterializationGate {
        let gate = MaterializationGate(holding: ids)
        session.materializationGate = { await gate.arrive($0) }
        addTeardownBlock { await gate.releaseAll() }
        return gate
    }

    private func waitForArrival(_ gate: MaterializationGate) async throws {
        let deadline = ContinuousClock.now + .seconds(30)
        while await gate.arrivals.isEmpty {
            if ContinuousClock.now >= deadline {
                throw TestSynchronizationError.timedOut(
                    "materialization to start", "no placeholder resolution began")
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    private func portableID(_ name: String, in viewModel: AppViewModel) throws
        -> PortablePhotoAssetID
    {
        try XCTUnwrap(
            viewModel.collection.items.first { $0.displayName == name }?.asset.source
                .portableIdentity.assetID)
    }

    func testShutdownWaitsForPlaceholderMaterializationAndSuppressesItsResult() async throws {
        let packageURL = try await makePackage(storedExposures: ["one.png": 1.5])
        try makeLegacyPlaceholders(in: packageURL)
        let (viewModel, fake, session) = try await reopen(
            packageURL, browsingAssets: true, holdPreparation: false)
        let id = try portableID("one.png", in: viewModel)
        let gate = installGate(holding: [id], on: session)

        try select("one.png", in: viewModel)
        try await waitForArrival(gate)

        let preparationsBeforeShutdown = await fake.sourcePreparationCount
        var shutdownFinished = false
        let shutdown = Task { @MainActor in
            await viewModel.shutdown()
            shutdownFinished = true
        }
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertFalse(shutdownFinished, "shutdown must wait for the in-flight materialization")

        await gate.release(id)
        await shutdown.value
        XCTAssertTrue(
            viewModel.collection.items.first { $0.displayName == "one.png" }?.asset.source
                .portableIdentity.sourceFingerprint.isBrowsingPlaceholder ?? false,
            "a result arriving after shutdown must not replace the collection item")
        let preparations = await fake.sourcePreparationCount
        XCTAssertEqual(preparations, preparationsBeforeShutdown)
        XCTAssertNil(viewModel.sourceImage)
        await viewModel.shutdown()
    }

    func testSlowMaterializationCannotReopenSupersededPhoto() async throws {
        let packageURL = try await makePackage(storedExposures: ["one.png": 1.5, "two.png": -0.5])
        try makeLegacyPlaceholders(in: packageURL)
        let (viewModel, _, session) = try await reopen(
            packageURL, browsingAssets: true, holdPreparation: false)
        let oneID = try portableID("one.png", in: viewModel)
        let gate = installGate(holding: [oneID], on: session)

        try select("one.png", in: viewModel)
        try await waitForArrival(gate)
        try select("two.png", in: viewModel)
        try await waitUntil("the second photo to settle") {
            viewModel.sourceName == "two.png" && viewModel.previewState == .ready
        }

        await gate.release(oneID)
        // The superseded open must not take over the editor. The collection item for one.png is
        // deliberately not asserted: once two.png is idle, neighbour warming
        // (`warmBrowsingNeighbourDocuments`) may legitimately resolve its placeholder, and whether
        // that happens before this point depends on scheduling under the parallel lane.
        for _ in 0..<20 {
            XCTAssertEqual(viewModel.sourceName, "two.png")
            XCTAssertEqual(viewModel.previewState, .ready)
            XCTAssertTrue(viewModel.navigation.isEdit)
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    func testOpeningCollectionAssetAfterShutdownDoesNotChangeNavigation() async throws {
        let packageURL = try await makePackage(storedExposures: ["one.png": 1.5])
        try makeLegacyPlaceholders(in: packageURL)
        let (viewModel, _, session) = try await reopen(
            packageURL, browsingAssets: true, holdPreparation: false)
        let id = try portableID("one.png", in: viewModel)
        let gate = installGate(holding: [id], on: session)
        let url = try XCTUnwrap(
            viewModel.collection.items.first { $0.displayName == "one.png" }?.url)

        await viewModel.shutdown()
        viewModel.openImage(url: url)

        XCTAssertTrue(viewModel.navigation.isGrid)
        let arrivals = await gate.arrivals
        XCTAssertTrue(arrivals.isEmpty, "shutdown must reject new materialization")
    }

    func testLegacyOpenReturnsBeforeFingerprintRepairCommits() async throws {
        let packageURL = try await makePackage(storedExposures: ["one.png": 1.5])
        try makeLegacyPlaceholders(in: packageURL)
        let (viewModel, _, session) = try await reopen(
            packageURL, browsingAssets: true, holdPreparation: false,
            scheduler: ImageWorkScheduler())
        let id = try portableID("one.png", in: viewModel)
        let repairGate = MaterializationGate(holding: [id])
        session.fingerprintRepairGate = { await repairGate.arrive($0) }
        addTeardownBlock { await repairGate.releaseAll() }

        let asset = try await session.materializedAsset(for: id)
        let resolved = asset.source.portableIdentity.sourceFingerprint
        XCTAssertFalse(resolved.isBrowsingPlaceholder)
        try await waitForArrival(repairGate)
        // Returning above, while the repair is held at its gate, proves the open did not wait.

        // A repeat open coalesces onto the pending repair.
        _ = try await session.materializedAsset(for: id)

        await repairGate.release(id)
        try await waitUntil("the repaired fingerprint to publish") {
            session.queryController.index.entry(for: id)?.summary.sourceFingerprint == resolved
        }
        let package = try PortableLibraryPackage.open(at: packageURL)
        let shard = try package.readMembershipShard(PortableLibraryPackage.shard(for: id))
        XCTAssertEqual(
            shard.entries.first { $0.assetID == id }?.summary.sourceFingerprint, resolved)
        let arrivals = await repairGate.arrivals
        XCTAssertEqual(arrivals.count, 1)
        await viewModel.shutdown()
    }

    func testShutdownWithPendingFingerprintRepairDoesNotHang() async throws {
        let packageURL = try await makePackage(storedExposures: ["one.png": 1.5])
        try makeLegacyPlaceholders(in: packageURL)
        let (viewModel, _, session) = try await reopen(
            packageURL, browsingAssets: true, holdPreparation: false,
            scheduler: ImageWorkScheduler())
        let id = try portableID("one.png", in: viewModel)
        let repairGate = MaterializationGate(holding: [id])
        session.fingerprintRepairGate = { await repairGate.arrive($0) }
        addTeardownBlock { await repairGate.releaseAll() }

        _ = try await session.materializedAsset(for: id)
        try await waitForArrival(repairGate)
        await repairGate.release(id)
        await viewModel.shutdown()
    }
}

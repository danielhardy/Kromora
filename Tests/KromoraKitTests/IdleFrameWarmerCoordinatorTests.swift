import CoreGraphics
import CoreImage
import XCTest

@testable import KromoraKit

actor IdleWarmDecodeProbe {
    private(set) var count = 0

    func record() { count += 1 }
}

/// Counts planning runs and can hold one open so a test can interleave main-actor work.
actor IdleWarmPlanProbe {
    private(set) var runCount = 0
    private var gateEnabled = false
    private var gate: CheckedContinuation<Void, Never>?
    private var startWaiter: CheckedContinuation<Void, Never>?

    func enableGate() { gateEnabled = true }

    func record() async {
        runCount += 1
        startWaiter?.resume()
        startWaiter = nil
        if gateEnabled { await withCheckedContinuation { gate = $0 } }
    }

    func waitUntilStarted() async {
        if runCount > 0 { return }
        await withCheckedContinuation { startWaiter = $0 }
    }

    func release() {
        gateEnabled = false
        gate?.resume()
        gate = nil
    }
}

actor IdleWarmTestEngine: RenderEngining {
    private let image: CGImage
    private(set) var thumbnailRequests: [RenderRequest] = []
    private(set) var previewRequests: [RenderRequest] = []
    private(set) var histogramRequestCount = 0
    private var thumbnailGateEnabled = false
    private var thumbnailGate: CheckedContinuation<Void, Never>?
    private(set) var activeRasterCallCount = 0
    private(set) var maximumConcurrentRasterCalls = 0

    init(image: CGImage) { self.image = image }

    func enableThumbnailGate() { thumbnailGateEnabled = true }

    func releaseThumbnailGate() {
        thumbnailGateEnabled = false
        thumbnailGate?.resume()
        thumbnailGate = nil
    }

    func makeThumbnailCGImage(_ request: RenderRequest) async -> sending CGImage? {
        thumbnailRequests.append(request)
        activeRasterCallCount += 1
        maximumConcurrentRasterCalls = max(maximumConcurrentRasterCalls, activeRasterCallCount)
        defer { activeRasterCallCount -= 1 }
        if thumbnailGateEnabled {
            await withCheckedContinuation { thumbnailGate = $0 }
        }
        return image
    }

    func makeCIImage(_ request: RenderRequest) async -> sending CIImage? {
        previewRequests.append(request)
        return CIImage(cgImage: image)
    }

    func makeCanonicalPreviewRaster(
        _ image: sending CIImage, space: WorkingSpace, longEdge: Int
    ) async -> CanonicalPreviewRaster? {
        RenderEngineResources.canonicalPreviewFrame(from: image, space: space, longEdge: longEdge)
    }

    func render(_ request: RenderRequest) async throws -> RenderResult {
        throw ImageError.processingFailed
    }

    func histogram(
        source: ImageSource, document: EditDocument, lut: CubeLUT?, scale: RenderScale,
        space: WorkingSpace, maxDimension: Int
    ) async -> HistogramData? {
        histogramRequestCount += 1
        return nil
    }

    func rawCapabilities(for source: ImageSource) async -> RAWCapabilities? { nil }

    func invalidateLUTCache() async {}

    func requestSources() -> (thumbnails: [PortablePhotoAssetID], previews: [PortablePhotoAssetID]) {
        (
            thumbnailRequests.map(\.source.cacheIdentity.assetID),
            previewRequests.map(\.source.cacheIdentity.assetID)
        )
    }
}

@MainActor
final class IdleWarmTestDestination: IdleFrameWarmerDestination {
    var idleFrameWarmerIsReady = true
    var idleFrameWarmerIsBlocked = false
    var idleFrameWarmerConditions = IdleFrameWarmerConditions(
        isLowPowerModeEnabled: false,
        isThermalStateSeriousOrWorse: false,
        isApplicationActive: true
    )
    var idleFrameWarmerCandidates: [IdleFrameWarmCandidate] = []
    var planGeneration: UInt64 = 0
    private(set) var materializedPageSizes: [Int] = []
    private(set) var planInputRequestCount = 0
    var onMaterialize: (@MainActor () -> Void)?

    func idleFrameWarmerPlanInput() -> IdleFrameWarmPlanInput? {
        planInputRequestCount += 1
        guard let index = try? LibraryIndexProjection(libraryID: UUID(), entries: []) else {
            return nil
        }
        return IdleFrameWarmPlanInput(
            controller: LibraryQueryController(index: index), anchorIDs: [],
            fallbackSelection: 0, recencyOrder: [], generation: planGeneration
        )
    }

    func idleFrameWarmerPlanIsCurrent(generation: UInt64) -> Bool {
        generation == planGeneration
    }

    func idleFrameWarmerCandidates(
        for entries: [IdleFrameWarmPlanEntry]
    ) -> [IdleFrameWarmCandidate] {
        materializedPageSizes.append(entries.count)
        onMaterialize?()
        return entries.compactMap { entry in
            idleFrameWarmerCandidates.first { $0.identity.assetID == entry.assetID }
        }
    }

    /// The candidate list ranked exactly as the production planner ranks index entries.
    func rankedEntries() -> [IdleFrameWarmPlanEntry] {
        idleFrameWarmerCandidates.map {
            IdleFrameWarmPlanEntry(
                assetID: $0.identity.assetID, index: $0.index,
                distanceFromViewport: $0.distanceFromViewport,
                launchHintRecencyRank: $0.launchHintRecencyRank
            )
        }.sorted {
            if $0.distanceFromViewport != $1.distanceFromViewport {
                return $0.distanceFromViewport < $1.distanceFromViewport
            }
            if $0.launchHintRecencyRank != $1.launchHintRecencyRank {
                return $0.launchHintRecencyRank < $1.launchHintRecencyRank
            }
            return $0.index < $1.index
        }
    }
    var idleFrameWarmerActivePortableAssetID: PortablePhotoAssetID?
    var idleFrameWarmerVisiblePortableAssetIDs: Set<PortablePhotoAssetID> = []
    var savedLooks: [PhotoAssetID: LookSignature] = [:]
    var luts: [LUTID: CubeLUT] = [:]

    func idleFrameWarmerSavedLookSignature(for assetID: PhotoAssetID) -> LookSignature? {
        savedLooks[assetID]
    }

    func idleFrameWarmerResolvedLUT(_ id: LUTID?) -> CubeLUT? {
        guard let id else { return nil }
        return luts[id]
    }

    func idleFrameWarmerCanonicalRequest(
        source: ImageSource, assetID: PhotoAssetID, document: EditDocument, lut: CubeLUT?
    ) -> RenderRequest {
        var planner = ResolutionPlanner()
        let plan = planner.plan(
            nativeExtent: document.rotation.orientedExtent(source.nativeExtent),
            crop: document.crop,
            viewportSize: CGSize(width: 2048, height: 2048),
            navigation: CanvasNavigation()
        )
        return RenderRequest(
            source: source, assetID: assetID, document: document, lut: lut,
            targetSize: plan.sourceSize,
            presentationImageExtent: plan.presentationImageExtent,
            quality: .preview, output: .raster, space: .current
        )
    }
}

@MainActor
final class IdleFrameWarmerCoordinatorTests: TempDirectoryTestCase {
    private struct Harness {
        let coordinator: IdleFrameWarmerCoordinator
        let scheduler: ImageWorkScheduler
        let engine: IdleWarmTestEngine
        let destination: IdleWarmTestDestination
        let thumbnailStore: ThumbnailFrameStore
        let previewStore: LatestPreviewFrameStore
        let presentation: PreviewPresentationCoordinator
        let package: PortableLibrarySession
        let planProbe: IdleWarmPlanProbe
    }

    private func makeHarness(
        names: [String], previewCapBytes: Int64 = LatestPreviewFrameStore.defaultCapBytes,
        decodeProbe: IdleWarmDecodeProbe? = nil, pageSize: Int = 24,
        planProbe: IdleWarmPlanProbe = IdleWarmPlanProbe()
    ) async throws -> Harness {
        let urls = try names.enumerated().map { index, name in
            try Fixtures.writeGradientPNG(
                width: 64 + index, height: 48, named: name, in: tempDirectory
            )
        }
        let package = try PortableLibrarySession(
            at: tempDirectory.appendingPathComponent("\(UUID().uuidString).kromoralibrary"),
            indexURL: tempDirectory.appendingPathComponent("index-\(UUID().uuidString).json")
        )
        _ = try package.importURLs(urls, duplicatePolicy: .importAnyway)
        let assets = try package.browsingAssets()
        let candidates = assets.enumerated().map { index, asset in
            let identity = asset.source.portableIdentity
            let source = ImageSource(
                url: asset.url!, nativeExtent: CGSize(width: 64 + index, height: 48),
                portableIdentity: identity,
                existingFileChangeSignature: asset.source.fingerprint
            )
            var document = EditDocument()
            document.adjustments = [.exposure(ev: 0.4)]
            return IdleFrameWarmCandidate(
                index: index, assetID: asset.id, source: source,
                reference: EditSourceReference(
                    assetID: asset.id, portableIdentity: identity, url: asset.url!
                ),
                inMemoryDocument: document, inMemoryLookSignature: LookSignature.none,
                distanceFromViewport: index, launchHintRecencyRank: index
            )
        }
        let scheduler = ImageWorkScheduler()
        let engine = IdleWarmTestEngine(image: try Fixtures.makeCGImage(width: 16, height: 12))
        let thumbnailStore = ThumbnailFrameStore(
            directory: tempDirectory.appendingPathComponent("thumbs-\(UUID().uuidString)")
        )
        let previewStore = LatestPreviewFrameStore(
            directory: tempDirectory.appendingPathComponent("previews-\(UUID().uuidString)"),
            capBytes: previewCapBytes
        )
        let presentation = PreviewPresentationCoordinator(store: previewStore, engine: engine)
        let destination = IdleWarmTestDestination()
        destination.idleFrameWarmerCandidates = candidates
        if let first = candidates.first {
            destination.idleFrameWarmerVisiblePortableAssetIDs = [first.identity.assetID]
        }
        let observer: (@Sendable () async -> Void)?
        if let decodeProbe {
            observer = { await decodeProbe.record() }
        } else {
            observer = nil
        }
        let coordinator = IdleFrameWarmerCoordinator(
            scheduler: scheduler, engine: engine,
            editStore: makeInMemoryEditStore(), thumbnailStore: thumbnailStore,
            previewPresentation: presentation, originalDecodeObserver: observer,
            idleDelay: .zero, observesSystemChanges: false,
            planProvider: { _ in
                await planProbe.record()
                return await destination.rankedEntries()
            },
            pageSize: pageSize, destination: destination
        )
        return Harness(
            coordinator: coordinator, scheduler: scheduler, engine: engine,
            destination: destination, thumbnailStore: thumbnailStore,
            previewStore: previewStore, presentation: presentation, package: package,
            planProbe: planProbe
        )
    }

    private func waitUntil(
        _ description: String,
        timeout: Duration = .seconds(10),
        _ condition: @escaping @MainActor () async -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !(await condition()) {
            if clock.now >= deadline {
                throw TestSynchronizationError.timedOut(description, "warmer did not settle")
            }
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    private func finish(_ harness: Harness) async {
        await harness.coordinator.shutdown()
        await harness.presentation.shutdown()
        await harness.thumbnailStore.flush()
        await harness.thumbnailStore.shutdown()
        await harness.previewStore.waitForPendingWrites()
        await harness.scheduler.cancelAllAndWait()
        await harness.package.shutdown()
    }

    // MARK: Planning

    func testMultiPageLibraryIsOrderedOncePerSnapshotAndMaterializedInBoundedPages() async throws {
        let harness = try await makeHarness(
            names: ["a.png", "b.png", "c.png", "d.png", "e.png"], pageSize: 2
        )
        harness.coordinator.schedule()
        try await waitUntil("five warmed photos") {
            harness.coordinator.progress == IdleFrameWarmerProgress(done: 5, remaining: 0)
        }
        let planRuns = await harness.planProbe.runCount
        XCTAssertEqual(planRuns, 1, "one full ordering per stable snapshot, not per page")
        XCTAssertEqual(harness.destination.materializedPageSizes, [2, 2, 1])
        await finish(harness)
    }

    func testGatedPlannerLetsMainActorRunAndCancelStopsBeforeAnyMaterialization() async throws {
        let harness = try await makeHarness(names: ["gated.png", "gated2.png"])
        await harness.planProbe.enableGate()
        harness.coordinator.schedule()
        await harness.planProbe.waitUntilStarted()

        var sentinelRan = false
        await Task { @MainActor in sentinelRan = true }.value
        XCTAssertTrue(sentinelRan, "planning must not hold the main actor")
        XCTAssertTrue(harness.destination.materializedPageSizes.isEmpty)

        harness.coordinator.cancel()
        await harness.planProbe.release()
        await harness.coordinator.shutdown()
        XCTAssertTrue(harness.destination.materializedPageSizes.isEmpty)
        let requests = await harness.engine.requestSources()
        XCTAssertTrue(requests.thumbnails.isEmpty)
        XCTAssertTrue(requests.previews.isEmpty)
        await finish(harness)
    }

    func testStalePlanIsAbandonedWhenLibraryGenerationChangesDuringPlanning() async throws {
        let harness = try await makeHarness(names: ["stale.png"])
        await harness.planProbe.enableGate()
        harness.coordinator.schedule()
        await harness.planProbe.waitUntilStarted()
        harness.destination.planGeneration &+= 1
        await harness.planProbe.release()
        await harness.coordinator.shutdown()
        XCTAssertTrue(harness.destination.materializedPageSizes.isEmpty)
        let requests = await harness.engine.requestSources()
        XCTAssertTrue(requests.thumbnails.isEmpty)
        await finish(harness)
    }

    func testGenerationChangeBetweenPagesAbandonsPlanAndReplansOnce() async throws {
        let harness = try await makeHarness(names: ["p1.png", "p2.png", "p3.png"], pageSize: 1)
        var bumped = false
        harness.destination.onMaterialize = { [destination = harness.destination] in
            guard !bumped else { return }
            bumped = true
            destination.planGeneration &+= 1
        }
        harness.coordinator.schedule()
        try await waitUntil("replanned pass completes") {
            harness.coordinator.progress == IdleFrameWarmerProgress(done: 3, remaining: 0)
        }
        // The first plan stops after its first page; the second plan pages through all three.
        XCTAssertEqual(harness.destination.materializedPageSizes, [1, 1, 1, 1])
        let planRuns = await harness.planProbe.runCount
        XCTAssertEqual(planRuns, 2)
        await finish(harness)
    }

    func testPlannerRanksByDistanceThenRecencyThenIndexWithoutMaterializingAssets() throws {
        let ids = (0..<9).map { _ in PortablePhotoAssetID() }
        let entries = ids.enumerated().map { offset, id in
            LibraryIndexEntry(from: .init(
                assetID: id,
                recordPath: "Assets/" + PortableLibraryPackage.shard(for: id) + "/" + id.raw
                    + "/asset.json",
                summary: .init(displayName: String(format: "IMG_%02d.png", offset))
            ))
        }
        let controller = LibraryQueryController(
            index: try LibraryIndexProjection(libraryID: UUID(), entries: entries), pageSize: 2
        )
        let order = controller.orderedAssetIDs()
        XCTAssertEqual(Set(order), Set(ids))
        let ranked = IdleFrameWarmPlanner.rank(IdleFrameWarmPlanInput(
            controller: controller, anchorIDs: [order[2], order[6], PortablePhotoAssetID()],
            fallbackSelection: 0, recencyOrder: [order[3], order[1], order[3]], generation: 0
        ))
        XCTAssertEqual(ranked.count, ids.count)
        // Distances to the nearest of positions 2 and 6; ties break on recency, then index.
        XCTAssertEqual(ranked.map(\.index), [2, 6, 3, 1, 5, 7, 0, 4, 8])
        XCTAssertEqual(ranked.map(\.assetID), [2, 6, 3, 1, 5, 7, 0, 4, 8].map { order[$0] })
        XCTAssertEqual(ranked.map(\.distanceFromViewport), [0, 0, 1, 1, 1, 1, 2, 2, 2])

        let fallback = IdleFrameWarmPlanner.rank(IdleFrameWarmPlanInput(
            controller: controller, anchorIDs: [PortablePhotoAssetID()],
            fallbackSelection: 100, recencyOrder: [], generation: 0
        ))
        XCTAssertEqual(fallback.map(\.index), [8, 7, 6, 5, 4, 3, 2, 1, 0])
    }

    func testWarmsAllThreePersistedTiersInViewportAndLaunchHintOrderWithoutPublishing() async throws {
        let decodeProbe = IdleWarmDecodeProbe()
        let harness = try await makeHarness(
            names: ["far.png", "viewport.png", "hinted.png"], decodeProbe: decodeProbe
        )
        let candidates = harness.destination.idleFrameWarmerCandidates
        harness.destination.idleFrameWarmerCandidates = [
            IdleFrameWarmCandidate(
                index: candidates[0].index, assetID: candidates[0].assetID,
                source: candidates[0].source, reference: candidates[0].reference,
                inMemoryDocument: candidates[0].inMemoryDocument,
                inMemoryLookSignature: candidates[0].inMemoryLookSignature,
                distanceFromViewport: 3, launchHintRecencyRank: 0
            ),
            IdleFrameWarmCandidate(
                index: candidates[1].index, assetID: candidates[1].assetID,
                source: candidates[1].source, reference: candidates[1].reference,
                inMemoryDocument: candidates[1].inMemoryDocument,
                inMemoryLookSignature: candidates[1].inMemoryLookSignature,
                distanceFromViewport: 0, launchHintRecencyRank: 2
            ),
            IdleFrameWarmCandidate(
                index: candidates[2].index, assetID: candidates[2].assetID,
                source: candidates[2].source, reference: candidates[2].reference,
                inMemoryDocument: candidates[2].inMemoryDocument,
                inMemoryLookSignature: candidates[2].inMemoryLookSignature,
                distanceFromViewport: 0, launchHintRecencyRank: 0
            )
        ]

        harness.coordinator.schedule()
        do {
            try await waitUntil("three warmed photos") {
                harness.coordinator.progress == IdleFrameWarmerProgress(done: 3, remaining: 0)
            }
        } catch {
            let requests = await harness.engine.requestSources()
            let previewBytes = await harness.previewStore.currentSizeBytes
            let decodeCount = await decodeProbe.count
            XCTFail(
                "\(error); progress=\(harness.coordinator.progress), "
                    + "admissions=\(harness.scheduler.admissionLog.count), "
                    + "cancellations=\(harness.scheduler.cancelledCount), "
                    + "pending=\(harness.scheduler.pendingEditorCount), "
                    + "running=\(harness.scheduler.runningEditorCount), "
                    + "decodes=\(decodeCount), thumbnails=\(requests.thumbnails.count), "
                    + "previews=\(requests.previews.count), previewBytes=\(previewBytes)"
            )
            await finish(harness)
            return
        }

        let sources = await harness.engine.requestSources()
        let expectedOrder = [candidates[2].identity.assetID, candidates[1].identity.assetID,
                             candidates[0].identity.assetID]
        XCTAssertEqual(sources.thumbnails, expectedOrder)
        XCTAssertEqual(sources.previews, expectedOrder)
        let maximumConcurrentRasterCalls = await harness.engine.maximumConcurrentRasterCalls
        XCTAssertEqual(maximumConcurrentRasterCalls, 1)
        XCTAssertTrue(harness.scheduler.admissionLog.allSatisfy {
            $0.id == harness.coordinator.jobID && $0.lane == .editor && $0.priority == .background
        })

        for candidate in candidates {
            let original = await harness.thumbnailStore.metadata(.original, for: candidate.identity)
            let edited = await harness.thumbnailStore.metadata(.edited, for: candidate.identity)
            let preview = await harness.previewStore.metadata(for: candidate.identity)
            XCTAssertEqual(original?.kind, .originalThumbnail480)
            XCTAssertEqual(edited?.kind, .editedThumbnail480)
            XCTAssertEqual(preview?.kind, .preview2048)
        }
        XCTAssertEqual(harness.presentation.presentationSession, nil)
        let histogramRequestCount = await harness.engine.histogramRequestCount
        XCTAssertEqual(histogramRequestCount, 0)
        await finish(harness)
    }

    func testExactStoredTiersSkipSourceDecodeAndEveryRendererRequest() async throws {
        let decodeProbe = IdleWarmDecodeProbe()
        let harness = try await makeHarness(names: ["exact.png"], decodeProbe: decodeProbe)
        let candidate = try XCTUnwrap(harness.destination.idleFrameWarmerCandidates.first)
        harness.coordinator.schedule()
        try await waitUntil("first warm completion") {
            harness.coordinator.progress == IdleFrameWarmerProgress(done: 1, remaining: 0)
        }
        let firstDecodeCount = await decodeProbe.count
        let firstRequestCounts = await harness.engine.requestSources()
        XCTAssertEqual(firstDecodeCount, 1)
        XCTAssertEqual(firstRequestCounts.thumbnails.count, 1)
        XCTAssertEqual(firstRequestCounts.previews.count, 1)

        try FileManager.default.removeItem(at: candidate.reference.url!)
        await harness.coordinator.shutdown()
        let exactHitCoordinator = IdleFrameWarmerCoordinator(
            scheduler: harness.scheduler, engine: harness.engine,
            editStore: makeInMemoryEditStore(), thumbnailStore: harness.thumbnailStore,
            previewPresentation: harness.presentation,
            originalDecodeObserver: { await decodeProbe.record() },
            idleDelay: .zero, observesSystemChanges: false,
            planProvider: { [destination = harness.destination] _ in
                await destination.rankedEntries()
            },
            destination: harness.destination
        )
        exactHitCoordinator.schedule()
        try await waitUntil("exact-hit pass") {
            exactHitCoordinator.progress == IdleFrameWarmerProgress(done: 1, remaining: 0)
        }
        let secondDecodeCount = await decodeProbe.count
        let secondRequestCounts = await harness.engine.requestSources()
        XCTAssertEqual(secondDecodeCount, firstDecodeCount)
        XCTAssertEqual(secondRequestCounts.thumbnails.count, 1)
        XCTAssertEqual(secondRequestCounts.previews.count, 1)
        await exactHitCoordinator.shutdown()
        await finish(harness)
    }

    func testUnsafeSystemConditionsDoNotStartAndSafeStateCanResume() async throws {
        let harness = try await makeHarness(names: ["conditions.png"])
        for conditions in [
            IdleFrameWarmerConditions(
                isLowPowerModeEnabled: true,
                isThermalStateSeriousOrWorse: false, isApplicationActive: true
            ),
            IdleFrameWarmerConditions(
                isLowPowerModeEnabled: false,
                isThermalStateSeriousOrWorse: true, isApplicationActive: true
            ),
            IdleFrameWarmerConditions(
                isLowPowerModeEnabled: false,
                isThermalStateSeriousOrWorse: false, isApplicationActive: false
            )
        ] {
            harness.destination.idleFrameWarmerConditions = conditions
            harness.coordinator.schedule()
            try await Task.sleep(for: .milliseconds(30))
            XCTAssertEqual(harness.scheduler.admissionLog.count, 0)
        }

        harness.destination.idleFrameWarmerConditions = IdleFrameWarmerConditions(
            isLowPowerModeEnabled: false,
            isThermalStateSeriousOrWorse: false, isApplicationActive: true
        )
        harness.coordinator.schedule()
        try await waitUntil("resume after safe system state") {
            harness.coordinator.progress == IdleFrameWarmerProgress(done: 1, remaining: 0)
        }
        await finish(harness)
    }

    func testUnresolvedLookWithoutSavedReferenceLeavesEveryTierUntouched() async throws {
        let harness = try await makeHarness(names: ["unresolved.png"], decodeProbe: .init())
        let candidate = try XCTUnwrap(harness.destination.idleFrameWarmerCandidates.first)
        var document = candidate.inMemoryDocument!
        let missingLookID = LUTID(raw: "missing-look")
        document.lut = LUTSettings(lutID: missingLookID)
        harness.destination.idleFrameWarmerCandidates[0] = IdleFrameWarmCandidate(
            index: candidate.index, assetID: candidate.assetID, source: candidate.source,
            reference: candidate.reference, inMemoryDocument: document,
            inMemoryLookSignature: nil, distanceFromViewport: 0, launchHintRecencyRank: 0
        )

        harness.coordinator.schedule()
        try await waitUntil("unresolved look pass") {
            harness.coordinator.progress == IdleFrameWarmerProgress(done: 1, remaining: 0)
        }

        let original = await harness.thumbnailStore.metadata(.original, for: candidate.identity)
        let edited = await harness.thumbnailStore.metadata(.edited, for: candidate.identity)
        let preview = await harness.previewStore.metadata(for: candidate.identity)
        XCTAssertNil(original)
        XCTAssertNil(edited)
        XCTAssertNil(preview)
        let requests = await harness.engine.requestSources()
        XCTAssertTrue(requests.thumbnails.isEmpty)
        XCTAssertTrue(requests.previews.isEmpty)
        await finish(harness)
    }

    func testPinnedFrameAtLowWaterStopsBeforeSourceDecodeAndKeepsExistingFrame() async throws {
        let harness = try await makeHarness(names: ["pinned.png"], previewCapBytes: 2_000)
        let candidate = try XCTUnwrap(harness.destination.idleFrameWarmerCandidates.first)
        await harness.previewStore.setPinned([candidate.identity.assetID])
        let protectedFrame = try FrameFixtures.frame(
            identity: candidate.identity, width: 512, height: 384
        )
        await harness.previewStore.enqueueWrite(protectedFrame)
        await harness.previewStore.waitForPendingWrites()
        let belowLowWater = await harness.previewStore.isBelowWarmingLowWaterMark()
        XCTAssertFalse(belowLowWater)

        let decodeProbe = IdleWarmDecodeProbe()
        // Rebuild the coordinator around the same stores so the probe observes a denied warm pass.
        let observer: @Sendable () async -> Void = { await decodeProbe.record() }
        let coordinator = IdleFrameWarmerCoordinator(
            scheduler: harness.scheduler, engine: harness.engine,
            editStore: makeInMemoryEditStore(), thumbnailStore: harness.thumbnailStore,
            previewPresentation: harness.presentation, originalDecodeObserver: observer,
            idleDelay: .zero, observesSystemChanges: false,
            planProvider: { [destination = harness.destination] _ in
                await destination.rankedEntries()
            },
            destination: harness.destination
        )
        coordinator.schedule()
        try await waitUntil("capacity stop") {
            harness.scheduler.admissionLog.count == 1
                && !harness.scheduler.contains(coordinator.jobID)
        }
        let decodeCount = await decodeProbe.count
        let original = await harness.thumbnailStore.metadata(.original, for: candidate.identity)
        let hasProtectedFrame = await harness.previewStore.contains(candidate.identity)
        let storedMetadata = await harness.previewStore.metadata(for: candidate.identity)
        XCTAssertEqual(decodeCount, 0)
        XCTAssertNil(original)
        XCTAssertTrue(hasProtectedFrame)
        XCTAssertEqual(storedMetadata, protectedFrame.metadata)
        await coordinator.shutdown()
        await finish(harness)
    }

    func testCancellationFencesLateThumbnailResultBeforeEditedOrPreviewWrites() async throws {
        let harness = try await makeHarness(names: ["cancelled.png"])
        let candidate = try XCTUnwrap(harness.destination.idleFrameWarmerCandidates.first)
        await harness.engine.enableThumbnailGate()
        harness.coordinator.schedule()
        try await waitUntil("gated edited thumbnail") {
            await harness.engine.thumbnailRequests.count == 1
        }

        harness.destination.idleFrameWarmerIsBlocked = true
        harness.coordinator.cancel()
        await harness.engine.releaseThumbnailGate()
        try await waitUntil("late renderer result returns") {
            await harness.engine.activeRasterCallCount == 0
        }
        try await Task.sleep(for: .milliseconds(20))

        let edited = await harness.thumbnailStore.metadata(.edited, for: candidate.identity)
        let preview = await harness.previewStore.metadata(for: candidate.identity)
        XCTAssertNil(edited)
        XCTAssertNil(preview)
        harness.destination.idleFrameWarmerIsBlocked = false
        harness.coordinator.schedule()
        try await waitUntil("warmer resumes on the next idle pass") {
            harness.coordinator.progress == IdleFrameWarmerProgress(done: 1, remaining: 0)
        }
        let resumedEdited = await harness.thumbnailStore.metadata(.edited, for: candidate.identity)
        let resumedPreview = await harness.previewStore.metadata(for: candidate.identity)
        XCTAssertNotNil(resumedEdited)
        XCTAssertEqual(resumedPreview?.kind, .preview2048)
        await finish(harness)
    }

    func testCanonicalWriteRejectsNoncanonicalPreviewAndROIRenders() async throws {
        let harness = try await makeHarness(names: ["roi.png"])
        let candidate = try XCTUnwrap(harness.destination.idleFrameWarmerCandidates.first)
        let document = candidate.inMemoryDocument!
        let image = CIImage(cgImage: try Fixtures.makeCGImage(width: 16, height: 12))
        let roiRequest = RenderRequest(
            source: candidate.source, assetID: candidate.assetID, document: document, lut: nil,
            targetSize: CGSize(width: 128, height: 96),
            sourceROI: CGRect(x: 0, y: 0, width: 8, height: 8), quality: .preview,
            output: .raster, space: .current
        )
        let reducedRequest = RenderRequest(
            source: candidate.source, assetID: candidate.assetID, document: document, lut: nil,
            targetSize: CGSize(width: 8, height: 6), quality: .preview,
            output: .raster, space: .current
        )

        let admitted = await harness.presentation.writeCanonicalForWarmer(image, for: roiRequest)
        let reducedAdmitted = await harness.presentation.writeCanonicalForWarmer(
            image, for: reducedRequest
        )
        let preview = await harness.previewStore.metadata(for: candidate.identity)
        XCTAssertFalse(admitted)
        XCTAssertFalse(reducedAdmitted)
        XCTAssertNil(preview)
        await finish(harness)
    }
}

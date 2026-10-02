import CoreGraphics
import CoreImage
import Foundation
import XCTest

@testable import KromoraKit

@MainActor
final class PreviewPresentationCoordinatorTests: TempDirectoryTestCase {
    func testStoredFrameLookupRecordsExactlyOneLedgerEntryForEachOutcome() async throws {
        let ledger = FrameLookupLedger()
        let directory = tempDirectory.appendingPathComponent("preview-ledger-\(UUID().uuidString)")
        let store = LatestPreviewFrameStore(directory: directory)
        let coordinator = PreviewPresentationCoordinator(store: store, frameLookupLedger: ledger)
        let identity = FrameFixtures.identity()
        let assetID = PhotoAssetID.imported(UUID())

        coordinator.beginPresentationSession(assetID: assetID, identity: identity, generation: 1)
        coordinator.beginStoredFrameLookup(assetID: assetID, identity: identity, generation: 1) { _ in }
        try await waitForLedgerCount(1, ledger: ledger)
        var records = await ledger.snapshot()
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].surface, .editPreview)
        XCTAssertEqual(records[0].outcome, .missingFile)

        let corruptIdentity = FrameFixtures.identity()
        await store.enqueueWrite(try FrameFixtures.frame(identity: corruptIdentity))
        await store.waitForPendingWrites()
        let assetHash = try XCTUnwrap(LatestPreviewFrameStore.assetHash(corruptIdentity.assetID))
        try Data("damaged envelope".utf8).write(
            to: directory.appendingPathComponent("\(assetHash).kframe")
        )
        coordinator.beginPresentationSession(
            assetID: assetID, identity: corruptIdentity, generation: 2
        )
        coordinator.beginStoredFrameLookup(
            assetID: assetID, identity: corruptIdentity, generation: 2
        ) { _ in }
        try await waitForLedgerCount(2, ledger: ledger)
        records = await ledger.snapshot()
        XCTAssertEqual(records.count, 2)
        XCTAssertEqual(records.map(\.surface), [.editPreview, .editPreview])
        XCTAssertEqual(records.map(\.outcome), [.missingFile, .corrupt])
    }

    func testGenerationFencesAreIndependentAcrossPresentationSurfaces() throws {
        let coordinator = makeCoordinator()

        coordinator.advanceDisplayRevision()
        coordinator.advanceDisplayRevision()
        coordinator.advanceComparisonRevision()

        XCTAssertEqual(coordinator.displayRevision, 2)
        XCTAssertEqual(coordinator.comparisonRevision, 1)
        coordinator.resetForSource()
        XCTAssertEqual(coordinator.displayRevision, 3)
        XCTAssertEqual(coordinator.comparisonRevision, 2)
    }

    func testPresentationSessionFencesCandidatesAndTracksFirstAndConfirmedFrames() throws {
        let coordinator = makeCoordinator()
        let source = ImageSource(
            backing: .data(Data("presentation-session".utf8)),
            kind: .standard, nativeExtent: CGSize(width: 32, height: 24)
        )
        let assetID = PhotoAssetID(rawValue: "presentation-session-asset")
        let generation: UInt64 = 9
        coordinator.beginPresentationSession(
            assetID: assetID, identity: source.portableIdentity, generation: generation
        )

        XCTAssertTrue(coordinator.presentProvisional(
            .editedThumbnail, assetID: assetID, identity: source.portableIdentity,
            generation: generation
        ))
        coordinator.confirmProvisionalPresentation(
            .editedThumbnail, assetID: assetID, identity: source.portableIdentity,
            generation: generation
        )
        XCTAssertFalse(coordinator.presentProvisional(
            .embeddedJPEG, assetID: assetID, identity: source.portableIdentity,
            generation: generation
        ), "an embedded JPEG must not add a hop after a same-asset thumbnail")
        XCTAssertFalse(coordinator.presentProvisional(
            .originalThumbnail, assetID: assetID, identity: source.portableIdentity,
            generation: generation
        ), "an original thumbnail must not replace an already visible edited thumbnail")
        XCTAssertFalse(coordinator.presentProvisional(
            .originalThumbnail, assetID: assetID, identity: source.portableIdentity,
            generation: generation - 1
        ), "late candidates from an older generation must be rejected")
        XCTAssertTrue(coordinator.admitsPublication(
            assetID: assetID, identity: source.portableIdentity, generation: generation
        ))
        coordinator.confirmRenderedFrame(
            assetID: assetID, identity: source.portableIdentity, generation: generation
        )

        let session = try XCTUnwrap(coordinator.presentationSession)
        XCTAssertEqual(session.state, .confirmed)
        XCTAssertEqual(session.candidateSource, .rendered)
        XCTAssertEqual(session.distinctFrameCount, 2)
        XCTAssertNotNil(session.firstPixelLatencyMilliseconds)
        XCTAssertNotNil(session.confirmedLatencyMilliseconds)
        XCTAssertEqual(session.staleGenerationDrops, 1)
    }

    func testResolutionPlannerStateIsIndependentAndResettable() throws {
        let coordinator = makeCoordinator()
        let document = EditDocument()
        var navigation = CanvasNavigation()
        navigation.toggleFitAndRememberedZoom()
        let zoomed = coordinator.plan(
            for: document,
            nativeExtent: CGSize(width: 4000, height: 3000),
            viewportSize: CGSize(width: 1000, height: 1000),
            surface: .mainPreview,
            navigation: navigation
        )
        navigation.fit()
        let comparisonFit = coordinator.plan(
            for: document,
            nativeExtent: CGSize(width: 4000, height: 3000),
            viewportSize: CGSize(width: 1000, height: 1000),
            surface: .comparisonBaseline,
            navigation: navigation
        )
        XCTAssertGreaterThan(zoomed.level, comparisonFit.level)

        coordinator.resetPlanners()
        let resetMain = coordinator.plan(
            for: document,
            nativeExtent: CGSize(width: 4000, height: 3000),
            viewportSize: CGSize(width: 1000, height: 1000),
            surface: .mainPreview,
            navigation: navigation
        )
        XCTAssertEqual(resetMain, comparisonFit)
    }

    func testCanonicalWriteRecordsEveryFrameSignatureComponent() async throws {
        let coordinator = makeCoordinator()
        let source = ImageSource(
            backing: .data(Data("frame-signature-source".utf8)),
            kind: .standard,
            nativeExtent: CGSize(width: 32, height: 24)
        )
        var document = EditDocument()
        document.adjustments = [.exposure(ev: 0.4)]
        let request = RenderRequest(
            source: source, document: document, targetSize: CGSize(width: 32, height: 24),
            quality: .preview, space: .displayP3
        )
        coordinator.writeCanonical(
            CIImage(cgImage: try Fixtures.makeCGImage(width: 32, height: 24)), for: request
        )
        try await waitUntil("canonical frame write") {
            await coordinator.store.contains(source.portableIdentity)
        }
        await coordinator.store.waitForPendingWrites()

        let metadata = try unwrapAwaited(await coordinator.store.metadata(for: source.portableIdentity))
        XCTAssertEqual(metadata.signature.source, source.portableIdentity)
        XCTAssertEqual(metadata.signature.editHash, document.editHash)
        XCTAssertEqual(metadata.signature.look, .none)
        XCTAssertEqual(metadata.signature.workingSpace, .displayP3)
        XCTAssertEqual(metadata.signature.pixelEpoch, RenderPipeline.pixelEpoch)
        XCTAssertEqual(metadata.rasterColorSpace, .displayP3)
        XCTAssertEqual(metadata.kind, .preview2048)
        XCTAssertEqual(max(metadata.pixelWidth, metadata.pixelHeight), 2048)
        XCTAssertEqual(metadata.geometry.orientedAspectRatio, 32.0 / 24.0, accuracy: 0.001)
    }

    func testCanonicalWritesRequirePreviewQualityACompleteFrameAndAResolvedLook() async throws {
        let coordinator = makeCoordinator()
        let source = ImageSource(
            backing: .data(Data("canonical-write-source".utf8)),
            kind: .standard,
            nativeExtent: CGSize(width: 32, height: 24)
        )
        let identity = source.portableIdentity
        let image = CIImage(cgImage: try Fixtures.makeCGImage(width: 32, height: 24))

        let thumbnailRequest = RenderRequest(
            source: source, document: EditDocument(), quality: .thumbnail
        )
        coordinator.writeCanonical(image, for: thumbnailRequest)
        let interactiveRequest = RenderRequest(
            source: source, document: EditDocument(), quality: .interactive
        )
        coordinator.writeCanonical(image, for: interactiveRequest)
        let roiRequest = RenderRequest(
            source: source,
            document: EditDocument(),
            sourceROI: CGRect(x: 1, y: 1, width: 10, height: 10),
            quality: .preview
        )
        coordinator.writeCanonical(image, for: roiRequest)
        let unresolvedRequest = RenderRequest(
            source: source,
            document: EditDocument(lut: LUTSettings(lutID: LUTID(raw: "missing"), intensity: 1)),
            quality: .preview
        )
        coordinator.writeCanonical(image, for: unresolvedRequest)
        try await Task.sleep(for: .milliseconds(150))
        await coordinator.store.waitForPendingWrites()
        let wroteEarly = await coordinator.store.contains(identity)
        XCTAssertFalse(
            wroteEarly,
            "thumbnail, interactive, ROI, and unresolved-Look output never persists"
        )

        let completeRequest = RenderRequest(
            source: source, document: EditDocument(), quality: .preview
        )
        coordinator.writeCanonical(image, for: completeRequest)
        try await waitUntil("canonical frame write") { await coordinator.store.contains(identity) }
    }

    func testStoredFrameLookupYieldsAUsableCandidateOnlyForTheSelectedSession() async throws {
        let coordinator = makeCoordinator()
        let identity = FrameFixtures.identity()
        let assetID = PhotoAssetID.imported(UUID())
        await coordinator.store.enqueueWrite(try FrameFixtures.frame(identity: identity))
        await coordinator.store.waitForPendingWrites()

        coordinator.beginPresentationSession(assetID: assetID, identity: identity, generation: 7)
        var delivered: [PreviewPresentationCoordinator.StoredFrameCandidate?] = []
        coordinator.beginStoredFrameLookup(
            assetID: assetID, identity: identity, generation: 7
        ) { delivered.append($0) }
        // A newer selection begins before the read lands: the old result must be dropped.
        coordinator.beginPresentationSession(
            assetID: PhotoAssetID.imported(UUID()), identity: FrameFixtures.identity(), generation: 8
        )
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertTrue(delivered.isEmpty, "a lookup from an older selection must never deliver")
        if case .idle = coordinator.storedFrameLookup {} else { XCTFail("new session starts idle") }

        coordinator.beginPresentationSession(assetID: assetID, identity: identity, generation: 9)
        coordinator.beginStoredFrameLookup(
            assetID: assetID, identity: identity, generation: 9
        ) { delivered.append($0) }
        try await waitUntil("candidate delivery") { !delivered.isEmpty }
        XCTAssertNotNil(delivered.first ?? nil)
        XCTAssertTrue(
            coordinator.presentProvisional(
                .storedFrame, assetID: assetID, identity: identity, generation: 9
            )
        )
    }

    func testAConfirmedFrameConsumesTheStoredCandidate() async throws {
        let coordinator = makeCoordinator()
        let identity = FrameFixtures.identity()
        let assetID = PhotoAssetID.imported(UUID())
        await coordinator.store.enqueueWrite(try FrameFixtures.frame(identity: identity))
        await coordinator.store.waitForPendingWrites()
        coordinator.beginPresentationSession(assetID: assetID, identity: identity, generation: 1)
        var delivered = false
        coordinator.beginStoredFrameLookup(
            assetID: assetID, identity: identity, generation: 1
        ) { _ in delivered = true }
        try await waitUntil("candidate delivery") { delivered }
        let request = RenderRequest(
            source: ImageSource(
                backing: .data(Data("x".utf8)), kind: .standard,
                nativeExtent: CGSize(width: 4, height: 4), portableIdentity: identity
            ),
            document: EditDocument(), quality: .preview
        )
        XCTAssertNotNil(
            coordinator.classifyStoredFrame(for: request, sourceRevision: 1, editsResolved: true)
        )

        coordinator.confirmRenderedFrame(assetID: assetID, identity: identity, generation: 1)

        XCTAssertNil(
            coordinator.classifyStoredFrame(for: request, sourceRevision: 1, editsResolved: true),
            "after the first confirmed frame an edit must render, never reuse the old pixels"
        )
    }

    func testAnUnusableStoredFrameIsReportedAsAMiss() async throws {
        let coordinator = makeCoordinator()
        let stored = FrameFixtures.identity(content: "old-bytes")
        let current = FrameFixtures.identity(asset: stored.assetID, content: "new-bytes")
        let assetID = PhotoAssetID.imported(UUID())
        await coordinator.store.enqueueWrite(try FrameFixtures.frame(identity: stored))
        await coordinator.store.waitForPendingWrites()
        coordinator.beginPresentationSession(assetID: assetID, identity: current, generation: 1)
        var result: PreviewPresentationCoordinator.StoredFrameCandidate??
        coordinator.beginStoredFrameLookup(
            assetID: assetID, identity: current, generation: 1
        ) { result = .some($0) }
        try await waitUntil("lookup") { result != nil }
        XCTAssertNil(result ?? nil)
        XCTAssertFalse(
            coordinator.presentProvisional(
                .storedFrame, assetID: assetID, identity: current, generation: 1
            ) && coordinator.isStoredFrameLookupLoading
        )
    }

    func testStoredFrameReplacesThumbnailAndEmbeddedCandidatesButNothingReplacesIt() {
        let coordinator = makeCoordinator()
        let identity = FrameFixtures.identity()
        let assetID = PhotoAssetID.imported(UUID())
        coordinator.beginPresentationSession(assetID: assetID, identity: identity, generation: 1)
        XCTAssertTrue(coordinator.presentProvisional(
            .originalThumbnail, assetID: assetID, identity: identity, generation: 1))
        XCTAssertTrue(coordinator.presentProvisional(
            .storedFrame, assetID: assetID, identity: identity, generation: 1))
        for source in [
            PreviewPresentationCoordinator.CandidateSource.editedThumbnail,
            .originalThumbnail, .embeddedJPEG,
        ] {
            XCTAssertFalse(coordinator.presentProvisional(
                source, assetID: assetID, identity: identity, generation: 1), "\(source)")
        }
    }

    private func makeCoordinator() -> PreviewPresentationCoordinator {
        let directory = tempDirectory.appendingPathComponent("preview-frames-\(UUID().uuidString)")
        return PreviewPresentationCoordinator(
            store: LatestPreviewFrameStore(directory: directory, capBytes: 10_000_000)
        )
    }

    private func waitUntil(
        _ description: String,
        timeout: Duration = .seconds(5),
        _ condition: @escaping @MainActor () async -> Bool
    ) async throws {
        let deadline = ContinuousClock.now + timeout
        while !(await condition()) {
            if ContinuousClock.now >= deadline {
                throw TestSynchronizationError.timedOut(description, "condition did not settle")
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    private func waitForLedgerCount(
        _ count: Int, ledger: FrameLookupLedger,
        file: StaticString = #filePath, line: UInt = #line
    ) async throws {
        let deadline = Date().addingTimeInterval(3)
        while await ledger.snapshot().count < count {
            if Date() > deadline { return XCTFail("timed out waiting for ledger entry", file: file, line: line) }
            try await Task.sleep(for: .milliseconds(5))
        }
    }
}

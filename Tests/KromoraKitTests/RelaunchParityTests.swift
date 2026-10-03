import Foundation
import AppKit
import CoreGraphics
import XCTest

@testable import KromoraKit

private actor ThumbnailDecodeProbe {
    private(set) var count = 0

    func record() { count += 1 }
}

@MainActor
private final class ThumbnailRasterProbe {
    private(set) var rasters: [NSImage] = []

    func record(_ image: NSImage) { rasters.append(image) }
}

/// Exercises persisted presentation frames across distinct application and collection lifetimes.
/// This intentionally loads the package's cheap browsing projection in both launches: that is the
/// startup path whose source fingerprint used to differ from the resolved edit source.
@MainActor
final class RelaunchParityTests: TempDirectoryTestCase {
    private let timeout: TimeInterval = 8

    private func waitUntil(
        _ description: String,
        _ condition: @escaping @MainActor () async -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !(await condition()) {
            if Date() >= deadline {
                throw TestSynchronizationError.timedOut(description, "presentation did not settle")
            }
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    private func model(
        packageURL: URL, previewDirectory: URL, thumbnailDirectory: URL,
        looksDirectory: URL, engine: FakeRenderEngine,
        decodeProbe: ThumbnailDecodeProbe? = nil
    ) throws -> (AppViewModel, PortableLibrarySession) {
        let session = try PortableLibrarySession(at: packageURL)
        let decodeObserver: (@Sendable () async -> Void)?
        if let decodeProbe {
            decodeObserver = { await decodeProbe.record() }
        } else {
            decodeObserver = nil
        }
        let originalThumbnailProvider: ImageCollection.OriginalThumbnailProvider = {
            url, data, fingerprint, identity, store, ledger, surface in
            await OriginalThumbnailLoader.load(
                url: url, data: data, dataFingerprint: fingerprint,
                identity: identity, store: store, ledger: ledger, surface: surface,
                decodeObserver: decodeObserver
            )
        }
        let viewModel = makeAppViewModel(
            engine: engine, userLookFolderURL: looksDirectory,
            previewFrameStoreDirectory: previewDirectory,
            thumbnailFrameStoreDirectory: thumbnailDirectory,
            portablePackageURL: packageURL, portableLibrarySession: session,
            originalThumbnailProvider: originalThumbnailProvider
        )
        return (viewModel, session)
    }

    private func pixels(of image: NSImage?) throws -> [UInt8] {
        var rect = CGRect(origin: .zero, size: image?.size ?? .zero)
        let cgImage = try XCTUnwrap(image?.cgImage(forProposedRect: &rect, context: nil, hints: nil))
        return try Pixels.bytes(of: cgImage)
    }

    private struct SinglePhotoRelaunch {
        let packageURL: URL
        let previewDirectory: URL
        let thumbnailDirectory: URL
        let looksDirectory: URL
        let sourceURL: URL
        let reference: EditSourceReference
        let identity: PortablePhotoIdentity
        let seedSignature: FrameSignature
    }

    /// Seed one durable frame, then close every package session so the next model is a real
    /// relaunch. The returned identity is the identity captured by the settled first session.
    private func seedSinglePhotoRelaunch() async throws -> SinglePhotoRelaunch {
        let packageURL = tempDirectory.appendingPathComponent("Invalidation.kromoralibrary")
        let previewDirectory = tempDirectory.appendingPathComponent("Invalidation/Previews")
        let thumbnailDirectory = tempDirectory.appendingPathComponent("Invalidation/Thumbnails")
        let looksDirectory = tempDirectory.appendingPathComponent("Invalidation/Looks", isDirectory: true)
        try FileManager.default.createDirectory(at: looksDirectory, withIntermediateDirectories: true)
        let sourceURL = try Fixtures.writeGradientPNG(
            width: 64, height: 48, named: "invalidation.png", in: tempDirectory
        )
        let package = try PortableLibrarySession(at: packageURL)
        _ = try package.importURLs([sourceURL], duplicatePolicy: .importAnyway)
        let asset = try XCTUnwrap(package.materializedAssets().first)
        try seedSourceAspectRatios(
            ["invalidation.png": 64.0 / 48.0], assets: [asset], package: package.package
        )
        let reference = EditSourceReference(
            assetID: asset.id, portableIdentity: asset.source.portableIdentity, url: asset.url
        )
        var document = EditDocument()
        document.adjustments = [.exposure(ev: 0.4)]
        try await EditDocumentStore(package: package.package, lease: package.lease)
            .save(document, for: reference)
        try package.refreshIndex()
        await package.shutdown()

        let firstEngine = FakeRenderEngine()
        let (first, firstSession) = try model(
            packageURL: packageURL, previewDirectory: previewDirectory,
            thumbnailDirectory: thumbnailDirectory, looksDirectory: looksDirectory,
            engine: firstEngine
        )
        first.collection.loadPortableAssets(try firstSession.browsingAssets())
        await first.collection.scanCompletion()
        first.collection.beginThumbnailDemand()
        first.collection.requestVisibleThumbnails(for: first.collection.items.map(\.id))
        try await waitUntil("seed edited thumbnail") {
            first.collection.items.first?.editedThumbnailRevision != nil
        }
        first.collection.setSelection(at: 0)
        first.openActiveCollectionImage()
        try await waitUntil("seed stored edit confirmed preview") {
            let requests = await firstEngine.previewRequests
            return first.admissionDocument.editHash == document.editHash
                && requests.last?.document.editHash == document.editHash
                && first.presentationSessionForDiagnostics?.state == .confirmed
        }
        let previewRequests = await firstEngine.previewRequests
        let seedRequest = try XCTUnwrap(previewRequests.last)
        // Use the package record's resolved identity as the baseline. The first UI request can
        // still carry the browsing placeholder; that separate relaunch mismatch belongs to the
        // multi-photo parity test, while these tests isolate one invalidation input at a time.
        let identity = asset.source.portableIdentity
        let seedSignature = FrameSignature(
            source: identity, editHash: document.editHash, look: .none,
            workingSpace: seedRequest.space, pixelEpoch: RenderPipeline.pixelEpoch
        )
        let flushResult = await first.flushPendingWrites()
        XCTAssertEqual(flushResult, .success)
        await first.thumbnailFrameStore.flush()
        await first.shutdown()
        let previewStore = LatestPreviewFrameStore(directory: previewDirectory)
        // The renderer fake does not produce canonical store rasters. Seed the same complete
        // signature the first session requested, so each relaunch variant below changes only its
        // named input. A deliberately mismatched seed would make every case a cache miss.
        let seedFrame = try FrameFixtures.frame(
            identity: identity, edit: seedSignature.editHash, look: seedSignature.look,
            space: seedSignature.workingSpace, epoch: seedSignature.pixelEpoch
        )
        XCTAssertEqual(
            FrameClassifier.classify(
                seedFrame.metadata,
                against: FrameCurrentInputs(
                    source: seedSignature.source, editHash: seedSignature.editHash,
                    look: seedSignature.look, workingSpace: seedSignature.workingSpace,
                    pixelEpoch: seedSignature.pixelEpoch
                )
            ),
            .exact,
            "the unchanged-input control must classify the persisted seed as exact"
        )
        await previewStore.enqueueWrite(seedFrame)
        await previewStore.waitForPendingWrites()
        let thumbnailStore = ThumbnailFrameStore(directory: thumbnailDirectory)
        await thumbnailStore.enqueueWrite(PresentationFrame(
            metadata: FrameFixtures.metadata(
                identity: identity, edit: seedSignature.editHash, look: seedSignature.look,
                space: seedSignature.workingSpace, epoch: seedSignature.pixelEpoch,
                kind: .editedThumbnail480
            ),
            rasterData: try FrameFixtures.jpeg()
        ))
        await thumbnailStore.flush()
        return SinglePhotoRelaunch(
            packageURL: packageURL, previewDirectory: previewDirectory,
            thumbnailDirectory: thumbnailDirectory, looksDirectory: looksDirectory,
            sourceURL: try XCTUnwrap(asset.url), reference: reference, identity: identity,
            seedSignature: seedSignature
        )
    }

    private func reopenedSinglePhoto(
        _ fixture: SinglePhotoRelaunch, engine: FakeRenderEngine,
        expectedEditHash: String? = nil
    ) async throws -> (AppViewModel, PortableLibrarySession) {
        let (viewModel, session) = try model(
            packageURL: fixture.packageURL, previewDirectory: fixture.previewDirectory,
            thumbnailDirectory: fixture.thumbnailDirectory, looksDirectory: fixture.looksDirectory,
            engine: engine
        )
        // This helper isolates signature invalidation from the separate browsing-placeholder
        // regression covered by the main two-session test below.
        viewModel.collection.loadPortableAssets(try session.materializedAssets())
        await viewModel.collection.scanCompletion()
        viewModel.collection.beginThumbnailDemand()
        viewModel.collection.requestVisibleThumbnails(for: viewModel.collection.items.map(\.id))
        try await waitUntil("relaunch edited thumbnail") {
            viewModel.collection.items.first?.editedThumbnailRevision != nil
        }
        viewModel.collection.setSelection(at: 0)
        viewModel.openActiveCollectionImage()
        let expectedEditHash = expectedEditHash ?? fixture.seedSignature.editHash
        try await waitUntil("relaunch stored edit confirmed preview") {
            let requests = await engine.previewRequests
            return viewModel.admissionDocument.editHash == expectedEditHash
                && (requests.last?.document.editHash == expectedEditHash || requests.isEmpty)
                && viewModel.presentationSessionForDiagnostics?.state == .confirmed
        }
        try await Task.sleep(for: .milliseconds(100))
        return (viewModel, session)
    }

    private func assertNoPrematureFallback(
        _ session: PreviewPresentationCoordinator.PresentationSession?, file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let sources = session?.provisionalCandidateSources ?? []
        XCTAssertFalse(sources.contains(.embeddedJPEG), "embedded JPEG was published before confirmation", file: file, line: line)
        XCTAssertFalse(sources.contains(.originalThumbnail), "original thumbnail was published before confirmation", file: file, line: line)
    }

    func testChangedEditBetweenSessionsInvalidatesPersistedFrameOnce() async throws {
        let fixture = try await seedSinglePhotoRelaunch()
        let package = try PortableLibrarySession(at: fixture.packageURL)
        var changed = EditDocument()
        changed.adjustments = [.exposure(ev: 1.1)]
        let maybeStoredFrame = await LatestPreviewFrameStore(directory: fixture.previewDirectory)
            .read(for: fixture.identity)
        let storedFrame = try XCTUnwrap(maybeStoredFrame)
        XCTAssertEqual(
            FrameClassifier.classify(
                storedFrame.frame.metadata,
                against: FrameCurrentInputs(
                    source: fixture.seedSignature.source, editHash: changed.editHash,
                    look: fixture.seedSignature.look,
                    workingSpace: fixture.seedSignature.workingSpace,
                    pixelEpoch: fixture.seedSignature.pixelEpoch
                )
            ),
            .staleCompatible,
            "only the edit hash should differ from the exact seed"
        )
        try await EditDocumentStore(package: package.package, lease: package.lease)
            .save(changed, for: fixture.reference)
        await package.shutdown()

        let engine = FakeRenderEngine()
        let (reopened, _) = try await reopenedSinglePhoto(
            fixture, engine: engine, expectedEditHash: changed.editHash
        )
        let diagnostics = try XCTUnwrap(reopened.presentationSessionForDiagnostics)
        let previewCount = await engine.previewRequests.count
        let thumbnailCount = await engine.thumbnailRequests.count
        XCTAssertEqual(diagnostics.confirmedFrameCount, 1)
        XCTAssertEqual(previewCount, 1, "a changed edit must render once")
        XCTAssertEqual(thumbnailCount, 1, "a changed edit must render its edited thumbnail once")
        assertNoPrematureFallback(diagnostics)
        await reopened.shutdown()
    }

    func testStaleEditedFrameIsFirstPaintAndGetsOneReplacement() async throws {
        let fixture = try await seedSinglePhotoRelaunch()
        let frameStore = ThumbnailFrameStore(directory: fixture.thumbnailDirectory)
        let storedFrames = await frameStore.readFrames(for: fixture.identity)
        let staleFrame = try XCTUnwrap(storedFrames.edited)
        let stalePixels = try Pixels.bytes(of: staleFrame.image)

        let package = try PortableLibrarySession(at: fixture.packageURL)
        var changed = EditDocument()
        changed.adjustments = [.exposure(ev: 1.1)]
        try await EditDocumentStore(package: package.package, lease: package.lease)
            .save(changed, for: fixture.reference)
        try package.refreshIndex()
        await package.shutdown()

        PlatformThumbnailProvider.invalidateCache()
        let decodeProbe = ThumbnailDecodeProbe()
        let engine = FakeRenderEngine()
        await engine.gateThumbnails()
        let (viewModel, session) = try model(
            packageURL: fixture.packageURL, previewDirectory: fixture.previewDirectory,
            thumbnailDirectory: fixture.thumbnailDirectory, looksDirectory: fixture.looksDirectory,
            engine: engine, decodeProbe: decodeProbe
        )
        viewModel.collection.loadPortableAssets(try session.materializedAssets())
        await viewModel.collection.scanCompletion()
        let item = try XCTUnwrap(viewModel.collection.items.first)
        XCTAssertEqual(item.asset.source.portableIdentity, fixture.identity)
        XCTAssertEqual(
            FrameClassifier.classify(
                staleFrame.frame.metadata,
                against: FrameCurrentInputs(source: item.asset.source.portableIdentity)
            ),
            .provisionalOnly,
            "the stored edited frame must be eligible for inert first paint"
        )
        let reservedRatio = item.libraryAspectRatio
        let rasterProbe = ThumbnailRasterProbe()
        item.onThumbnailAssignment = { rasterProbe.record($0) }
        viewModel.collection.beginThumbnailDemand()
        viewModel.collection.requestVisibleThumbnails(for: [item.id])

        try await waitUntil("stale frame before replacement") {
            let requests = await engine.thumbnailRequests.count
            return item.thumbnail != nil && requests == 1
        }
        XCTAssertNil(item.editedThumbnailRevision, "stale pixels stay inert until replacement")
        XCTAssertTrue(item.shouldFillLibraryThumbnail, "the stale edited pixels retain final geometry")
        let gridEditedSummary = await viewModel.frameLookupLedger.summary(for: .gridEdited)
        XCTAssertEqual(rasterProbe.rasters.count, 1,
                       "the original must not flash between a stale edit and its replacement; "
                           + gridEditedSummary)
        XCTAssertEqual(
            Pixels.worstDelta(try pixels(of: rasterProbe.rasters.first), stalePixels)?.delta, 0,
            "the stale stored frame must be the first raster"
        )
        XCTAssertEqual(item.libraryAspectRatio, reservedRatio, accuracy: 0.000_001)

        await engine.releaseThumbnails()
        try await waitUntil("one stale-frame replacement") { item.editedThumbnailRevision != nil }
        let thumbnailRequestCount = await engine.thumbnailRequests.count
        let decodeCount = await decodeProbe.count
        XCTAssertEqual(thumbnailRequestCount, 1)
        XCTAssertEqual(decodeCount, 0, "the stored original tier should not decode source pixels")
        XCTAssertEqual(rasterProbe.rasters.count, 2,
                       "stale stored pixels should be replaced exactly once")
        XCTAssertTrue(item.shouldFillLibraryThumbnail)
        XCTAssertEqual(item.libraryAspectRatio, reservedRatio, accuracy: 0.000_001,
                       "the replacement must not resize the cell")
        XCTAssertEqual(viewModel.collection.storedGeometryFallbackReflowCount, 0)
        await viewModel.shutdown()
    }

    func testMissingEditedFrameShowsFittedOriginalBeforeOneEditPaint() async throws {
        let fixture = try await seedSinglePhotoRelaunch()
        let frameStore = ThumbnailFrameStore(directory: fixture.thumbnailDirectory)
        let storedFrames = await frameStore.readFrames(for: fixture.identity)
        let originalFrame = try XCTUnwrap(storedFrames.original)
        let originalPixels = try Pixels.bytes(of: originalFrame.image)
        await frameStore.remove(.edited, for: fixture.identity.assetID)
        await frameStore.flush()

        PlatformThumbnailProvider.invalidateCache()
        let decodeProbe = ThumbnailDecodeProbe()
        let engine = FakeRenderEngine()
        await engine.gateThumbnails()
        let (viewModel, session) = try model(
            packageURL: fixture.packageURL, previewDirectory: fixture.previewDirectory,
            thumbnailDirectory: fixture.thumbnailDirectory, looksDirectory: fixture.looksDirectory,
            engine: engine, decodeProbe: decodeProbe
        )
        viewModel.collection.loadPortableAssets(try session.materializedAssets())
        await viewModel.collection.scanCompletion()
        let item = try XCTUnwrap(viewModel.collection.items.first)
        let reservedRatio = item.libraryAspectRatio
        let rasterProbe = ThumbnailRasterProbe()
        item.onThumbnailAssignment = { rasterProbe.record($0) }
        viewModel.collection.beginThumbnailDemand()
        viewModel.collection.requestVisibleThumbnails(for: [item.id])

        try await waitUntil("original paint while edited frame is missing") {
            let requests = await engine.thumbnailRequests.count
            return item.thumbnail != nil && requests == 1
        }
        XCTAssertFalse(item.shouldFillLibraryThumbnail,
                       "the original stays fitted in the reserved presented geometry")
        XCTAssertNil(item.editedThumbnailRevision)
        XCTAssertEqual(rasterProbe.rasters.count, 1)
        XCTAssertEqual(try pixels(of: rasterProbe.rasters.first), originalPixels,
                       "the packed original must paint before the edit render finishes")
        XCTAssertEqual(item.libraryAspectRatio, reservedRatio, accuracy: 0.000_001)

        await engine.releaseThumbnails()
        try await waitUntil("one edited raster after original paint") {
            item.editedThumbnailRevision != nil
        }
        let thumbnailRequestCount = await engine.thumbnailRequests.count
        let decodeCount = await decodeProbe.count
        XCTAssertEqual(thumbnailRequestCount, 1)
        XCTAssertEqual(decodeCount, 0)
        XCTAssertEqual(rasterProbe.rasters.count, 2,
                       "edited pixels should replace the original exactly once")
        XCTAssertTrue(item.shouldFillLibraryThumbnail)
        XCTAssertEqual(item.libraryAspectRatio, reservedRatio, accuracy: 0.000_001,
                       "the edited raster must not change the cell's size")
        XCTAssertEqual(viewModel.collection.storedGeometryFallbackReflowCount, 0)
        await viewModel.shutdown()
    }

    func testReplacedSourceBytesBetweenSessionsInvalidatePersistedFrameOnce() async throws {
        let fixture = try await seedSinglePhotoRelaunch()
        let replacement = try Fixtures.writeGradientPNG(
            width: 80, height: 48, named: "replacement.png", in: tempDirectory
        )
        try Data(contentsOf: replacement).write(to: fixture.sourceURL, options: .atomic)
        let package = try PortableLibraryPackage.open(at: fixture.packageURL)
        let oldRecord = try package.readAssetRecord(for: fixture.identity.assetID)
        let replacementFingerprint = try PortablePhotoSourceFingerprint.file(
            at: fixture.sourceURL,
            sourceRevision: fixture.identity.sourceFingerprint.sourceRevision + 1,
            decoderVersion: fixture.identity.sourceFingerprint.decoderVersion,
            geometry: fixture.identity.sourceFingerprint.geometry
        )
        let replacementIdentity = PortablePhotoIdentity(
            assetID: fixture.identity.assetID, sourceFingerprint: replacementFingerprint
        )
        let maybeReplacedFrame = await LatestPreviewFrameStore(directory: fixture.previewDirectory)
            .read(for: fixture.identity)
        let replacedFrame = try XCTUnwrap(maybeReplacedFrame)
        XCTAssertEqual(
            FrameClassifier.classify(
                replacedFrame.frame.metadata,
                against: FrameCurrentInputs(
                    source: replacementIdentity, editHash: fixture.seedSignature.editHash,
                    look: fixture.seedSignature.look,
                    workingSpace: fixture.seedSignature.workingSpace,
                    pixelEpoch: fixture.seedSignature.pixelEpoch
                )
            ),
            .unusable,
            "only the source fingerprint should differ from the exact seed"
        )
        try package.writeAssetRecord(PortablePackageAssetRecord(
            identity: replacementIdentity,
            source: oldRecord.source,
            sourceChangeSignature: PhotoSourceFingerprint.file(at: fixture.sourceURL),
            isRemoved: oldRecord.isRemoved, currentRevision: oldRecord.currentRevision,
            editHistory: oldRecord.editHistory, copyOfAssetID: oldRecord.copyOfAssetID
        ))

        let engine = FakeRenderEngine()
        let (reopened, _) = try await reopenedSinglePhoto(fixture, engine: engine)
        let diagnostics = try XCTUnwrap(reopened.presentationSessionForDiagnostics)
        let previewRequests = await engine.previewRequests
        let thumbnailRequests = await engine.thumbnailRequests
        let previewCount = previewRequests.filter {
            $0.document.editHash == fixture.seedSignature.editHash
                && $0.source?.portableIdentity.sourceFingerprint.matches(
                    replacementIdentity.sourceFingerprint
                ) == true
        }.count
        let thumbnailCount = thumbnailRequests.filter {
            $0.document.editHash == fixture.seedSignature.editHash
                && $0.source.portableIdentity.sourceFingerprint.matches(
                    replacementIdentity.sourceFingerprint
                ) == true
        }.count
        XCTAssertNotEqual(
            diagnostics.identity.sourceFingerprint.contentHash,
            fixture.identity.sourceFingerprint.contentHash,
            "replaced bytes must change the source identity"
        )
        XCTAssertTrue(
            reopened.collection.items.first?.asset.source.portableIdentity.sourceFingerprint
                .matches(replacementIdentity.sourceFingerprint) == true
        )
        XCTAssertEqual(
            diagnostics.confirmedFrameCount, 2,
            "a source miss confirms the speculative identity preview and its saved-edit correction"
        )
        let matchingPreviewDescriptions = previewRequests.filter {
            $0.document.editHash == fixture.seedSignature.editHash
                && $0.source?.portableIdentity.sourceFingerprint.matches(
                    replacementIdentity.sourceFingerprint
                ) == true
        }.map { "scale=\($0.scale), revision=\($0.requestRevision)" }
        XCTAssertEqual(
            previewCount, 1,
            "replaced source bytes must render once; requests=\(matchingPreviewDescriptions)"
        )
        XCTAssertEqual(thumbnailCount, 1, "replaced source bytes must render its edited thumbnail once")
        assertNoPrematureFallback(diagnostics)
        await reopened.shutdown()
    }

    func testDifferentPixelEpochBetweenSessionsRefinesPersistedFrameOnce() async throws {
        let fixture = try await seedSinglePhotoRelaunch()
        let store = LatestPreviewFrameStore(directory: fixture.previewDirectory)
        let maybeHit = await store.read(for: fixture.identity)
        let hit = try XCTUnwrap(maybeHit)
        XCTAssertEqual(hit.frame.signature, fixture.seedSignature)
        let old = hit.frame.metadata
        let stale = PresentationFrameMetadata(
            identity: old.identity, kind: old.kind,
            signature: FrameSignature(
                source: old.signature.source, editHash: old.signature.editHash,
                look: old.signature.look, workingSpace: old.signature.workingSpace,
                pixelEpoch: RenderPipeline.pixelEpoch - 1
            ),
            geometry: old.geometry, rasterColorSpace: old.rasterColorSpace,
            perceptualDigest: old.perceptualDigest, presentedAt: old.presentedAt,
            pixelWidth: old.pixelWidth, pixelHeight: old.pixelHeight
        )
        XCTAssertEqual(
            FrameClassifier.classify(
                stale,
                against: FrameCurrentInputs(
                    source: fixture.seedSignature.source,
                    editHash: fixture.seedSignature.editHash,
                    look: fixture.seedSignature.look,
                    workingSpace: fixture.seedSignature.workingSpace,
                    pixelEpoch: RenderPipeline.pixelEpoch
                )
            ),
            .staleCompatible,
            "only the pixel epoch should differ from the exact seed"
        )
        await store.enqueueWrite(PresentationFrame(metadata: stale, rasterData: hit.frame.rasterData))
        await store.waitForPendingWrites()

        let engine = FakeRenderEngine()
        let (reopened, _) = try await reopenedSinglePhoto(fixture, engine: engine)
        let diagnostics = try XCTUnwrap(reopened.presentationSessionForDiagnostics)
        let previewCount = await engine.previewRequests.count
        let thumbnailCount = await engine.thumbnailRequests.count
        XCTAssertEqual(diagnostics.confirmedFrameCount, 1)
        XCTAssertEqual(previewCount, 1, "an old pixel epoch must refine once")
        XCTAssertEqual(thumbnailCount, 0, "the unchanged edited thumbnail should still be reused")
        assertNoPrematureFallback(diagnostics)
        await reopened.shutdown()
    }

    func testUnchangedSinglePhotoSeedIsReusedAfterRelaunch() async throws {
        let fixture = try await seedSinglePhotoRelaunch()
        let engine = FakeRenderEngine()
        let (reopened, _) = try await reopenedSinglePhoto(fixture, engine: engine)
        let diagnostics = try XCTUnwrap(reopened.presentationSessionForDiagnostics)
        let requests = await engine.previewRequests
        if let currentRequest = requests.last {
            XCTAssertTrue(
                currentRequest.source?.portableIdentity.sourceFingerprint.matches(
                    fixture.seedSignature.source.sourceFingerprint
                ) == true
            )
            XCTAssertEqual(currentRequest.document.editHash, fixture.seedSignature.editHash)
            XCTAssertEqual(currentRequest.space, fixture.seedSignature.workingSpace)
            XCTAssertEqual(currentRequest.document.lut, LUTSettings())
        }
        let previewCount = await engine.previewRequests.count
        let thumbnailCount = await engine.thumbnailRequests.count

        XCTAssertEqual(diagnostics.confirmedFrameCount, 1)
        XCTAssertEqual(previewCount, 0, "an exact seed frame must skip preview rendering")
        XCTAssertEqual(thumbnailCount, 0, "an exact seed thumbnail must skip rendering")
        await reopened.shutdown()
    }

    func testUnchangedPackageReusesSettledFramesAfterRelaunch() async throws {
        let packageURL = tempDirectory.appendingPathComponent("Parity.kromoralibrary")
        let previewDirectory = tempDirectory.appendingPathComponent("Derived/Previews")
        let thumbnailDirectory = tempDirectory.appendingPathComponent("Derived/Thumbnails")
        let looksDirectory = tempDirectory.appendingPathComponent("Looks", isDirectory: true)
        try FileManager.default.createDirectory(at: looksDirectory, withIntermediateDirectories: true)
        let lookURL = try Fixtures.writeCube(
            Fixtures.identityCubeText(size: 2), named: "Parity Look.cube", in: looksDirectory
        )
        let look = try CubeLUT(url: lookURL)
        let names = ["plain-a.png", "plain-b.png", "exposure.png", "color.png", "crop.png", "look.png"]
        let sources = try names.enumerated().map { index, name in
            try Fixtures.writeGradientPNG(
                width: 48 + index, height: 32, named: name, in: tempDirectory
            )
        }
        let package = try PortableLibrarySession(at: packageURL)
        _ = try package.importURLs(sources, duplicatePolicy: .importAnyway)
        let seedAssets = try package.materializedAssets()
        try seedSourceAspectRatios(
            Dictionary(uniqueKeysWithValues: names.enumerated().map { index, name in
                (name, Double(48 + index) / 32.0)
            }),
            assets: seedAssets, package: package.package
        )
        let seedStore = EditDocumentStore(package: package.package, lease: package.lease)
        let edits: [(String, (inout EditDocument) -> Void)] = [
            ("exposure.png", { $0.adjustments = [.exposure(ev: 0.7)] }),
            ("color.png", { $0.light.contrast = 0.3 }),
            ("crop.png", { $0.crop = CropAdjustments(normalizedRect: CGRect(x: 0.1, y: 0.1, width: 0.7, height: 0.3)) }),
            ("look.png", { $0.lut = LUTSettings(lutID: look.lutID, intensity: 0.8) }),
        ]
        for (name, edit) in edits {
            guard let asset = seedAssets.first(where: { $0.displayName == name }) else {
                XCTFail("fixture photo \(name) must be present")
                continue
            }
            var document = EditDocument()
            edit(&document)
            try await seedStore.save(document, for: EditSourceReference(
                assetID: asset.id, portableIdentity: asset.source.portableIdentity, url: asset.url
            ))
        }
        try package.refreshIndex()
        await package.shutdown()

        let firstEngine = FakeRenderEngine()
        let (first, firstSession) = try model(
            packageURL: packageURL, previewDirectory: previewDirectory,
            thumbnailDirectory: thumbnailDirectory, looksDirectory: looksDirectory,
            engine: firstEngine
        )
        first.library.scan(looksDirectory)
        try await waitUntil("Look library scan") { first.library.allLUTs.contains { $0.lutID == look.lutID } }
        first.collection.loadPortableAssets(try firstSession.browsingAssets())
        await first.collection.scanCompletion()

        first.collection.beginThumbnailDemand()
        first.collection.requestVisibleThumbnails(for: first.collection.items.map(\.id))
        try await waitUntil("first launch grid frames") {
            first.collection.items.allSatisfy { $0.thumbnail != nil }
                && edits.allSatisfy { name, _ in
                    first.collection.items.first { $0.displayName == name }?.editedThumbnailRevision != nil
                }
        }
        for name in names {
            guard let index = first.collection.items.firstIndex(where: { $0.displayName == name }) else {
                XCTFail("fixture photo \(name) must be present")
                continue
            }
            first.collection.setSelection(at: index)
            first.openActiveCollectionImage()
            try await waitUntil("\(name) first launch Edit confirmation") {
                first.sourceName == name && first.presentationSessionForDiagnostics?.state == .confirmed
            }
        }
        let flushResult = await first.flushPendingWrites()
        XCTAssertEqual(flushResult, .success)
        await first.thumbnailFrameStore.flush()
        let expectedEditedFramePixels = try await readPersistedEditedPixels(
            names: edits.map(\.0), assets: seedAssets, thumbnailDirectory: thumbnailDirectory
        )
        await first.shutdown()

        PlatformThumbnailProvider.invalidateCache()
        let decodeProbe = ThumbnailDecodeProbe()
        let secondEngine = FakeRenderEngine()
        let (second, secondSession) = try model(
            packageURL: packageURL, previewDirectory: previewDirectory,
            thumbnailDirectory: thumbnailDirectory, looksDirectory: looksDirectory,
            engine: secondEngine, decodeProbe: decodeProbe
        )
        second.library.scan(looksDirectory)
        try await waitUntil("reopened Look library scan") {
            second.library.allLUTs.contains { $0.lutID == look.lutID }
        }
        second.collection.loadPortableAssets(try secondSession.browsingAssets())
        XCTAssertEqual(secondSession.rootURL, packageURL.standardizedFileURL,
                       "relaunch must reopen the same package")
        await second.collection.scanCompletion()
        let initialGridRatios = Dictionary(uniqueKeysWithValues: second.collection.items.map {
            ($0.id, $0.libraryAspectRatio)
        })
        let rasterProbes = Dictionary(uniqueKeysWithValues: edits.compactMap { name, _ in
            second.collection.items.first(where: { $0.displayName == name }).map { item in
                let probe = ThumbnailRasterProbe()
                item.onThumbnailAssignment = { probe.record($0) }
                return (name, probe)
            }
        })
        let preparationsBeforeThumbnails = await secondEngine.sourcePreparationCount
        second.collection.beginThumbnailDemand()
        second.collection.requestVisibleThumbnails(for: second.collection.items.map(\.id))
        try await waitUntil("relaunch grid cache lookups") {
            second.collection.items.allSatisfy { $0.thumbnail != nil }
                && edits.allSatisfy { name, _ in
                    second.collection.items.first { $0.displayName == name }?.editedThumbnailRevision != nil
                }
        }
        var settledGridPixels: [String: [UInt8]] = [:]
        for name in names {
            guard let item = second.collection.items.first(where: { $0.displayName == name }) else {
                continue
            }
            settledGridPixels[name] = try pixels(of: item.thumbnail)
        }

        let preparationsAfterThumbnails = await secondEngine.sourcePreparationCount
        XCTAssertEqual(
            preparationsAfterThumbnails - preparationsBeforeThumbnails, 0,
            "an exact persisted edited frame must skip thumbnail source preparation"
        )
        let originalDecodeCount = await decodeProbe.count
        XCTAssertEqual(originalDecodeCount, 0,
                       "the packed original frame must avoid the source decode tier")
        XCTAssertEqual(second.collection.storedGeometryFallbackReflowCount, 0,
                       "a published aspect ratio must avoid stored-geometry fallback reflow")

        for (name, _) in edits {
            let requests = await secondEngine.thumbnailRequests.filter {
                $0.assetID == second.collection.items.first { $0.displayName == name }?.id
            }
            XCTAssertEqual(
                requests.count, 0,
                "edited thumbnails must be reused without rendering for \(name)"
            )
            let rasterProbe = try XCTUnwrap(rasterProbes[name])
            XCTAssertEqual(rasterProbe.rasters.count, 1,
                           "the exact stored edited raster must be the cell's only paint for \(name)")
            XCTAssertEqual(
                try pixels(of: rasterProbe.rasters.first), expectedEditedFramePixels[name],
                "the first cell raster must be the persisted edited frame for \(name)"
            )
        }

        for name in names {
            let item = try XCTUnwrap(second.collection.items.first { $0.displayName == name })
            let finalPixels = try pixels(of: item.thumbnail)
            XCTAssertEqual(finalPixels, settledGridPixels[name],
                           "grid pixels must not swap after first paint for \(name)")
            let initialRatio = try XCTUnwrap(initialGridRatios[item.id])
            XCTAssertEqual(item.libraryAspectRatio, initialRatio, accuracy: 0.000_001,
                           "library aspect ratio must not change after first layout for \(name)")
        }

        await second.shutdown()

        // A fresh Derived directory is the non-vacuous control: an empty cache must request work.
        let coldEngine = FakeRenderEngine()
        let (cold, coldSession) = try model(
            packageURL: packageURL,
            previewDirectory: tempDirectory.appendingPathComponent("Cold/Previews"),
            thumbnailDirectory: tempDirectory.appendingPathComponent("Cold/Thumbnails"),
            looksDirectory: looksDirectory, engine: coldEngine
        )
        cold.library.scan(looksDirectory)
        try await waitUntil("cold control Look scan") {
            cold.library.allLUTs.contains { $0.lutID == look.lutID }
        }
        cold.collection.loadPortableAssets(try coldSession.browsingAssets())
        await cold.collection.scanCompletion()
        cold.collection.beginThumbnailDemand()
        cold.collection.requestVisibleThumbnails(for: cold.collection.items.map(\.id))
        try await waitUntil("cold control thumbnails") {
            edits.allSatisfy { name, _ in
                cold.collection.items.first { $0.displayName == name }?.editedThumbnailRevision != nil
            }
        }
        let coldThumbnailCount = await coldEngine.thumbnailRequests.count
        XCTAssertGreaterThan(coldThumbnailCount, 0, "a deleted Derived cache must trigger edited thumbnail renders")
        guard let coldIndex = cold.collection.items.firstIndex(where: { $0.displayName == "exposure.png" }) else {
            XCTFail("fixture photo exposure.png must be present")
            await cold.shutdown()
            return
        }
        cold.collection.setSelection(at: coldIndex)
        cold.openActiveCollectionImage()
        try await waitUntil("cold control preview") {
            cold.sourceName == "exposure.png" && cold.previewState == .ready
        }
        let coldPreviewCount = await coldEngine.previewRequests.count
        XCTAssertGreaterThan(coldPreviewCount, 0, "a deleted Derived cache must trigger preview render")
        await cold.shutdown()
    }

    private func readPersistedEditedPixels(
        names: [String], assets: [PhotoAsset], thumbnailDirectory: URL
    ) async throws -> [String: [UInt8]] {
        let store = ThumbnailFrameStore(directory: thumbnailDirectory)
        var result: [String: [UInt8]] = [:]
        for name in names {
            guard let asset = assets.first(where: { $0.displayName == name }) else {
                XCTFail("fixture photo \(name) must be present")
                continue
            }
            let frames = await store.readFrames(for: asset.source.portableIdentity)
            guard let image = frames.edited?.image else {
                XCTFail("persisted edited frame for \(name) must be readable")
                continue
            }
            result[name] = try Pixels.bytes(of: image)
        }
        return result
    }

    private func seedSourceAspectRatios(
        _ ratios: [String: Double], assets: [PhotoAsset], package: PortableLibraryPackage
    ) throws {
        var shards: [String: PortablePackageMembershipShard] = [:]
        for (name, ratio) in ratios {
            guard let asset = assets.first(where: { $0.displayName == name }) else {
                XCTFail("fixture photo \(name) must be present")
                continue
            }
            let assetID = asset.source.portableIdentity.assetID
            let shardName = PortableLibraryPackage.shard(for: assetID)
            var shard = try shards[shardName] ?? package.readMembershipShard(shardName)
            guard let index = shard.entries.firstIndex(where: { $0.assetID == assetID }) else {
                XCTFail("membership entry for \(name) must be present")
                continue
            }
            shard.entries[index].summary.aspectRatio = ratio
            shards[shardName] = shard
        }
        for shard in shards.values { try package.writeMembershipShard(shard) }
    }
}

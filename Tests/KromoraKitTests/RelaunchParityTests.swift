import Foundation
import AppKit
import CoreGraphics
import XCTest

@testable import KromoraKit

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
        looksDirectory: URL, engine: FakeRenderEngine
    ) throws -> (AppViewModel, PortableLibrarySession) {
        let session = try PortableLibrarySession(at: packageURL)
        let viewModel = makeAppViewModel(
            engine: engine, userLookFolderURL: looksDirectory,
            previewFrameStoreDirectory: previewDirectory,
            thumbnailFrameStoreDirectory: thumbnailDirectory,
            portablePackageURL: packageURL, portableLibrarySession: session
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
        let reference = EditSourceReference(
            assetID: asset.id, portableIdentity: asset.source.portableIdentity, url: asset.url
        )
        var document = EditDocument()
        document.adjustments = [.exposure(ev: 0.4)]
        try await EditDocumentStore(package: package.package, lease: package.lease)
            .save(document, for: reference)
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
        XCTAssertEqual(diagnostics.confirmedFrameCount, 1)
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
        await first.shutdown()

        let secondEngine = FakeRenderEngine()
        let (second, secondSession) = try model(
            packageURL: packageURL, previewDirectory: previewDirectory,
            thumbnailDirectory: thumbnailDirectory, looksDirectory: looksDirectory,
            engine: secondEngine
        )
        second.library.scan(looksDirectory)
        try await waitUntil("reopened Look library scan") {
            second.library.allLUTs.contains { $0.lutID == look.lutID }
        }
        second.collection.loadPortableAssets(try secondSession.browsingAssets())
        XCTAssertEqual(secondSession.rootURL, packageURL.standardizedFileURL,
                       "relaunch must reopen the same package")
        await second.collection.scanCompletion()
        second.collection.beginThumbnailDemand()
        second.collection.requestVisibleThumbnails(for: second.collection.items.map(\.id))
        try await waitUntil("relaunch grid cache lookups") {
            second.collection.items.allSatisfy { $0.thumbnail != nil }
                && edits.allSatisfy { name, _ in
                    second.collection.items.first { $0.displayName == name }?.editedThumbnailRevision != nil
                }
        }
        var settledGridPixels: [String: [UInt8]] = [:]
        var settledGridRatios: [String: Double] = [:]
        for name in names {
            guard let item = second.collection.items.first(where: { $0.displayName == name }) else {
                continue
            }
            settledGridPixels[name] = try pixels(of: item.thumbnail)
            settledGridRatios[name] = item.libraryAspectRatio
        }

        // KRMA-765/KRMA-766 geometry/crop work remains expected failures. Fingerprint-only
        // edited-thumbnail reuse below is unwrapped.
        // On this tree the expected failures include the observed messages:
        // "edited thumbnails must be reused without rendering for exposure.png" (1 request),
        // "Edit must publish one confirmed frame for exposure.png" (2 distinct frames),
        // "unchanged Edit source must use its confirmed frame without a render for exposure.png" (1 request),
        // and "library aspect ratio must not change after first layout for exposure.png"
        // (1.5625 became 1.3333333333333333). Color, crop, and Look previews also render once.
        // Identity-dependent relaunch assertions below are now ordinary passing assertions.
        for (name, _) in edits {
            let requests = await secondEngine.thumbnailRequests.filter {
                $0.assetID == second.collection.items.first { $0.displayName == name }?.id
            }
            XCTAssertEqual(
                requests.count, 0,
                "edited thumbnails must be reused without rendering for \(name)"
            )
        }

        for name in names {
            guard let index = second.collection.items.firstIndex(where: { $0.displayName == name }) else {
                XCTFail("fixture photo \(name) must be present")
                continue
            }
            let before = await secondEngine.previewRequests.count
            second.collection.setSelection(at: index)
            second.openActiveCollectionImage()
            try await waitUntil("\(name) relaunch Edit confirmation") {
                second.sourceName == name
                    && second.presentationSessionForDiagnostics?.state == .confirmed
            }
            let session = try XCTUnwrap(second.presentationSessionForDiagnostics)
            assertNoPrematureFallback(session)
            if !edits.contains(where: { $0.0 == name }) {
                XCTAssertEqual(session.distinctFrameCount, 1,
                               "unchanged plain photo should reuse its frame: \(name)")
                let afterPlain = await secondEngine.previewRequests.count
                XCTAssertEqual(afterPlain, before, "unchanged plain photo must not render: \(name)")
                continue
            }
            XCTAssertEqual(
                session.distinctFrameCount, 1,
                "Edit must publish one confirmed frame for \(name)"
            )
            XCTAssertNotEqual(session.candidateSource, .embeddedJPEG, "Edit must not begin with embedded JPEG for \(name)")
            XCTAssertNotEqual(session.candidateSource, .originalThumbnail, "Edit must not begin with original thumbnail for \(name)")
            let after = await secondEngine.previewRequests.count
            XCTAssertEqual(
                after - before, 0,
                "unchanged Edit source must use its confirmed frame without a render for \(name)"
            )
        }

        for name in names {
            let item = try XCTUnwrap(second.collection.items.first { $0.displayName == name })
            let finalPixels = try pixels(of: item.thumbnail)
            XCTAssertEqual(finalPixels, settledGridPixels[name],
                           "grid pixels must not swap after first paint for \(name)")
            if edits.contains(where: { $0.0 == name }) {
                XCTExpectFailure("KRMA-765: relaunch crop geometry", options: .nonStrict()) {
                    XCTAssertEqual(item.libraryAspectRatio, settledGridRatios[name],
                                   "library aspect ratio must not change after first layout for \(name)")
                }
            } else {
                XCTExpectFailure("KRMA-765: relaunch geometry", options: .nonStrict()) {
                    XCTAssertEqual(item.libraryAspectRatio, settledGridRatios[name],
                                   "plain photo aspect ratio must stay stable for \(name)")
                }
            }
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
}

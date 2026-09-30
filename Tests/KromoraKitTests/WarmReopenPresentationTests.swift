import CoreGraphics
import ImageIO
import XCTest
@testable import KromoraKit

/// End-to-end behavior of the latest-frame store through `AppViewModel`: what a warm reopen
/// renders, shows, and writes. The fake renderer proves orchestration and counts only; it says
/// nothing about timing.
@MainActor
final class WarmReopenPresentationTests: TempDirectoryTestCase {
    private struct Harness {
        let viewModel: AppViewModel
        let fake: FakeRenderEngine
        let data: Data
        let directory: URL
    }

    private func makeHarness(name: String = "warm.png") async throws -> Harness {
        let imageURL = try Fixtures.writeGradientPNG(
            width: 64, height: 48, named: name, in: tempDirectory
        )
        let data = try Data(contentsOf: imageURL)
        let rendered = try XCTUnwrap(
            CGImageSourceCreateWithURL(imageURL as CFURL, nil).flatMap {
                CGImageSourceCreateImageAtIndex($0, 0, nil)
            }
        )
        let fake = FakeRenderEngine(previewResult: rendered)
        let directory = tempDirectory.appendingPathComponent("warm-frames")
        let viewModel = makeAppViewModel(engine: fake, previewFrameStoreDirectory: directory)
        return Harness(viewModel: viewModel, fake: fake, data: data, directory: directory)
    }

    /// Open once and wait until the settled frame has been persisted.
    private func warmUp(_ harness: Harness, name: String = "warm.png") async throws
        -> PortablePhotoIdentity
    {
        harness.viewModel.openImage(data: harness.data, name: name)
        try await waitUntil("first preview") { harness.viewModel.previewState == .ready }
        try await waitUntil("frame write") { Self.frameFiles(in: harness.directory) == 1 }
        let source = try XCTUnwrap(harness.viewModel.admissionImageSource)
        return source.portableIdentity
    }

    private static func frameFiles(in directory: URL) -> Int {
        ((try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil))
            ?? []).filter { $0.pathExtension == "kframe" }.count
    }

    /// Rewrite the stored frame through an independent store over the same directory.
    private func rewriteStoredFrame(
        _ harness: Harness, identity: PortablePhotoIdentity,
        _ transform: (PresentationFrameMetadata) -> PresentationFrameMetadata
    ) async throws {
        let store = LatestPreviewFrameStore(directory: harness.directory)
        let hit = try unwrapAwaited(await store.read(for: identity))
        await store.enqueueWrite(PresentationFrame(
            metadata: transform(hit.frame.metadata), rasterData: hit.frame.rasterData
        ))
        await store.waitForPendingWrites()
    }

    /// Reopen the photo and report how many frames reached the surface and how many renders the
    /// reopen submitted, once everything has settled.
    private func reopen(_ harness: Harness, expectingRenders: Int) async throws
        -> (frames: UInt64, renders: Int)
    {
        let rendersBefore = await harness.fake.previewRequests.count
        harness.viewModel.openImage(data: harness.data, name: "warm.png")
        // Selection clears the canvas synchronously; count what reaches the surface afterwards.
        let revisionBefore = harness.viewModel.previewSurface.revision
        try await waitUntil("reopen settled") {
            await harness.fake.previewRequests.count == rendersBefore + expectingRenders
                && harness.viewModel.previewState == .ready
        }
        try await Task.sleep(for: .milliseconds(200))
        let renders = await harness.fake.previewRequests.count - rendersBefore
        return (harness.viewModel.previewSurface.revision - revisionBefore, renders)
    }

    /// Frames a reopen presents when nothing usable is stored: the selection-time thumbnail
    /// candidate (if any) plus the rendered frame. Stored-frame scenarios are compared against it.
    private func coldReopenFrames(_ harness: Harness) async throws -> UInt64 {
        for url in try FileManager.default.contentsOfDirectory(
            at: harness.directory, includingPropertiesForKeys: nil
        ) { try FileManager.default.removeItem(at: url) }
        let cold = try await reopen(harness, expectingRenders: 1)
        try await waitUntil("frame rewritten after the cold reopen") {
            Self.frameFiles(in: harness.directory) == 1
        }
        return cold.frames
    }

    func testExactWarmReopenRendersNothingAndAdmitsHistogramOnce() async throws {
        let harness = try await makeHarness()
        _ = try await warmUp(harness)
        let firstRenders = await harness.fake.previewRequests.count
        XCTAssertGreaterThan(firstRenders, 0)
        harness.viewModel.inspectorState.isPresented = true
        harness.viewModel.inspectorState.tab = .info
        try await waitUntil("first histogram") { harness.viewModel.histogram != nil }
        let firstHistograms = await harness.fake.histogramRequests.count

        harness.viewModel.openImage(data: harness.data, name: "warm.png")
        try await waitUntil("warm preview") { harness.viewModel.previewState == .ready }
        try await waitUntil("warm histogram") {
            await harness.fake.histogramRequests.count == firstHistograms + 1
        }
        try await Task.sleep(for: .milliseconds(150))

        let warmRenders = await harness.fake.previewRequests.count
        XCTAssertEqual(warmRenders, firstRenders, "an exact frame must not submit a preview render")
        let warmHistograms = await harness.fake.histogramRequests.count
        XCTAssertEqual(warmHistograms, firstHistograms + 1, "supporting work is admitted once")
    }

    func testPixelEpochBumpShowsTheFrameThenRendersOnceAndRewrites() async throws {
        let harness = try await makeHarness()
        let identity = try await warmUp(harness)
        let coldFrames = try await coldReopenFrames(harness)
        try await rewriteStoredFrame(harness, identity: identity) { old in
            PresentationFrameMetadata(
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
        }

        let warm = try await reopen(harness, expectingRenders: 1)

        XCTAssertEqual(warm.renders, 1, "a stale frame costs exactly one render")
        XCTAssertEqual(
            warm.frames, coldFrames + 1,
            "the stored frame is the one extra provisional presentation; the render is the one replacement"
        )
        let store = LatestPreviewFrameStore(directory: harness.directory)
        try await waitUntil("frame refreshed at the current epoch") {
            let metadata = await store.metadata(for: identity)
            return metadata?.signature.pixelEpoch == RenderPipeline.pixelEpoch
        }
        XCTAssertEqual(Self.frameFiles(in: harness.directory), 1)
    }

    func testStaleEditFrameRendersOnceBeforeAnyExactClaim() async throws {
        let harness = try await makeHarness()
        let identity = try await warmUp(harness)
        try await rewriteStoredFrame(harness, identity: identity) { old in
            PresentationFrameMetadata(
                identity: old.identity, kind: old.kind,
                signature: FrameSignature(
                    source: old.signature.source, editHash: "an-older-edit",
                    look: old.signature.look, workingSpace: old.signature.workingSpace,
                    pixelEpoch: old.signature.pixelEpoch
                ),
                geometry: old.geometry, rasterColorSpace: old.rasterColorSpace,
                perceptualDigest: old.perceptualDigest, presentedAt: old.presentedAt,
                pixelWidth: old.pixelWidth, pixelHeight: old.pixelHeight
            )
        }
        let rendersBefore = await harness.fake.previewRequests.count

        harness.viewModel.openImage(data: harness.data, name: "warm.png")
        try await waitUntil("stale-edit reopen settled") {
            await harness.fake.previewRequests.count == rendersBefore + 1
                && harness.viewModel.previewState == .ready
        }
        try await Task.sleep(for: .milliseconds(150))

        let rendersAfter = await harness.fake.previewRequests.count
        XCTAssertEqual(rendersAfter, rendersBefore + 1)
    }

    func testReplacedSourceNeverShowsTheStoredFrame() async throws {
        let harness = try await makeHarness()
        let identity = try await warmUp(harness)
        let coldFrames = try await coldReopenFrames(harness)
        let replaced = PortablePhotoIdentity(
            assetID: identity.assetID,
            sourceFingerprint: .data(Data("replaced".utf8), decoderVersion: "other")
        )
        try await rewriteStoredFrame(harness, identity: identity) { old in
            PresentationFrameMetadata(
                identity: replaced, kind: old.kind,
                signature: FrameSignature(
                    source: replaced, editHash: old.signature.editHash,
                    look: old.signature.look, workingSpace: old.signature.workingSpace,
                    pixelEpoch: old.signature.pixelEpoch
                ),
                geometry: old.geometry, rasterColorSpace: old.rasterColorSpace,
                perceptualDigest: old.perceptualDigest, presentedAt: old.presentedAt,
                pixelWidth: old.pixelWidth, pixelHeight: old.pixelHeight
            )
        }

        let reopened = try await reopen(harness, expectingRenders: 1)

        XCTAssertEqual(
            reopened.frames, coldFrames,
            "a replaced source must present exactly what a cold open presents"
        )
    }

    func testDeletingEveryStoredFrameCostsARenderNotCorrectness() async throws {
        let harness = try await makeHarness()
        _ = try await warmUp(harness)
        for url in try FileManager.default.contentsOfDirectory(
            at: harness.directory, includingPropertiesForKeys: nil
        ) { try FileManager.default.removeItem(at: url) }
        let rendersBefore = await harness.fake.previewRequests.count

        harness.viewModel.openImage(data: harness.data, name: "warm.png")
        try await waitUntil("reopen without frames") {
            await harness.fake.previewRequests.count == rendersBefore + 1
                && harness.viewModel.previewState == .ready
        }
    }

    func testCorruptStoredFrameIsAMissAndIsReplaced() async throws {
        let harness = try await makeHarness()
        _ = try await warmUp(harness)
        for url in try FileManager.default.contentsOfDirectory(
            at: harness.directory, includingPropertiesForKeys: nil
        ) where url.pathExtension == "kframe" {
            try Data(repeating: 0x42, count: 300).write(to: url)
        }
        let rendersBefore = await harness.fake.previewRequests.count

        harness.viewModel.openImage(data: harness.data, name: "warm.png")
        try await waitUntil("reopen with a corrupt frame") {
            await harness.fake.previewRequests.count == rendersBefore + 1
                && harness.viewModel.previewState == .ready
        }
        try await waitUntil("frame rewritten") { Self.frameFiles(in: harness.directory) == 1 }
        let store = LatestPreviewFrameStore(directory: harness.directory)
        let repaired = await store.read(for: try XCTUnwrap(harness.viewModel.admissionImageSource).portableIdentity)
        XCTAssertNotNil(repaired)
    }

    func testZoomedFramesNeverWriteTheStore() async throws {
        let harness = try await makeHarness()
        let identity = try await warmUp(harness)
        let store = LatestPreviewFrameStore(directory: harness.directory)
        let original = try unwrapAwaited(await store.metadata(for: identity))

        harness.viewModel.toggleCanvasZoom()
        let rendersBefore = await harness.fake.previewRequests.count
        try await waitUntil("zoomed render") {
            await harness.fake.previewRequests.count > rendersBefore
        }
        try await Task.sleep(for: .milliseconds(250))

        let after = try unwrapAwaited(await store.metadata(for: identity))
        XCTAssertEqual(after.presentedAt, original.presentedAt, "an ROI frame must not replace it")
        XCTAssertEqual(after.signature, original.signature)
    }

    private func waitUntil(
        _ description: String, timeout: TimeInterval = 8,
        _ condition: @MainActor @escaping () async -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !(await condition()) {
            if Date() > deadline {
                throw TestSynchronizationError.timedOut(description, "condition did not settle")
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}

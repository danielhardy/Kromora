import CoreGraphics
import CoreImage
import Metal
import XCTest
@testable import LumoKit

/// Acceptance coverage for LUMO-304's completed processing-prefix boundary.
///
/// These tests intentionally use the real RenderEngine. The normal initializer exercises the
/// private Metal texture path, while the injected-context initializer is the deterministic
/// non-GPU seam for the CPU fallback.
@MainActor
final class RenderEngineProcessingPrefixAcceptanceTests: TempDirectoryTestCase {

    func testNoCPUUploadOnLUTTickTest() async throws {
        try XCTSkipUnless(
            MTLCreateSystemDefaultDevice() != nil,
            "Metal is unavailable on this host"
        )

        let source = try makeSource()
        let engine = RenderEngine()
        let prefix = EditDocument(
            light: LightAdjustments(exposure: 0.25),
            effects: EffectsAdjustments(texture: 20, grain: GrainAdjustments(amount: 10))
        )
        let changed = EditDocument(
            light: prefix.light,
            effects: EffectsAdjustments(texture: 20, grain: GrainAdjustments(amount: 70))
        )

        _ = await engine.makeCGImage(request(source: source, document: prefix,
                                             lut: TestImages.identityLUT(name: "first")))
        let beforeTick = await engine.workStatistics()
        XCTAssertEqual(beforeTick.processingPrefixCPUReadbacks, 0)
        XCTAssertEqual(beforeTick.processingPrefixTextureSubmissions, 1)

        _ = await engine.makeCGImage(request(source: source, document: changed,
                                             lut: TestImages.warmLUT(name: "second")))
        let afterTick = await engine.workStatistics()
        XCTAssertEqual(
            afterTick.processingPrefixCPUReadbacks - beforeTick.processingPrefixCPUReadbacks,
            0,
            "a LUT/grain-only tick must not allocate a CPU bitmap for the warm prefix"
        )
        XCTAssertEqual(
            afterTick.processingPrefixTextureSubmissions
                - beforeTick.processingPrefixTextureSubmissions,
            0,
            "a LUT/grain-only tick must not re-submit the cached prefix texture"
        )

        let cache = await engine.cacheStatistics()
        XCTAssertEqual(cache.processingPrefix.hits, 1)
        XCTAssertEqual(cache.processingPrefix.count, 1)
    }

    func testPrefixPixelParityTest() async throws {
        try XCTSkipUnless(
            MTLCreateSystemDefaultDevice() != nil,
            "Metal is unavailable on this host"
        )

        let source = try makeSource()
        let document = EditDocument(
            light: LightAdjustments(exposure: 0.35, contrast: 12),
            color: ColorAdjustments(saturation: 0.18),
            effects: EffectsAdjustments(texture: 18, clarity: 12,
                                        grain: GrainAdjustments(amount: 25)),
            lut: LUTSettings(lutID: TestImages.warmLUT().lutID, intensity: 0.65)
        )
        let lut = TestImages.warmLUT()
        let request = request(source: source, document: document, lut: lut)

        let textureEngine = RenderEngine()
        let cpuEngine = RenderEngine(context: CIContext())
        let textureImageResult = await textureEngine.makeCGImage(request)
        let cpuImageResult = await cpuEngine.makeCGImage(request)
        let textureImage = try XCTUnwrap(textureImageResult)
        let cpuImage = try XCTUnwrap(cpuImageResult)

        assertPixelsEqual(
            try Pixels.bytes(of: textureImage), try Pixels.bytes(of: cpuImage), tolerance: 1,
            "texture-backed and CPU-materialized prefixes must preserve final pixels"
        )

        let textureWork = await textureEngine.workStatistics()
        let cpuWork = await cpuEngine.workStatistics()
        XCTAssertEqual(textureWork.processingPrefixTextureSubmissions, 1)
        XCTAssertEqual(textureWork.processingPrefixCPUReadbacks, 0)
        XCTAssertEqual(cpuWork.processingPrefixTextureSubmissions, 0)
        XCTAssertEqual(cpuWork.processingPrefixCPUReadbacks, 1)
    }

    func testNonGPUFallbackTest() async throws {
        let source = try makeSource()
        let document = EditDocument(
            light: LightAdjustments(exposure: 0.2),
            effects: EffectsAdjustments(texture: 16, clarity: 8)
        )
        let request = request(source: source, document: document)
        let fallbackEngine = RenderEngine(context: CIContext())
        let referenceEngine = RenderEngine()

        let fallbackImageResult = await fallbackEngine.makeCGImage(request)
        let referenceImageResult = await referenceEngine.makeCGImage(request)
        let fallbackImage = try XCTUnwrap(fallbackImageResult)
        let referenceImage = try XCTUnwrap(referenceImageResult)
        assertPixelsEqual(
            try Pixels.bytes(of: fallbackImage), try Pixels.bytes(of: referenceImage), tolerance: 1,
            "the non-GPU prefix fallback must produce the same pixels"
        )

        let work = await fallbackEngine.workStatistics()
        XCTAssertEqual(work.processingPrefixCPUReadbacks, 1,
                       "the forced non-GPU context must exercise materializedImage")
        XCTAssertEqual(work.processingPrefixTextureSubmissions, 0)
        let cache = await fallbackEngine.cacheStatistics()
        XCTAssertEqual(cache.processingPrefix.count, 1)
        XCTAssertGreaterThan(cache.processingPrefix.costBytes, 0)
    }

    func testPressureEvictsTexturePrefixTest() async throws {
        try XCTSkipUnless(
            MTLCreateSystemDefaultDevice() != nil,
            "Metal is unavailable on this host"
        )

        let source = try makeSource()
        let engine = RenderEngine()
        let document = EditDocument(
            light: LightAdjustments(exposure: 0.25),
            effects: EffectsAdjustments(texture: 20)
        )
        _ = await engine.makeCGImage(request(source: source, document: document))

        let warm = await engine.cacheStatistics()
        XCTAssertEqual(warm.processingPrefix.count, 1)
        XCTAssertGreaterThan(warm.processingPrefix.costBytes, 0)

        await engine.evictForMemoryPressure()
        let evicted = await engine.cacheStatistics()
        XCTAssertEqual(evicted.processingPrefix.count, 0)
        XCTAssertEqual(evicted.processingPrefix.costBytes, 0)
        XCTAssertGreaterThanOrEqual(evicted.processingPrefix.evictions, 1)
    }

    func testSettledPublishCountTest() async throws {
        let source = try makeSource()
        let engine = RenderEngine()
        let coordinator = PreviewCoordinator(engine: engine, settleDelay: .zero)
        var publicationLog: [String] = []
        var publishedFrame = false
        var publishedPhase: PreviewCoordinator.Phase?
        coordinator.onPublication = { publication in
            let frame = publication.gpuImage == nil ? "cpu" : "gpu"
            publicationLog.append("settled:\(frame)")
            publishedFrame = publication.gpuImage != nil || publication.image != nil
            publishedPhase = publication.phase
        }

        let document = EditDocument(
            light: LightAdjustments(exposure: 0.25),
            effects: EffectsAdjustments(texture: 20, grain: GrainAdjustments(amount: 40))
        )

        let completionGate = PrefixCompletionGate()
        await engine.setProcessingPrefixCompletionHook {
            await completionGate.pause()
        }
        coordinator.submit(request(source: source, document: document), phase: .settled)

        let gateDeadline = Date().addingTimeInterval(5)
        while !(await completionGate.entered) {
            if Date() > gateDeadline {
                return XCTFail("timed out waiting for the prefix completion re-entry window")
            }
            try await Task.sleep(for: .milliseconds(5))
        }
        await engine.invalidateRenderCaches()
        await completionGate.release()

        try await waitUntil("the settled publication") {
            publicationLog.count == 1
        }
        try await Task.sleep(for: .milliseconds(25))

        XCTAssertEqual(publicationLog.count, 1,
                       "one settle must produce one publication, with no blank intermediate")
        XCTAssertEqual(publishedPhase, .settled)
        XCTAssertTrue(publishedFrame, "the settled publication must carry a non-nil frame")
        let cache = await engine.cacheStatistics()
        XCTAssertEqual(cache.processingPrefix.count, 0,
                       "an invalidated in-flight prefix must not be inserted after completion")
    }

    private func makeSource() throws -> ImageSource {
        let url = try Fixtures.writeGradientPNG(
            width: 96, height: 64, named: "prefix-acceptance.png", in: tempDirectory
        )
        return ImageSource(url: url, nativeExtent: CGSize(width: 96, height: 64))
    }

    private func request(
        source: ImageSource,
        document: EditDocument,
        lut: CubeLUT? = nil
    ) -> RenderRequest {
        RenderRequest(
            source: source, document: document, lut: lut,
            targetSize: CGSize(width: 64, height: 64), quality: .preview,
            output: .raster, space: .sRGB
        )
    }

    private func waitUntil(
        _ description: String,
        timeout: TimeInterval = 5,
        _ condition: @escaping @MainActor () async -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !(await condition()) {
            if Date() > deadline { return XCTFail("timed out waiting for \(description)") }
            try await Task.sleep(for: .milliseconds(5))
        }
    }

}

private actor PrefixCompletionGate {
    private var releaseContinuation: CheckedContinuation<Void, Never>?
    private(set) var entered = false
    private var isReleased = false

    func pause() async {
        entered = true
        guard !isReleased else { return }
        await withCheckedContinuation { continuation in
            releaseContinuation = continuation
        }
    }

    func release() {
        isReleased = true
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

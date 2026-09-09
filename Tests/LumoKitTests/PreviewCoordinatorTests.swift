import XCTest
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import LumoKit

@MainActor
final class PreviewCoordinatorTests: XCTestCase {

    func testRapidInteractiveSubmissionsCoalesceToTheLatestDocument() async throws {
        let fake = ControlledRenderEngine()
        let coordinator = PreviewCoordinator(
            engine: fake, interactiveDelay: .zero, settleDelay: .seconds(10)
        )
        var publications: [PreviewCoordinator.Publication] = []
        coordinator.onPublication = { publications.append($0) }
        coordinator.beginInteraction()

        let source = makeSource()
        for step in 1...5 {
            let value = Double(step) / 10
            coordinator.submit(request(source: source, exposure: value), phase: .interactive)
        }

        try await waitUntil("one coalesced request") {
            await fake.requests.count == 1
        }
        let interactiveRequests = await fake.allRequests()
        XCTAssertEqual(interactiveRequests.first?.document.rawDevelop.exposure, 0.5)

        coordinator.endInteraction()
        try await waitUntil("the settled request") { await fake.requests.count == 2 }
        let allRequests = await fake.allRequests()
        XCTAssertEqual(allRequests[1].quality, .preview)
        XCTAssertEqual(allRequests[1].document.rawDevelop.exposure, 0.5)

        await fake.releaseNext()
        await fake.releaseNext()
        try await waitUntil("the settled publication") { publications.count == 1 }
        XCTAssertEqual(publications.first?.phase, .settled)
        XCTAssertEqual(publications.first?.request.quality, .preview)
        XCTAssertEqual(publications.first?.request.document.rawDevelop.exposure, 0.5)
    }

    func testAStaleResultCannotPublishAfterANewRevision() async throws {
        let fake = ControlledRenderEngine()
        let coordinator = PreviewCoordinator(
            engine: fake, interactiveDelay: .zero, settleDelay: .zero
        )
        var publications: [PreviewCoordinator.Publication] = []
        coordinator.onPublication = { publications.append($0) }
        let source = makeSource()

        coordinator.submit(request(source: source, exposure: 0.1))
        try await waitUntil("the first request") { await fake.requests.count == 1 }
        coordinator.submit(request(source: source, exposure: 0.5))
        try await waitUntil("the replacement request") { await fake.requests.count == 2 }

        await fake.releaseNext()
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertTrue(publications.isEmpty, "the superseded result must not reach UI state")

        await fake.releaseNext()
        try await waitUntil("the current publication") { publications.count == 1 }
        XCTAssertEqual(publications[0].request.document.rawDevelop.exposure, 0.5)
        XCTAssertEqual(publications[0].revision, 2)
    }

    func testPublicationCarriesCallerGenerationsThroughSettling() async throws {
        let fake = FakeRenderEngine()
        let coordinator = PreviewCoordinator(engine: fake, settleDelay: .zero)
        var publications: [PreviewCoordinator.Publication] = []
        coordinator.onPublication = { publications.append($0) }
        let source = makeSource()

        coordinator.submit(
            request(source: source, exposure: 0.5),
            sourceRevision: 17,
            displayRevision: 23
        )

        try await waitUntil("the generation-tagged publication") { publications.count == 1 }
        XCTAssertEqual(publications[0].sourceRevision, 17)
        XCTAssertEqual(publications[0].displayRevision, 23)
    }

    func testAssetIdentityRejectsEqualSourceResultsFromAnEarlierPhoto() async throws {
        let fake = ControlledRenderEngine()
        let coordinator = PreviewCoordinator(engine: fake, settleDelay: .zero)
        var publications: [PreviewCoordinator.Publication] = []
        coordinator.onPublication = { publications.append($0) }
        let source = makeSource()
        let firstAsset = PhotoAssetID.imported(UUID())
        let secondAsset = PhotoAssetID.imported(UUID())

        coordinator.submit(
            request(source: source, exposure: 0.1), assetID: firstAsset,
            sourceRevision: 1, displayRevision: 1
        )
        try await waitUntil("the first asset request") { await fake.requests.count == 1 }
        coordinator.submit(
            request(source: source, exposure: 0.5), assetID: secondAsset,
            sourceRevision: 1, displayRevision: 1
        )
        try await waitUntil("the second asset request") { await fake.requests.count == 2 }

        await fake.releaseNext()
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertTrue(publications.isEmpty, "an equal source is not enough to identify the photo")

        await fake.releaseNext()
        try await waitUntil("the second asset publication") { publications.count == 1 }
        XCTAssertEqual(publications[0].assetID, secondAsset)
    }

    func testSettledGPUPublicationDoesNotRasterizeASecondImage() async throws {
        let fake = GPUBackedRenderEngine()
        let coordinator = PreviewCoordinator(engine: fake)
        var publications: [PreviewCoordinator.Publication] = []
        coordinator.onPublication = { publications.append($0) }

        coordinator.submit(request(source: makeSource(), exposure: 0.5))

        try await waitUntil("the GPU-backed settled publication") { publications.count == 1 }
        XCTAssertEqual(publications[0].phase, .settled)
        XCTAssertNotNil(publications[0].gpuImage)
        XCTAssertNil(publications[0].image)
        let makeCGImageCalls = await fake.makeCGImageCalls
        XCTAssertEqual(makeCGImageCalls, 0)
    }

    func testInteractiveUpdatesDoNotStartAnotherRenderWhileOneIsInFlight() async throws {
        let fake = ControlledRenderEngine()
        let coordinator = PreviewCoordinator(
            engine: fake, interactiveDelay: .zero, settleDelay: .seconds(10)
        )
        coordinator.beginInteraction()
        let source = makeSource()

        coordinator.submit(request(source: source, exposure: 0.1), phase: .interactive)
        try await waitUntil("the first interactive request") { await fake.requests.count == 1 }

        for step in 2...5 {
            coordinator.submit(
                request(source: source, exposure: Double(step) / 10), phase: .interactive
            )
        }
        try await Task.sleep(for: .milliseconds(20))
        let inFlightCount = await fake.requests.count
        XCTAssertEqual(inFlightCount, 1,
                       "superseded pointer values must remain value state, not queued renders")

        await fake.releaseNext()
        try await waitUntil("the latest interactive request") { await fake.requests.count == 2 }
        let requests = await fake.allRequests()
        XCTAssertEqual(requests[1].document.rawDevelop.exposure, 0.5)
        await fake.releaseNext()
        coordinator.endInteraction()
    }

    func testInteractiveToneCurvePublishesBeforeGestureEnds() async throws {
        let fake = FakeRenderEngine()
        let coordinator = PreviewCoordinator(engine: fake, settleDelay: .seconds(10))
        var publications: [PreviewCoordinator.Publication] = []
        coordinator.onPublication = { publications.append($0) }
        let source = makeSource()
        let curve = LightToneCurve(points: [LightCurvePoint(input: 0.5, output: 0.8)])

        coordinator.beginInteraction()
        coordinator.submit(
            RenderRequest(
                source: source,
                document: EditDocument(light: LightAdjustments(toneCurve: curve)),
                targetSize: CGSize(width: 320, height: 240),
                quality: .preview,
                output: .raster
            ),
            phase: .interactive
        )

        try await waitUntil("the intermediate interactive publication") {
            publications.count == 1
        }
        XCTAssertEqual(publications[0].phase, .interactive)
        XCTAssertEqual(publications[0].request.quality, .interactive)
        XCTAssertEqual(
            publications[0].request.document.light.toneCurve.value(at: 0.5),
            0.8,
            accuracy: 0.000_001
        )

        coordinator.endInteraction()
        try await waitUntil("the settled publication") { publications.count == 2 }
        XCTAssertEqual(publications[1].phase, .settled)
        XCTAssertEqual(publications[1].request.quality, .preview)
    }

    func testSettledPromotionRetainsTheOriginatingInputTimestamp() async throws {
        let fake = FakeRenderEngine()
        let coordinator = PreviewCoordinator(engine: fake, settleDelay: .seconds(10))
        let source = makeSource()
        coordinator.beginInteraction()
        coordinator.submit(request(source: source, exposure: 0.5), phase: .interactive)
        try await waitUntil("interactive telemetry") {
            coordinator.telemetry.report().samples.contains { $0.revision == 1 }
        }

        coordinator.endInteraction()
        try await waitUntil("settled telemetry") { coordinator.telemetry.report().samples.count == 2 }
        let samples = coordinator.telemetry.report().samples
        XCTAssertEqual(samples.count, 2)
        XCTAssertEqual(samples[0].inputTime, samples[1].inputTime)
        XCTAssertEqual(samples[1].quality, .preview)
    }

    /// Opt-in smoke benchmark for the pointer-to-pixel path using a 60 MP-class source extent.
    /// The fake renderer keeps this repeatable in CI; the Instruments recipe remains the source of
    /// truth for hardware measurements with a real RAW and GPU.
    func testLargePreviewInteractiveLatencyBenchmark() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["LUMO_BENCH"] != nil,
            "set LUMO_BENCH=1 to run the interactive latency benchmark"
        )

        let fake = FakeRenderEngine()
        let coordinator = PreviewCoordinator(engine: fake, interactiveDelay: .zero)
        let source = ImageSource(
            url: URL(fileURLWithPath: "/tmp/60mp-tone-curve-test.raw"),
            nativeExtent: CGSize(width: 9_504, height: 6_336)
        )
        var publications = 0
        var samples: [Double] = []
        coordinator.onPublication = { publication in
            guard publication.phase == .interactive else { return }
            publications += 1
        }
        coordinator.beginInteraction()

        for step in 0..<20 {
            let before = Date()
            coordinator.submit(
                request(source: source, exposure: Double(step) / 20), phase: .interactive
            )
            try await waitUntil("interactive benchmark frame") { publications == step + 1 }
            samples.append(Date().timeIntervalSince(before) * 1_000)
        }
        coordinator.endInteraction()

        let sorted = samples.sorted()
        let p50 = sorted[sorted.count / 2]
        let p95 = sorted[Int(Double(sorted.count - 1) * 0.95)]
        print(String(format: "tone-curve 60 MP-class pointer-to-pixel latency: p50 %.1f ms, p95 %.1f ms", p50, p95))
        XCTAssertLessThanOrEqual(p95, 50, "interactive preview must stay within the 50 ms budget")
    }

    // MARK: - Two-phase masked preview

    /// A masked photo must not wait on Vision to show anything. The coordinator publishes the
    /// semantics-free frame first, then republishes the same visible revision once the masks
    /// resolve.
    func testMaskedPreviewPublishesABaseFrameBeforeTheResolvedOne() async throws {
        let fake = ControlledRenderEngine()
        let coordinator = PreviewCoordinator(engine: fake, settleDelay: .zero)
        var publications: [PreviewCoordinator.Publication] = []
        coordinator.onPublication = { publications.append($0) }
        let source = makeSource()

        coordinator.submit(maskedRequest(source: source, exposure: 0.1), displayRevision: 7)
        try await waitUntil("the base render") { await fake.requests.count == 1 }
        var requests = await fake.allRequests()
        XCTAssertEqual(requests[0].maskResolution, .deferSemantic,
                       "the first frame of a masked preview must skip semantic resolution")

        await fake.releaseNext()
        try await waitUntil("the base publication") { publications.count == 1 }
        XCTAssertEqual(publications[0].request.maskResolution, .deferSemantic)
        XCTAssertEqual(publications[0].displayRevision, 7)
        let firstPixels = try XCTUnwrap(coordinator.telemetry.measurements.last?.renderEnd)

        try await waitUntil("the refining render") { await fake.requests.count == 2 }
        requests = await fake.allRequests()
        XCTAssertEqual(requests[1].maskResolution, .resolved)
        XCTAssertEqual(requests[1].document, requests[0].document,
                       "the refinement must refine the frame that was published, not a newer one")

        await fake.releaseNext()
        try await waitUntil("the refined publication") { publications.count == 2 }
        XCTAssertEqual(publications[1].request.maskResolution, .resolved)
        XCTAssertEqual(publications[1].displayRevision, 7,
                       "the refinement carries the display revision it refines")
        XCTAssertEqual(coordinator.telemetry.measurements.last?.renderEnd, firstPixels,
                       "pointer-to-pixel latency must describe the frame the user saw first")
    }

    /// The two-phase publish exists to hide Vision latency. Once a resolved frame for the same
    /// photo and mask recipe has landed, the renderer's masks are warm, so a further edit must cost
    /// one render — not two.
    func testWarmSemanticMasksRenderInASinglePhase() async throws {
        let fake = ControlledRenderEngine()
        let coordinator = PreviewCoordinator(engine: fake, settleDelay: .zero)
        var publications: [PreviewCoordinator.Publication] = []
        coordinator.onPublication = { publications.append($0) }
        let source = makeSource()

        coordinator.submit(maskedRequest(source: source, exposure: 0.1))
        try await waitUntil("the base render") { await fake.requests.count == 1 }
        await fake.releaseNext()
        try await waitUntil("the refining render") { await fake.requests.count == 2 }
        await fake.releaseNext()
        try await waitUntil("the refined publication") { publications.count == 2 }

        coordinator.submit(maskedRequest(source: source, exposure: 0.4))
        try await waitUntil("the edited render") { await fake.requests.count == 3 }
        await fake.releaseNext()
        try await waitUntil("the edited publication") { publications.count == 3 }
        let requests = await fake.allRequests()
        XCTAssertEqual(requests.count, 3, "a warm mask recipe must not pay for a second base frame")
        XCTAssertEqual(requests[2].maskResolution, .resolved)

        // Editing the mask recipe itself makes the resolver cold again, so the base frame returns.
        var recipeChange = maskedRequest(source: source, exposure: 0.4)
        recipeChange = RenderRequest(
            source: recipeChange.source, document: EditDocument(
                rawDevelop: RAWDevelopSettings(exposure: 0.4),
                localAdjustments: [Self.maskLayer(target: .person)]
            ),
            targetSize: recipeChange.targetSize, quality: .preview, output: .raster
        )
        coordinator.submit(recipeChange)
        try await waitUntil("the cold base render") { await fake.requests.count == 4 }
        let afterRecipeChange = await fake.allRequests()
        XCTAssertEqual(afterRecipeChange[3].maskResolution, .deferSemantic,
                       "a new smart mask must publish a base frame while Vision resolves it")
    }

    /// The refinement is fenced by the same token as the base frame: a superseded base frame must
    /// neither publish nor drag its own refinement onto the screen behind a newer edit.
    func testASupersededBaseFrameNeitherPublishesNorRefines() async throws {
        let fake = ControlledRenderEngine()
        let coordinator = PreviewCoordinator(engine: fake, settleDelay: .zero)
        var publications: [PreviewCoordinator.Publication] = []
        coordinator.onPublication = { publications.append($0) }
        let source = makeSource()

        coordinator.submit(maskedRequest(source: source, exposure: 0.1))
        try await waitUntil("the first base render") { await fake.requests.count == 1 }
        coordinator.submit(maskedRequest(source: source, exposure: 0.9))
        try await waitUntil("the replacement base render") { await fake.requests.count == 2 }

        await fake.releaseNext()
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertTrue(publications.isEmpty, "the superseded base frame must not reach the screen")
        let afterStale = await fake.allRequests()
        XCTAssertEqual(afterStale.count, 2, "a superseded base frame must not start a refinement")

        await fake.releaseNext()
        try await waitUntil("the current base publication") { publications.count == 1 }
        XCTAssertEqual(publications[0].request.document.rawDevelop.exposure, 0.9)
        try await waitUntil("the current refinement") { await fake.requests.count == 3 }
        await fake.releaseNext()
        try await waitUntil("the current refined publication") { publications.count == 2 }
        XCTAssertEqual(publications[1].request.maskResolution, .resolved)
        XCTAssertEqual(publications[1].request.document.rawDevelop.exposure, 0.9)
    }

    /// A photo with no semantic masks has nothing to wait for, so it must keep the single exact
    /// render it has always had.
    func testUnmaskedPreviewStaysSinglePhase() async throws {
        let fake = ControlledRenderEngine()
        let coordinator = PreviewCoordinator(engine: fake, settleDelay: .zero)
        var publications: [PreviewCoordinator.Publication] = []
        coordinator.onPublication = { publications.append($0) }

        coordinator.submit(request(source: makeSource(), exposure: 0.2))
        try await waitUntil("the only render") { await fake.requests.count == 1 }
        await fake.releaseNext()
        try await waitUntil("the publication") { publications.count == 1 }
        try await Task.sleep(for: .milliseconds(20))
        let requests = await fake.allRequests()
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests[0].maskResolution, .resolved)
    }

    private static func maskLayer(target: SemanticTarget) -> LocalAdjustmentLayer {
        LocalAdjustmentLayer(
            components: [MaskComponent(source: .semantic(SemanticMaskDefinition(target: target)))],
            adjustments: LocalAdjustments(exposure: 0.5)
        )
    }

    private func maskedRequest(source: ImageSource, exposure: Double) -> RenderRequest {
        RenderRequest(
            source: source,
            document: EditDocument(
                rawDevelop: RAWDevelopSettings(exposure: exposure),
                localAdjustments: [Self.maskLayer(target: .subject)]
            ),
            targetSize: CGSize(width: 320, height: 240),
            quality: .preview,
            output: .raster
        )
    }

    private func request(source: ImageSource, exposure: Double) -> RenderRequest {
        RenderRequest(
            source: source,
            document: EditDocument(rawDevelop: RAWDevelopSettings(exposure: exposure)),
            targetSize: CGSize(width: 320, height: 240),
            quality: .preview,
            output: .raster
        )
    }

    private func makeSource() -> ImageSource {
        ImageSource(
            url: URL(fileURLWithPath: "/tmp/preview-coordinator-test.png"),
            nativeExtent: CGSize(width: 32, height: 24)
        )
    }

    private func waitUntil(
        _ description: String,
        timeout: TimeInterval = 2,
        _ condition: @escaping @MainActor () async -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !(await condition()) {
            if Date() > deadline { return XCTFail("timed out waiting for \(description)") }
            try await Task.sleep(for: .milliseconds(5))
        }
    }
}

/// A deterministic renderer that deliberately ignores task cancellation while a request is parked.
/// That models a renderer that has already entered a non-cancellable Core Image operation and proves
/// the coordinator's revision guard, rather than making the test pass only because cancellation was
/// observed before the renderer started.
private actor ControlledRenderEngine: RenderEngining {
    private(set) var requests: [RenderRequest] = []
    private var waiters: [(request: RenderRequest, continuation: CheckedContinuation<RenderResult, Never>)] = []

    func render(_ request: RenderRequest) async throws -> RenderResult {
        requests.append(request)
        return await withCheckedContinuation { continuation in
            waiters.append((request, continuation))
        }
    }

    func releaseNext() {
        guard !waiters.isEmpty else { return }
        let waiter = waiters.removeFirst()
        let request = waiter.request
        let continuation = waiter.continuation
        continuation.resume(returning: RenderResult(
            data: Self.pngData(), extent: CGSize(width: 2, height: 2), colorSpace: .current,
            quality: request.quality, output: request.output
        ))
    }

    func allRequests() -> [RenderRequest] { requests }

    func histogram(
        source: ImageSource, document: EditDocument, lut: CubeLUT?, scale: RenderScale,
        space: WorkingSpace, maxDimension: Int
    ) -> HistogramData? { nil }

    func invalidateLUTCache() {}
    func rawCapabilities(for source: ImageSource) async -> RAWCapabilities? { nil }

    private static func pngData() -> Data {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 8,
            space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(red: 0.5, green: 0.25, blue: 0.75, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(
            data, UTType.png.identifier as CFString, 1, nil
        )!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        precondition(CGImageDestinationFinalize(destination))
        return data as Data
    }
}

private actor GPUBackedRenderEngine: RenderEngining {
    private(set) var makeCGImageCalls = 0

    func makeCIImage(_ request: RenderRequest) async -> sending CIImage? {
        CIImage(color: CIColor(red: 0.5, green: 0.25, blue: 0.75)).cropped(
            to: CGRect(origin: .zero, size: request.targetSize ?? CGSize(width: 2, height: 2))
        )
    }

    func makeCGImage(_ request: RenderRequest) async -> sending CGImage? {
        makeCGImageCalls += 1
        return nil
    }

    func render(_ request: RenderRequest) async throws -> RenderResult {
        fatalError("not used by this test")
    }

    func histogram(
        source: ImageSource, document: EditDocument, lut: CubeLUT?, scale: RenderScale,
        space: WorkingSpace, maxDimension: Int
    ) -> HistogramData? { nil }

    func invalidateLUTCache() {}
    func rawCapabilities(for source: ImageSource) async -> RAWCapabilities? { nil }
}

import CoreImage
import XCTest

@testable import KromoraKit

/// KRMA-1174 through the real `RenderEngine`. The RAW methods need a local camera file (see
/// `Fixtures.localRAWURLs`) and are in the optional lane; the standard-image method runs in the
/// serial render lane.
final class RAWExposureRoutingRenderTests: TempDirectoryTestCase {

    private let box = CGSize(width: 384, height: 384)

    private func rawSources() throws -> [ImageSource] {
        let urls = Fixtures.localRAWURLs
        guard !urls.isEmpty else { throw XCTSkip("no local RAW; see Fixtures.localRAWURLs") }
        return urls.prefix(2).map { ImageSource(url: $0, nativeExtent: CGSize(width: 4000, height: 3000)) }
    }

    private func bytes(
        _ engine: RenderEngine, _ source: ImageSource, _ document: EditDocument,
        lut: CubeLUT? = nil, quality: RenderQuality = .preview
    ) async throws -> [UInt8] {
        let request = RenderRequest(
            source: source, document: document, lut: lut, targetSize: box, quality: quality)
        let image = await engine.makeCGImage(request)
        return try Pixels.bytes(of: try XCTUnwrap(image))
    }

    private func meanLuma(_ pixels: [UInt8]) -> Double {
        var sum = 0.0
        var count = 0.0
        for i in stride(from: 0, to: pixels.count - 3, by: 4) {
            sum += 0.2126 * Double(pixels[i]) + 0.7152 * Double(pixels[i + 1]) + 0.0722 * Double(pixels[i + 2])
            count += 1
        }
        return sum / count
    }

    // MARK: - RAW

    /// The slider and an explicit decoder value of the same size must be one operation: the slider
    /// document renders exactly like the document that spells the decoder exposure directly.
    func testSliderExposureIsAppliedOnceThroughTheDecoder() async throws {
        for source in try rawSources() {
            let engine = RenderEngine()
            let slider = try await bytes(engine, source, EditDocument(light: LightAdjustments(exposure: 1)))
            let decoder = try await bytes(
                engine, source,
                EditDocument(rawDevelop: RAWDevelopSettings(exposure: RAWExposureRouting.decoderExposure(forSliderEV: 1))))
            let neutral = try await bytes(engine, source, EditDocument())
            assertPixelsEqual(slider, decoder, "slider exposure must be exactly the decoder exposure")
            assertPixelsDiffer(slider, neutral, "precondition: exposure must change the frame")
            XCTAssertGreaterThan(meanLuma(slider), meanLuma(neutral))
        }
    }

    func testExplicitDecoderExposureAndSliderCombineWithoutDoubleApplication() async throws {
        let source = try XCTUnwrap(rawSources().first)
        let engine = RenderEngine()
        let combined = try await bytes(
            engine, source,
            EditDocument(rawDevelop: RAWDevelopSettings(exposure: 0.5), light: LightAdjustments(exposure: 1)))
        let spelled = try await bytes(
            engine, source, EditDocument(rawDevelop: RAWDevelopSettings(exposure: 1.25)))
        assertPixelsEqual(combined, spelled, "0.5 + 0.75 decoder stops is one 1.25-stop exposure")
    }

    /// Decoder exposure sits ahead of the Look; RGB exposure sits after it. They must not render alike.
    func testRAWExposureIsAppliedBeforeTheLook() async throws {
        let source = try XCTUnwrap(rawSources().first)
        let engine = RenderEngine()
        let lut = TestImages.warmLUT()
        var document = EditDocument(light: LightAdjustments(exposure: 1))
        document.lut = LUTSettings(lutID: LUTID(raw: "warm"), intensity: 1)

        let routed = try await bytes(engine, source, document, lut: lut)
        let decoderThenLook = try await bytes(
            engine, source,
            EditDocument(
                rawDevelop: RAWDevelopSettings(exposure: 0.75), lut: document.lut), lut: lut)
        let lookThenRGB = try await bytes(
            engine, source,
            EditDocument(adjustments: [.exposure(ev: 1)], lut: document.lut), lut: lut)
        assertPixelsEqual(routed, decoderThenLook, "exposure must precede the Look")
        assertPixelsDiffer(routed, lookThenRGB, "decoder-then-Look is not Look-then-RGB-EV")
    }

    func testInteractiveAndSettledFramesAgreeOnBrightness() async throws {
        let source = try XCTUnwrap(rawSources().first)
        let engine = RenderEngine()
        let document = EditDocument(light: LightAdjustments(exposure: -1.5))
        let interactive = try await bytes(engine, source, document, quality: .interactive)
        let settled = try await bytes(engine, source, document, quality: .preview)
        XCTAssertEqual(meanLuma(interactive), meanLuma(settled), accuracy: 3)
    }

    func testHistogramAndExportFollowTheRoutedDocument() async throws {
        let source = try XCTUnwrap(rawSources().first)
        let engine = RenderEngine()
        let slider = EditDocument(light: LightAdjustments(exposure: 1))
        let decoder = EditDocument(rawDevelop: RAWDevelopSettings(exposure: 0.75))
        let scale = RenderScale.preview(maxSize: box)

        let sliderHistogram = await engine.histogram(
            source: source, document: slider, lut: nil, scale: scale, space: .current, maxDimension: 128)
        let decoderHistogram = await engine.histogram(
            source: source, document: decoder, lut: nil, scale: scale, space: .current, maxDimension: 128)
        let neutralHistogram = await engine.histogram(
            source: source, document: EditDocument(), lut: nil, scale: scale, space: .current, maxDimension: 128)
        XCTAssertEqual(try XCTUnwrap(sliderHistogram), try XCTUnwrap(decoderHistogram))
        XCTAssertNotEqual(try XCTUnwrap(sliderHistogram), try XCTUnwrap(neutralHistogram))

        let exportedSlider = try await engine.encode(
            source: source, document: slider, lut: nil, scale: scale, format: .png, quality: 1, space: .current)
        let exportedDecoder = try await engine.encode(
            source: source, document: decoder, lut: nil, scale: scale, format: .png, quality: 1, space: .current)
        assertPixelsEqual(
            try Pixels.bytes(of: try Pixels.decode(exportedSlider)),
            try Pixels.bytes(of: try Pixels.decode(exportedDecoder)),
            "export must route exposure exactly as preview does")
    }

    /// Moving the slider must invalidate the developed source, and revisiting a value must hit it.
    func testSliderMovesInvalidateAndRevisitsReuseTheDevelopedSource() async throws {
        let source = try XCTUnwrap(rawSources().first)
        let engine = RenderEngine()
        func render(_ ev: Double) async throws {
            _ = try await bytes(engine, source, EditDocument(light: LightAdjustments(exposure: ev)))
        }
        try await render(0.5)
        let afterFirst = await engine.cacheStatistics().developedSource
        try await render(1.0)
        let afterMove = await engine.cacheStatistics().developedSource
        XCTAssertGreaterThan(afterMove.misses, afterFirst.misses, "a new exposure is a new developed source")
        try await render(0.5)
        let afterRevisit = await engine.cacheStatistics().developedSource
        XCTAssertGreaterThan(afterRevisit.hits, afterMove.hits, "a revisited exposure reuses its developed source")
    }

    func testInteractiveExposureTicksReuseOneDecoderFilter() async throws {
        let source = try XCTUnwrap(rawSources().first)
        let engine = RenderEngine()
        for ev in [0.2, 0.4, 0.6, 0.8] {
            _ = try await bytes(
                engine, source, EditDocument(light: LightAdjustments(exposure: ev)), quality: .interactive)
        }
        let work = await engine.workStatistics()
        XCTAssertEqual(work.rawFilterConstructions, 1, "ticks must reuse the interactive RAW session")
        XCTAssertEqual(work.rawOutputRequests, 4)
    }

    // MARK: - Standard images

    func testStandardImageExposureStaysRGBAndIgnoresDecoderExposure() async throws {
        let url = try Fixtures.writeJPEG(
            width: 96, height: 64, orientation: 1, named: "routing.jpg", in: tempDirectory)
        let source = ImageSource(url: url, nativeExtent: CGSize(width: 96, height: 64))
        XCTAssertEqual(source.kind, .standard)
        let engine = RenderEngine()

        let neutral = try await bytes(engine, source, EditDocument())
        let lifted = try await bytes(engine, source, EditDocument(light: LightAdjustments(exposure: 1)))
        let decoderOnly = try await bytes(
            engine, source, EditDocument(rawDevelop: RAWDevelopSettings(exposure: 2)))
        assertPixelsDiffer(lifted, neutral, "RGB exposure must still brighten a standard image")
        XCTAssertGreaterThan(meanLuma(lifted), meanLuma(neutral))
        assertPixelsEqual(decoderOnly, neutral, "decoder settings never reach a standard image")

        let viaPipeline = try XCTUnwrap(
            RenderPipeline.buildImage(
                source: source, document: EditDocument(light: LightAdjustments(exposure: 1)),
                lut: nil, scale: .full))
        XCTAssertEqual(viaPipeline.extent.size, CGSize(width: 96, height: 64))
    }
}

import CoreImage
import XCTest

@testable import KromoraKit

/// KRMA-1175 through the real `RenderEngine`. The RAW methods need a local camera file (see
/// `Fixtures.localRAWURLs`) and are in the optional lane; the standard-image and stage methods run
/// in the serial render lane.
final class RAWDetailRoutingRenderTests: TempDirectoryTestCase {

    private let box = CGSize(width: 384, height: 384)

    private func rawSources() throws -> [ImageSource] {
        let urls = Fixtures.localRAWURLs
        guard !urls.isEmpty else { throw XCTSkip("no local RAW; see Fixtures.localRAWURLs") }
        return urls.prefix(2).map { ImageSource(url: $0, nativeExtent: CGSize(width: 4000, height: 3000)) }
    }

    private func document(
        luminance: Double = 0, colour: Double = 0, sharpening: Double = 0
    ) -> EditDocument {
        var document = EditDocument()
        document.effects.detail = DetailAdjustments(
            sharpeningAmount: sharpening, luminanceNoise: luminance, colorNoise: colour)
        return document
    }

    private func bytes(
        _ engine: RenderEngine, _ source: ImageSource, _ document: EditDocument,
        quality: RenderQuality = .preview, size: CGSize? = nil
    ) async throws -> [UInt8] {
        let request = RenderRequest(
            source: source, document: document, lut: nil, targetSize: size ?? box, quality: quality)
        let image = await engine.makeCGImage(request)
        return try Pixels.bytes(of: try XCTUnwrap(image))
    }

    // MARK: - Standard images (always run)

    func testStandardImageNoiseReductionStaysRGBAndIgnoresDecoderAmounts() async throws {
        let url = try Fixtures.writeJPEG(
            width: 96, height: 64, orientation: 1, named: "detail.jpg", in: tempDirectory)
        let source = ImageSource(url: url, nativeExtent: CGSize(width: 96, height: 64))
        XCTAssertEqual(source.kind, .standard)
        let engine = RenderEngine()
        let neutral = try await bytes(engine, source, EditDocument())
        let decoderOnly = try await bytes(
            engine, source,
            EditDocument(rawDevelop: RAWDevelopSettings(
                luminanceNoiseReductionAmount: 1, colorNoiseReductionAmount: 1)))
        assertPixelsEqual(decoderOnly, neutral, "decoder settings never reach a standard image")
        let routed = document(luminance: 80, colour: 80).routedForRendering(source: .standard)
        XCTAssertEqual(routed.effects.detail.luminanceNoise, 80, "RGB keeps the control")
    }

    // MARK: - RAW

    private func capabilities(_ engine: RenderEngine, _ source: ImageSource) async throws -> RAWCapabilities {
        let capabilities = await engine.rawCapabilities(for: source)
        return try XCTUnwrap(capabilities)
    }

    /// The slider must be exactly the decoder amount: the document that spells that routed form
    /// renders identically, so nothing is applied twice.
    func testSliderNoiseReductionRendersExactlyTheRoutedForm() async throws {
        for source in try rawSources() {
            let engine = RenderEngine()
            let stored = document(luminance: 60, colour: 40)
            let capabilities = try await capabilities(engine, source)
            let spelled = stored.routedForRendering(source: .raw, decoder: capabilities)
            let viaSlider = try await bytes(engine, source, stored)
            let viaSpelling = try await bytes(engine, source, spelled)
            let neutral = try await bytes(engine, source, EditDocument())
            assertPixelsEqual(viaSlider, viaSpelling, "slider NR must route once")
            assertPixelsDiffer(viaSlider, neutral, "precondition: NR must change the frame")
        }
    }

    /// The decoder must be doing the denoising: the routed form with its decoder amounts withheld
    /// renders differently (and the RGB stage has nothing left to do for the routed channels).
    func testTheDecoderAmountIsWhatDenoisesTheRoutedFrame() async throws {
        let source = try XCTUnwrap(rawSources().first)
        let engine = RenderEngine()
        let stored = document(luminance: 100)
        let capabilities = try await capabilities(engine, source)
        var withheldDocument = stored.routedForRendering(source: .raw, decoder: capabilities)
        withheldDocument.rawDevelop.luminanceNoiseReductionAmount = nil
        // Decoder noise reduction acts at sensor scale, so a 384 px frame averages most of it away.
        let routed = try await bytes(engine, source, stored, size: CGSize(width: 1600, height: 1600))
        let withheld = try await bytes(
            engine, source, withheldDocument, size: CGSize(width: 1600, height: 1600))
        if capabilities.isLuminanceNoiseReductionSupported {
            assertPixelsDiffer(routed, withheld, "the decoder amount must change the frame")
        }
    }

    func testInteractiveAndSettledFramesAgreeOnNoiseReduction() async throws {
        let source = try XCTUnwrap(rawSources().first)
        let engine = RenderEngine()
        let stored = document(luminance: 60, colour: 60)
        let interactive = try await bytes(engine, source, stored, quality: .interactive)
        let settled = try await bytes(engine, source, stored, quality: .preview)
        func mean(_ pixels: [UInt8]) -> Double {
            stride(from: 0, to: pixels.count, by: 4).reduce(0.0) { $0 + Double(pixels[$1 + 1]) }
                / Double(pixels.count / 4)
        }
        XCTAssertEqual(mean(interactive), mean(settled), accuracy: 3)
    }

    func testExportFollowsTheRoutedDocument() async throws {
        let source = try XCTUnwrap(rawSources().first)
        let engine = RenderEngine()
        let stored = document(luminance: 60, colour: 40)
        let capabilities = try await capabilities(engine, source)
        let spelled = stored.routedForRendering(source: .raw, decoder: capabilities)
        let scale = RenderScale.preview(maxSize: box)
        let exported = try await engine.encode(
            source: source, document: stored, lut: nil, scale: scale, format: .png, quality: 1, space: .current)
        let reference = try await engine.encode(
            source: source, document: spelled, lut: nil, scale: scale, format: .png, quality: 1, space: .current)
        assertPixelsEqual(
            try Pixels.bytes(of: try Pixels.decode(exported)),
            try Pixels.bytes(of: try Pixels.decode(reference)),
            "export must route noise reduction exactly as preview does")
    }

    /// Moving a noise slider re-develops (it is a decoder input); revisiting a value reuses the
    /// developed source; moving Sharpening — an RGB control — never re-develops.
    func testNoiseTicksRedevelopRevisitsHitAndSharpeningNeverRedevelops() async throws {
        let source = try XCTUnwrap(rawSources().first)
        let engine = RenderEngine()
        func render(_ document: EditDocument) async throws { _ = try await bytes(engine, source, document) }
        try await render(document(luminance: 30))
        let first = await engine.cacheStatistics().developedSource
        try await render(document(luminance: 31))
        let moved = await engine.cacheStatistics().developedSource
        XCTAssertGreaterThan(moved.misses, first.misses, "a new decoder amount is a new developed source")
        try await render(document(luminance: 30))
        let revisited = await engine.cacheStatistics().developedSource
        XCTAssertGreaterThan(revisited.hits, moved.hits, "a revisited amount reuses its developed source")

        try await render(document(luminance: 30, sharpening: 40))
        try await render(document(luminance: 30, sharpening: 70))
        let sharpened = await engine.cacheStatistics().developedSource
        XCTAssertEqual(sharpened.misses, revisited.misses, "Sharpening must not re-develop the RAW")
    }

    func testInteractiveNoiseTicksReuseOneDecoderFilterAndNeverRebuildItForRouting() async throws {
        let source = try XCTUnwrap(rawSources().first)
        let engine = RenderEngine()
        for amount in [20.0, 40, 60, 80] {
            _ = try await bytes(engine, source, document(luminance: amount), quality: .interactive)
        }
        let work = await engine.workStatistics()
        XCTAssertEqual(work.rawFilterConstructions, 1, "ticks must reuse the interactive RAW session")
        XCTAssertEqual(work.rawOutputRequests, 4)
    }

    /// A settled render of a file with no live interactive session reads the decoder state once and
    /// does not evict (or create) the interactive session.
    func testSettledRoutingDoesNotCreateOrEvictTheInteractiveSession() async throws {
        let sources = try rawSources()
        let engine = RenderEngine()
        _ = try await bytes(engine, sources[0], document(luminance: 50), quality: .interactive)
        let before = await engine.workStatistics().rawFilterConstructions
        _ = try await bytes(engine, sources[sources.count - 1], document(luminance: 50), quality: .preview)
        _ = try await bytes(engine, sources[0], document(luminance: 55), quality: .interactive)
        let after = await engine.workStatistics().rawFilterConstructions
        XCTAssertEqual(before, 1)
        XCTAssertEqual(after, 1, "the interactive session for the edited photo must survive an export-like render")
    }
}

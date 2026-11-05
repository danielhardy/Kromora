import CoreImage
import XCTest

@testable import KromoraKit

/// KRMA-1179 through the real `RenderEngine`: the Color controls stay on developed RGB, so a colour
/// slider must never re-develop the RAW, while a stored decoder gamut or EDR setting must. Every
/// method needs a local camera file (`Fixtures.localRAWURLs`), so the class is in the optional lane;
/// the routing rules themselves are the deterministic `RAWColorRoutingTests`.
final class RAWColorRoutingRenderTests: XCTestCase {

    private let box = CGSize(width: 384, height: 384)

    private func sources() throws -> [ImageSource] {
        let urls = Fixtures.localRAWURLs
        guard !urls.isEmpty else { throw XCTSkip("no local RAW; see Fixtures.localRAWURLs") }
        return urls.prefix(3).map { ImageSource(url: $0, nativeExtent: CGSize(width: 4000, height: 3000)) }
    }

    private func bytes(
        _ engine: RenderEngine, _ source: ImageSource, _ document: EditDocument,
        quality: RenderQuality = .preview
    ) async throws -> [UInt8] {
        let request = RenderRequest(
            source: source, document: document, lut: nil, targetSize: box, quality: quality)
        let image = await engine.makeCGImage(request)
        return try Pixels.bytes(of: try XCTUnwrap(image))
    }

    /// Mean (max − min) over mid-luma pixels: a colour-saturation proxy.
    private func chroma(_ pixels: [UInt8]) -> Double {
        var sum = 0.0, count = 0.0
        for i in stride(from: 0, to: pixels.count - 3, by: 4) {
            let r = Int(pixels[i]), g = Int(pixels[i + 1]), b = Int(pixels[i + 2])
            let y = 0.2126 * Double(r) + 0.7152 * Double(g) + 0.0722 * Double(b)
            guard y >= 40, y <= 215 else { continue }
            sum += Double(max(r, g, b) - min(r, g, b))
            count += 1
        }
        return count > 0 ? sum / count : 0
    }

    private func color(_ saturation: Double) -> EditDocument {
        EditDocument(color: ColorAdjustments(saturation: saturation))
    }

    /// Four interactive Saturation ticks cost one decoder output (the first frame) and one filter.
    func testInteractiveColorTicksNeverAskTheDecoderAgain() async throws {
        for source in try sources() {
            let engine = RenderEngine()
            for saturation in [10.0, 20, 30, 40] {
                _ = try await bytes(engine, source, color(saturation), quality: .interactive)
            }
            let work = await engine.workStatistics()
            XCTAssertLessThanOrEqual(work.rawFilterConstructions, 1)
            XCTAssertEqual(work.rawOutputRequests, 1, "colour ticks are RGB work on the completed decode")
        }
    }

    /// Colour edits reuse the developed source; a decoder gamut or EDR change is a new one.
    func testColorEditsReuseTheDevelopedSourceAndDecoderColorSettingsInvalidateIt() async throws {
        for source in try sources() {
            let engine = RenderEngine()
            _ = try await bytes(engine, source, color(0))
            let first = await engine.cacheStatistics().developedSource

            let saturated = try await bytes(engine, source, color(50))
            let afterColor = await engine.cacheStatistics().developedSource
            XCTAssertEqual(afterColor.misses, first.misses, "Saturation must not re-develop")
            XCTAssertGreaterThan(afterColor.hits, first.hits)
            let plain = try await bytes(engine, source, color(0))
            assertPixelsDiffer(saturated, plain, "precondition")

            _ = try await bytes(engine, source, EditDocument(rawDevelop: RAWDevelopSettings(gamutMappingEnabled: false)))
            let afterGamut = await engine.cacheStatistics().developedSource
            XCTAssertGreaterThan(afterGamut.misses, afterColor.misses, "gamut mapping is a new developed source")

            _ = try await bytes(engine, source, EditDocument(rawDevelop: RAWDevelopSettings(extendedDynamicRangeAmount: 1)))
            let afterEDR = await engine.cacheStatistics().developedSource
            XCTAssertGreaterThan(afterEDR.misses, afterGamut.misses, "EDR is a new developed source")
        }
    }

    /// A stored decoder gamut/EDR setting is honored once and a colour edit stacks on it in RGB order.
    func testColorEditAppliesAfterAStoredDecoderColorSetting() async throws {
        for source in try sources() {
            let engine = RenderEngine()
            let decoder = RAWDevelopSettings(gamutMappingEnabled: false, extendedDynamicRangeAmount: 1)
            let plain = try await bytes(engine, source, EditDocument(rawDevelop: decoder))
            let edited = try await bytes(
                engine, source,
                EditDocument(rawDevelop: decoder, color: ColorAdjustments(saturation: 60)))
            XCTAssertGreaterThan(chroma(edited), chroma(plain), "Saturation still acts on a RAW with decoder settings")
            // Same decoder settings in a fresh engine: the cache is not what produced the result.
            let fresh = try await bytes(RenderEngine(), source, EditDocument(rawDevelop: decoder, color: ColorAdjustments(saturation: 60)))
            assertPixelsEqual(edited, fresh, "cached and cold renders agree")
        }
    }

    func testInteractiveAndSettledFramesAgreeOnColor() async throws {
        for source in try sources() {
            let engine = RenderEngine()
            let document = color(60)
            let interactive = try await bytes(engine, source, document, quality: .interactive)
            let settled = try await bytes(engine, source, document)
            XCTAssertEqual(chroma(interactive), chroma(settled), accuracy: 3)
        }
    }

    func testExportFollowsTheSameColorDocumentAsPreview() async throws {
        for source in try sources() {
            let engine = RenderEngine()
            let scale = RenderScale.preview(maxSize: box)
            let document = EditDocument(
                rawDevelop: RAWDevelopSettings(gamutMappingEnabled: false),
                color: ColorAdjustments(vibrance: 40, saturation: 30))
            let preview = try await bytes(engine, source, document)
            let exported = try await engine.encode(
                source: source, document: document, lut: nil, scale: scale, format: .png, quality: 1, space: .current)
            let exportedPixels = try Pixels.bytes(of: try Pixels.decode(exported))
            assertPixelsEqual(preview, exportedPixels, "preview and export use the same color document")

            let repeatedExport = try await RenderEngine().encode(
                source: source, document: document, lut: nil, scale: scale, format: .png, quality: 1, space: .current)
            assertPixelsEqual(
                exportedPixels,
                try Pixels.bytes(of: try Pixels.decode(repeatedExport)),
                "export is deterministic for the colour document")
            let neutral = try await engine.encode(
                source: source, document: EditDocument(), lut: nil, scale: scale, format: .png, quality: 1, space: .current)
            assertPixelsDiffer(
                exportedPixels,
                try Pixels.bytes(of: try Pixels.decode(neutral)), "precondition: the edit changes the export")
        }
    }
}

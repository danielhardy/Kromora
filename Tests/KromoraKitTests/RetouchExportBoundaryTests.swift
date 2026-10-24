import CoreGraphics
import ImageIO
import XCTest

@testable import KromoraKit

/// KRMA-1076: the signed app's full-size PNG export (`ExportCoordinator` → `RenderEngine.encode` with
/// asset identity and export options, streamed to a file) must carry the same retouch pixels as the
/// in-memory `RenderEngine.render` path the qualification harness uses. This pins the boundary within
/// one build using one generated source and document. It does not establish whether the previously
/// observed difference between a signed Release app and a Debug harness is caused by build mode or
/// time-separated Core Image evaluation.
final class RetouchExportBoundaryTests: TempDirectoryTestCase {
    private let width = 1200, height = 900

    private func makeSource() throws -> (source: ImageSource, url: URL) {
        var rgba = [UInt8](repeating: 255, count: width * height * 4)
        var state: UInt32 = 1076
        for y in 0..<height { for x in 0..<width {
            state = state &* 1664525 &+ 1013904223
            let noise = Int(state >> 28) - 8
            let base = 90 + (x * 80 / width) + (y * 40 / height)
            let dx = x - 700, dy = y - 420
            let speck = dx * dx + dy * dy < 49 ? -60 : 0
            let o = (y * width + x) * 4
            for c in 0..<3 { rgba[o + c] = UInt8(clamping: base + noise + speck + c * 6) }
        }}
        let provider = CGDataProvider(data: Data(rgba) as CFData)!
        let image = CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        let url = try Fixtures.writePNG(image, named: "boundary.png", in: tempDirectory)
        return (ImageSource(url: url, nativeExtent: CGSize(width: width, height: height)), url)
    }

    private func document() -> EditDocument {
        var document = EditDocument()
        let spot = RetouchSpot(
            mode: .heal,
            region: RetouchRegion(
                samples: [BrushSample(point: CGPoint(x: 700.0 / 1200, y: 1 - 420.0 / 900))],
                radius: 14.0 / 900))
        document.retouch = RetouchSettings(spots: [spot])
        return document
    }

    private func decode(_ data: Data) throws -> [UInt8] {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        return try Pixels.bytes(of: CIImage(cgImage: image))
    }

    private func maxDelta(_ a: [UInt8], _ b: [UInt8]) -> (count: Int, max: Int) {
        var count = 0, peak = 0
        for index in a.indices where a[index] != b[index] {
            count += 1
            peak = max(peak, abs(Int(a[index]) - Int(b[index])))
        }
        return (count, peak)
    }

    func testStreamedExportWithAssetIdentityMatchesInMemoryRenderForAutomaticHeal() async throws {
        let (source, sourceURL) = try makeSource()
        let document = document()
        let assetID = PhotoAssetID.file(sourceURL)

        let inMemory = try await RenderEngine(maskResolver: DefaultLocalMaskResolver()).render(RenderRequest(
            source: source, document: document, quality: .export, output: .encoded(format: .png, quality: 1)))

        let options = ExportOptions(format: .png, quality: 0.95, sizing: .fullSize)
        let stagingURL = tempDirectory.appendingPathComponent("streamed.png")
        try await RenderEngine(maskResolver: DefaultLocalMaskResolver()).encode(RenderRequest(
            source: source, assetID: assetID, document: document, quality: .export,
            output: .encoded(format: .png, quality: CGFloat(options.quality)), exportOptions: options),
            to: stagingURL)

        let baseline = try decode(inMemory.data)
        let streamed = try decode(try Data(contentsOf: stagingURL))
        XCTAssertEqual(baseline.count, streamed.count)
        let delta = maxDelta(baseline, streamed)
        // Core Image can move a byte by 1 between runs; anything larger is a real path difference.
        XCTAssertLessThanOrEqual(delta.max, 1, "streamed vs in-memory differ by \(delta)")

        let neutral = try await RenderEngine(maskResolver: DefaultLocalMaskResolver()).render(RenderRequest(
            source: source, document: EditDocument(), quality: .export,
            output: .encoded(format: .png, quality: 1)))
        XCTAssertGreaterThan(maxDelta(try decode(neutral.data), baseline).count, 0,
                             "the automatic Heal must actually change pixels")
    }

    // KRMA-1086: the app's export builds its source with a zero `nativeExtent`
    // (`ExportCoordinator.sourceAccess`); the qualification harness declared the real size. The
    // automatic Heal source and the exported pixels must not depend on that hint.

    private func undeclared(_ source: ImageSource, at url: URL) -> ImageSource {
        ImageSource(url: url, nativeExtent: .zero)
    }

    // KRMA-1094: a resolved automatic Heal set is reused, and re-picked when the set changes.
    func testAutomaticHealSourcesAreCachedAcrossBuilds() async throws {
        let (source, _) = try makeSource()
        var doc = document()
        let engine = RenderEngine(maskResolver: DefaultLocalMaskResolver())
        func render(_ d: EditDocument) async throws -> [UInt8] {
            try decode(try await engine.render(RenderRequest(
                source: source, document: d, quality: .export, output: .encoded(format: .png, quality: 1))).data)
        }
        let first = try await render(doc)
        let picks = await engine.retouchPickCount
        XCTAssertGreaterThan(picks, 0)
        let second = try await render(doc)
        let afterSecond = await engine.retouchPickCount
        XCTAssertEqual(afterSecond, picks, "unchanged document must not re-pick")
        XCTAssertEqual(first, second)

        doc.retouch.spots[0].opacity = 0.5
        _ = try await render(doc)
        let afterOpacity = await engine.retouchPickCount
        XCTAssertEqual(afterOpacity, picks, "nonzero opacity does not change blocker participation")

        doc.retouch.spots[0].opacity = 0
        _ = try await render(doc)
        let afterZeroOpacity = await engine.retouchPickCount
        XCTAssertGreaterThan(afterZeroOpacity, afterOpacity, "a zero-opacity spot no longer blocks picks")

        doc.retouch.spots[0].feather = 0.6
        _ = try await render(doc)
        let afterFeather = await engine.retouchPickCount
        XCTAssertGreaterThan(afterFeather, afterZeroOpacity, "feather change must re-pick")
    }

    func testAutomaticHealSourceDoesNotDependOnDeclaredNativeExtent() async throws {
        let (declared, url) = try makeSource()
        let hintless = undeclared(declared, at: url)
        let settings = document().retouch
        let spotID = try XCTUnwrap(settings.spots.first?.id)

        let engine = RenderEngine(maskResolver: DefaultLocalMaskResolver())
        let withHint = await engine.pickRetouchSource(source: declared, settings: settings, spotID: spotID, rank: 0)
        let withoutHint = await RenderEngine(maskResolver: DefaultLocalMaskResolver())
            .pickRetouchSource(source: hintless, settings: settings, spotID: spotID, rank: 0)
        XCTAssertNotNil(withHint)
        XCTAssertEqual(withHint, withoutHint, "automatic Heal source differs when nativeExtent is not declared")
    }

    func testExportPixelsDoNotDependOnDeclaredNativeExtent() async throws {
        let (declared, url) = try makeSource()
        let hintless = undeclared(declared, at: url)
        let document = document()
        let options = ExportOptions(format: .png, quality: 1, sizing: .fullSize)

        func encoded(_ source: ImageSource, name: String) async throws -> [UInt8] {
            let out = tempDirectory.appendingPathComponent(name)
            try await RenderEngine(maskResolver: DefaultLocalMaskResolver()).encode(RenderRequest(
                source: source, document: document, quality: .export,
                output: .encoded(format: .png, quality: 1), exportOptions: options), to: out)
            return try decode(try Data(contentsOf: out))
        }
        let withHint = try await encoded(declared, name: "declared.png")
        let withoutHint = try await encoded(hintless, name: "undeclared.png")
        XCTAssertEqual(withHint.count, withoutHint.count)
        let delta = maxDelta(withHint, withoutHint)
        XCTAssertEqual(delta.count, 0, "export differs by \(delta) when nativeExtent is not declared")
    }
}

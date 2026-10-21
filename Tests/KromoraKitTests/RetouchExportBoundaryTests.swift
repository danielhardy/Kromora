import CoreGraphics
import ImageIO
import XCTest

@testable import KromoraKit

/// KRMA-1076: the signed app's full-size PNG export (`ExportCoordinator` → `RenderEngine.encode` with
/// asset identity and export options, streamed to a file) must carry the same retouch pixels as the
/// in-memory `RenderEngine.render` path the qualification harness uses. This pins the boundary in one
/// build, with one source and one persisted document, so a difference here is a product inconsistency
/// and a difference only across builds or time-separated runs is not.
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
}

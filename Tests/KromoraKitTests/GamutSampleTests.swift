import CoreImage
import XCTest
@testable import KromoraKit

/// The production sample path (KRMA-1132): a generated extended-linear Display P3 image goes through
/// `RenderEngine.gamutSample` and `GamutTally`, and the shares match patch areas known by construction.
final class GamutSampleTests: XCTestCase {
    /// 4 quadrants of a 32x32 image: sRGB-safe gray, P3-only green, beyond-P3 (negative red), sRGB-safe skin.
    private func patchImage() -> CIImage {
        let side = 32
        var floats = [Float](repeating: 0, count: side * side * 4)
        for y in 0..<side {
            for x in 0..<side {
                let quadrant = (y < side / 2 ? 0 : 2) + (x < side / 2 ? 0 : 1)
                let rgb: SIMD3<Float>
                switch quadrant {
                case 0: rgb = SIMD3(0.4, 0.4, 0.4)
                case 1: rgb = SIMD3(0, 1, 0)            // P3 green: outside sRGB, inside P3
                case 2: rgb = SIMD3(-0.2, 0.6, 0.1)     // beyond P3
                default: rgb = SIMD3(0.6, 0.35, 0.2)
                }
                let i = (y * side + x) * 4
                floats[i] = rgb.x; floats[i + 1] = rgb.y; floats[i + 2] = rgb.z; floats[i + 3] = 1
            }
        }
        let data = floats.withUnsafeBufferPointer { Data(buffer: $0) }
        return CIImage(
            bitmapData: data, bytesPerRow: side * 16, size: CGSize(width: side, height: side),
            format: .RGBAf, colorSpace: WorkingSpace.current.linearWorkingColorSpace
        )
    }

    func testExtendedSampleRetainsBeyondP3AndSharesMatchPatchAreas() async throws {
        let engine = RenderEngine()
        let result = await engine.gamutSample(presentedImage: patchImage(), maxDimension: 64)
        let sample = try XCTUnwrap(result)
        XCTAssertEqual(sample.linearDisplayP3.count, 32 * 32)
        XCTAssertLessThan(try XCTUnwrap(sample.linearDisplayP3.map(\.x).min()), -0.1,
                          "the sample must keep out-of-range values")

        let tally = GamutTally(linearDisplayP3: sample.linearDisplayP3)
        XCTAssertTrue(tally.measuresBeyondP3)
        XCTAssertEqual(tally.outsideP3Fraction, 0.25, accuracy: 0.01)
        XCTAssertEqual(tally.outsideSRGBFraction, 0.50, accuracy: 0.01)
    }

    func testSampleIsBoundedByMaxDimension() async throws {
        let engine = RenderEngine()
        let result = await engine.gamutSample(presentedImage: patchImage(), maxDimension: 8)
        let sample = try XCTUnwrap(result)
        XCTAssertLessThanOrEqual(sample.linearDisplayP3.count, 8 * 8)
    }
}

/// Opt-in local-fixture lane (KRMA-1132): measures the share outside sRGB/P3 on real camera files
/// through the production sample path and logs it for comparison with the KRMA-1114 figures.
final class GamutSampleLocalFixtureTests: XCTestCase {
    func testLocalFixtureGamutShares() async throws {
        let urls = Fixtures.localRAWURLs
        try XCTSkipIf(urls.isEmpty, "no local RAW fixtures")
        let engine = RenderEngine()
        for url in urls {
            let source = ImageSource(url: url, nativeExtent: .zero)
            let preparedResult = await engine.prepareSource(source)
            let prepared = try XCTUnwrap(preparedResult)
            let request = RenderRequest(
                source: prepared.source, document: EditDocument(),
                targetSize: CGSize(width: 512, height: 512),
                quality: .preview, output: .raster, space: .current
            )
            let rendered = await engine.makeCIImage(request)
            let image = try XCTUnwrap(rendered)
            let result = await engine.gamutSample(presentedImage: image, maxDimension: 512)
            let sample = try XCTUnwrap(result)
            let tally = GamutTally(linearDisplayP3: sample.linearDisplayP3)
            print(String(format: "GAMUT %@ outsideSRGB=%.2f%% outsideP3=%.2f%% n=%d",
                         url.lastPathComponent, tally.outsideSRGBFraction * 100,
                         tally.outsideP3Fraction * 100, tally.pixelCount))
            XCTAssertGreaterThan(tally.pixelCount, 0)
        }
    }
}

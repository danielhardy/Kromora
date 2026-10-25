import XCTest
import CoreGraphics
@testable import KromoraKit

/// A space change must never reuse a stale render: every cache key and frame signature carries the
/// working space, and the live engine caches keep the two spaces apart. Spaces are constructed
/// explicitly; `WorkingSpace.current` is never flipped.
final class WorkingSpaceIdentityTests: TempDirectoryTestCase {
    private var source: ImageSource!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let url = try Fixtures.writeGradientPNG(width: 96, height: 64, named: "src.png", in: tempDirectory)
        source = ImageSource(url: url, nativeExtent: CGSize(width: 96, height: 64))
    }

    func testCacheKeysDifferOnlyBySpace() {
        let fingerprint = RenderSourceFingerprint(source)
        let scale = RenderScaleKey(.preview(maxSize: CGSize(width: 64, height: 64)))

        func developed(_ space: WorkingSpace) -> DevelopedSourceCacheKey {
            DevelopedSourceCacheKey(
                source: fingerprint, developHash: "d", scale: scale, space: space, pipelineVersion: 1
            )
        }
        func prefix(_ space: WorkingSpace) -> ProcessingPrefixCacheKey {
            ProcessingPrefixCacheKey(
                source: fingerprint, developHash: "d", upstreamHash: "u", scale: scale,
                sourceROI: nil, space: space, includePostRenderWhiteBalance: false, pipelineVersion: 1
            )
        }
        func preview(_ space: WorkingSpace) -> PreviewCacheKey {
            PreviewCacheKey(
                source: fingerprint, documentHash: "h", lutFingerprint: "l", targetScale: scale,
                sourceROI: nil, presentationROI: nil, quality: .preview, space: space,
                pipelineVersion: 1
            )
        }
        XCTAssertNotEqual(developed(.sRGB), developed(.displayP3))
        XCTAssertNotEqual(prefix(.sRGB), prefix(.displayP3))
        XCTAssertNotEqual(preview(.sRGB), preview(.displayP3))
        XCTAssertEqual(developed(.sRGB), developed(.sRGB))
    }

    func testFrameSignaturesDifferBySpace() {
        let identity = FrameFixtures.identity()
        func signature(_ space: WorkingSpace) -> FrameSignature {
            FrameSignature(
                source: identity, editHash: "e", look: .none, workingSpace: space,
                pixelEpoch: RenderPipeline.pixelEpoch
            )
        }
        XCTAssertNotEqual(signature(.sRGB), signature(.displayP3))
    }

    func testThumbnailEncodingFollowsTheGivenSpace() throws {
        let p3 = try XCTUnwrap(CGContext(
            data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
            space: WorkingSpace.displayP3.cgColorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        )?.makeImage())
        XCTAssertEqual(ThumbnailFrameEncoder.normalizedRaster(p3, space: .displayP3)?.space, .displayP3)
        XCTAssertEqual(
            ThumbnailFrameEncoder.normalizedRaster(p3, space: .sRGB)?.space, .sRGB,
            "a P3 raster is converted for an sRGB space, not stored as P3"
        )
    }

    func testEngineCachesKeepSpacesApart() async throws {
        let engine = RenderEngine()
        let lut = TestImages.warmLUT()
        let document = EditDocument(lut: LUTSettings(lutID: lut.lutID, intensity: 1))
        func request(_ space: WorkingSpace) -> RenderRequest {
            RenderRequest(
                source: source, document: document, lut: lut,
                targetSize: CGSize(width: 64, height: 64), quality: .preview,
                output: .raster, space: space
            )
        }
        let srgb = try await engine.render(request(.sRGB))
        let p3 = try await engine.render(request(.displayP3))
        XCTAssertEqual(srgb.colorSpace, .sRGB)
        XCTAssertEqual(p3.colorSpace, .displayP3, "a P3 request must not be served the sRGB entry")
        XCTAssertNotEqual(srgb.data, p3.data)

        let stats = await engine.cacheStatistics()
        XCTAssertEqual(stats.preview.count, 2)
        let again = try await engine.render(request(.sRGB))
        XCTAssertEqual(again.data, srgb.data)
        XCTAssertEqual(again.colorSpace, .sRGB)
    }
}

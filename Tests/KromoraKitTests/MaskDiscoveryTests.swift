import CoreGraphics
import XCTest
@testable import KromoraKit

@MainActor
final class MaskDiscoveryTests: XCTestCase {
    private func reference() -> RegionMaskReference {
        RegionMaskReference(
            cacheKey: MaskCacheKey(
                assetID: PhotoAssetID(rawValue: "discovery"),
                sourceFingerprint: .data(Data([1]), digest: "discovery"), kind: .subject),
            size: PixelDimensions(width: 2, height: 2))
    }

    func testSupersededCompletionAndTeardownCannotAffectNewRequest() {
        let state = MaskDiscoveryState()
        let old = state.begin(title: "Subject", now: 0)
        let current = state.begin(title: "Background", now: 1)
        state.resolve(old, reference: reference())
        state.end(old, now: 2)
        state.finish(old)
        XCTAssertEqual(state.request?.id, current)
        XCTAssertEqual(state.request?.phase, .waiting)
        state.resolve(current, reference: reference())
        state.end(current, now: 3) // request-task defer must preserve a successful reveal
        XCTAssertEqual(state.request?.phase, .resolved(reference()))
    }

    func testCancellationAndLateSuccessNeverReveal() {
        let state = MaskDiscoveryState()
        let id = state.begin(title: "Person", now: 0)
        state.end(id, now: 12)
        state.resolve(id, reference: reference())
        XCTAssertEqual(state.request?.phase, .ending(12))
        state.reset()
        state.resolve(id, reference: reference())
        XCTAssertNil(state.request)
    }

    func testQuickAndLongOperationsHaveBoundedEnvelopes() {
        XCTAssertEqual(MaskDiscoveryTiming.waitingOpacity(elapsed: 0), 0)
        for elapsed in [0.001, 0.1, 1, 30, 90, 3_600] {
            let opacity = MaskDiscoveryTiming.waitingOpacity(elapsed: elapsed)
            XCTAssertGreaterThanOrEqual(opacity, 0)
            XCTAssertLessThanOrEqual(opacity, 1)
        }
        XCTAssertEqual(MaskDiscoveryTiming.revealProgress(elapsed: 0), 0)
        XCTAssertEqual(MaskDiscoveryTiming.revealProgress(elapsed: 90), 1)
        XCTAssertLessThan(MaskDiscoveryTiming.waitingOpacity(elapsed: 90),
                          MaskDiscoveryTiming.waitingOpacity(elapsed: 1))
    }

    func testShaderMappingMatchesDocumentGeometryIncludingPerspective() throws {
        var crop = CropAdjustments.neutral
        crop.flipHorizontal = true
        crop.flipVertical = true
        crop.straightenAngle = 7
        crop.verticalPerspective = 0.25
        crop.horizontalPerspective = -0.18
        crop.normalizedRect = CGRect(x: 0.1, y: 0.2, width: 0.7, height: 0.6)
        for rotation in ImageRotation.allCases {
            let mapping = GeometryPointMapping(
                sourceSize: CGSize(width: 600, height: 400), rotation: rotation, crop: crop)
            let geometry = try XCTUnwrap(MaskDiscoveryGeometry(
                mapping: mapping, navigation: CanvasNavigation(),
                viewportSize: CGSize(width: 800, height: 600), backingScale: 2))
            for point in [CGPoint(x: 0.1, y: 0.3), CGPoint(x: 0.65, y: 0.8),
                          CGPoint(x: 0.5, y: 0.5)] {
                let expected = try XCTUnwrap(mapping.inverse(point))
                let actual = geometry.sourcePoint(forOutput: point)
                XCTAssertEqual(actual.x, expected.x, accuracy: 0.00001)
                XCTAssertEqual(actual.y, expected.y, accuracy: 0.00001)
            }
            let expectedCanvas = CanvasMaskTransform(
                sourceSize: mapping.outputSize, crop: crop, viewportSize: CGSize(width: 800, height: 600),
                backingScale: 2)
            XCTAssertEqual(geometry.imageRect, expectedCanvas.viewportRect(forSourceNormalized: expectedCanvas.cropRect))
        }
    }

    func testDisplayRasterPreservesOrientationAndCapsMemory() throws {
        let pixels = try NormalizedMask(size: PixelDimensions(width: 2, height: 2), values: [0, 0.5, 1, 0])
        let raster = try MaskDiscoveryRaster.make(from: pixels)
        XCTAssertEqual(raster.bytes, [0, 128, 255, 0])
        let large = try NormalizedMask(
            size: PixelDimensions(width: 1_024, height: 512),
            values: Array(repeating: 0.5, count: 1_024 * 512))
        let capped = try MaskDiscoveryRaster.make(from: large)
        XCTAssertEqual(capped.size, PixelDimensions(width: 512, height: 256))
        XCTAssertEqual(capped.bytes.count, 512 * 256)
    }
}

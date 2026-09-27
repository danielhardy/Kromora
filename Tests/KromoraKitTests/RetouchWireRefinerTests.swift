import Foundation
import XCTest

@testable import KromoraKit

final class RetouchWireRefinerTests: XCTestCase {
    func testStraightWireWithDeliberateOverspraySnapsToNarrowRidge() throws {
        let proxy = image(width: 160, height: 100) { x, y in
            let distance = abs(Double(y) - 50)
            let value: Float = distance <= 2 ? 28 : 68
            return SIMD3(value, 0, 0)
        }
        let region = roughRegion([(12, 44), (148, 44)], width: 160, height: 100, radius: 10)
        let proposal = try RetouchWireRefiner.refine(region: region, in: proxy, sourceWidth: 160, sourceHeight: 100)
        XCTAssertGreaterThan(proposal.region.samples.count, region.samples.count)
        XCTAssertLessThan(proposal.region.samples.map { abs($0.point.y * 99 - 50) }.reduce(0, +) / Double(proposal.region.samples.count), 1.6)
        XCTAssertLessThan(proposal.region.radius, region.radius * 0.4)
        XCTAssertGreaterThan(proposal.confidence, 0.5)
    }

    func testSaggingLowContrastWireCrossesAHorizontalEdgeAndPreservesBend() throws {
        let proxy = image(width: 180, height: 120) { x, y in
            let sag = 48 + 0.002 * Double(x - 90) * Double(x - 90)
            let wire = abs(Double(y) - sag) <= 1.5
            let roofEdge = y == 62
            let base: Float = y < 62 ? 62 : 66
            let value: Float = wire ? base - 9 : (roofEdge ? base + 9 : base)
            return SIMD3(value, 0, 0)
        }
        let region = roughRegion([(15, 57), (60, 50), (112, 50), (165, 59)], width: 180, height: 120, radius: 9)
        let proposal = try RetouchWireRefiner.refine(region: region, in: proxy, sourceWidth: 180, sourceHeight: 120)
        let meanError = proposal.region.samples.map { sample in
            let x = sample.point.x * 179
            let expected = 48 + 0.002 * (x - 90) * (x - 90)
            return abs(sample.point.y * 119 - expected)
        }.reduce(0, +) / Double(proposal.region.samples.count)
        XCTAssertLessThan(meanError, 2.5)
        XCTAssertLessThan(proposal.region.radius, region.radius)
    }

    func testAmbiguousTexturedCorridorIsRejected() {
        let proxy = image(width: 128, height: 96) { x, y in
            let pattern: Float = ((x / 3 + y / 3).isMultiple(of: 2)) ? 30 : 72
            return SIMD3(pattern, 0, 0)
        }
        let region = roughRegion([(8, 40), (120, 45)], width: 128, height: 96, radius: 12)
        XCTAssertThrowsError(try RetouchWireRefiner.refine(
            region: region, in: proxy, sourceWidth: 128, sourceHeight: 96
        )) { XCTAssertEqual($0 as? RetouchWireRefiner.Failure, .ambiguous) }
    }

    func testCancellationIsObservedBeforeProposal() {
        let proxy = image(width: 64, height: 48) { _, y in SIMD3(y == 24 ? 20 : 70, 0, 0) }
        let region = roughRegion([(4, 20), (60, 20)], width: 64, height: 48, radius: 8)
        XCTAssertThrowsError(try RetouchWireRefiner.refine(
            region: region, in: proxy, sourceWidth: 64, sourceHeight: 48, isCancelled: { true }
        )) { XCTAssertEqual($0 as? RetouchWireRefiner.Failure, .cancelled) }
    }

    func testOneThroughEightPixelWireWidthsWithBrushOverspray() throws {
        for wireWidth in 1...8 {
            let proxy = image(width: 144, height: 80) { _, y in
                let onWire = abs(Double(y) - 40) <= Double(wireWidth) * 0.5
                return SIMD3(onWire ? 34 : 68, 0, 0)
            }
            let region = roughRegion([(10, 44), (134, 44)], width: 144, height: 80, radius: 12)
            let proposal = try RetouchWireRefiner.refine(region: region, in: proxy, sourceWidth: 144, sourceHeight: 80)
            let meanError = proposal.region.samples.map { abs($0.point.y * 79 - 40) }
                .reduce(0, +) / Double(proposal.region.samples.count)
            XCTAssertLessThan(meanError, 2.0, "\(wireWidth) px wire should stay centered")
            XCTAssertLessThan(proposal.region.radius, region.radius)
        }
    }

    func testSinglePointDustSpotIsNotEligibleForWireRefinement() {
        let proxy = image(width: 64, height: 48) { _, _ in SIMD3(60, 0, 0) }
        let circle = RetouchRegion(samples: [BrushSample(point: CGPoint(x: 0.5, y: 0.5))], radius: 0.05)
        XCTAssertThrowsError(try RetouchWireRefiner.refine(
            region: circle, in: proxy, sourceWidth: 64, sourceHeight: 48
        )) { XCTAssertEqual($0 as? RetouchWireRefiner.Failure, .invalidInput) }
    }

    func testKRMA658WireFixturesReportAcceptedAndImprovedCases() throws {
        var accepted = 0, improved = 0, rejected = 0
        var beforeTotal = 0.0, afterTotal = 0.0
        for background in RetouchQualityFixtures.backgrounds {
            for defect in ["wire straight", "wire sagging edge"] {
                let fixture = RetouchQualityFixtures.make(background: background, defect: defect)
                let bytes = try Pixels.bytes(of: fixture.damaged)
                let proxy = RetouchAnalysisProxy.fromRGBA8(Data(bytes), width: fixture.width, height: fixture.height)
                let rough = fixture.stroke.map { BrushSample(point: CGPoint(x: $0.x, y: $0.y + 4 / CGFloat(fixture.height))) }
                let region = RetouchRegion(samples: rough, radius: 12 / Double(min(fixture.width, fixture.height)))
                let before = meanDistance(rough.map(\.point), to: fixture.stroke, width: fixture.width, height: fixture.height)
                do {
                    let proposal = try RetouchWireRefiner.refine(region: region, in: proxy,
                        sourceWidth: fixture.width, sourceHeight: fixture.height)
                    accepted += 1
                    let after = meanDistance(proposal.region.samples.map(\.point), to: fixture.stroke,
                                             width: fixture.width, height: fixture.height)
                    beforeTotal += before; afterTotal += after
                    if after < before { improved += 1 }
                } catch RetouchWireRefiner.Failure.ambiguous { rejected += 1 }
            }
        }
        print(String(format: "KRMA-658 wire refinement: accepted %d/12, improved %d/%d; centerline error %.2fpx → %.2fpx, rejected ambiguous %d/12",
                     accepted, improved, accepted, beforeTotal / Double(max(1, accepted)),
                     afterTotal / Double(max(1, accepted)), rejected))
        XCTAssertGreaterThan(improved, 0)
        XCTAssertEqual(accepted + rejected, 12)
    }

    private func roughRegion(_ points: [(Double, Double)], width: Int, height: Int, radius: Double) -> RetouchRegion {
        RetouchRegion(samples: points.map { BrushSample(point: CGPoint(x: $0.0 / Double(width), y: $0.1 / Double(height))) },
                      radius: radius / Double(min(width, height)))
    }

    private func image(width: Int, height: Int, pixel: (Int, Int) -> SIMD3<Float>) -> RetouchAnalysisProxy {
        RetouchAnalysisProxy(width: width, height: height,
                             pixels: (0..<height).flatMap { y in (0..<width).map { x in pixel(x, y) } })
    }

    private func meanDistance(_ points: [CGPoint], to path: [CGPoint], width: Int, height: Int) -> Double {
        func segmentDistance(_ point: CGPoint, _ a: CGPoint, _ b: CGPoint) -> Double {
            let px = point.x * Double(width), py = point.y * Double(height)
            let ax = a.x * Double(width), ay = a.y * Double(height)
            let bx = b.x * Double(width), by = b.y * Double(height)
            let dx = bx - ax, dy = by - ay
            let length = max(0.00001, dx * dx + dy * dy)
            let t = min(1, max(0, ((px - ax) * dx + (py - ay) * dy) / length))
            return hypot(px - ax - t * dx, py - ay - t * dy)
        }
        return points.map { point in
            zip(path, path.dropFirst()).map { segmentDistance(point, $0.0, $0.1) }.min() ?? .infinity
        }.reduce(0, +) / Double(max(1, points.count))
    }
}

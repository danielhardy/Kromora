import CoreGraphics
import XCTest
@testable import KromoraKit

final class RetouchSourcePickerTests: XCTestCase {
    func testCandidatesAreDeterministicAndDoNotOverlapDestinationOrOtherSpots() throws {
        let proxy = makeProxy(width: 96, height: 72)
        let spot = makeSpot(x: 0.5, y: 0.5, radius: 0.07)
        let other = makeSpot(x: 0.22, y: 0.22, radius: 0.06)
        let first = RetouchSourcePicker.candidates(for: spot, among: [spot, other], in: proxy)
        let second = RetouchSourcePicker.candidates(for: spot, among: [spot, other], in: proxy)
        XCTAssertEqual(first, second)
        XCTAssertFalse(first.isEmpty)
        for candidate in first {
            let x = 0.5 + candidate.offset.dx
            let y = 0.5 - candidate.offset.dy
            XCTAssertGreaterThanOrEqual(x, 0.07)
            XCTAssertLessThanOrEqual(x, 0.93)
            XCTAssertGreaterThanOrEqual(y, 0.09)
            XCTAssertLessThanOrEqual(y, 0.91)
            let dx = abs((x - 0.5) * 96), dy = abs((y - 0.5) * 72)
            XCTAssertTrue(dx > 7 || dy > 7)
            let otherDX = abs((x - 0.22) * 96), otherDY = abs((y - 0.22) * 72)
            XCTAssertTrue(otherDX > 14 || otherDY > 14, "candidate (\(x), \(y)) overlaps secondary hole by (\(otherDX), \(otherDY)) px")
        }
    }

    func testRankAdvancesToNextDeterministicSource() throws {
        let proxy = makeProxy(width: 96, height: 72)
        let spot = makeSpot(x: 0.5, y: 0.5, radius: 0.04)
        let choices = RetouchSourcePicker.candidates(for: spot, among: [spot], in: proxy)
        XCTAssertGreaterThanOrEqual(choices.count, 2)
        XCTAssertEqual(RetouchSourcePicker.source(for: spot, among: [spot], in: proxy, rank: 0),
                       .auto(offset: choices[0].offset, rank: 0))
        XCTAssertEqual(RetouchSourcePicker.source(for: spot, among: [spot], in: proxy, rank: 1),
                       .auto(offset: choices[1].offset, rank: 1))
        XCTAssertNotEqual(choices[0].offset, choices[1].offset)
    }

    func testManualSourceIsAuthoritativeWhenAdvancingAutomaticRank() {
        let proxy = makeProxy(width: 96, height: 72)
        let manual = RetouchSource.manual(offset: CGVector(dx: 0.12, dy: -0.08))
        let spot = RetouchSpot(mode: .heal, source: manual)
        XCTAssertEqual(RetouchSourcePicker.resolving(spot, among: [spot], in: proxy, rank: 5), spot)
    }

    func testProxyConvertsRGBAIntoLabValues() {
        let proxy = RetouchAnalysisProxy.fromRGBA8(Data([255, 0, 0, 255, 0, 255, 0, 255]), width: 2, height: 1)
        XCTAssertTrue(proxy.isUsable)
        XCTAssertNotEqual(try XCTUnwrap(proxy.lab(x: 0, y: 0)).x, try XCTUnwrap(proxy.lab(x: 1, y: 0)).x)
    }

    func testTypicalProxySelectionLatencyDiagnostic() {
        let proxy = makeProxy(width: 1024, height: 768)
        let spot = makeSpot(x: 0.5, y: 0.5, radius: 0.02)
        let start = Date()
        _ = RetouchSourcePicker.candidates(for: spot, among: [spot], in: proxy)
        print(String(format: "Retouch source picker: %.2f ms for 1024×768 Lab proxy",
                     Date().timeIntervalSince(start) * 1000))
    }

    func testFullResolutionRefinementIsStableAndBoundedToTwoPixels() {
        let spot = makeSpot(x: 0.5, y: 0.5, radius: 0.04)
        let coarse = RetouchSourcePicker.candidates(for: spot, among: [spot], in: makeProxy(width: 96, height: 72))
        let highResolution = RetouchAnalysisRegion(
            sourceWidth: 256, sourceHeight: 192, originX: 0, originY: 0,
            proxy: makeProxy(width: 256, height: 192)
        )
        let first = RetouchSourcePicker.refining(coarse, for: spot, among: [spot], in: highResolution)
        let second = RetouchSourcePicker.refining(coarse, for: spot, among: [spot], in: highResolution)
        XCTAssertEqual(first, second)
        XCTAssertFalse(first.isEmpty)
        for refined in first {
            let delta = coarse.map { candidate in
                (abs(Double((refined.offset.dx - candidate.offset.dx) * 256)),
                 abs(Double((refined.offset.dy - candidate.offset.dy) * 192)))
            }.min { hypot($0.0, $0.1) < hypot($1.0, $1.1) } ?? (.infinity, .infinity)
            // Include the ≤0.5 px rounding when mapping normalized proxy points to full resolution.
            XCTAssertLessThanOrEqual(delta.0, 2.51)
            XCTAssertLessThanOrEqual(delta.1, 2.51)
        }
    }

    /// KRMA-1062: a hair spanning most of the frame used to leave no candidate because the whole
    /// stroke bounding box was excluded. Placements must clear the stroke's path, not its box.
    func testLongStrokeKeepsCandidatesThatClearItsPathAndOtherSpots() throws {
        let proxy = makeProxy(width: 96, height: 72)
        let hair = makeStroke(from: CGPoint(x: 0.2, y: 0.3), to: CGPoint(x: 0.8, y: 0.45), radius: 0.03)
        let other = makeSpot(x: 0.5, y: 0.85, radius: 0.04)
        let first = RetouchSourcePicker.candidates(for: hair, among: [hair, other], in: proxy)
        XCTAssertFalse(first.isEmpty, "a long hair must still find clean sources")
        XCTAssertEqual(first, RetouchSourcePicker.candidates(for: hair, among: [hair, other], in: proxy))
        let radius = 0.03 * 72
        for candidate in first {
            // Every translated path point stays clear of the original path and the other spot.
            for t in stride(from: 0.0, through: 1.0, by: 0.05) {
                let x = (0.2 + 0.6 * t) * 96, y = (0.3 + 0.15 * t) * 72
                let moved = CGPoint(x: x + candidate.offset.dx * 96, y: y - candidate.offset.dy * 72)
                for u in stride(from: 0.0, through: 1.0, by: 0.01) {
                    let px = (0.2 + 0.6 * u) * 96, py = (0.3 + 0.15 * u) * 72
                    XCTAssertGreaterThan(hypot(moved.x - px, moved.y - py), radius * 1.4,
                                         "source crosses the destination stroke")
                }
                XCTAssertTrue(abs(moved.x - 0.5 * 96) > radius || abs(moved.y - 0.85 * 72) > radius,
                              "source lands on the other spot")
            }
        }
    }

    func testSnappedOffsetsAreWholeSourcePixelsAndScaleWithSourceSize() {
        let raw = [RetouchSourceCandidate(offset: CGVector(dx: -0.0253, dy: 0.1037), score: 1)]
        for (w, h) in [(6000, 4000), (1800, 1200)] {
            let snapped = RetouchSourcePicker.snapped(raw, sourceWidth: w, sourceHeight: h)
            let dx = snapped[0].offset.dx * CGFloat(w), dy = snapped[0].offset.dy * CGFloat(h)
            XCTAssertEqual(dx, dx.rounded(), accuracy: 1e-6)
            XCTAssertEqual(dy, dy.rounded(), accuracy: 1e-6)
            XCTAssertLessThanOrEqual(abs(snapped[0].offset.dx - raw[0].offset.dx), 0.5 / CGFloat(w) + 1e-9)
        }
    }

    private func makeStroke(from a: CGPoint, to b: CGPoint, radius: Double) -> RetouchSpot {
        let samples = (0...12).map { i -> BrushSample in
            let t = CGFloat(i) / 12
            return BrushSample(point: CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
        }
        return RetouchSpot(mode: .heal, region: RetouchRegion(samples: samples, radius: radius))
    }

    private func makeSpot(x: CGFloat, y: CGFloat, radius: Double) -> RetouchSpot {
        RetouchSpot(mode: .heal,
                    region: RetouchRegion(samples: [BrushSample(point: CGPoint(x: x, y: y))], radius: radius))
    }

    private func makeProxy(width: Int, height: Int) -> RetouchAnalysisProxy {
        let pixels = (0..<height).flatMap { y in (0..<width).map { x in
            let value = Float((x * 7 + y * 11) % 40)
            return SIMD3(value, Float((x * 3) % 17), Float((y * 5) % 23))
        } }
        return RetouchAnalysisProxy(width: width, height: height, pixels: pixels)
    }
}

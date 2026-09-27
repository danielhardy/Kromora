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

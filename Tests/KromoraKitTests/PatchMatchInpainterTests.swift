import Foundation
import XCTest
@testable import KromoraKit

final class PatchMatchInpainterTests: XCTestCase {
    func testDeterministicFieldAndAllSourcesStayOutsideHolesAndInBounds() throws {
        let width = 40, height = 32
        let image = PatchMatchInpainter.Image(width: width, height: height, lab: (0..<(width * height)).map {
            let x = Float($0 % width), y = Float($0 / width)
            return SIMD3(x / 40, y / 32, (x + y) / 72)
        })
        var hole = [UInt8](repeating: 0, count: width * height)
        var excluded = [UInt8](repeating: 0, count: width * height)
        for y in 13...17 { for x in 17...21 { hole[y * width + x] = 1 } }
        for y in 3...7 { for x in 4...8 { excluded[y * width + x] = 1 } }
        let input = PatchMatchInpainter.Input(image: image, holeMask: hole, exclusionMask: excluded,
                                               seed: 1234, initialOffset: SIMD2(0, -10))
        let first = try PatchMatchInpainter.solve(input)
        let second = try PatchMatchInpainter.solve(input)
        XCTAssertEqual(first.rg32f, second.rg32f)
        XCTAssertEqual(first.coordinates, second.coordinates)
        for y in 0..<first.height { for x in 0..<first.width {
            guard let p = first[x + first.x, y + first.y], p.x >= 0 else { continue }
            let sx = Int(p.x), sy = Int(p.y)
            XCTAssertGreaterThanOrEqual(sx, 2); XCTAssertGreaterThanOrEqual(sy, 2)
            XCTAssertLessThan(sx + 2, width); XCTAssertLessThan(sy + 2, height)
            for py in (sy - 2)...(sy + 2) { for px in (sx - 2)...(sx + 2) {
                XCTAssertEqual(hole[py * width + px], 0, "field source overlaps destination hole")
                XCTAssertEqual(excluded[py * width + px], 0, "field source overlaps excluded hole")
            } }
        } }
    }

    func testThinHoleChoosesFivePixelPatches() {
        var thin = [UInt8](repeating: 0, count: 20 * 20)
        for x in 3...16 { thin[10 * 20 + x] = 1 }
        XCTAssertEqual(PatchMatchInpainter.patchSize(for: thin, width: 20, height: 20), 5)
        for y in 7...13 { for x in 7...13 { thin[y * 20 + x] = 1 } }
        XCTAssertEqual(PatchMatchInpainter.patchSize(for: thin, width: 20, height: 20), 7)
    }

    func testCancellationReturnsNoPartialField() {
        let image = PatchMatchInpainter.Image(width: 32, height: 32,
            lab: Array(repeating: SIMD3<Float>(0.5, 0, 0), count: 32 * 32))
        var hole = [UInt8](repeating: 0, count: 32 * 32)
        for y in 10...20 { for x in 10...20 { hole[y * 32 + x] = 1 } }
        let input = PatchMatchInpainter.Input(image: image, holeMask: hole,
            exclusionMask: [UInt8](repeating: 0, count: 32 * 32), seed: 7, initialOffset: SIMD2(0, 0),
            isCancelled: { true })
        XCTAssertThrowsError(try PatchMatchInpainter.solve(input)) { error in
            XCTAssertEqual(error as? PatchMatchInpainter.SolverError, .cancelled)
        }
    }

}

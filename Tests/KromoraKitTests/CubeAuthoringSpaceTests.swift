import XCTest
import CoreImage
@testable import KromoraKit

/// The authoring-space stamp: header syntax, error cases, round trips, and that the stamp, not the
/// export target, selects the interpolation space (KRMA-1117, ADR-KRMA-1115 Decision 2).
final class CubeAuthoringSpaceTests: TempDirectoryTestCase {

    private func cubeText(header: [String], size: Int = 2) -> String {
        let identity = Fixtures.identityCubeText(size: size)
        return header.joined(separator: "\n") + (header.isEmpty ? "" : "\n") + identity
    }

    private func parse(_ text: String, name: String = "lut.cube") throws -> CubeLUT {
        try CubeLUT(url: Fixtures.writeCube(text, named: name, in: tempDirectory))
    }

    // MARK: - Header

    func testMissingHeaderMeansSRGB() throws {
        XCTAssertEqual(try parse(cubeText(header: [])).authoringSpace, .sRGB)
    }

    func testHeaderStampsEachRecognizedSpace() throws {
        for space in WorkingSpace.allCases {
            let lut = try parse(cubeText(header: [CubeLUT.authoringSpaceHeader(space)]), name: "\(space).cube")
            XCTAssertEqual(lut.authoringSpace, space)
        }
    }

    func testHeaderSyntaxIsDocumented() {
        XCTAssertEqual(CubeLUT.authoringSpaceHeader(.displayP3), "# KROMORA_AUTHORING_SPACE: displayP3")
        XCTAssertEqual(CubeLUT.authoringSpaceHeader(.sRGB), "# KROMORA_AUTHORING_SPACE: sRGB")
    }

    func testUnknownOrMalformedDeclarationsFail() {
        let bad = [
            "# KROMORA_AUTHORING_SPACE: rec2020",
            "# KROMORA_AUTHORING_SPACE:",
            "# KROMORA_AUTHORING_SPACE displayP3",
            "# KROMORA_AUTHORING_SPACE_X: sRGB",
            "# KROMORA_AUTHORING_SPACE: displayp3",
        ]
        for (index, line) in bad.enumerated() {
            XCTAssertThrowsError(try parse(cubeText(header: [line]), name: "bad\(index).cube"), line) {
                XCTAssertTrue($0 is LUTError, line)
            }
        }
    }

    func testDuplicateAndLateDeclarationsFail() {
        let one = CubeLUT.authoringSpaceHeader(.sRGB)
        let two = CubeLUT.authoringSpaceHeader(.displayP3)
        XCTAssertThrowsError(try parse(cubeText(header: [one, two]), name: "dup.cube"))
        XCTAssertThrowsError(try parse(cubeText(header: [one, one]), name: "dup2.cube"))
        XCTAssertThrowsError(try parse(cubeText(header: []) + two + "\n", name: "late.cube"))
    }

    func testUnrelatedCommentsAreStillIgnored() throws {
        let lut = try parse(cubeText(header: ["# authoring space: whatever", "# kromora_authoring_space: nope"]))
        XCTAssertEqual(lut.authoringSpace, .sRGB)
    }

    // MARK: - Identity and application

    func testAuthoringSpaceIsPartOfIdentity() {
        let srgb = TestImages.warmLUT(authoringSpace: .sRGB)
        let p3 = TestImages.warmLUT(authoringSpace: .displayP3)
        XCTAssertNotEqual(srgb.contentHash, p3.contentHash)
        XCTAssertNotEqual(srgb.id, p3.id, "the same numbers in another space are another derived Look")
        XCTAssertNotEqual(srgb.cacheFingerprint, p3.cacheFingerprint)
    }

    func testFilterInterpolatesInTheAuthoringSpaceNotTheTarget() throws {
        for space in WorkingSpace.allCases {
            let filter = try XCTUnwrap(TestImages.warmLUT(authoringSpace: space).makeFilter())
            let cgSpace = filter.value(forKey: "inputColorSpace") as! CGColorSpace
            XCTAssertEqual(cgSpace.name, space.cgColorSpace.name)
        }
    }

    func testUnstampedImportKeepsSRGBInterpretationUnderEitherTarget() throws {
        // A non-identity table so interpolation space is visible.
        let table = TestImages.warmLUT(size: 4).tableFloats.chunked3()
        func text(_ header: [String]) -> String {
            let body = CubeLUT.cubeFileContents(cube: table, size: 4, title: "t")
                .split(separator: "\n", omittingEmptySubsequences: false)
                .filter { !$0.hasPrefix("# KROMORA") }.joined(separator: "\n")
            return header.isEmpty ? body : header.joined(separator: "\n") + "\n" + body
        }
        let unstamped = try parse(text([]), name: "u.cube")
        let stampedSRGB = try parse(text([CubeLUT.authoringSpaceHeader(.sRGB)]), name: "s.cube")
        let stampedP3 = try parse(text([CubeLUT.authoringSpaceHeader(.displayP3)]), name: "p.cube")
        XCTAssertEqual(unstamped.authoringSpace, .sRGB)

        let source = try TestImages.gradient(width: 16, height: 16)
        for target in WorkingSpace.allCases {
            let a = try Pixels.bytes(of: XCTUnwrap(unstamped.apply(to: source)), space: target)
            let b = try Pixels.bytes(of: XCTUnwrap(stampedSRGB.apply(to: source)), space: target)
            let c = try Pixels.bytes(of: XCTUnwrap(stampedP3.apply(to: source)), space: target)
            XCTAssertEqual(a, b, "unstamped is sRGB when rendering to \(target)")
            assertPixelsDiffer(a, c, "a P3 stamp must change the interpretation under \(target)")
        }
    }

    // MARK: - Write / load round trips

    func testWriteThenParsePreservesTheStampAndBytes() throws {
        let cube = TestImages.warmLUT(size: 3).tableFloats.chunked3()
        for space in WorkingSpace.allCases {
            let url = tempDirectory.appendingPathComponent("rt-\(space.rawValue).cube")
            try CubeLUT.write(cube: cube, size: 3, title: "rt", authoringSpace: space, to: url)
            let parsed = try CubeLUT(url: url)
            XCTAssertEqual(parsed.authoringSpace, space)
            // Embedding copies bytes verbatim, so the header survives and the hash matches.
            let bytes = try Data(contentsOf: url)
            XCTAssertEqual(parsed.contentHash, PortablePackageLookReference(data: bytes).contentHash)
            XCTAssertTrue(String(decoding: bytes, as: UTF8.self).contains(CubeLUT.authoringSpaceHeader(space)))
        }
    }

    func testImportedFileIsNotRewritten() throws {
        let url = try Fixtures.writeCube(cubeText(header: []), named: "untouched.cube", in: tempDirectory)
        let before = try Data(contentsOf: url)
        _ = try CubeLUT(url: url)
        XCTAssertEqual(try Data(contentsOf: url), before)
    }
}

private extension Array where Element == Float {
    /// RGBA float table → RGB triples.
    func chunked3() -> [SIMD3<Float>] {
        stride(from: 0, to: count, by: 4).map { SIMD3(self[$0], self[$0 + 1], self[$0 + 2]) }
    }
}

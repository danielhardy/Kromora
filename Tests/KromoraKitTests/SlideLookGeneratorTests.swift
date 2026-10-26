import XCTest
@testable import KromoraKit

/// Unit tests for the slide Look generator (KRMA-1103). Structural checks only: there is no
/// reference to match, so nothing compares against a camera or a tolerance on the parameter table.
final class SlideLookGeneratorTests: XCTestCase {
    private typealias RGB = SlideLookGenerator.RGB

    private func generator(
        _ parameters: SlideLookParameters = .cleanSlide,
        space: WorkingSpace = .displayP3,
        encoding: SlideLookEncoding = .sRGBTransfer
    ) -> SlideLookGenerator {
        SlideLookGenerator(parameters: parameters, space: space, encoding: encoding)
    }

    private var cleanSlideURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/KromoraKit/Resources/StarterLooks/clean-slide.cube")
    }

    static let cleanSlideTitle = "Clean Slide"
    static let cleanSlideProvenance =
        "Original Kromora Look: Clean Slide. Best-guess approximation of a described neutral slide character; no camera profile or reference data."

    // MARK: Output

    func testCubeIs33CubedAndByteForByteReproducible() throws {
        let a = generator().cubeText(title: "T", provenance: "P")
        let b = generator().cubeText(title: "T", provenance: "P")
        XCTAssertEqual(a, b)
        let rows = a.split(separator: "\n").filter { !$0.hasPrefix("#") && !$0.hasPrefix("TITLE") && !$0.hasPrefix("LUT_3D_SIZE") }
        XCTAssertEqual(rows.count, 33 * 33 * 33)
        XCTAssertTrue(a.contains("LUT_3D_SIZE 33\n"))
    }

    func testCubeRowsUseLocaleIndependentDecimalFormatting() {
        XCTAssertEqual(
            SlideLookGenerator.formattedCubeRow(RGB(0.25, 0.5, 1)),
            "0.250000 0.500000 1.000000"
        )
    }

    func testHeaderStampsAuthoringSpaceAndEncodingAndParses() throws {
        for (space, encoding) in [(WorkingSpace.displayP3, SlideLookEncoding.sRGBTransfer),
                                  (.sRGB, .sRGBTransfer)] {
            let text = generator(space: space, encoding: encoding).cubeText(title: "T", provenance: "P")
            XCTAssertTrue(text.contains("# KROMORA_AUTHORING_SPACE: \(space.rawValue)\n"))
            XCTAssertTrue(text.contains("# KROMORA_ENCODING: \(encoding.rawValue)\n"))
            let url = try Fixtures.writeCube(text, named: "t.cube", in: FileManager.default.temporaryDirectory)
            defer { try? FileManager.default.removeItem(at: url) }
            let lut = try CubeLUT(url: url, source: .user)
            XCTAssertEqual(lut.size, 33)
            XCTAssertEqual(lut.authoringSpace, space)
        }
    }

    func testHLGEncodedCubeIsRejectedBeforeItCanRenderWithTheWrongTransfer() throws {
        let hlgGenerator = generator(space: .displayP3, encoding: .hlg)
        let input = RGB(0.7, 0.35, 0.25)
        let generatedColor = hlgGenerator.evaluate(input)
        XCTAssertGreaterThan(
            abs(generatedColor.x - input.x) + abs(generatedColor.y - input.y) + abs(generatedColor.z - input.z),
            0.01,
            "the HLG chart must contain a non-neutral Look before runtime rejection is checked"
        )

        let text = hlgGenerator.cubeText(title: "T", provenance: "P")
        XCTAssertTrue(text.contains("# KROMORA_ENCODING: hlg\n"))
        let url = try Fixtures.writeCube(text, named: "hlg.cube", in: FileManager.default.temporaryDirectory)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertThrowsError(try CubeLUT(url: url, source: .user)) { error in
            guard case LUTError.unsupported(let message) = error else {
                return XCTFail("expected unsupported, got \(error)")
            }
            XCTAssertTrue(message.contains("hlg"))
        }
    }

    func testMalformedEncodingHeaderCannotFallBackToSRGBTransfer() throws {
        let text = generator().cubeText(title: "T", provenance: "P")
            .replacingOccurrences(
                of: "# KROMORA_ENCODING: sRGBTransfer",
                with: "# KROMORA_ENCODING hlg"
            )
        let url = try Fixtures.writeCube(text, named: "malformed-encoding.cube", in: FileManager.default.temporaryDirectory)
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertThrowsError(try CubeLUT(url: url, source: .user)) { error in
            guard case LUTError.invalidFormat(let message) = error else {
                return XCTFail("expected malformed encoding declaration, got \(error)")
            }
            XCTAssertTrue(message.contains("KROMORA_ENCODING"))
        }
    }

    func testBundledCleanSlideMatchesTheGenerator() throws {
        let expected = generator().cubeText(title: Self.cleanSlideTitle, provenance: Self.cleanSlideProvenance)
        if ProcessInfo.processInfo.environment["KROMORA_WRITE_SLIDE_LOOKS"] == "1" {
            try expected.write(to: cleanSlideURL, atomically: true, encoding: .utf8)
        }
        XCTAssertEqual(try String(contentsOf: cleanSlideURL, encoding: .utf8), expected,
                       "clean-slide.cube is stale; run with KROMORA_WRITE_SLIDE_LOOKS=1")
    }

    // MARK: Tone, neutrals

    func testToneCurveIsStrictlyMonotonicAndKeepsEndpoints() {
        let curves: [SlideLookParameters.ToneCurve] = [
            .init(toe: 0, slope: 1, shoulder: 0), .init(toe: 0, slope: 1.12, shoulder: 0.12),
            .init(toe: 0.25, slope: 1.5, shoulder: 0.9), .init(toe: 0.1, slope: 1.3, shoulder: 0.5),
        ]
        for curve in curves {
            var p = SlideLookParameters(); p.toneCurve = curve
            let g = generator(p)
            var previous = -1.0
            for i in 0...1000 {
                let y = g.tone(Double(i) / 1000)
                XCTAssertGreaterThan(y, previous, "\(curve) not strictly increasing at \(i)")
                previous = y
            }
            XCTAssertEqual(g.tone(0), min(max(curve.toe, 0), 0.25), accuracy: 1e-12)
            XCTAssertEqual(g.tone(1), 1, accuracy: 1e-12)
            XCTAssertEqual(g.tone(0.5), 0.5, accuracy: 1e-12, "mid gray is exposure neutral")
        }
    }

    func testGrayRampIsNeutralAndDoesNotClip() {
        for encoding in SlideLookEncoding.allCases {
            let g = generator(encoding: encoding)
            var previous = -1.0
            for i in 0...32 {
                let v = Double(i) / 32
                let out = g.evaluate(RGB(repeating: v))
                XCTAssertEqual(out.x, out.y, accuracy: 1e-9)
                XCTAssertEqual(out.y, out.z, accuracy: 1e-9)
                XCTAssertGreaterThan(out.x, previous, "ramp step \(i) clipped or collapsed (\(encoding))")
                previous = out.x
            }
        }
    }

    func testEncodingRoundTrips() {
        for encoding in SlideLookEncoding.allCases {
            for i in 1...100 {
                let l = Double(i) / 100
                XCTAssertEqual(encoding.decode(encoding.encode(l)), l, accuracy: 1e-9)
            }
        }
    }

    func testIdentityParametersProduceIdentityCube() {
        let g = generator(SlideLookParameters())
        for v in [RGB(0.2, 0.5, 0.8), RGB(0.9, 0.1, 0.3), RGB(0, 1, 0.4)] {
            let out = g.evaluate(v)
            XCTAssertEqual(out.x, v.x, accuracy: 1e-9); XCTAssertEqual(out.y, v.y, accuracy: 1e-9)
            XCTAssertEqual(out.z, v.z, accuracy: 1e-9)
        }
    }

    // MARK: Hue sectors

    func testHueSectorsInterpolateSmoothlyAndPeriodically() {
        var p = SlideLookParameters()
        p.hueSectors[4] = .init(saturation: 1.5, hueShift: 10)   // green center, 120 degrees
        let g = generator(p)
        XCTAssertEqual(g.sectorValue(hue: 120, \.saturation), 1.5, accuracy: 1e-12)
        XCTAssertEqual(g.sectorValue(hue: 90, \.saturation), 1, accuracy: 1e-12)
        XCTAssertEqual(g.sectorValue(hue: 150, \.hueShift), 0, accuracy: 1e-12)
        let mid = g.sectorValue(hue: 105, \.saturation)
        XCTAssertEqual(mid, 1.25, accuracy: 1e-12, "smoothstep midpoint")
        // Periodic and continuous across the 360/0 seam.
        XCTAssertEqual(g.sectorValue(hue: -30, \.hueShift), g.sectorValue(hue: 330, \.hueShift), accuracy: 1e-12)
        var previous = g.sectorValue(hue: 0, \.saturation)
        for i in 1...3600 {
            let value = g.sectorValue(hue: Double(i) / 10, \.saturation)
            XCTAssertLessThan(abs(value - previous), 0.01)
            previous = value
        }
    }

    func testSectorSaturationAndHueShiftAffectOnlyThatHue() {
        var p = SlideLookParameters()
        p.hueSectors[4] = .init(saturation: 1.4, hueShift: 0)
        let g = generator(p)
        let green = RGB(0.3, 0.6, 0.3), red = RGB(0.6, 0.3, 0.3)
        func chroma(_ c: RGB) -> Double { max(c.x, c.y, c.z) - min(c.x, c.y, c.z) }
        XCTAssertGreaterThan(chroma(g.evaluate(green)), chroma(green) * 1.3)
        XCTAssertEqual(chroma(g.evaluate(red)), chroma(red), accuracy: 1e-9)

        p.hueSectors[4] = .init(saturation: 1, hueShift: 20)
        let shifted = generator(p).evaluate(green)
        XCTAssertGreaterThan(abs(SlideLookGenerator.hue(of: shifted - RGB(repeating: (shifted.x + shifted.y + shifted.z) / 3))
                                 - SlideLookGenerator.hue(of: green - RGB(repeating: 0.4))), 15)
    }

    func testGlobalSaturationScalesChromaAndKeepsLuma() {
        var p = SlideLookParameters(); p.globalSaturation = 0.5
        let g = generator(p)
        let c = RGB(0.7, 0.4, 0.2)
        let out = g.evaluate(c)
        XCTAssertEqual((out * g.lumaWeights).sum(), (c * g.lumaWeights).sum(), accuracy: 1e-9)
        XCTAssertEqual(out.x - out.z, (c.x - c.z) * 0.5, accuracy: 1e-9)
    }

    // MARK: chromeDepth, tints, skinGuard

    func testChromeDepthDarkensSaturatedWarmAndBlueButNotNeutralsOrGreen() {
        var p = SlideLookParameters(); p.chromeDepth = .init(warm: 0.4, blue: 0.4)
        let g = generator(p)
        func luma(_ c: RGB) -> Double { (c * g.lumaWeights).sum() }
        let red = RGB(0.9, 0.1, 0.1), blue = RGB(0.1, 0.2, 0.9), green = RGB(0.1, 0.8, 0.2)
        XCTAssertLessThan(luma(g.evaluate(red)), luma(red) - 0.03)
        XCTAssertLessThan(luma(g.evaluate(blue)), luma(blue) - 0.03)
        XCTAssertEqual(luma(g.evaluate(green)), luma(green), accuracy: 1e-9)
        // Proportional to saturation: a weakly saturated red moves less.
        let pale = RGB(0.55, 0.5, 0.5)
        XCTAssertLessThan(luma(red) - luma(g.evaluate(red)), 1)
        XCTAssertLessThan(luma(pale) - luma(g.evaluate(pale)), (luma(red) - luma(g.evaluate(red))) / 4)
        let gray = RGB(repeating: 0.5)
        XCTAssertEqual(g.evaluate(gray).x, 0.5, accuracy: 1e-12)
    }

    func testTintsAffectShadowsAndHighlightsRespectivelyAndPreserveLuma() {
        var p = SlideLookParameters()
        p.shadowTint = .init(hue: 210, amount: 0.08)     // cool-blue shadows
        p.highlightTint = .init(hue: 40, amount: 0.08)   // warm highlights
        let g = generator(p)
        let dark = g.evaluate(RGB(repeating: 0.1)), light = g.evaluate(RGB(repeating: 0.9))
        XCTAssertGreaterThan(dark.z, dark.x)
        XCTAssertGreaterThan(light.x, light.z)
        XCTAssertEqual((dark * g.lumaWeights).sum(), 0.1, accuracy: 1e-9)
        XCTAssertEqual((light * g.lumaWeights).sum(), 0.9, accuracy: 1e-9)
        let mid = g.evaluate(RGB(repeating: 0.5))
        XCTAssertLessThan(abs(mid.x - mid.z), min(abs(dark.x - dark.z), abs(light.x - light.z)))
    }

    func testSkinGuardLimitsChangeInSkinHueOnly() {
        var p = SlideLookParameters()
        p.globalSaturation = 1.5
        let skin = RGB(0.75, 0.55, 0.45), green = RGB(0.3, 0.6, 0.3)
        func chroma(_ c: RGB) -> Double { max(c.x, c.y, c.z) - min(c.x, c.y, c.z) }
        let unguarded = generator(p)
        p.skinGuard = 1
        let guarded = generator(p)
        let skinGain = { (g: SlideLookGenerator) in chroma(g.evaluate(skin)) / chroma(skin) }
        XCTAssertGreaterThan(skinGain(unguarded), 1.4)
        XCTAssertEqual(skinGain(guarded), 1, accuracy: 0.02)
        XCTAssertEqual(chroma(guarded.evaluate(green)), chroma(unguarded.evaluate(green)), accuracy: 1e-9)
    }

    func testFamilyOrderingByGlobalSaturation() {
        var vivid = SlideLookParameters.cleanSlide; vivid.globalSaturation = 1.35
        let color = RGB(0.2, 0.5, 0.8)
        func chroma(_ c: RGB) -> Double { max(c.x, c.y, c.z) - min(c.x, c.y, c.z) }
        XCTAssertGreaterThan(chroma(generator(vivid).evaluate(color)), chroma(generator().evaluate(color)))
    }
}

final class SlideLookManifestTests: XCTestCase {
    func testCleanSlideShipsWithP3ProvenanceAndNoTrademarkedNames() throws {
        let manifest = try BundledLookLibrary.validate()
        let entry = try XCTUnwrap(manifest.looks.first { $0.id == "kromora.starter.clean-slide" })
        XCTAssertEqual(entry.name, "Clean Slide")
        XCTAssertEqual(entry.category, "Slide")
        XCTAssertEqual(entry.approval.status, "approved")
        XCTAssertTrue(entry.approval.notes.contains("KROMORA_AUTHORING_SPACE: displayP3"))
        XCTAssertTrue(entry.approval.notes.contains("KROMORA_ENCODING: sRGBTransfer"))
        XCTAssertTrue(entry.approval.notes.contains("RenderPipeline"))

        let look = try XCTUnwrap(BundledLookLibrary.load().looks.first { $0.id == entry.id })
        XCTAssertEqual(look.size, 33)
        XCTAssertEqual(look.authoringSpace, .displayP3)
        let banned = ["fuji", "provia", "velvia", "astia", "classic chrome", "superia", "eterna", "acros", "kodachrome"]
        let fields = [entry.id, entry.name, entry.category, entry.source, entry.approval.notes, entry.resource]
        for field in fields {
            for name in banned { XCTAssertFalse(field.localizedCaseInsensitiveContains(name), "\(field) mentions \(name)") }
        }
    }
}

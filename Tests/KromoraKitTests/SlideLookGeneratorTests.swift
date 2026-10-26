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
        try assertBundledCubeMatches(.cleanSlide, name: "clean-slide", title: Self.cleanSlideTitle, provenance: Self.cleanSlideProvenance)
    }

    func testBundledVividSlideMatchesTheGenerator() throws {
        try assertBundledCubeMatches(.vividSlide, name: "vivid-slide", title: "Vivid Slide",
            provenance: "Original Kromora Look: Vivid Slide. Best-guess approximation of a described high-saturation slide character; no camera profile or reference data.")
    }

    func testBundledSoftSlideMatchesTheGenerator() throws {
        try assertBundledCubeMatches(.softSlide, name: "soft-slide", title: "Soft Slide",
            provenance: "Original Kromora Look: Soft Slide. Best-guess approximation of a described soft slide character; no camera profile or reference data.")
    }

    private func assertBundledCubeMatches(
        _ parameters: SlideLookParameters, name: String, title: String, provenance: String
    ) throws {
        let url = cleanSlideURL.deletingLastPathComponent().appendingPathComponent("\(name).cube")
        let expected = generator(parameters).cubeText(title: title, provenance: provenance)
        if ProcessInfo.processInfo.environment["KROMORA_WRITE_SLIDE_LOOKS"] == "1" {
            try expected.write(to: url, atomically: true, encoding: .utf8)
        }
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), expected,
                       "\(name).cube is stale; run with KROMORA_WRITE_SLIDE_LOOKS=1")
    }

    func testBundledFieldReportMatchesTheGenerator() throws {
        try assertBundledCubeMatches(.fieldReport, name: "field-report", title: "Field Report",
            provenance: "Original Kromora Look: Field Report. Best-guess approximation of a described documentary character; no camera profile or reference data.")
    }

    func testBundledCineFlatMatchesTheGenerator() throws {
        try assertBundledCubeMatches(.cineFlat, name: "cine-flat", title: "Cine Flat",
            provenance: "Original Kromora Look: Cine Flat. Best-guess approximation of a described low-contrast grading-base character; no camera profile or reference data.")
    }

    func testBundledSilverBypassMatchesTheGenerator() throws {
        try assertBundledCubeMatches(.silverBypass, name: "silver-bypass", title: "Silver Bypass",
            provenance: "Original Kromora Look: Silver Bypass. Best-guess approximation of a described high-contrast desaturated character; no camera profile or reference data.")
    }

    func testCineLooksBracketCleanSlideAndKeepMiddleGrayNeutral() {
        let clean = generator(.cleanSlide), flat = generator(.cineFlat), silver = generator(.silverBypass)
        XCTAssertLessThan(contrast(flat), contrast(clean))
        XCTAssertGreaterThan(contrast(silver), contrast(clean))
        XCTAssertLessThan(meanChroma(flat), meanChroma(clean))
        XCTAssertLessThan(meanChroma(silver), meanChroma(clean))
        XCTAssertLessThan(meanChroma(silver), 0.6 * meanChroma(clean), "much lower saturation")
        for g in [flat, silver] {
            let gray = g.evaluate(RGB(repeating: 0.5))
            XCTAssertEqual(gray.x, 0.5, accuracy: 1e-3)
            XCTAssertEqual(gray.x, gray.y, accuracy: 1e-9)
            XCTAssertEqual(gray.y, gray.z, accuracy: 1e-9)
        }
    }

    func testCineFlatDesaturatesGreensMagentasAndPurplesMost() {
        let flat = generator(.cineFlat), clean = generator(.cleanSlide)
        func ratio(_ c: RGB) -> Double { chroma(flat.colorStage(c)) / chroma(clean.colorStage(c)) }
        let green = RGB(0.3, 0.65, 0.35), purple = RGB(0.5, 0.3, 0.7), magenta = RGB(0.65, 0.3, 0.6)
        let red = RGB(0.7, 0.35, 0.3), yellow = RGB(0.7, 0.65, 0.3), cyan = RGB(0.3, 0.6, 0.65)
        for low in [green, purple, magenta] {
            for other in [red, yellow, cyan] { XCTAssertLessThan(ratio(low), ratio(other)) }
        }
    }

    func testSilverBypassShiftsNoHuesAndCrushesShadows() {
        let g = generator(.silverBypass)
        func hue(_ c: RGB) -> Double {
            let m = (c.x + c.y + c.z) / 3
            return SlideLookGenerator.hue(of: c - RGB(repeating: m))
        }
        for c in [RGB(0.7, 0.35, 0.3), RGB(0.3, 0.65, 0.35), RGB(0.2, 0.3, 0.8)] {
            XCTAssertEqual(hue(g.colorStage(c)), hue(c), accuracy: 1e-6)
        }
        XCTAssertLessThan(g.evaluate(RGB(repeating: 0.1)).x, 0.1)
        XCTAssertGreaterThan(g.evaluate(RGB(repeating: 0.9)).x, 0.9)
    }

    func testBundledPortraitSoftMatchesTheGenerator() throws {
        try assertBundledCubeMatches(.portraitSoft, name: "portrait-soft", title: "Portrait Soft",
            provenance: "Original Kromora Look: Portrait Soft. Best-guess approximation of a described low-contrast negative character; no camera profile or reference data.")
    }

    func testBundledPortraitCrispMatchesTheGenerator() throws {
        try assertBundledCubeMatches(.portraitCrisp, name: "portrait-crisp", title: "Portrait Crisp",
            provenance: "Original Kromora Look: Portrait Crisp. Best-guess approximation of a described moderate-contrast negative character; no camera profile or reference data.")
    }

    func testBundledStreetNegativeMatchesTheGenerator() throws {
        try assertBundledCubeMatches(.streetNegative, name: "street-negative", title: "Street Negative",
            provenance: "Original Kromora Look: Street Negative. Best-guess approximation of a described high-contrast negative character; no camera profile or reference data.")
    }

    func testBundledAmberPrintMatchesTheGenerator() throws {
        try assertBundledCubeMatches(.amberPrint, name: "amber-print", title: "Amber Print",
            provenance: "Original Kromora Look: Amber Print. Best-guess approximation of a described warm print character; no camera profile or reference data.")
    }

    func testBundledTrueColorMatchesTheGenerator() throws {
        try assertBundledCubeMatches(.trueColor, name: "true-color", title: "True Color",
            provenance: "Original Kromora Look: True Color. Best-guess approximation of a described near-neutral character; no camera profile or reference data.")
    }

    func testBundledFineMonoMatchesTheGenerator() throws {
        try assertBundledCubeMatches(.fineMono, name: "fine-mono", title: "Fine Mono",
            provenance: "Original Kromora Look: Fine Mono. Best-guess approximation of a described hard-mid-tone black-and-white character; no camera profile or reference data.")
    }

    func testBundledFineMonoYellowMatchesTheGenerator() throws {
        try assertBundledCubeMatches(.fineMonoYellow, name: "fine-mono-yellow", title: "Fine Mono Yellow",
            provenance: "Original Kromora Look: Fine Mono Yellow. Best-guess approximation of a described black-and-white character with a yellow colour filter; no camera profile or reference data.")
    }

    func testBundledFineMonoRedMatchesTheGenerator() throws {
        try assertBundledCubeMatches(.fineMonoRed, name: "fine-mono-red", title: "Fine Mono Red",
            provenance: "Original Kromora Look: Fine Mono Red. Best-guess approximation of a described black-and-white character with a red colour filter; no camera profile or reference data.")
    }

    func testBundledFineMonoGreenMatchesTheGenerator() throws {
        try assertBundledCubeMatches(.fineMonoGreen, name: "fine-mono-green", title: "Fine Mono Green",
            provenance: "Original Kromora Look: Fine Mono Green. Best-guess approximation of a described black-and-white character with a green colour filter; no camera profile or reference data.")
    }

    func testBundledPlainMonoMatchesTheGenerator() throws {
        try assertBundledCubeMatches(.plainMono, name: "plain-mono", title: "Plain Mono",
            provenance: "Original Kromora Look: Plain Mono. Best-guess approximation of a described flat black-and-white character; no camera profile or reference data.")
    }

    func testBundledWarmToneMatchesTheGenerator() throws {
        try assertBundledCubeMatches(.warmTone, name: "warm-tone", title: "Warm Tone",
            provenance: "Original Kromora Look: Warm Tone. Best-guess approximation of a described warm toned black-and-white character; no camera profile or reference data.")
    }

    // MARK: Monochrome Looks (KRMA-1108)

    private let monoLooks: [(String, SlideLookParameters)] = [
        ("fineMono", .fineMono), ("fineMonoYellow", .fineMonoYellow), ("fineMonoRed", .fineMonoRed),
        ("fineMonoGreen", .fineMonoGreen), ("plainMono", .plainMono),
    ]

    /// Output gray level of a pure P3 primary through a mono Look's channel mix and (neutral) curve.
    private func primaryLevels(_ parameters: SlideLookParameters) -> (r: Double, g: Double, b: Double) {
        let g = generator(parameters)
        func level(_ c: RGB) -> Double { g.shape(c).x }
        return (level(RGB(1, 0, 0)), level(RGB(0, 1, 0)), level(RGB(0, 0, 1)))
    }

    func testMonochromeFilterWeightsSumToOneAndAreOrderedByFilter() throws {
        for (name, parameters) in monoLooks + [("warmTone", .warmTone)] {
            let m = try XCTUnwrap(parameters.monochrome, name)
            XCTAssertEqual(m.red + m.green + m.blue, 1, accuracy: 1e-9, name)
            XCTAssertGreaterThan(min(m.red, m.green, m.blue), 0, name)
        }
        let plain = primaryLevels(.fineMono), yellow = primaryLevels(.fineMonoYellow)
        let red = primaryLevels(.fineMonoRed), green = primaryLevels(.fineMonoGreen)
        // Yellow darkens blue sky relative to no filter; Red darkens it further.
        XCTAssertLessThan(yellow.b, plain.b)
        XCTAssertLessThan(red.b, yellow.b)
        // Red lightens red-bearing colors; Green lightens green and darkens red.
        XCTAssertGreaterThan(red.r, yellow.r)
        XCTAssertGreaterThan(yellow.r, plain.r)
        XCTAssertGreaterThan(green.g, plain.g)
        XCTAssertLessThan(green.r, plain.r)
    }

    func testGreenFilterCompressesFoliageContrastComparedWithOtherFilters() {
        // Two foliage tones: a yellow-green and a blue-green. Green filter keeps them closest.
        let lightFoliage = RGB(0.55, 0.80, 0.25), darkFoliage = RGB(0.20, 0.55, 0.35)
        func gap(_ parameters: SlideLookParameters) -> Double {
            let g = generator(parameters)
            return abs(g.shape(lightFoliage).x - g.shape(darkFoliage).x)
        }
        XCTAssertLessThan(gap(.fineMonoGreen), gap(.fineMonoRed))
        XCTAssertLessThan(gap(.fineMonoGreen), gap(.fineMonoYellow))
    }

    func testMonochromeLooksAreNeutralMonotonicAndDoNotClipInP3() {
        let patches: [RGB] = [RGB(1, 0, 0), RGB(0, 1, 0), RGB(0, 0, 1), RGB(1, 1, 0), RGB(0, 1, 1), RGB(1, 0, 1),
                              RGB(0.9, 0.2, 0.1), RGB(0.2, 0.7, 0.3), RGB(0.15, 0.25, 0.95)]
        for (name, parameters) in monoLooks {
            let g = generator(parameters)
            for patch in patches {
                let out = g.shape(patch)
                XCTAssertEqual(out.x, out.y, accuracy: 1e-12, "\(name) \(patch)")
                XCTAssertEqual(out.y, out.z, accuracy: 1e-12, "\(name) \(patch)")
                XCTAssertGreaterThan(out.x, 0.001, "\(name) \(patch) crushed")
                XCTAssertLessThan(out.x, 0.999, "\(name) \(patch) clipped")
            }
            var previous = -1.0
            for i in 0...64 {
                let v = Double(i) / 64
                let out = g.shape(RGB(repeating: v))
                XCTAssertGreaterThan(out.x, previous, "\(name) not monotonic at \(v)")
                previous = out.x
            }
            XCTAssertEqual(g.shape(RGB(repeating: 1)).x, 1, accuracy: 1e-9, name)
        }
    }

    func testFineMonoIsHardInUpperMidsAndSoftInShadowsComparedWithPlainMono() {
        let fine = generator(.fineMono), plain = generator(.plainMono)
        func slope(_ g: SlideLookGenerator, _ a: Double, _ b: Double) -> Double {
            (g.shape(RGB(repeating: b)).x - g.shape(RGB(repeating: a)).x) / (b - a)
        }
        XCTAssertGreaterThan(slope(fine, 0.4, 0.6), slope(plain, 0.4, 0.6))
        XCTAssertGreaterThan(slope(fine, 0.4, 0.6), 1.2)
        // Soft into shadows: the toe slope is below the mid slope.
        XCTAssertLessThan(slope(fine, 0.02, 0.12), slope(fine, 0.4, 0.6))
        // Plain Mono holds highlights: its shoulder rolls off below its mid slope yet keeps gradation.
        XCTAssertLessThan(slope(plain, 0.9, 1.0), slope(plain, 0.4, 0.6))
        XCTAssertGreaterThan(slope(plain, 0.9, 1.0), 0.3)
    }

    func testWarmToneTintsShadowsAndHighlightsWarmWhileHoldingPlainMonoLuma() {
        let warm = generator(.warmTone)
        let plain = generator(.plainMono)
        XCTAssertEqual(SlideLookParameters.warmTone.toneCurve, SlideLookParameters.plainMono.toneCurve)
        for v in [0.1, 0.5, 0.9] {
            let out = warm.shape(RGB(repeating: v))
            XCTAssertGreaterThan(out.x, out.z, "warm at \(v)")
            XCTAssertGreaterThan(out.x, out.y - 1e-12, "warm at \(v)")
            XCTAssertEqual((out * warm.lumaWeights).sum(), plain.tone(v), accuracy: 2e-3, "Plain Mono luma held at \(v)")
        }
        // Mid-gray stays close to neutral: tint is weighted toward the ends.
        let mid = warm.shape(RGB(repeating: 0.5))
        XCTAssertLessThan(mid.x - mid.z, 0.03)
    }

    func testStreetNegativeResponseVariesAcrossAHueSweepAndLeansRed() {
        let g = generator(.streetNegative)
        func gain(_ hue: Double) -> Double {
            let input = RGB(repeating: 0.5) + SlideLookGenerator.hueVector(hue) * 0.2
            return chroma(g.colorStage(input)) / chroma(input)
        }
        XCTAssertGreaterThan(gain(0), 1.1)       // red boosted
        XCTAssertLessThan(gain(60), 0.8)         // yellow suppressed
        XCTAssertLessThan(gain(120), 0.75)       // green suppressed most
        XCTAssertLessThan(gain(240), 0.8)        // blue suppressed
        XCTAssertLessThan(gain(270), 0.8)        // purple suppressed
        let gains = stride(from: 0.0, to: 360, by: 30).map(gain)
        XCTAssertGreaterThan(gains.max()! - gains.min()!, 0.4)

        func hue(_ c: RGB) -> Double {
            SlideLookGenerator.hue(of: c - RGB(repeating: (c.x + c.y + c.z) / 3))
        }
        let magenta = RGB(0.5, 0.3, 0.5) + SlideLookGenerator.hueVector(330) * 0.1
        let out = g.colorStage(magenta)
        var delta = hue(out) - hue(magenta)
        if delta > 180 { delta -= 360 } else if delta < -180 { delta += 360 }
        XCTAssertGreaterThan(delta, 0)           // magenta hue (330) moves toward red (360)
    }

    func testStreetNegativeIsHighContrastWithCoolShadowsAndWarmHighlights() {
        let g = generator(.streetNegative)
        XCTAssertGreaterThan(contrast(g), contrast(generator(.cleanSlide)))
        let shadow = g.evaluate(RGB(repeating: 0.1)), highlight = g.evaluate(RGB(repeating: 0.9))
        XCTAssertGreaterThan(shadow.z, shadow.x)
        XCTAssertGreaterThan(highlight.x, highlight.z)
    }

    func testAmberPrintTintsWarmHighlightsAndCoolShadowsWithLiftedToe() {
        let g = generator(.amberPrint)
        let shadow = g.evaluate(RGB(repeating: 0.1)), highlight = g.evaluate(RGB(repeating: 0.9))
        XCTAssertGreaterThan(shadow.z, shadow.x)
        XCTAssertGreaterThan(shadow.y, shadow.x)         // blue-green
        XCTAssertGreaterThan(highlight.x, highlight.z)
        XCTAssertGreaterThan(highlight.x, highlight.y)   // amber leans red over green
        XCTAssertGreaterThan(highlight.y, highlight.z)
        XCTAssertGreaterThan(g.tone(0.1), 0.1 + 0.01)    // lifted toe
        XCTAssertEqual(g.tone(0), 0.06, accuracy: 1e-12)
    }

    func testTrueColorStaysNeutralOnAGrayRamp() {
        let g = generator(.trueColor)
        for i in 0...32 {
            let out = g.evaluate(RGB(repeating: Double(i) / 32))
            XCTAssertEqual(out.x, out.y, accuracy: 1e-9)
            XCTAssertEqual(out.y, out.z, accuracy: 1e-9)
        }
        let color = RGB(0.8, 0.4, 0.3)
        XCTAssertEqual(chroma(g.colorStage(color)) / chroma(color), 1, accuracy: 0.1)   // saturation held
    }

    func testNegativeLooksAreMonotonicAndDoNotClipInP3() {
        for parameters in [SlideLookParameters.streetNegative, .amberPrint, .trueColor] {
            let g = generator(parameters)
            for channel in 0..<3 {
                var previous = -1.0
                for i in 10...32 {
                    var input = RGB(repeating: 0.03)
                    input[channel] = Double(i) / 32
                    let out = g.evaluate(input)
                    XCTAssertGreaterThan(out[channel], previous, "channel \(channel) step \(i) of \(parameters.globalSaturation)")
                    previous = out[channel]
                }
            }
            XCTAssertLessThan(g.evaluate(RGB(1, 0, 0)).x, 1.0 + 1e-12)
        }
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

    // MARK: Family

    private func chroma(_ c: RGB) -> Double { max(c.x, c.y, c.z) - min(c.x, c.y, c.z) }

    /// Mean pre-tone chroma (color stage only, so tone compression does not mask saturation) over a coarse in-gamut color grid, away from the neutral axis and extremes.
    private func meanChroma(_ g: SlideLookGenerator) -> Double {
        var total = 0.0, count = 0.0
        for r in stride(from: 0.2, through: 0.8, by: 0.2) {
            for gr in stride(from: 0.2, through: 0.8, by: 0.2) {
                for b in stride(from: 0.2, through: 0.8, by: 0.2) {
                    total += chroma(g.colorStage(RGB(r, gr, b))); count += 1
                }
            }
        }
        return total / count
    }

    /// Tonal contrast: the output spread between the quarter and three-quarter gray.
    private func contrast(_ g: SlideLookGenerator) -> Double {
        g.evaluate(RGB(repeating: 0.75)).x - g.evaluate(RGB(repeating: 0.25)).x
    }

    func testSlideFamilyOrdering() {
        let clean = generator(.cleanSlide), vivid = generator(.vividSlide), soft = generator(.softSlide)
        XCTAssertGreaterThan(meanChroma(vivid), meanChroma(clean))
        XCTAssertGreaterThan(contrast(vivid), contrast(clean))
        XCTAssertLessThan(contrast(soft), contrast(clean))
        XCTAssertGreaterThan(meanChroma(soft), meanChroma(clean), "soft keeps slightly higher saturation")
        XCTAssertLessThan(meanChroma(soft), meanChroma(vivid))
    }

    func testFieldReportIsLessSaturatedThanCleanSlideWithYellowsReducedMost() {
        let clean = generator(.cleanSlide), field = generator(.fieldReport)
        XCTAssertLessThan(meanChroma(field), meanChroma(clean))
        // Pre-tone chroma ratio per hue patch (same lightness): yellows must be reduced most.
        func ratio(_ c: RGB) -> Double { chroma(field.colorStage(c)) / chroma(clean.colorStage(c)) }
        let yellow = RGB(0.7, 0.65, 0.3), yellowGreen = RGB(0.5, 0.65, 0.3)
        let red = RGB(0.7, 0.35, 0.3), green = RGB(0.3, 0.65, 0.35), cyan = RGB(0.3, 0.6, 0.65), magenta = RGB(0.65, 0.3, 0.6)
        for other in [red, green, cyan, magenta] {
            XCTAssertLessThan(ratio(yellow), ratio(other))
            XCTAssertLessThan(ratio(yellowGreen), ratio(other))
        }
    }

    func testFieldReportShiftsBluesTowardCyanWithFirmShadowsAndCoolShadowTint() {
        let g = generator(.fieldReport)
        func hue(_ c: RGB) -> Double {
            let m = (c.x + c.y + c.z) / 3
            return SlideLookGenerator.hue(of: c - RGB(repeating: m))
        }
        let blue = RGB(0.2, 0.3, 0.8)
        XCTAssertLessThan(hue(g.colorStage(blue)), hue(blue))
        // Soft highlights: the shoulder compresses the top end relative to Clean Slide.
        let clean = generator(.cleanSlide)
        XCTAssertLessThan(g.tone(1) - g.tone(0.95), clean.tone(1) - clean.tone(0.95))
        let shadow = g.evaluate(RGB(repeating: 0.1))
        XCTAssertGreaterThan(shadow.z, shadow.x, "cool shadow tint")
    }

    func testPortraitCrispIsSteeperThanPortraitSoftWithMatchingHues() {
        let soft = generator(.portraitSoft), crisp = generator(.portraitCrisp)
        XCTAssertGreaterThan(contrast(crisp), contrast(soft))
        XCTAssertLessThan(contrast(soft), contrast(generator(.cleanSlide)))
        XCTAssertGreaterThan(meanChroma(crisp), meanChroma(soft))
        func hue(_ c: RGB) -> Double {
            let m = (c.x + c.y + c.z) / 3
            return SlideLookGenerator.hue(of: c - RGB(repeating: m))
        }
        let patches = [RGB(0.7, 0.35, 0.3), RGB(0.7, 0.65, 0.3), RGB(0.3, 0.65, 0.35), RGB(0.3, 0.6, 0.7), RGB(0.25, 0.3, 0.75), RGB(0.65, 0.3, 0.6)]
        for patch in patches {
            var delta = abs(hue(soft.evaluate(patch)) - hue(crisp.evaluate(patch)))
            if delta > 180 { delta = 360 - delta }
            XCTAssertLessThan(delta, 4, "hue drift for \(patch)")
        }
        // Neither portrait Look rotates hue in the color stage.
        for patch in patches {
            XCTAssertEqual(hue(soft.colorStage(patch)), hue(patch), accuracy: 1e-6)
            XCTAssertEqual(hue(crisp.colorStage(patch)), hue(patch), accuracy: 1e-6)
        }
    }

    func testNewLooksKeepSkinHueWithinTheGuardLimit() {
        func hue(_ c: RGB) -> Double {
            let m = (c.x + c.y + c.z) / 3
            return SlideLookGenerator.hue(of: c - RGB(repeating: m))
        }
        let skins = [RGB(0.75, 0.55, 0.45), RGB(0.6, 0.42, 0.33), RGB(0.85, 0.68, 0.58), RGB(0.45, 0.31, 0.25)]
        for parameters in [SlideLookParameters.fieldReport, .portraitSoft, .portraitCrisp] {
            let g = generator(parameters)
            for skin in skins {
                let out = g.colorStage(skin)
                XCTAssertLessThan(abs(hue(out) - hue(skin)), 3, "skin hue moved for \(skin)")
                XCTAssertGreaterThan(chroma(out) / chroma(skin), 0.7)
                XCTAssertLessThanOrEqual(chroma(out) / chroma(skin), 1.0 + 1e-9)
            }
        }
    }

    func testNewLooksAreMonotonicNeutralAndDoNotClipInP3() {
        for parameters in [SlideLookParameters.fieldReport, .portraitSoft, .portraitCrisp] {
            let g = generator(parameters)
            var last = -1.0
            for i in 0...32 {
                let out = g.evaluate(RGB(repeating: Double(i) / 32))
                XCTAssertGreaterThan(out.x, last)
                last = out.x
                if parameters != .fieldReport { XCTAssertEqual(out.x, out.z, accuracy: 1e-9) }
            }
            XCTAssertEqual(g.tone(0), 0, accuracy: 1e-12)
            XCTAssertEqual(g.tone(1), 1, accuracy: 1e-12)
            for channel in 0..<3 {
                var previous = -1.0
                for i in 10...32 {
                    var input = RGB(repeating: 0.03)
                    input[channel] = Double(i) / 32
                    let out = g.evaluate(input)
                    XCTAssertGreaterThan(out[channel], previous)
                    previous = out[channel]
                }
            }
        }
    }

    func testVividAndSoftToneCurvesAreMonotonicWithFixedEndpoints() {
        for parameters in [SlideLookParameters.vividSlide, .softSlide] {
            let g = generator(parameters)
            var previous = -1.0
            for i in 0...1000 {
                let y = g.tone(Double(i) / 1000)
                XCTAssertGreaterThan(y, previous)
                previous = y
            }
            XCTAssertEqual(g.tone(0), 0, accuracy: 1e-12, "firm shadows")
            XCTAssertEqual(g.tone(1), 1, accuracy: 1e-12)
            XCTAssertEqual(g.tone(0.5), 0.5, accuracy: 1e-12)
            for encoding in SlideLookEncoding.allCases {
                var last = -1.0
                for i in 0...32 {
                    let out = generator(parameters, encoding: encoding).evaluate(RGB(repeating: Double(i) / 32))
                    XCTAssertEqual(out.x, out.z, accuracy: 1e-9)
                    XCTAssertGreaterThan(out.x, last)
                    last = out.x
                }
            }
        }
    }

    func testSaturatedPrimariesKeepGradationInP3() {
        for parameters in [SlideLookParameters.vividSlide, .softSlide] {
            let g = generator(parameters)
            // Dominant-channel ramps for saturated red, green and blue must keep distinct, ordered
            // values up to full level rather than collapsing onto a clipped plateau.
            for channel in 0..<3 {
                var previous = -1.0
                for i in 10...32 {
                    var input = RGB(repeating: 0.03)
                    input[channel] = Double(i) / 32
                    let out = g.evaluate(input)
                    XCTAssertGreaterThan(out[channel], previous, "channel \(channel) step \(i) clipped")
                    previous = out[channel]
                    XCTAssertTrue((0...1).contains(out.x) && (0...1).contains(out.y) && (0...1).contains(out.z))
                }
            }
            // Strongly saturated red and blue stay below white and keep their dominant channel.
            let red = g.evaluate(RGB(0.9, 0.1, 0.1)), blue = g.evaluate(RGB(0.1, 0.2, 0.9))
            XCTAssertLessThan(red.x, 1); XCTAssertGreaterThan(red.x, max(red.y, red.z))
            XCTAssertLessThan(blue.z, 1); XCTAssertGreaterThan(blue.z, max(blue.x, blue.y))
        }
    }

    func testVividShiftsBluesTowardMagentaAndYellowTowardOrange() {
        let g = generator(.vividSlide)
        func hue(_ c: RGB) -> Double {
            let m = (c.x + c.y + c.z) / 3
            return SlideLookGenerator.hue(of: c - RGB(repeating: m))
        }
        let blue = RGB(0.2, 0.3, 0.8), yellow = RGB(0.8, 0.75, 0.2)
        XCTAssertGreaterThan(hue(g.evaluate(blue)), hue(blue))
        XCTAssertLessThan(hue(g.evaluate(yellow)), hue(yellow))
    }

    func testBundledSlideCubesKeepSubWhiteGridSamplesBelowWhite() throws {
        for name in ["clean-slide", "vivid-slide", "soft-slide", "street-negative", "amber-print", "true-color"] {
            let url = cleanSlideURL.deletingLastPathComponent().appendingPathComponent("\(name).cube")
            let text = try String(contentsOf: url, encoding: .utf8)
            let rows = text.split(separator: "\n").filter {
                !$0.hasPrefix("#") && !$0.hasPrefix("TITLE") && !$0.hasPrefix("LUT_3D_SIZE")
            }
            XCTAssertEqual(rows.count, 33 * 33 * 33, "\(name) lattice size")

            for (index, row) in rows.enumerated() {
                let output = row.split(whereSeparator: \.isWhitespace).compactMap { Double($0) }
                XCTAssertEqual(output.count, 3, "\(name) row \(index)")
                guard output.count == 3 else { continue }
                let input = [index % 33, (index / 33) % 33, index / (33 * 33)].map { Double($0) / 32 }
                for channel in 0..<3 where input[channel] < 1 {
                    XCTAssertLessThan(output[channel], 1, "\(name) channel \(channel) clipped at row \(index)")
                }
            }
        }
    }
}

final class SlideLookManifestTests: XCTestCase {
    func testSlideLooksShipWithP3ProvenanceAndNoTrademarkedNames() throws {
        let manifest = try BundledLookLibrary.validate()
        let library = BundledLookLibrary.load()
        let names = ["Clean Slide", "Vivid Slide", "Soft Slide"]
        for name in names {
            let entry = try XCTUnwrap(manifest.looks.first { $0.name == name })
            XCTAssertEqual(entry.category, "Slide")
            XCTAssertEqual(entry.approval.status, "approved")
            XCTAssertTrue(entry.approval.notes.contains("KROMORA_AUTHORING_SPACE: displayP3"))
            XCTAssertTrue(entry.approval.notes.contains("KROMORA_ENCODING: sRGBTransfer"))
            XCTAssertTrue(entry.approval.notes.contains("RenderPipeline"))

            let look = try XCTUnwrap(library.looks.first { $0.id == entry.id })
            XCTAssertEqual(look.size, 33)
            XCTAssertEqual(look.authoringSpace, .displayP3)
            let banned = ["fuji", "provia", "velvia", "astia", "classic chrome", "superia", "eterna", "acros", "kodachrome"]
            let fields = [entry.id, entry.name, entry.category, entry.source, entry.approval.notes, entry.resource]
            for field in fields {
                for banned in banned { XCTAssertFalse(field.localizedCaseInsensitiveContains(banned), "\(field) mentions \(banned)") }
            }
        }
    }
}

final class DocumentaryAndPortraitLookManifestTests: XCTestCase {
    func testLooksShipWithP3ProvenanceCategoriesAndNoTrademarkedNames() throws {
        let manifest = try BundledLookLibrary.validate()
        let library = BundledLookLibrary.load()
        let expected = [("Field Report", "Negative"), ("Portrait Soft", "Negative"), ("Portrait Crisp", "Negative"),
                        ("Street Negative", "Negative"), ("Amber Print", "Negative"), ("True Color", "Negative")]
        for (name, category) in expected {
            let entry = try XCTUnwrap(manifest.looks.first { $0.name == name })
            XCTAssertEqual(entry.category, category)
            XCTAssertEqual(entry.approval.status, "approved")
            XCTAssertTrue(entry.approval.notes.contains("KROMORA_AUTHORING_SPACE: displayP3"))
            let look = try XCTUnwrap(library.looks.first { $0.id == entry.id })
            XCTAssertEqual(look.size, 33)
            XCTAssertEqual(look.authoringSpace, .displayP3)
            let banned = ["fuji", "provia", "velvia", "astia", "classic chrome", "superia", "eterna", "acros", "kodachrome", "pro neg", "nps"]
            for field in [entry.id, entry.name, entry.category, entry.source, entry.approval.notes, entry.resource] {
                for word in banned { XCTAssertFalse(field.localizedCaseInsensitiveContains(word), "\(field) mentions \(word)") }
            }
        }
    }
}

final class MonochromeLookManifestTests: XCTestCase {
    func testMonochromeLooksShipWithP3ProvenanceAndNoTrademarkedNames() throws {
        let manifest = try BundledLookLibrary.validate()
        let library = BundledLookLibrary.load()
        let names = ["Fine Mono", "Fine Mono Yellow", "Fine Mono Red", "Fine Mono Green", "Plain Mono", "Warm Tone"]
        for name in names {
            let entry = try XCTUnwrap(manifest.looks.first { $0.name == name })
            XCTAssertEqual(entry.category, "Monochrome")
            XCTAssertEqual(entry.approval.status, "approved")
            XCTAssertTrue(entry.approval.notes.contains("KROMORA_AUTHORING_SPACE: displayP3"))
            XCTAssertTrue(entry.source.contains("SlideLookGenerator"))
            let look = try XCTUnwrap(library.looks.first { $0.id == entry.id })
            XCTAssertEqual(look.size, 33)
            XCTAssertEqual(look.authoringSpace, .displayP3)
            let banned = ["fuji", "provia", "velvia", "astia", "classic chrome", "superia", "eterna", "acros", "neopan", "kodachrome"]
            for field in [entry.id, entry.name, entry.category, entry.source, entry.approval.notes, entry.resource] {
                for word in banned { XCTAssertFalse(field.localizedCaseInsensitiveContains(word), "\(field) mentions \(word)") }
            }
        }
    }
}

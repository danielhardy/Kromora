import Foundation
@testable import KromoraKit

/// Deterministic generator for the slide-style Look family (KRMA-1103).
///
/// A Look is a value of `SlideLookParameters`; `SlideLookGenerator.cubeText` turns it into a 33^3
/// `.cube` that is byte-for-byte reproducible. The values are best-guess approximations of publicly
/// described qualitative character (see `docs/FILM_SIMULATION_LOOKS_RESEARCH.md`); nothing here claims
/// fidelity to any camera or stock.
///
/// All work happens in a perceptual domain: node coordinates are encoded values in the authoring
/// space; they are decoded with the chosen `Encoding`, re-encoded with the sRGB transfer curve (an
/// identity for `.sRGBTransfer`), shaped, and mapped back. Cube coordinates stay in 0...1.
struct SlideLookParameters: Equatable {
    /// Tone curve applied per channel (so the neutral axis stays neutral). All three are bounded so
    /// the composition is strictly monotonic.
    struct ToneCurve: Equatable {
        /// Black-point lift, 0...0.25. Zero keeps black at black.
        var toe: Double
        /// Mid-tone slope at 0.5, 1...1.5. One is linear.
        var slope: Double
        /// Highlight roll-off, 0..<1. Reduces the slope at white without lowering white.
        var shoulder: Double
    }

    /// Per-sector saturation multiplier and hue rotation (degrees). Sector centers are 30 degrees
    /// apart starting at red (0) and moving through yellow (60), green (120), cyan (180), blue (240)
    /// and magenta (300); values are smoothly interpolated around the hue circle.
    struct HueSector: Equatable {
        var saturation: Double = 1
        var hueShift: Double = 0
    }

    /// Luminance reduction proportional to saturation: warm hues (red through yellow) and blue.
    struct ChromeDepth: Equatable {
        var warm: Double = 0
        var blue: Double = 0
    }

    /// Hue (degrees, 0 = red) and strength of a tint added to shadows or highlights.
    struct Tint: Equatable {
        var hue: Double = 0
        var amount: Double = 0
    }

    /// Channel-mix luma for a black-and-white Look: the output is `weights . rgb` (perceptually
    /// encoded), then shaped by the tone curve. Weights are non-negative and sum to one, so white
    /// stays white and every channel keeps some signal. The hue/saturation stage is bypassed.
    struct Monochrome: Equatable {
        var red: Double
        var green: Double
        var blue: Double
    }

    static let sectorCount = 12

    var monochrome: Monochrome?
    var toneCurve: ToneCurve
    var globalSaturation: Double
    var hueSectors: [HueSector]
    var chromeDepth: ChromeDepth
    var shadowTint: Tint
    var highlightTint: Tint
    /// 0...1. Fraction of the hue/saturation/chrome change removed inside the skin-hue range.
    var skinGuard: Double

    init(
        toneCurve: ToneCurve = .init(toe: 0, slope: 1, shoulder: 0),
        globalSaturation: Double = 1,
        hueSectors: [HueSector] = Array(repeating: HueSector(), count: sectorCount),
        chromeDepth: ChromeDepth = .init(),
        shadowTint: Tint = .init(),
        highlightTint: Tint = .init(),
        skinGuard: Double = 0,
        monochrome: Monochrome? = nil
    ) {
        self.monochrome = monochrome
        precondition(hueSectors.count == Self.sectorCount, "exactly \(Self.sectorCount) hue sectors")
        self.toneCurve = toneCurve
        self.globalSaturation = globalSaturation
        self.hueSectors = hueSectors
        self.chromeDepth = chromeDepth
        self.shadowTint = shadowTint
        self.highlightTint = highlightTint
        self.skinGuard = skinGuard
    }

    /// Clean Slide: the neutral baseline of the family. Gentle S-curve, a touch of red lift and a
    /// small orange-to-yellow and cyan-to-blue drift, light chrome depth, no tints.
    static let cleanSlide: SlideLookParameters = {
        var sectors = Array(repeating: HueSector(), count: sectorCount)
        sectors[0] = .init(saturation: 1.05, hueShift: 0)       // red
        sectors[1] = .init(saturation: 1, hueShift: 4)          // orange toward yellow
        sectors[6] = .init(saturation: 1, hueShift: 6)          // cyan toward blue
        return SlideLookParameters(
            toneCurve: .init(toe: 0, slope: 1.12, shoulder: 0.12),
            globalSaturation: 1.0,
            hueSectors: sectors,
            chromeDepth: .init(warm: 0.12, blue: 0.08),
            skinGuard: 0.5
        )
    }()

    /// Vivid Slide: strong S-curve with a firm toe, global saturation about 1.35 with extra in greens,
    /// blues and reds, blues toward magenta, yellow toward orange, heavy chrome depth.
    static let vividSlide: SlideLookParameters = {
        var sectors = Array(repeating: HueSector(), count: sectorCount)
        sectors[0] = .init(saturation: 1.25, hueShift: 0)       // red
        sectors[2] = .init(saturation: 1, hueShift: -6)         // yellow toward orange
        sectors[4] = .init(saturation: 0.85, hueShift: 0)       // green (about 1.15 effective)
        sectors[8] = .init(saturation: 1.3, hueShift: 8)        // blue toward magenta
        return SlideLookParameters(
            toneCurve: .init(toe: 0, slope: 1.3, shoulder: 0.15),
            globalSaturation: 1.35,
            hueSectors: sectors,
            chromeDepth: .init(warm: 0.25, blue: 0.15),
            skinGuard: 0.85
        )
    }()

    /// Soft Slide: softer S-curve, flattened shoulder, firm shadows, saturation about 1.10 with extra
    /// in greens, fair skin slightly less saturated and nudged away from red.
    static let softSlide: SlideLookParameters = {
        var sectors = Array(repeating: HueSector(), count: sectorCount)
        sectors[1] = .init(saturation: 0.95, hueShift: 3)       // skin-range orange, away from red
        sectors[4] = .init(saturation: 1.2, hueShift: 0)        // green
        sectors[6] = .init(saturation: 1, hueShift: 6)          // cyan toward blue
        return SlideLookParameters(
            toneCurve: .init(toe: 0, slope: 1.05, shoulder: 0.35),
            globalSaturation: 1.10,
            hueSectors: sectors,
            chromeDepth: .init(warm: 0.1, blue: 0.08),
            skinGuard: 0.3
        )
    }()

    /// Field Report: documentary character. Firm shadows, soft highlights, global saturation about
    /// 0.78 with yellows and yellow-greens pulled back most (effective about 0.6), dark blues and
    /// purples about 0.7, blues toward cyan, magenta eased in the sky range, slight cool shadow tint.
    static let fieldReport: SlideLookParameters = {
        var sectors = Array(repeating: HueSector(), count: sectorCount)
        sectors[2] = .init(saturation: 0.77, hueShift: 0)       // yellow
        sectors[3] = .init(saturation: 0.77, hueShift: 0)       // yellow-green
        sectors[8] = .init(saturation: 0.9, hueShift: -12)      // blue toward cyan
        sectors[9] = .init(saturation: 0.9, hueShift: -6)       // purple
        sectors[10] = .init(saturation: 0.9, hueShift: 0)       // magenta eased
        return SlideLookParameters(
            toneCurve: .init(toe: 0, slope: 1.1, shoulder: 0.3),
            globalSaturation: 0.78,
            hueSectors: sectors,
            shadowTint: .init(hue: 210, amount: 0.015),
            skinGuard: 0.5
        )
    }()

    /// Portrait Soft: negative-style, very low slope, global saturation about 0.85, hues untouched,
    /// skin protected.
    static let portraitSoft: SlideLookParameters = SlideLookParameters(
        toneCurve: .init(toe: 0, slope: 1.02, shoulder: 0.1),
        globalSaturation: 0.85,
        skinGuard: 0.8
    )

    /// Street Negative: very high contrast with an uneven per-hue response. Reds boosted (about 1.2),
    /// yellows about 0.7, dark greens about 0.65, blues and purples about 0.7; a slight red lean
    /// (orange and magenta nudged toward red); cool shadows with warm highlights.
    static let streetNegative: SlideLookParameters = {
        var sectors = Array(repeating: HueSector(), count: sectorCount)
        sectors[0] = .init(saturation: 1.23, hueShift: 0)       // red (about 1.1 effective)
        sectors[1] = .init(saturation: 1, hueShift: -3)         // orange toward red
        sectors[2] = .init(saturation: 0.78, hueShift: 0)       // yellow
        sectors[4] = .init(saturation: 0.72, hueShift: 0)       // green
        sectors[8] = .init(saturation: 0.78, hueShift: 0)       // blue
        sectors[9] = .init(saturation: 0.78, hueShift: 0)       // purple
        sectors[11] = .init(saturation: 1, hueShift: 3)         // magenta toward red
        return SlideLookParameters(
            toneCurve: .init(toe: 0, slope: 1.22, shoulder: 0.1),
            globalSaturation: 0.9,
            hueSectors: sectors,
            shadowTint: .init(hue: 215, amount: 0.02),
            highlightTint: .init(hue: 40, amount: 0.012),
            skinGuard: 0.5
        )
    }()

    /// Amber Print: soft slope with a lifted toe, saturation about 0.95, greens toward yellow, blues
    /// toward purple, slightly rosy skin, blue-green shadows and amber highlights.
    static let amberPrint: SlideLookParameters = {
        var sectors = Array(repeating: HueSector(), count: sectorCount)
        sectors[1] = .init(saturation: 1, hueShift: -3)         // skin-range orange, rosy
        sectors[4] = .init(saturation: 1, hueShift: -8)         // green toward yellow
        sectors[8] = .init(saturation: 1, hueShift: 5)          // blue toward purple
        return SlideLookParameters(
            toneCurve: .init(toe: 0.06, slope: 1.04, shoulder: 0.1),
            globalSaturation: 0.95,
            hueSectors: sectors,
            shadowTint: .init(hue: 190, amount: 0.025),
            highlightTint: .init(hue: 40, amount: 0.03),
            skinGuard: 0.3
        )
    }()

    /// True Color: near-neutral. Saturation 1, no tints, moderate slope; depth comes only from
    /// luminance shifts (blues darker, warm colors slightly deeper).
    static let trueColor: SlideLookParameters = SlideLookParameters(
        toneCurve: .init(toe: 0, slope: 1.1, shoulder: 0.08),
        globalSaturation: 1.0,
        chromeDepth: .init(warm: 0.05, blue: 0.1),
        skinGuard: 0.5
    )

    /// Portrait Crisp: the same hues as Portrait Soft with a steeper slope, slightly more saturation
    /// and slightly richer darks (a little luminance drop in saturated colors).
    static let portraitCrisp: SlideLookParameters = SlideLookParameters(
        toneCurve: .init(toe: 0, slope: 1.15, shoulder: 0.1),
        globalSaturation: 0.92,
        chromeDepth: .init(warm: 0.06, blue: 0.06),
        skinGuard: 0.8
    )

    // MARK: Cine (KRMA-1107)

    /// Cine Flat: a grading base. Very low slope with a lifted toe and a soft shoulder, saturation about
    /// 0.65 with greens, purples and magentas lowest (about 0.5). Middle gray is untouched by the curve.
    static let cineFlat: SlideLookParameters = {
        var sectors = Array(repeating: HueSector(), count: sectorCount)
        sectors[4] = .init(saturation: 0.77, hueShift: 0)       // green (about 0.5 effective)
        sectors[9] = .init(saturation: 0.77, hueShift: 0)       // purple
        sectors[10] = .init(saturation: 0.77, hueShift: 0)      // magenta
        return SlideLookParameters(
            toneCurve: .init(toe: 0.04, slope: 1, shoulder: 0.4),
            globalSaturation: 0.65,
            hueSectors: sectors,
            skinGuard: 0.5
        )
    }()

    /// Silver Bypass: very steep curve (crushed shadows, bright highlights), low uniform saturation
    /// about 0.35, no hue shift and no tint.
    static let silverBypass = SlideLookParameters(
        toneCurve: .init(toe: 0, slope: 1.5, shoulder: 0),
        globalSaturation: 0.35
    )

    // MARK: Monochrome (KRMA-1108)

    /// Fine Mono: neutral luma weights (the authoring space's own luma), hard from the lower mid-tones
    /// into the highlights, with a lifted toe so shadows soften rather than block up.
    /// Differs from Soft Mono (flat, low contrast), Silver Noir (dark, crushed) and Plain Mono (flatter).
    static let fineMono = SlideLookParameters(
        toneCurve: .init(toe: 0.03, slope: 1.35, shoulder: 0.1),
        monochrome: .init(red: 0.229, green: 0.692, blue: 0.079)
    )

    /// Yellow filter: blue (sky) darkens, reds and greens lighten a little.
    static let fineMonoYellow = SlideLookParameters(
        toneCurve: fineMono.toneCurve,
        monochrome: .init(red: 0.33, green: 0.62, blue: 0.05)
    )

    /// Red filter: blue darkens strongly, and red-bearing colors (including sunlit foliage) lighten.
    static let fineMonoRed = SlideLookParameters(
        toneCurve: fineMono.toneCurve,
        monochrome: .init(red: 0.58, green: 0.40, blue: 0.02)
    )

    /// Green filter: green dominates, so foliage tones collapse together (softer foliage contrast)
    /// while reds and blues darken.
    static let fineMonoGreen = SlideLookParameters(
        toneCurve: fineMono.toneCurve,
        monochrome: .init(red: 0.15, green: 0.80, blue: 0.05)
    )

    /// Plain Mono: the same luma weights as Fine Mono on a flatter curve that holds highlights.
    static let plainMono = SlideLookParameters(
        toneCurve: .init(toe: 0, slope: 1.1, shoulder: 0.35),
        monochrome: .init(red: 0.229, green: 0.692, blue: 0.079)
    )

    /// Warm Tone: Plain Mono's curve with a sepia-style split: deep amber shadows, light cream
    /// highlights. The tint is luma-held, so the tone ordering matches Plain Mono.
    static let warmTone = SlideLookParameters(
        toneCurve: plainMono.toneCurve,
        shadowTint: .init(hue: 35, amount: 0.05),
        highlightTint: .init(hue: 45, amount: 0.04),
        monochrome: .init(red: 0.229, green: 0.692, blue: 0.079)
    )
}

/// The transfer function node coordinates are encoded with.
enum SlideLookEncoding: String, CaseIterable {
    /// The sRGB / Display P3 piecewise transfer function (shared by both spaces).
    case sRGBTransfer
    /// Hybrid log-gamma (BT.2100) over its 0...1 signal range, for an extended-range HDR encoding.
    case hlg

    /// Encoded signal -> linear light, 0...1.
    func decode(_ e: Double) -> Double {
        switch self {
        case .sRGBTransfer:
            return e <= 0.04045 ? e / 12.92 : pow((e + 0.055) / 1.055, 2.4)
        case .hlg:
            let a = 0.17883277, b = 0.28466892, c = 0.55991073
            return e <= 0.5 ? e * e / 3 : (exp((e - c) / a) + b) / 12
        }
    }

    /// Linear light -> encoded signal, 0...1.
    func encode(_ l: Double) -> Double {
        switch self {
        case .sRGBTransfer:
            return l <= 0.0031308 ? l * 12.92 : 1.055 * pow(l, 1 / 2.4) - 0.055
        case .hlg:
            let a = 0.17883277, b = 0.28466892, c = 0.55991073
            return l <= 1.0 / 12 ? (3 * l).squareRoot() : a * log(12 * l - b) + c
        }
    }
}

struct SlideLookGenerator {
    static let latticeSize = 33
    private static let maximumSerializedValueBelowWhite = 0.999999
    private static let serializationLocale = Locale(identifier: "en_US_POSIX")

    let parameters: SlideLookParameters
    let space: WorkingSpace
    let encoding: SlideLookEncoding

    init(
        parameters: SlideLookParameters,
        space: WorkingSpace = .current,
        encoding: SlideLookEncoding = .sRGBTransfer
    ) {
        self.parameters = parameters
        self.space = space
        self.encoding = encoding
    }

    typealias RGB = SIMD3<Double>

    /// Luma weights applied to perceptually encoded values, per authoring space primaries.
    var lumaWeights: RGB {
        switch space {
        case .sRGB: RGB(0.2126, 0.7152, 0.0722)
        case .displayP3: RGB(0.2290, 0.6917, 0.0793)
        }
    }

    // MARK: Components (internal so they can be unit tested)

    /// Strictly monotonic tone curve on 0...1: contrast S, then toe lift, then highlight roll-off.
    func tone(_ x: Double) -> Double {
        let curve = parameters.toneCurve
        let x = min(max(x, 0), 1)
        let c = min(max(2 * (curve.slope - 1), 0), 1)
        var y = x + c * x * (1 - x) * (2 * x - 1)
        if y < 0.5 {
            let t = 1 - 2 * y
            y += min(max(curve.toe, 0), 0.25) * t * t
        }
        if y > 0.5 {
            let t = (y - 0.5) * 2
            let shoulder = min(max(curve.shoulder, 0), 0.99)
            y = 0.5 + 0.5 * (t + shoulder * t * t * (1 - t))
        }
        return min(max(y, 0), 1)
    }

    /// Smooth periodic interpolation of a per-sector value at a hue angle in degrees.
    func sectorValue(hue: Double, _ keyPath: KeyPath<SlideLookParameters.HueSector, Double>) -> Double {
        let n = SlideLookParameters.sectorCount
        var position = hue.truncatingRemainder(dividingBy: 360) / (360 / Double(n))
        if position < 0 { position += Double(n) }
        let lower = Int(position) % n
        let upper = (lower + 1) % n
        let f = position - Double(Int(position))
        let s = f * f * (3 - 2 * f)
        let a = parameters.hueSectors[lower][keyPath: keyPath]
        let b = parameters.hueSectors[upper][keyPath: keyPath]
        return a + (b - a) * s
    }

    /// Hue angle in degrees (0 = red, 120 = green, 240 = blue) of a chroma vector.
    static func hue(of d: RGB) -> Double {
        let h = atan2(3.0.squareRoot() / 2 * (d.y - d.z), d.x - (d.y + d.z) / 2) * 180 / Double.pi
        return h < 0 ? h + 360 : h
    }

    /// Zero-mean RGB direction for a hue angle, so adding it shifts hue and not brightness.
    static func hueVector(_ degrees: Double) -> RGB {
        let r = degrees * Double.pi / 180
        let third = 2 * Double.pi / 3
        return RGB(cos(r), cos(r - third), cos(r + third)) * (2.0 / 3.0)
    }

    /// 0...1 weight that is 1 at the center of the skin-hue range (about 30 degrees, orange) and
    /// falls smoothly to 0 by +-30 degrees; moderate chroma and mid luma only.
    func skinWeight(hue: Double, chroma: Double, luma: Double) -> Double {
        func smoothstep(_ a: Double, _ b: Double, _ x: Double) -> Double {
            let t = min(max((x - a) / (b - a), 0), 1)
            return t * t * (3 - 2 * t)
        }
        var delta = abs(hue - 30)
        if delta > 180 { delta = 360 - delta }
        let hueW = 1 - smoothstep(10, 30, delta)
        let chromaW = 1 - smoothstep(0.45, 0.75, chroma)
        let lumaW = smoothstep(0.15, 0.35, luma) * (1 - smoothstep(0.85, 0.98, luma))
        return hueW * chromaW * lumaW
    }

    /// Warm (red through yellow) and blue hue weights for chromeDepth.
    static func chromeWeights(hue: Double) -> (warm: Double, blue: Double) {
        func bump(_ center: Double, _ half: Double) -> Double {
            var delta = abs(hue - center)
            if delta > 180 { delta = 360 - delta }
            let t = min(delta / half, 1)
            return 1 - t * t * (3 - 2 * t)
        }
        return (bump(30, 60), bump(240, 50))
    }

    /// Color stage: hue/saturation sectors, skin guard and chromeDepth. Neutral input is unchanged.
    func colorStage(_ input: RGB) -> RGB {
        let w = lumaWeights
        let luma = (input * w).sum()
        let d = input - RGB(repeating: luma)
        let mean = (d.x + d.y + d.z) / 3
        let perp = d - RGB(repeating: mean)
        let chroma = (perp * perp).sum().squareRoot()
        guard chroma > 1e-12 else { return input }

        let hue = Self.hue(of: perp)
        let keep = 1 - parameters.skinGuard * skinWeight(hue: hue, chroma: chroma, luma: luma)
        let saturation = 1 + (parameters.globalSaturation * sectorValue(hue: hue, \.saturation) - 1) * keep
        let shift = sectorValue(hue: hue, \.hueShift) * keep * Double.pi / 180

        // Rotate the chroma vector about the gray axis (Rodrigues), then scale it.
        let k = RGB(repeating: 1 / 3.0.squareRoot())
        let cross = RGB(k.y * perp.z - k.z * perp.y, k.z * perp.x - k.x * perp.z, k.x * perp.y - k.y * perp.x)
        let rotated = (perp * cos(shift) + cross * sin(shift)) * saturation
        var rgb = RGB(repeating: luma + mean) + rotated
        rgb += RGB(repeating: luma - (rgb * w).sum())   // hold luma through hue/saturation changes

        // Boosted saturation can push the brightest channel past white. Soft-limit only that excess,
        // scaling chroma about the gray so hue and luma hold and the channel stays strictly below 1
        // and strictly monotonic instead of clipping onto a plateau.
        let inputPeak = max(input.x, input.y, input.z)
        let peak = max(rgb.x, rgb.y, rgb.z)
        if peak > inputPeak, peak > luma, inputPeak < 1 {
            let room = 1 - inputPeak
            let limited = inputPeak + room * tanh((peak - inputPeak) / room)
            let scale = (limited - luma) / (peak - luma)
            rgb = RGB(repeating: luma) + (rgb - RGB(repeating: luma)) * scale
        }

        let weights = Self.chromeWeights(hue: hue)
        let depth = (parameters.chromeDepth.warm * weights.warm + parameters.chromeDepth.blue * weights.blue)
            * min(chroma * saturation, 1) * keep
        return rgb * max(1 - depth, 0)
    }

    /// Split-tone: adds zero-mean hue vectors weighted toward shadows and highlights, luma-held.
    func tint(_ input: RGB) -> RGB {
        let shadow = parameters.shadowTint, highlight = parameters.highlightTint
        guard shadow.amount != 0 || highlight.amount != 0 else { return input }
        let w = lumaWeights
        let luma = (input * w).sum()
        let shadowWeight = (1 - luma) * (1 - luma)
        let highlightWeight = luma * luma
        var rgb = input
            + Self.hueVector(shadow.hue) * (shadow.amount * shadowWeight)
            + Self.hueVector(highlight.hue) * (highlight.amount * highlightWeight)
        rgb += RGB(repeating: luma - (rgb * w).sum())
        return rgb
    }

    /// The Look applied to a perceptually encoded RGB triple; the result is clamped to 0...1.
    func shape(_ input: RGB) -> RGB {
        var rgb: RGB
        if let mix = parameters.monochrome {
            rgb = RGB(repeating: mix.red * input.x + mix.green * input.y + mix.blue * input.z)
        } else {
            rgb = colorStage(input)
        }
        rgb = RGB(tone(rgb.x), tone(rgb.y), tone(rgb.z))
        rgb = tint(rgb)
        return RGB(min(max(rgb.x, 0), 1), min(max(rgb.y, 0), 1), min(max(rgb.z, 0), 1))
    }

    /// One lattice node: encoded in -> perceptual -> shaped -> encoded out.
    func evaluate(_ input: RGB) -> RGB {
        func toPerceptual(_ e: Double) -> Double {
            encoding == .sRGBTransfer ? e : SlideLookEncoding.sRGBTransfer.encode(encoding.decode(e))
        }
        func fromPerceptual(_ p: Double) -> Double {
            encoding == .sRGBTransfer ? p : encoding.encode(SlideLookEncoding.sRGBTransfer.decode(p))
        }
        let shaped = shape(RGB(toPerceptual(input.x), toPerceptual(input.y), toPerceptual(input.z)))
        func preserveSerializedHeadroom(_ output: Double, input: Double) -> Double {
            // Cube rows use six decimal places. Keep values below white from rounding to 1.000000,
            // which would otherwise turn a smooth near-white result into a clipped LUT node.
            input < 1 ? min(fromPerceptual(output), Self.maximumSerializedValueBelowWhite) : fromPerceptual(output)
        }
        return RGB(
            preserveSerializedHeadroom(shaped.x, input: input.x),
            preserveSerializedHeadroom(shaped.y, input: input.y),
            preserveSerializedHeadroom(shaped.z, input: input.z)
        )
    }

    /// Stable `.cube` row encoding, independent of the user's decimal separator.
    static func formattedCubeRow(_ value: RGB) -> String {
        String(
            format: "%.6f %.6f %.6f",
            locale: serializationLocale,
            arguments: [value.x, value.y, value.z]
        )
    }

    /// The `.cube` text: header comments (provenance, authoring space and encoding stamps), then
    /// 33^3 rows with red varying fastest. Deterministic: fixed-precision formatting, no timestamps.
    func cubeText(title: String, provenance: String) -> String {
        var lines = [
            "# \(provenance)",
            "# Generated by the slide Look generator (Tests/KromoraKitTests/SlideLookGenerator.swift).",
            CubeLUT.authoringSpaceHeader(space),
            "# KROMORA_ENCODING: \(encoding.rawValue)",
            "TITLE \"\(title)\"",
            "LUT_3D_SIZE \(Self.latticeSize)",
        ]
        lines.reserveCapacity(Self.latticeSize * Self.latticeSize * Self.latticeSize + lines.count)
        let n = Double(Self.latticeSize - 1)
        for b in 0..<Self.latticeSize {
            for g in 0..<Self.latticeSize {
                for r in 0..<Self.latticeSize {
                    let out = evaluate(RGB(Double(r) / n, Double(g) / n, Double(b) / n))
                    lines.append(Self.formattedCubeRow(out))
                }
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }
}

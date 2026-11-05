import CoreImage
import XCTest

@testable import KromoraKit

/// Opt-in characterization behind the KRMA-1179 decision on RAW colour headroom. For each local RAW
/// it develops the same 800-pixel frame with exposure, white balance, recovery, boost and lens
/// correction at their decoder defaults and varies only gamut mapping and EDR, then reads back float
/// **extended-linear Display P3** (the app's working space) and reports, per variant:
///
/// - frame-wide out-of-range channel fractions (`neg` below -0.001, `hi` above 1), *before* any
///   delivery conversion;
/// - a **saturated-subject region**: the most chromatic 0.5% of pixels (by `(max-min)/max`, among
///   pixels with a channel ≥ 0.25) in the neutral decode, compared at the same pixel indices after one
///   global gain returns the variant's whole-frame median luminance to the neutral's. Reported are the
///   mean chromaticity, the mean absolute hue shift versus neutral (an HSV-style hue of linear P3, so
///   only differences mean anything), the share of channels at/above 1, and the share of channels that
///   clamp to 0 or 255 after one identical output transform (clamp, encode as 8-bit Display P3);
/// - a **neutral reference region**: the 0.5% least chromatic pixels with luminance 0.1…0.6, whose
///   mean `|R-G|/G` and `|B-G|/G` shows whether a variant tints greys.
///
/// With `RAWColorHeadroomDownstream` it then applies Saturation, Vibrance, a mixer move and grading
/// through the production `RenderPipeline.applyColor`, with the Look off and with starter Looks on,
/// and reports the same region's hue shift and clipping relative to that variant's own un-edited
/// render, plus the same measurements at extreme decoder white balance.
///
/// There is no bracketed or sensor-clipped ground truth in `realworldtest/`. A boundary at 1 is an
/// output reference, not proof of sensor clipping, and a wider range or higher chromaticity is a tone
/// and gamut statement, not recovered detail. Needs `KROMORA_RAW_FIXTURE_DIR` or `realworldtest/`.
final class RAWColorHeadroomBenchmark: XCTestCase {
    private let space = WorkingSpace.displayP3.linearWorkingColorSpace
    private lazy var context = CIContext(options: [
        .workingColorSpace: space, .workingFormat: CIFormat.RGBAf,
    ])

    private struct Pixels {
        var width = 0
        var height = 0
        var rgba: [Float] = []
        var count: Int { width * height }
        func r(_ i: Int) -> Float { rgba[i * 4] }
        func g(_ i: Int) -> Float { rgba[i * 4 + 1] }
        func b(_ i: Int) -> Float { rgba[i * 4 + 2] }
        func luma(_ i: Int) -> Float { 0.2290 * r(i) + 0.6917 * g(i) + 0.0793 * b(i) }
        func maxChannel(_ i: Int) -> Float { max(r(i), g(i), b(i)) }
        func chromaticity(_ i: Int) -> Float {
            let m = maxChannel(i)
            return m > 1e-6 ? (m - min(r(i), g(i), b(i))) / m : 0
        }
        /// HSV-style hue of the linear triple, in degrees. Only differences are interpreted.
        func hue(_ i: Int) -> Float {
            atan2(Float(3).squareRoot() * (g(i) - b(i)), 2 * r(i) - g(i) - b(i)) * 180 / .pi
        }
    }

    private func read(_ image: CIImage) -> Pixels {
        let extent = image.extent.integral
        var p = Pixels(width: Int(extent.width), height: Int(extent.height))
        p.rgba = [Float](repeating: 0, count: p.width * p.height * 4)
        context.render(
            image, toBitmap: &p.rgba, rowBytes: p.width * 16, bounds: extent, format: .RGBAf,
            colorSpace: space)
        return p
    }

    private func median(_ p: Pixels) -> Float {
        var l = (0..<p.count).map { p.luma($0) }
        l.sort()
        return l[l.count / 2]
    }

    private func hueDelta(_ a: Float, _ b: Float) -> Float {
        var d = abs(a - b).truncatingRemainder(dividingBy: 360)
        if d > 180 { d = 360 - d }
        return d
    }

    /// The identical output transform: clamp the extended-linear P3 value, encode with the sRGB
    /// transfer curve (Display P3 shares it), quantize to 8 bits. Returns true when the channel
    /// lands on a rail (0 or 255).
    private func onRail(_ linear: Float, gain: Float) -> Bool {
        let v = max(0, min(1, linear * gain))
        let encoded = v <= 0.0031308 ? 12.92 * v : 1.055 * pow(v, 1 / 2.4) - 0.055
        let q = Int((encoded * 255).rounded())
        return q <= 0 || q >= 255
    }

    private struct Regions {
        var saturated: [Int]
        var neutral: [Int]
    }

    private func regions(of p: Pixels) -> Regions {
        let candidates = (0..<p.count).filter { p.maxChannel($0) >= 0.25 }
        let take = max(50, p.count / 200)
        let saturated = Array(candidates.sorted { p.chromaticity($0) > p.chromaticity($1) }.prefix(take))
        let greys = (0..<p.count).filter { p.luma($0) >= 0.1 && p.luma($0) <= 0.6 }
        let neutral = Array(greys.sorted { p.chromaticity($0) < p.chromaticity($1) }.prefix(take))
        return Regions(saturated: saturated, neutral: neutral)
    }

    private func line(
        _ name: String, _ p: Pixels, reference: Pixels, regions: Regions, referenceMedian: Float
    ) -> String {
        let gain = referenceMedian / max(median(p), 1e-6)
        var neg = 0, hi = 0
        for i in 0..<p.count {
            if min(p.r(i), p.g(i), p.b(i)) < -0.001 { neg += 1 }
            if p.maxChannel(i) > 1 { hi += 1 }
        }
        let n = Float(max(regions.saturated.count, 1))
        var chroma: Float = 0, hue: Float = 0, atOne = 0, rails = 0, negRegion = 0
        for i in regions.saturated {
            let scaled = (p.r(i) * gain, p.g(i) * gain, p.b(i) * gain)
            let m = max(scaled.0, scaled.1, scaled.2)
            chroma += m > 1e-6 ? (m - min(scaled.0, scaled.1, scaled.2)) / m : 0
            hue += hueDelta(p.hue(i), reference.hue(i))
            for c in [p.r(i), p.g(i), p.b(i)] {
                if c * gain >= 1 { atOne += 1 }
                if c < -0.001 { negRegion += 1 }
                if onRail(c, gain: gain) { rails += 1 }
            }
        }
        let g = Float(max(regions.neutral.count, 1))
        var cast: Float = 0
        for i in regions.neutral {
            let green = max(p.g(i), 1e-6)
            cast += (abs(p.r(i) - p.g(i)) + abs(p.b(i) - p.g(i))) / (2 * green)
        }
        return String(
            format:
                "  %-26@ frame neg=%.4f hi=%.4f | sat chroma=%.3f hueΔ=%5.2f° ≥1=%.3f rails=%.3f neg=%.3f | grey cast=%.4f",
            name as NSString, Float(neg) / Float(p.count), Float(hi) / Float(p.count), chroma / n,
            hue / n, Float(atOne) / (3 * n), Float(rails) / (3 * n), Float(negRegion) / (3 * n),
            cast / g)
    }

    private func starterLook(_ name: String) throws -> CubeLUT {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try CubeLUT(
            url: root.appendingPathComponent("Sources/KromoraKit/Resources/StarterLooks/\(name).cube"))
    }

    private func encoded8(_ linear: Float) -> Float {
        let v = max(0, min(1, linear))
        return (v <= 0.0031308 ? 12.92 * v : 1.055 * pow(v, 1 / 2.4) - 0.055) * 255
    }

    /// What gamut mapping off actually changes: the pixels that leave Display P3 (any channel below
    /// -0.001) in the gamut-off decode, compared with the same pixels in the gamut-mapped decode after
    /// the identical output transform, and again after a -50 Saturation pull-in (the one downstream
    /// control that could bring a negative channel back into range).
    func testPrintGamutOffOutOfGamutRegion() throws {
        let urls = Fixtures.localRAWURLs
        guard !urls.isEmpty else { throw XCTSkip("no local RAWs") }
        let scale = RenderScale.preview(maxSize: CGSize(width: 800, height: 800))
        for url in urls {
            let source = ImageSource(url: url, nativeExtent: CGSize(width: 4000, height: 3000))
            func develop(_ s: RAWDevelopSettings) -> CIImage? {
                RenderPipeline.developedSource(source, rawDevelop: s, scale: scale)
            }
            guard let on = develop(.neutral),
                let off = develop(RAWDevelopSettings(gamutMappingEnabled: false))
            else { continue }
            let onPixels = read(on), offPixels = read(off)
            let region = (0..<offPixels.count).filter {
                min(offPixels.r($0), offPixels.g($0), offPixels.b($0)) < -0.001
            }
            guard !region.isEmpty else {
                print("GAMUTOFF \(url.lastPathComponent) no out-of-gamut pixels")
                continue
            }
            func report(_ label: String, _ a: Pixels, _ b: Pixels) {
                var deltaSum: Float = 0, deltaMax: Float = 0, hueSum: Float = 0
                var chromaA: Float = 0, chromaB: Float = 0
                for i in region {
                    let ea = [a.r(i), a.g(i), a.b(i)].map(encoded8)
                    let eb = [b.r(i), b.g(i), b.b(i)].map(encoded8)
                    let d = zip(ea, eb).map { abs($0 - $1) }.reduce(0, +) / 3
                    deltaSum += d
                    deltaMax = max(deltaMax, zip(ea, eb).map { abs($0 - $1) }.max() ?? 0)
                    chromaA += ((ea.max() ?? 0) - (ea.min() ?? 0)) / max(ea.max() ?? 1, 1)
                    chromaB += ((eb.max() ?? 0) - (eb.min() ?? 0)) / max(eb.max() ?? 1, 1)
                    let ha = atan2(Float(3).squareRoot() * (ea[1] - ea[2]), 2 * ea[0] - ea[1] - ea[2]) * 180 / .pi
                    let hb = atan2(Float(3).squareRoot() * (eb[1] - eb[2]), 2 * eb[0] - eb[1] - eb[2]) * 180 / .pi
                    hueSum += hueDelta(ha, hb)
                }
                let n = Float(region.count)
                print(String(
                    format: "  %-22@ delivered |Δ| mean=%5.2f max=%6.2f /255 | hueΔ=%5.2f° | chroma off=%.3f on=%.3f",
                    label as NSString, deltaSum / n, deltaMax, hueSum / n, chromaA / n, chromaB / n))
            }
            let worst = region.map { min(offPixels.r($0), offPixels.g($0), offPixels.b($0)) }.min() ?? 0
            print(String(format: "GAMUTOFF %@ out-of-P3 pixels=%d (%.2f%% of frame) most-negative channel=%.4f",
                url.lastPathComponent as NSString, region.count, 100 * Double(region.count) / Double(offPixels.count), worst))
            report("as developed", offPixels, onPixels)
            let desat = ColorAdjustments(saturation: -50)
            report("both, saturation -50",
                read(RenderPipeline.applyColor(desat, to: off)), read(RenderPipeline.applyColor(desat, to: on)))
            let mixer = ColorAdjustments(mixer: ColorMixerAdjustments(
                red: ColorMixerChannel(saturation: -60), orange: ColorMixerChannel(saturation: -60),
                yellow: ColorMixerChannel(saturation: -60), green: ColorMixerChannel(saturation: -60),
                cyan: ColorMixerChannel(saturation: -60), blue: ColorMixerChannel(saturation: -60),
                purple: ColorMixerChannel(saturation: -60), magenta: ColorMixerChannel(saturation: -60)))
            report("both, mixer all sat -60",
                read(RenderPipeline.applyColor(mixer, to: off)), read(RenderPipeline.applyColor(mixer, to: on)))
        }
    }

    func testPrintColorHeadroomCharacterization() throws {
        let urls = Fixtures.localRAWURLs
        guard !urls.isEmpty else { throw XCTSkip("no local RAWs") }
        let scale = RenderScale.preview(maxSize: CGSize(width: 800, height: 800))
        let looks = [("vivid-slide", try starterLook("vivid-slide")), ("cine-flat", try starterLook("cine-flat"))]

        let decoderVariants: [(String, RAWDevelopSettings)] = [
            ("neutral (gamut on, EDR 0)", .neutral),
            ("gamut off", RAWDevelopSettings(gamutMappingEnabled: false)),
            ("EDR 1", RAWDevelopSettings(extendedDynamicRangeAmount: 1)),
            ("EDR 2", RAWDevelopSettings(extendedDynamicRangeAmount: 2)),
            ("gamut off + EDR 1", RAWDevelopSettings(gamutMappingEnabled: false, extendedDynamicRangeAmount: 1)),
            ("gamut off + EDR 2", RAWDevelopSettings(gamutMappingEnabled: false, extendedDynamicRangeAmount: 2)),
        ]
        let colorEdits: [(String, ColorAdjustments)] = [
            ("saturation +50", ColorAdjustments(saturation: 50)),
            ("saturation +100", ColorAdjustments(saturation: 100)),
            ("vibrance +50", ColorAdjustments(vibrance: 50)),
            ("vibrance +100", ColorAdjustments(vibrance: 100)),
            ("mixer red sat +60", ColorAdjustments(mixer: ColorMixerAdjustments(red: ColorMixerChannel(saturation: 60)))),
            ("grading highlights", ColorAdjustments(grading: ColorGradingAdjustments(highlights: ColorGradingWheel(hue: 40, saturation: 60)))),
        ]

        for url in urls {
            let source = ImageSource(url: url, nativeExtent: CGSize(width: 4000, height: 3000))
            func develop(_ s: RAWDevelopSettings) -> CIImage? {
                RenderPipeline.developedSource(source, rawDevelop: s, scale: scale)
            }
            guard let neutralImage = develop(.neutral) else { continue }
            let neutral = read(neutralImage)
            let m0 = median(neutral)
            let regs = regions(of: neutral)
            print("COLORHEADROOM \(url.lastPathComponent) \(neutral.width)x\(neutral.height) satRegion=\(regs.saturated.count) neutralRegion=\(regs.neutral.count)")
            if let f = CIRAWFilter(imageURL: url) {
                print("  decoder=\(f.decoderVersion) supported=\(f.supportedDecoderVersions.map(\.rawValue)) gamutMap=\(f.isGamutMappingEnabled) edr=\(f.extendedDynamicRangeAmount) boost=\(f.boostAmount) recovery=\(f.isHighlightRecoverySupported ? "\(f.isHighlightRecoveryEnabled)" : "unsupported") lens=\(f.isLensCorrectionSupported ? "\(f.isLensCorrectionEnabled)" : "unsupported")")
            }

            // 1. Decoder variants, extended-linear float, no RGB edit.
            var developed: [(String, CIImage, Pixels)] = []
            for (name, settings) in decoderVariants {
                guard let image = develop(settings) else { continue }
                let pixels = read(image)
                developed.append((name, image, pixels))
                print(line(name, pixels, reference: neutral, regions: regs, referenceMedian: m0))
            }

            // 2. Downstream RGB colour edits across the decoder variants, Look off and on. Hue shift
            // and clipping are measured against the same variant's un-edited (same Look) render.
            for (variantName, image, _) in developed where ["neutral (gamut on, EDR 0)", "gamut off", "EDR 1"].contains(variantName) {
                for lookCase in [("no Look", CubeLUT?.none)] + looks.map({ ($0.0, Optional($0.1)) }) {
                    func lit(_ base: CIImage) -> CIImage {
                        guard let lut = lookCase.1 else { return base }
                        return lut.apply(to: base, intensity: 1) ?? base
                    }
                    let baseline = read(lit(image))
                    let baselineMedian = median(baseline)
                    print("  [\(variantName) | \(lookCase.0)]")
                    for (editName, edit) in colorEdits {
                        let edited = read(lit(RenderPipeline.applyColor(edit, to: image)))
                        print(line(editName, edited, reference: baseline, regions: regs, referenceMedian: baselineMedian))
                    }
                }
            }

            // 3. Extreme decoder white balance (the existing RAW WB path) with and without gamut mapping.
            for (kelvin, tint) in [(2500.0, 0.0), (12000.0, 0.0), (6500.0, 120.0)] {
                for gamut in [true, false] {
                    let settings = RAWDevelopSettings(
                        neutralTemperature: kelvin, neutralTint: tint, gamutMappingEnabled: gamut)
                    guard let image = develop(settings) else { continue }
                    print(line("WB \(Int(kelvin))K/\(Int(tint)) gamut \(gamut ? "on" : "off")", read(image), reference: neutral, regions: regs, referenceMedian: m0))
                }
            }
        }
    }
}

import CoreImage
import XCTest

@testable import KromoraKit

/// Opt-in characterization behind the KRMA-1176 decision on RAW highlight/headroom routing. For each
/// local RAW it develops the same 800-pixel frame under decoder variants (highlight recovery, EDR,
/// boost, shadow boost, local tone map) and under the existing RGB Light controls, and prints
/// objective numbers for a **fixed region**: the brightest 0.5% of pixels by maximum channel in the
/// neutral decode. It reports the neutral support flags and defaults, a decode time per variant, and a
/// midtone-matched view (one global gain brings each variant's whole-frame median to the neutral's)
/// so tone appearance is separated from channel detail.
///
/// There is no bracketed or sensor-clipped ground truth in `realworldtest/`; a channel at or above 1
/// is an output reference, not proof of sensor clipping, and a larger highlight spread is a tone
/// statement, not recovered detail. Needs `KROMORA_RAW_FIXTURE_DIR` or `realworldtest/`.
final class RAWHighlightHeadroomBenchmark: XCTestCase {
    private let space = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!
    private lazy var context = CIContext(options: [
        .workingColorSpace: space, .workingFormat: CIFormat.RGBAf,
    ])

    private struct Pixels {
        var width = 0
        var height = 0
        var rgba: [Float] = []
        func luma(_ i: Int) -> Float {
            0.2126 * rgba[i * 4] + 0.7152 * rgba[i * 4 + 1] + 0.0722 * rgba[i * 4 + 2]
        }
        func maxChannel(_ i: Int) -> Float { max(rgba[i * 4], rgba[i * 4 + 1], rgba[i * 4 + 2]) }
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
        var l = (0..<p.width * p.height).map { p.luma($0) }
        l.sort()
        return l[l.count / 2]
    }

    private func percentile(_ values: [Float], _ q: Double) -> Float {
        guard !values.isEmpty else { return 0 }
        let s = values.sorted()
        return s[min(s.count - 1, Int(Double(s.count - 1) * q))]
    }

    private func line(
        _ name: String, _ p: Pixels, region: [Int], neutralMedian: Float, seconds: Double
    ) -> String {
        let gain = neutralMedian / max(median(p), 1e-6)
        var clipped = 0
        var lumas: [Float] = []
        var sat: [Float] = []
        for i in region {
            let m = p.maxChannel(i)
            if p.rgba[i * 4] >= 1 { clipped += 1 }
            if p.rgba[i * 4 + 1] >= 1 { clipped += 1 }
            if p.rgba[i * 4 + 2] >= 1 { clipped += 1 }
            lumas.append(p.luma(i))
            sat.append(m)
        }
        func spread(_ v: [Float]) -> Float { percentile(v, 0.95) - percentile(v, 0.05) }
        // Matched-midtone: the same statistics after the global gain.
        let matchedClip = region.reduce(0) { acc, i in
            acc + (0..<3).filter { p.rgba[i * 4 + $0] * Float(gain) >= 1 }.count
        }
        let n = Float(max(region.count, 1))
        // Scale-free texture: 5–95% spread over the region's median, so a pure rescale of the
        // highlights (EDR, a gain) scores the same as the neutral and only a reshaped shoulder moves.
        let relSpread = spread(lumas) / max(percentile(lumas, 0.5), 1e-6)
        return String(
            format:
                "  %-22@ med=%.3f | region clip=%.3f p99=%.3f relSpread=%.3f | midtone-matched clip=%.3f | %.0f ms",
            name as NSString, median(p), Float(clipped) / (3 * n), percentile(sat, 0.99),
            relSpread, Float(matchedClip) / (3 * n), seconds * 1000)
    }

    func testPrintHeadroomCharacterization() throws {
        let urls = Fixtures.localRAWURLs
        guard !urls.isEmpty else { throw XCTSkip("no local RAWs") }
        let scale = RenderScale.preview(maxSize: CGSize(width: 800, height: 800))

        for url in urls {
            let source = ImageSource(url: url, nativeExtent: CGSize(width: 4000, height: 3000))
            func develop(_ s: RAWDevelopSettings) -> CIImage? {
                RenderPipeline.developedSource(source, rawDevelop: s, scale: scale)
            }
            guard let neutralImage = develop(.neutral) else { continue }
            let neutral = read(neutralImage)
            let m0 = median(neutral)
            // Fixed region: the brightest 0.5% of pixels by max channel in the neutral decode. The
            // decoder geometry is identical for every variant, so the same indices are compared.
            let ranked = (0..<neutral.width * neutral.height).sorted {
                neutral.maxChannel($0) > neutral.maxChannel($1)
            }
            let region = Array(ranked.prefix(max(50, ranked.count / 200)))
            print(
                "HEADROOM \(url.lastPathComponent) \(neutral.width)x\(neutral.height) median=\(m0) regionPixels=\(region.count) neutralRegionClip=\(region.filter { neutral.maxChannel($0) >= 1 }.count)"
            )

            // Capabilities and decoder defaults, probed the way the engine does.
            if let f = CIRAWFilter(imageURL: url) {
                print(
                    "  defaults: boost=\(f.boostAmount) boostShadow=\(f.boostShadowAmount) edr=\(f.extendedDynamicRangeAmount) gamutMap=\(f.isGamutMappingEnabled) recoverySupported=\(f.isHighlightRecoverySupported) recovery=\(f.isHighlightRecoveryEnabled) localToneMapSupported=\(f.isLocalToneMapSupported) localToneMap=\(f.isLocalToneMapSupported ? f.localToneMapAmount : -1) baselineExposure=\(f.baselineExposure) decoder=\(f.decoderVersion)"
                )
            }

            func decoder(_ name: String, _ s: RAWDevelopSettings) {
                // Median of three timed develops + float readback (a proxy, not interactive latency).
                var times: [Double] = []
                var out: Pixels?
                for _ in 0..<3 {
                    let t = Date()
                    guard let img = develop(s) else { return }
                    out = read(img)
                    times.append(Date().timeIntervalSince(t))
                }
                print(line(name, out!, region: region, neutralMedian: m0, seconds: times.sorted()[1]))
            }
            func rgb(_ name: String, _ transform: (CIImage) -> CIImage) {
                let t = Date()
                let out = read(transform(neutralImage))
                print(line(name, out, region: region, neutralMedian: m0, seconds: Date().timeIntervalSince(t)))
            }

            decoder("neutral", .neutral)
            decoder("recovery off", RAWDevelopSettings(highlightRecoveryEnabled: false))
            decoder("recovery on", RAWDevelopSettings(highlightRecoveryEnabled: true))
            decoder("EDR 1", RAWDevelopSettings(extendedDynamicRangeAmount: 1))
            decoder("EDR 2", RAWDevelopSettings(extendedDynamicRangeAmount: 2))
            decoder("boost 0.5", RAWDevelopSettings(boostAmount: 0.5))
            decoder("boost 0", RAWDevelopSettings(boostAmount: 0))
            decoder("boost 0 + EDR 1", RAWDevelopSettings(boostAmount: 0, extendedDynamicRangeAmount: 1))
            decoder("boostShadow 0.5", RAWDevelopSettings(boostShadowAmount: 0.5))
            decoder("boostShadow 1.5", RAWDevelopSettings(boostShadowAmount: 1.5))
            decoder("localToneMap 0", RAWDevelopSettings(localToneMapAmount: 0))
            decoder("localToneMap 1", RAWDevelopSettings(localToneMapAmount: 1))
            decoder("exposure -1", RAWDevelopSettings(exposure: -1))

            rgb("RGB highlights -100") { RenderPipeline.applyLight(LightAdjustments(highlights: -100), to: $0) }
            rgb("RGB highlights -50") { RenderPipeline.applyLight(LightAdjustments(highlights: -50), to: $0) }
            rgb("RGB whites -100") { RenderPipeline.applyLight(LightAdjustments(whites: -100), to: $0) }
            rgb("RGB shadows +100") { RenderPipeline.applyLight(LightAdjustments(shadows: 100), to: $0) }
            rgb("RGB blacks -100") { RenderPipeline.applyLight(LightAdjustments(blacks: -100), to: $0) }
            rgb("RGB exposure -1") { RenderPipeline.applyLight(LightAdjustments(exposure: -1), to: $0) }
        }
    }
}

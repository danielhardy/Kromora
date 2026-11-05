import CoreImage
import Darwin
import XCTest

@testable import KromoraKit

/// Opt-in measurements for KRMA-1175 on the local RAWs (`Fixtures.localRAWURLs`). Prints, never
/// asserts, numbers:
///
/// 1. `testPrintMatchedNoiseComparison` — decoder-routed Luminance (and, for the record, Colour) NR against the RGB
///    `CINoiseReduction` path it replaced, **matched on flat-field noise** (the RGB slider is
///    bisected until its flat-patch noise equals the decoder's), then compared on edge retention
///    and overshoot. Set `KROMORA_RAW_DETAIL_CROP_DIR` to also write 1:1 crops.
/// 2. `testPrintSharpnessHeadroom` — the decoder sharpness default and the headroom above it.
/// 3. `testPrintEngineCost` — window-independent `RenderEngine` tick cost for decoder-routed NR
///    against an RGB-only control (Sharpening) and decoder Exposure (KRMA-1174 reference).
///
/// Metrics are computed from float readbacks of the stage graph over a 1500×1000 window of the
/// full-resolution development. Flat-field
/// noise is the standard deviation of the 5×5 high-pass residual in the flattest 48 px tile of the
/// neutral frame; edge retention is the mean gradient magnitude over the strongest 1% of neutral
/// pixels relative to neutral; overshoot is the mean excursion beyond the neutral frame's local 5×5
/// range around those edges (a halo proxy). None of these is a perceptual quality score.
final class RAWDetailRoutingBenchmark: XCTestCase {
    // MARK: - Frame access

    private struct Frame {
        let width: Int
        let height: Int
        /// Interleaved RGBA float.
        let pixels: [Float]

        func luma(_ i: Int) -> Double {
            Double(pixels[i * 4]) * 0.2126 + Double(pixels[i * 4 + 1]) * 0.7152
                + Double(pixels[i * 4 + 2]) * 0.0722
        }
        func chroma(_ i: Int) -> (Double, Double) {
            let g = Double(pixels[i * 4 + 1])
            return (Double(pixels[i * 4]) - g, Double(pixels[i * 4 + 2]) - g)
        }
    }

    private func read(_ image: CIImage) -> Frame {
        let rect = image.extent.integral
        let width = Int(rect.width)
        let height = Int(rect.height)
        var pixels = [Float](repeating: 0, count: width * height * 4)
        pixels.withUnsafeMutableBytes { raw in
            Pixels.context.render(
                image, toBitmap: raw.baseAddress!, rowBytes: width * 16, bounds: rect,
                format: .RGBAf, colorSpace: nil)
        }
        return Frame(width: width, height: height, pixels: pixels)
    }

    /// Box mean of `values` over (2r+1)² via an integral image.
    private func boxMean(_ values: [Double], width: Int, height: Int, radius r: Int) -> [Double] {
        var integral = [Double](repeating: 0, count: (width + 1) * (height + 1))
        for y in 0..<height {
            var row = 0.0
            for x in 0..<width {
                row += values[y * width + x]
                integral[(y + 1) * (width + 1) + x + 1] = integral[y * (width + 1) + x + 1] + row
            }
        }
        var out = [Double](repeating: 0, count: width * height)
        for y in 0..<height {
            let y0 = max(0, y - r), y1 = min(height, y + r + 1)
            for x in 0..<width {
                let x0 = max(0, x - r), x1 = min(width, x + r + 1)
                let sum =
                    integral[y1 * (width + 1) + x1] - integral[y0 * (width + 1) + x1]
                    - integral[y1 * (width + 1) + x0] + integral[y0 * (width + 1) + x0]
                out[y * width + x] = sum / Double((x1 - x0) * (y1 - y0))
            }
        }
        return out
    }

    private func gradient(_ luma: [Double], width: Int, height: Int) -> [Double] {
        var out = [Double](repeating: 0, count: width * height)
        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) {
                let gx = luma[y * width + x + 1] - luma[y * width + x - 1]
                let gy = luma[(y + 1) * width + x] - luma[(y - 1) * width + x]
                out[y * width + x] = (gx * gx + gy * gy).squareRoot()
            }
        }
        return out
    }

    // MARK: - Metrics anchored on the neutral frame

    private struct Anchor {
        let width: Int
        let height: Int
        let flat: (x: Int, y: Int)
        let edgePixels: [Int]
        let neutralEdgeMean: Double
        let localMax: [Int: Double]
        let localMin: [Int: Double]
        let edgeTile: (x: Int, y: Int)
    }

    private let tile = 48

    private func anchor(_ neutral: Frame) -> Anchor {
        let n = neutral.width * neutral.height
        let luma = (0..<n).map(neutral.luma)
        let highPass = zip(luma, boxMean(luma, width: neutral.width, height: neutral.height, radius: 2))
            .map { $0 - $1 }
        // Flattest tile among reasonably exposed ones.
        var best = (energy: Double.infinity, x: 0, y: 0)
        var strongest = (energy: 0.0, x: 0, y: 0)
        let grad = gradient(luma, width: neutral.width, height: neutral.height)
        for ty in stride(from: 8, to: neutral.height - tile - 8, by: tile) {
            for tx in stride(from: 8, to: neutral.width - tile - 8, by: tile) {
                var mean = 0.0, energy = 0.0, g = 0.0
                for y in ty..<(ty + tile) {
                    for x in tx..<(tx + tile) {
                        mean += luma[y * neutral.width + x]
                        g += grad[y * neutral.width + x]
                    }
                }
                mean /= Double(tile * tile)
                if mean > 0.03, mean < 0.8 {
                    for y in ty..<(ty + tile) {
                        for x in tx..<(tx + tile) {
                            energy += highPass[y * neutral.width + x] * highPass[y * neutral.width + x]
                        }
                    }
                    // Flat: low *gradient* energy too, so texture is not mistaken for noise.
                    let score = energy + g * g * 1e-3
                    if score < best.energy { best = (score, tx, ty) }
                }
                if g > strongest.energy { strongest = (g, tx, ty) }
            }
        }
        let threshold = grad.sorted()[Int(Double(grad.count) * 0.99)]
        var edges: [Int] = []
        for i in 0..<grad.count where grad[i] >= threshold { edges.append(i) }
        let meanEdge = edges.reduce(0.0) { $0 + grad[$1] } / Double(max(1, edges.count))
        // Local range of the neutral frame (5×5) around the edge pixels, for the overshoot proxy.
        var localMax = [Int: Double](), localMin = [Int: Double]()
        edges = edges.filter {
            let x = $0 % neutral.width, y = $0 / neutral.width
            return x >= 2 && y >= 2 && x < neutral.width - 2 && y < neutral.height - 2
        }
        for i in edges {
            var hi = -Double.infinity, lo = Double.infinity
            for dy in -2...2 {
                for dx in -2...2 {
                    let v = luma[i + dy * neutral.width + dx]
                    hi = max(hi, v); lo = min(lo, v)
                }
            }
            localMax[i] = hi
            localMin[i] = lo
        }
        return Anchor(
            width: neutral.width, height: neutral.height, flat: (best.x, best.y),
            edgePixels: edges, neutralEdgeMean: meanEdge, localMax: localMax, localMin: localMin,
            edgeTile: (strongest.x, strongest.y))
    }

    private struct Metrics {
        var lumaNoise = 0.0
        var chromaNoise = 0.0
        var edgeRetention = 0.0
        var overshoot = 0.0
    }

    private func metrics(_ frame: Frame, anchor a: Anchor) -> Metrics {
        let w = a.width
        func luma(_ i: Int) -> Double { frame.luma(i) }
        // 5×5 high-pass residual, evaluated only inside the flat tile.
        func highPass(_ x: Int, _ y: Int, _ value: (Int) -> Double) -> Double {
            var sum = 0.0
            for dy in -2...2 { for dx in -2...2 { sum += value((y + dy) * w + x + dx) } }
            return value(y * w + x) - sum / 25
        }
        var lumaEnergy = 0.0, chromaEnergy = 0.0
        for y in a.flat.y..<(a.flat.y + tile) {
            for x in a.flat.x..<(a.flat.x + tile) {
                lumaEnergy += pow(highPass(x, y, luma), 2)
                chromaEnergy +=
                    pow(highPass(x, y) { frame.chroma($0).0 }, 2)
                    + pow(highPass(x, y) { frame.chroma($0).1 }, 2)
            }
        }
        var m = Metrics()
        m.lumaNoise = (lumaEnergy / Double(tile * tile)).squareRoot()
        m.chromaNoise = (chromaEnergy / Double(tile * tile * 2)).squareRoot()
        var gradientSum = 0.0, overshoot = 0.0
        for i in a.edgePixels {
            let gx = luma(i + 1) - luma(i - 1)
            let gy = luma(i + w) - luma(i - w)
            gradientSum += (gx * gx + gy * gy).squareRoot()
            overshoot += max(0, luma(i) - (a.localMax[i] ?? .infinity)) + max(0, (a.localMin[i] ?? -.infinity) - luma(i))
        }
        let count = Double(max(1, a.edgePixels.count))
        m.edgeRetention = gradientSum / count / max(1e-9, a.neutralEdgeMean)
        m.overshoot = overshoot / count
        return m
    }

    // MARK: - Graphs

    /// A 1:1 window at the centre of the full-resolution development. Decoder noise reduction acts at
    /// sensor scale, so a downscaled preview would average the noise away and hide it.
    private let window = CGSize(width: 1500, height: 1000)

    private func developed(_ source: ImageSource, _ develop: RAWDevelopSettings) throws -> CIImage {
        let full = try XCTUnwrap(
            RenderPipeline.developedSource(source, rawDevelop: develop, scale: .full))
        let e = full.extent
        return full.cropped(to: CGRect(
            x: (e.midX - window.width / 2).rounded(), y: (e.midY - window.height / 2).rounded(),
            width: window.width, height: window.height))
    }

    /// The frame as a value image, so each RGB variant starts from the same pixels without
    /// re-developing the RAW.
    private func materialized(_ frame: Frame, origin: CGPoint) -> CIImage {
        CIImage(
            bitmapData: frame.pixels.withUnsafeBytes { Data($0) }, bytesPerRow: frame.width * 16,
            size: CGSize(width: frame.width, height: frame.height), format: .RGBAf, colorSpace: nil
        ).transformed(by: CGAffineTransform(translationX: origin.x, y: origin.y))
    }

    private func rgbFrame(_ neutral: CIImage, luminance: Double, colour: Double) -> Frame {
        read(
            RenderPipeline.applyDetailControls(
                DetailAdjustments(luminanceNoise: luminance, colorNoise: colour), to: neutral,
                referenceExtent: neutral.extent))
    }

    private func decoderFrame(
        _ source: ImageSource, _ capabilities: RAWCapabilities, luminance: Double, colour: Double
    ) throws -> Frame {
        let stored = EditDocument(
            effects: EffectsAdjustments(
                detail: DetailAdjustments(luminanceNoise: luminance, colorNoise: colour)))
        var routed = stored.routedForRendering(source: .raw, decoder: capabilities)
        if colour > 0 {
            // Colour NR is not routed in the product; measure the decoder control for the record.
            routed.rawDevelop.colorNoiseReductionAmount = RAWDetailRouting.decoderAmount(
                base: capabilities.colorNoiseReductionAmount, noise: colour, detail: 50, contrast: 0)
            routed.effects.detail.colorNoise = 0
        }
        let image = try developed(source, routed.rawDevelop)
        return read(
            RenderPipeline.applyDetailControls(
                routed.effects.detail, to: image, referenceExtent: image.extent))
    }

    private func capabilities(_ source: ImageSource) throws -> RAWCapabilities {
        let filter = try XCTUnwrap(RenderPipeline.rawFilter(for: source.backing))
        return RenderEngine.InteractiveRAWFilterSession.captureCapabilities(filter)
    }

    private func sources() throws -> [(name: String, source: ImageSource)] {
        let urls = Fixtures.localRAWURLs
        guard !urls.isEmpty else { throw XCTSkip("no local RAWs; see Fixtures.localRAWURLs") }
        return urls.map {
            ($0.deletingPathExtension().lastPathComponent,
             ImageSource(url: $0, nativeExtent: CGSize(width: 6000, height: 4000)))
        }
    }

    private func writeCrops(_ name: String, anchor a: Anchor, frames: [(String, Frame)]) {
        guard let dir = ProcessInfo.processInfo.environment["KROMORA_RAW_DETAIL_CROP_DIR"] else { return }
        let folder = URL(fileURLWithPath: dir, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let space = CGColorSpace(name: CGColorSpace.displayP3)!
        for (label, frame) in frames {
            for (kind, origin) in [("flat", a.flat), ("edge", a.edgeTile)] {
                let x = max(0, min(frame.width - 192, origin.x + tile / 2 - 96))
                let y = max(0, min(frame.height - 192, origin.y + tile / 2 - 96))
                var rows = Data()
                for row in y..<(y + 192) {
                    for col in x..<(x + 192) {
                        let i = (row * frame.width + col) * 4
                        for c in 0..<3 {
                            let v = Double(frame.pixels[i + c]).clamped(to: 0...1)
                            // sRGB-ish display encoding for viewing only.
                            rows.append(UInt8((pow(v, 1 / 2.2) * 255).rounded()))
                        }
                    }
                }
                guard let provider = CGDataProvider(data: rows as CFData),
                    let cg = CGImage(
                        width: 192, height: 192, bitsPerComponent: 8, bitsPerPixel: 24,
                        bytesPerRow: 192 * 3, space: space,
                        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                        provider: provider, decode: nil, shouldInterpolate: false,
                        intent: .defaultIntent)
                else { continue }
                let url = folder.appendingPathComponent("\(name)-\(kind)-\(label).png")
                try? CIContext().writePNGRepresentation(
                    of: CIImage(cgImage: cg), to: url, format: .RGBA8, colorSpace: space)
            }
        }
    }

    // MARK: - 1. Matched comparison

    func testPrintMatchedNoiseComparison() throws {
        for (name, source) in try sources() {
            let caps = try capabilities(source)
            let neutralLazy = try developed(source, .neutral)
            let neutral = read(neutralLazy)
            let neutralImage = materialized(neutral, origin: neutralLazy.extent.origin)
            let a = anchor(neutral)
            let base = metrics(neutral, anchor: a)
            print(
                "RAW-DETAIL", name,
                String(format: "decoder default lumNR=%.4f colNR=%.2f | neutral lumaNoise=%.5f chromaNoise=%.5f", caps.luminanceNoiseReductionAmount, caps.colorNoiseReductionAmount, base.lumaNoise, base.chromaNoise))

            for channel in ["luminance", "colour"] {
                let isLuma = channel == "luminance"
                func noise(_ m: Metrics) -> Double { isLuma ? m.lumaNoise : m.chromaNoise }
                for slider in [50.0, 100] {
                    let decoder = try decoderFrame(
                        source, caps, luminance: isLuma ? slider : 0, colour: isLuma ? 0 : slider)
                    let dm = metrics(decoder, anchor: a)
                    // Bisect the RGB slider to the decoder's flat-field noise.
                    var lo = 0.0, hi = 100.0
                    let atMax = metrics(
                        rgbFrame(neutralImage, luminance: isLuma ? 100 : 0, colour: isLuma ? 0 : 100),
                        anchor: a)
                    var matched = atMax
                    var rgbSlider = 100.0
                    var reachable = noise(atMax) <= noise(dm)
                    if reachable {
                        for _ in 0..<7 {
                            let mid = (lo + hi) / 2
                            let m = metrics(
                                rgbFrame(neutralImage, luminance: isLuma ? mid : 0, colour: isLuma ? 0 : mid),
                                anchor: a)
                            if noise(m) > noise(dm) { lo = mid } else { hi = mid }
                        }
                        rgbSlider = hi
                        matched = metrics(
                            rgbFrame(neutralImage, luminance: isLuma ? hi : 0, colour: isLuma ? 0 : hi),
                            anchor: a)
                        reachable = abs(noise(matched) - noise(dm)) < 0.1 * noise(dm)
                    }
                    print(
                        "RAW-DETAIL", name, channel, String(format: "slider=%3.0f", slider),
                        String(format: "[rgb@100 reach: noise=%.5f edge=%.3f]", noise(atMax), atMax.edgeRetention),
                        String(format: "decoder: noise=%.5f edge=%.3f overshoot=%.5f", noise(dm), dm.edgeRetention, dm.overshoot),
                        reachable
                            ? String(format: "| rgb@%.0f: noise=%.5f edge=%.3f overshoot=%.5f", rgbSlider, noise(matched), matched.edgeRetention, matched.overshoot)
                            : String(format: "| rgb unmatched (rgb@100 noise=%.5f edge=%.3f overshoot=%.5f)", noise(atMax), atMax.edgeRetention, atMax.overshoot))
                    if slider == 100 || slider == 50, isLuma {
                        writeCrops(
                            "\(name)-lum\(Int(slider))", anchor: a,
                            frames: [
                                ("neutral", neutral), ("decoder", decoder),
                                ("rgb", rgbFrame(neutralImage, luminance: rgbSlider, colour: 0)),
                            ])
                    }
                }
            }
        }
    }

    // MARK: - 1b. Decoder response sweep (KRMA-1183)

    /// Decoder-routed Luminance at a ladder of slider values, on the same anchor as the matched
    /// comparison, plus the neutral frame and an explicit write of the decoder's own default (to
    /// separate "the property was written" from "the amount moved").
    func testPrintDecoderLuminanceResponseSweep() throws {
        for (name, source) in try sources() {
            let caps = try capabilities(source)
            let neutral = read(try developed(source, .neutral))
            let a = anchor(neutral)
            func line(_ label: String, _ frame: Frame, amount: Double?) {
                let m = metrics(frame, anchor: a)
                print(
                    "RAW-DETAIL-SWEEP", name, label,
                    amount.map { String(format: "amount=%.4f", $0) } ?? "amount=unset",
                    String(format: "noise=%.5f edge=%.3f overshoot=%.5f", m.lumaNoise, m.edgeRetention, m.overshoot))
            }
            line("neutral", neutral, amount: nil)
            var explicitBase = RAWDevelopSettings()
            explicitBase.luminanceNoiseReductionAmount = caps.luminanceNoiseReductionAmount
            line("explicit-default", read(try developed(source, explicitBase)), amount: caps.luminanceNoiseReductionAmount)
            // The decoder amount itself, bypassing the slider mapping, around the 0.5 region.
            for amount in [0.3, 0.4, 0.45, 0.49, 0.5, 0.51, 0.55, 0.6, 0.75, 1.0] {
                var explicit = RAWDevelopSettings()
                explicit.luminanceNoiseReductionAmount = amount
                line("decoder", read(try developed(source, explicit)), amount: amount)
            }
            for slider in [10.0, 20, 30, 40, 50, 60, 75, 100] {
                let routed = EditDocument(
                    effects: EffectsAdjustments(detail: DetailAdjustments(luminanceNoise: slider))
                ).routedForRendering(source: .raw, decoder: caps)
                line(
                    String(format: "slider=%3.0f", slider),
                    read(try developed(source, routed.rawDevelop)),
                    amount: routed.rawDevelop.luminanceNoiseReductionAmount)
            }
        }
    }

    // MARK: - 2. Sharpness headroom

    func testPrintSharpnessHeadroom() throws {
        for (name, source) in try sources() {
            let caps = try capabilities(source)
            print(
                "RAW-DETAIL-SHARPNESS", name,
                "supported=\(caps.isSharpnessSupported)",
                String(format: "default=%.4f headroom=%.4f", caps.sharpnessAmount, max(0, 1 - caps.sharpnessAmount)),
                "lumNRsupported=\(caps.isLuminanceNoiseReductionSupported) colNRsupported=\(caps.isColorNoiseReductionSupported)")
        }
    }

    // MARK: - 3. Engine cost

    private func percentile(_ values: [Double], _ p: Double) -> Double {
        let sorted = values.sorted()
        return sorted[min(sorted.count - 1, Int((Double(sorted.count - 1) * p).rounded()))]
    }

    private func milliseconds(_ body: () async -> Void) async -> Double {
        let clock = ContinuousClock()
        let start = clock.now
        await body()
        let d = clock.now - start
        return Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15
    }

    func testPrintEngineCost() async throws {
        let box = CGSize(width: 1024, height: 1024)
        for (name, source) in try sources() {
            for (label, make) in [
                ("LumNR decoder", { (i: Int) -> EditDocument in
                    EditDocument(effects: EffectsAdjustments(detail: DetailAdjustments(luminanceNoise: 10 + Double(i) * 3))) }),
                ("ColNR RGB   ", { (i: Int) -> EditDocument in
                    EditDocument(effects: EffectsAdjustments(detail: DetailAdjustments(colorNoise: 10 + Double(i) * 3))) }),
                ("Sharpen RGB", { (i: Int) -> EditDocument in
                    EditDocument(effects: EffectsAdjustments(detail: DetailAdjustments(sharpeningAmount: 10 + Double(i) * 3))) }),
                ("Exposure   ", { (i: Int) -> EditDocument in
                    EditDocument(light: LightAdjustments(exposure: 0.1 + Double(i) * 0.08)) }),
            ] {
                let engine = RenderEngine()
                func request(_ i: Int, _ quality: RenderQuality) -> RenderRequest {
                    RenderRequest(source: source, document: make(i), targetSize: box, quality: quality)
                }
                let first = await milliseconds { _ = await engine.makeCGImage(request(0, .interactive)) }
                var ticks: [Double] = []
                for i in 1...24 { ticks.append(await milliseconds { _ = await engine.makeCGImage(request(i, .interactive)) }) }
                let settled = await milliseconds { _ = await engine.makeCGImage(request(31, .preview)) }
                let work = await engine.workStatistics()
                let caches = await engine.cacheStatistics()
                print(
                    "RAW-DETAIL-COST", name, label,
                    String(format: "first=%.0fms tick p50=%.1fms p95=%.1fms settled=%.0fms", first, percentile(ticks, 0.5), percentile(ticks, 0.95), settled),
                    "filters=\(work.rawFilterConstructions) rawOutputs=\(work.rawOutputRequests) propertyWrites=\(work.rawPropertyWrites) developedSource hit/miss=\(caches.developedSource.hits)/\(caches.developedSource.misses)")
            }
        }
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double { min(max(self, range.lowerBound), range.upperBound) }
}

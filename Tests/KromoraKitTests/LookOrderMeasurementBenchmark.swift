import CoreImage
import XCTest

@testable import KromoraKit

/// KRMA-1178 measurements, window-independent (real engine and RAW, no `NSWindow`). Optional lane;
/// it needs local camera files (`Fixtures.localRAWURLs`) and prints numbers for `docs/LOOKS.md` and
/// `docs/TESTING.md` rather than asserting on them, apart from sanity checks.
///
/// Run: `swift test --filter LookOrderMeasurementBenchmark`.
final class LookOrderMeasurementBenchmark: TempDirectoryTestCase {

    private let box = CGSize(width: 1024, height: 1024)

    /// A strongly non-linear creative cube, so Look-before and Look-after differ visibly.
    private func creativeLUT(name: String = "creative", redGamma: Float = 1) -> CubeLUT {
        let size = 17
        var cube = [SIMD3<Float>]()
        let denom = Float(size - 1)
        for b in 0..<size {
            for g in 0..<size {
                for r in 0..<size {
                    let (x, y, z) = (Float(r) / denom, Float(g) / denom, Float(b) / denom)
                    let luma = 0.2126 * x + 0.7152 * y + 0.0722 * z
                    let s = luma * luma * (3 - 2 * luma)  // S-curve
                    cube.append(
                        SIMD3(
                            pow(min(1, max(0, s + (x - luma) * 1.15 + 0.03)), redGamma),
                            min(1, s + (y - luma) * 1.05),
                            min(1, s + (z - luma) * 0.9 - 0.02)).clamped01)
                }
            }
        }
        return CubeLUT(cube: cube, size: size, name: name)
    }

    private func sources() throws -> [(String, ImageSource)] {
        var result: [(String, ImageSource)] = []
        if let raw = Fixtures.localRAWURLs.first {
            result.append(("RAW \(raw.lastPathComponent)", ImageSource(url: raw, nativeExtent: CGSize(width: 4000, height: 3000))))
        }
        let jpg = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("realworldtest/DSC00366.JPG")
        if FileManager.default.fileExists(atPath: jpg.path) {
            result.append(("JPEG \(jpg.lastPathComponent)", ImageSource(url: jpg, nativeExtent: CGSize(width: 4000, height: 3000))))
        }
        if result.isEmpty { throw XCTSkip("no local fixtures; see Fixtures.localRAWURLs") }
        return result
    }

    private func floats(_ image: CIImage, space: WorkingSpace) -> [Float] {
        let width = Int(image.extent.width), height = Int(image.extent.height)
        var out = [Float](repeating: 0, count: width * height * 4)
        out.withUnsafeMutableBytes {
            Pixels.context.render(
                image, toBitmap: $0.baseAddress!, rowBytes: width * 16,
                bounds: image.extent, format: .RGBAf, colorSpace: space.cgColorSpace)
        }
        return out
    }

    private func stats(_ values: [Float]) -> (luma: Double, over: Double, under: Double) {
        var luma = 0.0, over = 0.0, under = 0.0, n = 0.0
        for i in stride(from: 0, to: values.count, by: 4) {
            let r = values[i], g = values[i + 1], b = values[i + 2]
            luma += Double(0.2126 * min(max(r, 0), 1) + 0.7152 * min(max(g, 0), 1) + 0.0722 * min(max(b, 0), 1))
            if max(r, g, b) > 1 { over += 1 }
            if min(r, g, b) < 0 { under += 1 }
            n += 1
        }
        return (luma / n, over / n, under / n)
    }

    func testMeasureLUTDomainClippingAndSliderResponse() throws {
        let lut = creativeLUT()
        let space = WorkingSpace.current
        let pushes: [(String, EditDocument)] = [
            ("neutral", EditDocument()),
            ("+1 EV", EditDocument(light: LightAdjustments(exposure: 1))),
            ("+60 sat", EditDocument(color: ColorAdjustments(saturation: 60))),
            ("+1 EV +60 sat +30 contrast", EditDocument(
                light: LightAdjustments(exposure: 1, contrast: 30), color: ColorAdjustments(saturation: 60))),
        ]
        print("KRMA-1178 measurement: source | corrections | corrected>1 | corrected<0 | luma(corrected) | luma(Look∘corr) | luma(corr∘Look) | mean|Δ| between orders (8-bit)")
        for (name, source) in try sources() {
            for (label, stored) in pushes {
                let routed = stored.routedForRendering(source: source.kind)
                guard let developed = RenderPipeline.developedSource(
                    source, rawDevelop: routed.rawDevelop, scale: .preview(maxSize: box))
                else { continue }
                let corrected = RenderPipeline.buildCorrectedImage(developed: developed, document: routed)
                let lookAfter = try XCTUnwrap(lut.apply(to: corrected, intensity: 1))
                let lookFirst = RenderPipeline.buildCorrectedImage(
                    developed: try XCTUnwrap(lut.apply(to: developed, intensity: 1)), document: routed)
                let c = stats(floats(corrected, space: space))
                let after = floats(lookAfter, space: space)
                let first = floats(lookFirst, space: space)
                var delta = 0.0
                for i in stride(from: 0, to: after.count, by: 4) {
                    for k in 0..<3 {
                        delta += abs(Double(min(max(after[i + k], 0), 1)) - Double(min(max(first[i + k], 0), 1))) * 255
                    }
                }
                delta /= Double(after.count / 4 * 3)
                print(String(
                    format: "KRMA-1178 | %@ | %@ | %.2f%% | %.2f%% | %.3f | %.3f | %.3f | %.2f",
                    name, label, c.over * 100, c.under * 100, c.luma,
                    stats(after).luma, stats(first).luma, delta))
            }
        }
    }

    /// Interaction cost through the real engine: median of 12 warm renders per interaction.
    func testMeasureInteractionCost() async throws {
        let lutA = creativeLUT()
        let lutB = creativeLUT(name: "alt", redGamma: 0.8)
        for (name, source) in try sources() {
            let engine = RenderEngine()
            var base = EditDocument(
                light: LightAdjustments(contrast: 15), color: ColorAdjustments(saturation: 15))
            base.lut = LUTSettings(lutID: lutA.lutID, intensity: 1)

            func time(_ label: String, _ make: (Int) -> (EditDocument, CubeLUT)) async throws {
                var samples: [Double] = []
                for tick in 0..<13 {
                    let (document, lut) = make(tick)
                    let request = RenderRequest(
                        source: source, document: document, lut: lut, targetSize: box, quality: .preview)
                    let start = ContinuousClock.now
                    let image = await engine.makeCGImage(request)
                    let elapsed = ContinuousClock.now - start
                    _ = try XCTUnwrap(image)
                    if tick > 0 {  // tick 0 pays the prefix build for this interaction
                        samples.append(Double(elapsed.components.attoseconds) / 1e15
                            + Double(elapsed.components.seconds) * 1000)
                    }
                }
                samples.sort()
                print(String(format: "KRMA-1178 cost | %@ | %@ | median %.1f ms | max %.1f ms",
                             name, label, samples[samples.count / 2], samples.last ?? 0))
            }

            _ = await engine.makeCGImage(RenderRequest(
                source: source, document: base, lut: lutA, targetSize: box, quality: .preview))
            let decodesBefore = await engine.workStatistics().rawOutputRequests
            try await time("Look intensity tick") { tick in
                var d = base; d.lut.intensity = 0.2 + 0.05 * Double(tick); return (d, lutA)
            }
            try await time("Look switch (A/B)") { tick in
                var d = base; let lut = tick.isMultiple(of: 2) ? lutB : lutA
                d.lut = LUTSettings(lutID: lut.lutID, intensity: 1); return (d, lut)
            }
            try await time("Saturation tick (pre-Look correction)") { tick in
                var d = base; d.color.saturation = 10 + Double(tick); return (d, lutA)
            }
            try await time("Clarity tick (spatial effect)") { tick in
                var d = base; d.effects.clarity = 10 + Double(tick) * 2; return (d, lutA)
            }
            try await time("Grain tick (post-prefix)") { tick in
                var d = base; d.effects.grain = GrainAdjustments(amount: 10 + Double(tick) * 3); return (d, lutA)
            }
            let work = await engine.workStatistics()
            print("KRMA-1178 cost | \(name) | RAW decoder output requests during RGB-only ticks: \(work.rawOutputRequests - decodesBefore)")
            if source.kind == .raw {
                XCTAssertEqual(work.rawOutputRequests, decodesBefore,
                               "RGB-only interactions must not re-decode the RAW")
            }
        }
    }
}

extension SIMD3 where Scalar == Float {
    fileprivate var clamped01: SIMD3<Float> {
        SIMD3(min(max(x, 0), 1), min(max(y, 0), 1), min(max(z, 0), 1))
    }
}

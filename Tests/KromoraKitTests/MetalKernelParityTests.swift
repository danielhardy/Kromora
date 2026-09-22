import CryptoKit
import Metal
import XCTest
import CoreImage
import CoreGraphics
@testable import KromoraKit

/// Golden-pixel parity for the KRMA-524 migration from deprecated CIKernel Language sources to
/// precompiled Metal libraries.
///
/// Provenance: the references in `Resources/MetalKernelGoldens/` were rendered on 2026-09-22 from
/// the pre-migration CIKL kernels (via the throwaway `GoldenGeneratorTests`, since deleted) on a
/// Metal CIContext in the current working space — the same `Pixels.bytes` pipeline these tests
/// use. Regeneration procedure: temporarily restore the CIKL sources, re-run the generator
/// inputs below (each test documents its exact input), and replace the `.rgba` files.
/// Total reference payload is ~100 KB.
///
/// Tolerance policy: Core Image is not bit-reproducible across time-separated runs — around
/// 0.0003% of bytes can move by 1 — so tolerance 1 is the floor (the house convention from
/// `PixelAssertions.swift`). Every kernel below holds tolerance 1 on Metal *except* grain:
/// the grain value-noise hash evaluates `sin` at large arguments, where single-precision range
/// reduction is implementation-defined, so the CIKL and Metal compilers produce different (but
/// equally valid) grain patterns from identical sources. Grain is therefore locked by
/// statistical parity (mean/std within 3 levels of the golden), determinism, seed sensitivity,
/// and a loose byte bound — not by exact pattern match. Amplitude, frequency response,
/// roughness character, and seed behavior are unchanged; see `KromoraCIKernels.ci.metal`.
///
/// ROI coverage: vignette, radial mask, and tone curve each have a non-zero-origin variant,
/// because those kernels carry explicit full-frame/origin handling that a origin-zero test
/// would not exercise.
final class MetalKernelParityTests: XCTestCase {

    // MARK: - Library validation (the clear CI failure when the metallib is missing/stale)

    func testCIMetallibIsBundledLoadableAndComplete() throws {
        _ = try XCTUnwrap(
            KromoraKitResourceBundle.data(forResource: "KromoraCIKernels.ci", withExtension: "metallib"),
            "KromoraCIKernels.ci.metallib is missing from the bundle — run scripts/build-metal-libraries.sh")
        XCTAssertTrue(CIKernelLibrary.isAvailable)
        let names = try XCTUnwrap(
            CIKernelLibrary.bundledKernelNames(), "bundled CI library does not load as a Core Image library")
        XCTAssertEqual(
            Set(names).intersection(CIKernelLibrary.expectedKernelNames),
            Set(CIKernelLibrary.expectedKernelNames),
            "bundled CI library is missing kernel functions: \(Set(CIKernelLibrary.expectedKernelNames).subtracting(names))")
        // Every expected kernel must actually instantiate in its declared class.
        let colorNames = ["effectsMidtoneMask", "effectsVignette", "effectsGrain", "hslMixer", "colorGrading"]
        for name in colorNames {
            XCTAssertNotNil(CIKernelLibrary.colorKernel(named: name), "color kernel \(name) failed to load")
        }
        let generalNames = ["localAnalyticMask", "localInvertMask", "localCombineMask", "applyToneCurve"]
        for name in generalNames {
            XCTAssertNotNil(CIKernelLibrary.kernel(named: name), "general kernel \(name) failed to load")
        }
        XCTAssertNil(CIKernelLibrary.colorKernel(named: "noSuchKernel"))
    }

    func testCIMetallibMatchesBundledSources() throws {
        // scripts/build-metal-libraries.sh records sha256(source); a mismatch means the .ci.metal
        // source was edited without rebuilding the checked-in library.
        let sourceURL = try XCTUnwrap(KromoraKitResourceBundle.url(
            forResource: "KromoraCIKernels.ci", withExtension: "metal"))
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let recorded = try XCTUnwrap(
            KromoraKitResourceBundle.data(forResource: "KromoraCIKernels", withExtension: "sha256"))
            .flatMap { String(data: $0, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) }
        XCTAssertEqual(
            SHA256.hash(data: Data(source.utf8)).hexString, recorded,
            "KromoraCIKernels.ci.metallib is stale — run scripts/build-metal-libraries.sh")
    }

    func testPresentationMetallibIsBundledFreshAndLoadable() throws {
        let url = try XCTUnwrap(
            KromoraKitResourceBundle.presentationMetallibURL(),
            "KromoraPresentation.metallib is missing from the bundle — run scripts/build-metal-libraries.sh")
        let recorded = try XCTUnwrap(
            KromoraKitResourceBundle.data(forResource: "KromoraPresentation", withExtension: "sha256"))
            .flatMap { String(data: $0, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) }
        // The script hashes the concatenation PreviewSurface.metal + MaskOverlay.metal, in order.
        let preview = try XCTUnwrap(KromoraKitResourceBundle.metalSource(named: "PreviewSurface"))
        let overlay = try XCTUnwrap(KromoraKitResourceBundle.metalSource(named: "MaskOverlay"))
        var hasher = SHA256()
        hasher.update(data: Data(preview.utf8))
        hasher.update(data: Data(overlay.utf8))
        XCTAssertEqual(
            hasher.finalize().hexString, recorded,
            "KromoraPresentation.metallib is stale — run scripts/build-metal-libraries.sh")
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("no Metal device")
        }
        let library = try device.makeLibrary(URL: url)
        for name in ["preview_quad_vertex", "preview_quad_fragment",
                     "mask_overlay_vertex", "mask_overlay_fragment"] {
            XCTAssertNotNil(
                library.makeFunction(name: name),
                "presentation library is missing \(name) — rebuild with scripts/build-metal-libraries.sh")
        }
    }

    /// Acceptance criteria 1 and 3 as a source gate: no deprecated CIKL compilation and no
    /// runtime Metal source compilation anywhere in the module. A shader leaves no observable
    /// trace once compiled, so — like the RenderStackTests context gate — the only way to keep
    /// runtime compilation from coming back is to look.
    func testNoRuntimeShaderSourceCompilation() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/KromoraKit")
        let enumerator = try XCTUnwrap(
            FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
        let banned = ["CIKernel(source:", "CIColorKernel(source:",
                      "makeLibrary(source:", "kernelsWithMetalString"]
        var offenders: [String] = []
        var scanned = 0
        while let url = enumerator.nextObject() as? URL {
            guard url.pathExtension == "swift" else { continue }
            scanned += 1
            let text = try String(contentsOf: url, encoding: .utf8)
            for line in text.split(separator: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.hasPrefix("//"), !trimmed.hasPrefix("///") else { continue }
                if banned.contains(where: trimmed.contains) {
                    offenders.append("\(url.lastPathComponent): \(trimmed)")
                }
            }
        }
        XCTAssertGreaterThan(scanned, 20, "expected to scan the whole module")
        XCTAssertTrue(
            offenders.isEmpty,
            "runtime shader source compilation found:\n\(offenders.joined(separator: "\n"))")
    }

    // MARK: - Golden helpers

    private struct Golden {
        let bytes: [UInt8]
        let width: Int
        let height: Int
    }

    private func golden(named name: String) throws -> Golden {
        let candidates = ["Resources/MetalKernelGoldens", "MetalKernelGoldens"]
        var url: URL?
        for subdir in candidates {
            if let found = Bundle.module.url(
                forResource: name, withExtension: "rgba", subdirectory: subdir) {
                url = found
                break
            }
        }
        let data = try XCTUnwrap(try url.map { try Data(contentsOf: $0) },
                                 "missing golden \(name).rgba")
        let manifestURL: URL? = candidates.lazy.compactMap {
            Bundle.module.url(forResource: "manifest", withExtension: "json", subdirectory: $0)
        }.first
        let manifest = try XCTUnwrap(manifestURL.map { try Data(contentsOf: $0) })
        let json = try JSONSerialization.jsonObject(with: manifest) as? [String: Any]
        let entry = ((json?["goldens"] as? [[String: Any]]) ?? []).first { $0["name"] as? String == name }
        let width = entry?["width"] as? Int ?? 0
        let height = entry?["height"] as? Int ?? 0
        XCTAssertGreaterThan(width, 0, "manifest entry missing for \(name)")
        XCTAssertEqual(data.count, width * height * 4, "golden \(name) size mismatch")
        return Golden(bytes: [UInt8](data), width: width, height: height)
    }

    private func checkGolden(
        _ image: CIImage, named name: String, tolerance: Int = 1,
        file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let golden = try golden(named: name)
        let fresh = try Pixels.bytes(of: image)
        XCTAssertEqual(
            fresh.count, golden.bytes.count,
            "\(name): byte count changed (\(fresh.count) vs \(golden.bytes.count))",
            file: file, line: line)
        assertPixelsEqual(fresh, golden.bytes, tolerance: tolerance, "golden \(name)", file: file, line: line)
    }

    private func cpuBytes(of image: CIImage) -> [UInt8] {
        let rect = image.extent.integral
        let width = Int(rect.width)
        let height = Int(rect.height)
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        let context = CIContext(options: [.useSoftwareRenderer: true])
        buffer.withUnsafeMutableBytes { raw in
            guard let base = raw.baseAddress else { return }
            context.render(
                image, toBitmap: base, rowBytes: width * 4, bounds: rect,
                format: .RGBA8, colorSpace: WorkingSpace.current.cgColorSpace)
        }
        return buffer
    }

    private func gradient(width: Int, height: Int) throws -> CIImage {
        let filter = try XCTUnwrap(CIFilter(name: "CILinearGradient"))
        filter.setValue(CIVector(x: 0, y: 0), forKey: "inputPoint0")
        filter.setValue(CIVector(x: CGFloat(width), y: CGFloat(height)), forKey: "inputPoint1")
        filter.setValue(CIColor(red: 0.9, green: 0.15, blue: 0.1), forKey: "inputColor0")
        filter.setValue(CIColor(red: 0.1, green: 0.25, blue: 0.9), forKey: "inputColor1")
        return try XCTUnwrap(filter.outputImage?.cropped(to: CGRect(x: 0, y: 0, width: width, height: height)))
    }

    // MARK: - Golden-pixel parity (Metal)

    func testVignetteMatchesGolden() throws {
        let photo = try gradient(width: 96, height: 64)
        let vignette = VignetteAdjustments(
            amount: -75, midpoint: 42, roundness: -30, feather: 72, highlights: 55)
        try checkGolden(RenderPipeline.applyVignette(vignette, to: photo), named: "vignette-origin")
    }

    func testVignetteROIEdgeMatchesGolden() throws {
        let photo = try gradient(width: 96, height: 64)
        let vignette = VignetteAdjustments(
            amount: -75, midpoint: 42, roundness: -30, feather: 72, highlights: 55)
        let roi = photo.cropped(to: CGRect(x: 16, y: 12, width: 64, height: 40))
        try checkGolden(
            RenderPipeline.applyVignette(vignette, to: roi, frameExtent: photo.extent),
            named: "vignette-roi")
    }

    func testHSLMixerMatchesGolden() throws {
        let hues: [CGFloat] = [0, 30, 60, 120, 180, 240, 270, 300]
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        var px = [UInt8]()
        for hue in hues {
            let h = hue / 60
            let (r, g, b): (CGFloat, CGFloat, CGFloat)
            switch h {
            case 0..<1: (r, g, b) = (0.8, 0.8 * (1 - abs(h - 1)), 0)
            default: (r, g, b) = (0.2, 0.3, 0.7)
            }
            px += [UInt8(r * 255), UInt8(g * 255), UInt8(b * 255), 255]
        }
        let strip = try XCTUnwrap(CIImage(
            bitmapData: Data(px), bytesPerRow: hues.count * 4,
            size: CGSize(width: hues.count, height: 1), format: .RGBA8, colorSpace: space))
        let mixer = ColorMixerAdjustments(
            red: ColorMixerChannel(hue: 20, saturation: -30, luminance: 40),
            green: ColorMixerChannel(luminance: -25),
            blue: ColorMixerChannel(hue: -15, saturation: 35, luminance: 10))
        try checkGolden(RenderPipeline.applyColorMixer(mixer, to: strip), named: "hsl-mixer")
    }

    func testColorGradingMatchesGolden() throws {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        var gpixels = [UInt8]()
        for i in 0..<32 {
            let v = UInt8(i * 255 / 31)
            gpixels += [v, v &+ 10, 255 &- v, 255]
        }
        let strip = try XCTUnwrap(CIImage(
            bitmapData: Data(gpixels), bytesPerRow: 32 * 4,
            size: CGSize(width: 32, height: 1), format: .RGBA8, colorSpace: space))
        let grading = ColorGradingAdjustments(
            shadows: ColorGradingWheel(hue: 210, saturation: 45),
            midtones: ColorGradingWheel(hue: 40, saturation: 30),
            highlights: ColorGradingWheel(hue: 0, saturation: 25),
            blending: 55, balance: -20)
        try checkGolden(RenderPipeline.applyColorGrading(grading, to: strip), named: "color-grading")
    }

    func testMidtoneMaskMatchesGolden() throws {
        let values: [CGFloat] = [0.05, 0.2, 0.35, 0.5, 0.65, 0.8, 0.95, 1.0]
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        var gray = [UInt8]()
        for v in values {
            let b = UInt8((v * 255).rounded())
            gray += [b, b, b, 255]
        }
        let strip = try XCTUnwrap(CIImage(
            bitmapData: Data(gray), bytesPerRow: values.count * 4,
            size: CGSize(width: values.count, height: 1), format: .RGBA8, colorSpace: space))
        try checkGolden(RenderPipeline.midtoneMask(for: strip, amount: 0.8), named: "midtone-mask")
    }

    func testLinearMaskMatchesGolden() throws {
        let renderer = LocalMaskRenderer()
        let payload = LocalMaskPayload(
            sourceFingerprint: "golden-linear",
            targetSize: PixelDimensions(width: 64, height: 48),
            quality: .preview,
            descriptor: .linear(LinearGradientDefinition(
                zeroStrengthPoint: CGPoint(x: 0.2, y: 0.2),
                fullStrengthPoint: CGPoint(x: 0.8, y: 0.9), density: 0.85)))
        let image = try XCTUnwrap(renderer.image(
            for: payload, extent: CGRect(x: 0, y: 0, width: 64, height: 48), transform: .identity))
        try checkGolden(image, named: "mask-linear")
    }

    func testRadialMaskROIEdgeMatchesGolden() throws {
        let renderer = LocalMaskRenderer()
        let payload = LocalMaskPayload(
            sourceFingerprint: "golden-radial",
            targetSize: PixelDimensions(width: 64, height: 48),
            quality: .preview,
            descriptor: .radial(RadialGradientDefinition(
                center: CGPoint(x: 0.5, y: 0.5), horizontalRadius: 0.35, verticalRadius: 0.25,
                rotation: 0.4, feather: 0.5, density: 0.9, isInside: true)))
        let image = try XCTUnwrap(renderer.image(
            for: payload, extent: CGRect(x: 10, y: 8, width: 64, height: 48), transform: .identity))
        try checkGolden(image, named: "mask-radial-roi")
    }

    func testInvertAndCombineMatchGoldens() throws {
        let renderer = LocalMaskRenderer()
        let base = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0.6))
            .cropped(to: CGRect(x: 0, y: 0, width: 16, height: 16))
        try checkGolden(renderer.inverted(base, extent: base.extent), named: "mask-invert")
        let other = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0.3))
            .cropped(to: base.extent)
        try checkGolden(
            renderer.combined(base, with: other, mode: .subtract, extent: base.extent),
            named: "mask-combine-subtract")
    }

    func testToneCurveMatchesGoldens() throws {
        let cache = ToneCurveFilterCache()
        let curve = LightToneCurve(points: [
            LightCurvePoint(input: 0, output: 0),
            LightCurvePoint(input: 0.25, output: 0.2),
            LightCurvePoint(input: 0.5, output: 0.55),
            LightCurvePoint(input: 0.75, output: 0.8),
            LightCurvePoint(input: 1, output: 1),
        ])
        let source = try gradient(width: 48, height: 8)
        try checkGolden(cache.apply(curve, to: source), named: "tone-curve-origin")
        let roi = source.cropped(to: CGRect(x: 8, y: 2, width: 32, height: 4))
        try checkGolden(cache.apply(curve, to: roi), named: "tone-curve-roi")
    }

    // MARK: - Grain (statistical parity; see header)

    private func grainImage(seed: UInt32) throws -> CIImage {
        let flat = CIImage(color: CIColor(red: 0.45, green: 0.4, blue: 0.38))
            .cropped(to: CGRect(x: 0, y: 0, width: 64, height: 64))
        return RenderPipeline.applyGrain(
            GrainAdjustments(amount: 70, size: 40, roughness: 60), to: flat, seed: seed)
    }

    private func meanAndStd(_ bytes: [UInt8]) -> (mean: Double, std: Double) {
        var mean = 0.0
        for b in bytes { mean += Double(b) }
        mean /= Double(bytes.count)
        var sum2 = 0.0
        for b in bytes { sum2 += (Double(b) - mean) * (Double(b) - mean) }
        return (mean, (sum2 / Double(bytes.count)).squareRoot())
    }

    func testGrainKeepsGoldenStatistics() throws {
        // Golden stats (CIKL render): mean 142.07, std 65.67. Same character, new pattern.
        let golden = try golden(named: "grain-seed")
        let (goldenMean, goldenStd) = meanAndStd(golden.bytes)
        let fresh = try Pixels.bytes(of: grainImage(seed: 123456789))
        let (mean, std) = meanAndStd(fresh)
        XCTAssertEqual(mean, goldenMean, accuracy: 3.0, "grain mean drifted: \(mean) vs golden \(goldenMean)")
        XCTAssertEqual(std, goldenStd, accuracy: 3.0, "grain spread drifted: \(std) vs golden \(goldenStd)")
        // Loose byte bound (measured worst delta 29 on both renderers): trips only on a
        // gross change (flat field, missing octave, ...).
        assertPixelsEqual(fresh, golden.bytes, tolerance: 32, "grain-seed")
    }

    func testGrainIsDeterministicAndSeedSensitive() throws {
        let first = try Pixels.bytes(of: grainImage(seed: 123456789))
        let second = try Pixels.bytes(of: grainImage(seed: 123456789))
        assertPixelsEqual(first, second, tolerance: 0, "same seed must render identical grain")
        let other = try Pixels.bytes(of: grainImage(seed: 987654321))
        assertPixelsDiffer(first, other, "different seeds must produce different grain")
    }

    // MARK: - Software-renderer parity (the CPU compatibility seam)

    func testMigratedKernelsRenderOnTheSoftwareRenderer() throws {
        // The precompiled library must serve the CPU path too, not just Metal. Tolerance 2
        // covers the CPU/GPU 1-LSB boundary on top of the cross-run floor.
        let photo = try gradient(width: 96, height: 64)
        let vignette = VignetteAdjustments(
            amount: -75, midpoint: 42, roundness: -30, feather: 72, highlights: 55)
        let cases: [(CIImage, String)] = [
            (RenderPipeline.applyVignette(vignette, to: photo), "vignette-origin"),
            (RenderPipeline.applyGrain(
                GrainAdjustments(amount: 70, size: 40, roughness: 60),
                to: CIImage(color: CIColor(red: 0.45, green: 0.4, blue: 0.38))
                    .cropped(to: CGRect(x: 0, y: 0, width: 64, height: 64)),
                seed: 123456789), "grain-seed"),
        ]
        for (image, name) in cases {
            let golden = try golden(named: name)
            let fresh = cpuBytes(of: image)
            XCTAssertEqual(fresh.count, golden.bytes.count, "\(name) on CPU: byte count changed")
            assertPixelsEqual(
                fresh, golden.bytes,
                tolerance: name == "grain-seed" ? 32 : 2, "\(name) on CPU")
        }
    }
}

private extension Digest {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}

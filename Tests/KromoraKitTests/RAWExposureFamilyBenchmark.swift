import CoreImage
import XCTest

@testable import KromoraKit

/// Opt-in visual-validation numbers behind the per-family Exposure calibration (KRMA-1180). For each
/// local RAW it renders the shipped routing (the Exposure slider through the decoder, calibrated for
/// the file's family) and the RGB path (`CIExposureAdjust` on developed RGB) at matched slider EV, with
/// the Look off and on, through the real `RenderEngine`, and prints per-frame statistics:
///
/// - `mean` / `p50`: encoded luma (0–255) so the two paths can be compared at matched midtones;
/// - `hiClip`: share of pixels with any channel ≥ 253; `crush`: share with every channel ≤ 2;
/// - `chroma`: mean (max − min) of mid-luma pixels (40…215), a colour-saturation proxy;
/// - `rb`, `bg`: channel balance, mean R / mean G and mean B / mean G;
/// - `hiGrad`, `loGrad`: mean luma gradient magnitude among pixels above 200 / below 50, a channel-
///   detail proxy for highlight and shadow separation.
///
/// Different tone is *not* evidence of recovered sensor detail; these numbers describe the two
/// renderings, they do not rank them. Needs `KROMORA_RAW_FIXTURE_DIR` or `realworldtest/`.
final class RAWExposureFamilyBenchmark: XCTestCase {
    private let box = CGSize(width: 1024, height: 1024)

    private struct Stats {
        var mean = 0.0
        var p50 = 0.0
        var hiClip = 0.0
        var crush = 0.0
        var chroma = 0.0
        var rb = 0.0
        var bg = 0.0
        var hiGrad = 0.0
        var loGrad = 0.0

        var line: String {
            String(
                format: "mean=%5.1f p50=%5.1f hiClip=%5.2f%% crush=%5.2f%% chroma=%5.1f rb=%.3f bg=%.3f hiGrad=%5.2f loGrad=%5.2f",
                mean, p50, hiClip * 100, crush * 100, chroma, rb, bg, hiGrad, loGrad)
        }
    }

    private func stats(_ image: CGImage) throws -> Stats {
        let pixels = try Pixels.bytes(of: image)
        let width = image.width
        let height = image.height
        var luma = [Float](repeating: 0, count: width * height)
        var sumR = 0.0, sumG = 0.0, sumB = 0.0
        var clip = 0, crush = 0, midCount = 0
        var chroma = 0.0
        for i in 0..<luma.count {
            let r = Int(pixels[i * 4]), g = Int(pixels[i * 4 + 1]), b = Int(pixels[i * 4 + 2])
            sumR += Double(r); sumG += Double(g); sumB += Double(b)
            let y = 0.2126 * Float(r) + 0.7152 * Float(g) + 0.0722 * Float(b)
            luma[i] = y
            if max(r, g, b) >= 253 { clip += 1 }
            if max(r, g, b) <= 2 { crush += 1 }
            if y >= 40, y <= 215 {
                chroma += Double(max(r, g, b) - min(r, g, b))
                midCount += 1
            }
        }
        var hiSum = 0.0, hiN = 0.0, loSum = 0.0, loN = 0.0
        for y in 0..<(height - 1) {
            for x in 0..<(width - 1) {
                let i = y * width + x
                let gradient = Double(abs(luma[i + 1] - luma[i]) + abs(luma[i + width] - luma[i]))
                if luma[i] >= 200 { hiSum += gradient; hiN += 1 }
                if luma[i] <= 50 { loSum += gradient; loN += 1 }
            }
        }
        let total = Double(luma.count)
        let sorted = luma.sorted()
        var result = Stats()
        result.mean = Double(luma.reduce(0, +)) / total
        result.p50 = Double(sorted[sorted.count / 2])
        result.hiClip = Double(clip) / total
        result.crush = Double(crush) / total
        result.chroma = midCount > 0 ? chroma / Double(midCount) : 0
        result.rb = sumG > 0 ? sumR / sumG : 0
        result.bg = sumG > 0 ? sumB / sumG : 0
        result.hiGrad = hiN > 0 ? hiSum / hiN : 0
        result.loGrad = loN > 0 ? loSum / loN : 0
        return result
    }

    private func look() throws -> CubeLUT {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let cube = repoRoot.appendingPathComponent("realworldtest/DSC03293_recipe_33_Rec709.cube")
        if FileManager.default.fileExists(atPath: cube.path), let lut = try? CubeLUT(url: cube) {
            return lut
        }
        return TestImages.warmLUT()
    }

    func testPrintFamilyComparison() async throws {
        let urls = Fixtures.localRAWURLs
        guard !urls.isEmpty else { throw XCTSkip("no local RAWs; see Fixtures.localRAWURLs") }
        let lut = try look()
        let lookSettings = LUTSettings(lutID: LUTID(raw: lut.id), intensity: 1)
        for url in urls {
            let source = ImageSource(url: url, nativeExtent: CGSize(width: 6000, height: 4000))
            let engine = RenderEngine()
            let capabilities = await engine.rawCapabilities(for: source)
            let family = RAWExposureRouting.stopsPerSliderStop(decoder: capabilities)
            func render(_ document: EditDocument, withLook: Bool) async throws -> Stats {
                var document = document
                if withLook { document.lut = lookSettings }
                let request = RenderRequest(
                    source: source, document: document, lut: withLook ? lut : nil,
                    targetSize: box, quality: .preview)
                let image = await engine.makeCGImage(request)
                return try stats(try XCTUnwrap(image))
            }
            for withLook in [false, true] {
                let neutral = try await render(EditDocument(), withLook: withLook)
                print("RAW-EXPOSURE-FAMILY", url.lastPathComponent, "ratio=\(family)", "look=\(withLook)", "neutral", neutral.line)
                for ev in [-3.0, -2, -1, -0.5, -0.25, 0.25, 0.5, 1, 2, 3] {
                    let decoder = try await render(
                        EditDocument(light: LightAdjustments(exposure: ev)), withLook: withLook)
                    let rgb = try await render(
                        EditDocument(adjustments: [.exposure(ev: ev)]), withLook: withLook)
                    print("RAW-EXPOSURE-FAMILY", url.lastPathComponent, String(format: "ev=%+.2f", ev), "look=\(withLook)", "decoder", decoder.line)
                    print("RAW-EXPOSURE-FAMILY", url.lastPathComponent, String(format: "ev=%+.2f", ev), "look=\(withLook)", "rgb    ", rgb.line)
                }
            }
        }
    }
}

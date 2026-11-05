import CoreImage
import XCTest

@testable import KromoraKit

/// Opt-in measurement behind `RAWExposureRouting`'s calibration (KRMA-1174). It develops each local
/// RAW at screen scale, then finds the decoder exposure whose whole-frame median linear luminance
/// matches `CIExposureAdjust` at each slider EV. Needs `KROMORA_RAW_FIXTURE_DIR` or `realworldtest/`.
final class RAWExposureCalibrationBenchmark: XCTestCase {
    private let context = CIContext(options: [
        .workingColorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!,
        .workingFormat: CIFormat.RGBAf,
    ])

    private func medianLuminance(_ image: CIImage) -> Double {
        let extent = image.extent.integral
        let width = Int(extent.width)
        let height = Int(extent.height)
        var pixels = [Float](repeating: 0, count: width * height * 4)
        context.render(
            image, toBitmap: &pixels, rowBytes: width * 16, bounds: extent, format: .RGBAf,
            colorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!)
        var lumas = [Float](repeating: 0, count: width * height)
        for i in 0..<lumas.count {
            lumas[i] = 0.2126 * pixels[i * 4] + 0.7152 * pixels[i * 4 + 1] + 0.0722 * pixels[i * 4 + 2]
        }
        lumas.sort()
        return Double(lumas[lumas.count / 2])
    }

    func testPrintCalibrationTable() throws {
        let urls = Fixtures.localRAWURLs
        guard !urls.isEmpty else { throw XCTSkip("no local RAWs") }
        let scale = RenderScale.preview(maxSize: CGSize(width: 800, height: 800))
        for url in urls {
            let source = ImageSource(url: url, nativeExtent: CGSize(width: 4000, height: 3000))
            func develop(_ ev: Double?) -> CIImage? {
                RenderPipeline.developedSource(
                    source, rawDevelop: RAWDevelopSettings(exposure: ev), scale: scale)
            }
            guard let neutral = develop(nil) else { continue }
            let m0 = medianLuminance(neutral)
            var line = "\(url.lastPathComponent) m0=\(String(format: "%.4f", m0))"
            for slider in stride(from: -4.0, through: 4.0, by: 1.0) where slider != 0 {
                let rgb = CIFilter.exposureAdjust()
                rgb.inputImage = neutral
                rgb.ev = Float(slider)
                let target = medianLuminance(rgb.outputImage!)
                var lo = -8.0, hi = 8.0
                for _ in 0..<14 {
                    let mid = (lo + hi) / 2
                    let m = medianLuminance(develop(mid)!)
                    if m < target { lo = mid } else { hi = mid }
                }
                line += String(format: " | %+.0f→%+.2f", slider, (lo + hi) / 2)
            }
            print("CALIBRATION", line)
        }
    }
}

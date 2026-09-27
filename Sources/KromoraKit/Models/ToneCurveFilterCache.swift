import CoreImage
import Foundation

/// Actor-confined Core Image resource for the separable master RGB curve.
///
/// The kernel is compiled once and the curve is represented by one 256×1 texture (4 KiB), rather
/// than by a 64³ RGBA cube (4 MiB). `CIFilter`/`CIKernel`/`CIImage` are deliberately not Sendable;
/// the owning `RenderEngine` actor serializes access to this cache.
final class ToneCurveFilterCache {
    private static let sampleCount = 256
    // Precompiled Metal kernel (Sources/KromoraKit/Resources/KromoraCIKernels.ci.metal).
    private static let kernel = CIKernelLibrary.kernel(named: "applyToneCurve")

    private var curves: [LightToneCurve]?
    private var parametric: ParametricToneCurve?
    private var sampledData: Data?
    private var sampledImage: CIImage?

    func apply(_ curve: LightToneCurve, to image: CIImage) -> CIImage {
        apply(curve, red: .identity, green: .identity, blue: .identity,
              parametric: .neutral, to: image)
    }

    /// Applies the latest curve. Reusing the compiled kernel and replacing only this small texture
    /// makes curve ticks bounded by the sample count, not by the cube volume.
    func apply(_ master: LightToneCurve, red: LightToneCurve, green: LightToneCurve,
               blue: LightToneCurve, parametric: ParametricToneCurve, to image: CIImage) -> CIImage {
        let nextCurves = [master, red, green, blue]
        if curves != nextCurves || self.parametric != parametric || sampledImage == nil || sampledData == nil {
            var samples = [Float](repeating: 0, count: Self.sampleCount * 4)
            for index in 0..<Self.sampleCount {
                let offset = index * 4
                let input = Double(index) / Double(Self.sampleCount - 1)
                let masterValue = master.value(at: parametric.value(at: input))
                samples[offset] = Float(red.value(at: masterValue))
                samples[offset + 1] = Float(green.value(at: masterValue))
                samples[offset + 2] = Float(blue.value(at: masterValue))
                samples[offset + 3] = 1
            }
            sampledData = samples.withUnsafeBytes { Data($0) }
            sampledImage = sampledData.flatMap {
                CIImage(
                    bitmapData: $0, bytesPerRow: Self.sampleCount * 4 * MemoryLayout<Float>.size,
                    size: CGSize(width: Self.sampleCount, height: 1), format: .RGBAf,
                    colorSpace: nil)
            }
            curves = nextCurves
            self.parametric = parametric
        }

        guard let kernel = Self.kernel, let sampledImage else { return image }

        // `samplerCoord(image)` is in the sampler's local space. A committed crop (or any ROI)
        // leaves a non-zero CIImage origin; sampling that origin as if it were (0,0) reads empty
        // tiles and the preview goes black. Run the kernel on an origin-zero copy, then put the
        // extent back so later crop/presentation math still matches.
        let origin = image.extent.origin
        let working: CIImage
        if origin.x == 0, origin.y == 0 {
            working = image
        } else {
            working = image.transformed(
                by: CGAffineTransform(translationX: -origin.x, y: -origin.y))
        }
        let curved =
            kernel.apply(
                extent: working.extent, roiCallback: { _, rect in rect },
                arguments: [working, sampledImage]
            ) ?? working
        if origin.x == 0, origin.y == 0 {
            return curved
        }
        return curved.transformed(
            by: CGAffineTransform(translationX: origin.x, y: origin.y))
    }

    /// Explicitly drops the texture when the source or working-space boundary is invalidated.
    func removeAll() {
        curves = nil
        parametric = nil
        sampledData = nil
        sampledImage = nil
    }

}

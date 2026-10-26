import CoreGraphics
import Foundation

/// Where an image's pixels sit relative to the sRGB and Display P3 gamuts (KRMA-1132).
///
/// Pure and `Sendable`: no Core Image and no `CGImage`. It tallies a bounded pixel sample; the Info
/// inspector gets the production extended-linear sample from `RenderEngine` and only receives
/// Sendable pixel values.
///
/// Pixels are binned into a fixed `gridSize` x `gridSize` grid on the CIE 1976 u'v' chromaticity
/// plane (more perceptually even than xy), so the view draws density, never individual pixels.
///
/// The RGBA8 initializer can show "outside sRGB" but cannot measure beyond P3. The production
/// linear-float initializer accepts extended-range values and measures both shares.
struct GamutTally: Equatable, Sendable {
    static let gridSize = 64
    /// Plot extent in u'v'. Covers the spectral locus (u' <= 0.623, v' <= 0.587).
    static let uRange: ClosedRange<Double> = 0...0.65
    static let vRange: ClosedRange<Double> = 0...0.6

    /// Linear components further than this outside 0...1 count as out of gamut. Absorbs the 8-bit
    /// quantization of an sRGB color stored as P3, which can land a hair past the boundary.
    static let defaultTolerance: Float = 0.01
    /// Float render samples have no 8-bit quantization, so only absorb color-matrix/raster noise.
    static let linearSampleTolerance: Float = 0.0001

    /// Whether the sample could register colors beyond Display P3.
    let measuresBeyondP3: Bool
    let pixelCount: Int
    let outsideSRGBCount: Int
    let outsideP3Count: Int
    /// Row-major `gridSize * gridSize` counts, row 0 at v' = `vRange.lowerBound`.
    let density: [Int]

    var outsideSRGBFraction: Double { Self.fraction(outsideSRGBCount, of: pixelCount) }
    var outsideP3Fraction: Double { Self.fraction(outsideP3Count, of: pixelCount) }
    var densityPeak: Int { density.max() ?? 0 }

    private static func fraction(_ count: Int, of total: Int) -> Double {
        total > 0 ? Double(count) / Double(total) : 0
    }

    // MARK: Color math

    /// Linear Display P3 to XYZ (D65).
    private static func xyz(fromLinearP3 c: SIMD3<Float>) -> SIMD3<Float> {
        SIMD3(
            0.4865709 * c.x + 0.2656677 * c.y + 0.1982173 * c.z,
            0.2289746 * c.x + 0.6917385 * c.y + 0.0792869 * c.z,
            0.0451134 * c.y + 1.0439444 * c.z
        )
    }

    /// XYZ (D65) to linear sRGB.
    private static func linearSRGB(fromXYZ v: SIMD3<Float>) -> SIMD3<Float> {
        SIMD3(
            3.2404542 * v.x - 1.5371385 * v.y - 0.4985314 * v.z,
            -0.9692660 * v.x + 1.8760108 * v.y + 0.0415560 * v.z,
            0.0556434 * v.x - 0.2040259 * v.y + 1.0572252 * v.z
        )
    }

    private static func luvChromaticity(of v: SIMD3<Float>) -> (u: Double, v: Double)? {
        let d = Double(v.x) + 15 * Double(v.y) + 3 * Double(v.z)
        guard d > 1e-9 else { return nil }
        return (4 * Double(v.x) / d, 9 * Double(v.y) / d)
    }

    /// u'v' of the sRGB primaries (red, green, blue), for drawing the sRGB triangle.
    static var sRGBPrimaries: [CGPoint] {
        [
            SIMD3<Float>(0.4124564, 0.2126729, 0.0193339),
            SIMD3<Float>(0.3575761, 0.7151522, 0.1191920),
            SIMD3<Float>(0.1804375, 0.0721750, 0.9503041),
        ].compactMap(luvChromaticity(of:)).map { CGPoint(x: $0.u, y: $0.v) }
    }

    /// u'v' of the Display P3 primaries (red, green, blue).
    static var displayP3Primaries: [CGPoint] {
        [SIMD3<Float>(1, 0, 0), SIMD3<Float>(0, 1, 0), SIMD3<Float>(0, 0, 1)]
            .compactMap { luvChromaticity(of: xyz(fromLinearP3: $0)) }
            .map { CGPoint(x: $0.u, y: $0.v) }
    }

    /// The sRGB transfer function's inverse, for a 0...1 encoded value.
    private static let decodeTable: [Float] = (0...255).map { i in
        let e = Float(i) / 255
        return e <= 0.04045 ? e / 12.92 : powf((e + 0.055) / 1.055, 2.4)
    }

    // MARK: Tally

    /// Tally packed RGB bytes (3 per pixel) encoded in Display P3, as `HistogramData.samples` is.
    init(displayP3Samples samples: [UInt8], tolerance: Float = GamutTally.defaultTolerance) {
        let count = samples.count / 3
        var builder = Builder(measuresBeyondP3: false, tolerance: tolerance)
        samples.withUnsafeBufferPointer { buf in
            for i in 0..<count {
                let linear = SIMD3(
                    Self.decodeTable[Int(buf[i * 3])],
                    Self.decodeTable[Int(buf[i * 3 + 1])],
                    Self.decodeTable[Int(buf[i * 3 + 2])]
                )
                builder.add(linearP3: linear)
            }
        }
        self = builder.finish()
    }

    /// Tally linear, extended-range Display P3 pixels. Components outside 0...1 are out of P3.
    init(linearDisplayP3 pixels: [SIMD3<Float>], tolerance: Float = GamutTally.linearSampleTolerance) {
        var builder = Builder(measuresBeyondP3: true, tolerance: tolerance)
        for pixel in pixels { builder.add(linearP3: pixel) }
        self = builder.finish()
    }

    private init(measuresBeyondP3: Bool, pixelCount: Int, outsideSRGBCount: Int,
                 outsideP3Count: Int, density: [Int]) {
        self.measuresBeyondP3 = measuresBeyondP3
        self.pixelCount = pixelCount
        self.outsideSRGBCount = outsideSRGBCount
        self.outsideP3Count = outsideP3Count
        self.density = density
    }

    private struct Builder {
        let measuresBeyondP3: Bool
        let tolerance: Float
        var pixelCount = 0
        var outsideSRGB = 0
        var outsideP3 = 0
        var density = [Int](repeating: 0, count: GamutTally.gridSize * GamutTally.gridSize)

        init(measuresBeyondP3: Bool, tolerance: Float) {
            self.measuresBeyondP3 = measuresBeyondP3
            self.tolerance = tolerance
        }

        mutating func add(linearP3 c: SIMD3<Float>) {
            pixelCount += 1
            let lo = -tolerance
            let hi = 1 + tolerance
            if measuresBeyondP3, c.min() < lo || c.max() > hi { outsideP3 += 1 }
            let xyz = GamutTally.xyz(fromLinearP3: c)
            let s = GamutTally.linearSRGB(fromXYZ: xyz)
            if s.min() < lo || s.max() > hi { outsideSRGB += 1 }
            guard let uv = GamutTally.luvChromaticity(of: xyz) else { return }
            let n = Double(GamutTally.gridSize)
            let fu = (uv.u - GamutTally.uRange.lowerBound)
                / (GamutTally.uRange.upperBound - GamutTally.uRange.lowerBound)
            let fv = (uv.v - GamutTally.vRange.lowerBound)
                / (GamutTally.vRange.upperBound - GamutTally.vRange.lowerBound)
            let x = min(GamutTally.gridSize - 1, max(0, Int(fu * n)))
            let y = min(GamutTally.gridSize - 1, max(0, Int(fv * n)))
            density[y * GamutTally.gridSize + x] += 1
        }

        func finish() -> GamutTally {
            GamutTally(measuresBeyondP3: measuresBeyondP3, pixelCount: pixelCount,
                       outsideSRGBCount: outsideSRGB, outsideP3Count: outsideP3, density: density)
        }
    }
}

/// A bounded sample of the edited render in extended-range linear Display P3, produced on demand by
/// `RenderEngine` for the Info gamut view. Values outside 0...1 are kept.
struct GamutSample: Sendable, Equatable {
    let linearDisplayP3: [SIMD3<Float>]
}

import CoreGraphics
import Foundation

struct PixelReadout: Equatable, Sendable {
    let x: Int
    let y: Int
    let red: UInt8
    let green: UInt8
    let blue: UInt8
    let lab: (l: Double, a: Double, b: Double)

    static func == (lhs: PixelReadout, rhs: PixelReadout) -> Bool {
        lhs.x == rhs.x && lhs.y == rhs.y && lhs.red == rhs.red
            && lhs.green == rhs.green && lhs.blue == rhs.blue
            && lhs.lab.l == rhs.lab.l && lhs.lab.a == rhs.lab.a && lhs.lab.b == rhs.lab.b
    }
}

/// Per-channel tonal distribution of an image, in 256 bins (one per 8-bit
/// level). Computed from a downscaled RGBA8 render — see
/// `RenderEngine.histogram(source:document:lut:scale:space:maxDimension:)`.
///
/// `Sendable` because the tally happens inside `actor RenderEngine`, where the `CIContext` lives,
/// and the result crosses back to the main actor to be published.
struct HistogramData: Equatable, Sendable {

    /// Bounded row-major RGB samples from the exact rendered preview represented by this
    /// histogram. Keeping these samples lets the inspector draw spatial scopes and answer cursor
    /// queries without asking the renderer for another image or retaining framework objects.
    let samples: [UInt8]
    let sampleWidth: Int
    let sampleHeight: Int

    /// Channels a histogram view can draw.
    enum Channel: CaseIterable {
        case red, green, blue, luma
    }

    let red: [Int]
    let green: [Int]
    let blue: [Int]
    /// Rec. 709 luminance (0.2126R + 0.7152G + 0.0722B).
    let luma: [Int]

    let clippedHighlights: Int
    let clippedShadows: Int
    let clippedRed: Int
    let clippedGreen: Int
    let clippedBlue: Int

    var binCount: Int { red.count }

    init(red: [Int], green: [Int], blue: [Int], luma: [Int],
         samples: [UInt8] = [], sampleWidth: Int = 0, sampleHeight: Int = 0,
         clippedHighlights: Int = 0, clippedShadows: Int = 0,
         clippedRed: Int = 0, clippedGreen: Int = 0, clippedBlue: Int = 0) {
        self.red = red
        self.green = green
        self.blue = blue
        self.luma = luma
        self.samples = samples
        self.sampleWidth = sampleWidth
        self.sampleHeight = sampleHeight
        self.clippedHighlights = clippedHighlights
        self.clippedShadows = clippedShadows
        self.clippedRed = clippedRed
        self.clippedGreen = clippedGreen
        self.clippedBlue = clippedBlue
    }

    /// Tally an already-rasterized RGBA8 buffer.
    ///
    /// Pure — no `CIContext`, no `CGImage`, no framework at all. Rasterizing is the caller's job
    /// (`RenderEngine`, which owns the one context); counting bytes is not, and keeping the two apart
    /// is what lets the arithmetic below be tested against a hand-built buffer rather than against
    /// whatever a decoder happened to produce.
    ///
    /// Returns `nil` for a buffer that cannot hold `height` rows of `bytesPerRow`.
    init?(rgba8 bytes: [UInt8], width: Int, height: Int, bytesPerRow: Int? = nil) {
        let stride = bytesPerRow ?? width * 4
        guard width > 0, height > 0, stride >= width * 4, bytes.count >= height * stride else {
            return nil
        }

        var red = [Int](repeating: 0, count: 256)
        var green = [Int](repeating: 0, count: 256)
        var blue = [Int](repeating: 0, count: 256)
        var luma = [Int](repeating: 0, count: 256)
        var clippedHighlights = 0
        var clippedShadows = 0
        var clippedRed = 0
        var clippedGreen = 0
        var clippedBlue = 0

        bytes.withUnsafeBufferPointer { buf in
            for y in 0..<height {
                let row = y * stride
                for x in 0..<width {
                    let off = row + x * 4
                    let r = Int(buf[off])
                    let g = Int(buf[off + 1])
                    let b = Int(buf[off + 2])
                    if r == 255 { clippedRed += 1 }
                    if g == 255 { clippedGreen += 1 }
                    if b == 255 { clippedBlue += 1 }
                    if r == 255 || g == 255 || b == 255 { clippedHighlights += 1 }
                    if r == 0 && g == 0 && b == 0 { clippedShadows += 1 }
                    red[r] += 1
                    green[g] += 1
                    blue[b] += 1
                    // Rec.709 luma, rounded to nearest bin.
                    let l = (2126 * r + 7152 * g + 722 * b + 5000) / 10000
                    luma[min(255, l)] += 1
                }
            }
        }

        var samples = [UInt8](repeating: 0, count: width * height * 3)
        for y in 0..<height {
            for x in 0..<width {
                let from = y * stride + x * 4
                let to = (y * width + x) * 3
                samples[to] = bytes[from]
                samples[to + 1] = bytes[from + 1]
                samples[to + 2] = bytes[from + 2]
            }
        }
        self.init(red: red, green: green, blue: blue, luma: luma,
                  samples: samples, sampleWidth: width, sampleHeight: height,
                  clippedHighlights: clippedHighlights, clippedShadows: clippedShadows,
                  clippedRed: clippedRed, clippedGreen: clippedGreen, clippedBlue: clippedBlue)
    }

    func bins(for channel: Channel) -> [Int] {
        switch channel {
        case .red: return red
        case .green: return green
        case .blue: return blue
        case .luma:  return luma
        }
    }

    /// Cursor samples use encoded sRGB 8-bit values and CIE Lab (D65, 2° observer).
    func readout(x: Int, y: Int) -> PixelReadout? {
        guard x >= 0, y >= 0, x < sampleWidth, y < sampleHeight,
              samples.count >= sampleWidth * sampleHeight * 3 else { return nil }
        let offset = (y * sampleWidth + x) * 3
        let r = Double(samples[offset]) / 255
        let g = Double(samples[offset + 1]) / 255
        let b = Double(samples[offset + 2]) / 255
        func linear(_ value: Double) -> Double {
            value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        let rl = linear(r), gl = linear(g), bl = linear(b)
        let xyzX = (0.4124564 * rl + 0.3575761 * gl + 0.1804375 * bl) / 0.95047
        let xyzY = 0.2126729 * rl + 0.7151522 * gl + 0.0721750 * bl
        let xyzZ = (0.0193339 * rl + 0.1191920 * gl + 0.9503041 * bl) / 1.08883
        func labCurve(_ value: Double) -> Double {
            value > 216.0 / 24389.0 ? cbrt(value) : (24389.0 / 27.0 * value + 16) / 116
        }
        let fx = labCurve(xyzX), fy = labCurve(xyzY), fz = labCurve(xyzZ)
        return PixelReadout(x: x, y: y, red: samples[offset], green: samples[offset + 1],
                            blue: samples[offset + 2],
                            lab: (116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz)))
    }

    /// Display ceiling used to scale bar heights. The pure-black (0) and
    /// pure-white (255) bins are excluded so a single clipping spike doesn't
    /// flatten the rest of the curve into the floor. Falls back to the absolute
    /// max if the interior is empty.
    private static func displayMax(_ channels: [[Int]]) -> Int {
        var interior = 0
        var absolute = 0
        for bins in channels {
            guard bins.count > 2 else { continue }
            for (i, v) in bins.enumerated() {
                absolute = max(absolute, v)
                if i > 0 && i < bins.count - 1 { interior = max(interior, v) }
            }
        }
        return interior > 0 ? interior : absolute
    }

    /// Bars normalized to 0...1 for drawing, scaled by the appropriate ceiling.
    func normalized(_ channel: Channel) -> [CGFloat] {
        let ceiling = channel == .luma ? HistogramData.displayMax([luma])
                                        : HistogramData.displayMax([red, green, blue])
        guard ceiling > 0 else { return Array(repeating: 0, count: binCount) }
        let denom = CGFloat(ceiling)
        return bins(for: channel).map { min(1, CGFloat($0) / denom) }
    }
}

/// A histogram whose bins retain fractional weights. The renderer uses this for soft semantic
/// masks: a pixel at the edge of a feathered mask contributes proportionally instead of being
/// rounded to an all-or-nothing inclusion.
struct WeightedHistogramData: Equatable, Sendable {
    let red: [Double]
    let green: [Double]
    let blue: [Double]
    let luma: [Double]

    init(red: [Double], green: [Double], blue: [Double], luma: [Double]) {
        self.red = red
        self.green = green
        self.blue = blue
        self.luma = luma
    }

    var totalWeight: Double { luma.reduce(0, +) }

    /// Tally a rendered RGBA8 image against a canonical-resolution mask. This is the one raster
    /// boundary where pixels and mask values meet; all downstream statistics operate on bins only.
    init?(
        rgba8 bytes: [UInt8], width: Int, height: Int, bytesPerRow: Int? = nil,
        mask: NormalizedMask
    ) {
        let stride = bytesPerRow ?? width * 4
        guard width > 0, height > 0, stride >= width * 4,
              bytes.count >= height * stride, mask.size.width == width,
              mask.size.height == height else { return nil }

        var red = [Double](repeating: 0, count: 256)
        var green = [Double](repeating: 0, count: 256)
        var blue = [Double](repeating: 0, count: 256)
        var luma = [Double](repeating: 0, count: 256)

        bytes.withUnsafeBufferPointer { buffer in
            for y in 0..<height {
                let row = y * stride
                let maskRow = y * width
                for x in 0..<width {
                    let weight = Double(mask.values[maskRow + x])
                    guard weight > 0 else { continue }
                    let offset = row + x * 4
                    let r = Int(buffer[offset])
                    let g = Int(buffer[offset + 1])
                    let b = Int(buffer[offset + 2])
                    red[r] += weight
                    green[g] += weight
                    blue[b] += weight
                    let level = min(255, (2126 * r + 7152 * g + 722 * b + 5000) / 10000)
                    luma[level] += weight
                }
            }
        }

        self.init(red: red, green: green, blue: blue, luma: luma)
    }
}

import CoreGraphics
import Foundation

/// Bounded, deterministic camera-scale crops with known clean references for the retouch
/// diagnostics (KRMA-1061). Each case is a 1800 × 1200 crop at native pixel pitch (the size of a
/// 1:1 region of a 24 MP frame) with a texture whose features span tens of pixels, per-pixel grain,
/// and a thin hair, a soft dust disc, or a hard speck. Nothing is committed: pixels come from fixed
/// coordinates and an integer hash.
enum RetouchCameraScaleFixtures {
    struct Case {
        let background: String
        let defect: String
        let width: Int
        let height: Int
        let clean: [UInt8]
        let damaged: [UInt8]
        let mask: [Bool]
        /// Brush samples, normalized from the top-left like `BrushSample` elsewhere.
        let stroke: [CGPoint]
        /// Brush radius normalized by the short side.
        let radius: Double
        let radiusPixels: Double
        /// Known clean source, as a pixel displacement in image (y-down) coordinates.
        let manualPixelOffset: CGPoint
        /// Window around the defect that metrics and renders are restricted to.
        let window: CGRect

        var manualOffset: CGVector {
            CGVector(dx: manualPixelOffset.x / CGFloat(width), dy: -manualPixelOffset.y / CGFloat(height))
        }
        /// The limit set the quality oracle uses for this background.
        var limitKey: String { background == "edge" ? "cloud" : background }
        var name: String { "\(background) / \(defect)" }
    }

    static let width = 1800
    static let height = 1200
    static let backgrounds = ["sky", "foliage", "skin", "edge"]
    /// Supported v1 defect classes only: thin hair/fibre, soft dust, hard speck.
    static let defects = ["hair", "long hair", "soft dust", "hard speck"]

    static func make(background: String, defect: String, seed: UInt32 = 658) -> Case {
        let width = Self.width, height = Self.height
        func hash(_ x: Int, _ y: Int) -> Double {
            var n = UInt32(truncatingIfNeeded: x &* 1_103_515_245 &+ y &* 12_345) ^ seed
            n = (n ^ (n >> 16)) &* 0x7feb352d
            n = (n ^ (n >> 15)) &* 0x846ca68b
            n ^= n >> 16
            return Double(n & 0xffff) / 65535 - 0.5
        }
        var clean = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height { for x in 0..<width {
            let fx = Double(x), fy = Double(y)
            let grain = hash(x, y) * 0.03
            let rgb: (Double, Double, Double)
            switch background {
            case "sky":
                let wisp = sin(fx / 210 + sin(fy / 140) * 1.5) * 0.015
                rgb = (0.48 + fy / 1200 * 0.24 + wisp, 0.67 + fy / 1200 * 0.2 + wisp, 0.82 + fy / 1200 * 0.14 + wisp)
            case "foliage":
                let t = (sin(fx / 9 + fy / 41) * cos(fy / 7 - fx / 53) + 1) * 0.12
                rgb = (0.16 + t, 0.31 + t, 0.12 + t * 0.55)
            case "skin":
                let t = (sin(fx / 150) + cos(fy / 120) + sin((fx + fy) / 70)) * 0.018
                rgb = (0.66 + t, 0.43 + t * 0.72, 0.34 + t * 0.55)
            default:
                // A soft-edged ridge (about 6 px transition) running across the frame: bright
                // above, dark below. Sources across it are a contamination trap.
                let ridge = 880 + 40 * sin(fx / 300)
                let s = 0.5 + 0.5 * tanh((ridge - fy) / 3)
                let t = s * 0.2 + sin(fx / 90) * 0.012
                rgb = (0.30 + t, 0.45 + t, 0.62 + t * 0.8)
            }
            let i = (y * width + x) * 4
            for (c, value) in [rgb.0 + grain, rgb.1 + grain, rgb.2 + grain].enumerated() {
                clean[i + c] = UInt8(min(max(value, 0), 1) * 255)
            }
        }}

        // Placement is deliberately off-centre (upper third) so a vertical-origin mistake in any
        // crop-to-source mapping cannot cancel by symmetry.
        let center = CGPoint(x: 1010, y: background == "edge" ? 780 : 380)
        let stroke: [CGPoint]
        let defectRadius: Double
        switch defect {
        case "hair":
            defectRadius = 1.6
            stroke = [CGPoint(x: center.x - 80, y: center.y - 22), CGPoint(x: center.x - 30, y: center.y + 4),
                      CGPoint(x: center.x + 25, y: center.y + 22), CGPoint(x: center.x + 80, y: center.y + 18)]
        case "long hair":
            // A fibre lying across most of the frame: its bounding box covers about 60% of the crop.
            defectRadius = 1.6
            stroke = [CGPoint(x: 240, y: 230), CGPoint(x: 700, y: 420), CGPoint(x: 1150, y: 680),
                      CGPoint(x: 1560, y: 1010)]
        case "soft dust":
            defectRadius = 7; stroke = [center]
        default:
            defectRadius = 5; stroke = [center]
        }
        func distance(_ p: CGPoint) -> Double {
            if stroke.count == 1 { return hypot(Double(p.x - stroke[0].x), Double(p.y - stroke[0].y)) }
            return zip(stroke, stroke.dropFirst()).map { a, b in
                let dx = Double(b.x - a.x), dy = Double(b.y - a.y)
                let length = dx * dx + dy * dy
                let t = min(max((Double(p.x - a.x) * dx + Double(p.y - a.y) * dy) / length, 0), 1)
                return hypot(Double(p.x - a.x) - t * dx, Double(p.y - a.y) - t * dy)
            }.min() ?? 99
        }
        var damaged = clean
        var mask = [Bool](repeating: false, count: width * height)
        let xs = stroke.map(\.x), ys = stroke.map(\.y)
        let reach = defectRadius * 1.4 + 2
        let box = CGRect(x: xs.min()! - reach, y: ys.min()! - reach,
                         width: xs.max()! - xs.min()! + reach * 2, height: ys.max()! - ys.min()! + reach * 2)
        for y in Int(box.minY)...Int(box.maxY) { for x in Int(box.minX)...Int(box.maxX) {
            let d = distance(CGPoint(x: x, y: y))
            let index = y * width + x
            // Hair and speck are opaque inside their radius with a one pixel antialiased rim; dust
            // falls off smoothly out to 1.4 radii.
            let weight: Double
            let level: Double
            switch defect {
            case "soft dust": weight = max(0, min(1, (defectRadius * 1.4 - d) / (defectRadius * 0.9))); level = 0.12
            case "hair", "long hair": weight = max(0, min(1, defectRadius + 0.5 - d)); level = 0.04
            default: weight = max(0, min(1, defectRadius + 0.5 - d)); level = 0.08
            }
            guard weight > 0 else { continue }
            mask[index] = d <= defectRadius
            let i = index * 4
            for c in 0..<3 {
                let original = Double(clean[i + c]) / 255
                damaged[i + c] = UInt8(min(max(original * (1 - weight) + level * weight, 0), 1) * 255)
            }
        }}

        // Brush covers the defect with a little margin, as a user's stroke would.
        let brush = defectRadius + 1.5
        let normalizedStroke = stroke.map { CGPoint(x: $0.x / CGFloat(width), y: $0.y / CGFloat(height)) }
        // Known clean source: straight below the defect on flat or textured backgrounds, and along
        // the ridge for the edge case, far enough that the translated brush shares no pixel with it.
        let offset = defect == "long hair" ? CGPoint(x: 0, y: 100)
            : background == "edge" ? CGPoint(x: 260, y: 0) : CGPoint(x: 0, y: 150)
        // Metrics cover the defect plus a margin; for the long hair, its central 360 × 300 portion.
        let window = (defect == "long hair"
            ? CGRect(x: 745, y: 400, width: 360, height: 300)
            : CGRect(x: box.minX - 24, y: box.minY - 24, width: box.width + 48, height: box.height + 48))
            .intersection(CGRect(x: 0, y: 0, width: width, height: height)).integral
        return Case(background: background, defect: defect, width: width, height: height, clean: clean,
                    damaged: damaged, mask: mask, stroke: normalizedStroke,
                    radius: brush / Double(min(width, height)), radiusPixels: brush,
                    manualPixelOffset: offset, window: window)
    }
}

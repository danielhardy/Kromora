import CoreGraphics
import Foundation

/// CPU-only difference-of-Gaussians dust analysis over the neutral Lab proxy.
/// Coordinates returned by this type are normalized in oriented source space.
struct RetouchDustSuggestion: Sendable, Equatable, Identifiable {
    let id: UUID
    let point: CGPoint
    let radius: Double
    let confidence: Double
    let seed: UInt32
}

enum RetouchDustDetector {
    static func detect(in proxy: RetouchAnalysisProxy, threshold: Double = 0.025,
                       maximum: Int = 500) -> [RetouchDustSuggestion] {
        guard proxy.isUsable, proxy.width >= 9, proxy.height >= 9 else { return [] }
        let width = proxy.width, height = proxy.height
        let luminance = proxy.pixels.map { Double($0.x) / 100 }
        let small = blur(luminance, width: width, height: height, sigma: 1.2)
        let medium = blur(luminance, width: width, height: height, sigma: 2.4)
        let large = blur(luminance, width: width, height: height, sigma: 4.8)
        let dog = zip(small, medium).map { abs($0 - $1) }
        let dog2 = zip(medium, large).map { abs($0 - $1) }
        let gate = max(0.005, threshold)
        var peaks: [(x: Int, y: Int, strength: Double, sigma: Double)] = []
        for y in 4..<(height - 4) {
            for x in 4..<(width - 4) {
                let i = y * width + x
                let response = max(dog[i], dog2[i])
                guard response >= gate, isLocalMaximum(response, x: x, y: y, width: width, dog: dog, dog2: dog2),
                      smoothRegion(x: x, y: y, width: width, height: height, luminance: luminance) else { continue }
                peaks.append((x, y, response, dog2[i] > dog[i] ? 4.8 : 2.4))
            }
        }
        peaks.sort { $0.strength == $1.strength ? ($0.y == $1.y ? $0.x < $1.x : $0.y < $1.y) : $0.strength > $1.strength }
        var accepted: [(x: Int, y: Int, strength: Double, sigma: Double)] = []
        for peak in peaks {
            guard !accepted.contains(where: { hypot(Double($0.x - peak.x), Double($0.y - peak.y)) < peak.sigma }) else { continue }
            accepted.append(peak)
            if accepted.count >= max(0, maximum) { break }
        }
        let shortSide = Double(min(width, height))
        return accepted.map { peak in
            let point = CGPoint(x: Double(peak.x) / Double(width - 1), y: Double(peak.y) / Double(height - 1))
            let seed = stableSeed(x: peak.x, y: peak.y, width: width, height: height)
            return RetouchDustSuggestion(id: UUID(uuidString: String(format: "%08X-0000-4000-8000-%012X", seed, UInt64(peak.y * width + peak.x)))!,
                point: point, radius: min(0.08, max(0.003, peak.sigma * 2.2 / shortSide)),
                confidence: min(1, peak.strength / (gate * 3)), seed: seed)
        }
    }

    private static func isLocalMaximum(_ value: Double, x: Int, y: Int, width: Int,
                                       dog: [Double], dog2: [Double]) -> Bool {
        for dy in -1...1 { for dx in -1...1 where dx != 0 || dy != 0 {
            let i = (y + dy) * width + x + dx
            if max(dog[i], dog2[i]) > value { return false }
        } }
        return true
    }

    /// Reject areas with strong or rapidly changing local gradients (foliage, edges, texture).
    private static func smoothRegion(x: Int, y: Int, width: Int, height: Int, luminance: [Double]) -> Bool {
        var sum = 0.0, square = 0.0, count = 0.0
        for dy in -6...6 { for dx in -6...6 where dx * dx + dy * dy >= 16 && dx * dx + dy * dy <= 36 {
            let px = x + dx, py = y + dy
            guard px > 0, py > 0, px + 1 < width, py + 1 < height else { continue }
            let i = py * width + px
            let gx = luminance[i + 1] - luminance[i - 1]
            let gy = luminance[i + width] - luminance[i - width]
            let g = hypot(gx, gy)
            sum += g; square += g * g; count += 1
        } }
        guard count > 0 else { return false }
        let mean = sum / count
        return mean < 0.035 && max(0, square / count - mean * mean) < 0.0007
    }

    private static func blur(_ input: [Double], width: Int, height: Int, sigma: Double) -> [Double] {
        let radius = max(1, Int((sigma * 3).rounded()))
        let weights = (-radius...radius).map { exp(-Double($0 * $0) / (2 * sigma * sigma)) }
        let norm = weights.reduce(0, +)
        let kernel = weights.map { $0 / norm }
        var horizontal = Array(repeating: 0.0, count: input.count)
        var output = horizontal
        for y in 0..<height { for x in 0..<width {
            var value = 0.0
            for k in -radius...radius { value += input[y * width + min(width - 1, max(0, x + k))] * kernel[k + radius] }
            horizontal[y * width + x] = value
        } }
        for y in 0..<height { for x in 0..<width {
            var value = 0.0
            for k in -radius...radius { value += horizontal[min(height - 1, max(0, y + k)) * width + x] * kernel[k + radius] }
            output[y * width + x] = value
        } }
        return output
    }

    private static func stableSeed(x: Int, y: Int, width: Int, height: Int) -> UInt32 {
        var value = UInt32(truncatingIfNeeded: x &* 73856093 ^ y &* 19349663 ^ width &* 83492791 ^ height)
        value ^= value >> 16; value &*= 0x7feb352d; value ^= value >> 15
        value &*= 0x846ca68b; value ^= value >> 16
        return value == 0 ? 1 : value
    }
}

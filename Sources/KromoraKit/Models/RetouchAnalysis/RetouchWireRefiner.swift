import CoreGraphics
import Foundation

/// Snaps an intentionally broad Remove brush stroke to a single coherent, thin ridge.
/// Coordinates and widths are returned in the same oriented-source normalized space as a brush.
enum RetouchWireRefiner {
    struct Proposal: Sendable, Equatable {
        let region: RetouchRegion
        let meanContrast: Double
        let confidence: Double
    }

    enum Failure: Error, Equatable { case invalidInput, ambiguous, cancelled }

    /// The proxy is neutral Lab and bounded to the whole image. Cancellation is polled throughout
    /// the corridor walk so callers can abandon a stale or explicitly cancelled proposal.
    static func refine(
        region: RetouchRegion,
        in image: RetouchAnalysisProxy,
        sourceWidth: Int,
        sourceHeight: Int,
        isCancelled: @Sendable () -> Bool = { false }
    ) throws -> Proposal {
        guard image.isUsable, sourceWidth > 1, sourceHeight > 1,
              region.samples.count >= 2 else { throw Failure.invalidInput }
        let shortSide = Double(min(sourceWidth, sourceHeight))
        let proxyShort = Double(min(image.width, image.height))
        let corridor = max(2, region.radius * proxyShort)
        let proxyPoints = region.samples.map {
            CGPoint(x: $0.point.x * Double(image.width - 1), y: $0.point.y * Double(image.height - 1))
        }
        let length = zip(proxyPoints, proxyPoints.dropFirst()).reduce(0.0) { total, pair in
            total + hypot(pair.1.x - pair.0.x, pair.1.y - pair.0.y)
        }
        let count = min(4096, max(region.samples.count, Int(ceil(length / 1.5)) + 1))
        guard count >= 2 else { throw Failure.invalidInput }
        let path = resample(proxyPoints, count: count)
        var offsets: [Double] = []; offsets.reserveCapacity(path.count)
        var contrasts: [Double] = []; contrasts.reserveCapacity(path.count)
        var polarities: [Double] = []; polarities.reserveCapacity(path.count)
        let searchRadius = min(24.0, corridor)
        let step = max(0.75, searchRadius / 8)
        let flankDistance = min(8, max(4, corridor * 0.65))

        for index in path.indices {
            if isCancelled() { throw Failure.cancelled }
            let point = path[index]
            let before = path[max(0, index - 2)], after = path[min(path.count - 1, index + 2)]
            let dx = after.x - before.x, dy = after.y - before.y
            let magnitude = hypot(dx, dy)
            guard magnitude > 0.01 else { throw Failure.ambiguous }
            let nx = -dy / magnitude, ny = dx / magnitude
            var candidates: [(offset: Double, contrast: Double, polarity: Double)] = []
            var offset = -searchRadius
            while offset <= searchRadius + 0.001 {
                let x = Int((point.x + nx * offset).rounded())
                let y = Int((point.y + ny * offset).rounded())
                guard x >= 3, y >= 3, x < image.width - 3, y < image.height - 3,
                      let center = image.lab(x: x, y: y),
                      let sideA = image.lab(x: Int((Double(x) + nx * flankDistance).rounded()), y: Int((Double(y) + ny * flankDistance).rounded())),
                      let sideB = image.lab(x: Int((Double(x) - nx * flankDistance).rounded()), y: Int((Double(y) - ny * flankDistance).rounded())) else {
                    offset += step; continue
                }
                let side = (sideA.x + sideB.x) * 0.5
                // Penalize asymmetric background gradients and reward a ridge that is distinct
                // from both flanks. The score is polarity agnostic (dark wire or light wire).
                let balance = abs(center.x - sideA.x) + abs(center.x - sideB.x)
                let asymmetry = abs(abs(center.x - sideA.x) - abs(center.x - sideB.x))
                // The original brush path is a spatial prior. This keeps a nearby roof or
                // horizon edge from winning over the intended ridge at crossings.
                let ridgeEvidence = Double(balance) * 0.5 - Double(asymmetry) * 0.30
                let pathPenalty = abs(offset) * 0.45
                let strength = max(0.0, ridgeEvidence - pathPenalty)
                candidates.append((offset, strength, Double(center.x - side)))
                offset += step
            }
            candidates.sort { $0.contrast > $1.contrast }
            guard let best = candidates.first, best.contrast >= 4.0 else { throw Failure.ambiguous }
            // A single 1–8 px wire can create several adjacent high-scoring samples; only a
            // second ridge beyond that width counts as competing evidence.
            let separated = candidates.dropFirst().filter { abs($0.offset - best.offset) > 12 }.first
            if let separated, separated.contrast > best.contrast * 0.86 { throw Failure.ambiguous }
            let centerOffset = ridgeCenterOffset(
                point: point, normalX: nx, normalY: ny, selectedOffset: best.offset,
                extent: min(10, max(6, flankDistance + 2)), image: image
            )
            offsets.append(centerOffset); contrasts.append(best.contrast); polarities.append(best.polarity)
        }

        guard let medianPolarity = median(polarities),
              polarities.filter({ $0 * medianPolarity > 0 }).count >= Int(Double(polarities.count) * 0.72),
              let medianContrast = median(contrasts), medianContrast >= 4 else { throw Failure.ambiguous }

        // Smooth one-pixel detector jitter without flattening intentional bends; endpoints remain
        // evidence guided, while original pressure values and path coverage are retained.
        let smoothed = offsets.indices.map { i -> Double in
            let lo = max(0, i - 2), hi = min(offsets.count - 1, i + 2)
            return median(Array(offsets[lo...hi])) ?? offsets[i]
        }
        var result: [BrushSample] = []
        for index in path.indices {
            let before = path[max(0, index - 2)], after = path[min(path.count - 1, index + 2)]
            let dx = after.x - before.x, dy = after.y - before.y, magnitude = max(0.01, hypot(dx, dy))
            let nx = -dy / magnitude, ny = dx / magnitude
            let shifted = CGPoint(x: path[index].x + nx * smoothed[index], y: path[index].y + ny * smoothed[index])
            result.append(BrushSample(point: CGPoint(x: shifted.x / Double(image.width - 1),
                                                     y: shifted.y / Double(image.height - 1))))
        }

        // Estimate half-width at half contrast around the selected line. This is conservative:
        // the standard renderer adds its normal feather to the accepted centerline.
        let estimatedHalfWidth = estimateHalfWidth(path: path, offsets: smoothed, image: image)
        let sourcePixelsPerProxy = max(Double(sourceWidth) / Double(image.width), Double(sourceHeight) / Double(image.height))
        let radiusPixels = min(4.5, max(0.65, estimatedHalfWidth * sourcePixelsPerProxy))
        let normalizedRadius = radiusPixels / shortSide
        let confidence = min(1, max(0, medianContrast / 24))
        return Proposal(region: RetouchRegion(samples: result, radius: normalizedRadius),
                        meanContrast: medianContrast, confidence: confidence)
    }

    private static func estimateHalfWidth(path: [CGPoint], offsets: [Double], image: RetouchAnalysisProxy) -> Double {
        guard !path.isEmpty else { return 1 }
        var widths: [Double] = []
        for index in stride(from: 0, to: path.count, by: max(1, path.count / 32)) {
            let point = path[index]
            let before = path[max(0, index - 2)], after = path[min(path.count - 1, index + 2)]
            let dx = after.x - before.x, dy = after.y - before.y, magnitude = max(0.01, hypot(dx, dy))
            let nx = -dy / magnitude, ny = dx / magnitude
            let cx = point.x + nx * offsets[index], cy = point.y + ny * offsets[index]
            guard let center = image.lab(x: Int(cx.rounded()), y: Int(cy.rounded())) else { continue }
            let sideA = image.lab(x: Int((cx + nx * 5).rounded()), y: Int((cy + ny * 5).rounded()))?.x ?? center.x
            let sideB = image.lab(x: Int((cx - nx * 5).rounded()), y: Int((cy - ny * 5).rounded()))?.x ?? center.x
            let background = (sideA + sideB) * 0.5
            let threshold = abs(center.x - background) * 0.5
            var radius = 0.5
            for distance in stride(from: 1.0, through: 8.0, by: 0.5) {
                let a = image.lab(x: Int((cx + nx * distance).rounded()), y: Int((cy + ny * distance).rounded()))?.x
                let b = image.lab(x: Int((cx - nx * distance).rounded()), y: Int((cy - ny * distance).rounded()))?.x
                guard let a, let b else { break }
                if abs(a - background) <= threshold && abs(b - background) <= threshold { break }
                radius = distance
            }
            widths.append(radius)
        }
        return median(widths) ?? 1
    }

    /// Recenters a selected edge response on the middle of its connected ridge support. This
    /// matters for wide (up to 8 px) wires, where the user's overspray may land on one edge.
    private static func ridgeCenterOffset(
        point: CGPoint, normalX: Double, normalY: Double, selectedOffset: Double,
        extent: Double, image: RetouchAnalysisProxy
    ) -> Double {
        let centerX = point.x + normalX * selectedOffset
        let centerY = point.y + normalY * selectedOffset
        func luminance(_ distance: Double) -> Double? {
            image.lab(x: Int((centerX + normalX * distance).rounded()),
                      y: Int((centerY + normalY * distance).rounded())).map { Double($0.x) }
        }
        guard let left = luminance(-extent), let right = luminance(extent) else { return selectedOffset }
        let baseline = (left + right) * 0.5
        let values = stride(from: -extent, through: extent, by: 0.5).map { distance in
            (distance, luminance(distance).map { abs($0 - baseline) } ?? 0)
        }
        guard let peak = values.map(\.1).max(), peak >= 4 else { return selectedOffset }
        let threshold = peak * 0.35
        guard let peakIndex = values.firstIndex(where: { $0.1 == peak }) else { return selectedOffset }
        var lower = peakIndex, upper = peakIndex
        while lower > 0 && values[lower - 1].1 >= threshold { lower -= 1 }
        while upper + 1 < values.count && values[upper + 1].1 >= threshold { upper += 1 }
        let support = values[lower...upper]
        let weight = support.reduce(0.0) { $0 + $1.1 }
        guard weight > 0 else { return selectedOffset }
        let centroid = support.reduce(0.0) { $0 + $1.0 * $1.1 } / weight
        return selectedOffset + centroid
    }

    private static func resample(_ points: [CGPoint], count: Int) -> [CGPoint] {
        guard points.count > 1, count > 1 else { return points }
        var lengths = [0.0]
        for pair in zip(points, points.dropFirst()) { lengths.append(lengths.last! + hypot(pair.1.x - pair.0.x, pair.1.y - pair.0.y)) }
        let total = lengths.last ?? 0
        guard total > 0 else { return points }
        return (0..<count).map { i in
            let distance = total * Double(i) / Double(count - 1)
            guard let segment = lengths.firstIndex(where: { $0 >= distance }), segment > 0 else { return points[0] }
            let start = lengths[segment - 1], span = max(0.001, lengths[segment] - start)
            let t = (distance - start) / span
            return CGPoint(x: points[segment - 1].x + (points[segment].x - points[segment - 1].x) * t,
                           y: points[segment - 1].y + (points[segment].y - points[segment - 1].y) * t)
        }
    }

    private static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted(); return sorted[sorted.count / 2]
    }
}

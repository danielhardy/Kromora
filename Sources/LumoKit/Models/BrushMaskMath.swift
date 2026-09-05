import CoreGraphics
import Foundation

/// Pure brush geometry shared by pointer capture, preview, and export.  Brush recipes stay
/// normalized, while distances are measured in source pixels so a stroke has the same shape at
/// every render resolution.
enum BrushMaskMath {
    static let defaultRadius = 0.05
    static let defaultFeather = 0.5
    static let defaultFlow = 1.0
    static let defaultDensity = 1.0

    /// Resample by physical source distance and then apply Ramer-Douglas-Peucker simplification.
    /// The error is expressed as a fraction of the source's shorter side, which makes the bound
    /// independent of the preview/export pixel box.
    static func resampledAndSimplified(
        _ samples: [BrushSample],
        sourceSize: CGSize,
        radius: Double,
        error: Double? = nil,
        maximumSamples: Int = 4_096
    ) -> [BrushSample] {
        guard !samples.isEmpty, maximumSamples > 0 else { return [] }
        let width = max(sourceSize.width.isFinite ? sourceSize.width : 1, 1)
        let height = max(sourceSize.height.isFinite ? sourceSize.height : 1, 1)
        let shorter = max(min(width, height), 1)
        let spacing = samplingSpacing(sourceSize: sourceSize, radius: radius)

        var resampled = [samples[0]]
        resampled.reserveCapacity(min(samples.count, maximumSamples))
        var last = samples[0].point
        var carry = 0.0
        for sample in samples.dropFirst() {
            let distance = physicalDistance(
                last, sample.point, sourceSize: CGSize(width: width, height: height))
            carry += distance
            if carry >= spacing {
                resampled.append(sample)
                last = sample.point
                carry = 0
                if resampled.count == maximumSamples { break }
            }
        }
        if resampled.count == 1, let lastSample = samples.last, lastSample != samples[0],
            maximumSamples > 1
        {
            resampled.append(lastSample)
        } else if let lastSample = samples.last, resampled.last != lastSample,
            resampled.count < maximumSamples
        {
            resampled.append(lastSample)
        } else if let lastSample = samples.last, resampled.last != lastSample,
            !resampled.isEmpty
        {
            resampled[resampled.count - 1] = lastSample
        }

        let tolerance =
            max(
                error ?? max(radius * 0.06, 0.0005),
                0.0001
            ) * shorter
        return simplify(resampled, tolerance: tolerance, width: width, height: height)
    }

    /// The minimum physical distance between samples accepted during a live stroke. Keeping this
    /// policy separate lets pointer capture bound its working array without repeatedly walking the
    /// whole stroke on the main actor. The final `resampledAndSimplified` pass still applies the
    /// exact same spacing and simplification contract at commit time.
    static func samplingSpacing(sourceSize: CGSize, radius: Double) -> Double {
        let width = max(sourceSize.width.isFinite ? sourceSize.width : 1, 1)
        let height = max(sourceSize.height.isFinite ? sourceSize.height : 1, 1)
        let shorter = max(min(width, height), 1)
        return max(shorter * max(radius.isFinite ? radius : defaultRadius, 0.0001) * 0.18, 0.5)
    }

    static func physicalDistance(_ lhs: CGPoint, _ rhs: CGPoint, sourceSize: CGSize) -> Double {
        let width = max(sourceSize.width.isFinite ? sourceSize.width : 1, 1)
        let height = max(sourceSize.height.isFinite ? sourceSize.height : 1, 1)
        return hypot((lhs.x - rhs.x) * width, (lhs.y - rhs.y) * height)
    }

    /// Mouse samples have no pressure.  Treating absent, invalid, or zero tablet pressure as a
    /// finite normalized value keeps the renderer deterministic and avoids a mouse stroke that
    /// disappears on devices which report pressure lazily.
    static func normalizedPressure(_ pressure: Double?) -> Double {
        guard let pressure, pressure.isFinite else { return 1 }
        return min(max(pressure, 0), 1)
    }

    /// Smooth radial falloff for one stamp.  The result is the alpha deposited before repeated
    /// stamp accumulation and is intentionally resolution independent.
    static func stampAlpha(
        distance: Double, radius: Double, feather: Double, flow: Double, pressure: Double?
    ) -> Double {
        let safeRadius = max(radius.isFinite ? radius : defaultRadius, 0.000001)
        let safeFeather = min(max(feather.isFinite ? feather : defaultFeather, 0), 1)
        let inner = safeRadius * (1 - safeFeather)
        guard distance.isFinite, distance < safeRadius else { return 0 }
        let falloff: Double
        if distance <= inner || safeRadius == inner {
            falloff = 1
        } else {
            let t = min(max((distance - inner) / (safeRadius - inner), 0), 1)
            let smooth = t * t * (3 - 2 * t)
            falloff = 1 - smooth
        }
        let safeFlow = min(max(flow.isFinite ? flow : defaultFlow, 0), 1)
        return min(max(safeFlow * normalizedPressure(pressure) * falloff, 0), 1)
    }

    /// Repeated deposits accumulate without exceeding the stroke density cap.
    static func accumulatedOpacity(current: Double, stamp: Double, density: Double) -> Double {
        let existing = min(max(current.isFinite ? current : 0, 0), 1)
        let deposit = min(max(stamp.isFinite ? stamp : 0, 0), 1)
        let cap = min(max(density.isFinite ? density : defaultDensity, 0), 1)
        return min(cap, 1 - (1 - existing) * (1 - deposit))
    }

    private static func simplify(
        _ samples: [BrushSample], tolerance: Double, width: Double, height: Double
    ) -> [BrushSample] {
        guard samples.count > 2 else { return samples }
        var keep = Array(repeating: false, count: samples.count)
        keep[0] = true
        keep[keep.count - 1] = true
        simplify(
            samples, first: 0, last: samples.count - 1, tolerance: tolerance,
            width: width, height: height, keep: &keep)
        return samples.enumerated().compactMap { keep[$0.offset] ? $0.element : nil }
    }

    private static func simplify(
        _ samples: [BrushSample], first: Int, last: Int, tolerance: Double,
        width: Double, height: Double, keep: inout [Bool]
    ) {
        guard last > first + 1 else { return }
        var maximum = tolerance
        var split: Int?
        for index in (first + 1)..<last {
            let distance = perpendicularDistance(
                samples[index].point, from: samples[first].point,
                to: samples[last].point, width: width, height: height)
            if distance > maximum {
                maximum = distance
                split = index
            }
        }
        guard let split else { return }
        keep[split] = true
        simplify(
            samples, first: first, last: split, tolerance: tolerance,
            width: width, height: height, keep: &keep)
        simplify(
            samples, first: split, last: last, tolerance: tolerance,
            width: width, height: height, keep: &keep)
    }

    private static func perpendicularDistance(
        _ point: CGPoint, from start: CGPoint, to end: CGPoint, width: Double, height: Double
    ) -> Double {
        let px = point.x * width
        let py = point.y * height
        let sx = start.x * width
        let sy = start.y * height
        let ex = end.x * width
        let ey = end.y * height
        let dx = ex - sx
        let dy = ey - sy
        let length = hypot(dx, dy)
        guard length > 0 else { return hypot(px - sx, py - sy) }
        return abs((px - sx) * dy - (py - sy) * dx) / length
    }
}

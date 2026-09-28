import CoreGraphics
import Foundation

struct RetouchSourceCandidate: Sendable, Equatable {
    let offset: CGVector
    let score: Double
}

/// Stable patch source search shared by Heal and Clone.
enum RetouchSourcePicker {
    static func candidates(
        for spot: RetouchSpot, among spots: [RetouchSpot], in proxy: RetouchAnalysisProxy,
        limit: Int = 24, cancellation: (() -> Bool)? = nil
    ) -> [RetouchSourceCandidate] {
        guard proxy.isUsable, let shape = Shape(spot: spot, width: proxy.width, height: proxy.height) else { return [] }
        let step = max(1, shape.radius)
        let maxRadius = max(step, shape.radius * 6)
        var points: [(Int, Int)] = []
        // Deterministic square spiral shells. Enumerate only each shell's perimeter so search
        // setup stays proportional to the candidate count instead of rescanning every inner box.
        for ring in 1...max(1, maxRadius / step) {
            if cancellation?() == true { return [] }
            let edge = ring * step
            for x in stride(from: -edge, through: edge, by: step) {
                points.append((shape.centerX + x, shape.centerY - edge))
                points.append((shape.centerX + x, shape.centerY + edge))
            }
            if edge > step {
                for y in stride(from: -edge + step, to: edge, by: step) {
                    points.append((shape.centerX - edge, shape.centerY + y))
                    points.append((shape.centerX + edge, shape.centerY + y))
                }
            }
        }
        // Coarse full-frame grid ensures distant clean areas remain discoverable.
        let coarse = max(shape.radius, min(proxy.width, proxy.height) / 8, 1)
        for y in stride(from: coarse / 2, to: proxy.height, by: coarse) {
            for x in stride(from: coarse / 2, to: proxy.width, by: coarse) { points.append((x, y)) }
        }

        var best: [RetouchSourceCandidate] = []
        for (x, y) in points {
            if cancellation?() == true { return [] }
            guard valid(centerX: x, centerY: y, shape: shape, spots: spots, excluding: spot.id) else { continue }
            let score = score(centerX: x, centerY: y, shape: shape, sample: proxy.lab)
            guard score.isFinite else { continue }
            best.append(RetouchSourceCandidate(
                offset: CGVector(dx: CGFloat(x - shape.centerX) / CGFloat(proxy.width),
                                 dy: -CGFloat(y - shape.centerY) / CGFloat(proxy.height)),
                score: score
            ))
        }
        best.sort(by: candidateOrder)
        // Refine top candidates at pixel resolution within ±2 px; offsets remain normalized.
        let refine = Array(best.prefix(max(1, min(4, limit))))
        var refined: [RetouchSourceCandidate] = []
        for candidate in refine {
            let baseX = shape.centerX + Int((candidate.offset.dx * CGFloat(proxy.width)).rounded())
            let baseY = shape.centerY - Int((candidate.offset.dy * CGFloat(proxy.height)).rounded())
            for dy in -2...2 { for dx in -2...2 {
                let x = baseX + dx, y = baseY + dy
                guard valid(centerX: x, centerY: y, shape: shape, spots: spots, excluding: spot.id) else { continue }
                refined.append(RetouchSourceCandidate(
                    offset: CGVector(dx: CGFloat(x - shape.centerX) / CGFloat(proxy.width),
                                     dy: -CGFloat(y - shape.centerY) / CGFloat(proxy.height)),
                    score: score(centerX: x, centerY: y, shape: shape, sample: proxy.lab)
                ))
            } }
        }
        best = Array((refined + best).sorted(by: candidateOrder).uniquedOffsets().prefix(max(0, limit)))
        return best
    }

    static func source(for spot: RetouchSpot, among spots: [RetouchSpot], in proxy: RetouchAnalysisProxy,
                       rank: Int = 0, cancellation: (() -> Bool)? = nil) -> RetouchSource? {
        let values = candidates(for: spot, among: spots, in: proxy, limit: max(rank + 1, 24), cancellation: cancellation)
        guard values.indices.contains(rank) else { return nil }
        return .auto(offset: values[rank].offset, rank: rank)
    }

    static func resolving(_ spot: RetouchSpot, among spots: [RetouchSpot], in proxy: RetouchAnalysisProxy,
                          rank: Int = 0, cancellation: (() -> Bool)? = nil) -> RetouchSpot {
        if case .manual? = spot.source { return spot }
        var resolved = spot
        resolved.source = source(for: spot, among: spots, in: proxy, rank: rank, cancellation: cancellation)
        return resolved
    }

    /// Re-score leading proxy matches using a bounded full-resolution crop and refine each within
    /// ±2 full-resolution pixels. Candidates outside the supplied crop retain their proxy score.
    static func refining(
        _ candidates: [RetouchSourceCandidate], for spot: RetouchSpot, among spots: [RetouchSpot],
        in region: RetouchAnalysisRegion, limit: Int = 4, cancellation: (() -> Bool)? = nil
    ) -> [RetouchSourceCandidate] {
        guard let shape = Shape(spot: spot, width: region.sourceWidth, height: region.sourceHeight) else { return candidates }
        var refined: [RetouchSourceCandidate] = []
        for candidate in candidates.prefix(max(0, limit)) {
            if cancellation?() == true { return candidates }
            let baseX = shape.centerX + Int((candidate.offset.dx * CGFloat(shape.width)).rounded())
            let baseY = shape.centerY - Int((candidate.offset.dy * CGFloat(shape.height)).rounded())
            guard region.lab(sourceX: shape.centerX, sourceY: shape.centerY) != nil,
                  region.lab(sourceX: baseX, sourceY: baseY) != nil else { continue }
            for dy in -2...2 { for dx in -2...2 {
                let x = baseX + dx, y = baseY + dy
                guard valid(centerX: x, centerY: y, shape: shape, spots: spots, excluding: spot.id) else { continue }
                refined.append(RetouchSourceCandidate(
                    offset: CGVector(dx: CGFloat(x - shape.centerX) / CGFloat(shape.width),
                                     dy: -CGFloat(y - shape.centerY) / CGFloat(shape.height)),
                    score: score(centerX: x, centerY: y, shape: shape, sample: region.lab)
                ))
            } }
        }
        return Array((refined + candidates).sorted(by: candidateOrder).uniquedOffsets().prefix(candidates.count))
    }

    private static func candidateOrder(_ a: RetouchSourceCandidate, _ b: RetouchSourceCandidate) -> Bool {
        if a.score != b.score { return a.score < b.score }
        if a.offset.dy != b.offset.dy { return a.offset.dy < b.offset.dy }
        return a.offset.dx < b.offset.dx
    }

    private static func valid(centerX: Int, centerY: Int, shape: Shape, spots: [RetouchSpot], excluding id: UUID) -> Bool {
        let margin = max(2, shape.radius / 3)
        let dx = centerX - shape.centerX, dy = centerY - shape.centerY
        let candidate = shape.bounds.offsetBy(dx: CGFloat(dx), dy: CGFloat(dy))
            .insetBy(dx: -CGFloat(margin), dy: -CGFloat(margin))
        guard candidate.minX >= 0, candidate.minY >= 0,
              candidate.maxX < CGFloat(shape.width), candidate.maxY < CGFloat(shape.height),
              !overlaps(candidate, shape.bounds.insetBy(dx: -CGFloat(margin), dy: -CGFloat(margin))) else { return false }
        for other in spots where other.id != id && !other.isIdentity {
            guard let otherShape = Shape(spot: other, width: shape.width, height: shape.height) else { continue }
            if overlaps(candidate, otherShape.bounds.insetBy(dx: -CGFloat(margin), dy: -CGFloat(margin))) { return false }
        }
        return true
    }

    private static func overlaps(_ a: CGRect, _ b: CGRect) -> Bool {
        a.minX < b.maxX && a.maxX > b.minX && a.minY < b.maxY && a.maxY > b.minY
    }

    private static func score(
        centerX: Int, centerY: Int, shape: Shape,
        sample: (Int, Int) -> SIMD3<Float>?
    ) -> Double {
        var color = 0.0, gradient = 0.0, ringTexture = 0.0, interiorTexture = 0.0
        var ringCount = 0.0, interiorCount = 0.0
        let outer = shape.radius + max(2, shape.radius / 2)
        let sampleStep = max(1, shape.radius / 3)
        for dy in stride(from: -outer, through: outer, by: sampleStep) {
          for dx in stride(from: -outer, through: outer, by: sampleStep) {
            let r2 = dx * dx + dy * dy
            guard r2 <= outer * outer && r2 >= shape.radius * shape.radius else { continue }
            guard let a = sample(shape.centerX + dx, shape.centerY + dy),
                  let b = sample(centerX + dx, centerY + dy) else { continue }
            let dl = Double(a.x - b.x), da = Double(a.y - b.y), db = Double(a.z - b.z)
            color += dl * dl + da * da + db * db
            if let ax = sample(shape.centerX + dx + 1, shape.centerY + dy),
               let bx = sample(centerX + dx + 1, centerY + dy) {
                let ga = hypot(Double(ax.x - a.x), Double(ax.y - a.y))
                let gb = hypot(Double(bx.x - b.x), Double(bx.y - b.y))
                gradient += (ga - gb) * (ga - gb)
            }
            let destinationGradient = sample(shape.centerX + dx + 1, shape.centerY + dy).map {
                hypot(Double($0.x - a.x), Double($0.y - a.y))
            } ?? 0
            ringTexture += destinationGradient
            ringCount += 1
        } }
        for dy in stride(from: -shape.radius, through: shape.radius, by: sampleStep) {
          for dx in stride(from: -shape.radius, through: shape.radius, by: sampleStep)
            where dx * dx + dy * dy < shape.radius * shape.radius {
            guard let center = sample(centerX + dx, centerY + dy),
                  let right = sample(centerX + dx + 1, centerY + dy),
                  let down = sample(centerX + dx, centerY + dy + 1) else { continue }
            interiorTexture += hypot(Double(right.x - center.x), Double(right.y - center.y))
                + hypot(Double(down.x - center.x), Double(down.y - center.y))
            interiorCount += 2
          }
        }
        guard ringCount > 0, interiorCount > 0 else { return .infinity }
        let distance = hypot(Double(centerX - shape.centerX), Double(centerY - shape.centerY)) / Double(max(1, shape.radius * 6))
        let textureMismatch = abs(interiorTexture / interiorCount - ringTexture / ringCount)
        return color / ringCount + gradient / ringCount * 0.35 + textureMismatch * 0.08 + distance * 0.35
    }

    private struct Shape {
        let centerX: Int; let centerY: Int; let radius: Int; let width: Int; let height: Int
        let bounds: CGRect
        init?(spot: RetouchSpot, width: Int, height: Int) {
            guard width > 0, height > 0, !spot.region.samples.isEmpty else { return nil }
            self.width = width; self.height = height
            radius = max(2, Int((spot.region.radius * CGFloat(min(width, height))).rounded()))
            let points = spot.region.samples.map { CGPoint(x: $0.point.x * CGFloat(width), y: $0.point.y * CGFloat(height)) }
            let minX = points.map(\.x).min()!, maxX = points.map(\.x).max()!
            let minY = points.map(\.y).min()!, maxY = points.map(\.y).max()!
            centerX = Int(((minX + maxX) / 2).rounded())
            centerY = Int(((minY + maxY) / 2).rounded())
            bounds = CGRect(x: minX - CGFloat(radius), y: minY - CGFloat(radius),
                            width: maxX - minX + CGFloat(radius * 2),
                            height: maxY - minY + CGFloat(radius * 2))
        }
    }
}

private extension Array where Element == RetouchSourceCandidate {
    func uniquedOffsets() -> Self {
        var seen = Set<String>()
        return filter { seen.insert("\($0.offset.dx),\($0.offset.dy)").inserted }
    }
}

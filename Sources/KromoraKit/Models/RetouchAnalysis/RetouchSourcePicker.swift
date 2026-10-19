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

        let blockers = Self.blockers(for: shape, among: spots, excluding: spot.id)
        var best: [RetouchSourceCandidate] = []
        for (x, y) in points {
            if cancellation?() == true { return [] }
            guard valid(centerX: x, centerY: y, shape: shape, blockers: blockers) else { continue }
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
                guard valid(centerX: x, centerY: y, shape: shape, blockers: blockers) else { continue }
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
        let blockers = Self.blockers(for: shape, among: spots, excluding: spot.id)
        var refined: [RetouchSourceCandidate] = []
        for candidate in candidates.prefix(max(0, limit)) {
            if cancellation?() == true { return candidates }
            let baseX = shape.centerX + Int((candidate.offset.dx * CGFloat(shape.width)).rounded())
            let baseY = shape.centerY - Int((candidate.offset.dy * CGFloat(shape.height)).rounded())
            guard region.lab(sourceX: shape.centerX, sourceY: shape.centerY) != nil,
                  region.lab(sourceX: baseX, sourceY: baseY) != nil else { continue }
            for dy in -2...2 { for dx in -2...2 {
                let x = baseX + dx, y = baseY + dy
                guard valid(centerX: x, centerY: y, shape: shape, blockers: blockers) else { continue }
                refined.append(RetouchSourceCandidate(
                    offset: CGVector(dx: CGFloat(x - shape.centerX) / CGFloat(shape.width),
                                     dy: -CGFloat(y - shape.centerY) / CGFloat(shape.height)),
                    score: score(centerX: x, centerY: y, shape: shape, sample: region.lab)
                ))
            } }
        }
        return Array((refined + candidates).sorted(by: candidateOrder).uniquedOffsets().prefix(candidates.count))
    }

    /// Rounds each offset to whole source pixels so Core Image copies the fill without resampling it
    /// (a fractional offset smooths the grain and fails the variance limit). Candidates that collapse
    /// onto the same pixel offset keep their best rank.
    static func snapped(_ candidates: [RetouchSourceCandidate], sourceWidth: Int, sourceHeight: Int)
        -> [RetouchSourceCandidate] {
        guard sourceWidth > 0, sourceHeight > 0 else { return candidates }
        let w = CGFloat(sourceWidth), h = CGFloat(sourceHeight)
        return candidates.map {
            RetouchSourceCandidate(
                offset: CGVector(dx: ($0.offset.dx * w).rounded() / w, dy: ($0.offset.dy * h).rounded() / h),
                score: $0.score)
        }.uniquedOffsets()
    }

    private static func candidateOrder(_ a: RetouchSourceCandidate, _ b: RetouchSourceCandidate) -> Bool {
        if a.score != b.score { return a.score < b.score }
        if a.offset.dy != b.offset.dy { return a.offset.dy < b.offset.dy }
        return a.offset.dx < b.offset.dx
    }

    /// Geometry a translated destination stroke must keep clear of: the stroke itself and every other
    /// visible spot. `reach` is the Chebyshev centre distance below which two brush discs (plus margin)
    /// overlap, so a single dab reproduces the old box test while a long hair only blocks placements
    /// that actually cross its path.
    private struct Blocker {
        let grid: [Cell: [CGPoint]]
        let cell: CGFloat
        let reach: CGFloat
        let bounds: CGRect

        struct Cell: Hashable { let x: Int; let y: Int }

        init(points: [CGPoint], bounds: CGRect, reach: CGFloat) {
            cell = max(1, reach)
            self.reach = reach
            self.bounds = bounds
            var grid: [Cell: [CGPoint]] = [:]
            for p in points { grid[Cell(x: Int((p.x / cell).rounded(.down)), y: Int((p.y / cell).rounded(.down))), default: []].append(p) }
            self.grid = grid
        }

        func blocks(_ points: [CGPoint], dx: CGFloat, dy: CGFloat) -> Bool {
            for p in points {
                let q = CGPoint(x: p.x + dx, y: p.y + dy)
                let cx = Int((q.x / cell).rounded(.down)), cy = Int((q.y / cell).rounded(.down))
                for gy in cy - 1...cy + 1 { for gx in cx - 1...cx + 1 {
                    guard let near = grid[Cell(x: gx, y: gy)] else { continue }
                    for o in near where abs(o.x - q.x) < reach && abs(o.y - q.y) < reach { return true }
                } }
            }
            return false
        }
    }

    private static func blockers(for shape: Shape, among spots: [RetouchSpot], excluding id: UUID) -> [Blocker] {
        let margin = CGFloat(shape.margin)
        var result = [Blocker(points: shape.path, bounds: shape.bounds,
                              reach: CGFloat(shape.radius * 2) + margin * 2 + shape.slack * 2)]
        for other in spots where other.id != id && !other.isIdentity {
            guard let otherShape = Shape(spot: other, width: shape.width, height: shape.height) else { continue }
            result.append(Blocker(points: otherShape.path, bounds: otherShape.bounds,
                                  reach: CGFloat(shape.radius + otherShape.radius) + margin * 2
                                      + shape.slack + otherShape.slack))
        }
        return result
    }

    private static func valid(centerX: Int, centerY: Int, shape: Shape, blockers: [Blocker]) -> Bool {
        let margin = CGFloat(shape.margin)
        let dx = CGFloat(centerX - shape.centerX), dy = CGFloat(centerY - shape.centerY)
        let candidate = shape.bounds.offsetBy(dx: dx, dy: dy).insetBy(dx: -margin, dy: -margin)
        guard candidate.minX >= 0, candidate.minY >= 0,
              candidate.maxX < CGFloat(shape.width), candidate.maxY < CGFloat(shape.height) else { return false }
        for blocker in blockers {
            // Cheap reject first; only strokes whose boxes touch need the path test.
            guard overlaps(candidate, blocker.bounds.insetBy(dx: -margin, dy: -margin)) else { continue }
            if blocker.blocks(shape.path, dx: dx, dy: dy) { return false }
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
        let shiftX = centerX - shape.centerX, shiftY = centerY - shape.centerY
        for anchor in shape.anchors {
          let ax = anchor.x, ay = anchor.y
          for dy in stride(from: -outer, through: outer, by: sampleStep) {
            for dx in stride(from: -outer, through: outer, by: sampleStep) {
              let r2 = dx * dx + dy * dy
              guard r2 <= outer * outer && r2 >= shape.radius * shape.radius else { continue }
              // Along a long stroke the ring crosses the stroke's own neighbouring path: not trusted surround.
              if shape.isLong && shape.isOnStroke(ax + dx, ay + dy) { continue }
              guard let a = sample(ax + dx, ay + dy),
                    let b = sample(ax + shiftX + dx, ay + shiftY + dy) else { continue }
              let dl = Double(a.x - b.x), da = Double(a.y - b.y), db = Double(a.z - b.z)
              color += dl * dl + da * da + db * db
              if let ax1 = sample(ax + dx + 1, ay + dy),
                 let bx1 = sample(ax + shiftX + dx + 1, ay + shiftY + dy) {
                  let ga = hypot(Double(ax1.x - a.x), Double(ax1.y - a.y))
                  let gb = hypot(Double(bx1.x - b.x), Double(bx1.y - b.y))
                  gradient += (ga - gb) * (ga - gb)
              }
              let destinationGradient = sample(ax + dx + 1, ay + dy).map {
                  hypot(Double($0.x - a.x), Double($0.y - a.y))
              } ?? 0
              ringTexture += destinationGradient
              ringCount += 1
            }
          }
          for dy in stride(from: -shape.radius, through: shape.radius, by: sampleStep) {
            for dx in stride(from: -shape.radius, through: shape.radius, by: sampleStep)
              where dx * dx + dy * dy < shape.radius * shape.radius {
              guard let center = sample(ax + shiftX + dx, ay + shiftY + dy),
                    let right = sample(ax + shiftX + dx + 1, ay + shiftY + dy),
                    let down = sample(ax + shiftX + dx, ay + shiftY + dy + 1) else { continue }
              interiorTexture += hypot(Double(right.x - center.x), Double(right.y - center.y))
                  + hypot(Double(down.x - center.x), Double(down.y - center.y))
              interiorCount += 2
            }
          }
        }
        guard ringCount > 0, interiorCount > 0 else { return .infinity }
        let distance = hypot(Double(shiftX), Double(shiftY)) / Double(max(1, shape.radius * 6))
        let textureMismatch = abs(interiorTexture / interiorCount - ringTexture / ringCount)
        return color / ringCount + gradient / ringCount * 0.35 + textureMismatch * 0.08 + distance * 0.35
    }

    private struct Shape {
        let centerX: Int; let centerY: Int; let radius: Int; let width: Int; let height: Int
        let bounds: CGRect
        /// Stroke polyline resampled at `spacing` (top-down pixels); one point for a single dab.
        let path: [CGPoint]
        /// Half the resampling gap, added to overlap tests so gaps between path points cannot hide a crossing.
        let slack: CGFloat
        var margin: Int { max(2, radius / 3) }
        /// Scoring anchors: the centre for a compact stroke, points spread along a long one so the
        /// match is judged around the whole hair rather than only its midpoint.
        let anchors: [(x: Int, y: Int)]
        let isLong: Bool

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

            let spacing = max(1, CGFloat(radius) / 2)
            var dense = [points[0]]
            for (a, b) in zip(points, points.dropFirst()) {
                let length = hypot(b.x - a.x, b.y - a.y)
                let steps = max(1, Int((length / spacing).rounded(.up)))
                for step in 1...steps {
                    let t = CGFloat(step) / CGFloat(steps)
                    let p = CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
                    if hypot(p.x - dense[dense.count - 1].x, p.y - dense[dense.count - 1].y) >= spacing * 0.5 { dense.append(p) }
                }
            }
            path = dense
            slack = dense.count > 1 ? spacing / 2 : 0

            isLong = hypot(maxX - minX, maxY - minY) >= CGFloat(radius * 4)
            if isLong {
                let count = min(8, max(2, Int(hypot(maxX - minX, maxY - minY) / CGFloat(radius * 2))))
                anchors = (0..<count).map { i in
                    let p = dense[(dense.count - 1) * i / (count - 1)]
                    return (Int(p.x.rounded()), Int(p.y.rounded()))
                }
            } else {
                anchors = [(centerX, centerY)]
            }
        }

        /// True when (x, y) lies on the stroke itself, within `radius` of any path point.
        func isOnStroke(_ x: Int, _ y: Int) -> Bool {
            let r = CGFloat(radius)
            return path.contains { hypot($0.x - CGFloat(x), $0.y - CGFloat(y)) < r }
        }
    }
}

private extension Array where Element == RetouchSourceCandidate {
    func uniquedOffsets() -> Self {
        var seen = Set<String>()
        return filter { seen.insert("\($0.offset.dx),\($0.offset.dy)").inserted }
    }
}

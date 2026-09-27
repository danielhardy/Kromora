import Foundation
import simd

/// Deterministic PatchMatch correspondence solver for small Remove regions.
///
/// Coordinates in the returned field are absolute pixel coordinates in the input image. Entries
/// outside the destination mask (inside `field.bounds`, in row-major order) are `(-1, -1)`.
enum PatchMatchInpainter {
    struct Image: Sendable, Equatable {
        let width: Int
        let height: Int
        let lab: [SIMD3<Float>]

        init(width: Int, height: Int, lab: [SIMD3<Float>]) {
            self.width = width
            self.height = height
            self.lab = lab.count == width * height ? lab : []
        }
    }

    struct Field: Sendable, Equatable {
        let x: Int
        let y: Int
        let width: Int
        let height: Int
        let coordinates: [SIMD2<Float>]

        subscript(x: Int, y: Int) -> SIMD2<Float>? {
            guard x >= self.x, y >= self.y, x < self.x + width, y < self.y + height else { return nil }
            return coordinates[(y - self.y) * width + (x - self.x)]
        }

        /// RG32F-compatible interleaved storage for texture upload.
        var rg32f: [Float] {
            coordinates.flatMap { [$0.x, $0.y] }
        }
    }

    struct Input: Sendable {
        let image: Image
        /// Nonzero means this pixel is a destination pixel to fill.
        let holeMask: [UInt8]
        /// Nonzero pixels must be avoided by source patches (usually other dilated holes).
        let exclusionMask: [UInt8]
        let seed: UInt32
        /// KRMA-660 source offset in image pixels.
        let initialOffset: SIMD2<Int>
        /// Cancellation is polled inside propagation and random-search loops.
        let isCancelled: @Sendable () -> Bool

        init(image: Image, holeMask: [UInt8], exclusionMask: [UInt8], seed: UInt32,
             initialOffset: SIMD2<Int>, isCancelled: @escaping @Sendable () -> Bool = { false }) {
            self.image = image
            self.holeMask = holeMask
            self.exclusionMask = exclusionMask
            self.seed = seed
            self.initialOffset = initialOffset
            self.isCancelled = isCancelled
        }
    }

    enum SolverError: Error, Equatable { case invalidInput, noValidSource, cancelled }

    static func patchSize(for holeMask: [UInt8], width: Int, height: Int) -> Int {
        guard width > 0, height > 0, holeMask.count == width * height else { return 7 }
        var minX = width, maxX = -1, minY = height, maxY = -1
        for i in holeMask.indices where holeMask[i] != 0 {
            let x = i % width, y = i / width
            minX = min(minX, x); maxX = max(maxX, x)
            minY = min(minY, y); maxY = max(maxY, y)
        }
        guard maxX >= minX else { return 7 }
        let shortDimension = min(maxX - minX + 1, maxY - minY + 1)
        return shortDimension < 6 ? 5 : 7
    }

    static func solve(_ input: Input) throws -> Field {
        let image = input.image
        guard image.width > 0, image.height > 0, image.lab.count == image.width * image.height,
              input.holeMask.count == image.lab.count, input.exclusionMask.count == image.lab.count else {
            throw SolverError.invalidInput
        }
        if input.isCancelled() { throw SolverError.cancelled }
        let width = image.width, height = image.height, count = image.lab.count
        var minX = width, maxX = -1, minY = height, maxY = -1
        for i in input.holeMask.indices where input.holeMask[i] != 0 {
            let x = i % width, y = i / width
            minX = min(minX, x); maxX = max(maxX, x)
            minY = min(minY, y); maxY = max(maxY, y)
        }
        guard maxX >= minX else { throw SolverError.invalidInput }

        let patch = patchSize(for: input.holeMask, width: width, height: height)
        let radius = patch / 2
        var forbidden = [UInt8](repeating: 0, count: count)
        for i in 0..<count { forbidden[i] = input.holeMask[i] | input.exclusionMask[i] }
        // Summed area table makes the all-pixels-outside-all-holes source-patch check O(1).
        var integral = [Int](repeating: 0, count: (width + 1) * (height + 1))
        for y in 0..<height {
            var row = 0
            for x in 0..<width {
                row += forbidden[y * width + x] == 0 ? 0 : 1
                integral[(y + 1) * (width + 1) + x + 1] = integral[y * (width + 1) + x + 1] + row
            }
        }
        func validSource(_ x: Int, _ y: Int) -> Bool {
            guard x >= radius, y >= radius, x + radius < width, y + radius < height else { return false }
            let stride = width + 1
            let sum = integral[(y + radius + 1) * stride + x + radius + 1]
                - integral[(y - radius) * stride + x + radius + 1]
                - integral[(y + radius + 1) * stride + x - radius]
                + integral[(y - radius) * stride + x - radius]
            return sum == 0
        }
        var validSources: [Int] = []
        if width > patch && height > patch {
            for y in radius..<(height - radius) { for x in radius..<(width - radius) where validSource(x, y) {
                validSources.append(y * width + x)
            } }
        }
        guard !validSources.isEmpty else { throw SolverError.noValidSource }

        let boxWidth = maxX - minX + 1, boxHeight = maxY - minY + 1
        var coords = [Int](repeating: -1, count: boxWidth * boxHeight)
        var scores = [Float](repeating: .infinity, count: coords.count)
        var rng = SplitMix32(state: input.seed)
        let ox = input.initialOffset.x, oy = input.initialOffset.y

        func score(targetX tx: Int, targetY ty: Int, sourceX sx: Int, sourceY sy: Int) -> Float {
            guard validSource(sx, sy) else { return .infinity }
            var color: Float = 0, gradient: Float = 0, samples: Float = 0, gradients: Float = 0
            for dy in -radius...radius { for dx in -radius...radius {
                let x = tx + dx, y = ty + dy, xx = sx + dx, yy = sy + dy
                guard x >= 0, y >= 0, x < width, y < height,
                      input.holeMask[y * width + x] == 0,
                      input.exclusionMask[y * width + x] == 0 else { continue }
                let a = image.lab[y * width + x], b = image.lab[yy * width + xx]
                let d = a - b
                color += simd_dot(d, d)
                samples += 1
                // Compare centered image gradients. This rewards a source patch whose edge
                // orientation and continuation agree with the visible context around a wire.
                if x + 1 < width, xx + 1 < width, y + 1 < height, yy + 1 < height,
                   input.holeMask[y * width + x + 1] == 0, input.holeMask[(y + 1) * width + x] == 0 {
                    let gxA = image.lab[y * width + x + 1] - a
                    let gyA = image.lab[(y + 1) * width + x] - a
                    let gxB = image.lab[yy * width + xx + 1] - b
                    let gyB = image.lab[(yy + 1) * width + xx] - b
                    let dxGradient = gxA - gxB, dyGradient = gyA - gyB
                    gradient += simd_dot(dxGradient, dxGradient) + simd_dot(dyGradient, dyGradient)
                    gradients += 2
                }
            } }
            // Large soft-dust masks can fully cover an inner target patch. Keep the source
            // candidate usable; its neighboring propagated patches still carry the boundary.
            guard samples > 0 else { return 1_000_000 }
            let offsetX = Float((sx - tx) - ox), offsetY = Float((sy - ty) - oy)
            // The source picker supplies a useful spatial prior. Prefer its coherent patch flow
            // when the visible patch costs tie (common in sky/grain), while allowing a clear edge
            // continuation match to move the correspondence elsewhere.
            let prior = (offsetX * offsetX + offsetY * offsetY) * 0.03
            return color / samples + (gradients > 0 ? gradient / gradients * 1.6 : 0) + prior
        }
        func consider(_ slot: Int, _ tx: Int, _ ty: Int, _ sx: Int, _ sy: Int) {
            let candidate = score(targetX: tx, targetY: ty, sourceX: sx, sourceY: sy)
            // Strict comparison preserves deterministic first-candidate tie breaking.
            if candidate < scores[slot] { scores[slot] = candidate; coords[slot] = sy * width + sx }
        }

        // Initialize every hole pixel from KRMA-660's offset, falling back to the nearest
        // deterministic valid source if the supplied offset lands in an exclusion.
        for y in minY...maxY { for x in minX...maxX where input.holeMask[y * width + x] != 0 {
            if input.isCancelled() { throw SolverError.cancelled }
            let slot = (y - minY) * boxWidth + x - minX
            let sx = x + ox, sy = y + oy
            if validSource(sx, sy) { consider(slot, x, y, sx, sy) }
            else {
                let nearest = validSources.min { a, b in
                    let ax = a % width - sx, ay = a / width - sy
                    let bx = b % width - sx, by = b / width - sy
                    let da = ax * ax + ay * ay, db = bx * bx + by * by
                    return da == db ? a < b : da < db
                }!
                consider(slot, x, y, nearest % width, nearest / width)
            }
        } }

        // Forward/reverse propagation followed by seeded, geometrically shrinking search gives
        // the usual coarse-to-fine PatchMatch schedule without allocating pyramid image copies.
        let extent = max(width, height)
        let searchRadii = [max(1, extent / 4), max(1, extent / 16), max(1, extent / 64)]
        for radiusSearch in searchRadii {
            for reverse in [false, true] {
                let ys: [Int] = reverse ? Array((minY...maxY).reversed()) : Array(minY...maxY)
                let xs: [Int] = reverse ? Array((minX...maxX).reversed()) : Array(minX...maxX)
                for y in ys { for x in xs where input.holeMask[y * width + x] != 0 {
                    if input.isCancelled() { throw SolverError.cancelled }
                    let slot = (y - minY) * boxWidth + x - minX
                    for (nx, ny) in reverse ? [(x + 1, y), (x, y + 1)] : [(x - 1, y), (x, y - 1)] {
                        guard nx >= minX, ny >= minY, nx <= maxX, ny <= maxY else { continue }
                        let neighbor = (ny - minY) * boxWidth + nx - minX
                        guard coords[neighbor] >= 0 else { continue }
                        let deltaX = x - nx, deltaY = y - ny
                        let source = coords[neighbor]
                        consider(slot, x, y, source % width + deltaX, source / width + deltaY)
                    }
                    var range = radiusSearch
                    while range >= 1 {
                        let best = coords[slot]
                        let bx = best % width, by = best / width
                        let rx = bx + rng.symmetric(range), ry = by + rng.symmetric(range)
                        consider(slot, x, y, rx, ry)
                        range /= 2
                    }
                } }
            }
        }

        // Weighted voting among overlapping patch matches stabilizes the compact field while
        // retaining exact source coordinates when a neighbor is materially less similar.
        let raw = coords
        for y in minY...maxY { for x in minX...maxX where input.holeMask[y * width + x] != 0 {
            let slot = (y - minY) * boxWidth + x - minX
            if input.isCancelled() { throw SolverError.cancelled }
            let own = raw[slot]
            var sumX = Double(own % width), sumY = Double(own / width), total = 1.0
            for dy in -2...2 { for dx in -2...2 where dx != 0 || dy != 0 {
                let nx = x + dx, ny = y + dy
                guard nx >= minX, nx <= maxX, ny >= minY, ny <= maxY,
                      input.holeMask[ny * width + nx] != 0 else { continue }
                let neighborSlot = (ny - minY) * boxWidth + nx - minX
                let candidate = raw[neighborSlot]
                guard candidate >= 0 else { continue }
                let weight = 1.0 / (1.0 + hypot(Double(dx), Double(dy)))
                sumX += Double(candidate % width) * weight
                sumY += Double(candidate / width) * weight
                total += weight
            } }
            let votedX = Int((sumX / total).rounded()), votedY = Int((sumY / total).rounded())
            if validSource(votedX, votedY) { coords[slot] = votedY * width + votedX }
        } }

        var field = [SIMD2<Float>](repeating: SIMD2(-1, -1), count: boxWidth * boxHeight)
        for y in minY...maxY { for x in minX...maxX where input.holeMask[y * width + x] != 0 {
            let source = coords[(y - minY) * boxWidth + x - minX]
            guard source >= 0, validSource(source % width, source / width) else { throw SolverError.noValidSource }
            field[(y - minY) * boxWidth + x - minX] = SIMD2(Float(source % width), Float(source / width))
        } }
        if input.isCancelled() { throw SolverError.cancelled }
        return Field(x: minX, y: minY, width: boxWidth, height: boxHeight, coordinates: field)
    }
}

private struct SplitMix32 {
    var state: UInt32
    mutating func next() -> UInt32 {
        state &+= 0x9e3779b9
        var value = state
        value = (value ^ (value >> 16)) &* 0x85ebca6b
        value = (value ^ (value >> 13)) &* 0xc2b2ae35
        return value ^ (value >> 16)
    }
    mutating func symmetric(_ radius: Int) -> Int {
        guard radius > 0 else { return 0 }
        return Int(next() % UInt32(radius * 2 + 1)) - radius
    }
}

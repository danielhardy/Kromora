import CoreGraphics
import Foundation

/// Maps points anchored to the EXIF-oriented source frame through the document geometry.
/// Points use upper-left normalized coordinates so saved edits remain tied to image content.
struct GeometryPointMapping: Sendable {
    let sourceSize: CGSize
    let rotation: ImageRotation
    let crop: CropAdjustments

    init(sourceSize: CGSize, rotation: ImageRotation = .zero, crop: CropAdjustments = .neutral) {
        self.sourceSize = sourceSize
        self.rotation = rotation
        self.crop = crop
    }

    var outputSize: CGSize {
        RenderPipeline.geometryExtent(of: rotation.orientedExtent(sourceSize), for: crop)
    }

    /// Maps a point from oriented-source normalized space to post-geometry normalized space.
    func forward(_ point: CGPoint) -> CGPoint? {
        guard valid else { return nil }
        let rotated = rotate(point)
        var x = rotated.x
        var y = rotated.y
        if crop.flipHorizontal { x = 1 - x }
        if crop.flipVertical { y = 1 - y }

        let orientedSize = rotation.orientedExtent(sourceSize)
        let aabb = RenderPipeline.geometryExtent(of: orientedSize, for: crop)
        let radians = crop.straightenAngle * .pi / 180
        let dx = x * orientedSize.width - orientedSize.width / 2
        let dy = orientedSize.height / 2 - y * orientedSize.height
        // Core Image's positive affine angle is counter-clockwise in its y-up coordinate space.
        let px = cos(radians) * dx - sin(radians) * dy + aabb.width / 2
        let py = aabb.height / 2 - (sin(radians) * dx + cos(radians) * dy)
        let normalized = CGPoint(x: px / aabb.width, y: py / aabb.height)
        return perspectiveForward(normalized)
    }

    /// Maps a post-geometry normalized point back to oriented-source normalized space.
    func inverse(_ point: CGPoint) -> CGPoint? {
        guard valid, let unwarped = perspectiveInverse(point) else { return nil }
        let orientedSize = rotation.orientedExtent(sourceSize)
        let aabb = RenderPipeline.geometryExtent(of: orientedSize, for: crop)
        let px = unwarped.x * aabb.width - aabb.width / 2
        let py = aabb.height / 2 - unwarped.y * aabb.height
        let radians = -crop.straightenAngle * .pi / 180
        let x = cos(radians) * px - sin(radians) * py + orientedSize.width / 2
        let y = orientedSize.height / 2 - (sin(radians) * px + cos(radians) * py)
        var source = CGPoint(x: x / orientedSize.width, y: y / orientedSize.height)
        if crop.flipHorizontal { source.x = 1 - source.x }
        if crop.flipVertical { source.y = 1 - source.y }
        return inverseRotate(source)
    }

    /// Local radius scale in the output frame for a source-space radius, accounting for perspective.
    func forwardRadiusScale(at point: CGPoint) -> CGFloat? {
        guard let center = forward(point), let right = forward(CGPoint(x: point.x + 0.0001, y: point.y)),
              let down = forward(CGPoint(x: point.x, y: point.y + 0.0001)) else { return nil }
        let sx = hypot(right.x - center.x, right.y - center.y) * 10_000
        let sy = hypot(down.x - center.x, down.y - center.y) * 10_000
        return (sx + sy) / 2
    }

    /// Maps an oriented-source point all the way to the viewport, composing geometry with the
    /// existing crop and canvas presentation transform.
    func viewportPoint(
        forRetouchPoint point: CGPoint,
        navigation: CanvasNavigation,
        viewportSize: CGSize,
        backingScale: CGFloat = 1
    ) -> CGPoint? {
        guard let postGeometry = forward(point) else { return nil }
        let transform = CanvasMaskTransform(
            sourceSize: outputSize, crop: crop, navigation: navigation,
            viewportSize: viewportSize, backingScale: backingScale
        )
        return transform.viewportPoint(forSourceNormalized: postGeometry)
    }

    /// Maps a viewport point back through canvas, crop, and geometry into oriented-source space.
    func retouchPoint(
        forViewport point: CGPoint,
        navigation: CanvasNavigation,
        viewportSize: CGSize,
        backingScale: CGFloat = 1
    ) -> CGPoint? {
        let transform = CanvasMaskTransform(
            sourceSize: outputSize, crop: crop, navigation: navigation,
            viewportSize: viewportSize, backingScale: backingScale
        )
        guard let postGeometry = transform.sourceNormalizedPoint(forViewport: point) else { return nil }
        return inverse(postGeometry)
    }

    private var valid: Bool {
        sourceSize.width.isFinite && sourceSize.height.isFinite
            && sourceSize.width > 0 && sourceSize.height > 0
    }

    private func rotate(_ point: CGPoint) -> CGPoint {
        switch rotation {
        case .zero: return point
        case .clockwise90: return CGPoint(x: 1 - point.y, y: point.x)
        case .half: return CGPoint(x: 1 - point.x, y: 1 - point.y)
        case .counterClockwise90: return CGPoint(x: point.y, y: 1 - point.x)
        }
    }

    private func inverseRotate(_ point: CGPoint) -> CGPoint {
        switch rotation {
        case .zero: return point
        case .clockwise90: return CGPoint(x: point.y, y: 1 - point.x)
        case .half: return CGPoint(x: 1 - point.x, y: 1 - point.y)
        case .counterClockwise90: return CGPoint(x: 1 - point.y, y: point.x)
        }
    }

    private func perspectiveForward(_ point: CGPoint) -> CGPoint? {
        guard crop.verticalPerspective != 0 || crop.horizontalPerspective != 0 else { return point }
        let v = crop.verticalPerspective * 0.45
        let h = crop.horizontalPerspective * 0.45
        let quad = [CGPoint(x: v, y: -h), CGPoint(x: 1-v, y: h),
                    CGPoint(x: 1+v, y: 1+h), CGPoint(x: -v, y: 1-h)]
        return project(point, from: quad, to: [CGPoint(x: 0,y: 0), CGPoint(x: 1,y: 0), CGPoint(x: 1,y: 1), CGPoint(x: 0,y: 1)])
    }

    private func perspectiveInverse(_ point: CGPoint) -> CGPoint? {
        guard crop.verticalPerspective != 0 || crop.horizontalPerspective != 0 else { return point }
        let v = crop.verticalPerspective * 0.45
        let h = crop.horizontalPerspective * 0.45
        let quad = [CGPoint(x: v, y: -h), CGPoint(x: 1-v, y: h),
                    CGPoint(x: 1+v, y: 1+h), CGPoint(x: -v, y: 1-h)]
        return project(point, from: [CGPoint(x: 0,y: 0), CGPoint(x: 1,y: 0), CGPoint(x: 1,y: 1), CGPoint(x: 0,y: 1)], to: quad)
    }

    /// Four-point projective mapping, solved as an 8×8 linear system.
    private func project(_ point: CGPoint, from source: [CGPoint], to destination: [CGPoint]) -> CGPoint? {
        guard source.count == 4, destination.count == 4 else { return nil }
        var matrix = [[Double]]()
        for index in 0..<4 {
            let x = Double(source[index].x), y = Double(source[index].y)
            let u = Double(destination[index].x), v = Double(destination[index].y)
            matrix.append([x, y, 1, 0, 0, 0, -u*x, -u*y, u])
            matrix.append([0, 0, 0, x, y, 1, -v*x, -v*y, v])
        }
        for column in 0..<8 {
            guard let pivot = (column..<8).max(by: { abs(matrix[$0][column]) < abs(matrix[$1][column]) }),
                  abs(matrix[pivot][column]) > 1e-12 else { return nil }
            matrix.swapAt(column, pivot)
            let divisor = matrix[column][column]
            for j in column..<9 { matrix[column][j] /= divisor }
            for row in 0..<8 where row != column {
                let factor = matrix[row][column]
                for j in column..<9 { matrix[row][j] -= factor * matrix[column][j] }
            }
        }
        let c = matrix.map { $0[8] }
        let x = Double(point.x), y = Double(point.y)
        let denominator = c[6]*x + c[7]*y + 1
        guard denominator.isFinite, abs(denominator) > 1e-12 else { return nil }
        return CGPoint(x: (c[0]*x + c[1]*y + c[2]) / denominator,
                       y: (c[3]*x + c[4]*y + c[5]) / denominator)
    }
}

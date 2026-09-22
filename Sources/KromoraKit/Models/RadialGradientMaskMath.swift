import CoreGraphics
import Foundation

/// Resolution-independent geometry and falloff for radial masks.
///
/// Radial definitions use normalized source coordinates, but rotation is a visual operation in
/// source-pixel space. Keeping that conversion here gives the canvas, accessibility actions, and
/// the renderer the same answer on non-square sources.
enum RadialGradientMaskMath {
    static let minimumRadius = 0.0001

    static func alpha(
        at point: CGPoint,
        definition: RadialGradientDefinition,
        sourceSize: CGSize = CGSize(width: 1, height: 1)
    ) -> Double {
        let coverage = insideCoverage(at: point, definition: definition, sourceSize: sourceSize)
        return coverage * definition.density
    }

    static func insideCoverage(
        at point: CGPoint,
        definition: RadialGradientDefinition,
        sourceSize: CGSize = CGSize(width: 1, height: 1)
    ) -> Double {
        let size = validSourceSize(sourceSize)
        let local = localPixelPoint(
            at: point, center: definition.center, rotation: definition.rotation, sourceSize: size
        )
        let radiusX = max(definition.horizontalRadius * size.width, minimumRadius)
        let radiusY = max(definition.verticalRadius * size.height, minimumRadius)
        let distance = hypot(local.x / radiusX, local.y / radiusY)
        let inner = max(0, 1 - definition.feather)
        let inside = distance <= inner
            ? 1
            : 1 - smoothstep(inner, 1, distance)
        return definition.isInside ? inside : 1 - inside
    }

    static func innerPoint(
        _ parameter: Double,
        definition: RadialGradientDefinition,
        sourceSize: CGSize = CGSize(width: 1, height: 1)
    ) -> CGPoint {
        let scale = max(0, 1 - definition.feather)
        return point(
            parameter, horizontalRadius: definition.horizontalRadius * scale,
            verticalRadius: definition.verticalRadius * scale, center: definition.center,
            rotation: definition.rotation, sourceSize: sourceSize
        )
    }

    static func point(
        _ parameter: Double,
        horizontalRadius: Double,
        verticalRadius: Double,
        center: CGPoint,
        rotation: Double,
        sourceSize: CGSize = CGSize(width: 1, height: 1)
    ) -> CGPoint {
        let size = validSourceSize(sourceSize)
        let x = cos(parameter) * horizontalRadius * size.width
        let y = sin(parameter) * verticalRadius * size.height
        let cosine = cos(rotation)
        let sine = sin(rotation)
        return CGPoint(
            x: center.x + (x * cosine - y * sine) / size.width,
            y: center.y + (x * sine + y * cosine) / size.height
        )
    }

    /// Converts a normalized source point to the ellipse's unrotated source-pixel axes.
    static func localPixelPoint(
        at point: CGPoint,
        center: CGPoint,
        rotation: Double,
        sourceSize: CGSize = CGSize(width: 1, height: 1)
    ) -> CGPoint {
        let size = validSourceSize(sourceSize)
        let x = (point.x - center.x) * size.width
        let y = (point.y - center.y) * size.height
        let cosine = cos(rotation)
        let sine = sin(rotation)
        return CGPoint(x: x * cosine + y * sine, y: -x * sine + y * cosine)
    }

    static func normalizedPoint(
        fromLocalPixel point: CGPoint,
        around center: CGPoint,
        rotation: Double,
        sourceSize: CGSize = CGSize(width: 1, height: 1)
    ) -> CGPoint {
        let size = validSourceSize(sourceSize)
        let cosine = cos(rotation)
        let sine = sin(rotation)
        let x = point.x * cosine - point.y * sine
        let y = point.x * sine + point.y * cosine
        return CGPoint(x: center.x + x / size.width, y: center.y + y / size.height)
    }

    static func smoothstep(_ edge0: Double, _ edge1: Double, _ value: Double) -> Double {
        guard edge1 > edge0 else { return value < edge1 ? 1 : 0 }
        let t = min(max((value - edge0) / (edge1 - edge0), 0), 1)
        return t * t * (3 - 2 * t)
    }

    private static func validSourceSize(_ value: CGSize) -> CGSize {
        CGSize(
            width: value.width.isFinite && value.width > 0 ? value.width : 1,
            height: value.height.isFinite && value.height > 0 ? value.height : 1
        )
    }
}

import CoreGraphics
import Foundation

/// Resolution-independent linear-mask math. The renderer's CI kernel mirrors these equations;
/// keeping the reference implementation here gives hit testing, accessibility, and golden tests
/// one source of truth for projection and smooth falloff.
enum LinearGradientMaskMath {
    static func projection(of point: CGPoint, on definition: LinearGradientDefinition) -> Double {
        let direction = CGPoint(
            x: definition.fullStrengthPoint.x - definition.zeroStrengthPoint.x,
            y: definition.fullStrengthPoint.y - definition.zeroStrengthPoint.y
        )
        let denominator = direction.x * direction.x + direction.y * direction.y
        guard denominator > 0.0000001 else { return 0 }
        return
            ((point.x - definition.zeroStrengthPoint.x) * direction.x
            + (point.y - definition.zeroStrengthPoint.y) * direction.y) / denominator
    }

    static func alpha(at point: CGPoint, definition: LinearGradientDefinition) -> Double {
        smoothstep(0, 1, projection(of: point, on: definition)) * definition.density
    }

    static func smoothstep(_ edge0: Double, _ edge1: Double, _ value: Double) -> Double {
        guard edge1 > edge0 else { return value < edge1 ? 1 : 0 }
        let t = min(max((value - edge0) / (edge1 - edge0), 0), 1)
        return t * t * (3 - 2 * t)
    }

    static func translated(
        _ definition: LinearGradientDefinition, by delta: CGPoint
    ) -> LinearGradientDefinition {
        var result = definition
        result.zeroStrengthPoint = normalized(
            CGPoint(
                x: definition.zeroStrengthPoint.x + delta.x,
                y: definition.zeroStrengthPoint.y + delta.y
            ))
        result.fullStrengthPoint = normalized(
            CGPoint(
                x: definition.fullStrengthPoint.x + delta.x,
                y: definition.fullStrengthPoint.y + delta.y
            ))
        return result
    }

    /// Resize one endpoint from a normalized source-space pointer while keeping the opposite
    /// endpoint anchored. Projection onto the gesture-start axis deliberately ignores pointer
    /// movement perpendicular to the gradient: endpoint editing changes only the transition
    /// length, never its angle or placement.
    static func endpointEdited(
        _ definition: LinearGradientDefinition,
        edge: LinearGradientEdge,
        to point: CGPoint
    ) -> LinearGradientDefinition {
        let currentLength = definition.falloff
        guard currentLength.isFinite, point.x.isFinite, point.y.isFinite else {
            return definition
        }

        // A decoded or nearly collapsed definition still needs a finite edit direction. For a
        // nonzero segment, use its exact direction; for a collapsed segment, retain the model's
        // angle fallback so the endpoint edit remains bounded rather than becoming a redraw.
        let direction: CGPoint
        if currentLength > 0.000001 {
            direction = CGPoint(
                x: (definition.fullStrengthPoint.x - definition.zeroStrengthPoint.x) / currentLength,
                y: (definition.fullStrengthPoint.y - definition.zeroStrengthPoint.y) / currentLength
            )
        } else {
            direction = CGPoint(x: cos(definition.angle), y: sin(definition.angle))
        }
        let length: Double
        switch edge {
        case .zeroStrength:
            length = (definition.fullStrengthPoint.x - point.x) * direction.x
                + (definition.fullStrengthPoint.y - point.y) * direction.y
            return definition.changingFalloff(to: max(0, length), keeping: .fullStrength)
        case .fullStrength:
            length = (point.x - definition.zeroStrengthPoint.x) * direction.x
                + (point.y - definition.zeroStrengthPoint.y) * direction.y
            return definition.changingFalloff(to: max(0, length), keeping: .zeroStrength)
        }
    }

    private static func normalized(_ point: CGPoint) -> CGPoint {
        CGPoint(x: min(max(point.x, 0), 1), y: min(max(point.y, 0), 1))
    }
}

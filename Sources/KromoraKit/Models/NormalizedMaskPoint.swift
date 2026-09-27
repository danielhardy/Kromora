import CoreGraphics

enum NormalizedMaskPoint {
    static func clampedToUnitSquare(_ point: CGPoint) -> CGPoint {
        CGPoint(x: min(max(point.x, 0), 1), y: min(max(point.y, 0), 1))
    }
}

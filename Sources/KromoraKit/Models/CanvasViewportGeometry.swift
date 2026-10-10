import CoreGraphics

/// A top-aligned visible viewport within a larger, stable Metal surface. Coordinates used by
/// overlays and pointer input start at the same top-left origin, so no input translation is needed.
struct CanvasViewportGeometry {
    let surfaceSize: CGSize
    let viewportSize: CGSize

    init(surfaceSize: CGSize, viewportSize: CGSize?) {
        self.surfaceSize = surfaceSize
        let proposed = viewportSize ?? surfaceSize
        self.viewportSize = CGSize(
            width: Self.dimension(proposed.width, within: surfaceSize.width),
            height: Self.dimension(proposed.height, within: surfaceSize.height)
        )
    }

    func backingSize(drawableSize: CGSize) -> CGSize {
        guard surfaceSize.width > 0, surfaceSize.height > 0 else { return .zero }
        return CGSize(
            width: viewportSize.width * drawableSize.width / surfaceSize.width,
            height: viewportSize.height * drawableSize.height / surfaceSize.height
        )
    }

    private static func dimension(_ value: CGFloat, within limit: CGFloat) -> CGFloat {
        guard limit.isFinite, limit > 0 else { return 0 }
        return min(max(value.isFinite ? value : limit, 1), limit)
    }
}

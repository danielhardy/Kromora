import CoreGraphics
import Foundation

/// A rendering surface with its own resolution-planning hysteresis state.
///
/// Main-preview settled and interactive requests intentionally share one surface. Comparison and
/// histogram requests do not: they can have different viewports or crops as those features evolve,
/// so one surface's recent detail choice must not influence another's.
enum ResolutionPlannerSurface: String, Sendable {
    case mainPreview
    case comparisonBaseline
    case histogram
}

/// The discrete source detail selected for one canvas request.
///
/// `sourceSize` is the planner-sized full source decode. `visibleSourceRect` is the native-space
/// ROI that preview graph stages may consume after the cacheable decode. Full-resolution/export
/// callers continue to use the original uncropped graph.
struct ResolutionPlan: Equatable, Sendable {
    let level: Int
    let scale: CGFloat
    let requiredScale: CGFloat
    let sourceSize: CGSize
    let presentationGeometrySize: CGSize
    let cropRect: CGRect
    let visibleSourceRect: CGRect
    /// The visible viewport in normalized post-geometry coordinates. Unlike `visibleSourceRect`,
    /// this remains meaningful after a flip/straighten/perspective transform and is carried to
    /// the renderer so it can crop and place the transformed result safely.
    let visiblePresentationRect: CGRect
    let hasGeometryTransform: Bool
    let isNativeResolution: Bool

    var pixelCount: Int {
        let width = max(0, Int(sourceSize.width.rounded(.down)))
        let height = max(0, Int(sourceSize.height.rounded(.down)))
        return width.multipliedReportingOverflow(by: height).overflow
            ? Int.max : width * height
    }

    /// The committed crop frame in the same scaled coordinate system as `sourceSize`. The preview
    /// surface uses this as a virtual extent when the renderer publishes only a smaller ROI. The
    /// renderer applies straighten before crop, so this uses the geometry AABB rather than the
    /// pre-straighten source box or fit/zoom will map the committed raster onto the wrong aspect.
    var presentationImageExtent: CGRect {
        CGRect(
            x: cropRect.minX * presentationGeometrySize.width,
            y: cropRect.minY * presentationGeometrySize.height,
            width: cropRect.width * presentationGeometrySize.width,
            height: cropRect.height * presentationGeometrySize.height
        )
    }

    /// Avoid creating an ROI graph when the viewport already covers the complete source. This is
    /// the common fit case and keeps the full-image preview path a true no-op.
    func previewSourceROI(nativeExtent: CGSize) -> CGRect? {
        // A fitted geometry crop is already a complete presented photo. Keep that request on the
        // established complete-frame path; the performance win targeted here is the deep-zoom
        // viewport strip, where the transformed ROI is materially smaller than the frame.
        if hasGeometryTransform, coversPresentedPhoto(nativeExtent: nativeExtent) { return nil }
        let full = CGRect(origin: .zero, size: nativeExtent)
        guard !Self.rect(visibleSourceRect, matches: full) else { return nil }
        return visibleSourceRect
    }

    /// Whether the current visible rectangle is the complete presented photo. A fit cropped
    /// preview still has a source ROI so the renderer can skip discarded pixels, but that ROI
    /// *is* the photo on screen and must fill the canvas like an uncropped fit frame.
    func coversPresentedPhoto(nativeExtent: CGSize) -> Bool {
        _ = nativeExtent
        let epsilon: CGFloat = 0.0001
        return abs(visiblePresentationRect.minX - cropRect.minX) <= epsilon
            && abs(visiblePresentationRect.minY - cropRect.minY) <= epsilon
            && abs(visiblePresentationRect.width - cropRect.width) <= epsilon
            && abs(visiblePresentationRect.height - cropRect.height) <= epsilon
    }

    static func roi(_ roi: CGRect, coversCrop cropRect: CGRect, nativeExtent: CGSize) -> Bool {
        guard nativeExtent.width.isFinite, nativeExtent.height.isFinite,
            nativeExtent.width > 0, nativeExtent.height > 0
        else { return false }
        let presented = CGRect(
            x: cropRect.minX * nativeExtent.width,
            y: cropRect.minY * nativeExtent.height,
            width: cropRect.width * nativeExtent.width,
            height: cropRect.height * nativeExtent.height
        )
        return rect(roi, matches: presented)
    }

    private static func rect(_ lhs: CGRect, matches rhs: CGRect) -> Bool {
        let epsilon = max(
            0.5,
            0.0001 * max(max(lhs.width, lhs.height), max(rhs.width, rhs.height))
        )
        return abs(lhs.minX - rhs.minX) <= epsilon
            && abs(lhs.minY - rhs.minY) <= epsilon
            && abs(lhs.width - rhs.width) <= epsilon
            && abs(lhs.height - rhs.height) <= epsilon
    }
}

/// Chooses a bounded, reusable resolution pyramid for the canvas.
///
/// The planner works in source-pixel scale rather than viewport-point scale. This makes it correct
/// for mixed-DPI displays and for side-by-side panels, provided the viewport is the panel's actual
/// backing-pixel size. Levels are deliberately few: a zoom gesture should revisit cache entries,
/// not manufacture one for every fractional magnification value.
struct ResolutionPlanner: Equatable, Sendable {
    /// Enough granularity for a preview while keeping the source-cache working set bounded. The
    /// native level is always the final safety net for small crops and deep inspection.
    static let detailScales: [CGFloat] = [0.125, 0.25, 0.5, 0.75, 1.0]
    static let downgradeHysteresis: CGFloat = 0.85

    private(set) var selectedLevel: Int?

    init() { selectedLevel = nil }

    mutating func reset() { selectedLevel = nil }

    mutating func plan(
        nativeExtent: CGSize,
        crop: CropAdjustments = .neutral,
        viewportSize: CGSize,
        navigation: CanvasNavigation = CanvasNavigation()
    ) -> ResolutionPlan {
        let validNative = Self.isValidSize(nativeExtent)
        let native = validNative ? nativeExtent : CGSize(width: 1, height: 1)
        let rect = crop.normalizedRect ?? CropAdjustments.unitRect
        let geometrySize = RenderPipeline.geometryExtent(of: native, for: crop)
        let cropSize = CGSize(
            width: geometrySize.width * rect.width,
            height: geometrySize.height * rect.height
        )
        let validViewport = Self.isValidSize(viewportSize)

        let fitScale: CGFloat
        let transform: CanvasTransform
        if validViewport, Self.isValidSize(cropSize) {
            transform = navigation.transform(
                imageExtent: CGRect(origin: .zero, size: cropSize), viewportSize: viewportSize
            )
            fitScale = min(
                viewportSize.width / cropSize.width,
                viewportSize.height / cropSize.height)
        } else {
            transform = CanvasTransform(scale: 1, origin: .zero, imageSize: cropSize)
            fitScale = 1
        }

        // Never choose less detail than a fit preview. A custom zoom below 1.0 changes presentation,
        // but it should not cause a previously useful source level to be discarded.
        let requestedScale = max(fitScale, transform.scale)
        let requiredScale = min(max(requestedScale.isFinite ? requestedScale : 1, 0), 1)
        // A complete-photo viewport is a hard coverage boundary, not another point in the
        // zoom gesture. After a deep zoom the hysteresis state may still be at native detail;
        // carrying that level back into fit can make the full-frame render unnecessarily large.
        // If that render fails, PreviewSurface quite correctly retains the last valid ROI frame,
        // which then leaves the newly revealed edges blank under the fit transform. Re-enter the
        // ordinary adequate level when the whole presented photo is visible and the current
        // level is materially above it. A one-level resize still keeps the existing hysteresis;
        // partial viewport pans/fills keep the existing cache reuse behavior.
        let visiblePresentationRect = Self.visiblePresentationRect(
            cropRect: rect, nativeExtent: native, cropSize: cropSize,
            transform: transform, viewportSize: viewportSize
        )
        let geometryNativeSize = RenderPipeline.geometryExtent(of: native, for: crop)
        let presentationPixels = CGRect(
            x: visiblePresentationRect.minX * geometryNativeSize.width,
            y: visiblePresentationRect.minY * geometryNativeSize.height,
            width: visiblePresentationRect.width * geometryNativeSize.width,
            height: visiblePresentationRect.height * geometryNativeSize.height
        )
        let visibleSourceRect = crop.hasGeometryTransform
            ? RenderPipeline.sourceROI(
                forPresentationROI: presentationPixels, nativeExtent: native, crop: crop
            )
            : CGRect(
                x: visiblePresentationRect.minX * native.width,
                y: visiblePresentationRect.minY * native.height,
                width: visiblePresentationRect.width * native.width,
                height: visiblePresentationRect.height * native.height
            )
        let completePresentedPhoto = ResolutionPlan(
            level: 0, scale: 1, requiredScale: 1, sourceSize: native,
            presentationGeometrySize: geometryNativeSize, cropRect: rect,
            visibleSourceRect: visibleSourceRect,
            visiblePresentationRect: visiblePresentationRect,
            hasGeometryTransform: crop.hasGeometryTransform, isNativeResolution: true
        ).coversPresentedPhoto(nativeExtent: native)
        let adequateLevel = Self.level(for: requiredScale, current: nil)
        let recoveringCompleteFrame =
            completePresentedPhoto && selectedLevel.map { $0 - adequateLevel >= 2 } == true
        let level = Self.level(
            for: requiredScale, current: recoveringCompleteFrame ? nil : selectedLevel
        )
        selectedLevel = level
        let scale = Self.detailScales[level]
        let sourceSize = CGSize(
            width: max(
                1, min(native.width, (native.width * scale).rounded(.toNearestOrAwayFromZero))),
            height: max(
                1, min(native.height, (native.height * scale).rounded(.toNearestOrAwayFromZero)))
        )

        return ResolutionPlan(
            level: level,
            scale: scale,
            requiredScale: requiredScale,
            sourceSize: sourceSize,
            presentationGeometrySize: RenderPipeline.geometryExtent(of: sourceSize, for: crop),
            cropRect: rect,
            visibleSourceRect: visibleSourceRect,
            visiblePresentationRect: visiblePresentationRect,
            hasGeometryTransform: crop.hasGeometryTransform,
            isNativeResolution: level == Self.detailScales.count - 1 || requiredScale >= 1
        )
    }

    private static func level(for required: CGFloat, current: Int?) -> Int {
        let adequate = detailScales.firstIndex { $0 >= required } ?? detailScales.count - 1
        guard let current, detailScales.indices.contains(current) else { return adequate }

        // Upgrades happen as soon as the current level is no longer adequate. A downgrade waits
        // until the next lower level has meaningful headroom, preventing boundary thrashing while
        // the user moves a pinch or resizes a window by a few pixels.
        if required > detailScales[current] { return adequate }
        guard current > 0 else { return current }
        let lower = current - 1
        return required <= detailScales[lower] * downgradeHysteresis ? lower : current
    }

    private static func visiblePresentationRect(
        cropRect: CGRect,
        nativeExtent: CGSize,
        cropSize: CGSize,
        transform: CanvasTransform,
        viewportSize: CGSize
    ) -> CGRect {
        guard isValidSize(nativeExtent), isValidSize(cropSize), isValidSize(viewportSize),
            transform.scale.isFinite, transform.scale > 0
        else {
            return CGRect(origin: .zero, size: .init(width: 1, height: 1))
        }

        let visible = CGRect(
            x: (0 - transform.origin.x) / transform.scale,
            y: (0 - transform.origin.y) / transform.scale,
            width: viewportSize.width / transform.scale,
            height: viewportSize.height / transform.scale
        ).intersection(CGRect(origin: .zero, size: cropSize))
        guard !visible.isNull, visible.width > 0, visible.height > 0 else {
            return CGRect(origin: .zero, size: .init(width: 1, height: 1))
        }
        // CanvasNavigation is y-down (0 is the top of the crop). Core Image and CropAdjustments
        // are y-up (0 is the bottom of the source). Convert only the vertical edge so a pan toward
        // the top of the photo requests the top of the source, not the bottom.
        let yUpInCrop = cropSize.height - visible.maxY
        return CGRect(
            x: cropRect.minX + visible.minX / cropSize.width * cropRect.width,
            y: cropRect.minY + yUpInCrop / cropSize.height * cropRect.height,
            width: visible.width / cropSize.width * cropRect.width,
            height: visible.height / cropSize.height * cropRect.height
        )
    }

    private static func isValidSize(_ size: CGSize) -> Bool {
        size.width.isFinite && size.height.isFinite && size.width > 0 && size.height > 0
    }
}

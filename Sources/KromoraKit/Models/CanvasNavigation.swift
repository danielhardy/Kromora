import CoreGraphics
import Foundation
import Combine

/// High-frequency, presentation-only state for the editor canvas.
///
/// This object is intentionally separate from `AppViewModel`. Pan, zoom, and crop-handle
/// updates occur at pointer frequency and should invalidate only the canvas subtree. The
/// `AppViewModel` remains the owner of the committed `EditDocument`, history, rendering, and
/// persistence boundaries.
@MainActor
final class CanvasInteractionState: ObservableObject {
    @Published private(set) var navigation = CanvasNavigation()
    @Published private(set) var isCropToolActive = false
    @Published private(set) var cropDraft: CGRect?
    @Published private(set) var cropAspectRatio: CropAspectRatio = .freeform
    @Published private(set) var cropOrientation: CropAspectRatioOrientation = .automatic
    /// Rotation accumulated while Crop is open. This remains transient until Apply so a crop
    /// session can be cancelled without changing the durable edit document.
    @Published private(set) var cropRotation: ImageRotation = .zero
    @Published private(set) var cropStraightenAngle: Double = 0
    /// The frame's physical aspect ratio captured when Straighten began. Preserving this value for
    /// Freeform is what prevents an angle change from silently stretching a user-drawn frame.
    @Published private(set) var cropPixelAspectRatio: CGFloat?
    @Published private(set) var cropFlipHorizontal = false
    @Published private(set) var cropFlipVertical = false
    @Published private(set) var cropVerticalPerspective: Double = 0
    @Published private(set) var cropHorizontalPerspective: Double = 0

    func resetForSource() {
        navigation.resetForSource()
        isCropToolActive = false
        cropDraft = nil
        cropAspectRatio = .freeform
        cropOrientation = .automatic
        cropRotation = .zero
        cropStraightenAngle = 0
        cropPixelAspectRatio = nil
        cropFlipHorizontal = false
        cropFlipVertical = false
        cropVerticalPerspective = 0
        cropHorizontalPerspective = 0
    }

    func fit() { navigation.fit() }
    func fill() { navigation.fill() }
    func reset() { navigation.reset() }
    func toggleFitAndRememberedZoom() { navigation.toggleFitAndRememberedZoom() }

    func setZoom(_ value: CGFloat) {
        navigation.setZoom(value)
    }

    func pan(by delta: CGSize, imageExtent: CGRect, viewportSize: CGSize) {
        navigation.pan(by: delta, imageExtent: imageExtent, viewportSize: viewportSize)
    }

    @discardableResult
    func beginCrop(using committedCrop: CropAdjustments, sourceSize: CGSize = .zero) -> Bool {
        guard !isCropToolActive else { return false }
        navigation.fit()
        isCropToolActive = true
        cropDraft = committedCrop.normalizedRect ?? CropAdjustments.unitRect
        cropAspectRatio = committedCrop.aspectRatio
        cropOrientation = committedCrop.orientation
        cropRotation = .zero
        cropStraightenAngle = committedCrop.straightenAngle
        cropPixelAspectRatio = nil
        cropFlipHorizontal = committedCrop.flipHorizontal
        cropFlipVertical = committedCrop.flipVertical
        cropVerticalPerspective = committedCrop.verticalPerspective
        cropHorizontalPerspective = committedCrop.horizontalPerspective
        if committedCrop.straightenAngle != 0, sourceSize.width > 0, sourceSize.height > 0 {
            cropPixelAspectRatio = Self.pixelAspectRatio(
                for: committedCrop, sourceSize: sourceSize
            )
            cropDraft = CropOverlayInteraction.constrainedToRotatedImage(
                cropDraft ?? CropAdjustments.unitRect,
                sourceSize: sourceSize,
                angle: committedCrop.straightenAngle,
                pixelAspectRatio: cropPixelAspectRatio
            )
        }
        return true
    }

    func updateCropDraft(_ normalizedRect: CGRect, sourceSize: CGSize = .zero) {
        guard isCropToolActive else { return }
        let target = cropPixelAspectRatio ?? aspectPixelRatio(for: sourceSize)
        cropDraft = CropOverlayInteraction.constrainedToRotatedImage(
            normalizedRect, sourceSize: sourceSize, angle: cropStraightenAngle,
            pixelAspectRatio: target
        )
    }

    func selectCropAspectRatio(
        _ aspectRatio: CropAspectRatio,
        orientation: CropAspectRatioOrientation = .automatic,
        imageSize: CGSize,
        sourceSize: CGSize = .zero
    ) {
        guard isCropToolActive else { return }
        let current = cropDraft ?? CropAdjustments.unitRect
        cropAspectRatio = aspectRatio
        cropOrientation = orientation
        let adjusted = CropOverlayInteraction.applying(
            aspectRatio, orientation: orientation, to: current, imageSize: imageSize
        )
        cropPixelAspectRatio = cropStraightenAngle == 0
            ? nil
            : aspectRatio.pixelRatio(
                for: validSourceSize(sourceSize) ?? imageSize, orientation: orientation
            ) ?? cropPixelAspectRatio
        cropDraft = CropOverlayInteraction.constrainedToRotatedImage(
            adjusted, sourceSize: sourceSize, angle: cropStraightenAngle,
            pixelAspectRatio: cropPixelAspectRatio
        )
    }

    func finishCrop() {
        isCropToolActive = false
        cropDraft = nil
        cropAspectRatio = .freeform
        cropOrientation = .automatic
        cropRotation = .zero
        cropStraightenAngle = 0
        cropPixelAspectRatio = nil
        cropFlipHorizontal = false
        cropFlipVertical = false
        cropVerticalPerspective = 0
        cropHorizontalPerspective = 0
    }

    func resetCropDraft() {
        guard isCropToolActive else { return }
        cropDraft = CropAdjustments.unitRect
        cropAspectRatio = .freeform
        cropOrientation = .automatic
        cropStraightenAngle = 0
        cropPixelAspectRatio = nil
        cropFlipHorizontal = false
        cropFlipVertical = false
        cropVerticalPerspective = 0
        cropHorizontalPerspective = 0
    }

    func setCropStraightenAngle(_ angle: Double, sourceSize: CGSize = .zero) {
        guard isCropToolActive else { return }
        let next = min(max(angle.isFinite ? angle : 0, -45), 45)
        let target = cropPixelAspectRatio ?? aspectPixelRatio(for: sourceSize)
        if cropPixelAspectRatio == nil { cropPixelAspectRatio = target }
        if let target, let sourceSize = validSourceSize(sourceSize), let current = cropDraft {
            cropDraft = CropOverlayInteraction.reframedForStraightenChange(
                current, sourceSize: sourceSize, oldAngle: cropStraightenAngle,
                newAngle: next, pixelAspectRatio: target
            )
        }
        cropStraightenAngle = next
    }

    func setCropVerticalPerspective(_ value: Double) {
        guard isCropToolActive else { return }
        cropVerticalPerspective = Self.clampPerspective(value)
    }

    func setCropHorizontalPerspective(_ value: Double) {
        guard isCropToolActive else { return }
        cropHorizontalPerspective = Self.clampPerspective(value)
    }

    private static func clampPerspective(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, -CropAdjustments.maximumPerspective), CropAdjustments.maximumPerspective)
    }

    func toggleCropFlip(horizontal: Bool) {
        guard isCropToolActive else { return }
        let draft = CropAdjustments(
            normalizedRect: cropDraft,
            aspectRatio: cropAspectRatio,
            orientation: cropOrientation,
            straightenAngle: cropStraightenAngle,
            flipHorizontal: cropFlipHorizontal,
            flipVertical: cropFlipVertical,
            verticalPerspective: cropVerticalPerspective,
            horizontalPerspective: cropHorizontalPerspective
        ).mirrored(horizontal: horizontal, vertical: !horizontal)
        cropDraft = draft.normalizedRect ?? CropAdjustments.unitRect
        cropFlipHorizontal = draft.flipHorizontal
        cropFlipVertical = draft.flipVertical
        cropVerticalPerspective = draft.verticalPerspective
        cropHorizontalPerspective = draft.horizontalPerspective
    }

    /// Rotate the draft crop and its coordinate system together. The rectangle is remapped before
    /// the next render so it continues to frame the same content after the quarter-turn.
    @discardableResult
    func rotateCrop(clockwise: Bool) -> Bool {
        guard isCropToolActive else { return false }
        let turns = clockwise ? 1 : -1
        let rotated = CropAdjustments(
            normalizedRect: cropDraft ?? CropAdjustments.unitRect,
            aspectRatio: cropAspectRatio,
            orientation: cropOrientation,
            straightenAngle: cropStraightenAngle,
            flipHorizontal: cropFlipHorizontal,
            flipVertical: cropFlipVertical,
            verticalPerspective: cropVerticalPerspective,
            horizontalPerspective: cropHorizontalPerspective
        ).rotated(byClockwiseQuarterTurns: turns)
        cropDraft = rotated.normalizedRect ?? CropAdjustments.unitRect
        cropFlipHorizontal = rotated.flipHorizontal
        cropFlipVertical = rotated.flipVertical
        cropVerticalPerspective = rotated.verticalPerspective
        cropHorizontalPerspective = rotated.horizontalPerspective
        cropRotation = cropRotation.addingClockwiseQuarterTurns(turns)
        return true
    }

    func cropImageSize(from committedOrientedSize: CGSize) -> CGSize {
        let quarterTurned = cropRotation.orientedExtent(committedOrientedSize)
        return RenderPipeline.geometryExtent(
            of: quarterTurned,
            for: CropAdjustments(straightenAngle: cropStraightenAngle)
        )
    }

    private func aspectPixelRatio(for sourceSize: CGSize) -> CGFloat? {
        guard sourceSize.width > 0, sourceSize.height > 0 else { return nil }
        if let ratio = cropAspectRatio.pixelRatio(
            for: sourceSize, orientation: cropOrientation
        ) {
            return ratio
        }
        guard let draft = cropDraft else { return nil }
        let frame = RenderPipeline.geometryExtent(
            of: sourceSize, for: CropAdjustments(straightenAngle: cropStraightenAngle)
        )
        guard draft.height > 0, frame.height > 0 else { return nil }
        return draft.width * frame.width / (draft.height * frame.height)
    }

    private static func pixelAspectRatio(for crop: CropAdjustments, sourceSize: CGSize) -> CGFloat? {
        guard let rect = crop.normalizedRect, rect.height > 0 else { return nil }
        let frame = RenderPipeline.geometryExtent(
            of: sourceSize, for: CropAdjustments(straightenAngle: crop.straightenAngle)
        )
        guard frame.width > 0, frame.height > 0 else { return nil }
        if !crop.aspectRatio.isFreeform,
            let ratio = crop.aspectRatio.pixelRatio(
                for: sourceSize, orientation: crop.orientation
            ) {
            return ratio
        }
        return rect.width * frame.width / (rect.height * frame.height)
    }

    private func validSourceSize(_ size: CGSize) -> CGSize? {
        size.width > 0 && size.height > 0 ? size : nil
    }

}

/// Transient presentation state for the editor canvas.
///
/// This is deliberately not part of `EditDocument`: changing how an image is viewed must never
/// change the pixels produced by export. The focal point is normalized to the source image so a
/// window/inspector resize can recompute the transform without losing the user's subject.
struct CanvasNavigation: Equatable, Sendable {
    enum Mode: String, CaseIterable, Sendable {
        case fit
        case fill
        case custom
    }

    static let minimumZoom: CGFloat = 0.1
    static let maximumZoom: CGFloat = 16

    private(set) var mode: Mode = .fit
    /// Multiplier over the mode's base scale. Fit and Fill both use 1; custom values are
    /// relative to fit, which makes the zoom control stable as the window changes size.
    private(set) var zoom: CGFloat = 1
    private(set) var focalPoint = CGPoint(x: 0.5, y: 0.5)
    /// The last finite zoom selected by an explicit control or a zoom gesture. Fit and Fill do not
    /// clear this value so the canvas can return to the user's previous detail level.
    private(set) var rememberedZoom: CGFloat?

    /// A predictable detail level for the first double-click, before the user has chosen a custom
    /// zoom. This is presentation state only and is intentionally independent of edit history.
    static let doubleClickFallbackZoom: CGFloat = 2

    init(rememberedZoom: CGFloat? = nil) {
        self.rememberedZoom = rememberedZoom.map(Self.clampZoom)
    }

    var zoomPercent: Int { Int((zoom * 100).rounded()) }

    mutating func fit() {
        mode = .fit
        zoom = 1
        focalPoint = Self.center
    }

    mutating func fill() {
        mode = .fill
        zoom = 1
        focalPoint = Self.center
    }

    mutating func reset() { fit() }

    mutating func resetForSource() {
        self = CanvasNavigation()
    }

    mutating func toggleFitAndRememberedZoom() {
        guard mode == .fit else {
            fit()
            return
        }

        let target = Self.clampZoom(rememberedZoom ?? Self.doubleClickFallbackZoom)
        rememberedZoom = target
        mode = .custom
        zoom = target
        focalPoint = Self.center
    }

    mutating func setZoom(_ value: CGFloat) {
        mode = .custom
        zoom = Self.clampZoom(value)
        if value.isFinite {
            rememberedZoom = zoom
        }
    }

    mutating func multiplyZoom(by factor: CGFloat) {
        guard factor.isFinite, factor > 0 else { return }
        setZoom(zoom * factor)
    }

    /// Pan in the coordinate space of the visible SwiftUI canvas. The focal point representation
    /// makes the result independent of backing scale and keeps it stable through layout changes.
    mutating func pan(by delta: CGSize, imageExtent: CGRect, viewportSize: CGSize) {
        guard delta.width.isFinite, delta.height.isFinite else { return }
        let transform = Self.transform(
            imageExtent: imageExtent, viewportSize: viewportSize,
            mode: mode, zoom: zoom, focalPoint: focalPoint
        )
        focalPoint = Self.focalPoint(
            afterMovingOrigin: CGSize(width: transform.origin.x + delta.width,
                                      height: transform.origin.y + delta.height),
            imageExtent: imageExtent, viewportSize: viewportSize,
            scale: transform.scale
        )
    }

    /// The image placement used by both the raster fallback and the Metal presentation surface.
    func transform(imageExtent: CGRect, viewportSize: CGSize) -> CanvasTransform {
        Self.transform(
            imageExtent: imageExtent, viewportSize: viewportSize,
            mode: mode, zoom: zoom, focalPoint: focalPoint
        )
    }

    /// How much more source resolution is useful than a fit render. This feeds preview requests;
    /// the render pipeline still refuses to upscale beyond the native image extent.
    func renderResolutionMultiplier(imageExtent: CGSize, viewportSize: CGSize) -> CGFloat {
        guard Self.isValidSize(imageExtent), Self.isValidSize(viewportSize) else { return 1 }
        let fit = min(viewportSize.width / imageExtent.width,
                      viewportSize.height / imageExtent.height)
        guard fit.isFinite, fit > 0 else { return 1 }
        return max(1, min(Self.maximumZoom, transform(
            imageExtent: CGRect(origin: .zero, size: imageExtent),
            viewportSize: viewportSize
        ).scale / fit))
    }

    static let center = CGPoint(x: 0.5, y: 0.5)

    static func clampZoom(_ value: CGFloat) -> CGFloat {
        guard value.isFinite else { return 1 }
        return min(max(value, minimumZoom), maximumZoom)
    }

    private static func transform(
        imageExtent: CGRect, viewportSize: CGSize, mode: Mode, zoom: CGFloat,
        focalPoint: CGPoint
    ) -> CanvasTransform {
        guard isValidSize(imageExtent.size), isValidSize(viewportSize) else {
            return CanvasTransform(scale: 1, origin: .zero, imageSize: .zero)
        }

        let fitScale = min(viewportSize.width / imageExtent.width,
                           viewportSize.height / imageExtent.height)
        let fillScale = max(viewportSize.width / imageExtent.width,
                            viewportSize.height / imageExtent.height)
        let baseScale = mode == .fill ? fillScale : fitScale
        let scale = baseScale * clampZoom(zoom)
        let imageSize = CGSize(width: imageExtent.width * scale,
                               height: imageExtent.height * scale)
        let focal = CGPoint(x: min(max(focalPoint.x, 0), 1),
                            y: min(max(focalPoint.y, 0), 1))
        let centeredOrigin = CGPoint(
            x: viewportSize.width / 2 - focal.x * imageSize.width,
            y: viewportSize.height / 2 - focal.y * imageSize.height
        )
        let origin = CGPoint(
            x: constrainedOrigin(centeredOrigin.x, content: imageSize.width,
                                  viewport: viewportSize.width),
            y: constrainedOrigin(centeredOrigin.y, content: imageSize.height,
                                  viewport: viewportSize.height)
        )
        return CanvasTransform(scale: scale, origin: origin, imageSize: imageSize)
    }

    private static func focalPoint(
        afterMovingOrigin origin: CGSize, imageExtent: CGRect, viewportSize: CGSize, scale: CGFloat
    ) -> CGPoint {
        guard isValidSize(imageExtent.size), isValidSize(viewportSize), scale.isFinite, scale > 0
        else { return center }
        let imageSize = CGSize(width: imageExtent.width * scale, height: imageExtent.height * scale)
        let constrainedX = constrainedOrigin(origin.width, content: imageSize.width,
                                              viewport: viewportSize.width)
        let constrainedY = constrainedOrigin(origin.height, content: imageSize.height,
                                              viewport: viewportSize.height)
        return CGPoint(
            x: min(max((viewportSize.width / 2 - constrainedX) / imageSize.width, 0), 1),
            y: min(max((viewportSize.height / 2 - constrainedY) / imageSize.height, 0), 1)
        )
    }

    private static func constrainedOrigin(_ origin: CGFloat, content: CGFloat, viewport: CGFloat) -> CGFloat {
        guard content.isFinite, content > 0, viewport.isFinite, viewport > 0 else { return 0 }
        guard content > viewport else { return (viewport - content) / 2 }
        return min(max(origin, viewport - content), 0)
    }

    private static func isValidSize(_ size: CGSize) -> Bool {
        size.width.isFinite && size.height.isFinite && size.width > 0 && size.height > 0
    }
}

struct CanvasTransform: Equatable, Sendable {
    let scale: CGFloat
    /// Origin of the displayed image in pixel space, y-down (pixel y=0 is the top of the
    /// view), matching `DragGesture.translation` and the vertex shader's `pixelPosition`
    /// convention in PreviewSurface.metal — not Core Image's bottom-left convention.
    let origin: CGPoint
    let imageSize: CGSize

    func affineTransform(for imageExtent: CGRect) -> CGAffineTransform {
        CGAffineTransform(
            a: scale, b: 0, c: 0, d: scale,
            tx: origin.x - imageExtent.minX * scale,
            ty: origin.y - imageExtent.minY * scale
        )
    }
}

/// The presentation-only mapping used by mask geometry prototypes and, eventually, persisted
/// mask components. Mask points are normalized in the oriented source image with an upper-left
/// origin. CropAdjustments remains Core Image's bottom-left value, so the conversion is explicit
/// at this boundary rather than leaking a second convention into mask state.
struct CanvasMaskTransform: Equatable, Sendable {
    let sourceSize: CGSize
    let cropRect: CGRect
    let viewportSize: CGSize
    let backingScale: CGFloat
    let displaySize: CGSize
    let canvasTransform: CanvasTransform

    init(
        sourceSize: CGSize,
        crop: CropAdjustments = .neutral,
        navigation: CanvasNavigation = CanvasNavigation(),
        viewportSize: CGSize,
        backingScale: CGFloat = 1
    ) {
        self.sourceSize = sourceSize
        self.viewportSize = viewportSize
        self.backingScale = backingScale.isFinite && backingScale > 0 ? backingScale : 1
        let normalizedCrop = crop.normalizedRect ?? CropAdjustments.unitRect
        // CropAdjustments is bottom-left based; mask geometry is upper-left based.
        self.cropRect = CGRect(
            x: normalizedCrop.minX,
            y: 1 - normalizedCrop.maxY,
            width: normalizedCrop.width,
            height: normalizedCrop.height
        )
        self.displaySize = CGSize(
            width: sourceSize.width * self.cropRect.width,
            height: sourceSize.height * self.cropRect.height
        )
        let backingViewport = CGSize(
            width: viewportSize.width * self.backingScale,
            height: viewportSize.height * self.backingScale
        )
        self.canvasTransform = navigation.transform(
            imageExtent: CGRect(origin: .zero, size: self.displaySize),
            viewportSize: backingViewport
        )
    }

    /// Convert an oriented-source normalized point to a SwiftUI viewport point. Points outside
    /// the crop are retained so recropping can reveal them later; callers may clip for drawing.
    func viewportPoint(forSourceNormalized point: CGPoint) -> CGPoint? {
        guard isValid, canvasTransform.scale.isFinite, canvasTransform.scale > 0 else { return nil }
        let inCrop = CGPoint(
            x: (point.x - cropRect.minX) / cropRect.width * displaySize.width,
            y: (point.y - cropRect.minY) / cropRect.height * displaySize.height
        )
        let backingPoint = CGPoint(
            x: canvasTransform.origin.x + inCrop.x * canvasTransform.scale,
            y: canvasTransform.origin.y + inCrop.y * canvasTransform.scale
        )
        return CGPoint(x: backingPoint.x / backingScale, y: backingPoint.y / backingScale)
    }

    /// Convert a SwiftUI viewport point back into oriented-source normalized coordinates.
    func sourceNormalizedPoint(forViewport point: CGPoint) -> CGPoint? {
        guard isValid, canvasTransform.scale.isFinite, canvasTransform.scale > 0 else { return nil }
        let backingPoint = CGPoint(x: point.x * backingScale, y: point.y * backingScale)
        let inCrop = CGPoint(
            x: (backingPoint.x - canvasTransform.origin.x) / canvasTransform.scale,
            y: (backingPoint.y - canvasTransform.origin.y) / canvasTransform.scale
        )
        return CGPoint(
            x: cropRect.minX + inCrop.x / displaySize.width * cropRect.width,
            y: cropRect.minY + inCrop.y / displaySize.height * cropRect.height
        )
    }

    /// Convert a viewport translation directly into oriented-source normalized coordinates.
    ///
    /// Gesture code must use a delta for translation handles. Converting two absolute points and
    /// subtracting them is subtly unsafe at crop/pan boundaries because each point can be clamped
    /// independently before it reaches the mask model. Keeping the scale conversion here also
    /// makes the Retina backing conversion explicit: the caller supplies SwiftUI points, while the
    /// canvas transform operates in drawable pixels.
    func sourceNormalizedDelta(forViewportDelta delta: CGSize) -> CGPoint? {
        guard isValid, canvasTransform.scale.isFinite, canvasTransform.scale > 0,
              delta.width.isFinite, delta.height.isFinite else { return nil }
        return CGPoint(
            x: delta.width * backingScale / canvasTransform.scale / sourceSize.width,
            y: delta.height * backingScale / canvasTransform.scale / sourceSize.height
        )
    }

    func viewportRect(forSourceNormalized rect: CGRect) -> CGRect? {
        guard let topLeft = viewportPoint(forSourceNormalized: rect.origin),
              let bottomRight = viewportPoint(forSourceNormalized: CGPoint(x: rect.maxX, y: rect.maxY))
        else { return nil }
        return CGRect(
            x: min(topLeft.x, bottomRight.x), y: min(topLeft.y, bottomRight.y),
            width: abs(bottomRight.x - topLeft.x), height: abs(bottomRight.y - topLeft.y)
        )
    }

    private var isValid: Bool {
        sourceSize.width.isFinite && sourceSize.height.isFinite
            && sourceSize.width > 0 && sourceSize.height > 0
            && viewportSize.width.isFinite && viewportSize.height.isFinite
            && viewportSize.width > 0 && viewportSize.height > 0
            && cropRect.width > 0 && cropRect.height > 0
            && displaySize.width.isFinite && displaySize.height.isFinite
            && displaySize.width > 0 && displaySize.height > 0
    }
}

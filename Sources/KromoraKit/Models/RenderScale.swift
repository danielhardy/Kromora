import Foundation
import CoreGraphics

/// The one thing that differs between a preview and an export.
///
/// Preview/export parity is structural in Phase 2 rather than a pair of code paths that merely agree:
/// both call the same `buildImage`, and this value is the only argument that changes. See
/// `docs/ENGINEERING_GUIDE.md`
///
/// The scale is applied **early** — `CIRAWFilter.scaleFactor` before `outputImage` for RAW, an ImageIO
/// thumbnail decode for standard images — so adjustment and LUT nodes operate on a preview-sized
/// image rather than the full extent. That is what makes every `AdjustmentNode`'s
/// resolution-independence a hard requirement rather than a nicety (§5).
enum RenderScale: Sendable, Equatable {
    /// Whole-frame budget for a fit view, where the preview is being downscaled to the canvas anyway.
    private static let interactivePixelsPerFrameBudget = 1_500_000.0
    /// Budget for the visible region of a zoomed view. A retina viewport is several megapixels, so
    /// the fit-view budget would upscale the ROI texture ~2x and read as blur while a slider drags.
    private static let interactiveVisiblePixelsBudget = 4_000_000.0
    /// ROI scaling can spend more decode work on the visible region, but rapid edits still need
    /// a source-wide ceiling so a tiny ROI cannot turn an interactive render into a large decode.
    /// The ceiling is high enough that a ~45 MP body stays near 1:1 at deep zoom; the decoded
    /// source is cached across a drag, so it is paid once per gesture for non-RAW-develop controls.
    private static let interactiveAbsolutePixelCeiling = 36_000_000.0

    /// Fit within `maxSize`, never upscaling.
    case preview(maxSize: CGSize)
    /// Interaction policy. The input is the canvas backing-pixel size, not a fixed export box.
    /// Interactive rendering intentionally uses a bounded pixel budget so a large RAW cannot
    /// monopolize the GPU past the next display tick.
    /// `budgetAreaFraction` is the fraction of the source covered by the requested visible ROI.
    case interactive(
        maxSize: CGSize,
        frameBudgetMilliseconds: Double = 16.7,
        budgetAreaFraction: CGFloat = 1
    )
    /// Native resolution.
    case full

    var isFull: Bool {
        if case .full = self { return true }
        return false
    }

    /// The maximum output box represented by this legacy scale, when one exists.
    var targetSize: CGSize? {
        switch self {
        case .preview(let maxSize): return maxSize
        case .interactive(let maxSize, let budget, let budgetAreaFraction):
            let safeBudget = budget.isFinite && budget > 0 ? budget : 16.7
            // Spend the pixel budget on the visible ROI rather than the complete source, while
            // retaining a source-wide ceiling for predictable interactive decode cost.
            let safeAreaFraction = budgetAreaFraction.isFinite && budgetAreaFraction > 0
                ? min(budgetAreaFraction, 1) : 1
            let frameBudgetScale = safeBudget / 16.7
            let visibleBudget = safeAreaFraction < 1
                ? Self.interactiveVisiblePixelsBudget : Self.interactivePixelsPerFrameBudget
            let roiBudgetPixels = visibleBudget * frameBudgetScale / safeAreaFraction
            let absoluteBudgetPixels = Self.interactiveAbsolutePixelCeiling * frameBudgetScale
            let budgetPixels = min(roiBudgetPixels, absoluteBudgetPixels)
            guard maxSize.width > 0, maxSize.height > 0,
                  maxSize.width.isFinite, maxSize.height.isFinite else { return maxSize }
            let pixels = maxSize.width * maxSize.height
            guard pixels > budgetPixels else { return maxSize }
            let factor = sqrt(budgetPixels / pixels)
            return CGSize(width: maxSize.width * factor, height: maxSize.height * factor)
        case .full: return nil
        }
    }

    /// The factor to render `nativeExtent` at, in 0…1.
    ///
    /// Always ≤ 1: a preview box larger than the image renders at 1.0 rather than magnifying it.
    /// Degenerate inputs (a zero or non-finite extent, an empty preview box) fall back to 1.0, which
    /// leaves the source alone and lets the caller's own extent check reject it — rather than
    /// producing a zero or NaN scale that would trap later on when it reaches `Int(width)`.
    func factor(for nativeExtent: CGSize) -> CGFloat {
        switch self {
        case .full:
            return 1.0
        case .preview(let maxSize):
            guard nativeExtent.width > 0, nativeExtent.height > 0,
                  nativeExtent.width.isFinite, nativeExtent.height.isFinite,
                  maxSize.width > 0, maxSize.height > 0
            else { return 1.0 }
            return min(maxSize.width / nativeExtent.width, maxSize.height / nativeExtent.height, 1.0)
        case .interactive:
            // `targetSize` applies the interactive pixel budget. Using the unbounded drawable
            // size here made the cap advisory only: RAW development still ran at the full backing
            // resolution, so a rapid curve drag could fill the presentation queue.
            guard let maxSize = targetSize,
                  nativeExtent.width > 0, nativeExtent.height > 0,
                  nativeExtent.width.isFinite, nativeExtent.height.isFinite,
                  maxSize.width > 0, maxSize.height > 0
            else { return 1.0 }
            return min(maxSize.width / nativeExtent.width, maxSize.height / nativeExtent.height, 1.0)
        }
    }
}

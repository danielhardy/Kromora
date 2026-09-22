import CoreGraphics
import Foundation

/// Shared geometry and document-view transforms used by runtime Auto measurement.
///
/// Pixel rendering, comparison, reporting, and artifact output belong to the test-only
/// evaluation harness. Keeping this small value seam in the library avoids duplicating the
/// analysis view used by production measurement without shipping file-writing diagnostics.
enum AutoCandidateEvaluation {
    /// Long edge used for evaluation renders. Matches the analysis default (768px) so later
    /// measurement and policy tickets evaluate what analysis actually saw.
    static let evaluationLongEdge = 768

    /// Target box that fits `nativeExtent` inside the evaluation long edge without upscaling.
    static func targetSize(for nativeExtent: CGSize, longEdge: Int = evaluationLongEdge) -> CGSize {
        guard nativeExtent.width > 0, nativeExtent.height > 0,
              nativeExtent.width.isFinite, nativeExtent.height.isFinite,
              longEdge > 0
        else { return nativeExtent }
        let longest = max(nativeExtent.width, nativeExtent.height)
        let scale = min(1, CGFloat(longEdge) / longest)
        return CGSize(width: nativeExtent.width * scale, height: nativeExtent.height * scale)
    }

    /// The Auto analysis view of a complete edit: LUT, color grading, grain, and decorative
    /// vignette are excluded so correction proposals are fit against photographic tone/color
    /// rather than a creative finish. Crop, rotation, RAW develop, light, vibrance/saturation,
    /// mixer, detail effects (texture/clarity/dehaze), curves, ordered adjustments, and local
    /// masks are retained so geometry and photographic intent survive the view transform.
    static func analysisDocument(from complete: EditDocument) -> EditDocument {
        var view = complete
        view.lut = .none
        view.color.grading = .neutral
        view.effects.grain = .neutral
        view.effects.vignette = .neutral
        return view
    }

}

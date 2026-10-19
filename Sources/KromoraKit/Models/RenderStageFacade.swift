import CoreImage
import CoreGraphics

/// The stage-composition seam between the request façade and the pure Core Image pipeline.
///
/// `RenderPipeline` owns the individual transformations. This façade owns only their final
/// composition contract, so `RenderEngine` does not need to know which stages follow the graded prefix or
/// how deterministic grain is seeded. The cache object remains actor-confined by the caller.
enum RenderStageFacade {
    /// Apply the post-prefix stages in the product's canonical order: crop, post-crop vignette,
    /// and deterministic grain. The Look is already inside the graded prefix (it is the base look
    /// the sliders adjust).
    static func buildFinalStages(
        graded image: CIImage,
        document: EditDocument,
        grainSeed: UInt32,
        applyCommittedCrop: Bool = true,
        finalFrameExtent: CGRect? = nil
    ) -> CIImage {
        RenderPipeline.buildImage(
            graded: image,
            document: document,
            grainSeed: grainSeed,
            applyCommittedCrop: applyCommittedCrop,
            finalFrameExtent: finalFrameExtent
        )
    }
}

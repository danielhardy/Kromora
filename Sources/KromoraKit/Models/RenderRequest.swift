import Foundation
import CoreGraphics

/// The work a renderer should perform.
///
/// This is deliberately made only from value types. It is safe to create on the main actor and
/// send to a renderer without bringing SwiftUI, AppKit, `CIImage`, or a file destination into the
/// rendering API. `document` is the one edit model for every quality tier.
/// The representation a render should return.
enum RenderOutput: Sendable, Equatable {
    /// Return a displayable lossless raster (PNG) in the requested working space.
    case raster
    /// Return bytes in the requested export format and encoder quality.
    case encoded(format: ExportFormat, quality: CGFloat)

    /// A descriptive alias for callers that think in terms of display images.
    static var image: Self { .raster }
}

/// Controls whether semantic local masks are part of this render yet. Procedural and brush
/// masks remain available in both modes; the deferred mode is only used for the fast first frame
/// of a masked preview while Vision resolves the semantic components.
enum MaskResolutionPolicy: Sendable, Equatable {
    case resolved
    case deferSemantic
}

struct RenderRequest: Sendable, Equatable {
    /// Kept nested as a discoverable spelling alongside the top-level type.
    typealias Output = RenderOutput

    let source: ImageSource
    /// Optional durable identity. When absent, the renderer derives the identity from the source;
    /// editor/export callers with a Photos-backed ID should provide it explicitly.
    let assetID: PhotoAssetID?
    let document: EditDocument
    let lut: CubeLUT?
    /// Maximum output dimensions for preview tiers. Export sizing is carried by exportOptions.
    let targetSize: CGSize?
    /// Native-space rectangle requested for a preview. The decoder still owns the full planned
    /// scaled source (so adjacent pans hit the developed-source cache), but expensive graph stages
    /// may operate only on this rectangle. `nil` preserves the uncropped/full-source path.
    let sourceROI: CGRect?
    /// Scaled crop-frame geometry for the presentation surface when `sourceROI` is smaller than
    /// the committed crop. This never changes export pixels.
    let presentationImageExtent: CGRect?
    let quality: RenderQuality
    let frameBudgetMilliseconds: Double
    let output: Output
    let space: WorkingSpace
    /// Projection of normalized mask geometry into this render. It is identity for ordinary image
    /// renders, but remains on the request so preview/export and derived-mask caches share one seam.
    let maskTransform: LocalMaskRenderTransform
    let maskResolution: MaskResolutionPolicy
    /// RenderEngine-local supersession token. UI publication staleness is checked independently by
    /// PreviewCoordinator/AppViewModel and is never encoded into a reusable mask payload.
    let requestRevision: UInt64
    /// Full export policy when this is an encoded request. Kept separate from `RenderOutput` so the
    /// legacy format/quality spelling remains source-compatible for existing renderer clients.
    let exportOptions: ExportOptions?

    init(
        source: ImageSource,
        assetID: PhotoAssetID? = nil,
        document: EditDocument,
        lut: CubeLUT? = nil,
        targetSize: CGSize? = nil,
        sourceROI: CGRect? = nil,
        presentationImageExtent: CGRect? = nil,
        quality: RenderQuality,
        frameBudgetMilliseconds: Double = 16.7,
        output: Output = .raster,
        space: WorkingSpace = .current,
        exportOptions: ExportOptions? = nil,
        maskTransform: LocalMaskRenderTransform = .identity,
        maskResolution: MaskResolutionPolicy = .resolved,
        requestRevision: UInt64 = 0
    ) {
        self.source = source
        self.assetID = assetID
        self.document = document
        self.lut = lut
        self.targetSize = targetSize
        self.sourceROI = sourceROI
        self.presentationImageExtent = presentationImageExtent
        self.quality = quality
        self.frameBudgetMilliseconds = frameBudgetMilliseconds
        self.output = output
        self.space = space
        self.exportOptions = exportOptions
        self.maskTransform = maskTransform
        self.maskResolution = maskResolution
        self.requestRevision = requestRevision
    }

    /// The scale policy used by the existing deterministic pipeline.
    ///
    /// Downsampled quality tiers intentionally share the same source/edit pipeline. Their quality
    /// identity remains visible in the request so a future scheduler or cache can distinguish them,
    /// while the current implementation uses the requested viewport as the only pixel policy.
    var renderScale: RenderScale {
        let nativeExtent = document.rotation.orientedExtent(source.nativeExtent)
        switch quality {
        case .thumbnail, .preview:
            return .preview(maxSize: targetSize ?? nativeExtent)
        case .interactive:
            return .interactive(
                maxSize: targetSize ?? nativeExtent,
                frameBudgetMilliseconds: frameBudgetMilliseconds
            )
        case .fullResolution:
            return .full
        case .export:
            guard let options = exportOptions, options.sizing.longEdge != nil else {
                return .full
            }
            // Keep both dimensions proportional to the one long-edge factor. Passing the rounded
            // output plan here lets an extreme aspect ratio's short axis become the tightest ratio
            // and changes the factor before the renderer reaches the encoder.
            return .preview(maxSize: options.sizing.unroundedOutputSize(for: nativeExtent))
        }
    }

    /// The durable pixel contract for a sized export. The renderer applies this after the shared
    /// graph has been evaluated because `RenderScale` intentionally describes a scale factor, not
    /// an independently rounded pixel box.
    var exportOutputSize: CGSize? {
        guard quality == .export, let options = exportOptions,
              options.sizing.longEdge != nil else { return nil }
        return options.outputSize(for: document.rotation.orientedExtent(source.nativeExtent))
    }
}

/// A bounded Look-browser request.
///
/// The browser normally changes only `candidateDocument.lut`. Keeping the base document beside
/// the candidate makes that contract explicit to the renderer: a LUT-only candidate may reuse the
/// developed/pre-LUT prefix, while a bundled preset that changes any other document field must
/// take the ordinary full-build path for that candidate.
struct LookPreviewRequest: Sendable, Equatable {
    let source: ImageSource
    let baseDocument: EditDocument
    let candidateDocument: EditDocument
    let look: CubeLUT
    let targetSize: CGSize
    let space: WorkingSpace

    init(
        source: ImageSource,
        document: EditDocument,
        look: CubeLUT,
        targetSize: CGSize,
        space: WorkingSpace = .current
    ) {
        var candidate = document
        candidate.lut = LUTSettings(lutID: look.lutID, intensity: 1)
        self.init(
            source: source, baseDocument: document, candidateDocument: candidate,
            look: look, targetSize: targetSize, space: space
        )
    }

    init(
        source: ImageSource,
        baseDocument: EditDocument,
        candidateDocument: EditDocument,
        look: CubeLUT,
        targetSize: CGSize,
        space: WorkingSpace = .current
    ) {
        self.source = source
        self.baseDocument = baseDocument
        self.candidateDocument = candidateDocument
        self.look = look
        self.targetSize = targetSize
        self.space = space
    }

    /// Conservative by design. The shared prefix boundary is below every document field except
    /// the LUT: `version`, `rawDevelop`, `light`, `color`, every `effects` field, `crop`, ordered
    /// `adjustments`, and `localAdjustments` all force the candidate's full build. This keeps
    /// bundled tone/preset changes pixel-correct even if a future preset adds a field whose stage
    /// ordering is not yet known to the browser.
    var isLUTOnlyChange: Bool {
        var base = baseDocument
        var candidate = candidateDocument
        base.lut = .none
        candidate.lut = .none
        return base == candidate
    }

    var renderRequest: RenderRequest {
        RenderRequest(
            source: source, document: candidateDocument, lut: look,
            targetSize: targetSize, quality: .thumbnail, output: .raster, space: space
        )
    }
}

/// The five work classes used by orchestration and caching.
///
/// Quality is intentionally independent from `RenderRequest.Output`: an interactive raster and an
/// export encoding are different output policies, while both still use the same `EditDocument` and
/// deterministic adjustment/LUT ordering.
enum RenderQuality: String, Codable, CaseIterable, Sendable, Equatable {
    case thumbnail
    case interactive
    case preview
    case fullResolution
    case export
}

/// A renderer's sendable response.
///
/// Raster results are PNG bytes, not `CGImage`: Core Graphics image objects are not Sendable and must
/// stay inside the renderer actor. The extent is the integral pixel extent actually encoded, and the
/// color space records the same `WorkingSpace` used for LUT interpolation and output encoding.
struct RenderResult: Sendable, Equatable {
    let data: Data
    let extent: CGSize
    let colorSpace: WorkingSpace
    let quality: RenderQuality
    let output: RenderOutput

    var imageData: Data { data }

    init(
        data: Data,
        extent: CGSize,
        colorSpace: WorkingSpace,
        quality: RenderQuality,
        output: RenderOutput
    ) {
        self.data = data
        self.extent = extent
        self.colorSpace = colorSpace
        self.quality = quality
        self.output = output
    }
}

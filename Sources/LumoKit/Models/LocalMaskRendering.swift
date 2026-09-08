import CoreGraphics
import Foundation

/// The normalized transform used when a persisted mask definition is projected into a render.
/// Mask definitions remain in oriented source coordinates; this value belongs to the render request
/// and is therefore also part of derived-mask cache identity.
struct LocalMaskRenderTransform: Codable, Hashable, Sendable, Equatable {
    var scaleX: Double
    var scaleY: Double
    var translationX: Double
    var translationY: Double
    var rotation: Double

    static let identity = LocalMaskRenderTransform()

    init(
        scaleX: Double = 1, scaleY: Double = 1,
        translationX: Double = 0, translationY: Double = 0,
        rotation: Double = 0
    ) {
        self.scaleX = Self.finite(scaleX, fallback: 1)
        self.scaleY = Self.finite(scaleY, fallback: 1)
        self.translationX = Self.finite(translationX, fallback: 0)
        self.translationY = Self.finite(translationY, fallback: 0)
        self.rotation = Self.finite(rotation, fallback: 0)
    }

    private static func finite(_ value: Double, fallback: Double) -> Double {
        value.isFinite ? value : fallback
    }
}

/// The value-only request crossing from `RenderEngine` to a mask resolver. No Core Image or Metal
/// object is allowed here. A resolver may use a semantic cache, a Vision provider, or simply return
/// the analytic/brush descriptor already present in the request. Request revisions stay in the
/// engine's supersession checks rather than crossing into reusable resolver payloads.
struct LocalMaskResolveRequest: Sendable, Equatable {
    let source: ImageSource
    let assetID: PhotoAssetID
    let component: MaskComponent
    /// The working extent for this component. Preview semantic rasters may be smaller than the
    /// display extent; `LocalMaskRenderer` upscales those values when building the CI graph.
    let targetSize: PixelDimensions
    let quality: RenderQuality
    let transform: LocalMaskRenderTransform

    init(
        source: ImageSource,
        assetID: PhotoAssetID? = nil,
        component: MaskComponent,
        targetSize: PixelDimensions,
        quality: RenderQuality,
        transform: LocalMaskRenderTransform = .identity
    ) {
        self.source = source
        self.assetID = assetID ?? PhotoAnalysisCoordinator.assetID(for: source)
        self.component = component
        self.targetSize = targetSize
        self.quality = quality
        self.transform = transform
    }
}

/// Preview semantic masks carry low-frequency information, so resolving them at the full display
/// extent wastes memory and CPU when the canvas is zoomed to a large source. The raster remains
/// smooth when Core Image samples it at the display extent. Full-resolution/export requests do
/// not use this policy.
enum SemanticMaskPreviewResolution {
    static let maximumPixelCount = 4_000_000
    static let maximumLongEdge = 2_560
    static let defaultCap = PixelDimensions(width: maximumLongEdge, height: maximumLongEdge)

    static func targetSize(for size: PixelDimensions, cap: PixelDimensions?) -> PixelDimensions {
        guard let cap,
              size.width > 0, size.height > 0,
              cap.width > 0, cap.height > 0 else { return size }

        let width = Double(size.width)
        let height = Double(size.height)
        let pixelScale = sqrt(Double(maximumPixelCount) / (width * height))
        let longEdgeScale = Double(maximumLongEdge) / max(width, height)
        let scale = min(1, pixelScale, longEdgeScale,
                        Double(cap.width) / width, Double(cap.height) / height)
        guard scale < 1 else { return size }

        var resultWidth = max(1, Int((width * scale).rounded(.down)))
        var resultHeight = max(1, Int((height * scale).rounded(.down)))
        while resultWidth * resultHeight > maximumPixelCount {
            if resultWidth >= resultHeight {
                resultWidth -= 1
            } else {
                resultHeight -= 1
            }
        }
        return PixelDimensions(width: resultWidth, height: resultHeight)
    }
}

/// Presentation-only styling for the mask inspection surface. These values never enter an
/// `EditDocument` or a normal `RenderRequest`; they only describe how resolved alpha is displayed.
struct MaskOverlayStyle: Sendable, Equatable {
    enum Inspection: String, Sendable, Equatable {
        case colorWash
        case grayscale
    }

    let inspection: Inspection
    let red: Double
    let green: Double
    let blue: Double

    init(inspection: Inspection = .colorWash, red: Double, green: Double, blue: Double) {
        self.inspection = inspection
        self.red = Self.clamp(red)
        self.green = Self.clamp(green)
        self.blue = Self.clamp(blue)
    }

    private static func clamp(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }
}

/// Presentation opacity policy for the inspection surface. Coverage is intentionally the only
/// value controlled by the overlay opacity slider; guides are composited separately by the view
/// and remain fully opaque so they do not disappear into the photo while coverage is softened.
struct MaskOverlayPresentation: Sendable, Equatable {
    let coverageOpacity: Double
    let toolingOpacity: Double

    init(coverageOpacity: Double) {
        self.coverageOpacity = min(max(coverageOpacity.isFinite ? coverageOpacity : 0, 0), 1)
        toolingOpacity = 1
    }
}

/// Value-only request for the presentation mask inspection image. It deliberately carries layers,
/// selection, and solo state instead of a document mutation: rendering this image must never alter
/// edit history, exported pixels, or the normal preview request.
struct MaskOverlayRequest: Sendable, Equatable {
    let source: ImageSource
    let assetID: PhotoAssetID?
    let layers: [LocalAdjustmentLayer]
    let selectedLayerID: UUID?
    let selectedComponentID: UUID?
    let soloLayerID: UUID?
    let soloComponentID: UUID?
    let targetSize: PixelDimensions
    let quality: RenderQuality
    let transform: LocalMaskRenderTransform
    /// RenderEngine-local supersession token; it is not part of the resolved payload identity.
    let requestRevision: UInt64
    let style: MaskOverlayStyle

    init(
        source: ImageSource,
        assetID: PhotoAssetID? = nil,
        layers: [LocalAdjustmentLayer],
        selectedLayerID: UUID?,
        soloLayerID: UUID?,
        targetSize: PixelDimensions,
        quality: RenderQuality = .preview,
        transform: LocalMaskRenderTransform = .identity,
        style: MaskOverlayStyle,
        requestRevision: UInt64 = 0,
        selectedComponentID: UUID? = nil,
        soloComponentID: UUID? = nil
    ) {
        self.source = source
        self.assetID = assetID
        self.layers = layers
        self.selectedLayerID = selectedLayerID
        self.selectedComponentID = selectedComponentID
        self.soloLayerID = soloLayerID
        self.soloComponentID = soloComponentID
        self.targetSize = targetSize
        self.quality = quality
        self.transform = transform
        self.requestRevision = requestRevision
        self.style = style
    }
}

/// A resolved mask is still a sendable value. Raster payloads use upper-left row order, matching
/// the persisted brush/analytic coordinate contract. Procedural payloads are evaluated by the
/// renderer at the requested extent, so they do not need a semantic cache or a pixel buffer.
/// Staleness is checked by `RenderEngine` before this value is cached or rendered, and by
/// `AppViewModel`/`PreviewCoordinator` before a completed frame is published.
struct LocalMaskPayload: Sendable, Equatable {
    enum Descriptor: Sendable, Equatable {
        case raster(NormalizedMask)
        case linear(LinearGradientDefinition)
        case radial(RadialGradientDefinition)
        case brush(BrushMaskDefinition)
    }

    let assetID: PhotoAssetID?
    let sourceFingerprint: String
    let definitionHash: String
    /// The descriptor's working extent. A preview semantic raster may be smaller than the render
    /// extent and is upscaled only at the Core Image boundary.
    let targetSize: PixelDimensions
    let quality: RenderQuality
    let providerVersion: String
    let descriptor: Descriptor

    init(
        sourceFingerprint: String,
        definitionHash: String = "",
        targetSize: PixelDimensions,
        quality: RenderQuality,
        assetID: PhotoAssetID? = nil,
        providerVersion: String = "local-1",
        descriptor: Descriptor
    ) {
        self.assetID = assetID
        self.sourceFingerprint = sourceFingerprint
        self.definitionHash = definitionHash
        self.targetSize = targetSize
        self.quality = quality
        self.providerVersion = providerVersion
        self.descriptor = descriptor
    }

    var estimatedCostBytes: Int {
        switch descriptor {
        case .raster(let mask):
            let cost = mask.values.count.multipliedReportingOverflow(by: MemoryLayout<Float>.size)
            return cost.overflow ? Int.max : cost.partialValue
        case .linear, .radial, .brush:
            return 1024
        }
    }
}

enum LocalMaskResolutionError: Error, Sendable, Equatable, CustomStringConvertible {
    case semanticMaskUnavailable(target: SemanticTarget, quality: MaskQuality)
    case incompatibleDefinition(target: SemanticTarget, version: Int)
    case providerFailure(target: SemanticTarget, reason: String)
    case sourceMismatch
    case invalidPayload
    case cancelled

    var description: String {
        switch self {
        case .semanticMaskUnavailable(let target, let quality):
            return "The \(target.rawValue) mask is not available at \(quality.rawValue) quality for this source. Resolve it or choose an explicit lower-quality export."
        case .incompatibleDefinition(let target, let version):
            return "The saved \(target.rawValue) mask was created by an incompatible generation version (\(version)). Retry regeneration after updating the definition."
        case .providerFailure(let target, let reason):
            return "The \(target.rawValue) mask could not be regenerated: \(reason)"
        case .sourceMismatch:
            return "The resolved mask belongs to a different source and was rejected."
        case .invalidPayload:
            return "The mask resolver returned an invalid payload for the requested render."
        case .cancelled:
            return "Mask resolution was cancelled."
        }
    }
}

/// Boundary for semantic-mask providers and procedural mask renderers. Implementations are actors
/// when they own mutable caches; the protocol itself remains safe to call from RenderEngine.
protocol LocalMaskResolving: Sendable {
    func resolve(_ request: LocalMaskResolveRequest) async throws -> LocalMaskPayload
}

/// The built-in resolver handles masks that are already portable recipes. Semantic masks are
/// intentionally not guessed: a production provider must validate the active source fingerprint
/// before returning pixels.
struct DefaultLocalMaskResolver: LocalMaskResolving {
    func resolve(_ request: LocalMaskResolveRequest) async throws -> LocalMaskPayload {
        try Task.checkCancellation()
        let sourceFingerprint = request.source.cacheFingerprint
        let definitionHash = RenderCacheHash.digest(request.component.source)
        let descriptor: LocalMaskPayload.Descriptor
        switch request.component.source {
        case .semantic(let definition):
            throw LocalMaskResolutionError.semanticMaskUnavailable(
                target: definition.target, quality: request.quality.maskQuality
            )
        case .brush(let definition):
            descriptor = .brush(definition)
        case .linear(let definition):
            descriptor = .linear(definition)
        case .radial(let definition):
            descriptor = .radial(definition)
        }
        return LocalMaskPayload(
            sourceFingerprint: sourceFingerprint,
            definitionHash: definitionHash,
            targetSize: request.targetSize,
            quality: request.quality,
            assetID: request.assetID,
            descriptor: descriptor
        )
    }
}

/// Semantic providers can use this small adapter when they have already loaded a validated raster
/// from `MaskStore`. Keeping the source and definition checks in the payload means RenderEngine
/// still rejects stale pixels even if an adapter is accidentally reused across image switches.
struct ResolvedSemanticMask: LocalMaskResolving {
    let mask: NormalizedMask
    let assetID: PhotoAssetID
    let sourceFingerprint: String
    let definitionHash: String
    let quality: RenderQuality

    func resolve(_ request: LocalMaskResolveRequest) async throws -> LocalMaskPayload {
        try Task.checkCancellation()
        guard sourceFingerprint == request.source.cacheFingerprint,
              assetID == request.assetID,
              definitionHash == RenderCacheHash.digest(request.component.source),
              mask.size == request.targetSize else {
            throw LocalMaskResolutionError.sourceMismatch
        }
        return LocalMaskPayload(
            sourceFingerprint: sourceFingerprint,
            definitionHash: definitionHash,
            targetSize: mask.size,
            quality: quality,
            assetID: assetID,
            descriptor: .raster(mask)
        )
    }
}

/// Resolves durable semantic recipes through the existing coordinator/provider/store path. The
/// resolver deliberately returns values only; Core Image construction remains in RenderEngine.
actor CoordinatorLocalMaskResolver: LocalMaskResolving {
    private let coordinator: PhotoAnalysisCoordinator

    init(coordinator: PhotoAnalysisCoordinator) {
        self.coordinator = coordinator
    }

    func resolve(_ request: LocalMaskResolveRequest) async throws -> LocalMaskPayload {
        try Task.checkCancellation()
        guard case .semantic(let definition) = request.component.source else {
            return try await DefaultLocalMaskResolver().resolve(request)
        }
        guard definition.generationVersion <= SemanticMaskDefinition.currentGenerationVersion else {
            throw LocalMaskResolutionError.incompatibleDefinition(
                target: definition.target, version: definition.generationVersion
            )
        }

        let kind = definition.target.semanticMaskKind
        let requestedQuality = request.quality.maskQuality
        let mask: RegionMask
        do {
            mask = try await resolveMask(
                assetID: request.assetID, source: request.source, kind: kind,
                quality: requestedQuality, targetSize: request.targetSize
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as LocalMaskResolutionError {
            throw error
        } catch {
            throw LocalMaskResolutionError.providerFailure(
                target: definition.target, reason: String(describing: error)
            )
        }

        guard mask.reference.cacheKey.assetID == request.assetID,
              mask.reference.cacheKey.sourceFingerprint.cacheKey
                == PhotoAnalysisCoordinator.sourceFingerprint(for: request.source).cacheKey,
              mask.reference.cacheKey.kind == kind,
              mask.reference.cacheKey.quality == mask.quality,
              !mask.reference.cacheKey.providerVersion.isEmpty,
              mask.quality == requestedQuality || requestedQuality == .render else {
            throw LocalMaskResolutionError.sourceMismatch
        }
        guard let pixels = await coordinator.pixels(for: mask.reference) else {
            throw LocalMaskResolutionError.semanticMaskUnavailable(
                target: definition.target, quality: requestedQuality
            )
        }
        let resized = try MaskOperations.resized(pixels, to: request.targetSize)
        let adjusted = try Self.apply(definition, to: resized)
        return LocalMaskPayload(
            sourceFingerprint: request.source.cacheFingerprint,
            definitionHash: RenderCacheHash.digest(request.component.source),
            targetSize: request.targetSize,
            quality: request.quality,
            assetID: request.assetID,
            providerVersion: mask.reference.cacheKey.providerVersion,
            descriptor: .raster(adjusted)
        )
    }

    private func resolveMask(
        assetID: PhotoAssetID, source: ImageSource, kind: SemanticMaskKind,
        quality: MaskQuality, targetSize: PixelDimensions
    ) async throws -> RegionMask {
        do {
            let mask = try await coordinator.mask(
                assetID: assetID, source: source, kind: kind, quality: quality
            )
            if quality == .render, mask.quality != .render {
                return try await coordinator.refineMask(
                    mask, source: source, targetDimensions: targetSize
                )
            }
            return mask
        } catch {
            guard quality == .render else { throw error }
            // A provider may expose only preview quality. Upgrade that validated seed through the
            // shared refinement service rather than silently exporting the preview pixels.
            let preview = try await coordinator.mask(
                assetID: assetID, source: source, kind: kind, quality: .preview
            )
            return try await coordinator.refineMask(
                preview, source: source, targetDimensions: targetSize
            )
        }
    }

    private static func apply(_ definition: SemanticMaskDefinition, to mask: NormalizedMask) throws -> NormalizedMask {
        // An untouched definition must not pay for a full-resample pass: at render quality this
        // maps tens of millions of values for no change.
        if definition.edgeFeather <= 0 && definition.edgeShift == 0 && definition.density == 1 {
            return mask
        }
        var result = mask
        if definition.edgeFeather > 0 {
            let radius = max(1, Int((definition.edgeFeather * Double(min(mask.size.width, mask.size.height)) * 0.05).rounded()))
            result = try MaskOperations.feather(result, radius: radius)
        }
        let values = result.values.map { value in
            let shifted = min(max(Double(value) + definition.edgeShift, 0), 1)
            return Float(shifted * definition.density)
        }
        return try NormalizedMask(size: result.size, values: values)
    }
}

extension SemanticMaskDefinition {
    static let currentGenerationVersion = 1
}

extension SemanticTarget {
    var semanticMaskKind: SemanticMaskKind {
        switch self {
        case .foreground: return .foreground
        case .background: return .background
        case .subject: return .subject
        case .person: return .person
        case .face: return .face
        }
    }
}

extension RenderQuality {
    var maskQuality: MaskQuality {
        switch self {
        case .thumbnail, .interactive, .preview: return .preview
        case .fullResolution, .export: return .render
        }
    }
}

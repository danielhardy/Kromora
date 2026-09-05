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
/// the analytic/brush descriptor already present in the request.
struct LocalMaskResolveRequest: Sendable, Equatable {
    let source: ImageSource
    let component: MaskComponent
    let targetSize: PixelDimensions
    let quality: RenderQuality
    let transform: LocalMaskRenderTransform

    init(
        source: ImageSource,
        component: MaskComponent,
        targetSize: PixelDimensions,
        quality: RenderQuality,
        transform: LocalMaskRenderTransform = .identity
    ) {
        self.source = source
        self.component = component
        self.targetSize = targetSize
        self.quality = quality
        self.transform = transform
    }
}

/// A resolved mask is still a sendable value. Raster payloads use upper-left row order, matching
/// the persisted brush/analytic coordinate contract. Procedural payloads are evaluated by the
/// renderer at the requested extent, so they do not need a semantic cache or a pixel buffer.
struct LocalMaskPayload: Sendable, Equatable {
    enum Descriptor: Sendable, Equatable {
        case raster(NormalizedMask)
        case linear(LinearGradientDefinition)
        case radial(RadialGradientDefinition)
        case brush(BrushMaskDefinition)
    }

    let sourceFingerprint: String
    let definitionHash: String
    let targetSize: PixelDimensions
    let quality: RenderQuality
    let descriptor: Descriptor

    init(
        sourceFingerprint: String,
        definitionHash: String = "",
        targetSize: PixelDimensions,
        quality: RenderQuality,
        descriptor: Descriptor
    ) {
        self.sourceFingerprint = sourceFingerprint
        self.definitionHash = definitionHash
        self.targetSize = targetSize
        self.quality = quality
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
    case sourceMismatch
    case invalidPayload
    case cancelled

    var description: String {
        switch self {
        case .semanticMaskUnavailable(let target, let quality):
            return "The \(target.rawValue) mask is not available at \(quality.rawValue) quality for this source. Resolve it or choose an explicit lower-quality export."
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
            descriptor: descriptor
        )
    }
}

/// Semantic providers can use this small adapter when they have already loaded a validated raster
/// from `MaskStore`. Keeping the source and definition checks in the payload means RenderEngine
/// still rejects stale pixels even if an adapter is accidentally reused across image switches.
struct ResolvedSemanticMask: LocalMaskResolving {
    let mask: NormalizedMask
    let sourceFingerprint: String
    let definitionHash: String
    let quality: RenderQuality

    func resolve(_ request: LocalMaskResolveRequest) async throws -> LocalMaskPayload {
        try Task.checkCancellation()
        guard sourceFingerprint == request.source.cacheFingerprint,
              definitionHash == RenderCacheHash.digest(request.component.source),
              mask.size == request.targetSize else {
            throw LocalMaskResolutionError.sourceMismatch
        }
        return LocalMaskPayload(
            sourceFingerprint: sourceFingerprint,
            definitionHash: definitionHash,
            targetSize: mask.size,
            quality: quality,
            descriptor: .raster(mask)
        )
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

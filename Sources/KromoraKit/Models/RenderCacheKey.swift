import Foundation
import CoreGraphics
import CryptoKit

/// Portable identity for a source at the render boundary.
///
/// The wrapped value contains the opaque asset UUID plus immutable source content, decoder, and
/// geometry fields. It deliberately has no URL, inode, device, or timestamp component, so moving
/// a source does not partition the in-memory render caches.
struct RenderSourceFingerprint: Hashable, Sendable {
    let identity: PortablePhotoIdentity

    init(_ source: ImageSource) {
        self.identity = source.cacheIdentity
    }

    init(identity: PortablePhotoIdentity) {
        self.identity = identity
    }

    var value: String { identity.cacheKey }
}

/// The effective source dimensions and scale used by a render. `RenderScale` is intentionally a
/// small policy enum, not a cache key, because its requested box is not necessarily the pixel box
/// it produces (interactive rendering applies a frame-budget cap).
struct RenderScaleKey: Hashable, Sendable {
    let isFull: Bool
    let widthBits: UInt64
    let heightBits: UInt64
    let factorBits: UInt64

    init(_ scale: RenderScale, nativeExtent: CGSize? = nil) {
        guard let nativeExtent, nativeExtent.width > 0, nativeExtent.height > 0,
              nativeExtent.width.isFinite, nativeExtent.height.isFinite else {
            switch scale {
            case .full:
                isFull = true
                widthBits = 0
                heightBits = 0
                factorBits = Double(1).bitPattern
            case .preview(let size), .interactive(let size, _, _):
                isFull = false
                widthBits = Double(size.width).bitPattern
                heightBits = Double(size.height).bitPattern
                factorBits = Double(scale.factor(for: size)).bitPattern
            }
            return
        }

        switch scale {
        case .full:
            isFull = true
            widthBits = 0
            heightBits = 0
            factorBits = Double(1).bitPattern
        case .preview, .interactive:
            isFull = false
            let factor = scale.factor(for: nativeExtent)
            widthBits = Double(nativeExtent.width * factor).bitPattern
            heightBits = Double(nativeExtent.height * factor).bitPattern
            factorBits = Double(factor).bitPattern
        }
    }
}

/// Cache identity for the source stage. It excludes adjustments and LUTs because those are applied
/// after the developed source has been built. The working space is part of the key because the
/// engine's `CIContext` materializes (and a RAW develop may be tagged for) the space it renders in.
struct DevelopedSourceCacheKey: Hashable, Sendable {
    let source: RenderSourceFingerprint
    let developHash: String
    let scale: RenderScaleKey
    let space: WorkingSpace
    let pipelineVersion: Int
}

/// The materialized prefix can stop either before local adjustments or immediately after them.
/// Both include the Look (the base look at the head of the chain), so its identity and intensity
/// are part of `upstreamHash`; crop, vignette, and grain sit downstream and are not.
enum ProcessingPrefixStage: String, Hashable, Sendable {
    case graded
    case postLocal
}

/// The geometry applied to the developed source before the prefix is built. The prefix document
/// digest neutralizes `crop`, but the cached image is built from the transformed source, so a
/// flip, straighten, or perspective change must miss.
struct PrefixGeometryKey: Hashable, Sendable {
    let rotation: ImageRotation
    let flipHorizontal: Bool
    let flipVertical: Bool
    let straightenAngle: Double
    let verticalPerspective: Double
    let horizontalPerspective: Double

    static let neutral = PrefixGeometryKey(
        rotation: .zero, flipHorizontal: false, flipVertical: false,
        straightenAngle: 0, verticalPerspective: 0, horizontalPerspective: 0
    )

    init(
        rotation: ImageRotation, flipHorizontal: Bool, flipVertical: Bool,
        straightenAngle: Double, verticalPerspective: Double, horizontalPerspective: Double
    ) {
        self.rotation = rotation
        self.flipHorizontal = flipHorizontal
        self.flipVertical = flipVertical
        self.straightenAngle = straightenAngle
        self.verticalPerspective = verticalPerspective
        self.horizontalPerspective = horizontalPerspective
    }

    init(_ document: EditDocument) {
        self.init(
            rotation: document.rotation,
            flipHorizontal: document.crop.flipHorizontal, flipVertical: document.crop.flipVertical,
            straightenAngle: document.crop.straightenAngle,
            verticalPerspective: document.crop.verticalPerspective,
            horizontalPerspective: document.crop.horizontalPerspective
        )
    }
}

/// Identity for the one intentionally materialized expensive prefix.
struct ProcessingPrefixCacheKey: Hashable, Sendable {
    let source: RenderSourceFingerprint
    let developHash: String
    let upstreamHash: String
    let stage: ProcessingPrefixStage
    let localAdjustmentsHash: String?
    let maskResolutionState: String?
    let maskPayloadVersion: String?
    let scale: RenderScaleKey
    let sourceROI: CGRect?
    let geometry: PrefixGeometryKey
    let space: WorkingSpace
    let includePostRenderWhiteBalance: Bool
    let pipelineVersion: Int

    init(
        source: RenderSourceFingerprint,
        developHash: String,
        upstreamHash: String,
        stage: ProcessingPrefixStage = .graded,
        localAdjustmentsHash: String? = nil,
        maskResolutionState: String? = nil,
        maskPayloadVersion: String? = nil,
        scale: RenderScaleKey,
        sourceROI: CGRect?,
        geometry: PrefixGeometryKey = .neutral,
        space: WorkingSpace,
        includePostRenderWhiteBalance: Bool,
        pipelineVersion: Int
    ) {
        self.source = source
        self.developHash = developHash
        self.upstreamHash = upstreamHash
        self.stage = stage
        self.localAdjustmentsHash = localAdjustmentsHash
        self.maskResolutionState = maskResolutionState
        self.maskPayloadVersion = maskPayloadVersion
        self.scale = scale
        self.sourceROI = sourceROI
        self.geometry = geometry
        self.space = space
        self.includePostRenderWhiteBalance = includePostRenderWhiteBalance
        self.pipelineVersion = pipelineVersion
    }
}

/// Identity for one resolved local-mask component. It deliberately contains no document/global
/// slider hash: changing exposure or a LUT must not invalidate a reusable mask payload.
struct LocalMaskCacheKey: Hashable, Sendable {
    let source: RenderSourceFingerprint
    let definitionHash: String
    let targetSize: PixelDimensions
    let quality: RenderQuality
    let transform: LocalMaskRenderTransform
    let rendererVersion: Int
}

/// Cache identity for a display raster. Full-resolution/export requests never create this key.
struct PreviewCacheKey: Hashable, Sendable {
    let source: RenderSourceFingerprint
    let documentHash: String
    let lutFingerprint: String
    let targetScale: RenderScaleKey
    let sourceROI: CGRect?
    let presentationROI: CGRect?
    let quality: RenderQuality
    let space: WorkingSpace
    let pipelineVersion: Int
}

enum RenderCacheHash {
    static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).hexString
    }

    static func digest<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        // A fixed fallback would let two different values that both fail to encode (e.g. a
        // non-conforming Double such as .nan) collide on the same cache key and serve each other's
        // pixels. A fresh identity per failure guarantees a miss instead — safe, just uncached.
        guard let data = try? encoder.encode(value) else { return "encoding-failed:\(UUID())" }
        return digest(data)
    }
}

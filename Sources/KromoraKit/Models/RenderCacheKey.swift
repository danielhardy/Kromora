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
            case .preview(let size), .interactive(let size, _):
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
/// after the developed source has been built.
struct DevelopedSourceCacheKey: Hashable, Sendable {
    let source: RenderSourceFingerprint
    let developHash: String
    let scale: RenderScaleKey
    let pipelineVersion: Int
}

/// The materialized prefix can stop either before local adjustments or immediately after them.
/// LUT intensity/content and the composition effects below it remain common interactive edit
/// targets in both cases.
enum ProcessingPrefixStage: String, Hashable, Sendable {
    case preLUT
    case postLocal
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
    let space: WorkingSpace
    let includePostRenderWhiteBalance: Bool
    let pipelineVersion: Int

    init(
        source: RenderSourceFingerprint,
        developHash: String,
        upstreamHash: String,
        stage: ProcessingPrefixStage = .preLUT,
        localAdjustmentsHash: String? = nil,
        maskResolutionState: String? = nil,
        maskPayloadVersion: String? = nil,
        scale: RenderScaleKey,
        sourceROI: CGRect?,
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
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
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

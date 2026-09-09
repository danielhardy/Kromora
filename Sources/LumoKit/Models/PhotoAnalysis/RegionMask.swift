import Foundation

enum SemanticMaskKind: Codable, Sendable, Equatable, Hashable {
    /// The stable user-facing foreground selection. Instance kinds remain available for analysis
    /// and diagnostics, but callers should use this union for durable editing recipes.
    case foreground
    case subject
    case background
    case person
    case face
    /// The first detected face is addressed by `face`; additional faces use this indexed kind.
    /// Keeping `.face` source-compatible makes the common single-face request ergonomic while
    /// still giving multi-face consumers a stable cache identity for every detection.
    case faceInstance(Int)
    case foregroundInstance(Int)
    /// New semantic kinds can be cached and round-tripped before the app learns how to render them.
    case unknown(String)
}

enum MaskQuality: String, Codable, Sendable, Equatable, Comparable, CaseIterable {
    case analysis
    case preview
    case render

    static func < (lhs: MaskQuality, rhs: MaskQuality) -> Bool {
        let rank: [MaskQuality: Int] = [.analysis: 0, .preview: 1, .render: 2]
        return rank[lhs, default: 0] < rank[rhs, default: 0]
    }
}

struct MaskCacheKey: Codable, Sendable, Equatable, Hashable {
    let assetID: PhotoAssetID
    let sourceFingerprint: PhotoSourceFingerprint
    let kind: SemanticMaskKind
    let quality: MaskQuality
    let providerVersion: String

    init(
        assetID: PhotoAssetID,
        sourceFingerprint: PhotoSourceFingerprint,
        kind: SemanticMaskKind,
        quality: MaskQuality = .analysis,
        providerVersion: String = "vision-1"
    ) {
        self.assetID = assetID
        self.sourceFingerprint = sourceFingerprint
        self.kind = kind
        self.quality = quality
        self.providerVersion = providerVersion
    }

    func with(quality: MaskQuality) -> MaskCacheKey {
        MaskCacheKey(assetID: assetID, sourceFingerprint: sourceFingerprint, kind: kind,
                     quality: quality, providerVersion: providerVersion)
    }

    func with(kind: SemanticMaskKind, quality: MaskQuality? = nil) -> MaskCacheKey {
        MaskCacheKey(assetID: assetID, sourceFingerprint: sourceFingerprint, kind: kind,
                     quality: quality ?? self.quality, providerVersion: providerVersion)
    }
}

struct RegionMaskReference: Codable, Sendable, Equatable, Hashable {
    let cacheKey: MaskCacheKey
    let size: PixelDimensions
    let quality: MaskQuality

    init(cacheKey: MaskCacheKey, size: PixelDimensions, quality: MaskQuality? = nil) {
        self.cacheKey = cacheKey.with(quality: quality ?? cacheKey.quality)
        self.size = size
        self.quality = quality ?? cacheKey.quality
    }
}

/// A portable mask payload for operations and tests. RegionMask itself stores only a reference so
/// large pixel buffers remain owned by MaskStore rather than being copied into analysis results.
struct NormalizedMask: Codable, Sendable, Equatable {
    let size: PixelDimensions
    let values: [Float]
    let coverage: Float
    /// Whether every value is exactly 0 or 1. Computed once here rather than rescanned by
    /// renderers on every frame, since a mask's values never change after construction.
    let isBinary: Bool

    init(size: PixelDimensions, values: [Float]) throws {
        guard values.count == size.width * size.height else { throw RegionMaskError.invalidPixelCount }
        var normalized: [Float] = []
        normalized.reserveCapacity(values.count)
        var total: Float = 0
        var binary = true
        for value in values {
            guard value.isFinite else { throw RegionMaskError.invalidPixelValue }
            let clipped = min(max(value, 0), 1)
            normalized.append(clipped)
            total += clipped
            if clipped != 0, clipped != 1 { binary = false }
        }
        self.size = size
        self.values = normalized
        self.coverage = normalized.isEmpty ? 0 : total / Float(normalized.count)
        self.isBinary = binary
    }

    /// Used only by internal producers after they have validated the dimensions and established
    /// the [0, 1] invariant. The optional coverage is for small/test call sites; hot producers
    /// pass the sum they already accumulated while generating the values.
    init(
        trustingSize size: PixelDimensions,
        values: [Float],
        coverage: Float? = nil,
        isBinary: Bool? = nil
    ) {
        precondition(values.count == size.width * size.height, "mask values must match mask size")
        self.size = size
        self.values = values
        self.coverage = coverage ?? (values.isEmpty ? 0 : values.reduce(0, +) / Float(values.count))
        self.isBinary = isBinary ?? values.allSatisfy { $0 == 0 || $0 == 1 }
    }

    private enum CodingKeys: String, CodingKey {
        case size
        case values
    }

    /// Coverage is derived on decode so legacy payloads that contain only size and values remain
    /// readable. This is also the validating I/O boundary for inline and decoded mask payloads.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            size: container.decode(PixelDimensions.self, forKey: .size),
            values: container.decode([Float].self, forKey: .values)
        )
    }

    /// Keep coverage out of serialized payloads; it is a derived value and older sidecars do not
    /// carry it. Persisted mask metadata has its own custom schema in MaskStore.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(size, forKey: .size)
        try container.encode(values, forKey: .values)
    }
}

struct RegionMask: Codable, Sendable, Equatable, Identifiable {
    let id: UUID
    let kind: SemanticMaskKind
    let bounds: NormalizedRect
    let quality: MaskQuality
    let reference: RegionMaskReference
    let confidence: Float
    let coverage: Float

    init(
        id: UUID = UUID(),
        kind: SemanticMaskKind,
        bounds: NormalizedRect,
        quality: MaskQuality,
        reference: RegionMaskReference,
        confidence: Float,
        coverage: Float
    ) {
        self.id = id
        self.kind = kind
        self.bounds = bounds
        self.quality = quality
        self.reference = reference
        self.confidence = Self.unit(confidence)
        self.coverage = Self.unit(coverage)
    }

    private static func unit(_ value: Float) -> Float {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }
}

/// Presentation policy for semantic masks. This is deliberately separate from mask production:
/// filtering a result must never prevent Auto or the cache from retaining it.
enum MaskPresentationPolicy {
    /// A mask needs a small but non-trivial area and stable provider confidence to be useful to
    /// an editor. Background is not special-cased; a full-frame background is valid and useful.
    static let minimumConfidence: Float = 0.55
    static let minimumCoverage: Float = 0.02

    enum Decision: Equatable, Sendable {
        case actionable
        case lowConfidence
        case empty

        var userMessage: String? {
            switch self {
            case .actionable: return nil
            case .lowConfidence: return "This target is unavailable because the region was not confidently identified."
            case .empty: return "This target is unavailable because no usable region was found."
            }
        }
    }

    static func decision(for mask: RegionMask) -> Decision {
        guard mask.coverage >= minimumCoverage else { return .empty }
        guard mask.confidence >= minimumConfidence else { return .lowConfidence }
        return .actionable
    }

}

protocol SemanticMaskProviding: Sendable {
    func mask(for kind: SemanticMaskKind, image: AnalysisImage, quality: MaskQuality) async throws -> RegionMask
}

enum RegionMaskError: Error, Sendable, Equatable {
    case invalidPixelCount
    case invalidPixelValue
    case incompatibleSizes
    case missingPixels
}

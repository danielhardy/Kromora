import Foundation

enum SemanticMaskKind: Codable, Sendable, Equatable, Hashable {
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

    init(size: PixelDimensions, values: [Float]) throws {
        guard values.count == size.width * size.height else { throw RegionMaskError.invalidPixelCount }
        guard values.allSatisfy({ $0.isFinite }) else { throw RegionMaskError.invalidPixelValue }
        self.size = size
        self.values = values.map { min(max($0, 0), 1) }
    }

    var coverage: Float {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Float(values.count)
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

protocol SemanticMaskProviding: Sendable {
    func mask(for kind: SemanticMaskKind, image: AnalysisImage, quality: MaskQuality) async throws -> RegionMask
}

enum RegionMaskError: Error, Sendable, Equatable {
    case invalidPixelCount
    case invalidPixelValue
    case incompatibleSizes
    case missingPixels
}

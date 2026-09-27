import CoreGraphics
import Foundation

struct RetouchSettings: Codable, Sendable, Equatable {
    static let neutral = RetouchSettings()
    var spots: [RetouchSpot]
    var eyes: [EyeCorrection]

    init(spots: [RetouchSpot] = [], eyes: [EyeCorrection] = []) {
        self.spots = spots
        self.eyes = eyes
    }

    private enum CodingKeys: String, CodingKey { case spots, eyes }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            spots: try c.decodeIfPresent([RetouchSpot].self, forKey: .spots) ?? [],
            eyes: try c.decodeIfPresent([EyeCorrection].self, forKey: .eyes) ?? []
        )
    }

    var isIdentity: Bool { spots.allSatisfy(\.isIdentity) && eyes.allSatisfy(\.isIdentity) }
}

enum RetouchMode: String, Codable, Sendable, CaseIterable { case remove, heal, clone }
enum EyeKind: String, Codable, Sendable, CaseIterable { case human, pet }

struct RetouchRegion: Codable, Sendable, Equatable {
    var samples: [BrushSample]
    /// Fraction of the oriented source's shorter side.
    var radius: Double

    init(samples: [BrushSample] = [BrushSample(point: CGPoint(x: 0.5, y: 0.5))], radius: Double = 0.02) {
        self.samples = Array(samples.prefix(4096))
        self.radius = Self.clamp(radius, fallback: 0.02, range: 0.0005...0.25)
    }

    private enum CodingKeys: String, CodingKey { case samples, radius }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            samples: try c.decodeIfPresent([BrushSample].self, forKey: .samples) ?? [],
            radius: try c.decodeIfPresent(Double.self, forKey: .radius) ?? 0.02
        )
    }

    private static func clamp(_ value: Double, fallback: Double, range: ClosedRange<Double>) -> Double {
        value.isFinite ? min(max(value, range.lowerBound), range.upperBound) : fallback
    }
}

enum RetouchSource: Codable, Sendable, Equatable {
    case auto(offset: CGVector, rank: Int)
    case manual(offset: CGVector)

    var offset: CGVector {
        switch self {
        case .auto(let offset, _), .manual(let offset): return offset
        }
    }

    private enum CodingKeys: String, CodingKey { case kind, offset, rank }
    private enum Kind: String, Codable { case auto, manual }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let offset = Self.clamp(try c.decodeIfPresent(CGVector.self, forKey: .offset) ?? .zero)
        switch try c.decodeIfPresent(Kind.self, forKey: .kind) ?? .manual {
        case .auto: self = .auto(offset: offset, rank: max(0, try c.decodeIfPresent(Int.self, forKey: .rank) ?? 0))
        case .manual: self = .manual(offset: offset)
        }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .auto(let offset, let rank):
            try c.encode(Kind.auto, forKey: .kind); try c.encode(Self.clamp(offset), forKey: .offset)
            try c.encode(max(0, rank), forKey: .rank)
        case .manual(let offset):
            try c.encode(Kind.manual, forKey: .kind); try c.encode(Self.clamp(offset), forKey: .offset)
        }
    }
    private static func clamp(_ v: CGVector) -> CGVector {
        func c(_ n: CGFloat) -> CGFloat { n.isFinite ? min(max(n, -1.5), 1.5) : 0 }
        return CGVector(dx: c(v.dx), dy: c(v.dy))
    }
}

struct RetouchSpot: Codable, Sendable, Equatable, Identifiable {
    var id: UUID
    var mode: RetouchMode
    var region: RetouchRegion
    var source: RetouchSource?
    var feather: Double
    var opacity: Double
    var isVisible: Bool
    var seed: UInt32

    init(id: UUID = UUID(), mode: RetouchMode = .remove, region: RetouchRegion = RetouchRegion(
        samples: [BrushSample(point: CGPoint(x: 0.5, y: 0.5))]), source: RetouchSource? = nil,
        feather: Double = 0.35, opacity: Double = 1, isVisible: Bool = true, seed: UInt32 = 0
    ) {
        self.id = id; self.mode = mode; self.region = region; self.source = source
        self.feather = Self.clamp(feather, fallback: 0.35, range: 0...1)
        self.opacity = Self.clamp(opacity, fallback: 1, range: 0...1)
        self.isVisible = isVisible; self.seed = seed
    }

    var isIdentity: Bool { !isVisible || opacity == 0 || region.samples.isEmpty }
    private enum CodingKeys: String, CodingKey { case id, mode, region, source, feather, opacity, isVisible, seed }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID(),
            mode: try c.decodeIfPresent(RetouchMode.self, forKey: .mode) ?? .remove,
            region: try c.decodeIfPresent(RetouchRegion.self, forKey: .region) ?? RetouchRegion(),
            source: try c.decodeIfPresent(RetouchSource.self, forKey: .source),
            feather: try c.decodeIfPresent(Double.self, forKey: .feather) ?? 0.35,
            opacity: try c.decodeIfPresent(Double.self, forKey: .opacity) ?? 1,
            isVisible: try c.decodeIfPresent(Bool.self, forKey: .isVisible) ?? true,
            seed: try c.decodeIfPresent(UInt32.self, forKey: .seed) ?? 0
        )
    }
    private static func clamp(_ value: Double, fallback: Double, range: ClosedRange<Double>) -> Double {
        value.isFinite ? min(max(value, range.lowerBound), range.upperBound) : fallback
    }
}

struct EyeCorrection: Codable, Sendable, Equatable, Identifiable {
    var id: UUID
    var kind: EyeKind
    var center: CGPoint
    var radiusX: Double
    var radiusY: Double
    var pupilSize: Double
    var darken: Double
    var addCatchlight: Bool
    var catchlightOffset: CGVector
    var isVisible: Bool

    init(
        id: UUID = UUID(), kind: EyeKind = .human, center: CGPoint = CGPoint(x: 0.5, y: 0.5),
        radiusX: Double = 0.015, radiusY: Double = 0.01, pupilSize: Double = 50,
        darken: Double = 50, addCatchlight: Bool = false,
        catchlightOffset: CGVector = CGVector(dx: -0.3, dy: -0.3), isVisible: Bool = true
    ) {
        self.id = id
        self.kind = kind
        self.center = CGPoint(
            x: center.x.isFinite ? min(max(center.x, -0.25), 1.25) : 0.5,
            y: center.y.isFinite ? min(max(center.y, -0.25), 1.25) : 0.5
        )
        self.radiusX = Self.clamp(radiusX, fallback: 0.015, range: 0.001...0.1)
        self.radiusY = Self.clamp(radiusY, fallback: 0.01, range: 0.001...0.1)
        self.pupilSize = Self.clamp(pupilSize, fallback: 50, range: 0...100)
        self.darken = Self.clamp(darken, fallback: 50, range: 0...100)
        self.addCatchlight = addCatchlight
        self.catchlightOffset = CGVector(
            dx: catchlightOffset.dx.isFinite ? min(max(catchlightOffset.dx, -1), 1) : -0.3,
            dy: catchlightOffset.dy.isFinite ? min(max(catchlightOffset.dy, -1), 1) : -0.3
        )
        self.isVisible = isVisible
    }

    var isIdentity: Bool { !isVisible || darken == 0 || pupilSize == 0 }

    private enum CodingKeys: String, CodingKey {
        case id, kind, center, radiusX, radiusY, pupilSize, darken, addCatchlight, catchlightOffset, isVisible
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID(),
            kind: try c.decodeIfPresent(EyeKind.self, forKey: .kind) ?? .human,
            center: try c.decodeIfPresent(CGPoint.self, forKey: .center) ?? CGPoint(x: 0.5, y: 0.5),
            radiusX: try c.decodeIfPresent(Double.self, forKey: .radiusX) ?? 0.015,
            radiusY: try c.decodeIfPresent(Double.self, forKey: .radiusY) ?? 0.01,
            pupilSize: try c.decodeIfPresent(Double.self, forKey: .pupilSize) ?? 50,
            darken: try c.decodeIfPresent(Double.self, forKey: .darken) ?? 50,
            addCatchlight: try c.decodeIfPresent(Bool.self, forKey: .addCatchlight) ?? false,
            catchlightOffset: try c.decodeIfPresent(CGVector.self, forKey: .catchlightOffset)
                ?? CGVector(dx: -0.3, dy: -0.3),
            isVisible: try c.decodeIfPresent(Bool.self, forKey: .isVisible) ?? true
        )
    }

    private static func clamp(_ value: Double, fallback: Double, range: ClosedRange<Double>) -> Double {
        value.isFinite ? min(max(value, range.lowerBound), range.upperBound) : fallback
    }
}

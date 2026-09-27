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

enum RetouchMode: String, Codable, Sendable, CaseIterable { case heal, clone }
enum EyeKind: String, Codable, Sendable, CaseIterable { case human, pet }

enum SpotShape: Codable, Sendable, Equatable {
    case circle(center: CGPoint)
    case stroke(points: [CGPoint])

    private enum CodingKeys: String, CodingKey { case kind, center, points }
    private enum Kind: String, Codable { case circle, stroke }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .circle:
            self = .circle(center: Self.clamp(
                try container.decodeIfPresent(CGPoint.self, forKey: .center) ?? .zero
            ))
        case .stroke:
            let points = try container.decodeIfPresent([CGPoint].self, forKey: .points) ?? []
            self = .stroke(points: Array(points.prefix(256)).map(Self.clamp))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .circle(let center):
            try container.encode(Kind.circle, forKey: .kind)
            try container.encode(Self.clamp(center), forKey: .center)
        case .stroke(let points):
            try container.encode(Kind.stroke, forKey: .kind)
            try container.encode(Array(points.prefix(256)).map(Self.clamp), forKey: .points)
        }
    }

    private static func clamp(_ point: CGPoint) -> CGPoint {
        func value(_ n: CGFloat) -> CGFloat {
            n.isFinite ? min(max(n, -0.25), 1.25) : 0.5
        }
        return CGPoint(x: value(point.x), y: value(point.y))
    }
}

struct RetouchSpot: Codable, Sendable, Equatable, Identifiable {
    var id: UUID
    var name: String?
    var mode: RetouchMode
    var shape: SpotShape
    var radius: Double
    var sourceOffset: CGVector
    var feather: Double
    var opacity: Double
    var isVisible: Bool
    var sourceWasAutoPicked: Bool

    init(
        id: UUID = UUID(), name: String? = nil, mode: RetouchMode = .heal,
        shape: SpotShape = .circle(center: CGPoint(x: 0.5, y: 0.5)),
        radius: Double = 0.02, sourceOffset: CGVector = .zero,
        feather: Double? = nil, opacity: Double = 1, isVisible: Bool = true,
        sourceWasAutoPicked: Bool = true
    ) {
        self.id = id
        self.name = name
        self.mode = mode
        self.shape = shape
        self.radius = Self.finiteClamp(radius, fallback: 0.02, range: 0.0005...0.25)
        self.sourceOffset = CGVector(
            dx: Self.coordinate(sourceOffset.dx), dy: Self.coordinate(sourceOffset.dy)
        )
        self.feather = Self.finiteClamp(feather ?? (mode == .heal ? 0.35 : 0.5), fallback: 0.35, range: 0...1)
        self.opacity = Self.finiteClamp(opacity, fallback: 1, range: 0...1)
        self.isVisible = isVisible
        self.sourceWasAutoPicked = sourceWasAutoPicked
    }

    var isIdentity: Bool { !isVisible || opacity == 0 }

    private enum CodingKeys: String, CodingKey {
        case id, name, mode, shape, radius, sourceOffset, feather, opacity, isVisible, sourceWasAutoPicked
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID(),
            name: try c.decodeIfPresent(String.self, forKey: .name),
            mode: try c.decodeIfPresent(RetouchMode.self, forKey: .mode) ?? .heal,
            shape: try c.decodeIfPresent(SpotShape.self, forKey: .shape) ?? .circle(center: CGPoint(x: 0.5, y: 0.5)),
            radius: try c.decodeIfPresent(Double.self, forKey: .radius) ?? 0.02,
            sourceOffset: try c.decodeIfPresent(CGVector.self, forKey: .sourceOffset) ?? .zero,
            feather: try c.decodeIfPresent(Double.self, forKey: .feather),
            opacity: try c.decodeIfPresent(Double.self, forKey: .opacity) ?? 1,
            isVisible: try c.decodeIfPresent(Bool.self, forKey: .isVisible) ?? true,
            sourceWasAutoPicked: try c.decodeIfPresent(Bool.self, forKey: .sourceWasAutoPicked) ?? false
        )
    }

    private static func coordinate(_ value: CGFloat) -> CGFloat {
        value.isFinite ? min(max(value, -1.5), 1.5) : 0
    }
    private static func finiteClamp(_ value: Double, fallback: Double, range: ClosedRange<Double>) -> Double {
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

    var isIdentity: Bool { !isVisible }

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

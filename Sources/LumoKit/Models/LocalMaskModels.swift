import Foundation

// MARK: - Local adjustment values

/// Photographer-facing adjustments applied through a local mask.
///
/// These values intentionally use the same neutral points as the global controls where the
/// renderer will eventually share its mapping. They are recipes, not rendered pixels, and are
/// therefore independent of preview/export resolution.
struct LocalAdjustments: Codable, Sendable, Equatable {
    static let neutral = LocalAdjustments()

    static let exposureRange = -5.0...5.0
    static let contrastRange = -100.0...100.0
    static let highlightsRange = -100.0...100.0
    static let shadowsRange = -100.0...100.0
    static let whitesRange = -100.0...100.0
    static let blacksRange = -100.0...100.0
    static let temperatureRange = 2000.0...11000.0
    static let tintRange = -150.0...150.0
    static let saturationRange = -100.0...100.0
    static let vibranceRange = -100.0...100.0
    static let textureRange = -100.0...100.0
    static let clarityRange = -100.0...100.0
    static let dehazeRange = -100.0...100.0

    var exposure: Double { didSet { exposure = Self.clamp(exposure, to: Self.exposureRange, default: 0) } }
    var contrast: Double { didSet { contrast = Self.clamp(contrast, to: Self.contrastRange, default: 0) } }
    var highlights: Double { didSet { highlights = Self.clamp(highlights, to: Self.highlightsRange, default: 0) } }
    var shadows: Double { didSet { shadows = Self.clamp(shadows, to: Self.shadowsRange, default: 0) } }
    var whites: Double { didSet { whites = Self.clamp(whites, to: Self.whitesRange, default: 0) } }
    var blacks: Double { didSet { blacks = Self.clamp(blacks, to: Self.blacksRange, default: 0) } }
    var temperature: Double { didSet { temperature = Self.clamp(temperature, to: Self.temperatureRange, default: 6500) } }
    var tint: Double { didSet { tint = Self.clamp(tint, to: Self.tintRange, default: 0) } }
    var saturation: Double { didSet { saturation = Self.clamp(saturation, to: Self.saturationRange, default: 0) } }
    var vibrance: Double { didSet { vibrance = Self.clamp(vibrance, to: Self.vibranceRange, default: 0) } }
    var texture: Double { didSet { texture = Self.clamp(texture, to: Self.textureRange, default: 0) } }
    var clarity: Double { didSet { clarity = Self.clamp(clarity, to: Self.clarityRange, default: 0) } }
    var dehaze: Double { didSet { dehaze = Self.clamp(dehaze, to: Self.dehazeRange, default: 0) } }

    init(
        exposure: Double = 0, contrast: Double = 0, highlights: Double = 0,
        shadows: Double = 0, whites: Double = 0, blacks: Double = 0,
        temperature: Double = 6500, tint: Double = 0, saturation: Double = 0,
        vibrance: Double = 0, texture: Double = 0, clarity: Double = 0,
        dehaze: Double = 0
    ) {
        self.exposure = Self.clamp(exposure, to: Self.exposureRange, default: 0)
        self.contrast = Self.clamp(contrast, to: Self.contrastRange, default: 0)
        self.highlights = Self.clamp(highlights, to: Self.highlightsRange, default: 0)
        self.shadows = Self.clamp(shadows, to: Self.shadowsRange, default: 0)
        self.whites = Self.clamp(whites, to: Self.whitesRange, default: 0)
        self.blacks = Self.clamp(blacks, to: Self.blacksRange, default: 0)
        self.temperature = Self.clamp(temperature, to: Self.temperatureRange, default: 6500)
        self.tint = Self.clamp(tint, to: Self.tintRange, default: 0)
        self.saturation = Self.clamp(saturation, to: Self.saturationRange, default: 0)
        self.vibrance = Self.clamp(vibrance, to: Self.vibranceRange, default: 0)
        self.texture = Self.clamp(texture, to: Self.textureRange, default: 0)
        self.clarity = Self.clamp(clarity, to: Self.clarityRange, default: 0)
        self.dehaze = Self.clamp(dehaze, to: Self.dehazeRange, default: 0)
    }

    var isIdentity: Bool {
        exposure == 0 && contrast == 0 && highlights == 0 && shadows == 0 &&
            whites == 0 && blacks == 0 && temperature == 6500 && tint == 0 &&
            saturation == 0 && vibrance == 0 && texture == 0 && clarity == 0 && dehaze == 0
    }

    /// Core Image's normalized values, exposed here so global and local render mapping can share
    /// these conventions without changing the persisted units.
    var normalizedSaturation: Double { 1 + saturation / 100 }
    var normalizedVibrance: Double { vibrance / 100 }

    private enum CodingKeys: String, CodingKey {
        case exposure, contrast, highlights, shadows, whites, blacks, temperature, tint,
             saturation, vibrance, texture, clarity, dehaze
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            exposure: try c.decodeIfPresent(Double.self, forKey: .exposure) ?? 0,
            contrast: try c.decodeIfPresent(Double.self, forKey: .contrast) ?? 0,
            highlights: try c.decodeIfPresent(Double.self, forKey: .highlights) ?? 0,
            shadows: try c.decodeIfPresent(Double.self, forKey: .shadows) ?? 0,
            whites: try c.decodeIfPresent(Double.self, forKey: .whites) ?? 0,
            blacks: try c.decodeIfPresent(Double.self, forKey: .blacks) ?? 0,
            temperature: try c.decodeIfPresent(Double.self, forKey: .temperature) ?? 6500,
            tint: try c.decodeIfPresent(Double.self, forKey: .tint) ?? 0,
            saturation: try c.decodeIfPresent(Double.self, forKey: .saturation) ?? 0,
            vibrance: try c.decodeIfPresent(Double.self, forKey: .vibrance) ?? 0,
            texture: try c.decodeIfPresent(Double.self, forKey: .texture) ?? 0,
            clarity: try c.decodeIfPresent(Double.self, forKey: .clarity) ?? 0,
            dehaze: try c.decodeIfPresent(Double.self, forKey: .dehaze) ?? 0
        )
    }

    private static func clamp(_ value: Double, to range: ClosedRange<Double>, default fallback: Double) -> Double {
        guard value.isFinite else { return fallback }
        return min(max(value, range.lowerBound), range.upperBound)
    }
}

// MARK: - Mask definitions

enum SemanticTarget: String, Codable, Sendable, Equatable, CaseIterable {
    case foreground, background, subject, person, face
}

struct SemanticMaskDefinition: Codable, Sendable, Equatable {
    var target: SemanticTarget
    var edgeFeather: Double
    var edgeShift: Double
    var density: Double
    var generationVersion: Int

    init(
        target: SemanticTarget = .foreground, edgeFeather: Double = 0,
        edgeShift: Double = 0, density: Double = 1, generationVersion: Int = 1
    ) {
        self.target = target
        self.edgeFeather = Self.unit(edgeFeather)
        self.edgeShift = Self.clamp(edgeShift, -1...1, default: 0)
        self.density = Self.unit(density)
        self.generationVersion = max(1, generationVersion)
    }

    private enum CodingKeys: String, CodingKey { case target, edgeFeather, edgeShift, density, generationVersion }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            target: try c.decodeIfPresent(SemanticTarget.self, forKey: .target) ?? .foreground,
            edgeFeather: try c.decodeIfPresent(Double.self, forKey: .edgeFeather) ?? 0,
            edgeShift: try c.decodeIfPresent(Double.self, forKey: .edgeShift) ?? 0,
            density: try c.decodeIfPresent(Double.self, forKey: .density) ?? 1,
            generationVersion: try c.decodeIfPresent(Int.self, forKey: .generationVersion) ?? 1
        )
    }

    private static func unit(_ value: Double) -> Double { clamp(value, 0...1, default: 0) }
    private static func clamp(_ value: Double, _ range: ClosedRange<Double>, default fallback: Double) -> Double {
        guard value.isFinite else { return fallback }
        return min(max(value, range.lowerBound), range.upperBound)
    }
}

struct BrushSample: Codable, Sendable, Equatable {
    /// Upper-left oriented-source coordinates, normalized to 0...1.
    var point: CGPoint
    var pressure: Double?

    init(point: CGPoint, pressure: Double? = nil) {
        self.point = Self.normalized(point)
        self.pressure = pressure.map { Self.clamp($0, 0...1, default: 1) }
    }

    private enum CodingKeys: String, CodingKey { case point, pressure }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            point: try c.decodeIfPresent(CGPoint.self, forKey: .point) ?? .zero,
            pressure: try c.decodeIfPresent(Double.self, forKey: .pressure)
        )
    }

    private static func normalized(_ point: CGPoint) -> CGPoint {
        CGPoint(x: clamp(point.x, 0...1, default: 0), y: clamp(point.y, 0...1, default: 0))
    }
    private static func clamp(_ value: Double, _ range: ClosedRange<Double>, default fallback: Double) -> Double {
        guard value.isFinite else { return fallback }
        return min(max(value, range.lowerBound), range.upperBound)
    }
}

struct BrushStroke: Codable, Sendable, Equatable, Identifiable {
    var id: UUID
    var samples: [BrushSample]
    /// Fraction of the source's shorter side.
    var radius: Double { didSet { radius = Self.clamp(radius, 0...1, default: 0.05) } }
    var feather: Double { didSet { feather = Self.clamp(feather, 0...1, default: 0.5) } }
    var flow: Double { didSet { flow = Self.clamp(flow, 0...1, default: 1) } }
    var density: Double { didSet { density = Self.clamp(density, 0...1, default: 1) } }

    init(
        id: UUID = UUID(), samples: [BrushSample] = [], radius: Double = 0.05,
        feather: Double = 0.5, flow: Double = 1, density: Double = 1
    ) {
        self.id = id
        self.samples = samples
        self.radius = Self.clamp(radius, 0...1, default: 0.05)
        self.feather = Self.clamp(feather, 0...1, default: 0.5)
        self.flow = Self.clamp(flow, 0...1, default: 1)
        self.density = Self.clamp(density, 0...1, default: 1)
    }

    private enum CodingKeys: String, CodingKey { case id, samples, radius, feather, flow, density }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID(),
            samples: try c.decodeIfPresent([BrushSample].self, forKey: .samples) ?? [],
            radius: try c.decodeIfPresent(Double.self, forKey: .radius) ?? 0.05,
            feather: try c.decodeIfPresent(Double.self, forKey: .feather) ?? 0.5,
            flow: try c.decodeIfPresent(Double.self, forKey: .flow) ?? 1,
            density: try c.decodeIfPresent(Double.self, forKey: .density) ?? 1
        )
    }

    private static func clamp(_ value: Double, _ range: ClosedRange<Double>, default fallback: Double) -> Double {
        guard value.isFinite else { return fallback }
        return min(max(value, range.lowerBound), range.upperBound)
    }
}

struct BrushMaskDefinition: Codable, Sendable, Equatable {
    var strokes: [BrushStroke]
    init(strokes: [BrushStroke] = []) { self.strokes = strokes }
}

struct LinearGradientDefinition: Codable, Sendable, Equatable {
    /// The zero-strength and full-strength edges in upper-left oriented-source coordinates.
    var zeroStrengthPoint: CGPoint
    var fullStrengthPoint: CGPoint
    var density: Double { didSet { density = Self.clamp(density, 0...1, default: 1) } }

    init(zeroStrengthPoint: CGPoint = CGPoint(x: 0, y: 0.5), fullStrengthPoint: CGPoint = CGPoint(x: 1, y: 0.5), density: Double = 1) {
        self.zeroStrengthPoint = Self.point(zeroStrengthPoint)
        self.fullStrengthPoint = Self.point(fullStrengthPoint)
        self.density = Self.clamp(density, 0...1, default: 1)
    }

    var startPoint: CGPoint { zeroStrengthPoint }
    var endPoint: CGPoint { fullStrengthPoint }

    private enum CodingKeys: String, CodingKey { case zeroStrengthPoint, fullStrengthPoint, density }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            zeroStrengthPoint: try c.decodeIfPresent(CGPoint.self, forKey: .zeroStrengthPoint) ?? CGPoint(x: 0, y: 0.5),
            fullStrengthPoint: try c.decodeIfPresent(CGPoint.self, forKey: .fullStrengthPoint) ?? CGPoint(x: 1, y: 0.5),
            density: try c.decodeIfPresent(Double.self, forKey: .density) ?? 1
        )
    }
    private static func point(_ p: CGPoint) -> CGPoint { CGPoint(x: clamp(p.x, 0...1, default: 0), y: clamp(p.y, 0...1, default: 0)) }
    private static func clamp(_ value: Double, _ range: ClosedRange<Double>, default fallback: Double) -> Double {
        guard value.isFinite else { return fallback }
        return min(max(value, range.lowerBound), range.upperBound)
    }
}

struct RadialGradientDefinition: Codable, Sendable, Equatable {
    var center: CGPoint
    var horizontalRadius: Double { didSet { horizontalRadius = Self.clamp(horizontalRadius, 0...1, default: 0.5) } }
    var verticalRadius: Double { didSet { verticalRadius = Self.clamp(verticalRadius, 0...1, default: 0.5) } }
    var rotation: Double { didSet { rotation = rotation.isFinite ? rotation : 0 } }
    var feather: Double { didSet { feather = Self.clamp(feather, 0...1, default: 0.5) } }
    var density: Double { didSet { density = Self.clamp(density, 0...1, default: 1) } }
    var isInside: Bool

    init(center: CGPoint = CGPoint(x: 0.5, y: 0.5), horizontalRadius: Double = 0.5, verticalRadius: Double = 0.5, rotation: Double = 0, feather: Double = 0.5, density: Double = 1, isInside: Bool = true) {
        self.center = CGPoint(x: Self.clamp(center.x, 0...1, default: 0.5), y: Self.clamp(center.y, 0...1, default: 0.5))
        self.horizontalRadius = Self.clamp(horizontalRadius, 0...1, default: 0.5)
        self.verticalRadius = Self.clamp(verticalRadius, 0...1, default: 0.5)
        self.rotation = rotation.isFinite ? rotation : 0
        self.feather = Self.clamp(feather, 0...1, default: 0.5)
        self.density = Self.clamp(density, 0...1, default: 1)
        self.isInside = isInside
    }

    private enum CodingKeys: String, CodingKey { case center, horizontalRadius, verticalRadius, rotation, feather, density, isInside }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            center: try c.decodeIfPresent(CGPoint.self, forKey: .center) ?? CGPoint(x: 0.5, y: 0.5),
            horizontalRadius: try c.decodeIfPresent(Double.self, forKey: .horizontalRadius) ?? 0.5,
            verticalRadius: try c.decodeIfPresent(Double.self, forKey: .verticalRadius) ?? 0.5,
            rotation: try c.decodeIfPresent(Double.self, forKey: .rotation) ?? 0,
            feather: try c.decodeIfPresent(Double.self, forKey: .feather) ?? 0.5,
            density: try c.decodeIfPresent(Double.self, forKey: .density) ?? 1,
            isInside: try c.decodeIfPresent(Bool.self, forKey: .isInside) ?? true
        )
    }
    private static func clamp(_ value: Double, _ range: ClosedRange<Double>, default fallback: Double) -> Double {
        guard value.isFinite else { return fallback }
        return min(max(value, range.lowerBound), range.upperBound)
    }
}

enum MaskSource: Codable, Sendable, Equatable {
    case semantic(SemanticMaskDefinition)
    case brush(BrushMaskDefinition)
    case linear(LinearGradientDefinition)
    case radial(RadialGradientDefinition)

    private enum CodingKeys: String, CodingKey { case kind, semantic, brush, linear, radial }
    private enum Kind: String, Codable { case semantic, brush, linear, radial }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(Kind.self, forKey: .kind) {
        case .semantic: self = .semantic(try c.decode(SemanticMaskDefinition.self, forKey: .semantic))
        case .brush: self = .brush(try c.decode(BrushMaskDefinition.self, forKey: .brush))
        case .linear: self = .linear(try c.decode(LinearGradientDefinition.self, forKey: .linear))
        case .radial: self = .radial(try c.decode(RadialGradientDefinition.self, forKey: .radial))
        }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .semantic(let value): try c.encode(Kind.semantic, forKey: .kind); try c.encode(value, forKey: .semantic)
        case .brush(let value): try c.encode(Kind.brush, forKey: .kind); try c.encode(value, forKey: .brush)
        case .linear(let value): try c.encode(Kind.linear, forKey: .kind); try c.encode(value, forKey: .linear)
        case .radial(let value): try c.encode(Kind.radial, forKey: .kind); try c.encode(value, forKey: .radial)
        }
    }
}

extension MaskSource {
    /// Whether the recipe can produce any coverage. This keeps an empty brush recipe and disabled
    /// components exact no-ops even before a renderer resolves a source-specific mask.
    var hasPotentialCoverage: Bool {
        if case .brush(let value) = self { return !value.strokes.isEmpty }
        return true
    }

    var semanticDefinition: SemanticMaskDefinition? {
        guard case .semantic(let value) = self else { return nil }
        return value
    }
    var brushDefinition: BrushMaskDefinition? {
        guard case .brush(let value) = self else { return nil }
        return value
    }
    var linearDefinition: LinearGradientDefinition? {
        guard case .linear(let value) = self else { return nil }
        return value
    }
    var radialDefinition: RadialGradientDefinition? {
        guard case .radial(let value) = self else { return nil }
        return value
    }
}

enum MaskCombineMode: String, Codable, Sendable, Equatable, CaseIterable { case replace, add, subtract, intersect }

extension MaskCombineMode {
    func combining(current: Double, next: Double) -> Double {
        MaskComposition.combine(current, next, mode: self)
    }
}

struct MaskComponent: Codable, Sendable, Equatable, Identifiable {
    var id: UUID
    var mode: MaskCombineMode
    var isEnabled: Bool
    var isInverted: Bool
    var source: MaskSource

    init(id: UUID = UUID(), mode: MaskCombineMode = .replace, isEnabled: Bool = true, isInverted: Bool = false, source: MaskSource) {
        self.id = id; self.mode = mode; self.isEnabled = isEnabled; self.isInverted = isInverted; self.source = source
    }

    var isUsable: Bool { isEnabled && source.hasPotentialCoverage }
}

struct LocalAdjustmentLayer: Codable, Sendable, Equatable, Identifiable {
    var id: UUID
    var name: String
    var isEnabled: Bool
    var isInverted: Bool
    var amount: Double { didSet { amount = Self.clamp(amount, 0...1, default: 1) } }
    var components: [MaskComponent]
    var adjustments: LocalAdjustments

    init(id: UUID = UUID(), name: String = "Local Adjustment", isEnabled: Bool = true, isInverted: Bool = false, amount: Double = 1, components: [MaskComponent] = [], adjustments: LocalAdjustments = .neutral) {
        self.id = id; self.name = name; self.isEnabled = isEnabled; self.isInverted = isInverted
        self.amount = Self.clamp(amount, 0...1, default: 1); self.components = components; self.adjustments = adjustments
    }

    var isIdentity: Bool { !isEnabled || amount == 0 || !components.contains(where: \.isUsable) || adjustments.isIdentity }
    var hasVisibleLook: Bool { isEnabled && amount > 0 && components.contains(where: \.isUsable) && !adjustments.isIdentity }

    private enum CodingKeys: String, CodingKey { case id, name, isEnabled, isInverted, amount, components, adjustments }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID(),
            name: try c.decodeIfPresent(String.self, forKey: .name) ?? "Local Adjustment",
            isEnabled: try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true,
            isInverted: try c.decodeIfPresent(Bool.self, forKey: .isInverted) ?? false,
            amount: try c.decodeIfPresent(Double.self, forKey: .amount) ?? 1,
            components: try c.decodeIfPresent([MaskComponent].self, forKey: .components) ?? [],
            adjustments: try c.decodeIfPresent(LocalAdjustments.self, forKey: .adjustments) ?? .neutral
        )
    }
    private static func clamp(_ value: Double, _ range: ClosedRange<Double>, default fallback: Double) -> Double {
        guard value.isFinite else { return fallback }
        return min(max(value, range.lowerBound), range.upperBound)
    }
}

/// Pure alpha composition used by preview and export renderers.
enum MaskComposition {
    static func inverted(_ value: Double) -> Double {
        1 - min(max(value.isFinite ? value : 0, 0), 1)
    }

    static func combine(_ current: Double, _ next: Double, mode: MaskCombineMode) -> Double {
        let a = min(max(current.isFinite ? current : 0, 0), 1)
        let b = min(max(next.isFinite ? next : 0, 0), 1)
        switch mode {
        case .replace: return b
        case .add: return max(a, b)
        case .subtract: return a * (1 - b)
        case .intersect: return min(a, b)
        }
    }
}

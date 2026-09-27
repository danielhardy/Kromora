import Foundation

enum ToneCurveChannel: String, CaseIterable, Codable, Sendable, Identifiable {
    case master = "Master"
    case red = "Red"
    case green = "Green"
    case blue = "Blue"
    var id: String { rawValue }
}

/// A normalized point in the master RGB tone curve.
///
/// The curve editor can replace points without knowing about Core Image; this value is the
/// persistence contract consumed by the renderer. Inputs and outputs are normalized to 0...1 so the
/// same edit is independent of preview and export resolution.
struct LightCurvePoint: Codable, Equatable, Sendable {
    let input: Double
    let output: Double

    init(input: Double, output: Double) {
        self.input = input.clamped(to: 0...1, default: 0)
        self.output = output.clamped(to: 0...1, default: 0)
    }

    private enum CodingKeys: String, CodingKey { case input, output }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            input: try container.decodeIfPresent(Double.self, forKey: .input) ?? 0,
            output: try container.decodeIfPresent(Double.self, forKey: .output) ?? 0
        )
    }
}

/// The versioned, master RGB tone curve value used by `LightAdjustments`.
///
/// Points are sorted by input, duplicate inputs use the last point, and at least two controls are
/// always present. Version 1 adds fixed controls at inputs 0 and 1; version 2 persists the first
/// and last controls as movable endpoints. This gives interpolation a well-defined domain.
struct LightToneCurve: Codable, Equatable, Sendable {
    // Version 1 implicitly fixed endpoint inputs at 0 and 1. Version 2 stores their positions
    // explicitly so existing documents keep their original transfer function.
    static let currentVersion = 2
    static let identity = LightToneCurve(points: [
        LightCurvePoint(input: 0, output: 0),
        LightCurvePoint(input: 1, output: 1),
    ])

    private(set) var version: Int
    var points: [LightCurvePoint] {
        didSet { points = Self.normalized(points, fixedEndpoints: version == 1) }
    }

    init(
        version: Int = Self.currentVersion,
        points: [LightCurvePoint] = Self.identity.points,
        preserveEndpointPositions: Bool = false
    ) {
        self.version = min(max(version, 1), Self.currentVersion)
        self.points = Self.normalized(
            points, fixedEndpoints: self.version == 1 || !preserveEndpointPositions
        )
    }

    var isIdentity: Bool { self == Self.identity }

    /// True when the control points describe a non-decreasing transfer function.
    ///
    /// The value model preserves non-monotonic curves so a future editor can represent the full
    /// control-point space. This property lets callers validate or constrain that choice explicitly.
    var isMonotonic: Bool {
        zip(points, points.dropFirst()).allSatisfy { $0.output <= $1.output }
    }

    /// Interpolate the curve at a normalized input.
    ///
    /// This is a piecewise cubic Hermite interpolation with PCHIP-style slopes. It is C1 smooth at
    /// interior control points, preserves every control-point value, and does not overshoot between
    /// monotonic control points. Keeping the interpolation here is important: the graph and the
    /// renderer both sample this value function, so they cannot drift into showing and exporting
    /// different transfer functions. Inputs outside the normalized domain are clamped, and a
    /// non-finite input is treated as zero so callers always receive a finite result.
    func value(at input: Double) -> Double {
        let x = input.isFinite ? min(max(input, 0), 1) : 0
        guard let upperIndex = points.firstIndex(where: { $0.input >= x }) else {
            return points.last?.output ?? 1
        }
        guard upperIndex > 0 else { return points[upperIndex].output }

        let lower = points[upperIndex - 1]
        let upper = points[upperIndex]
        let span = upper.input - lower.input
        guard span > 0 else { return upper.output }
        if x == upper.input { return upper.output }

        let fraction = (x - lower.input) / span
        let leftSlope = Self.slope(at: upperIndex - 1, points: points)
        let rightSlope = Self.slope(at: upperIndex, points: points)
        let t = fraction
        let t2 = t * t
        let t3 = t2 * t
        let h00 = 2 * t3 - 3 * t2 + 1
        let h10 = t3 - 2 * t2 + t
        let h01 = -2 * t3 + 3 * t2
        let h11 = t3 - t2
        let interpolated = h00 * lower.output + h10 * span * leftSlope
            + h01 * upper.output + h11 * span * rightSlope

        // PCHIP's slope limiter guarantees this mathematically. The final clamp also protects
        // against a tiny floating-point excursion, which matters when a sampled texture is used
        // to evaluate a monotonic curve on the GPU.
        return min(max(interpolated, min(lower.output, upper.output)),
                   max(lower.output, upper.output))
    }

    private static func slope(at index: Int, points: [LightCurvePoint]) -> Double {
        guard points.count > 1 else { return 0 }
        if index == 0 {
            let firstSpan = points[1].input - points[0].input
            let secondSpan = points.count > 2 ? points[2].input - points[1].input : firstSpan
            let firstDelta = (points[1].output - points[0].output) / firstSpan
            guard points.count > 2 else { return firstDelta }
            let secondDelta = (points[2].output - points[1].output) / secondSpan
            return endpointSlope(firstSpan, secondSpan, firstDelta, secondDelta)
        }
        if index == points.count - 1 {
            let lastSpan = points[index].input - points[index - 1].input
            let lastDelta = (points[index].output - points[index - 1].output) / lastSpan
            guard points.count > 2 else { return lastDelta }
            let previousSpan = points[index - 1].input - points[index - 2].input
            let previousDelta = (points[index - 1].output - points[index - 2].output) / previousSpan
            return endpointSlope(lastSpan, previousSpan, lastDelta, previousDelta)
        }

        let previousSpan = points[index].input - points[index - 1].input
        let nextSpan = points[index + 1].input - points[index].input
        let previousDelta = (points[index].output - points[index - 1].output) / previousSpan
        let nextDelta = (points[index + 1].output - points[index].output) / nextSpan
        guard previousDelta != 0, nextDelta != 0,
              (previousDelta < 0) == (nextDelta < 0) else { return 0 }

        let weightPrevious = 2 * nextSpan + previousSpan
        let weightNext = nextSpan + 2 * previousSpan
        return (weightPrevious + weightNext) /
            (weightPrevious / previousDelta + weightNext / nextDelta)
    }

    private static func endpointSlope(
        _ endpointSpan: Double,
        _ adjacentSpan: Double,
        _ endpointDelta: Double,
        _ adjacentDelta: Double
    ) -> Double {
        let slope = ((2 * endpointSpan + adjacentSpan) * endpointDelta
            - endpointSpan * adjacentDelta) / (endpointSpan + adjacentSpan)
        guard slope != 0 else { return 0 }
        guard (slope < 0) == (endpointDelta < 0) else { return 0 }
        if (endpointDelta < 0) != (adjacentDelta < 0), abs(slope) > 3 * abs(endpointDelta) {
            return 3 * endpointDelta
        }
        return slope
    }

    /// Return a curve with an interior point sampled from the current transfer function.
    ///
    /// This is the model operation behind clicking the drawn curve. Keeping the sampling here
    /// means the editor and any future curve surface use exactly the same interpolation rule as
    /// the renderer. Invalid and endpoint inputs are ignored because endpoints are handles, not
    /// add targets.
    func addingPoint(at input: Double) -> LightToneCurve {
        guard input.isFinite, input > 0.001, input < 0.999 else { return self }
        guard !points.contains(where: { abs($0.input - input) < 0.005 }) else { return self }
        return LightToneCurve(
            version: version,
            points: points + [LightCurvePoint(input: input, output: value(at: input))],
            preserveEndpointPositions: version >= 2
        )
    }

    /// Return the nearest interior point when its input is within the editor's hit tolerance.
    ///
    /// Keeping this lookup beside `removingPoint(at:)` gives pointer selection and removal the
    /// same normalized tolerance. The graph uses input space for the hit because a point's
    /// horizontal position is stable even when the curve between controls changes.
    func interiorPoint(nearInput input: Double, tolerance: Double = 0.03) -> LightCurvePoint? {
        guard input.isFinite, tolerance >= 0 else { return nil }
        guard let index = points.indices.dropFirst().dropLast().min(by: {
            abs(points[$0].input - input) < abs(points[$1].input - input)
        }) else { return nil }
        guard abs(points[index].input - input) <= tolerance else { return nil }
        return points[index]
    }

    /// Return the nearest point, including endpoints, within the editor's hit tolerance.
    ///
    /// This is the counterpart to `interiorPoint(nearInput:)` used to start a drag on an existing
    /// handle. Endpoints must stay eligible here even though `interiorPoint` deliberately excludes
    /// them for removal, or a press on an endpoint handle would fall through to click-to-add and
    /// insert a spurious neighboring point instead of moving the endpoint.
    func nearestPoint(toInput input: Double, tolerance: Double = 0.03) -> LightCurvePoint? {
        guard input.isFinite, tolerance >= 0, !points.isEmpty else { return nil }
        let index = points.indices.min(by: {
            abs(points[$0].input - input) < abs(points[$1].input - input)
        })!
        guard abs(points[index].input - input) <= tolerance else { return nil }
        return points[index]
    }

    /// Return a curve with the interior point nearest to `input` removed.
    ///
    /// Endpoints are deliberately never candidates. A small hit tolerance makes this useful for
    /// pointer gestures while preserving the invariant even if a caller supplies 0 or 1.
    func removingPoint(at input: Double, tolerance: Double = 0.03) -> LightToneCurve {
        guard let point = interiorPoint(nearInput: input, tolerance: tolerance),
              let index = points.firstIndex(of: point) else { return self }
        var remaining = points
        remaining.remove(at: index)
        return LightToneCurve(
            version: version, points: remaining, preserveEndpointPositions: version >= 2
        )
    }

    private static func normalized(
        _ input: [LightCurvePoint], fixedEndpoints: Bool = false
    ) -> [LightCurvePoint] {
        // Dictionary assignment gives duplicate inputs an explicit last-write-wins rule before
        // sorting; relying on sort stability would make a hand-edited document non-deterministic.
        var unique: [Double: LightCurvePoint] = [:]
        for point in input { unique[point.input] = point }
        let sorted = unique.values.sorted { $0.input < $1.input }
        var result: [LightCurvePoint] = []
        for point in sorted {
            if let last = result.last, last.input == point.input {
                result[result.count - 1] = point
            } else {
                result.append(point)
            }
        }

        if fixedEndpoints {
            if result.first?.input != 0 {
                result.insert(LightCurvePoint(input: 0, output: 0), at: 0)
            }
            if result.last?.input != 1 {
                result.append(LightCurvePoint(input: 1, output: 1))
            }
        } else if result.count < 2 {
            // Keep malformed and empty v2 documents evaluable.
            return Self.identity.points
        }
        return result.isEmpty ? Self.identity.points : result
    }

    private enum CodingKeys: String, CodingKey { case version, points }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Curves written before schema versioning were normalized to fixed 0/1 endpoints.
        let version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        guard version <= Self.currentVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .version,
                in: container,
                debugDescription: "Tone curve was saved by a newer version of Kromora (schema \(version))."
            )
        }
        self.init(
            version: version,
            points: try container.decodeIfPresent([LightCurvePoint].self, forKey: .points) ?? Self.identity.points,
            preserveEndpointPositions: version >= 2
        )
    }
}

/// A regional tone curve with independently adjustable tonal bands and control-point positions.
struct ParametricToneCurve: Codable, Equatable, Sendable {
    static let neutral = ParametricToneCurve()
    static let amountRange = -100.0...100.0
    static let splitRange = 0.0...1.0

    var highlights: Double { didSet { highlights = highlights.clamped(to: Self.amountRange, default: 0) } }
    var lights: Double { didSet { lights = lights.clamped(to: Self.amountRange, default: 0) } }
    var darks: Double { didSet { darks = darks.clamped(to: Self.amountRange, default: 0) } }
    var shadows: Double { didSet { shadows = shadows.clamped(to: Self.amountRange, default: 0) } }
    var shadowSplit: Double
    var darkSplit: Double
    var lightSplit: Double
    var highlightSplit: Double

    init(highlights: Double = 0, lights: Double = 0, darks: Double = 0, shadows: Double = 0,
         shadowSplit: Double = 0.16, darkSplit: Double = 0.38,
         lightSplit: Double = 0.62, highlightSplit: Double = 0.84) {
        self.highlights = highlights.clamped(to: Self.amountRange, default: 0)
        self.lights = lights.clamped(to: Self.amountRange, default: 0)
        self.darks = darks.clamped(to: Self.amountRange, default: 0)
        self.shadows = shadows.clamped(to: Self.amountRange, default: 0)
        self.shadowSplit = shadowSplit.clamped(to: 0.02...0.92, default: 0.16)
        self.darkSplit = darkSplit.clamped(to: (self.shadowSplit + 0.02)...0.94, default: 0.38)
        self.lightSplit = lightSplit.clamped(to: (self.darkSplit + 0.02)...0.96, default: 0.62)
        self.highlightSplit = highlightSplit.clamped(to: (self.lightSplit + 0.02)...0.98, default: 0.84)
    }

    var isIdentity: Bool { highlights == 0 && lights == 0 && darks == 0 && shadows == 0 }

    func value(at input: Double) -> Double {
        let x = input.clamped(to: 0...1, default: 0)
        let anchors: [(Double, Double)] = [
            (0, 0), (shadowSplit, shadows), (darkSplit, darks),
            (lightSplit, lights), (highlightSplit, highlights), (1, 0)
        ]
        guard let upper = anchors.firstIndex(where: { $0.0 >= x }) else { return x }
        guard upper > 0 else { return x + anchors[upper].1 / 100 * 0.15 }
        let lowerAnchor = anchors[upper - 1]
        let upperAnchor = anchors[upper]
        let fraction = (x - lowerAnchor.0) / max(upperAnchor.0 - lowerAnchor.0, 0.001)
        let amount = lowerAnchor.1 + (upperAnchor.1 - lowerAnchor.1) * fraction
        return (x + amount / 100 * 0.15).clamped(to: 0...1, default: x)
    }

    private enum CodingKeys: String, CodingKey {
        case highlights, lights, darks, shadows, shadowSplit, darkSplit, lightSplit, highlightSplit
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(highlights: try c.decodeIfPresent(Double.self, forKey: .highlights) ?? 0,
                  lights: try c.decodeIfPresent(Double.self, forKey: .lights) ?? 0,
                  darks: try c.decodeIfPresent(Double.self, forKey: .darks) ?? 0,
                  shadows: try c.decodeIfPresent(Double.self, forKey: .shadows) ?? 0,
                  shadowSplit: try c.decodeIfPresent(Double.self, forKey: .shadowSplit) ?? 0.16,
                  darkSplit: try c.decodeIfPresent(Double.self, forKey: .darkSplit) ?? 0.38,
                  lightSplit: try c.decodeIfPresent(Double.self, forKey: .lightSplit) ?? 0.62,
                  highlightSplit: try c.decodeIfPresent(Double.self, forKey: .highlightSplit) ?? 0.84)
    }
}

/// Photographer-facing global Light controls.
///
/// These values are intentionally independent of Core Image parameter units. Exposure is in EV;
/// the remaining sliders use the familiar -100...100 photographic scale. The renderer maps these
/// controls to dedicated GPU-backed stages.
struct LightAdjustments: Codable, Equatable, Sendable {
    static let neutral = LightAdjustments()

    static let exposureRange = -5.0...5.0
    static let contrastRange = -100.0...100.0
    static let highlightsRange = -100.0...100.0
    static let shadowsRange = -100.0...100.0
    static let whitesRange = -100.0...100.0
    static let blacksRange = -100.0...100.0

    var exposure: Double {
        didSet { exposure = exposure.clamped(to: Self.exposureRange, default: 0) }
    }
    var contrast: Double {
        didSet { contrast = contrast.clamped(to: Self.contrastRange, default: 0) }
    }
    var highlights: Double {
        didSet { highlights = highlights.clamped(to: Self.highlightsRange, default: 0) }
    }
    var shadows: Double {
        didSet { shadows = shadows.clamped(to: Self.shadowsRange, default: 0) }
    }
    var whites: Double {
        didSet { whites = whites.clamped(to: Self.whitesRange, default: 0) }
    }
    var blacks: Double {
        didSet { blacks = blacks.clamped(to: Self.blacksRange, default: 0) }
    }
    var toneCurve: LightToneCurve {
        didSet {
            toneCurve = LightToneCurve(
                version: toneCurve.version,
                points: toneCurve.points,
                preserveEndpointPositions: toneCurve.version >= 2
            )
        }
    }
    var redToneCurve: LightToneCurve
    var greenToneCurve: LightToneCurve
    var blueToneCurve: LightToneCurve
    var parametricCurve: ParametricToneCurve

    func toneCurve(for channel: ToneCurveChannel) -> LightToneCurve {
        switch channel {
        case .master: toneCurve
        case .red: redToneCurve
        case .green: greenToneCurve
        case .blue: blueToneCurve
        }
    }

    mutating func setToneCurve(_ curve: LightToneCurve, for channel: ToneCurveChannel) {
        switch channel {
        case .master: toneCurve = curve
        case .red: redToneCurve = curve
        case .green: greenToneCurve = curve
        case .blue: blueToneCurve = curve
        }
    }

    init(
        exposure: Double = 0,
        contrast: Double = 0,
        highlights: Double = 0,
        shadows: Double = 0,
        whites: Double = 0,
        blacks: Double = 0,
        toneCurve: LightToneCurve = .identity,
        redToneCurve: LightToneCurve = .identity,
        greenToneCurve: LightToneCurve = .identity,
        blueToneCurve: LightToneCurve = .identity,
        parametricCurve: ParametricToneCurve = .neutral
    ) {
        self.exposure = exposure.clamped(to: Self.exposureRange, default: 0)
        self.contrast = contrast.clamped(to: Self.contrastRange, default: 0)
        self.highlights = highlights.clamped(to: Self.highlightsRange, default: 0)
        self.shadows = shadows.clamped(to: Self.shadowsRange, default: 0)
        self.whites = whites.clamped(to: Self.whitesRange, default: 0)
        self.blacks = blacks.clamped(to: Self.blacksRange, default: 0)
        self.toneCurve = LightToneCurve(
            version: toneCurve.version,
            points: toneCurve.points,
            preserveEndpointPositions: toneCurve.version >= 2
        )
        self.redToneCurve = redToneCurve
        self.greenToneCurve = greenToneCurve
        self.blueToneCurve = blueToneCurve
        self.parametricCurve = parametricCurve
    }

    var isIdentity: Bool {
        exposure == 0 && contrast == 0 && highlights == 0 && shadows == 0 &&
            whites == 0 && blacks == 0 && toneCurve.isIdentity && redToneCurve.isIdentity &&
            greenToneCurve.isIdentity && blueToneCurve.isIdentity && parametricCurve.isIdentity
    }

    private enum CodingKeys: String, CodingKey {
        case exposure, contrast, highlights, shadows, whites, blacks, toneCurve
        case redToneCurve, greenToneCurve, blueToneCurve, parametricCurve
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            exposure: try container.decodeIfPresent(Double.self, forKey: .exposure) ?? 0,
            contrast: try container.decodeIfPresent(Double.self, forKey: .contrast) ?? 0,
            highlights: try container.decodeIfPresent(Double.self, forKey: .highlights) ?? 0,
            shadows: try container.decodeIfPresent(Double.self, forKey: .shadows) ?? 0,
            whites: try container.decodeIfPresent(Double.self, forKey: .whites) ?? 0,
            blacks: try container.decodeIfPresent(Double.self, forKey: .blacks) ?? 0,
            toneCurve: try container.decodeIfPresent(LightToneCurve.self, forKey: .toneCurve) ?? .identity,
            redToneCurve: try container.decodeIfPresent(LightToneCurve.self, forKey: .redToneCurve) ?? .identity,
            greenToneCurve: try container.decodeIfPresent(LightToneCurve.self, forKey: .greenToneCurve) ?? .identity,
            blueToneCurve: try container.decodeIfPresent(LightToneCurve.self, forKey: .blueToneCurve) ?? .identity,
            parametricCurve: try container.decodeIfPresent(ParametricToneCurve.self, forKey: .parametricCurve) ?? .neutral
        )
    }
}

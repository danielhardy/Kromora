import Foundation

/// Metadata facet selections for the advanced Library filter sidebar.
///
/// Values within a facet combine with OR; facets combine with AND, and with the basic
/// flag/rating filter and search text. Selections are stored as the display values the index
/// summary already carries, so no package-format change is involved.
struct LibraryFacetSelection: Codable, Equatable, Hashable, Sendable {
    var cameras: Set<String> = []
    var lenses: Set<String> = []
    var locations: Set<String> = []
    var focalLength: LibraryRangeSelection?
    var iso: LibraryRangeSelection?
    var aperture: LibraryRangeSelection?

    static let none = LibraryFacetSelection()

    var isActive: Bool { activeCount > 0 }
    var activeCount: Int {
        cameras.count + lenses.count + locations.count
            + LibraryRangeFacet.allCases.count(where: { range(for: $0) != nil })
    }

    func range(for facet: LibraryRangeFacet) -> LibraryRangeSelection? {
        switch facet {
        case .focalLength: focalLength
        case .iso: iso
        case .aperture: aperture
        }
    }

    mutating func setRange(_ range: LibraryRangeSelection?, for facet: LibraryRangeFacet) {
        switch facet {
        case .focalLength: focalLength = range
        case .iso: iso = range
        case .aperture: aperture = range
        }
    }

    func matches(
        _ summary: PortablePackageAssetSummary,
        ignoring ignored: LibraryFacet? = nil,
        ignoringRange ignoredRange: LibraryRangeFacet? = nil
    ) -> Bool {
        for facet in LibraryRangeFacet.allCases where facet != ignoredRange {
            // Assets without a value (or not yet read) never satisfy an active range.
            if let range = range(for: facet),
               !(facet.value(in: summary).map(range.contains) ?? false) {
                return false
            }
        }
        return matchesValueFacets(summary, ignoring: ignored)
    }

    private func matchesValueFacets(
        _ summary: PortablePackageAssetSummary, ignoring ignored: LibraryFacet?
    ) -> Bool {
        if ignored != .camera, !cameras.isEmpty {
            guard cameras.contains(LibraryFacet.camera.value(in: summary)) else { return false }
        }
        if ignored != .lens, !lenses.isEmpty {
            guard lenses.contains(LibraryFacet.lens.value(in: summary)) else { return false }
        }
        if ignored != .location, !locations.isEmpty {
            guard locations.contains(LibraryFacet.location.value(in: summary)) else { return false }
        }
        return true
    }

    func selected(in facet: LibraryFacet) -> Set<String> {
        switch facet {
        case .camera: cameras
        case .lens: lenses
        case .location: locations
        }
    }

    mutating func toggle(_ value: String, in facet: LibraryFacet) {
        switch facet {
        case .camera: cameras.formSymmetricDifference([value])
        case .lens: lenses.formSymmetricDifference([value])
        case .location: locations.formSymmetricDifference([value])
        }
    }

    init() {}

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        cameras = try container.decodeIfPresent(Set<String>.self, forKey: .cameras) ?? []
        lenses = try container.decodeIfPresent(Set<String>.self, forKey: .lenses) ?? []
        locations = try container.decodeIfPresent(Set<String>.self, forKey: .locations) ?? []
        focalLength = try container.decodeIfPresent(LibraryRangeSelection.self, forKey: .focalLength)
        iso = try container.decodeIfPresent(LibraryRangeSelection.self, forKey: .iso)
        aperture = try container.decodeIfPresent(LibraryRangeSelection.self, forKey: .aperture)
    }
}

/// An inclusive numeric range selected for a range facet.
struct LibraryRangeSelection: Codable, Equatable, Hashable, Sendable {
    var lower: Double
    var upper: Double

    init(lower: Double, upper: Double) {
        self.lower = min(lower, upper)
        self.upper = max(lower, upper)
    }

    func contains(_ value: Double) -> Bool { value >= lower && value <= upper }
}

/// Facets filtered by a numeric range over capture settings.
enum LibraryRangeFacet: String, CaseIterable, Codable, Sendable, Identifiable {
    case focalLength
    case iso
    case aperture

    var id: String { rawValue }

    var title: String {
        switch self {
        case .focalLength: "Focal length"
        case .iso: "ISO"
        case .aperture: "Aperture"
        }
    }

    func value(in summary: PortablePackageAssetSummary) -> Double? {
        guard let settings = summary.captureSettings else { return nil }
        switch self {
        case .focalLength: return settings.focalLength
        case .iso: return settings.iso.map(Double.init)
        case .aperture: return settings.aperture
        }
    }

    private func number(_ value: Double) -> String {
        value.rounded() == value
            ? String(Int(value)) : value.formatted(.number.precision(.fractionLength(1)))
    }

    /// Display text for one value, e.g. "35 mm", "ISO 400", "ƒ/2.8".
    func format(_ value: Double) -> String { decorate(number(value)) }

    /// Display text for a range, e.g. "35–200 mm", "ISO 100–1600", "ƒ/1.8–2.8".
    func describe(_ range: LibraryRangeSelection) -> String {
        range.lower == range.upper
            ? format(range.lower) : decorate("\(number(range.lower))–\(number(range.upper))")
    }

    private func decorate(_ text: String) -> String {
        switch self {
        case .focalLength: "\(text) mm"
        case .iso: "ISO \(text)"
        case .aperture: "ƒ/\(text)"
        }
    }
}

enum LibraryFacet: String, CaseIterable, Codable, Sendable, Identifiable {
    case camera
    case lens
    case location

    var id: String { rawValue }

    var title: String {
        switch self {
        case .camera: "Camera"
        case .lens: "Lens"
        case .location: "Location"
        }
    }

    /// Value shown for assets that carry no value for this facet.
    static let missingValue = "Unknown"

    /// Value for assets whose original was read and carries no GPS. Assets not yet read stay
    /// under `missingValue`.
    static let noLocationValue = "No location"

    func value(in summary: PortablePackageAssetSummary) -> String {
        let raw: String?
        switch self {
        case .camera:
            raw = [summary.cameraMake, summary.cameraModel].compactMap { $0 }
                .joined(separator: " ")
        case .lens:
            raw = summary.lens
        case .location:
            guard let cell = summary.coarseLocation else { return Self.missingValue }
            raw = cell.isEmpty ? Self.noLocationValue : cell
        }
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed?.isEmpty == false ? trimmed : nil) ?? Self.missingValue
    }
}

struct LibraryFacetValueCount: Equatable, Hashable, Sendable, Identifiable {
    let value: String
    let count: Int
    var id: String { value }
}

/// Per-facet value counts. Each facet's counts reflect every other active filter but not its own
/// selection, so the user can add alternatives within a facet.
struct LibraryFacetCounts: Equatable, Sendable {
    var values: [LibraryFacet: [LibraryFacetValueCount]] = [:]

    /// Observed value bounds per range facet, over entries matching every other active filter
    /// (including the other range facets, but not the facet's own range).
    var ranges: [LibraryRangeFacet: ClosedRange<Double>] = [:]
    /// Count of entries whose original has not yet been read for capture settings.
    var unreadCaptureSettingsCount = 0

    func counts(for facet: LibraryFacet) -> [LibraryFacetValueCount] { values[facet] ?? [] }
    func bounds(for facet: LibraryRangeFacet) -> ClosedRange<Double>? { ranges[facet] }
}

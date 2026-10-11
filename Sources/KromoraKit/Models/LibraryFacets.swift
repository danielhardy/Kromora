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
    var captureDate: LibraryRangeSelection?

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
        case .captureDate: captureDate
        }
    }

    mutating func setRange(_ range: LibraryRangeSelection?, for facet: LibraryRangeFacet) {
        switch facet {
        case .focalLength: focalLength = range
        case .iso: iso = range
        case .aperture: aperture = range
        case .captureDate: captureDate = range
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
        captureDate = try container.decodeIfPresent(LibraryRangeSelection.self, forKey: .captureDate)
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
    /// Capture day as days since 1970-01-01 (camera-local calendar day).
    case captureDate

    var id: String { rawValue }

    var title: String {
        switch self {
        case .focalLength: "Focal length"
        case .iso: "ISO"
        case .aperture: "Aperture"
        case .captureDate: "Capture date"
        }
    }

    func value(in summary: PortablePackageAssetSummary) -> Double? {
        if self == .captureDate { return summary.captureDateISO.flatMap(Self.dayNumber) }
        guard let settings = summary.captureSettings else { return nil }
        switch self {
        case .focalLength: return settings.focalLength
        case .iso: return settings.iso.map(Double.init)
        case .aperture: return settings.aperture
        case .captureDate: return nil
        }
    }

    /// Days since 1970-01-01 for the "yyyy-MM-dd…" prefix of a sortable capture time.
    static func dayNumber(_ iso: String) -> Double? {
        let characters = Array(iso.prefix(10))
        guard characters.count == 10, characters[4] == "-", characters[7] == "-",
              let year = Int(String(characters[0..<4])),
              let month = Int(String(characters[5..<7])),
              let day = Int(String(characters[8..<10])),
              (1...9999).contains(year), (1...12).contains(month),
              (1...ImageMetadata.daysInMonth(month, year: year)).contains(day)
        else { return nil }
        // Civil-from-days inverse (proleptic Gregorian), avoiding Calendar in the per-entry loop.
        let civilYear = month <= 2 ? year - 1 : year
        let era = (civilYear >= 0 ? civilYear : civilYear - 399) / 400
        let yearOfEra = civilYear - era * 400
        let shiftedMonth = month + (month > 2 ? -3 : 9)
        let dayOfYear = (153 * shiftedMonth + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return Double(era * 146_097 + dayOfEra - 719_468)
    }

    /// The inverse of `dayNumber`, as a date at noon UTC (stable across zones for display).
    static func date(forDayNumber day: Double) -> Date {
        Date(timeIntervalSince1970: day * 86_400 + 43_200)
    }

    private func number(_ value: Double) -> String {
        value.rounded() == value
            ? String(Int(value)) : value.formatted(.number.precision(.fractionLength(1)))
    }

    /// Display text for one value, e.g. "35 mm", "ISO 400", "ƒ/2.8".
    func format(_ value: Double) -> String {
        self == .captureDate ? Self.dayText(value) : decorate(number(value))
    }

    private static func dayText(_ day: Double) -> String {
        Self.date(forDayNumber: day).formatted(
            Date.FormatStyle(locale: .autoupdatingCurrent, timeZone: .gmt)
                .year().month(.abbreviated).day()
        )
    }

    /// Display text for a range, e.g. "35–200 mm", "ISO 100–1600", "ƒ/1.8–2.8".
    func describe(_ range: LibraryRangeSelection) -> String {
        if self == .captureDate {
            return range.lower == range.upper
                ? format(range.lower) : "\(format(range.lower))–\(format(range.upper))"
        }
        return range.lower == range.upper
            ? format(range.lower) : decorate("\(number(range.lower))–\(number(range.upper))")
    }

    private func decorate(_ text: String) -> String {
        switch self {
        case .focalLength: "\(text) mm"
        case .iso: "ISO \(text)"
        case .aperture: "ƒ/\(text)"
        case .captureDate: text
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

extension Calendar {
    /// Gregorian calendar fixed to UTC, used for camera-local capture days stored as day numbers.
    static let utcGregorian: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }()
}

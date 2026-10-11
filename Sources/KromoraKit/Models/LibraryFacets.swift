import Foundation

/// Metadata facet selections for the advanced Library filter sidebar.
///
/// Values within a facet combine with OR; facets combine with AND, and with the basic
/// flag/rating filter and search text. Selections are stored as the display values the index
/// summary already carries, so no package-format change is involved.
struct LibraryFacetSelection: Codable, Equatable, Hashable, Sendable {
    var cameras: Set<String> = []
    var lenses: Set<String> = []

    static let none = LibraryFacetSelection()

    var isActive: Bool { !cameras.isEmpty || !lenses.isEmpty }
    var activeCount: Int { cameras.count + lenses.count }

    func matches(_ summary: PortablePackageAssetSummary, ignoring ignored: LibraryFacet? = nil)
        -> Bool
    {
        if ignored != .camera, !cameras.isEmpty {
            guard cameras.contains(LibraryFacet.camera.value(in: summary)) else { return false }
        }
        if ignored != .lens, !lenses.isEmpty {
            guard lenses.contains(LibraryFacet.lens.value(in: summary)) else { return false }
        }
        return true
    }

    func selected(in facet: LibraryFacet) -> Set<String> {
        switch facet {
        case .camera: cameras
        case .lens: lenses
        }
    }

    mutating func toggle(_ value: String, in facet: LibraryFacet) {
        switch facet {
        case .camera: cameras.formSymmetricDifference([value])
        case .lens: lenses.formSymmetricDifference([value])
        }
    }

    init() {}

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        cameras = try container.decodeIfPresent(Set<String>.self, forKey: .cameras) ?? []
        lenses = try container.decodeIfPresent(Set<String>.self, forKey: .lenses) ?? []
    }
}

enum LibraryFacet: String, CaseIterable, Codable, Sendable, Identifiable {
    case camera
    case lens

    var id: String { rawValue }

    var title: String {
        switch self {
        case .camera: "Camera"
        case .lens: "Lens"
        }
    }

    /// Value shown for assets that carry no value for this facet.
    static let missingValue = "Unknown"

    func value(in summary: PortablePackageAssetSummary) -> String {
        let raw: String?
        switch self {
        case .camera:
            raw = [summary.cameraMake, summary.cameraModel].compactMap { $0 }
                .joined(separator: " ")
        case .lens:
            raw = summary.lens
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

    func counts(for facet: LibraryFacet) -> [LibraryFacetValueCount] { values[facet] ?? [] }
}

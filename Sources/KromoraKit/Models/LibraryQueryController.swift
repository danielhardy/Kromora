import Foundation

/// The fields that can be ordered by the library index.  These fields intentionally mirror the
/// denormalised membership summary rather than the asset record or an edit sidecar.
enum LibraryQuerySortKey: String, Codable, CaseIterable, Sendable {
    case displayName
    case captureDate
    case rating
    case flag
    case label
    case camera
    case lens
    case assetRevision
    case assetID
}

enum LibraryQuerySortDirection: String, Codable, Sendable {
    case ascending
    case descending

    var reversed: Self {
        self == .ascending ? .descending : .ascending
    }
}

struct LibraryQuerySort: Codable, Equatable, Hashable, Sendable {
    var key: LibraryQuerySortKey
    var direction: LibraryQuerySortDirection

    init(
        key: LibraryQuerySortKey = .displayName,
        direction: LibraryQuerySortDirection = .ascending
    ) {
        self.key = key
        self.direction = direction
    }

    static let displayNameAscending = Self()
    static let captureDateDescending = Self(key: .captureDate, direction: .descending)
    static let ratingDescending = Self(key: .rating, direction: .descending)
}

/// One live membership value copied into the local query projection.  It is deliberately not an
/// asset record: the projection is safe to rebuild or delete and contains no original, edit, or
/// thumbnail bytes.
struct LibraryIndexEntry: Codable, Equatable, Hashable, Sendable, Identifiable {
    let assetID: PortablePhotoAssetID
    let recordPath: String
    let addedRevision: UInt64
    let deletedRevision: UInt64?
    let summary: PortablePackageAssetSummary

    var id: PortablePhotoAssetID { assetID }

    init(
        assetID: PortablePhotoAssetID,
        recordPath: String,
        addedRevision: UInt64 = 0,
        deletedRevision: UInt64? = nil,
        summary: PortablePackageAssetSummary
    ) {
        self.assetID = assetID
        self.recordPath = recordPath
        self.addedRevision = addedRevision
        self.deletedRevision = deletedRevision
        self.summary = summary
    }

    init(from membership: PortablePackageMembershipEntry) {
        assetID = membership.assetID
        recordPath = membership.recordPath
        addedRevision = membership.addedRevision
        deletedRevision = membership.deletedRevision
        summary = membership.summary
    }
}

/// A local, rebuildable projection of package membership shards.
///
/// The package remains canonical.  This value contains only the fields needed to browse a
/// library, so a query never has to open `Assets/**/asset.json`, an XMP packet, an original, or a
/// thumbnail.  The projection is kept independent from package storage so the future index
/// rebuild/maintenance ticket can choose its on-disk location without changing query semantics.
struct LibraryIndexProjection: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let libraryID: UUID
    let entries: [LibraryIndexEntry]

    init(libraryID: UUID, entries: [LibraryIndexEntry]) throws {
        schemaVersion = Self.currentSchemaVersion
        self.libraryID = libraryID
        self.entries = try Self.validated(entries)
    }

    /// Rebuild the projection from the package's membership summaries only.
    init(package: PortableLibraryPackage) throws {
        var entries: [LibraryIndexEntry] = []
        for shard in PortableLibraryPackage.allShards {
            let membership = try package.readMembershipShard(shard)
            entries.append(contentsOf: membership.entries
                .filter { !$0.isTombstone }
                .map(LibraryIndexEntry.init(from:)))
        }
        try self.init(libraryID: package.manifest.libraryID, entries: entries)
    }

    var count: Int { entries.count }

    func entry(for assetID: PortablePhotoAssetID) -> LibraryIndexEntry? {
        entries.first { $0.assetID == assetID }
    }

    /// Store/load are intentionally small conveniences for a future application-support index.
    /// Losing this file is always recoverable by calling `init(package:)`.
    func write(to url: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
    }

    static func load(from url: URL) throws -> Self {
        let decoder = JSONDecoder()
        let value = try decoder.decode(Self.self, from: Data(contentsOf: url))
        guard value.schemaVersion == Self.currentSchemaVersion else {
            throw LibraryQueryError.invalidIndex("unsupported schema version \(value.schemaVersion)")
        }
        return try Self(libraryID: value.libraryID, entries: value.entries)
    }

    private static func validated(_ entries: [LibraryIndexEntry]) throws -> [LibraryIndexEntry] {
        var ids = Set<PortablePhotoAssetID>()
        for entry in entries {
            guard ids.insert(entry.assetID).inserted else {
                throw LibraryQueryError.duplicateAsset(entry.assetID.raw)
            }
            let expectedPath = "Assets/\(PortableLibraryPackage.shard(for: entry.assetID))/\(entry.assetID.raw)/asset.json"
            guard entry.recordPath == expectedPath else {
                throw LibraryQueryError.invalidIndex("record path does not match asset \(entry.assetID)")
            }
        }
        return entries.sorted { $0.assetID.raw < $1.assetID.raw }
    }
}

enum LibraryQueryError: Error, Equatable, CustomStringConvertible {
    case invalidIndex(String)
    case duplicateAsset(String)

    var description: String {
        switch self {
        case .invalidIndex(let message): "Invalid library index: \(message)"
        case .duplicateAsset(let assetID): "Library index contains duplicate asset \(assetID)"
        }
    }
}

struct LibraryQuery: Codable, Equatable, Sendable {
    var filter: LibraryFilter
    var searchText: String?
    var sort: LibraryQuerySort

    init(
        filter: LibraryFilter = .all,
        searchText: String? = nil,
        sort: LibraryQuerySort = .init()
    ) {
        self.filter = filter
        self.searchText = searchText?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.sort = sort
    }

    static let all = Self()
}

/// A value summary returned by a paged query.  `isSelected` is computed from UUID state at query
/// time, so the same asset remains selected when filtering or sorting changes its page position.
struct LibraryQueryItem: Codable, Equatable, Sendable, Identifiable {
    let assetID: PortablePhotoAssetID
    let recordPath: String
    let summary: PortablePackageAssetSummary
    let isSelected: Bool

    var id: PortablePhotoAssetID { assetID }
    var displayName: String { summary.displayName }
    var aspectRatio: Double { summary.aspectRatio ?? 4.0 / 3.0 }
}

struct LibraryQueryPage: Codable, Equatable, Sendable {
    let pageIndex: Int
    let pageSize: Int
    let totalCount: Int
    let items: [LibraryQueryItem]

    var isEmpty: Bool { items.isEmpty }
    var hasPreviousPage: Bool { pageIndex > 0 }
    var hasNextPage: Bool { (pageIndex + 1) * pageSize < totalCount }
    var selectedIDs: Set<PortablePhotoAssetID> {
        Set(items.filter(\.isSelected).map(\.assetID))
    }
}

/// Paged, index-side library browsing with UUID-keyed selection.
///
/// `LibraryQueryController` owns no AppKit objects and never materialises `PhotoAsset`.  A caller
/// may retain it on a view model, request pages as needed, and separately resolve a selected UUID
/// through the package when an editor actually needs the full record.
struct LibraryQueryController: Sendable {
    typealias Index = LibraryIndexProjection
    typealias SortKey = LibraryQuerySortKey
    typealias SortDirection = LibraryQuerySortDirection
    typealias Sort = LibraryQuerySort
    typealias Query = LibraryQuery
    typealias Page = LibraryQueryPage
    typealias Item = LibraryQueryItem

    let index: LibraryIndexProjection
    let pageSize: Int
    private(set) var selectedAssetIDs: Set<PortablePhotoAssetID>
    private(set) var activeAssetID: PortablePhotoAssetID?

    init(
        index: LibraryIndexProjection,
        pageSize: Int = 500,
        selectedAssetIDs: Set<PortablePhotoAssetID> = [],
        activeAssetID: PortablePhotoAssetID? = nil
    ) {
        self.index = index
        self.pageSize = max(1, pageSize)
        let validIDs = Set(index.entries.map(\.assetID))
        let validSelectedIDs = selectedAssetIDs.intersection(validIDs)
        self.selectedAssetIDs = validSelectedIDs
        self.activeAssetID = activeAssetID.flatMap {
            validIDs.contains($0) && validSelectedIDs.contains($0) ? $0 : nil
        } ?? validSelectedIDs.first
    }

    init(package: PortableLibraryPackage, pageSize: Int = 500) throws {
        try self.init(index: LibraryIndexProjection(package: package), pageSize: pageSize)
    }

    init(indexURL: URL, pageSize: Int = 500) throws {
        try self.init(index: LibraryIndexProjection.load(from: indexURL), pageSize: pageSize)
    }

    var totalCount: Int { index.count }
    var selectedIDs: Set<PortablePhotoAssetID> { selectedAssetIDs }
    var activeID: PortablePhotoAssetID? { activeAssetID }

    func page(
        at pageIndex: Int,
        query: LibraryQuery = .all
    ) -> LibraryQueryPage {
        let safePageIndex = max(0, pageIndex)
        let matching = index.entries.filter { matches($0, query: query) }
        let ordered = matching.sorted { precedes($0, $1, by: query.sort) }
        let start = min(ordered.count, safePageIndex * pageSize)
        let end = min(ordered.count, start + pageSize)
        let items = ordered[start..<end].map { entry in
            LibraryQueryItem(
                assetID: entry.assetID,
                recordPath: entry.recordPath,
                summary: entry.summary,
                isSelected: selectedAssetIDs.contains(entry.assetID)
            )
        }
        return LibraryQueryPage(
            pageIndex: safePageIndex,
            pageSize: pageSize,
            totalCount: ordered.count,
            items: Array(items)
        )
    }

    func page(number: Int, query: LibraryQuery = .all) -> LibraryQueryPage {
        page(at: number, query: query)
    }

    func contains(_ assetID: PortablePhotoAssetID) -> Bool {
        index.entry(for: assetID) != nil
    }

    mutating func select(_ assetID: PortablePhotoAssetID) {
        guard contains(assetID) else { return }
        selectedAssetIDs = [assetID]
        activeAssetID = assetID
    }

    mutating func toggleSelection(_ assetID: PortablePhotoAssetID) {
        guard contains(assetID) else { return }
        if selectedAssetIDs.contains(assetID) {
            selectedAssetIDs.remove(assetID)
            activeAssetID = selectedAssetIDs.first
        } else {
            selectedAssetIDs.insert(assetID)
            activeAssetID = assetID
        }
    }

    mutating func select(_ assetID: PortablePhotoAssetID, additive: Bool) {
        additive ? toggleSelection(assetID) : select(assetID)
    }

    mutating func selectAll(query: LibraryQuery = .all) {
        let matching = index.entries
            .filter { matches($0, query: query) }
            .sorted { precedes($0, $1, by: query.sort) }
        selectedAssetIDs = Set(matching.map(\.assetID))
        activeAssetID = matching.first?.assetID
    }

    mutating func clearSelection() {
        selectedAssetIDs.removeAll()
        activeAssetID = nil
    }

    mutating func reconcileSelection() {
        let validIDs = Set(index.entries.map(\.assetID))
        selectedAssetIDs = selectedAssetIDs.intersection(validIDs)
        if let activeAssetID,
           validIDs.contains(activeAssetID),
           selectedAssetIDs.contains(activeAssetID) {
            self.activeAssetID = activeAssetID
        } else {
            self.activeAssetID = selectedAssetIDs.first
        }
    }

    private func matches(_ entry: LibraryIndexEntry, query: LibraryQuery) -> Bool {
        let summary = entry.summary
        let flag = PhotoFlag(rawValue: summary.flag ?? "none") ?? .none
        guard query.filter.matches(flag: flag, rating: summary.rating ?? 0) else { return false }
        guard let searchText = query.searchText, !searchText.isEmpty else { return true }
        let haystack = [
            summary.displayName, summary.label, summary.cameraMake, summary.cameraModel,
            summary.lens, summary.captureDate,
        ].compactMap { $0 }.joined(separator: " ").foldedForLibrarySearch
        return haystack.contains(searchText.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current))
    }

    private func precedes(
        _ lhs: LibraryIndexEntry,
        _ rhs: LibraryIndexEntry,
        by sort: LibraryQuerySort
    ) -> Bool {
        let comparison = compare(lhs, rhs, key: sort.key)
        if comparison == .orderedSame { return lhs.assetID.raw < rhs.assetID.raw }
        return sort.direction == .ascending
            ? comparison == .orderedAscending
            : comparison == .orderedDescending
    }

    private func compare(
        _ lhs: LibraryIndexEntry,
        _ rhs: LibraryIndexEntry,
        key: LibraryQuerySortKey
    ) -> ComparisonResult {
        let left = lhs.summary
        let right = rhs.summary
        switch key {
        case .rating:
            return compare(left.rating ?? 0, right.rating ?? 0)
        case .assetRevision:
            return compare(left.assetRevision, right.assetRevision)
        case .displayName:
            return compare(left.displayName, right.displayName)
        case .captureDate:
            return compareOptional(left.captureDate, right.captureDate)
        case .flag:
            return compare(left.flag ?? "none", right.flag ?? "none")
        case .label:
            return compareOptional(left.label, right.label)
        case .camera:
            return compareOptional(
                [left.cameraMake, left.cameraModel].compactMap { $0 }.joined(separator: " ").nilIfEmpty,
                [right.cameraMake, right.cameraModel].compactMap { $0 }.joined(separator: " ").nilIfEmpty
            )
        case .lens:
            return compareOptional(left.lens, right.lens)
        case .assetID:
            return compare(lhs.assetID.raw, rhs.assetID.raw)
        }
    }

    private func compare<T: Comparable>(_ lhs: T, _ rhs: T) -> ComparisonResult {
        if lhs == rhs { return .orderedSame }
        return lhs < rhs ? .orderedAscending : .orderedDescending
    }

    private func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = lhs.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let right = rhs.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let folded: ComparisonResult
        if left == right {
            folded = .orderedSame
        } else {
            folded = left < right ? .orderedAscending : .orderedDescending
        }
        return folded == .orderedSame ? compare(lhs, rhs) : folded
    }

    private func compareOptional(_ lhs: String?, _ rhs: String?) -> ComparisonResult {
        switch (lhs, rhs) {
        case (nil, nil): .orderedSame
        case (nil, _): .orderedDescending
        case (_, nil): .orderedAscending
        case let (left?, right?): compare(left, right)
        }
    }
}

private extension String {
    var foldedForLibrarySearch: String {
        folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    var nilIfEmpty: String? { isEmpty ? nil : self }
}

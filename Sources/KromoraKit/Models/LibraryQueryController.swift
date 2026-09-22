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

/// The small canonical-to-projection change set emitted by a package transaction.  Import and
/// trash operations can update the disposable index without reopening every membership shard.
struct LibraryIndexDelta: Equatable, Sendable {
    let upserts: [LibraryIndexEntry]
    let removals: [PortablePhotoAssetID]

    static let empty = Self(upserts: [], removals: [])

    init(
        upserts: [LibraryIndexEntry] = [],
        removals: [PortablePhotoAssetID] = []
    ) {
        self.upserts = upserts
        self.removals = removals
    }

    func merging(_ other: Self) -> Self {
        var upsertsByID = Dictionary(uniqueKeysWithValues: upserts.map { ($0.assetID, $0) })
        var removalsByID = Set(removals)
        for assetID in other.removals {
            upsertsByID.removeValue(forKey: assetID)
            removalsByID.insert(assetID)
        }
        for entry in other.upserts {
            removalsByID.remove(entry.assetID)
            upsertsByID[entry.assetID] = entry
        }
        return Self(upserts: Array(upsertsByID.values), removals: Array(removalsByID))
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
        try self.init(libraryID: package.manifest.libraryID, entries: Self.readEntries(from: package))
    }

    /// Applies a transaction's membership delta while retaining the projection's current
    /// contents. This deliberately does not touch the package, so callers can publish the
    /// in-memory query state immediately and coalesce the durable index write separately.
    func applying(_ delta: LibraryIndexDelta) throws -> Self {
        var entries = Dictionary(uniqueKeysWithValues: entries.map { ($0.assetID, $0) })
        for assetID in delta.removals {
            entries.removeValue(forKey: assetID)
        }
        for entry in delta.upserts {
            entries[entry.assetID] = entry
        }
        return try Self(libraryID: libraryID, entries: Array(entries.values))
    }

    /// Rebuilds the local projection from membership shards and atomically publishes it.
    ///
    /// The first progress callback is emitted once a complete page of summaries is available.
    /// That page is intentionally a usable partial projection; the final callback contains the
    /// complete projection after it has been written. No asset record, original, thumbnail, or
    /// XMP file is opened by this operation.
    static func rebuild(
        from package: PortableLibraryPackage,
        to indexURL: URL,
        pageSize: Int = 500,
        progress: (@Sendable (LibraryIndexRebuildProgress) async -> Void)? = nil
    ) async throws -> Self {
        let effectivePageSize = max(1, pageSize)
        var entries: [LibraryIndexEntry] = []
        var publishedFirstPage = false

        for (offset, shard) in PortableLibraryPackage.allShards.enumerated() {
            try Task.checkCancellation()
            let membership = try package.readMembershipShard(shard)
            entries.append(contentsOf: membership.entries
                .filter { !$0.isTombstone }
                .map(LibraryIndexEntry.init(from:)))

            guard !publishedFirstPage, entries.count >= effectivePageSize else { continue }
            let partial = try Self(libraryID: package.manifest.libraryID, entries: entries)
            let controller = LibraryQueryController(index: partial, pageSize: effectivePageSize)
            await progress?(.init(
                projection: partial,
                page: controller.page(at: 0),
                shardsRead: offset + 1,
                totalShards: PortableLibraryPackage.allShards.count,
                isComplete: false
            ))
            publishedFirstPage = true
        }

        let projection = try Self(libraryID: package.manifest.libraryID, entries: entries)
        try projection.write(to: indexURL)
        let controller = LibraryQueryController(index: projection, pageSize: effectivePageSize)
        await progress?(.init(
            projection: projection,
            page: controller.page(at: 0),
            shardsRead: PortableLibraryPackage.allShards.count,
            totalShards: PortableLibraryPackage.allShards.count,
            isComplete: true
        ))
        return projection
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

    func validated(for package: PortableLibraryPackage) throws -> Self {
        guard libraryID == package.manifest.libraryID else {
            throw LibraryQueryError.invalidIndex("library ID does not match the package")
        }
        return try Self(libraryID: libraryID, entries: entries)
    }

    private static func readEntries(from package: PortableLibraryPackage) throws -> [LibraryIndexEntry] {
        var entries: [LibraryIndexEntry] = []
        for shard in PortableLibraryPackage.allShards {
            let membership = try package.readMembershipShard(shard)
            entries.append(contentsOf: membership.entries
                .filter { !$0.isTombstone }
                .map(LibraryIndexEntry.init(from:)))
        }
        return entries
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

/// A snapshot published during a cold index rebuild. The first snapshot is deliberately allowed
/// to be partial so a caller can paint the first page while the remaining membership shards are
/// still being read.
struct LibraryIndexRebuildProgress: Sendable {
    let projection: LibraryIndexProjection
    let page: LibraryQueryPage
    let shardsRead: Int
    let totalShards: Int
    let isComplete: Bool
}

/// The source selected while opening a query session. A rebuilt session publishes its first page
/// as soon as the first page of membership summaries has been collected.
enum LibraryIndexOpenSource: Sendable, Equatable {
    case warm
    case rebuilt
}

/// The query-facing lifecycle for a package index.
///
/// A warm session reads one local index file and never touches package contents. A cold session
/// starts a shard-only rebuild, publishes its first page through `firstPage()`, and updates the
/// session to the complete projection when `waitForRebuild()` finishes. The actor keeps the
/// controller and its UUID selection state coherent while those updates arrive.
actor LibraryIndexSession {
    private var controller: LibraryQueryController
    private let indexURL: URL
    private let initialQuery: LibraryQuery
    private(set) var source: LibraryIndexOpenSource
    private var rebuildTask: Task<LibraryIndexProjection, Error>?
    private var firstPublishedPage: LibraryQueryPage?
    private var firstPageWaiters: [CheckedContinuation<LibraryQueryPage, Error>] = []
    private var rebuildError: Error?

    private init(
        controller: LibraryQueryController,
        indexURL: URL,
        query: LibraryQuery,
        source: LibraryIndexOpenSource,
        initialPage: LibraryQueryPage? = nil
    ) {
        self.controller = controller
        self.indexURL = indexURL
        self.initialQuery = query
        self.source = source
        self.firstPublishedPage = initialPage
    }

    /// Opens the local index when valid, otherwise starts an automatic shard-only rebuild.
    ///
    /// The method waits only until the first page is available on the cold path. The rebuild task
    /// remains owned by this session and can be awaited explicitly, or can continue while the UI
    /// uses `page(at:query:)`.
    static func open(
        package: PortableLibraryPackage,
        indexURL: URL,
        pageSize: Int = 500,
        query: LibraryQuery = .all
    ) async throws -> Self {
        if let loaded = try? LibraryIndexProjection.load(from: indexURL),
           let valid = try? loaded.validated(for: package) {
            let controller = LibraryQueryController(index: valid, pageSize: pageSize)
            return Self(
                controller: controller,
                indexURL: indexURL,
                query: query,
                source: .warm,
                initialPage: controller.page(at: 0, query: query)
            )
        }

        let empty = try LibraryIndexProjection(libraryID: package.manifest.libraryID, entries: [])
        let session = Self(
            controller: LibraryQueryController(index: empty, pageSize: pageSize),
            indexURL: indexURL,
            query: query,
            source: .rebuilt
        )
        let task = Task { [session] in
            do {
                return try await LibraryIndexProjection.rebuild(
                    from: package,
                    to: indexURL,
                    pageSize: pageSize,
                    progress: { progress in await session.apply(progress) }
                )
            } catch {
                await session.failRebuild(error)
                throw error
            }
        }
        await session.install(task)
        _ = try await session.waitForFirstPage()
        return session
    }

    /// The default local index location used by the application-support projection.
    static func defaultIndexURL(for libraryID: UUID, applicationSupportURL: URL? = nil) -> URL {
        if let applicationSupportURL {
            return applicationSupportURL
                .appendingPathComponent("Kromora/Indexes", isDirectory: true)
                .appendingPathComponent(libraryID.uuidString.lowercased(), isDirectory: true)
                .appendingPathComponent("LibraryIndex.store")
        }
        return KromoraStorage.indexURL(for: libraryID)
    }

    var isRebuilding: Bool { rebuildTask != nil }

    func page(at pageIndex: Int, query: LibraryQuery = .all) -> LibraryQueryPage {
        controller.page(at: pageIndex, query: query)
    }

    func firstPage() async throws -> LibraryQueryPage {
        try await waitForFirstPage()
    }

    /// Waits for the final projection, preserving any first page already visible to the caller.
    @discardableResult
    func waitForRebuild() async throws -> LibraryIndexProjection {
        guard let rebuildTask else { return controller.index }
        return try await rebuildTask.value
    }

    func currentController() -> LibraryQueryController {
        controller
    }

    private func install(_ task: Task<LibraryIndexProjection, Error>) {
        rebuildTask = task
    }

    private func waitForFirstPage() async throws -> LibraryQueryPage {
        if let firstPublishedPage { return firstPublishedPage }
        if let rebuildError { throw rebuildError }
        return try await withCheckedThrowingContinuation { continuation in
            firstPageWaiters.append(continuation)
        }
    }

    private func apply(_ progress: LibraryIndexRebuildProgress) {
        let selectedIDs = controller.selectedIDs
        let activeID = controller.activeID
        controller = LibraryQueryController(
            index: progress.projection,
            pageSize: controller.pageSize,
            selectedAssetIDs: selectedIDs,
            activeAssetID: activeID
        )
        if firstPublishedPage == nil {
            firstPublishedPage = controller.page(at: 0, query: initialQuery)
            let waiters = firstPageWaiters
            firstPageWaiters.removeAll()
            waiters.forEach { $0.resume(returning: firstPublishedPage!) }
        }
        if progress.isComplete { rebuildTask = nil }
    }

    private func failRebuild(_ error: Error) {
        rebuildError = error
        rebuildTask = nil
        let waiters = firstPageWaiters
        firstPageWaiters.removeAll()
        waiters.forEach { $0.resume(throwing: error) }
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
        let foldedSearchText = query.searchText?.foldedForLibrarySearch
        let matching = index.entries.filter {
            matches($0, query: query, foldedSearchText: foldedSearchText)
        }
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
        let foldedSearchText = query.searchText?.foldedForLibrarySearch
        let matching = index.entries.filter {
            matches($0, query: query, foldedSearchText: foldedSearchText)
        }
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

    private func matches(
        _ entry: LibraryIndexEntry,
        query: LibraryQuery,
        foldedSearchText: String?
    ) -> Bool {
        let summary = entry.summary
        let flag = PhotoFlag(rawValue: summary.flag ?? "none") ?? .none
        guard query.filter.matches(flag: flag, rating: summary.rating ?? 0) else { return false }
        guard let foldedSearchText, !foldedSearchText.isEmpty else { return true }
        let haystack = [
            summary.displayName, summary.label, summary.cameraMake, summary.cameraModel,
            summary.lens, summary.captureDate,
        ].compactMap { $0 }.joined(separator: " ").foldedForLibrarySearch
        return haystack.contains(foldedSearchText)
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

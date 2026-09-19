import Foundation

/// The application boundary for the portable library package.
///
/// Opening this value is intentionally synchronous: AppViewModel does not publish a library until
/// the package manifest, membership shards, writer lease, and rebuildable query projection have
/// been established. A failure is thrown to the composition root, where it becomes an empty,
/// actionable failure state; there is no legacy-library fallback.
@MainActor
final class PortableLibrarySession {
    let package: PortableLibraryPackage
    let lease: PortablePackageLease
    let rootURL: URL
    let indexURL: URL

    private(set) var queryController: LibraryQueryController
    private var importCatalog: PortablePackageImportCatalog?

    init(
        at rootURL: URL,
        indexURL: URL? = nil,
        pageSize: Int = 500,
        now: Date = Date(),
        recoverExpiredLease: Bool = false
    ) throws {
        let normalizedRoot = rootURL.standardizedFileURL
        let fileManager = FileManager.default
        let package: PortableLibraryPackage

        // A missing path is the only create case. An existing placeholder, file, or malformed
        // package is opened and rejected; it is never replaced with an empty library.
        if fileManager.fileExists(atPath: normalizedRoot.path) {
            package = try PortableLibraryPackage.open(at: normalizedRoot)
        } else {
            package = try PortableLibraryPackage.create(at: normalizedRoot)
        }

        let lease = try Self.acquireWriterLease(
            at: normalizedRoot, now: now, recoverExpired: recoverExpiredLease
        )
        do {
            self.package = package
            self.lease = lease
            self.rootURL = normalizedRoot
            self.indexURL = indexURL?.standardizedFileURL
                ?? LibraryIndexSession.defaultIndexURL(for: package.manifest.libraryID)

            // A warm projection is preferred, but every mismatch/corruption is recoverable from
            // package membership summaries. This keeps the package canonical and the index
            // disposable without making the launch path silently empty.
            let projection: LibraryIndexProjection
            if let loaded = try? LibraryIndexProjection.load(from: self.indexURL),
               let valid = try? loaded.validated(for: package)
            {
                projection = valid
            } else {
                projection = try LibraryIndexProjection(package: package)
                try projection.write(to: self.indexURL)
            }
            self.queryController = LibraryQueryController(index: projection, pageSize: pageSize)
        } catch {
            try? lease.release()
            throw error
        }
    }

    private static func acquireWriterLease(
        at packageRoot: URL,
        now: Date,
        recoverExpired: Bool
    ) throws -> PortablePackageLease {
        do {
            return try PortablePackageLease.acquire(at: packageRoot, now: now)
        } catch let error as PortablePackageLeaseError {
            guard recoverExpired, case .expired = error else { throw error }
            try PortablePackageLease.recoverExpiredWriter(at: packageRoot, now: now)
            return try PortablePackageLease.acquire(at: packageRoot, now: now)
        }
    }

    deinit {
        try? lease.release()
    }

    var assetCount: Int { queryController.totalCount }

    func page(at pageIndex: Int, query: LibraryQuery = .all) -> LibraryQueryPage {
        queryController.page(at: pageIndex, query: query)
    }

    func select(_ assetID: PortablePhotoAssetID, additive: Bool = false) {
        queryController.select(assetID, additive: additive)
    }

    /// Rebuild the disposable projection after a package transaction. Selection is retained by
    /// opaque UUID, never by a page or array offset.
    @discardableResult
    func refreshIndex() throws -> LibraryIndexProjection {
        let projection = try LibraryIndexProjection(package: package)
        try projection.write(to: indexURL)
        queryController = LibraryQueryController(
            index: projection,
            pageSize: queryController.pageSize,
            selectedAssetIDs: queryController.selectedIDs,
            activeAssetID: queryController.activeID
        )
        importCatalog = nil
        return projection
    }

    @discardableResult
    func importURLs(
        _ urls: [URL],
        duplicatePolicy: PortablePackageDuplicatePolicy = .skip,
        isCancelled: @Sendable () -> Bool = { false },
        progress: @Sendable (PortablePackageImportProgress) -> Void = { _ in }
    ) throws -> PortablePackageImportResult {
        let sources = urls.map { PortablePackageImportSource(url: $0) }
        let result = try package.importSources(
            sources,
            lease: lease,
            options: .init(duplicatePolicy: duplicatePolicy),
            isCancelled: isCancelled,
            progress: progress
        )
        try refreshIndex()
        return result
    }

    /// Photos delivers bytes rather than a stable file URL. The temporary file is only an import
    /// transport; PortablePackageImporter owns the copy and the external/provider bytes are never
    /// used as a managed source after this method returns.
    @discardableResult
    func importData(
        _ data: Data,
        name: String,
        duplicatePolicy: PortablePackageDuplicatePolicy = .skip,
        rebuildIndex: Bool = true
    ) throws -> PortablePackageImportResult {
        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Kromora-import-\(UUID().uuidString)-\(safeFilename(name))")
        try data.write(to: temporaryURL, options: .atomic)
        defer { try? FileManager.default.removeItem(at: temporaryURL) }
        let result: PortablePackageImportResult
        if rebuildIndex {
            result = try package.importSources(
                [.init(url: temporaryURL, name: name)],
                lease: lease,
                options: .init(duplicatePolicy: duplicatePolicy)
            )
        } else {
            let catalog = try importCatalog ?? PortablePackageImportCatalog(package: package)
            result = try package.importSources(
                [.init(url: temporaryURL, name: name)],
                lease: lease,
                options: .init(duplicatePolicy: duplicatePolicy),
                catalog: catalog
            )
            importCatalog = catalog
        }
        if rebuildIndex {
            try refreshIndex()
        }
        return result
    }

    func finishImportBatch() {
        importCatalog = nil
    }

    func materializedAssets(pageIndex: Int, query: LibraryQuery = .all) throws -> [PhotoAsset] {
        try materialize(page(at: pageIndex, query: query).items)
    }

    /// Materialize the complete query result for the current presentation bridge. Membership and
    /// ordering still come from the paged package-backed index; this loop merely adapts every
    /// page to the existing collection UI until that UI consumes pages directly.
    func materializedAssets(query: LibraryQuery = .all) throws -> [PhotoAsset] {
        var assets: [PhotoAsset] = []
        var pageIndex = 0
        while true {
            let page = self.page(at: pageIndex, query: query)
            assets.append(contentsOf: try materialize(page.items))
            guard page.hasNextPage else { return assets }
            pageIndex += 1
        }
    }

    private func materialize(_ items: [LibraryQueryItem]) throws -> [PhotoAsset] {
        try items.map { item in
            let record = try package.readAssetRecord(for: item.assetID)
            let sourceURL = try package.embeddedSourceURL(for: record)
            let source = PhotoAssetSource(
                url: sourceURL,
                id: PhotoAssetID(rawValue: "portable:\(item.assetID.raw)"),
                data: nil,
                bookmarkData: nil,
                portableIdentity: record.identity
            )
            let summary = item.summary
            let metadata = PhotoAssetMetadata(
                dimensions: summary.dimensions,
                captureDate: summary.captureDate,
                cameraMake: summary.cameraMake,
                cameraModel: summary.cameraModel,
                lens: summary.lens
            )
            let state = PhotoAssetLibraryState(
                rating: summary.rating ?? 0,
                flag: PhotoFlag(rawValue: summary.flag ?? "none") ?? .none
            )
            return PhotoAsset(
                source: source,
                filename: summary.displayName,
                fileType: sourceURL.pathExtension,
                metadata: metadata,
                libraryState: state
            )
        }
    }

    @discardableResult
    func removeFromLibrary(_ assetID: PortablePhotoAssetID) throws -> PortablePackageRemovalResult {
        let result = try package.removeFromLibrary(assetID, lease: lease)
        try refreshIndex()
        return result
    }

    /// Persist the package-owned catalog summary used by filtering and sorting. The presentation
    /// bridge may mirror this state for the current window, but it must not become the durable
    /// authority for a portable library.
    func updateLibraryState(
        for assetID: PortablePhotoAssetID,
        rating: Int,
        flag: PhotoFlag
    ) throws {
        let shardName = PortableLibraryPackage.shard(for: assetID)
        var shard = try package.readMembershipShard(shardName)
        guard let index = shard.entries.firstIndex(where: {
            $0.assetID == assetID && !$0.isTombstone
        }) else {
            throw PortablePackageTrashError.assetNotFound(assetID)
        }
        guard shard.entries[index].summary.rating != rating
            || shard.entries[index].summary.flag != flag.rawValue else { return }
        shard.entries[index].summary.rating = min(max(rating, 0), 5)
        shard.entries[index].summary.flag = flag.rawValue
        shard.entries[index].summary.assetRevision &+= 1

        var transaction = try package.beginTransaction(lease: lease)
        do {
            try transaction.stage(
                data: try package.encodedMembershipShard(shard),
                at: "Catalog/Membership/\(shardName).json"
            )
            try transaction.commit()
        } catch {
            try? transaction.abort()
            throw error
        }
        try refreshIndex()
    }

    private func safeFilename(_ name: String) -> String {
        let component = URL(fileURLWithPath: name).lastPathComponent
        return component.isEmpty ? "original" : component.replacingOccurrences(of: "/", with: "_")
    }
}

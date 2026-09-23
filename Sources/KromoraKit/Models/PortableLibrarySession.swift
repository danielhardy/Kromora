import Foundation
import os.lock

/// Injectable time hooks keep lease-lifetime tests deterministic while production uses wall-clock
/// time and the same cooperative sleep mechanism as the rest of the app.
struct PortableLibrarySessionClock: Sendable {
    let now: @Sendable () -> Date
    let sleep: @Sendable (_ seconds: TimeInterval) async throws -> Void

    init(
        now: @escaping @Sendable () -> Date = { Date() },
        sleep: @escaping @Sendable (_ seconds: TimeInterval) async throws -> Void = { seconds in
            try await Task.sleep(for: .seconds(seconds))
        }
    ) {
        self.now = now
        self.sleep = sleep
    }
}

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
    private let leaseDuration: TimeInterval
    private let clock: PortableLibrarySessionClock
    private let scheduler: ImageWorkScheduler?
    private let heartbeatJobID: ImageWorkScheduler.JobID
    private let indexWriteJobID: ImageWorkScheduler.JobID
    private var activeImportJobIDs: Set<ImageWorkScheduler.JobID> = []
    private var asyncImportCatalog: ImportCatalogState?
    private var pendingImportIndexDelta = LibraryIndexDelta.empty
    private var heartbeatTask: Task<Void, Never>?
    private var isShuttingDown = false
    private var lostDuringSession = false

    init(
        at rootURL: URL,
        indexURL: URL? = nil,
        pageSize: Int = 500,
        now: Date? = nil,
        recoverExpiredLease: Bool = false,
        leaseDuration: TimeInterval = PortablePackageLease.defaultDuration,
        clock: PortableLibrarySessionClock = .init(),
        scheduler: ImageWorkScheduler? = nil
    ) throws {
        let normalizedRoot = rootURL.standardizedFileURL
        let acquisitionNow = now ?? clock.now()
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
            at: normalizedRoot, now: acquisitionNow, duration: leaseDuration,
            recoverExpired: recoverExpiredLease
        )
        do {
            self.package = package
            self.lease = lease
            self.rootURL = normalizedRoot
            self.indexURL =
                indexURL?.standardizedFileURL
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
            self.leaseDuration = max(0.001, leaseDuration)
            self.clock = clock
            self.scheduler = scheduler
            self.heartbeatJobID = ImageWorkScheduler.JobID(
                "portable-package-lease-heartbeat-\(lease.ownerID.uuidString)"
            )
            self.indexWriteJobID = ImageWorkScheduler.JobID(
                "portable-package-index-write-\(lease.ownerID.uuidString)"
            )
            if scheduler != nil { startLeaseHeartbeat() }
        } catch {
            try? lease.release()
            throw error
        }
    }

    private static func acquireWriterLease(
        at packageRoot: URL, now: Date, duration: TimeInterval, recoverExpired: Bool
    ) throws -> PortablePackageLease {
        do {
            return try PortablePackageLease.acquire(
                at: packageRoot, now: now, duration: duration
            )
        } catch let error as PortablePackageLeaseError {
            guard recoverExpired, case .expired = error else { throw error }
            try PortablePackageLease.recoverExpiredWriter(at: packageRoot, now: now)
            return try PortablePackageLease.acquire(at: packageRoot, now: now)
        }
    }

    deinit {
        heartbeatTask?.cancel()
        try? lease.release()
    }

    /// Begins the session-owned renewal loop on the shared package-I/O lane. The loop is started
    /// by the app composition root after it has created that scheduler; unit tests can inject the
    /// same lane and clock without waiting on real time.
    private func startLeaseHeartbeat() {
        let interval = max(0.001, leaseDuration / 3)
        heartbeatTask = Task { @MainActor [weak self] in
            while let self, !Task.isCancelled, !self.isShuttingDown {
                do {
                    try await self.clock.sleep(interval)
                } catch {
                    return
                }
                guard !Task.isCancelled, !self.isShuttingDown else { return }
                self.enqueueLeaseRenewal()
            }
        }
    }

    /// Schedules an immediate renewal after the application wakes. If the scheduler is busy, the
    /// normal heartbeat will retry; rejection is an ordinary dependency/contended-lane condition,
    /// not permission to steal or break a lock.
    func renewAfterWake() {
        guard !isShuttingDown, !lostDuringSession else { return }
        enqueueLeaseRenewal()
    }

    private func enqueueLeaseRenewal() {
        guard let scheduler, !scheduler.contains(heartbeatJobID) else { return }
        let lease = self.lease
        let now = clock.now
        let failure = LeaseHeartbeatFailure()
        _ = scheduler.enqueuePackageIO(
            id: heartbeatJobID,
            lane: .leaseHeartbeat,
            onTerminal: { [weak self] outcome in
                guard let self else { return }
                if failure.didFail && outcome != .cancelled && !self.isShuttingDown {
                    self.lostDuringSession = true
                }
            },
            operation: {
                do {
                    try lease.renew(now: now())
                } catch {
                    failure.didFail = true
                }
            }
        )
    }

    /// Stops renewal, waits for a renewal already inside the detached package-I/O body, then
    /// releases the lock. The order is important: no heartbeat may run against a future owner.
    func shutdown() async {
        guard !isShuttingDown else { return }
        isShuttingDown = true
        heartbeatTask?.cancel()
        heartbeatTask = nil
        await scheduler?.cancelAndWait(id: heartbeatJobID)
        for jobID in activeImportJobIDs {
            await scheduler?.cancelAndWait(id: jobID)
        }
        activeImportJobIDs.removeAll()
        await scheduler?.cancelAndWait(id: indexWriteJobID)
        try? lease.release()
    }

    private func ensureWritableLease() throws {
        guard !isShuttingDown else { throw PortablePackageLeaseError.notOwner }
        guard !lostDuringSession else { throw PortablePackageLeaseError.lostDuringSession }
        do {
            try lease.renew(now: clock.now())
        } catch {
            lostDuringSession = true
            throw PortablePackageLeaseError.lostDuringSession
        }
    }

    private func ensureLeaseError(_ error: Error) -> Error {
        if error is PortablePackageLeaseError { return PortablePackageLeaseError.lostDuringSession }
        return error
    }

    /// Thread-safe result handoff from the detached package-I/O operation to the main-actor
    /// session. A renewal failure is deliberately reduced to a boolean: the user-facing action
    /// is the same for expiry, deletion, contention after a steal, or an invalid lock payload.
    private final class LeaseHeartbeatFailure: Sendable {
        private let value = OSAllocatedUnfairLock(initialState: false)

        var didFail: Bool {
            get { value.withLock { $0 } }
            set { value.withLock { $0 = newValue } }
        }
    }

    var assetCount: Int { queryController.totalCount }

    func totalCount(query: LibraryQuery = .all) -> Int {
        page(at: 0, query: query).totalCount
    }

    func page(at pageIndex: Int, query: LibraryQuery = .all) -> LibraryQueryPage {
        queryController.page(at: pageIndex, query: query)
    }

    /// Single selection authority for the portable path. Grid, filmstrip, keyboard navigation,
    /// culling, and open all route through these UUID-keyed values; ImageCollection mirrors them
    /// for presentation but never diverges as an independent selection store.
    var portableSelectedIDs: Set<PortablePhotoAssetID> { queryController.selectedIDs }
    var portableActiveID: PortablePhotoAssetID? { queryController.activeID }

    func select(_ assetID: PortablePhotoAssetID, additive: Bool = false) {
        queryController.select(assetID, additive: additive)
    }

    func setPortableSelection(_ assetIDs: [PortablePhotoAssetID], activeID: PortablePhotoAssetID?) {
        queryController.setSelection(assetIDs, activeID: activeID)
    }

    func togglePortableSelection(_ assetID: PortablePhotoAssetID) {
        queryController.toggleSelection(assetID)
    }

    func clearPortableSelection() {
        queryController.clearSelection()
    }

    func selectAllPortable(query: LibraryQuery = .all) {
        queryController.selectAll(query: query)
    }

    /// Windowed browsing projection for grid/filmstrip. Returns the assets for exactly one page
    /// plus the total match count for that query, so callers can bound retained Items to the
    /// visible window while keeping stable `portable:<uuid>` identity across page changes.
    func browsingWindow(
        pageIndex: Int, query: LibraryQuery = .all
    ) throws -> (assets: [PhotoAsset], totalCount: Int, pageSize: Int) {
        let page = self.page(at: pageIndex, query: query)
        let assets = try page.items.map { try Self.browsingAsset(for: $0, package: package) }
        return (assets, page.totalCount, page.pageSize)
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

    /// Publish the membership change already returned by a package transaction. The projection is
    /// updated synchronously in memory for query consistency, while its disposable JSON file is
    /// written on the package-I/O lane and coalesced with later imports.
    @discardableResult
    private func applyIndexDelta(_ delta: LibraryIndexDelta, persistSynchronously: Bool = false)
        throws -> LibraryIndexProjection
    {
        let projection = try queryController.index.applying(delta)
        let selectedAssetIDs = queryController.selectedIDs
        let activeAssetID = queryController.activeID
        queryController = LibraryQueryController(
            index: projection,
            pageSize: queryController.pageSize,
            selectedAssetIDs: selectedAssetIDs,
            activeAssetID: activeAssetID
        )
        importCatalog = nil
        if persistSynchronously {
            try projection.write(to: indexURL)
        } else {
            enqueueIndexWrite(projection)
        }
        return projection
    }

    private final class IndexWriteGeneration: Sendable {
        private let state = OSAllocatedUnfairLock(initialState: 0)

        func publish() -> Int {
            state.withLock {
                $0 += 1
                return $0
            }
        }

        func isCurrent(_ value: Int) -> Bool {
            state.withLock { $0 == value }
        }
    }

    private let indexWriteGeneration = IndexWriteGeneration()

    private func enqueueIndexWrite(_ projection: LibraryIndexProjection) {
        guard let scheduler else {
            // Headless/session tests without a scheduler still get a durable projection. The
            // production composition root always supplies the shared package-I/O lane.
            try? projection.write(to: indexURL)
            return
        }
        let generation = indexWriteGeneration.publish()
        _ = scheduler.enqueuePackageIO(
            id: indexWriteJobID,
            lane: .indexRebuild,
            operation: { [indexWriteGeneration, projection, indexURL] in
                guard indexWriteGeneration.isCurrent(generation), !Task.isCancelled else { return }
                try? projection.write(to: indexURL)
            }
        )
    }

    /// Starts an import without performing package I/O on the main actor. The returned handle is
    /// deliberately small: callers consume its progress stream and await its final result, while
    /// the worker owns all source copies, hashes, fsyncs, commits, and rollback.
    func startImportURLs(
        _ urls: [URL],
        duplicatePolicy: PortablePackageDuplicatePolicy = .skip
    ) throws -> PortablePackageImportHandle {
        try startImport(
            sources: urls.map { .init(url: $0) },
            duplicatePolicy: duplicatePolicy,
            catalogState: nil
        )
    }

    func startImportData(
        _ data: Data,
        name: String,
        duplicatePolicy: PortablePackageDuplicatePolicy = .skip,
        rebuildIndex: Bool = true
    ) throws -> PortablePackageImportHandle {
        try startImportDataBatch(
            [(name: name, data: data)],
            duplicatePolicy: duplicatePolicy,
            rebuildIndex: rebuildIndex
        )
    }

    func startImportDataBatch(
        _ items: [(name: String, data: Data)],
        duplicatePolicy: PortablePackageDuplicatePolicy = .skip,
        rebuildIndex: Bool = true
    ) throws -> PortablePackageImportHandle {
        let state = rebuildIndex ? nil : (asyncImportCatalog ?? ImportCatalogState())
        if let state, asyncImportCatalog == nil { asyncImportCatalog = state }
        let sources = items.map { PortablePackageImportSource(data: $0.data, name: $0.name) }
        return try startImport(
            sources: sources,
            duplicatePolicy: duplicatePolicy,
            catalogState: state
        )
    }

    private actor ImportCatalogState {
        var catalog: PortablePackageImportCatalog?

        func importing(
            with importer: PortablePackageImporter,
            sources: [PortablePackageImportSource],
            options: PortablePackageImportOptions,
            isCancelled: @Sendable @escaping () -> Bool,
            progress: @Sendable @escaping (PortablePackageImportProgress) -> Void,
            now: @escaping @Sendable () -> Date
        ) throws -> PortablePackageImportResult {
            let catalog = try catalog ?? PortablePackageImportCatalog(package: importer.package)
            let result = try importer.import(
                sources: sources,
                options: options,
                isCancelled: isCancelled,
                progress: progress,
                catalog: catalog,
                now: now
            )
            self.catalog = catalog
            return result
        }
    }

    private func appendPendingImportDelta(_ delta: LibraryIndexDelta) {
        pendingImportIndexDelta = pendingImportIndexDelta.merging(delta)
    }

    private func startImport(
        sources: [PortablePackageImportSource],
        duplicatePolicy: PortablePackageDuplicatePolicy,
        catalogState: ImportCatalogState?
    ) throws -> PortablePackageImportHandle {
        guard !isShuttingDown else { throw PortablePackageLeaseError.notOwner }
        guard !lostDuringSession else { throw PortablePackageLeaseError.lostDuringSession }
        guard let scheduler else { throw PortablePackageImportWorkerError.schedulerUnavailable }

        let progressSink = PortablePackageImportProgressSink()
        let progress = AsyncStream<PortablePackageImportProgress> { continuation in
            progressSink.install(continuation)
        }
        let resultBox = PortablePackageImportResultBox()
        let workerResultBox = PortablePackageImportResultBox()
        let cancellation = PortablePackageImportCancellation()
        let jobID = ImageWorkScheduler.JobID(
            "portable-package-import-\(lease.ownerID.uuidString)-\(UUID().uuidString)"
        )
        let handle = PortablePackageImportHandle(
            progress: progress,
            resultBox: resultBox,
            cancellation: cancellation,
            cancelAction: { scheduler.cancel(id: jobID) }
        )
        activeImportJobIDs.insert(jobID)
        let package = self.package
        let lease = self.lease
        let now = self.clock.now
        let admitted = scheduler.enqueuePackageIO(
            id: jobID,
            lane: .importCopyHash,
            onTerminal: { [weak self, weak handle, progressSink] outcome in
                guard let self else { return }
                self.activeImportJobIDs.remove(jobID)
                // A queued job cancelled before its operation runs never reaches the defer
                // below, so end the progress stream on every terminal outcome. Otherwise a
                // `for await` consumer would wait forever; finishing twice is a no-op.
                progressSink.finish()
                switch outcome {
                case .completed:
                    guard let outcome = workerResultBox.outcomeIfFinished() else {
                        handle?.finish(.failure(CancellationError()))
                        return
                    }
                    if case .success(let result) = outcome {
                        do {
                            if catalogState == nil {
                                _ = try self.applyIndexDelta(result.indexDelta)
                            } else {
                                self.appendPendingImportDelta(result.indexDelta)
                            }
                        } catch {
                            // The package remains canonical; a disposable index can be rebuilt
                            // at next launch if an unexpected projection validation error occurs.
                            _ = try? self.refreshIndex()
                        }
                    }
                    handle?.finish(outcome)
                case .cancelled, .evicted, .rejected:
                    handle?.finish(
                        .failure(
                        outcome == .rejected
                            ? PortablePackageImportWorkerError.notAdmitted
                            : CancellationError()
                    ))
                }
            },
            operation: {
                defer {
                    progressSink.finish()
                }
                do {
                    let importer = PortablePackageImporter(package: package, lease: lease)
                    let result: PortablePackageImportResult
                    if let catalogState {
                        result = try await catalogState.importing(
                            with: importer,
                            sources: sources,
                            options: .init(duplicatePolicy: duplicatePolicy),
                            isCancelled: { cancellation.isCancelled || Task.isCancelled },
                            progress: { progressSink.yield($0) },
                            now: now
                        )
                    } else {
                        result = try importer.import(
                            sources: sources,
                            options: .init(duplicatePolicy: duplicatePolicy),
                            isCancelled: { cancellation.isCancelled || Task.isCancelled },
                            progress: { progressSink.yield($0) },
                            now: now
                        )
                    }
                    workerResultBox.finish(.success(result))
                } catch {
                    workerResultBox.finish(.failure(error))
                }
            }
        )
        if !admitted {
            activeImportJobIDs.remove(jobID)
            progressSink.finish()
            handle.finish(.failure(PortablePackageImportWorkerError.notAdmitted))
            throw PortablePackageImportWorkerError.notAdmitted
        }
        return handle
    }

    @discardableResult
    func importURLs(
        _ urls: [URL],
        duplicatePolicy: PortablePackageDuplicatePolicy = .skip,
        isCancelled: @Sendable () -> Bool = { false },
        progress: @Sendable (PortablePackageImportProgress) -> Void = { _ in }
    ) throws -> PortablePackageImportResult {
        try ensureWritableLease()
        let sources = urls.map { PortablePackageImportSource(url: $0) }
        let result: PortablePackageImportResult
        do {
            result = try package.importSources(
                sources,
                lease: lease,
                options: .init(duplicatePolicy: duplicatePolicy),
                isCancelled: isCancelled,
                progress: progress,
                now: clock.now
            )
        } catch {
            throw ensureLeaseError(error)
        }
        _ = try applyIndexDelta(result.indexDelta, persistSynchronously: true)
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
        try ensureWritableLease()
        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "Kromora-import-\(UUID().uuidString)-\(PortableLibraryPackage.safeFilename(name))")
        try data.write(to: temporaryURL, options: .atomic)
        defer { try? FileManager.default.removeItem(at: temporaryURL) }
        let result: PortablePackageImportResult
        do {
            if rebuildIndex {
                result = try package.importSources(
                    [.init(url: temporaryURL, name: name)],
                    lease: lease,
                    options: .init(duplicatePolicy: duplicatePolicy),
                    now: clock.now
                )
            } else {
                let catalog = try importCatalog ?? PortablePackageImportCatalog(package: package)
                result = try package.importSources(
                    [.init(url: temporaryURL, name: name)],
                    lease: lease,
                    options: .init(duplicatePolicy: duplicatePolicy),
                    catalog: catalog,
                    now: clock.now
                )
                importCatalog = catalog
            }
        } catch {
            throw ensureLeaseError(error)
        }
        if rebuildIndex {
            _ = try applyIndexDelta(result.indexDelta, persistSynchronously: true)
        } else {
            appendPendingImportDelta(result.indexDelta)
        }
        return result
    }

    func finishImportBatch() {
        importCatalog = nil
        asyncImportCatalog = nil
        guard pendingImportIndexDelta != .empty else { return }
        _ = try? applyIndexDelta(pendingImportIndexDelta)
        pendingImportIndexDelta = .empty
    }

    /// Test/diagnostic hook invoked once per asset record opened by `materialize(_:)` or the
    /// `resolveEmbeddedSourceURL(for:)` record fallback. The browsing projection never fires
    /// it; the scale regression suite uses it to prove that launch, reload, first grid frame,
    /// and import/reload do not open non-visible records.
    var assetRecordReadObserver: ((PortablePhotoAssetID) -> Void)?

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

    /// Browsing projection for the presentation bridge. Grid metadata (identity, name, type,
    /// dimensions, rating, flag, and the derived embedded URL) comes from `LibraryIndexEntry`
    /// summaries only: no asset record is opened, no original is fingerprinted, and no thumbnail
    /// bytes are read. Full records are resolved lazily by `resolveEmbeddedSourceURL(for:)` when
    /// an asset is opened, exported, or edited.
    ///
    /// Membership and ordering still come from the paged package-backed index; this loop adapts
    /// every page to the existing collection UI until that UI consumes pages directly (KRMA-519
    /// scope item 2). The per-item cost is pure value construction, so launch and reload stay
    /// bounded by the index rather than by record or original I/O.
    func browsingAssets(query: LibraryQuery = .all) throws -> [PhotoAsset] {
        var assets: [PhotoAsset] = []
        var pageIndex = 0
        while true {
            let page = self.page(at: pageIndex, query: query)
            assets.append(
                contentsOf: try page.items.map { try Self.browsingAsset(for: $0, package: package) }
            )
            guard page.hasNextPage else { return assets }
            pageIndex += 1
        }
    }

    /// The first visible window of the browsing projection. Grid and filmstrip paint from this
    /// page; stable `PhotoAssetID` identity (`portable:<uuid>`) keeps selection coherent as
    /// further pages fault in.
    func browsingAssets(pageIndex: Int, query: LibraryQuery = .all) throws -> [PhotoAsset] {
        try page(at: pageIndex, query: query).items.map {
            try Self.browsingAsset(for: $0, package: package)
        }
    }

    /// Canonical source URL for opening, exporting, or editing one asset. The derived browsing
    /// locator wins when the file exists (zero record reads); otherwise exactly one record is
    /// opened for the requested asset and never for its neighbours.
    func resolveEmbeddedSourceURL(for assetID: PortablePhotoAssetID) throws -> URL {
        if let entry = queryController.index.entry(for: assetID) {
            // Keep the observer honest: `verifiedEmbeddedSourceURL` opens the record when the
            // derived file is missing, so check the cheap derived path first and only count
            // the fallback when a record is actually opened. The returned URL is identical.
            let derived = try package.browsingOriginalURL(
                for: assetID, displayName: entry.summary.displayName
            )
            if FileManager.default.fileExists(atPath: derived.path) { return derived }
            assetRecordReadObserver?(assetID)
            return try package.verifiedEmbeddedSourceURL(
                for: assetID, displayName: entry.summary.displayName
            )
        }
        assetRecordReadObserver?(assetID)
        return try package.embeddedSourceURL(for: package.readAssetRecord(for: assetID))
    }

    private static func browsingAsset(
        for item: LibraryQueryItem, package: PortableLibraryPackage
    ) throws -> PhotoAsset {
        let summary = item.summary
        let embeddedURL = try package.browsingOriginalURL(
            for: item.assetID, displayName: summary.displayName
        )
        let source = PhotoAssetSource(
            browsingPortableAsset: item.assetID,
            embeddedURL: embeddedURL,
            summary: summary
        )
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
            fileType: embeddedURL.pathExtension,
            metadata: metadata,
            libraryState: state
        )
    }

    private func materialize(_ items: [LibraryQueryItem]) throws -> [PhotoAsset] {
        try items.map { item in
            assetRecordReadObserver?(item.assetID)
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
        try ensureWritableLease()
        let result: PortablePackageRemovalResult
        do {
            result = try package.removeFromLibrary(assetID, lease: lease)
        } catch {
            throw ensureLeaseError(error)
        }
        _ = try applyIndexDelta(.init(removals: [assetID]))
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
        try ensureWritableLease()
        let shardName = PortableLibraryPackage.shard(for: assetID)
        var shard = try package.readMembershipShard(shardName)
        guard
            let index = shard.entries.firstIndex(where: {
            $0.assetID == assetID && !$0.isTombstone
            })
        else {
            throw PortablePackageTrashError.assetNotFound(assetID)
        }
        guard
            shard.entries[index].summary.rating != rating
                || shard.entries[index].summary.flag != flag.rawValue
        else { return }
        shard.entries[index].summary.rating = min(max(rating, 0), 5)
        shard.entries[index].summary.flag = flag.rawValue
        shard.entries[index].summary.assetRevision &+= 1

        var transaction = try package.beginTransaction(lease: lease, now: clock.now())
        do {
            try transaction.stage(
                data: try package.encodedMembershipShard(shard),
                at: "Catalog/Membership/\(shardName).json"
            )
            try transaction.commit()
        } catch {
            try? transaction.abort()
            throw ensureLeaseError(error)
        }
        _ = try applyIndexDelta(
            .init(upserts: [.init(from: shard.entries[index])])
        )
    }

}

import Foundation
import os
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

struct LibraryIndexLoadingState: Sendable {
    let shardsRead: Int
    let totalShards: Int
    let isComplete: Bool
    let errorMessage: String?
}

/// Prevents an unreadable legacy record from restarting the background scan indefinitely during
/// one package session. Committed progress starts a fresh consecutive-failure window.
struct SourceFingerprintBackfillRetryGate {
    static let maximumConsecutiveFailures = 3

    private(set) var consecutiveFailures = 0

    var permitsAttempt: Bool {
        consecutiveFailures < Self.maximumConsecutiveFailures
    }

    mutating func recordFailure() {
        consecutiveFailures += 1
    }

    mutating func recordProgress() {
        consecutiveFailures = 0
    }
}

/// The application boundary for the portable library package.
///
/// Opening the package and acquiring its writer lease are synchronous. Production startup opts
/// into asynchronous index loading so a cold shard walk or large index decode never occupies the
/// main actor. Tests and explicit maintenance callers can retain the synchronous boundary.
@MainActor
final class PortableLibrarySession {
    let package: PortableLibraryPackage
    let lease: PortablePackageLease
    let rootURL: URL
    let indexURL: URL

    private(set) var queryController: LibraryQueryController
    /// Advances whenever the published index is replaced, so an index-side plan built from an
    /// earlier `queryController` value can be recognized as stale.
    private(set) var indexGeneration: UInt64 = 0
    private var startupFirstPage: LibraryQueryPage?
    private var importCatalog: PortablePackageImportCatalog?
    private let leaseDuration: TimeInterval
    private let clock: PortableLibrarySessionClock
    private let scheduler: ImageWorkScheduler?
    private let heartbeatJobID: ImageWorkScheduler.JobID
    private let indexWriteJobID: ImageWorkScheduler.JobID
    private let virtualCopyJobID: ImageWorkScheduler.JobID
    private let removalJobID: ImageWorkScheduler.JobID
    private let libraryStateJobID: ImageWorkScheduler.JobID
    private let indexLoadJobID: ImageWorkScheduler.JobID
    private let presentedAspectRatioRepairJobID: ImageWorkScheduler.JobID
    private let sourceFingerprintBackfillJobID: ImageWorkScheduler.JobID
    /// Open-time fingerprint repairs in flight, keyed by asset so repeated opens coalesce.
    private var pendingFingerprintRepairs: [PortablePhotoAssetID: ImageWorkScheduler.JobID] = [:]
    private let captureMetadataBackfillJobID: ImageWorkScheduler.JobID
    private(set) var indexLoadingState: LibraryIndexLoadingState?
    private(set) var isLoadingIndex = false
    private(set) var didRepairIndexOnOpen = false
    var onIndexLoadingStateChange: (@MainActor (LibraryIndexLoadingState) -> Void)?
    var onIndexWriteFailure: (@MainActor (String) -> Void)?
    var onPresentedAspectRatioUpdates: (@MainActor ([PortablePhotoAssetID: Double]) -> Void)?
    /// Test seam: runs on the repair thread while it holds the writer mutation lock for a shard,
    /// so a benchmark can start a mutation against a lock that is provably held. Production
    /// leaves it nil.
    private let presentedAspectRatioRepairLockHook: (@Sendable () -> Void)?
    private var activeImportJobIDs: Set<ImageWorkScheduler.JobID> = []
    private var asyncImportCatalog: ImportCatalogState?
    private var pendingImportIndexDelta = LibraryIndexDelta.empty
    private var heartbeatTask: Task<Void, Never>?
    private var detachedIndexLoadTask: Task<Void, Never>?
    private var detachedPresentedAspectRatioRepairTask: Task<Void, Never>?
    private var detachedSourceFingerprintBackfillTask: Task<Void, Never>?
    private var didStartPresentedAspectRatioRepair = false
    /// Assets whose ratio was resolved in memory for the first page but is not yet durable, so the
    /// repair pass still has to write their summaries.
    private var hydratedAspectRatioAssetIDs: Set<PortablePhotoAssetID> = []
    private var presentedAspectRatioRepairShards: [String] = []
    private var nextPresentedAspectRatioRepairShard = 0
    private var didStartSourceFingerprintBackfill = false
    private var detachedCaptureMetadataBackfillTask: Task<Void, Never>?
    private var didStartCaptureMetadataBackfill = false
    private var captureMetadataBackfillShards: [String] = []
    private var nextCaptureMetadataBackfillShard = 0
    private var sourceFingerprintBackfillRetryGate = SourceFingerprintBackfillRetryGate()
    private var isShuttingDown = false
    private var pendingLibraryStateUpdates: [PortablePhotoAssetID: LibraryStateUpdate] = [:]
    private var isDrainingLibraryState = false
    private var libraryStateIndexWriteMayBeLost = false
    /// Culling changes whose shard failed to commit. They stay dirty until a later drain (the next
    /// enqueue or flush) writes them or a newer intent for the same asset replaces them.
    private var failedLibraryStateUpdates: [PortablePhotoAssetID: LibraryStateUpdate] = [:]
    private var libraryStateIdleWaiters: [CheckedContinuation<Void, Never>] = []
    private var libraryStateFailureHandler: (@MainActor (Error) -> Void)?
    private var lostDuringSession = false

    convenience init(
        at rootURL: URL,
        indexURL: URL? = nil,
        pageSize: Int = 500,
        now: Date? = nil,
        recoverExpiredLease: Bool = false,
        leaseDuration: TimeInterval = PortablePackageLease.defaultDuration,
        clock: PortableLibrarySessionClock = .init(),
        scheduler: ImageWorkScheduler? = nil,
        asynchronousIndexLoading: Bool = false,
        presentedAspectRatioRepairLockHook: (@Sendable () -> Void)? = nil
    ) throws {
        let opened = try Self.acquire(
            at: rootURL, now: now ?? clock.now(), leaseDuration: leaseDuration,
            recoverExpiredLease: recoverExpiredLease,
            asynchronousIndexLoading: asynchronousIndexLoading
        )
        try self.init(
            opened: opened, indexURL: indexURL, pageSize: pageSize, leaseDuration: leaseDuration,
            clock: clock, scheduler: scheduler, asynchronousIndexLoading: asynchronousIndexLoading,
            presentedAspectRatioRepairLockHook: presentedAspectRatioRepairLockHook
        )
    }

    /// The blocking half of opening: opens (or, for a missing path, creates) the package and
    /// acquires its writer lease. It touches no main-actor state, so launch runs it off the main
    /// actor and builds the session from the result with ``init(opened:)``.
    nonisolated static func acquire(
        at rootURL: URL,
        now: Date,
        leaseDuration: TimeInterval = PortablePackageLease.defaultDuration,
        recoverExpiredLease: Bool = false,
        asynchronousIndexLoading: Bool = false
    ) throws -> OpenedPackage {
        let normalizedRoot = rootURL.standardizedFileURL
        // A missing path is the only create case. An existing placeholder, file, or malformed
        // package is opened and rejected; it is never replaced with an empty library.
        let package: PortableLibraryPackage
        if FileManager.default.fileExists(atPath: normalizedRoot.path) {
            package = try asynchronousIndexLoading
                ? PortableLibraryPackage.openForQuery(at: normalizedRoot)
                : PortableLibraryPackage.open(at: normalizedRoot)
        } else {
            package = try PortableLibraryPackage.create(at: normalizedRoot)
        }
        let lease = try acquireWriterLease(
            at: normalizedRoot, now: now, duration: leaseDuration,
            recoverExpired: recoverExpiredLease
        )
        return OpenedPackage(package: package, lease: lease)
    }

    /// Builds the session around an already-open package and lease. A throw releases the lease.
    init(
        opened: OpenedPackage,
        indexURL: URL? = nil,
        pageSize: Int = 500,
        leaseDuration: TimeInterval = PortablePackageLease.defaultDuration,
        clock: PortableLibrarySessionClock = .init(),
        scheduler: ImageWorkScheduler? = nil,
        asynchronousIndexLoading: Bool = false,
        presentedAspectRatioRepairLockHook: (@Sendable () -> Void)? = nil
    ) throws {
        self.presentedAspectRatioRepairLockHook = presentedAspectRatioRepairLockHook
        let package = opened.package
        let lease = opened.lease
        let normalizedRoot = package.rootURL.standardizedFileURL
        let fileManager = FileManager.default
        do {
            self.package = package
            self.lease = lease
            self.rootURL = normalizedRoot
            self.indexURL =
                indexURL?.standardizedFileURL
                ?? LibraryIndexSession.defaultIndexURL(for: package.manifest.libraryID)
            let hadPersistedIndex = fileManager.fileExists(atPath: self.indexURL.path)

            // A warm projection is preferred, but every mismatch/corruption is recoverable from
            // package membership summaries. This keeps the package canonical and the index
            // disposable without making the launch path silently empty.
            let projection: LibraryIndexProjection
            if asynchronousIndexLoading {
                projection = try LibraryIndexProjection(
                    libraryID: package.manifest.libraryID, entries: [])
            } else if let loaded = try? LibraryIndexProjection.load(from: self.indexURL),
                      let valid = try? loaded.validated(for: package) {
                let reconciled = try valid.reconcilingMembership(with: package)
                if reconciled != valid {
                    self.didRepairIndexOnOpen = true
                    Self.noteIndexRepaired(from: valid, to: reconciled)
                    try reconciled.write(to: self.indexURL)
                }
                projection = reconciled
            } else {
                projection = try LibraryIndexProjection(package: package)
                try projection.write(to: self.indexURL)
                self.didRepairIndexOnOpen = hadPersistedIndex
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
            self.virtualCopyJobID = ImageWorkScheduler.JobID(
                "portable-package-virtual-copy-\(lease.ownerID.uuidString)"
            )
            self.removalJobID = ImageWorkScheduler.JobID(
                "portable-package-removal-\(lease.ownerID.uuidString)"
            )
            self.libraryStateJobID = ImageWorkScheduler.JobID(
                "portable-package-library-state-\(lease.ownerID.uuidString)"
            )
            self.indexLoadJobID = ImageWorkScheduler.JobID(
                "portable-package-index-load-\(lease.ownerID.uuidString)"
            )
            self.presentedAspectRatioRepairJobID = ImageWorkScheduler.JobID(
                "portable-package-presented-aspect-ratio-repair-\(lease.ownerID.uuidString)"
            )
            self.sourceFingerprintBackfillJobID = ImageWorkScheduler.JobID(
                "portable-package-source-fingerprint-backfill-\(lease.ownerID.uuidString)"
            )
            self.captureMetadataBackfillJobID = ImageWorkScheduler.JobID(
                "portable-package-capture-metadata-backfill-\(lease.ownerID.uuidString)"
            )
            if scheduler != nil { startLeaseHeartbeat() }
            if asynchronousIndexLoading {
                self.isLoadingIndex = true
                startIndexLoading(package: package, hadPersistedIndex: hadPersistedIndex)
            } else {
                startPresentedAspectRatioRepair()
            }
        } catch {
            try? lease.release()
            throw error
        }
    }

    nonisolated private static func acquireWriterLease(
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

    /// A persisted index that disagreed with package membership was repaired on open. The package
    /// is canonical, so this is recoverable, but it means an earlier index write was lost.
    nonisolated private static func noteIndexRepaired(
        from stale: LibraryIndexProjection, to repaired: LibraryIndexProjection
    ) {
        KromoraObservability.event(
            .libraryIndexRepaired,
            detail: "indexed=\(stale.entries.count) members=\(repaired.entries.count)"
        )
    }

    private func startIndexLoading(
        package: PortableLibraryPackage, hadPersistedIndex: Bool
    ) {
        let indexURL = self.indexURL
        let pageSize = queryController.pageSize
        let rawPublish: @Sendable (LibraryIndexProjection?, LibraryQueryPage?, Int, Int, Bool, String?) async -> Void = {
            [weak self] projection, page, shardsRead, totalShards, isComplete, error in
            await MainActor.run {
                guard let self, !self.isShuttingDown else { return }
                if let projection {
                    self.indexGeneration &+= 1
                    self.queryController = LibraryQueryController(
                        index: projection, pageSize: pageSize,
                        selectedAssetIDs: self.queryController.selectedIDs,
                        activeAssetID: self.queryController.activeID
                    )
                    self.startupFirstPage = page
                }
                let state = LibraryIndexLoadingState(
                    shardsRead: shardsRead, totalShards: totalShards,
                    isComplete: isComplete, errorMessage: error
                )
                self.indexLoadingState = state
                if state.isComplete { self.isLoadingIndex = false }
                if state.isComplete, error == nil {
                    self.startPresentedAspectRatioRepair()
                }
                self.onIndexLoadingStateChange?(state)
            }
        }
        // A legacy summary has no presented ratio, so its cell would take the 4:3 fallback in the
        // first projection. Resolve the first page's ratios from the originals' headers before
        // publishing; the repair pass makes them durable afterwards.
        let publish: @Sendable (LibraryIndexProjection?, LibraryQueryPage?, Int, Int, Bool, String?) async -> Void = {
            [weak self] projection, page, shardsRead, totalShards, isComplete, error in
            var projection = projection
            var page = page
            if let current = projection, let firstPage = page {
                let pageIDs = Set(firstPage.items.map(\.assetID))
                let ratios = package.resolvedPresentedAspectRatios(
                    for: current.entries.filter { pageIDs.contains($0.assetID) }
                )
                if !ratios.isEmpty,
                   let hydrated = try? current.applying(.init(presentedAspectRatioUpdates: ratios)) {
                    projection = hydrated
                    page = LibraryQueryController(index: hydrated, pageSize: pageSize).page(at: 0)
                    await MainActor.run { self?.hydratedAspectRatioAssetIDs.formUnion(ratios.keys) }
                }
            }
            await rawPublish(projection, page, shardsRead, totalShards, isComplete, error)
        }
        let operation: @Sendable () async -> Void = {
            var interval = KromoraSignpostInterval(
                .libraryIndex,
                context: KromoraTraceContext(sourceToken: "library-index", quality: "startup")
            )
            defer { interval.end() }
            do {
                if let loaded = try? LibraryIndexProjection.load(from: indexURL),
                   let valid = try? loaded.validated(for: package) {
                    let reconciled = try valid.reconcilingMembership(with: package)
                    KromoraObservability.event(.libraryIndexWarm)
                    let controller = LibraryQueryController(index: reconciled, pageSize: pageSize)
                    if reconciled != valid {
                        await MainActor.run { self.didRepairIndexOnOpen = true }
                        Self.noteIndexRepaired(from: valid, to: reconciled)
                        try reconciled.write(to: indexURL)
                    }
                    await publish(reconciled, controller.page(at: 0), 0, 0, true, nil)
                    return
                }
                if hadPersistedIndex {
                    await MainActor.run { self.didRepairIndexOnOpen = true }
                }
                KromoraObservability.event(.libraryIndexRebuild)
                _ = try await LibraryIndexProjection.rebuild(
                    from: package, to: indexURL, pageSize: pageSize,
                    progress: { progress in
                        await publish(progress.projection, progress.page, progress.shardsRead,
                                      progress.totalShards, progress.isComplete, nil)
                    }
                )
            } catch {
                await publish(nil, nil, 0, PortableLibraryPackage.allShards.count, true,
                              error.localizedDescription)
            }
        }
        if let scheduler {
            _ = scheduler.enqueuePackageIO(
                id: indexLoadJobID, lane: .indexRebuild, priority: .packageIO,
                onTerminal: { outcome in
                    guard outcome != .completed else { return }
                    Task {
                        await publish(
                            nil, nil, 0, PortableLibraryPackage.allShards.count, true,
                            "The package I/O scheduler could not start the library index task."
                        )
                    }
                },
                operation: operation
            )
        } else {
            detachedIndexLoadTask = Task.detached(operation: operation)
        }
    }

    /// Repairs legacy edit geometry only after a usable package index is published. The gate is
    /// computed entirely from that in-memory projection, so a current package performs no record
    /// reads for this maintenance pass. Scheduler-backed opens admit one shard per job at the
    /// lowest priority, returning the package-I/O lane between shards.
    private func startPresentedAspectRatioRepair() {
        guard !didStartPresentedAspectRatioRepair, !isShuttingDown else { return }
        let missing = queryController.index.entries.filter {
            $0.deletedRevision == nil
                && ($0.summary.presentedAspectRatio == nil
                    || hydratedAspectRatioAssetIDs.contains($0.assetID))
        }
        guard !missing.isEmpty else {
            startSourceFingerprintBackfill()
            return
        }
        didStartPresentedAspectRatioRepair = true
        presentedAspectRatioRepairShards = Array(Set(missing.map {
            PortableLibraryPackage.shard(for: $0.assetID)
        })).sorted()
        nextPresentedAspectRatioRepairShard = 0

        guard !presentedAspectRatioRepairShards.isEmpty else {
            startSourceFingerprintBackfill()
            return
        }

        if scheduler != nil {
            enqueueNextPresentedAspectRatioRepairShard()
            return
        }

        let package = self.package
        let lease = self.lease
        let shardNames = presentedAspectRatioRepairShards
        let lockHook = presentedAspectRatioRepairLockHook
        let operation: @Sendable () async -> Void = { [weak self] in
            do {
                _ = try await package.repairPresentedAspectRatios(
                    lease: lease,
                    shardNames: shardNames,
                    isCancelled: { Task.isCancelled },
                    afterWriterLockAcquired: lockHook,
                    onBatch: { [weak self] entries in
                        await MainActor.run {
                            self?.publishPresentedAspectRatioRepairBatch(entries)
                        }
                    }
                )
            } catch {
                // Earlier shard commits remain valid; a later package open resumes missing ones.
            }
            await MainActor.run { [weak self] in
                guard let self, !self.isShuttingDown else { return }
                self.startSourceFingerprintBackfill()
            }
        }
        detachedPresentedAspectRatioRepairTask = Task.detached(operation: operation)
    }

    private func enqueueNextPresentedAspectRatioRepairShard() {
        guard !isShuttingDown, let scheduler else { return }
        guard presentedAspectRatioRepairShards.indices.contains(
            nextPresentedAspectRatioRepairShard
        ) else {
            presentedAspectRatioRepairShards = []
            startSourceFingerprintBackfill()
            return
        }

        let shardName = presentedAspectRatioRepairShards[nextPresentedAspectRatioRepairShard]
        let package = self.package
        let lease = self.lease
        let now = clock.now
        let lockHook = presentedAspectRatioRepairLockHook
        _ = scheduler.enqueuePackageIO(
            id: presentedAspectRatioRepairJobID,
            lane: .maintenance,
            priority: .background,
            onTerminal: { [weak self] outcome in
                guard let self, !self.isShuttingDown else { return }
                switch outcome {
                case .completed:
                    self.nextPresentedAspectRatioRepairShard += 1
                    self.enqueueNextPresentedAspectRatioRepairShard()
                case .cancelled:
                    break
                case .evicted, .rejected:
                    // The missing summaries are durable repair markers and the next open retries.
                    self.startSourceFingerprintBackfill()
                }
            },
            operation: { [weak self] in
                do {
                    _ = try await package.repairPresentedAspectRatios(
                        lease: lease,
                        shardNames: [shardName],
                        now: now(),
                        isCancelled: { Task.isCancelled },
                        afterWriterLockAcquired: lockHook,
                        onBatch: { [weak self] entries in
                            await MainActor.run {
                                self?.publishPresentedAspectRatioRepairBatch(entries)
                            }
                        }
                    )
                } catch is CancellationError {
                    // Committed shards remain valid and the next package open resumes the scan.
                } catch {
                    // A bad shard does not prevent the remaining legacy summaries being repaired.
                }
            }
        )
    }

    private func publishPresentedAspectRatioRepairBatch(_ entries: [LibraryIndexEntry]) {
        let updates = Dictionary(
            entries.compactMap { entry in
                entry.summary.presentedAspectRatio.map { (entry.assetID, $0) }
            },
            uniquingKeysWith: { _, latest in latest }
        )
        guard !updates.isEmpty else { return }
        hydratedAspectRatioAssetIDs.subtract(updates.keys)
        _ = try? applyIndexDelta(.init(presentedAspectRatioUpdates: updates))
    }

    /// Starts legacy summary repair only after a usable index has been published. Browsing and
    /// selection are read-only projection work and do not cancel maintenance; the package
    /// scheduler keeps repair at background priority. Shutdown is the cancellation boundary.
    private func startSourceFingerprintBackfill() {
        guard !didStartSourceFingerprintBackfill, !isShuttingDown else { return }
        guard sourceFingerprintBackfillRetryGate.permitsAttempt,
              queryController.index.entries.contains(where: { $0.summary.sourceFingerprint == nil })
        else {
            startCaptureMetadataBackfill()
            return
        }
        didStartSourceFingerprintBackfill = true
        let package = self.package
        let lease = self.lease
        let operation: @Sendable () async -> Void = { [weak self] in
            var didFail = false
            do {
                _ = try await package.repairSourceFingerprints(
                    lease: lease,
                    isCancelled: { Task.isCancelled },
                    onBatch: { [weak self] entries in
                        await MainActor.run {
                            guard let self, !self.isShuttingDown else { return }
                            self.sourceFingerprintBackfillRetryGate.recordProgress()
                            _ = try? self.applyIndexDelta(.init(upserts: entries))
                        }
                    }
                )
            } catch is CancellationError {
                // Committed batches remain valid and the next library open resumes the scan.
            } catch {
                // A repair failure is non-fatal; missing identities remain safe placeholders.
                didFail = true
            }
            await MainActor.run { [weak self] in
                guard let self else { return }
                if didFail {
                    self.sourceFingerprintBackfillRetryGate.recordFailure()
                } else {
                    self.sourceFingerprintBackfillRetryGate.recordProgress()
                }
                self.didStartSourceFingerprintBackfill = false
                self.startCaptureMetadataBackfill()
            }
        }
        if let scheduler {
            _ = scheduler.enqueuePackageIO(
                id: sourceFingerprintBackfillJobID,
                lane: .maintenance,
                priority: .background,
                operation: operation
            )
        } else {
            detachedSourceFingerprintBackfillTask = Task.detached(operation: operation)
        }
    }

    /// Reads focal length, ISO, aperture, and the coarse location cell from originals whose summary
    /// does not carry them yet. It runs after the other summary repairs, one membership shard per
    /// background job, and publishes each committed shard to the in-memory index so facets fill in
    /// while the user browses. The still-nil summaries are the durable resume marker: a package
    /// open that is interrupted simply continues at the remaining shards next time.
    private func startCaptureMetadataBackfill() {
        guard !didStartCaptureMetadataBackfill, !isShuttingDown else { return }
        let shards = Set(
            queryController.index.entries
                .filter { $0.deletedRevision == nil
                    && PortableLibraryPackage.needsCaptureMetadata($0.summary) }
                .map { PortableLibraryPackage.shard(for: $0.assetID) }
        ).sorted()
        guard !shards.isEmpty else { return }
        didStartCaptureMetadataBackfill = true
        captureMetadataBackfillShards = shards
        nextCaptureMetadataBackfillShard = 0

        if scheduler != nil {
            enqueueNextCaptureMetadataBackfillShard()
            return
        }
        let package = self.package
        let lease = self.lease
        detachedCaptureMetadataBackfillTask = Task.detached { [weak self] in
            for shard in shards {
                guard !Task.isCancelled else { return }
                do {
                    let entries = try package.repairCaptureMetadataShard(
                        shard, lease: lease, isCancelled: { Task.isCancelled }
                    )
                    await MainActor.run { [weak self] in
                        self?.publishCaptureMetadataBackfill(entries)
                    }
                } catch is CancellationError {
                    return
                } catch {
                    continue
                }
                try? await Task.sleep(for: .milliseconds(1))
            }
        }
    }

    private func enqueueNextCaptureMetadataBackfillShard() {
        guard !isShuttingDown, let scheduler,
              captureMetadataBackfillShards.indices.contains(nextCaptureMetadataBackfillShard)
        else { return }
        let shard = captureMetadataBackfillShards[nextCaptureMetadataBackfillShard]
        let package = self.package
        let lease = self.lease
        let now = clock.now
        _ = scheduler.enqueuePackageIO(
            id: captureMetadataBackfillJobID,
            lane: .maintenance,
            priority: .background,
            onTerminal: { [weak self] outcome in
                guard let self, !self.isShuttingDown, outcome != .cancelled else { return }
                self.nextCaptureMetadataBackfillShard += 1
                self.enqueueNextCaptureMetadataBackfillShard()
            },
            operation: { [weak self] in
                do {
                    let entries = try package.repairCaptureMetadataShard(
                        shard, lease: lease, now: now(), isCancelled: { Task.isCancelled }
                    )
                    await MainActor.run { [weak self] in
                        self?.publishCaptureMetadataBackfill(entries)
                    }
                } catch {
                    // A bad shard does not stop later ones; its nil summaries retry on next open.
                }
            }
        )
    }

    private func publishCaptureMetadataBackfill(_ entries: [LibraryIndexEntry]) {
        guard !entries.isEmpty, !isShuttingDown else { return }
        _ = try? applyIndexDelta(.init(upserts: entries))
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
        // Queued culling changes are user data: write them before the lease goes away.
        await flushPendingLibraryState()
        guard !isShuttingDown else { return }
        // The flush may have queued a projection write that a scheduler-wide cancellation or the
        // cancellation below would drop; persist the current projection after cancelling so the
        // next open does not serve pre-flush values.
        isShuttingDown = true
        heartbeatTask?.cancel()
        heartbeatTask = nil
        await scheduler?.cancelAndWait(id: heartbeatJobID)
        for jobID in activeImportJobIDs {
            await scheduler?.cancelAndWait(id: jobID)
        }
        activeImportJobIDs.removeAll()
        await scheduler?.cancelAndWait(id: libraryStateJobID)
        await scheduler?.cancelAndWait(id: virtualCopyJobID)
        await scheduler?.cancelAndWait(id: removalJobID)
        await scheduler?.cancelAndWait(id: indexWriteJobID)
        if libraryStateIndexWriteMayBeLost { try? queryController.index.write(to: indexURL) }
        await scheduler?.cancelAndWait(id: indexLoadJobID)
        await scheduler?.cancelAndWait(id: presentedAspectRatioRepairJobID)
        for jobID in pendingFingerprintRepairs.values {
            await scheduler?.cancelAndWait(id: jobID)
        }
        pendingFingerprintRepairs.removeAll()
        await scheduler?.cancelAndWait(id: sourceFingerprintBackfillJobID)
        await scheduler?.cancelAndWait(id: captureMetadataBackfillJobID)
        detachedIndexLoadTask?.cancel()
        await detachedIndexLoadTask?.value
        detachedIndexLoadTask = nil
        detachedPresentedAspectRatioRepairTask?.cancel()
        await detachedPresentedAspectRatioRepairTask?.value
        detachedPresentedAspectRatioRepairTask = nil
        detachedSourceFingerprintBackfillTask?.cancel()
        await detachedSourceFingerprintBackfillTask?.value
        detachedSourceFingerprintBackfillTask = nil
        detachedCaptureMetadataBackfillTask?.cancel()
        await detachedCaptureMetadataBackfillTask?.value
        detachedCaptureMetadataBackfillTask = nil
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
    var libraryID: UUID { package.manifest.libraryID }

    /// Resolve hinted IDs only against the already-published membership projection. This reads
    /// neither asset records nor originals and naturally drops IDs removed from the package.
    func launchHintAssets(for ids: [PortablePhotoAssetID]) -> [PhotoAsset] {
        ids.compactMap { id in
            guard let entry = queryController.index.entry(for: id), entry.deletedRevision == nil else {
                return nil
            }
            return try? browsingAssetForLaunchHint(entry)
        }
    }

    func totalCount(query: LibraryQuery = .all) -> Int {
        page(at: 0, query: query).totalCount
    }

    /// A value snapshot of the query controller for index-side work off the main actor.
    func facetCounts(query: LibraryQuery) async -> LibraryFacetCounts {
        let controller = queryController
        return await Task.detached { controller.facetCounts(query: query) }.value
    }

    func page(at pageIndex: Int, query: LibraryQuery = .all) -> LibraryQueryPage {
        if pageIndex == 0, query == .all, let startupFirstPage {
            return startupFirstPage
        }
        return queryController.page(at: pageIndex, query: query)
    }

    /// Single selection authority for the portable path. Grid, filmstrip, keyboard navigation,
    /// culling, and open all route through these UUID-keyed values; ImageCollection mirrors them
    /// for presentation but never diverges as an independent selection store.
    var portableSelectedIDs: Set<PortablePhotoAssetID> { queryController.selectedIDs }
    var portableActiveID: PortablePhotoAssetID? { queryController.activeID }

    func select(_ assetID: PortablePhotoAssetID, additive: Bool = false) {
        startupFirstPage = nil
        queryController.select(assetID, additive: additive)
    }

    func setPortableSelection(_ assetIDs: [PortablePhotoAssetID], activeID: PortablePhotoAssetID?) {
        startupFirstPage = nil
        queryController.setSelection(assetIDs, activeID: activeID)
    }

    func togglePortableSelection(_ assetID: PortablePhotoAssetID) {
        startupFirstPage = nil
        queryController.toggleSelection(assetID)
    }

    func clearPortableSelection() {
        startupFirstPage = nil
        queryController.clearSelection()
    }

    func selectAllPortable(query: LibraryQuery = .all) {
        startupFirstPage = nil
        queryController.selectAll(query: query)
    }

    /// Windowed browsing projection for grid/filmstrip. Returns the assets for exactly one page
    /// plus the total match count for that query, so callers can bound retained Items to the
    /// visible window while keeping stable `portable:<uuid>` identity across page changes.
    func browsingWindow(
        pageIndex: Int, query: LibraryQuery = .all
    ) throws -> (assets: [PhotoAsset], totalCount: Int, pageSize: Int) {
        let page = self.page(at: pageIndex, query: query)
        let assets = try page.items.map { try browsingAsset(for: $0) }
        return (assets, page.totalCount, page.pageSize)
    }

    /// Rebuild the disposable projection after a package transaction. Selection is retained by
    /// opaque UUID, never by a page or array offset.
    @discardableResult
    func refreshIndex() throws -> LibraryIndexProjection {
        startupFirstPage = nil
        let projection = try LibraryIndexProjection(package: package)
        try projection.write(to: indexURL)
        indexGeneration &+= 1
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
        startupFirstPage = nil
        let projection = try queryController.index.applying(delta)
        let selectedAssetIDs = queryController.selectedIDs
        let activeAssetID = queryController.activeID
        indexGeneration &+= 1
        queryController = LibraryQueryController(
            index: projection,
            pageSize: queryController.pageSize,
            selectedAssetIDs: selectedAssetIDs,
            activeAssetID: activeAssetID
        )
        importCatalog = nil
        if !delta.presentedAspectRatioUpdates.isEmpty {
            onPresentedAspectRatioUpdates?(delta.presentedAspectRatioUpdates)
        }
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
            Self.writeIndex(projection, to: indexURL) { [weak self] message in
                Task { @MainActor [weak self] in self?.onIndexWriteFailure?(message) }
            }
            return
        }
        let generation = indexWriteGeneration.publish()
        _ = scheduler.enqueuePackageIO(
            id: indexWriteJobID,
            lane: .indexRebuild,
            operation: { [weak self, indexWriteGeneration, projection, indexURL] in
                guard indexWriteGeneration.isCurrent(generation), !Task.isCancelled else { return }
                Self.writeIndex(projection, to: indexURL) { [weak self] message in
                    Task { @MainActor [weak self] in self?.onIndexWriteFailure?(message) }
                }
            }
        )
    }

    private func reportIndexWriteFailure(_ error: Error) {
        let message = error.localizedDescription
        KromoraObservability.event(.libraryIndexWriteFailed, detail: message)
        onIndexWriteFailure?(message)
    }

    /// The index is disposable and repaired from membership on the next open, so a failed write is
    /// not fatal, but it must not disappear silently.
    nonisolated private static func writeIndex(
        _ projection: LibraryIndexProjection, to url: URL,
        onFailure: @escaping @Sendable (String) -> Void
    ) {
        do {
            try projection.write(to: url)
        } catch {
            onFailure(error.localizedDescription)
            KromoraObservability.event(.libraryIndexWriteFailed, detail: error.localizedDescription)
        }
    }

    /// Starts an import without performing package I/O on the main actor. The returned handle is
    /// deliberately small: callers consume its progress stream and await its final result, while
    /// the worker owns all source copies, hashes, fsyncs, commits, and rollback.
    func startImportURLs(
        _ urls: [URL],
        duplicatePolicy: PortablePackageDuplicatePolicy = .skip,
        access: [SecurityScopedResourceAccess] = []
    ) throws -> PortablePackageImportHandle {
        try startImport(
            sources: urls.map { .init(url: $0) },
            duplicatePolicy: duplicatePolicy,
            catalogState: nil,
            access: access
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
            catalogState: state,
            access: []
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

    /// Makes sources committed by a running import visible to queries. Upserts are idempotent, so
    /// the final result delta re-applying the same entries is harmless.
    @discardableResult
    private func publishCommittedImportEntries(from buffer: PortablePackageCommitBuffer) -> Int {
        let entries = buffer.drain()
        guard !entries.isEmpty else { return 0 }
        do {
            _ = try applyIndexDelta(LibraryIndexDelta(upserts: entries))
        } catch {
            reportIndexWriteFailure(error)
            return 0
        }
        return entries.count
    }

    private func appendPendingImportDelta(_ delta: LibraryIndexDelta) {
        pendingImportIndexDelta = pendingImportIndexDelta.merging(delta)
    }

    private func startImport(
        sources: [PortablePackageImportSource],
        duplicatePolicy: PortablePackageDuplicatePolicy,
        catalogState: ImportCatalogState?,
        access: [SecurityScopedResourceAccess]
    ) throws -> PortablePackageImportHandle {
        var transferredAccess = false
        defer {
            if !transferredAccess { access.forEach { $0.release() } }
        }
        guard !isShuttingDown else { throw PortablePackageLeaseError.notOwner }
        guard !lostDuringSession else { throw PortablePackageLeaseError.lostDuringSession }
        guard let scheduler else { throw PortablePackageImportWorkerError.schedulerUnavailable }

        let progressSink = PortablePackageImportProgressSink()
        let progress = AsyncStream<PortablePackageImportProgress>(bufferingPolicy: .bufferingNewest(1)) { continuation in
            progressSink.install(continuation)
        }
        let resultBox = PortablePackageImportResultBox()
        let workerResultBox = PortablePackageImportResultBox()
        let cancellation = PortablePackageImportCancellation()
        let jobID = ImageWorkScheduler.JobID(
            "portable-package-import-\(lease.ownerID.uuidString)-\(UUID().uuidString)"
        )
        // Deferred-catalog batches (Photos) publish one index delta per batch, so they leave live
        // publication off. Every other import makes each committed source queryable immediately.
        let commitBuffer = PortablePackageCommitBuffer()
        let publishesLive = catalogState == nil
        let handle = PortablePackageImportHandle(
            progress: progress,
            resultBox: resultBox,
            cancellation: cancellation,
            cancelAction: { scheduler.cancel(id: jobID) },
            commitPublisher: { [weak self] in
                guard publishesLive else { return 0 }
                return self?.publishCommittedImportEntries(from: commitBuffer) ?? 0
            }
        )
        activeImportJobIDs.insert(jobID)
        let package = self.package
        let lease = self.lease
        let now = self.clock.now
        let admitted = scheduler.enqueuePackageIO(
            id: jobID,
            lane: .importCopyHash,
            onTerminal: { [weak self, weak handle, progressSink, access, commitBuffer] outcome in
                access.forEach { $0.release() }
                guard let self else { return }
                self.activeImportJobIDs.remove(jobID)
                // Anything committed but not yet published must reach the index even when the
                // import failed or was cancelled; the package already holds those assets.
                if publishesLive { self.publishCommittedImportEntries(from: commitBuffer) }
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
                            // The package remains canonical; rebuild the disposable index now so the
                            // grid cannot go stale, and record the failure if that fails too.
                            self.reportIndexWriteFailure(error)
                            do { _ = try self.refreshIndex() } catch {
                                self.reportIndexWriteFailure(error)
                            }
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
                            committed: { commitBuffer.append($0) },
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
        transferredAccess = true
        return handle
    }

    /// "IMG_1370.DNG" becomes "IMG_1370 — Copy.DNG", so the copy keeps a real extension.
    nonisolated static func virtualCopyDisplayName(for sourceFilename: String) -> String {
        let url = URL(fileURLWithPath: sourceFilename)
        let base = url.deletingPathExtension().lastPathComponent
        let stem = base.isEmpty ? "Copy" : base
        let ext = url.pathExtension
        if ext.isEmpty { return "\(stem) — Copy" }
        return "\(stem) — Copy.\(ext)"
    }

    @discardableResult
    func importURLs(
        _ urls: [URL],
        duplicatePolicy: PortablePackageDuplicatePolicy = .skip,
        access: [SecurityScopedResourceAccess] = [],
        isCancelled: @Sendable () -> Bool = { false },
        progress: @Sendable (PortablePackageImportProgress) -> Void = { _ in }
    ) throws -> PortablePackageImportResult {
        defer { access.forEach { $0.release() } }
        return try importPackageSources(
            urls.map { PortablePackageImportSource(url: $0) },
            duplicatePolicy: duplicatePolicy,
            isCancelled: isCancelled,
            progress: progress
        )
    }

    @discardableResult
    func importPackageSources(
        _ sources: [PortablePackageImportSource],
        duplicatePolicy: PortablePackageDuplicatePolicy = .skip,
        isCancelled: @Sendable () -> Bool = { false },
        progress: @Sendable (PortablePackageImportProgress) -> Void = { _ in }
    ) throws -> PortablePackageImportResult {
        try ensureWritableLease()
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

    /// The independent identity of a freshly created virtual copy.
    struct VirtualCopyResult: Sendable {
        let assetID: PortablePhotoAssetID
        let identity: PortablePhotoIdentity
        let displayName: String
        let indexDelta: LibraryIndexDelta
    }

    private final class VirtualCopyOutcome: Sendable {
        private let value = OSAllocatedUnfairLock<Result<VirtualCopyResult, Error>?>(initialState: nil)
        func store(_ result: Result<VirtualCopyResult, Error>) { value.withLock { $0 = result } }
        func take() -> Result<VirtualCopyResult, Error>? { value.withLock { $0 } }
    }

    /// Copies one managed original into a new package asset, then records its source relationship.
    /// The copy, content hash and relationship transaction run on the package-I/O lane (inline
    /// for a session without a scheduler); only the incremental index update runs here. The
    /// caller persists the copied edit document under the returned independent identity.
    func createVirtualCopy(of sourceID: PortablePhotoAssetID) async throws -> VirtualCopyResult {
        try ensureWritableLease()
        let package = self.package
        let lease = self.lease
        let now = clock.now
        let result: VirtualCopyResult
        if let scheduler {
            let outcome = VirtualCopyOutcome()
            result = try await withCheckedThrowingContinuation { continuation in
                scheduler.enqueuePackageIO(
                    id: virtualCopyJobID,
                    lane: .importCopyHash,
                    onTerminal: { terminal in
                        // A copy that already finished is kept even if shutdown cancelled the
                        // job: the package holds it and the caller must see the result.
                        if let finished = outcome.take() {
                            continuation.resume(with: finished)
                        } else if terminal == .rejected {
                            continuation.resume(throwing: PortablePackageImportWorkerError.notAdmitted)
                        } else {
                            continuation.resume(throwing: CancellationError())
                        }
                    },
                    operation: {
                        outcome.store(Result {
                            try Self.writeVirtualCopy(of: sourceID, package: package, lease: lease, now: now)
                        })
                    }
                )
            }
        } else {
            result = try Self.writeVirtualCopy(of: sourceID, package: package, lease: lease, now: now)
        }
        if !isShuttingDown { _ = try applyIndexDelta(result.indexDelta) }
        return result
    }

    nonisolated private static func writeVirtualCopy(
        of sourceID: PortablePhotoAssetID,
        package: PortableLibraryPackage,
        lease: PortablePackageLease,
        now: @escaping @Sendable () -> Date
    ) throws -> VirtualCopyResult {
        do {
            let sourceRecord = try package.readAssetRecord(for: sourceID)
            let sourceURL = try package.embeddedSourceURL(for: sourceRecord)
            // Keep the extension at the end. "IMG_1370.DNG — Copy" has no path extension, so the
            // browsing locator and RAW classifier both miss the embedded file.
            let displayName = virtualCopyDisplayName(for: sourceURL.lastPathComponent)
            let imported = try package.importSources(
                [.init(url: sourceURL, name: displayName)],
                lease: lease,
                options: .init(duplicatePolicy: .importAnyway),
                now: now
            )
            guard let copy = imported.imported.first else {
                throw PortablePackageError.invalidVirtualCopy("the source original could not be copied")
            }
            try lease.withWriterMutationLock {
                try package.markVirtualCopy(
                    copy.assetID, of: sourceID, displayName: displayName, lease: lease, now: now()
                )
            }
            let copyRecord = try package.readAssetRecord(for: copy.assetID)
            let shard = try package.readMembershipShard(PortableLibraryPackage.shard(for: copy.assetID))
            var delta = imported.indexDelta
            if let entry = shard.entries.first(where: { $0.assetID == copy.assetID }) {
                delta = delta.merging(.init(upserts: [.init(from: entry)]))
            }
            return VirtualCopyResult(
                assetID: copy.assetID, identity: copyRecord.identity,
                displayName: displayName, indexDelta: delta
            )
        } catch {
            if error is PortablePackageLeaseError { throw PortablePackageLeaseError.lostDuringSession }
            throw error
        }
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

    /// Test seam awaited by `materializedAsset(for:)` before the worker read begins. It lets a
    /// lifecycle test hold a cancellation-oblivious resolution open at a deterministic point.
    var materializationGate: (@Sendable (PortablePhotoAssetID) async -> Void)?

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
    /// Browsing assets for query items the caller does not already hold, so an incremental window
    /// merge materializes only what is new.
    func browsingAssets(for items: [LibraryQueryItem]) throws -> [PhotoAsset] {
        try items.map { try browsingAsset(for: $0) }
    }

    /// Browsing assets for specific IDs, in the order given. IDs no longer in the published index
    /// are dropped; only the requested entries are materialized.
    func browsingAssets(forIDs ids: [PortablePhotoAssetID]) throws -> [PhotoAsset] {
        try ids.compactMap { id in
            guard let entry = queryController.index.entry(for: id), entry.deletedRevision == nil
            else { return nil }
            return try browsingAsset(for: LibraryQueryItem(
                assetID: id, recordPath: entry.recordPath, summary: entry.summary,
                isSelected: queryController.selectedIDs.contains(id)
            ))
        }
    }

    func browsingAssets(query: LibraryQuery = .all) throws -> [PhotoAsset] {
        var assets: [PhotoAsset] = []
        var pageIndex = 0
        while true {
            let page = self.page(at: pageIndex, query: query)
            assets.append(contentsOf: try page.items.map { try browsingAsset(for: $0) })
            guard page.hasNextPage else { return assets }
            pageIndex += 1
        }
    }

    /// The first visible window of the browsing projection. Grid and filmstrip paint from this
    /// page; stable `PhotoAssetID` identity (`portable:<uuid>`) keeps selection coherent as
    /// further pages fault in.
    func browsingAssets(pageIndex: Int, query: LibraryQuery = .all) throws -> [PhotoAsset] {
        return try page(at: pageIndex, query: query).items.map { try browsingAsset(for: $0) }
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

    /// Resolve the selected browsing projection against its durable record. New summaries already
    /// carry the persisted identity; legacy summaries use a placeholder until this record read
    /// resolves the fingerprint and repairs the summary if needed.
    func materializedAsset(for assetID: PortablePhotoAssetID) async throws -> PhotoAsset {
        guard let entry = queryController.index.entry(for: assetID) else {
            throw CocoaError(.fileNoSuchFile)
        }
        assetRecordReadObserver?(assetID)
        await materializationGate?(assetID)
        let summary = entry.summary
        let package = self.package
        let resolved = try await Task.detached {
            let record = try package.readAssetRecord(for: assetID)
            let sourceURL = try package.embeddedSourceURL(for: record)
            let source = PhotoAssetSource(
                url: sourceURL,
                id: PhotoAssetID(rawValue: "portable:\(assetID.raw)"),
                data: nil,
                bookmarkData: nil,
                portableIdentity: record.identity,
                sourceChangeSignature: record.sourceChangeSignature
            )
            assert(
                source.portableIdentity.sourceFingerprint == record.identity.sourceFingerprint,
                "A materialized asset must retain the fingerprint persisted in its record."
            )
            return PhotoAsset(
                source: source,
                filename: summary.displayName,
                fileType: sourceURL.pathExtension,
                metadata: PhotoAssetMetadata(
                    dimensions: summary.dimensions,
                    captureDate: summary.captureDate,
                    cameraMake: summary.cameraMake,
                    cameraModel: summary.cameraModel,
                    lens: summary.lens
                ),
                libraryState: PhotoAssetLibraryState(
                    rating: summary.rating ?? 0,
                    flag: PhotoFlag(rawValue: summary.flag ?? "none") ?? .none
                ),
                presentedAspectRatio: summary.presentedAspectRatio
            )
        }.value
        let fingerprint = resolved.source.portableIdentity.sourceFingerprint
        if summary.sourceFingerprint != fingerprint {
            repairSourceFingerprintOnOpen(for: assetID, to: fingerprint)
        }
        return resolved
    }

    /// Test seam awaited inside the off-main open-time fingerprint repair, before its write.
    var fingerprintRepairGate: (@Sendable (PortablePhotoAssetID) async -> Void)?

    nonisolated private static let repairLog = Logger(
        subsystem: "com.kromora.app", category: "portable-library")

    /// Persists a legacy summary's resolved fingerprint without making the open wait for the
    /// durable write. With a scheduler the write runs on the package-I/O lane and the index entry
    /// is updated when it commits; a repeat open of the same asset coalesces onto the pending job.
    /// A session without a scheduler repairs inline. Failures are logged and never fail the open.
    private func repairSourceFingerprintOnOpen(
        for assetID: PortablePhotoAssetID, to fingerprint: PortablePhotoSourceFingerprint
    ) {
        let package = self.package
        let lease = self.lease
        let clock = self.clock
        guard let scheduler else {
            do {
                if let updated = try package.replaceSourceFingerprint(
                    for: assetID, with: fingerprint, lease: lease, now: clock.now()
                ) {
                    try applyIndexDelta(.init(upserts: [updated]))
                }
            } catch {
                Self.repairLog.error(
                    "Source fingerprint repair failed for \(assetID.raw, privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
            }
            return
        }
        guard !isShuttingDown, pendingFingerprintRepairs[assetID] == nil else { return }
        let jobID = ImageWorkScheduler.JobID(
            "portable-package-source-fingerprint-repair-\(assetID.raw)-\(lease.ownerID.uuidString)"
        )
        pendingFingerprintRepairs[assetID] = jobID
        let gate = fingerprintRepairGate
        let admitted = scheduler.enqueuePackageIO(
            id: jobID,
            lane: .maintenance,
            priority: .background,
            onTerminal: { [weak self] _ in self?.pendingFingerprintRepairs[assetID] = nil },
            operation: { [weak self] in
                await gate?(assetID)
                guard !Task.isCancelled else { return }
                do {
                    guard let updated = try package.replaceSourceFingerprint(
                        for: assetID, with: fingerprint, lease: lease, now: clock.now()
                    ) else { return }
                    await MainActor.run {
                        guard let self, !self.isShuttingDown else { return }
                        _ = try? self.applyIndexDelta(.init(upserts: [updated]))
                    }
                } catch {
                    Self.repairLog.error(
                        "Source fingerprint repair failed for \(assetID.raw, privacy: .public): \(error.localizedDescription, privacy: .public)"
                    )
                }
            }
        )
        if !admitted { pendingFingerprintRepairs[assetID] = nil }
    }

    private func browsingAsset(for item: LibraryQueryItem) throws -> PhotoAsset {
        let summary = item.summary
        // Names such as "IMG_1370.DNG — Copy" have no path extension. The derived
        // Original/ filename is then not the embedded file, so resolve the record.
        let embeddedURL: URL
        if URL(fileURLWithPath: summary.displayName).pathExtension.isEmpty {
            embeddedURL = try resolveEmbeddedSourceURL(for: item.assetID)
        } else {
            embeddedURL = try package.browsingOriginalURL(
                for: item.assetID, displayName: summary.displayName
            )
        }
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
            libraryState: state,
            presentedAspectRatio: summary.presentedAspectRatio
        )
    }

    /// Hint reads require only identity, geometry, and the package-derived locator. In particular,
    /// do not fall back to opening an asset record when a display name has no extension.
    private func browsingAssetForLaunchHint(_ entry: LibraryIndexEntry) throws -> PhotoAsset {
        let summary = entry.summary
        let embeddedURL = try package.browsingOriginalURL(
            for: entry.assetID, displayName: summary.displayName
        )
        let source = PhotoAssetSource(
            browsingPortableAsset: entry.assetID, embeddedURL: embeddedURL, summary: summary
        )
        let metadata = PhotoAssetMetadata(
            dimensions: summary.dimensions, captureDate: summary.captureDate,
            cameraMake: summary.cameraMake, cameraModel: summary.cameraModel, lens: summary.lens
        )
        return PhotoAsset(
            source: source, filename: summary.displayName,
            fileType: embeddedURL.pathExtension, metadata: metadata,
            libraryState: PhotoAssetLibraryState(
                rating: summary.rating ?? 0,
                flag: PhotoFlag(rawValue: summary.flag ?? "none") ?? .none
            ), presentedAspectRatio: summary.presentedAspectRatio
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
                libraryState: state,
                presentedAspectRatio: summary.presentedAspectRatio
            )
        }
    }

    /// Replace a source fingerprint and publish the returned membership value to browsing. The
    /// package operation commits the record and summary together; this completes the projection
    /// side of that source replacement.
    @discardableResult
    func replaceSourceFingerprint(
        for assetID: PortablePhotoAssetID,
        with fingerprint: PortablePhotoSourceFingerprint
    ) throws -> LibraryIndexEntry? {
        try ensureWritableLease()
        let entry = try package.replaceSourceFingerprint(
            for: assetID, with: fingerprint, lease: lease, now: clock.now()
        )
        if let entry { _ = try applyIndexDelta(.init(upserts: [entry])) }
        return entry
    }

    @discardableResult
    func removeFromLibrary(_ assetID: PortablePhotoAssetID) throws -> PortablePackageRemovalResult {
        try ensureWritableLease()
        let package = self.package
        let lease = self.lease
        let now = clock.now()
        let result: PortablePackageRemovalResult
        do {
            result = try lease.withWriterMutationLock {
                try package.removeFromLibrary(assetID, lease: lease, now: now)
            }
        } catch PortablePackageTrashError.alreadyRemoved(let removedID) {
            // A prior removal committed its tombstone but did not finish updating the projection.
            // Reconcile the index so the item leaves the grid, then let the caller finish cleanup.
            _ = try applyIndexDelta(.init(removals: [assetID]))
            throw PortablePackageTrashError.alreadyRemoved(removedID)
        } catch {
            throw ensureLeaseError(error)
        }
        _ = try applyIndexDelta(.init(removals: [assetID]))
        return result
    }

    private final class RemovalOutcome: Sendable {
        private let value = OSAllocatedUnfairLock<Result<PortablePackageRemovalResult, Error>?>(
            initialState: nil
        )
        func store(_ result: Result<PortablePackageRemovalResult, Error>) { value.withLock { $0 = result } }
        func take() -> Result<PortablePackageRemovalResult, Error>? { value.withLock { $0 } }
    }

    /// Remove one asset with the quarantine/tombstone transaction on the package-I/O lane (inline
    /// for a session without a scheduler); only the index update runs here. Callers must not
    /// overlap calls. A removal that already committed is reported even if shutdown cancelled the
    /// job; one that never started throws `CancellationError`, so no item is left half-removed.
    @discardableResult
    func removeFromLibraryOffMain(_ assetID: PortablePhotoAssetID) async throws
        -> PortablePackageRemovalResult
    {
        try ensureWritableLease()
        let package = self.package
        let lease = self.lease
        let now = clock.now
        let result: Result<PortablePackageRemovalResult, Error>
        if let scheduler {
            let outcome = RemovalOutcome()
            result = await withCheckedContinuation { continuation in
                scheduler.enqueuePackageIO(
                    id: removalJobID,
                    lane: .maintenance,
                    priority: .packageIO,
                    onTerminal: { terminal in
                        if let finished = outcome.take() {
                            continuation.resume(returning: finished)
                        } else if terminal == .rejected {
                            continuation.resume(
                                returning: .failure(PortablePackageImportWorkerError.notAdmitted)
                            )
                        } else {
                            continuation.resume(returning: .failure(CancellationError()))
                        }
                    },
                    operation: {
                        outcome.store(Result {
                            try Self.writeRemoval(assetID, package: package, lease: lease, now: now())
                        })
                    }
                )
            }
        } else {
            result = Result { try Self.writeRemoval(assetID, package: package, lease: lease, now: now()) }
        }
        switch result {
        case .success(let removal):
            if !isShuttingDown { _ = try applyIndexDelta(.init(removals: [assetID])) }
            return removal
        case .failure(PortablePackageTrashError.alreadyRemoved(let removedID)):
            // A prior removal committed its tombstone but did not finish updating the projection.
            if !isShuttingDown { _ = try applyIndexDelta(.init(removals: [assetID])) }
            throw PortablePackageTrashError.alreadyRemoved(removedID)
        case .failure(let error):
            throw ensureLeaseError(error)
        }
    }

    nonisolated private static func writeRemoval(
        _ assetID: PortablePhotoAssetID,
        package: PortableLibraryPackage,
        lease: PortablePackageLease,
        now: Date
    ) throws -> PortablePackageRemovalResult {
        try lease.withWriterMutationLock {
            try package.removeFromLibrary(assetID, lease: lease, now: now)
        }
    }

    /// Mirror a membership entry a package transaction already committed (an edit's presented
    /// geometry) into the disposable projection. The package stays canonical; this only keeps the
    /// query index from serving the previous value until the next rebuild.
    func mirrorCommittedMemberships(from store: EditDocumentStore) async {
        await store.setMembershipObserver { [weak self] entry in
            Task { @MainActor in self?.applyCommittedMembership(entry) }
        }
    }

    func applyCommittedMembership(_ entry: PortablePackageMembershipEntry) {
        guard !entry.isTombstone else { return }
        _ = try? applyIndexDelta(.init(upserts: [.init(from: entry)]))
    }

    /// One culling change for `updateLibraryState(_:)`.
    struct LibraryStateUpdate: Sendable, Equatable {
        let assetID: PortablePhotoAssetID
        let rating: Int
        let flag: PhotoFlag
    }

    /// Persist the package-owned catalog summary used by filtering and sorting. The presentation
    /// bridge may mirror this state for the current window, but it must not become the durable
    /// authority for a portable library.
    func updateLibraryState(
        for assetID: PortablePhotoAssetID,
        rating: Int,
        flag: PhotoFlag
    ) throws {
        try updateLibraryState([.init(assetID: assetID, rating: rating, flag: flag)])
    }

    /// Synchronously persist a batch with one package transaction per affected membership shard.
    func updateLibraryState(_ updates: [LibraryStateUpdate]) throws {
        try ensureWritableLease()
        let package = self.package
        let lease = self.lease
        let now = clock.now()
        let outcome = Self.commitLibraryState(updates, package: package, lease: lease, now: now)
        // Shards that committed are durable even when another shard failed; mirror them first.
        if !outcome.entries.isEmpty { _ = try applyIndexDelta(.init(upserts: outcome.entries)) }
        if let error = outcome.error { throw ensureLeaseError(error) }
    }

    /// Queue culling changes for a serial, off-main write. Changes for the same asset coalesce
    /// last-write-wins while an earlier batch is still writing, so a later rating can never be
    /// overwritten by an earlier one. A session without a scheduler writes inline.
    func enqueueLibraryStateUpdates(
        _ updates: [LibraryStateUpdate],
        onFailure: @escaping @MainActor (Error) -> Void
    ) {
        guard !updates.isEmpty else { return }
        for update in updates {
            pendingLibraryStateUpdates[update.assetID] = update
            // The newer intent replaces a failed one; a retry must not resurrect the old value.
            failedLibraryStateUpdates[update.assetID] = nil
        }
        libraryStateFailureHandler = onFailure
        if !isDrainingLibraryState { startLibraryStateDrain() }
    }

    /// Suspends until every queued culling change has been written or has failed. Changes that
    /// failed earlier are retried first. Used before quit so a rating made just before ⌘Q is
    /// durable; a failure means some changes are still dirty, so the caller can offer a retry.
    @discardableResult
    func flushPendingLibraryState() async -> PersistenceFlushResult {
        if !isDrainingLibraryState, !failedLibraryStateUpdates.isEmpty {
            startLibraryStateDrain()
        }
        if isDrainingLibraryState || !pendingLibraryStateUpdates.isEmpty {
            await withCheckedContinuation { libraryStateIdleWaiters.append($0) }
        }
        let unsaved = failedLibraryStateUpdates.count + pendingLibraryStateUpdates.count
        guard unsaved > 0 else { return .success }
        let noun = unsaved == 1 ? "photo's rating or flag" : "photos' ratings or flags"
        return .failure("Kromora could not save \(unsaved) \(noun) to the library.")
    }

    /// Abandons culling changes after the user chooses Quit Without Saving. Wait for an active
    /// write to settle first so its completion cannot restore a failed batch after it is cleared.
    func discardPendingLibraryState() async {
        if isDrainingLibraryState {
            await withCheckedContinuation { libraryStateIdleWaiters.append($0) }
        }
        pendingLibraryStateUpdates.removeAll()
        failedLibraryStateUpdates.removeAll()
    }

    private func startLibraryStateDrain() {
        // Retry earlier failures with this drain; anything newer already in the queue wins.
        for (assetID, update) in failedLibraryStateUpdates
        where pendingLibraryStateUpdates[assetID] == nil {
            pendingLibraryStateUpdates[assetID] = update
        }
        failedLibraryStateUpdates.removeAll()
        let batch = Array(pendingLibraryStateUpdates.values)
        pendingLibraryStateUpdates.removeAll()
        guard !batch.isEmpty else { finishLibraryStateDrain(); return }
        isDrainingLibraryState = true

        guard let scheduler else {
            completeLibraryStateBatch(batch, outcome: writeLibraryStateInline(batch))
            return
        }
        let package = self.package
        let lease = self.lease
        let now = clock.now
        let box = LibraryStateWriteResult()
        scheduler.enqueuePackageIO(
            id: libraryStateJobID,
            lane: .maintenance,
            priority: .packageIO,
            onTerminal: { [weak self] outcome in
                guard let self else { return }
                switch outcome {
                case .completed:
                    if let result = box.take() {
                        self.completeLibraryStateBatch(batch, outcome: result)
                    } else {
                        self.writeLibraryStateOffMain(batch)
                    }
                case .cancelled, .evicted, .rejected:
                    // The change is user data: never drop it because the lane was full or the
                    // scheduler was cancelled. Keep a result the operation already produced;
                    // otherwise retry off-main because terminal callbacks run on the main actor.
                    if let result = box.take() {
                        self.completeLibraryStateBatch(batch, outcome: result)
                    } else {
                        self.writeLibraryStateOffMain(batch)
                    }
                }
            },
            operation: {
                box.store(
                    Self.commitLibraryState(batch, package: package, lease: lease, now: now())
                )
            }
        )
    }

    private func writeLibraryStateInline(_ batch: [LibraryStateUpdate])
        -> LibraryStateWriteOutcome
    {
        Self.commitLibraryState(batch, package: package, lease: lease, now: clock.now())
    }

    /// Retry a scheduler job that never entered its package-I/O operation without moving durable
    /// package work onto the main actor. The session stays draining until this task reports back.
    private func writeLibraryStateOffMain(_ batch: [LibraryStateUpdate]) {
        let package = self.package
        let lease = self.lease
        let now = clock.now
        Task.detached(priority: .utility) { [weak self] in
            let result = Self.commitLibraryState(
                batch, package: package, lease: lease, now: now()
            )
            await self?.completeLibraryStateBatch(batch, outcome: result)
        }
    }

    private func completeLibraryStateBatch(
        _ batch: [LibraryStateUpdate], outcome: LibraryStateWriteOutcome?
    ) {
        if let outcome {
            if !outcome.entries.isEmpty {
                libraryStateIndexWriteMayBeLost = true
                do { _ = try applyIndexDelta(.init(upserts: outcome.entries)) } catch {
                    libraryStateFailureHandler?(error)
                }
            }
            // Committed shards are already out of the batch. Failed ones stay dirty unless a newer
            // intent for the asset is queued, or the asset no longer exists in the library.
            for update in outcome.failed where pendingLibraryStateUpdates[update.assetID] == nil {
                if outcome.missingAssetIDs.contains(update.assetID) { continue }
                failedLibraryStateUpdates[update.assetID] = update
            }
            if let error = outcome.error {
                let mapped = ensureLeaseError(error)
                if mapped is PortablePackageLeaseError { lostDuringSession = true }
                libraryStateFailureHandler?(mapped)
            }
        }
        if pendingLibraryStateUpdates.isEmpty {
            finishLibraryStateDrain()
        } else {
            startLibraryStateDrain()
        }
    }

    private func finishLibraryStateDrain() {
        isDrainingLibraryState = false
        if !pendingLibraryStateUpdates.isEmpty, !isShuttingDown {
            startLibraryStateDrain()
            return
        }
        let waiters = libraryStateIdleWaiters
        libraryStateIdleWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
    }

    /// Thread-safe result handoff from the package-I/O operation to the main-actor session.
    private final class LibraryStateWriteResult: Sendable {
        private let value = OSAllocatedUnfairLock<LibraryStateWriteOutcome?>(initialState: nil)
        func store(_ result: LibraryStateWriteOutcome) {
            value.withLock { $0 = result }
        }
        func take() -> LibraryStateWriteOutcome? {
            value.withLock { $0 }
        }
    }

    /// What a culling write achieved, shard by shard.
    struct LibraryStateWriteOutcome: Sendable {
        /// Refreshed index entries for the shards that committed.
        var entries: [LibraryIndexEntry] = []
        /// Updates whose shard did not commit (all of them when the lease was lost).
        var failed: [LibraryStateUpdate] = []
        /// Assets a failing shard reported as no longer in the library; retrying cannot help.
        var missingAssetIDs: Set<PortablePhotoAssetID> = []
        /// The first failure, if any shard failed.
        var error: Error?
    }

    /// Throwing form of `commitLibraryState` for callers that treat any failed shard as failure.
    nonisolated static func writeLibraryState(
        _ updates: [LibraryStateUpdate],
        package: PortableLibraryPackage,
        lease: PortablePackageLease,
        now: Date,
        didCommitShard: (@Sendable (String) -> Void)? = nil
    ) throws -> [LibraryIndexEntry] {
        let outcome = commitLibraryState(
            updates, package: package, lease: lease, now: now, didCommitShard: didCommitShard
        )
        if let error = outcome.error { throw error }
        return outcome.entries
    }

    /// Groups updates by membership shard and commits exactly one transaction per shard under the
    /// writer mutation lock. Unchanged entries are skipped, and a shard with no change commits
    /// nothing. A failing shard does not undo or block the others: its updates are reported in
    /// `failed` so the caller can keep them dirty.
    nonisolated static func commitLibraryState(
        _ updates: [LibraryStateUpdate],
        package: PortableLibraryPackage,
        lease: PortablePackageLease,
        now: Date,
        didCommitShard: (@Sendable (String) -> Void)? = nil
    ) -> LibraryStateWriteOutcome {
        var outcome = LibraryStateWriteOutcome()
        // Last update for an asset wins within a batch.
        var latest: [PortablePhotoAssetID: LibraryStateUpdate] = [:]
        for update in updates { latest[update.assetID] = update }
        do { try lease.renew(now: now) } catch {
            outcome.failed = Array(latest.values)
            outcome.error = PortablePackageLeaseError.lostDuringSession
            return outcome
        }
        let byShard = Dictionary(grouping: latest.values) {
            PortableLibraryPackage.shard(for: $0.assetID)
        }
        for shardName in byShard.keys.sorted() {
            let shardUpdates = byShard[shardName] ?? []
            do {
            let entries: [LibraryIndexEntry] = try lease.withWriterMutationLock {
                var shard = try package.readMembershipShard(shardName)
                var positions: [PortablePhotoAssetID: Int] = [:]
                for (index, entry) in shard.entries.enumerated() where !entry.isTombstone {
                    positions[entry.assetID] = index
                }
                var touched: [Int] = []
                for update in shardUpdates {
                    guard let index = positions[update.assetID] else {
                        throw PortablePackageTrashError.assetNotFound(update.assetID)
                    }
                    let rating = min(max(update.rating, 0), 5)
                    guard shard.entries[index].summary.rating != rating
                            || shard.entries[index].summary.flag != update.flag.rawValue
                    else { continue }
                    shard.entries[index].summary.rating = rating
                    shard.entries[index].summary.flag = update.flag.rawValue
                    shard.entries[index].summary.assetRevision &+= 1
                    touched.append(index)
                }
                guard !touched.isEmpty else { return [] }

                var transaction = try package.beginTransaction(lease: lease, now: now)
                do {
                    try transaction.stage(
                        data: try package.encodedMembershipShard(shard),
                        at: "Catalog/Membership/\(shardName).json"
                    )
                    try transaction.commit(now: now)
                } catch {
                    try? transaction.abort()
                    throw error
                }
                didCommitShard?(shardName)
                return touched.map { LibraryIndexEntry(from: shard.entries[$0]) }
            }
            outcome.entries.append(contentsOf: entries)
            } catch {
                outcome.failed.append(contentsOf: shardUpdates)
                if case PortablePackageTrashError.assetNotFound(let missing) = error {
                    outcome.missingAssetIDs.insert(missing)
                }
                if outcome.error == nil { outcome.error = error }
            }
        }
        return outcome
    }

}

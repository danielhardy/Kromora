import Foundation

/// The source information needed to address one edit revision.
struct EditSourceReference: Codable, Sendable, Equatable {
    private enum CodingKeys: String, CodingKey {
        case assetID, portableAssetID, url
    }

    let assetID: PhotoAssetID
    /// The package-owned identity. `assetID` remains at this boundary for editor compatibility;
    /// it is never used as the package key when an explicit portable identity is available.
    let portableAssetID: PortablePhotoAssetID
    let url: URL?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let assetID = try container.decode(PhotoAssetID.self, forKey: .assetID)
        self.assetID = assetID
        portableAssetID =
            try container.decodeIfPresent(PortablePhotoAssetID.self, forKey: .portableAssetID)
            ?? PortablePhotoAssetID.compatibility(from: assetID)
        url = try container.decodeIfPresent(URL.self, forKey: .url)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(assetID, forKey: .assetID)
        try container.encode(portableAssetID, forKey: .portableAssetID)
        try container.encodeIfPresent(url, forKey: .url)
    }

    init(
        assetID: PhotoAssetID,
        portableIdentity: PortablePhotoIdentity? = nil,
        url: URL? = nil
    ) {
        self.assetID = assetID
        portableAssetID =
            portableIdentity?.assetID ?? PortablePhotoAssetID.compatibility(from: assetID)
        self.url = url
    }

    init(
        portableIdentity: PortablePhotoIdentity,
        assetID: PhotoAssetID? = nil,
        url: URL? = nil
    ) {
        self.assetID = assetID ?? PhotoAssetID(rawValue: "portable:\(portableIdentity.assetID.raw)")
        portableAssetID = portableIdentity.assetID
        self.url = url
    }
}

/// The result of looking up one source in the edit store.
struct EditDocumentLoadResult: Sendable, Equatable {
    let document: EditDocument
    let found: Bool
    let status: EditDocumentStore.Status
    /// The Look identity of the current package revision, taken from its content-addressed
    /// `PortablePackageLookReference` rather than from the Look browser. It is durable and does not
    /// depend on scan timing; `.none` for a neutral fallback or a revision with no Look. The blob
    /// is not read or copied — the hash was recorded when the revision was written.
    let lookSignature: LookSignature

    init(
        document: EditDocument, found: Bool, status: EditDocumentStore.Status,
        lookSignature: LookSignature = .none
    ) {
        self.document = document
        self.found = found
        self.status = status
        self.lookSignature = lookSignature
    }

    /// A speculative preview may use a healthy missing record as identity, but must not use the
    /// neutral fallback returned when persistence could not establish what the stored state was.
    var isUsableForPrefetch: Bool {
        if !found { return !status.isActionable }
        if case .corrupt = status { return false }
        return true
    }
}

/// A bounded, actor-local cache in front of package edit revisions.
///
/// The cache contains decoded values only. Every write appends an immutable package revision
/// before this cache is updated, so eviction can discard memory but can never discard an edit.
/// Package revision numbers are retained with entries and checked against the asset record before
/// a cached value is returned; an edit written by another package operation therefore invalidates
/// the entry naturally.
actor EditDocumentStore {
    static let defaultCacheCapacity = 128

    enum Status: Sendable, Equatable {
        case ready
        /// The store has not been bound to a package yet. Operations fail closed, but this is a
        /// transient startup state, not an actionable package failure.
        case opening
        case relinked
        case corrupt(String)
        case packageFailure(String)
        case writeFailure(String)

        var message: String? {
            switch self {
            case .ready:
                return nil
            case .opening:
                return "Opening the library…"
            case .relinked:
                return "Restored edits after the source photo moved."
            case .corrupt(let detail):
                return "Could not read edit record (\(detail)); using neutral edits until the record is repaired."
            case .packageFailure(let detail):
                return "Could not read the library package (\(detail)); edits were not replaced."
            case .writeFailure(let detail):
                return "Could not save edit records: \(detail)"
            }
        }

        var isActionable: Bool {
            switch self {
            case .ready, .opening: return false
            case .relinked, .corrupt, .packageFailure, .writeFailure: return true
            }
        }

        var severity: Int {
            switch self {
            case .ready, .opening: return 0
            case .relinked: return 1
            case .corrupt: return 2
            case .packageFailure: return 3
            case .writeFailure: return 4
            }
        }
    }

    enum StoreError: Error, LocalizedError, Equatable {
        case cannotWrite(String)

        var errorDescription: String? {
            switch self {
            case .cannotWrite(let detail): return detail
            }
        }
    }

    private struct CacheEntry: Sendable {
        let document: EditDocument
        let revision: UInt64
    }

    /// Test evidence retained because it also verifies that package I/O never runs on the main
    /// actor. These counters do not participate in persistence decisions.
    private(set) var lastIOWasMainThread = false
    private(set) var writeCount = 0
    private(set) var saveAttemptCount = 0
    private(set) var status: Status = .ready
    private(set) var worstActionableStatus: Status?

    let cacheCapacity: Int
    private(set) var cacheCount = 0
    private var cache: [PortablePhotoAssetID: CacheEntry] = [:]
    private var lru: [PortablePhotoAssetID] = []

    private var packageRoot: URL?
    private var packageLease: PortablePackageLease?
    /// True for a store created by `makeUnboundStore()` until `bind(package:lease:)` runs.
    private var awaitsBinding = false
    private var embeddedLookBytes: [String: Data] = [:]
    private var embeddedLookTask: Task<Void, Never>?
    private var embeddedLookGeneration: UInt64 = 0
    /// Receives the membership entry a package transaction committed beside an edit, so the
    /// disposable library index can carry the same `presentedAspectRatio` without a rebuild.
    private var membershipObserver: (@Sendable (PortablePackageMembershipEntry) -> Void)?
    private var artificialWriteDelay: Duration
    private var failuresRemaining: Int
    private let writeAcknowledgementGate: (@Sendable () async -> Void)?

    private init(awaitsBinding: Bool = false) {
        self.awaitsBinding = awaitsBinding
        packageRoot = nil
        packageLease = nil
        cacheCapacity = Self.defaultCacheCapacity
        artificialWriteDelay = .zero
        failuresRemaining = 0
        writeStartSignal = nil
        writeAcknowledgementGate = nil
    }

    /// Opens the canonical package edit store.
    init(
        package: PortableLibraryPackage,
        lease: PortablePackageLease,
        cacheCapacity: Int = EditDocumentStore.defaultCacheCapacity,
        artificialWriteDelay: Duration = .zero,
        failuresBeforeSuccess: Int = 0,
        writeStartSignal: AsyncStream<Void>.Continuation? = nil,
        writeAcknowledgementGate: (@Sendable () async -> Void)? = nil
    ) {
        packageRoot = package.rootURL
        packageLease = lease
        self.cacheCapacity = max(1, cacheCapacity)
        self.artificialWriteDelay = artificialWriteDelay
        self.failuresRemaining = max(0, failuresBeforeSuccess)
        self.writeStartSignal = writeStartSignal
        self.writeAcknowledgementGate = writeAcknowledgementGate
    }

    /// Convenience form for integration boundaries that retain only the package URL.
    init(
        packageRoot: URL,
        lease: PortablePackageLease,
        cacheCapacity: Int = EditDocumentStore.defaultCacheCapacity,
        artificialWriteDelay: Duration = .zero,
        failuresBeforeSuccess: Int = 0,
        writeStartSignal: AsyncStream<Void>.Continuation? = nil,
        writeAcknowledgementGate: (@Sendable () async -> Void)? = nil
    ) throws {
        try self.init(
            package: PortableLibraryPackage.openForQuery(at: packageRoot), lease: lease,
            cacheCapacity: cacheCapacity, artificialWriteDelay: artificialWriteDelay,
            failuresBeforeSuccess: failuresBeforeSuccess, writeStartSignal: writeStartSignal,
            writeAcknowledgementGate: writeAcknowledgementGate
        )
    }

    /// A package-backed store has no separate edit database.
    var onDiskFileURL: URL? { nil }

    /// Unavailable projection store for isolated coordinator composition. It holds no persistence
    /// authority and reports the same actionable package failure as a failed package open.
    static func makeInMemoryProjectionStore() -> EditDocumentStore {
        EditDocumentStore()
    }

    /// Store whose package is not open yet. Reads and writes fail closed with `Status.opening`
    /// (not an actionable package failure) until `bind(package:lease:)` supplies the package.
    static func makeUnboundStore() -> EditDocumentStore {
        EditDocumentStore(awaitsBinding: true)
    }

    /// Binds an unbound store to its opened package. Allowed exactly once; a second call, or a call
    /// on a store that was constructed bound, is rejected and leaves the store unchanged.
    @discardableResult
    func bind(package: PortableLibraryPackage, lease: PortablePackageLease) -> Bool {
        guard awaitsBinding, packageRoot == nil else { return false }
        packageRoot = package.rootURL
        packageLease = lease
        awaitsBinding = false
        status = .ready
        return true
    }

    private var unavailableStatus: Status {
        awaitsBinding
            ? .opening : .packageFailure("the canonical edit package is unavailable")
    }

    private var unavailableDetail: String {
        awaitsBinding ? "the library is still opening" : "the canonical edit package is unavailable"
    }

    func setEmbeddedLookBytes(_ values: [String: Data]) {
        _ = cancelPendingEmbeddedLookLoading()
        embeddedLookBytes = values
    }

    /// Loads Look bytes off the actor's caller and installs them only if no newer snapshot, cancel, or
    /// direct `setEmbeddedLookBytes` has superseded this one. `save` awaits the latest pending load,
    /// so an edit written right after a Look import still embeds that Look's bytes.
    func loadEmbeddedLooks(
        _ sources: [EmbeddedLookSource],
        retaining accesses: [SecurityScopedResourceAccess],
        reader: @escaping EmbeddedLookLoader.Reader = EmbeddedLookLoader.fileReader
    ) {
        embeddedLookTask?.cancel()
        embeddedLookGeneration &+= 1
        let generation = embeddedLookGeneration
        embeddedLookTask = Task { [weak self] in
            let values = await EmbeddedLookLoader.load(sources, retaining: accesses, reader: reader)
            guard !Task.isCancelled else { return }
            await self?.installEmbeddedLooks(values, generation: generation)
        }
    }

    /// Cancels pending Look loading; nothing already in flight can publish afterwards.
    func cancelEmbeddedLookLoading() -> Task<Void, Never>? {
        cancelPendingEmbeddedLookLoading()
    }

    private func cancelPendingEmbeddedLookLoading() -> Task<Void, Never>? {
        let task = embeddedLookTask
        task?.cancel()
        embeddedLookTask = nil
        embeddedLookGeneration &+= 1
        return task
    }

    /// Suspends until the newest Look snapshot has been installed (or cancelled).
    func awaitEmbeddedLooks() async {
        await embeddedLookTask?.value
    }

    private func installEmbeddedLooks(_ values: [String: Data], generation: UInt64) {
        guard generation == embeddedLookGeneration else { return }
        embeddedLookBytes = values
        embeddedLookTask = nil
    }

    func setMembershipObserver(_ observer: (@Sendable (PortablePackageMembershipEntry) -> Void)?) {
        membershipObserver = observer
    }

    func load(for source: EditSourceReference) async -> EditDocumentLoadResult {
        markIO()
        guard let packageRoot else {
            return finishLoad(document: EditDocument(), found: false, status: unavailableStatus)
        }

        do {
            let package = try PortableLibraryPackage.openForQuery(at: packageRoot)
            let record = try package.readAssetRecord(for: source.portableAssetID)
            guard record.currentRevision > 0 else {
                return finishLoad(document: EditDocument(), found: false, status: .ready)
            }

            let sidecar = try package.readEditSidecar(for: source.portableAssetID)
            if let entry = cache[source.portableAssetID],
               entry.revision == record.currentRevision,
               sidecar.native.revision == entry.revision
            {
                // Validate the immutable native/XMP pair even on a cache hit. The package remains
                // authoritative if a sidecar is damaged or replaced outside this actor.
                touch(source.portableAssetID)
                return finishLoad(
                    document: entry.document, found: true, status: .ready,
                    lookSignature: LookSignature(
                        settings: entry.document.lut,
                        reference: sidecar.native.lookReferences.first
                    )
                )
            }
            let document = sidecar.native.document
            insert(document, revision: sidecar.native.revision, for: source.portableAssetID)
            return finishLoad(
                document: document, found: true, status: .ready,
                lookSignature: LookSignature(
                    settings: document.lut, reference: sidecar.native.lookReferences.first
                )
            )
        } catch {
            let failure = Self.status(for: error)
            return finishLoad(document: EditDocument(), found: false, status: failure)
        }
    }

    func load(for assetID: PhotoAssetID) async -> EditDocumentLoadResult {
        await load(for: EditSourceReference(assetID: assetID))
    }

    func load(for sources: [EditSourceReference]) async -> [EditDocumentLoadResult] {
        var results: [EditDocumentLoadResult] = []
        results.reserveCapacity(sources.count)
        for source in sources {
            results.append(await load(for: source))
        }
        return results
    }

    func document(for source: EditSourceReference) async -> EditDocument? {
        let result = await load(for: source)
        return result.found ? result.document : nil
    }

    /// Loads immutable package edit revisions for the editor's history browser.
    func history(for source: EditSourceReference) async throws -> [PortablePackageEditRevision] {
        guard let packageRoot else {
            throw StoreError.cannotWrite(unavailableDetail)
        }
        let package = try PortableLibraryPackage.openForQuery(at: packageRoot)
        return try package.readEditHistory(for: source.portableAssetID)
    }

    func currentRevision(for source: EditSourceReference) async throws -> UInt64 {
        guard let packageRoot else {
            throw StoreError.cannotWrite(unavailableDetail)
        }
        let package = try PortableLibraryPackage.openForQuery(at: packageRoot)
        return try package.readAssetRecord(for: source.portableAssetID).editHistory.currentRevision
    }

    func selectRevision(_ revision: UInt64, for source: EditSourceReference) async throws {
        guard let packageRoot, let packageLease else {
            throw StoreError.cannotWrite(unavailableDetail)
        }
        let package = try PortableLibraryPackage.openForQuery(at: packageRoot)
        if let membership = try package.selectEditRevision(
            for: source.portableAssetID, revision: revision, lease: packageLease
        ) {
            membershipObserver?(membership)
        }
    }

    func save(_ document: EditDocument, for source: EditSourceReference) async throws {
        try await save(document, for: source, snapshotName: nil)
    }

    func saveSnapshot(_ document: EditDocument, named name: String, for source: EditSourceReference) async throws {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { throw StoreError.cannotWrite("snapshot name cannot be empty") }
        try await save(document, for: source, snapshotName: normalized)
    }

    private func save(
        _ document: EditDocument, for source: EditSourceReference, snapshotName: String?
    ) async throws {
        markIO()
        await awaitEmbeddedLooks()
        // Encode before incrementing attempt counters or changing the cache. An invalid value must
        // not make a failed save look like a dirty durable revision.
        _ = try JSONEncoder().encode(document)
        guard let packageRoot, let packageLease else {
            let failure = StoreError.cannotWrite(unavailableDetail)
            status = awaitsBinding ? .opening : .writeFailure(failure.localizedDescription)
            throw failure
        }

        saveAttemptCount += 1
        do {
            if failuresRemaining > 0 {
                failuresRemaining -= 1
                throw StoreError.cannotWrite("injected persistence failure")
            }
            let package = try PortableLibraryPackage.openForQuery(at: packageRoot)
            let commit = try package.commitEditRevision(
                for: source.portableAssetID, document: document,
                snapshotName: snapshotName,
                lookBytes: sourceLookBytes(for: document), lease: packageLease
            )
            let sidecar = commit.sidecar
            if let membership = commit.membership { membershipObserver?(membership) }
            insert(document, revision: sidecar.native.revision, for: source.portableAssetID)
            writeCount += 1
            status = .ready
            writeStartSignal?.yield(())
            await writeAcknowledgementGate?()
            await delayIfNeeded()
        } catch {
            status = .writeFailure(error.localizedDescription)
            throw error
        }
    }

    func save(_ document: EditDocument, for assetID: PhotoAssetID, url: URL? = nil) async throws {
        try await save(document, for: EditSourceReference(assetID: assetID, url: url))
    }

    /// Removes only the memory entry. Package edit revisions are immutable and remain recoverable.
    func delete(for source: EditSourceReference) async throws {
        markIO()
        cache.removeValue(forKey: source.portableAssetID)
        lru.removeAll { $0 == source.portableAssetID }
        cacheCount = cache.count
        status = .ready
    }

    func delete(for assetID: PhotoAssetID, url: URL? = nil) async throws {
        try await delete(for: EditSourceReference(assetID: assetID, url: url))
    }

    private(set) var writeStartSignal: AsyncStream<Void>.Continuation?

    private func sourceLookBytes(for document: EditDocument) -> [Data] {
        guard let lutID = document.lut.lutID, let bytes = embeddedLookBytes[lutID.raw] else {
            return []
        }
        return [bytes]
    }

    private func delayIfNeeded() async {
        guard artificialWriteDelay > .zero else { return }
        let delay = artificialWriteDelay
        // Deliberately detached: the artificial write delay must run its full length even when the
        // caller is cancelled, which is what the slow-write tests model.
        await Task.detached {
            try? await Task.sleep(for: delay)
        }.value
    }

    private func insert(
        _ document: EditDocument, revision: UInt64, for assetID: PortablePhotoAssetID
    ) {
        cache[assetID] = CacheEntry(document: document, revision: revision)
        touch(assetID)
        while cache.count > cacheCapacity, let evicted = lru.first {
            lru.removeFirst()
            cache.removeValue(forKey: evicted)
        }
        cacheCount = cache.count
    }

    private func touch(_ assetID: PortablePhotoAssetID) {
        lru.removeAll { $0 == assetID }
        lru.append(assetID)
    }

    private func markIO() {
        lastIOWasMainThread = Thread.isMainThread
    }

    private func finishLoad(
        document: EditDocument, found: Bool, status loadStatus: Status,
        lookSignature: LookSignature = .none
    ) -> EditDocumentLoadResult {
        status = loadStatus
        if loadStatus.isActionable {
            retainWorstActionableStatus(loadStatus)
        }
        return EditDocumentLoadResult(
            document: document, found: found, status: loadStatus, lookSignature: lookSignature
        )
    }

    private func retainWorstActionableStatus(_ candidate: Status) {
        guard candidate.isActionable else { return }
        guard let current = worstActionableStatus else {
            worstActionableStatus = candidate
            return
        }
        if candidate.severity >= current.severity { worstActionableStatus = candidate }
    }

    private static func status(for error: Error) -> Status {
        switch error {
        case let error as PortablePackageError:
            switch error {
            case .invalidEditRevision, .malformedXMP, .invalidLookReference,
                 .lookChecksumMismatch, .missingLook:
                return .corrupt(error.localizedDescription)
            default:
                return .packageFailure(error.localizedDescription)
            }
        case is DecodingError:
            return .corrupt(error.localizedDescription)
        default:
            return .packageFailure(error.localizedDescription)
        }
    }
}

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
        case relinked
        case corrupt(String)
        case packageFailure(String)
        case writeFailure(String)

        var message: String? {
            switch self {
            case .ready:
                return nil
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
            case .ready: return false
            case .relinked, .corrupt, .packageFailure, .writeFailure: return true
            }
        }

        var severity: Int {
            switch self {
            case .ready: return 0
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

    private let packageRoot: URL?
    private let packageLease: PortablePackageLease?
    private var embeddedLookBytes: [String: Data] = [:]
    private var artificialWriteDelay: Duration
    private var failuresRemaining: Int

    // These compatibility values are used only by old headless test composition points while
    // those tests move to package fixtures. Production always constructs the package initializer.
    private let compatibilityBackend: CompatibilityEditBackend?
    private let compatibilityFileURL: URL?

    /// Opens the canonical package edit store.
    init(
        package: PortableLibraryPackage,
        lease: PortablePackageLease,
        modelContainer: Any? = nil,
        cacheCapacity: Int = EditDocumentStore.defaultCacheCapacity,
        artificialWriteDelay: Duration = .zero,
        failuresBeforeSuccess: Int = 0,
        writeStartSignal: AsyncStream<Void>.Continuation? = nil
    ) {
        _ = modelContainer
        packageRoot = package.rootURL
        packageLease = lease
        self.cacheCapacity = max(1, cacheCapacity)
        self.artificialWriteDelay = artificialWriteDelay
        self.failuresRemaining = max(0, failuresBeforeSuccess)
        compatibilityBackend = nil
        compatibilityFileURL = nil
        self.writeStartSignal = writeStartSignal
    }

    /// Convenience form for integration boundaries that retain only the package URL.
    init(
        packageRoot: URL,
        lease: PortablePackageLease,
        cacheCapacity: Int = EditDocumentStore.defaultCacheCapacity,
        artificialWriteDelay: Duration = .zero,
        failuresBeforeSuccess: Int = 0,
        writeStartSignal: AsyncStream<Void>.Continuation? = nil
    ) throws {
        try self.init(
            package: PortableLibraryPackage.openForQuery(at: packageRoot), lease: lease,
            modelContainer: nil,
            cacheCapacity: cacheCapacity, artificialWriteDelay: artificialWriteDelay,
            failuresBeforeSuccess: failuresBeforeSuccess, writeStartSignal: writeStartSignal
        )
    }

    /// Compatibility constructor for headless clients that have not yet adopted a package
    /// fixture. It is an in-memory cache backend, not a production persistence path.
    init(
        modelContainer: sending Any,
        cacheCapacity: Int = EditDocumentStore.defaultCacheCapacity,
        artificialWriteDelay: Duration = .zero,
        failuresBeforeSuccess: Int = 0,
        writeStartSignal: AsyncStream<Void>.Continuation? = nil
    ) {
        packageRoot = nil
        packageLease = nil
        self.cacheCapacity = max(1, cacheCapacity)
        self.artificialWriteDelay = artificialWriteDelay
        self.failuresRemaining = max(0, failuresBeforeSuccess)
        let key = CompatibilityEditBackendRegistry.key(for: modelContainer)
        compatibilityBackend = compatibilityBackends.backend(for: key)
        compatibilityFileURL = nil
        self.writeStartSignal = writeStartSignal
    }

    /// Compatibility constructor for old support tests. It does not create or open a standalone
    /// edit database; the URL only scopes a disposable in-memory backend.
    init(
        fileURL: URL,
        cacheCapacity: Int = EditDocumentStore.defaultCacheCapacity,
        artificialWriteDelay: Duration = .zero,
        failuresBeforeSuccess: Int = 0,
        writeStartSignal: AsyncStream<Void>.Continuation? = nil
    ) {
        packageRoot = nil
        packageLease = nil
        self.cacheCapacity = max(1, cacheCapacity)
        self.artificialWriteDelay = artificialWriteDelay
        self.failuresRemaining = max(0, failuresBeforeSuccess)
        let key = "file:\(fileURL.standardizedFileURL.path)"
        compatibilityBackend = compatibilityBackends.backend(for: key)
        compatibilityFileURL = fileURL
        self.writeStartSignal = writeStartSignal
    }

    /// Empty disposable store used by isolated coordinator tests. It has no package authority.
    static func makeInMemoryProjectionStore() -> EditDocumentStore {
        EditDocumentStore(modelContainer: UUID())
    }

    /// A package-backed store has no separate edit database. The URL is exposed only for old
    /// headless clients that still inject a disposable compatibility backend.
    var onDiskFileURL: URL? { compatibilityFileURL }

    func setEmbeddedLookBytes(_ values: [String: Data]) {
        embeddedLookBytes = values
    }

    func load(for source: EditSourceReference) -> EditDocumentLoadResult {
        markIO()
        if let compatibilityBackend {
            let result = compatibilityBackend.load(for: source)
            return finishLoad(
                document: result?.document ?? EditDocument(), found: result != nil, status: .ready
            )
        }

        guard let packageRoot else {
            return finishLoad(document: EditDocument(), found: false, status: .packageFailure(
                "the canonical edit package is unavailable"
            ))
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
                return finishLoad(document: entry.document, found: true, status: .ready)
            }
            let document = sidecar.native.document
            insert(document, revision: sidecar.native.revision, for: source.portableAssetID)
            return finishLoad(document: document, found: true, status: .ready)
        } catch {
            let failure = Self.status(for: error)
            return finishLoad(document: EditDocument(), found: false, status: failure)
        }
    }

    func load(for assetID: PhotoAssetID) -> EditDocumentLoadResult {
        load(for: EditSourceReference(assetID: assetID))
    }

    func load(for sources: [EditSourceReference]) -> [EditDocumentLoadResult] {
        sources.map { load(for: $0) }
    }

    func document(for source: EditSourceReference) -> EditDocument? {
        let result = load(for: source)
        return result.found ? result.document : nil
    }

    func save(_ document: EditDocument, for source: EditSourceReference) async throws {
        markIO()
        // Encode before incrementing attempt counters or changing the cache. An invalid value must
        // not make a failed save look like a dirty durable revision.
        let encodedDocument = try JSONEncoder().encode(document)
        if let compatibilityBackend {
            try await saveToCompatibilityBackend(
                document, encoded: encodedDocument, for: source, backend: compatibilityBackend
            )
            return
        }

        guard let packageRoot, let packageLease else {
            let failure = StoreError.cannotWrite("the canonical edit package is unavailable")
            status = .writeFailure(failure.localizedDescription)
            throw failure
        }

        saveAttemptCount += 1
        do {
            if failuresRemaining > 0 {
                failuresRemaining -= 1
                throw StoreError.cannotWrite("injected persistence failure")
            }
            let package = try PortableLibraryPackage.openForQuery(at: packageRoot)
            let sidecar = try package.appendEditRevision(
                for: source.portableAssetID, document: document,
                lookBytes: sourceLookBytes(for: document), lease: packageLease
            )
            insert(document, revision: sidecar.native.revision, for: source.portableAssetID)
            writeCount += 1
            status = .ready
            writeStartSignal?.yield(())
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
    func delete(for source: EditSourceReference) throws {
        markIO()
        cache.removeValue(forKey: source.portableAssetID)
        lru.removeAll { $0 == source.portableAssetID }
        cacheCount = cache.count
        compatibilityBackend?.remove(for: source.portableAssetID)
        status = .ready
    }

    func delete(for assetID: PhotoAssetID, url: URL? = nil) throws {
        try delete(for: EditSourceReference(assetID: assetID, url: url))
    }

    private(set) var writeStartSignal: AsyncStream<Void>.Continuation?

    private func saveToCompatibilityBackend(
        _ document: EditDocument,
        encoded: Data,
        for source: EditSourceReference,
        backend: CompatibilityEditBackend
    ) async throws {
        _ = encoded
        saveAttemptCount += 1
        do {
            if failuresRemaining > 0 {
                failuresRemaining -= 1
                throw StoreError.cannotWrite("injected persistence failure")
            }
            backend.save(document, for: source)
            insert(
                document, revision: backend.revision(for: source.portableAssetID),
                for: source.portableAssetID
            )
            writeCount += 1
            status = .ready
            writeStartSignal?.yield(())
            await delayIfNeeded()
        } catch {
            status = .writeFailure(error.localizedDescription)
            throw error
        }
    }

    private func sourceLookBytes(for document: EditDocument) -> [Data] {
        guard let lutID = document.lut.lutID, let bytes = embeddedLookBytes[lutID.raw] else {
            return []
        }
        return [bytes]
    }

    private func delayIfNeeded() async {
        guard artificialWriteDelay > .zero else { return }
        let delay = artificialWriteDelay
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
        document: EditDocument, found: Bool, status loadStatus: Status
    ) -> EditDocumentLoadResult {
        status = loadStatus
        if loadStatus.isActionable {
            retainWorstActionableStatus(loadStatus)
        }
        return EditDocumentLoadResult(document: document, found: found, status: loadStatus)
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

// MARK: - Disposable compatibility backend

/// This backend exists only for legacy headless test composition points. It deliberately has no
/// file format, URL lookup, or source relinking behavior; package mode above is the sole product
/// persistence implementation.
private final class CompatibilityEditBackend: @unchecked Sendable {
    private let lock = NSLock()
    private var documents: [PortablePhotoAssetID: EditDocument] = [:]
    private var revisions: [PortablePhotoAssetID: UInt64] = [:]
    private var aliases: [String: PortablePhotoAssetID] = [:]

    func save(_ document: EditDocument, for source: EditSourceReference) {
        let assetID = source.portableAssetID
        lock.lock()
        documents[assetID] = document
        revisions[assetID, default: 0] += 1
        if let url = source.url {
            aliases[url.standardizedFileURL.resolvingSymlinksInPath().path] = assetID
        }
        lock.unlock()
    }

    func load(for source: EditSourceReference) -> (document: EditDocument, revision: UInt64)? {
        lock.lock()
        defer { lock.unlock() }
        let assetID = source.url
            .flatMap { aliases[$0.standardizedFileURL.resolvingSymlinksInPath().path] }
            ?? source.portableAssetID
        guard let document = documents[assetID], let revision = revisions[assetID] else { return nil }
        return (document, revision)
    }

    func revision(for assetID: PortablePhotoAssetID) -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return revisions[assetID] ?? 0
    }

    func remove(for assetID: PortablePhotoAssetID) {
        lock.lock()
        documents.removeValue(forKey: assetID)
        revisions.removeValue(forKey: assetID)
        aliases = aliases.filter { $0.value != assetID }
        lock.unlock()
    }
}

private final class CompatibilityEditBackendRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: CompatibilityEditBackend] = [:]

    func backend(for key: String) -> CompatibilityEditBackend {
        lock.lock()
        defer { lock.unlock() }
        if let value = values[key] { return value }
        let value = CompatibilityEditBackend()
        values[key] = value
        return value
    }

    static func key(for value: Any) -> String {
        if let uuid = value as? UUID {
            return "uuid:\(uuid.uuidString)"
        }
        let object = value as AnyObject
        return "object:\(ObjectIdentifier(object))"
    }
}

private let compatibilityBackends = CompatibilityEditBackendRegistry()

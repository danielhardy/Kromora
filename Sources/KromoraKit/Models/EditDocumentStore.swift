import Foundation
import SwiftData

/// The source information persisted alongside an edit document.
struct EditSourceReference: Codable, Sendable, Equatable {
    private enum CodingKeys: String, CodingKey {
        case assetID, portableAssetID, url
    }

    let assetID: PhotoAssetID
    /// The opaque identity used by `EditRecord`. The legacy `assetID` is retained at this API
    /// boundary so editor/import callers can migrate independently of the store schema.
    let portableAssetID: PortablePhotoAssetID
    let url: URL?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let assetID = try container.decode(PhotoAssetID.self, forKey: .assetID)
        self.assetID = assetID
        self.portableAssetID =
            try container.decodeIfPresent(PortablePhotoAssetID.self, forKey: .portableAssetID)
            ?? PortablePhotoAssetID.compatibility(from: assetID)
        self.url = try container.decodeIfPresent(URL.self, forKey: .url)
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
        self.portableAssetID =
            portableIdentity?.assetID ?? PortablePhotoAssetID.compatibility(from: assetID)
        self.url = url
    }

    init(
        portableIdentity: PortablePhotoIdentity,
        assetID: PhotoAssetID? = nil,
        url: URL? = nil
    ) {
        self.assetID = assetID ?? PhotoAssetID(rawValue: "portable:\(portableIdentity.assetID.raw)")
        self.portableAssetID = portableIdentity.assetID
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

/// Actor-isolated SwiftData persistence for per-photo edit documents.
///
/// Each photo is an `EditRecord`, so saving one edit only saves the changed SwiftData row. The
/// v2 store deliberately has no record migration from the former path-keyed SwiftData store:
/// the product has not shipped, and ADR-001 approved a clean-slate disposition. The old file is
/// left untouched and the app opens a separate v2 container, so a mistaken premise cannot turn
/// into silent deletion.
@ModelActor
actor EditDocumentStore {

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
            case .ready:
                return false
            case .relinked, .corrupt, .packageFailure, .writeFailure:
                return true
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
            case .cannotWrite(let detail):
                return detail
            }
        }
    }

    /// Testable evidence that persistence work ran on the model actor executor, not the main actor.
    private(set) var lastIOWasMainThread = false
    /// Durable-write counters are actor-isolated so coalescing tests do not need filesystem tracing.
    private(set) var writeCount = 0
    private(set) var saveAttemptCount = 0
    /// Test evidence that a relink needed the bookmark fallback scan after the path query missed.
    private(set) var relinkFallbackScanCount = 0

    private var artificialWriteDelay: Duration = .zero
    private var writeStartSignal: AsyncStream<Void>.Continuation? = nil
    private var failuresRemaining: Int = 0
    private var persistenceUnavailable = false
    /// When present, the package sidecars are canonical and SwiftData is only a local projection.
    /// Keeping the URL and lease rather than a mutable package value means every operation opens
    /// the current manifest/asset record and cannot accidentally write through stale metadata.
    private var canonicalPackageRoot: URL? = nil
    private var packageLease: PortablePackageLease? = nil
    /// Resolved Look bytes are supplied by the application composition root. The document keeps
    /// only the stable Look ID, while the package revision embeds the exact bytes used at save.
    private var embeddedLookBytes: [String: Data] = [:]
    /// The outcome of the most recent store operation. Load callers must use their
    /// `EditDocumentLoadResult.status` instead of treating this as a load-wide diagnostic.
    private(set) var status: Status = .ready
    /// The store-wide actionable condition is retained for persistence-health diagnostics. This
    /// is the only deliberately sticky load diagnostic: it is separate from a load result, so a
    /// corrupt record for photo A must not make a healthy photo B report `.corrupt`.
    private(set) var worstActionableStatus: Status?
    private var persistentFileURL: URL? = nil

    /// The store file to expose for backup and support workflows, or `nil` when this store is
    /// running in memory because its on-disk container could not be opened (or because a test
    /// supplied an in-memory container).
    var onDiskFileURL: URL? { persistentFileURL }

    /// Update the in-memory Look resolver used only when a canonical package edit is committed.
    /// Missing data is safe: the document remains durable and the next save can retry embedding it.
    func setEmbeddedLookBytes(_ values: [String: Data]) {
        embeddedLookBytes = values
    }

    /// The legacy development store path, retained for support and disposition tests.
    static var defaultFileURL: URL {
        return
            KromoraStorage.applicationSupportRoot()
            .appendingPathComponent("EditStore.store")
    }

    /// The v2 container used by the shipped app after the opaque-identity cutover. Keeping the
    /// legacy path named above makes support tooling and tests able to identify old data without
    /// accidentally opening it as the new schema.
    static var portableStoreFileURL: URL {
        KromoraStorage.applicationSupportRoot()
            .appendingPathComponent("EditStore.v2.store")
    }

    /// Builds a local-only SwiftData container. CloudKit is explicitly disabled for this store.
    static func makeContainer(url: URL) throws -> ModelContainer {
        let schema = Schema([EditRecord.self])
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let configuration = ModelConfiguration(
            "EditStorePortableIdentityV2",
            schema: schema,
            url: url,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    /// Creates a store backed by the requested on-disk SwiftData container.
    ///
    /// App-owned callers should use `makeDefaultStore()` so a container failure remains a
    /// recoverable, user-visible persistence warning rather than escaping during app startup.
    static func makePersistentStore(fileURL: URL) throws -> EditDocumentStore {
        EditDocumentStore(
            modelContainer: try makeContainer(url: fileURL),
            persistentFileURL: fileURL
        )
    }

    private static func makeInMemoryContainer() -> ModelContainer {
        let schema = Schema([EditRecord.self])
        let configuration = ModelConfiguration(
            "EditStorePortableIdentityV2",
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        // A schema made from the same model that is accepted by makeContainer cannot fail here.
        return try! ModelContainer(for: schema, configurations: [configuration])
    }

    /// Creates the production store while preserving the app's never-crash persistence policy.
    /// A failed on-disk container is replaced by an isolated in-memory store and remains visible
    /// to the app through the store's actionable status.
    static func makeDefaultStore() -> EditDocumentStore {
        do {
            // ADR-001 approved a clean slate. The old path-keyed store is intentionally not
            // opened, migrated, deleted, or overwritten; it remains available for support or a
            // future explicitly approved migration.
            return try makePersistentStore(fileURL: portableStoreFileURL)
        } catch {
            return EditDocumentStore(
                modelContainer: makeInMemoryContainer(),
                initialStatus: .writeFailure(error.localizedDescription),
                persistenceUnavailable: true,
                persistentFileURL: nil
            )
        }
    }

    /// Creates the disposable local projection used while a canonical package is active. Keeping
    /// this explicit prevents the production composition root from creating an unused standalone
    /// Application Support store before the package session is opened.
    static func makeInMemoryProjectionStore() -> EditDocumentStore {
        EditDocumentStore(modelContainer: makeInMemoryContainer())
    }

    /// Creates a persistent store, degrading to an in-memory store if the URL cannot be opened.
    /// The failure remains visible through `status` and the first save/load continues to be safe.
    init(
        fileURL: URL = EditDocumentStore.defaultFileURL,
        artificialWriteDelay: Duration = .zero,
        failuresBeforeSuccess: Int = 0,
        writeStartSignal: AsyncStream<Void>.Continuation? = nil
    ) {
        let container: ModelContainer
        let initialStatus: Status
        let persistenceUnavailable: Bool
        do {
            container = try Self.makeContainer(url: fileURL)
            initialStatus = .ready
            persistenceUnavailable = false
        } catch {
            container = Self.makeInMemoryContainer()
            initialStatus = .writeFailure(error.localizedDescription)
            persistenceUnavailable = true
        }
        self.init(
            modelContainer: container,
            initialStatus: initialStatus,
            persistenceUnavailable: persistenceUnavailable,
            persistentFileURL: persistenceUnavailable ? nil : fileURL,
            canonicalPackageRoot: nil,
            packageLease: nil,
            artificialWriteDelay: artificialWriteDelay,
            failuresBeforeSuccess: failuresBeforeSuccess,
            writeStartSignal: writeStartSignal
        )
    }

    /// Injectable container initializer used by tests and by clients that own the container.
    init(
        modelContainer: ModelContainer,
        initialStatus: Status = .ready,
        persistenceUnavailable: Bool = false,
        persistentFileURL: URL? = nil,
        canonicalPackageRoot: URL? = nil,
        packageLease: PortablePackageLease? = nil,
        artificialWriteDelay: Duration = .zero,
        failuresBeforeSuccess: Int = 0,
        writeStartSignal: AsyncStream<Void>.Continuation? = nil
    ) {
        let modelContext = ModelContext(modelContainer)
        self.modelExecutor = DefaultSerialModelExecutor(modelContext: modelContext)
        self.modelContainer = modelContainer
        self.artificialWriteDelay = artificialWriteDelay
        self.failuresRemaining = failuresBeforeSuccess
        self.persistenceUnavailable = persistenceUnavailable
        self.persistentFileURL = persistentFileURL
        self.canonicalPackageRoot = canonicalPackageRoot
        self.packageLease = packageLease
        self.writeStartSignal = writeStartSignal
        self.status = initialStatus
        self.worstActionableStatus = initialStatus.isActionable ? initialStatus : nil
    }

    /// Creates a projection-backed store for an already opened package. The lease is held by the
    /// package session and must remain alive for the lifetime of this store. Package commits happen
    /// before the local SwiftData projection is updated, so a projection failure cannot lose the
    /// user's edit and a deleted cache can always be rebuilt from the package.
    init(
        package: PortableLibraryPackage,
        lease: PortablePackageLease,
        modelContainer: ModelContainer? = nil,
        artificialWriteDelay: Duration = .zero,
        failuresBeforeSuccess: Int = 0,
        writeStartSignal: AsyncStream<Void>.Continuation? = nil
    ) {
        self.init(
            modelContainer: modelContainer ?? Self.makeInMemoryContainer(),
            canonicalPackageRoot: package.rootURL,
            packageLease: lease,
            artificialWriteDelay: artificialWriteDelay,
            failuresBeforeSuccess: failuresBeforeSuccess,
            writeStartSignal: writeStartSignal
        )
    }

    /// Convenience form for callers that keep only the package URL at their integration boundary.
    init(
        packageRoot: URL,
        lease: PortablePackageLease,
        modelContainer: ModelContainer? = nil,
        artificialWriteDelay: Duration = .zero,
        failuresBeforeSuccess: Int = 0,
        writeStartSignal: AsyncStream<Void>.Continuation? = nil
    ) throws {
        try self.init(
            package: PortableLibraryPackage.openForQuery(at: packageRoot), lease: lease,
            modelContainer: modelContainer, artificialWriteDelay: artificialWriteDelay,
            failuresBeforeSuccess: failuresBeforeSuccess, writeStartSignal: writeStartSignal
        )
    }

    func load(for source: EditSourceReference) -> EditDocumentLoadResult {
        markIO()
        if canonicalPackageRoot != nil {
            return loadFromCanonicalPackage(for: source)
        }
        let key = source.portableAssetID.uuid

        do {
            if let record = try fetchRecord(assetID: key) {
                // A stale direct-key record can coexist with a record whose locator proves that
                // it is the source being opened. Treat that observed relink as the newest write;
                // `relink` below applies the same keep-newest policy as the normal relink path.
                if let url = source.url,
                    sourcePath(for: url) != record.sourcePath,
                    usesLegacyIdentityBridge(for: source),
                    let relinkedRecord = try fetchRecordsForRelinking().first(where: {
                        $0 !== record && matches($0, url: url)
                    })
                {
                    let document: EditDocument
                    do {
                        document = try relinkedRecord.decodeDocument()
                    } catch {
                        return finishLoad(
                            document: EditDocument(), found: true,
                            status: .corrupt(error.localizedDescription)
                        )
                    }
                    return relink(
                        relinkedRecord,
                        document: document,
                        to: key,
                        for: url,
                        replacing: record
                    )
                }

                let document: EditDocument
                do {
                    document = try record.decodeDocument()
                } catch {
                    return finishLoad(
                        document: EditDocument(), found: true,
                        status: .corrupt(error.localizedDescription)
                    )
                }
                if let url = source.url,
                    sourcePath(for: url) != record.sourcePath,
                    usesLegacyIdentityBridge(for: source)
                {
                    return relink(
                        record,
                        document: document,
                        to: key,
                        for: url,
                        replacing: nil
                    )
                }
                return finishLoad(document: document, found: true, status: .ready)
            }

            guard let url = source.url else {
                return finishLoad(
                    document: EditDocument(), found: false, status: loadBaselineStatus
                )
            }

            let canonicalPath = sourcePath(for: url)
            let record = try fetchRecord(sourcePath: canonicalPath)
                ?? fetchRecordsForRelinking().first(where: { matches($0, url: url) })
            guard let record else {
                return finishLoad(
                    document: EditDocument(), found: false, status: loadBaselineStatus
                )
            }

            let document: EditDocument
            do {
                document = try record.decodeDocument()
            } catch {
                return finishLoad(
                    document: EditDocument(), found: true,
                    status: .corrupt(error.localizedDescription)
                )
            }

            // No record occupies `key` (the direct-key fetch above already established that), so
            // this is a plain rekey with nothing to replace.
            return relink(
                record,
                document: document,
                to: key,
                for: url,
                replacing: nil
            )
        } catch {
            return finishLoad(
                document: EditDocument(), found: false,
                status: .writeFailure(error.localizedDescription)
            )
        }
    }

    func load(for assetID: PhotoAssetID) -> EditDocumentLoadResult {
        load(for: EditSourceReference(assetID: assetID))
    }

    /// Load several source records in one actor hop. Callers use this for speculative work so
    /// the store lookup does not occupy the editor scheduler lane one neighbor at a time.
    func load(for sources: [EditSourceReference]) -> [EditDocumentLoadResult] {
        sources.map { load(for: $0) }
    }

    func document(for source: EditSourceReference) -> EditDocument? {
        let result = load(for: source)
        return result.found ? result.document : nil
    }

    func save(_ document: EditDocument, for source: EditSourceReference) async throws {
        markIO()
        if canonicalPackageRoot != nil {
            try await saveToCanonicalPackage(document, for: source)
            return
        }
        do {
            guard !persistenceUnavailable else {
                throw StoreError.cannotWrite(
                    worstActionableStatus?.message ?? "edit database is unavailable"
                )
            }
            // Encode before fetching or mutating the model context. JSONEncoder rejects values
            // such as non-conforming floating-point numbers; those failures must not create an
            // empty row or partially update an existing one.
            let encodedDocument = try JSONEncoder().encode(document)
            let record =
                try fetchRecord(assetID: source.portableAssetID.uuid)
                ?? EditRecord(
                    assetID: source.portableAssetID,
                    documentData: encodedDocument
                )
            record.documentData = encodedDocument
            if record.modelContext == nil {
                modelContext.insert(record)
            }
            updateLocator(on: record, for: source.url)
            try persist()
            status = .ready
            writeStartSignal?.yield(())
            if artificialWriteDelay > .zero {
                let delay = artificialWriteDelay
                await Task.detached {
                    try? await Task.sleep(for: delay)
                }.value
            }
        } catch {
            status = .writeFailure(error.localizedDescription)
            throw error
        }
    }

    func save(_ document: EditDocument, for assetID: PhotoAssetID, url: URL? = nil) async throws {
        try await save(document, for: EditSourceReference(assetID: assetID, url: url))
    }

    /// Remove every record that identifies the source. The path match matters for a source that
    /// was relinked before it was deleted: the current asset ID is normally enough, but keeping
    /// the locator cleanup here prevents an old moved-source record from surviving the action.
    func delete(for source: EditSourceReference) throws {
        markIO()
        if canonicalPackageRoot != nil {
            // Deleting a projection row must not delete the package's immutable revision. A later
            // load or an explicit rebuild repopulates the row from the canonical sidecar.
            try deleteProjection(for: source)
            status = .ready
            return
        }
        do {
            var records: [EditRecord] = []
            if let direct = try fetchRecord(assetID: source.portableAssetID.uuid) {
                records.append(direct)
            }
            if let url = source.url,
               let located = try fetchRecord(sourcePath: sourcePath(for: url)),
               !records.contains(where: { $0 === located }) {
                records.append(located)
            }
            guard !records.isEmpty else {
                status = .ready
                return
            }

            records.forEach(modelContext.delete)
            try persist()
            status = .ready
        } catch {
            modelContext.rollback()
            status = .writeFailure(error.localizedDescription)
            throw error
        }
    }

    func delete(for assetID: PhotoAssetID, url: URL? = nil) throws {
        try delete(for: EditSourceReference(assetID: assetID, url: url))
    }

    /// Rebuilds the local SwiftData projection from every current package edit sidecar.
    ///
    /// The package is read completely before the local model is changed. A malformed sidecar or
    /// missing asset therefore leaves the old projection intact and reports the failure to the
    /// caller. Assets with no edit revision intentionally have no local row because the neutral
    /// document is implicit in both representations.
    @discardableResult
    func rebuildProjectionFromPackage() throws -> Int {
        markIO()
        guard let packageRoot = canonicalPackageRoot else {
            return try rebuildProjectionFromLocalStore()
        }

        do {
            let package = try PortableLibraryPackage.openForQuery(at: packageRoot)
            var documents: [(PortablePhotoAssetID, EditDocument)] = []
            for shard in PortableLibraryPackage.allShards {
                let membership = try package.readMembershipShard(shard)
                for entry in membership.entries where !entry.isTombstone {
                    let record = try package.readAssetRecord(for: entry.assetID)
                    guard record.currentRevision > 0 else { continue }
                    let sidecar = try package.readEditSidecar(for: entry.assetID)
                    documents.append((entry.assetID, sidecar.native.document))
                }
            }

            let existing = try modelContext.fetch(FetchDescriptor<EditRecord>())
            let desired = Set(documents.map { $0.0.uuid })
            for record in existing where !desired.contains(record.assetID) {
                modelContext.delete(record)
            }
            for (assetID, document) in documents {
                let record = try fetchRecord(assetID: assetID.uuid)
                    ?? EditRecord(assetID: assetID, document: document)
                record.documentData = try JSONEncoder().encode(document)
                if record.modelContext == nil { modelContext.insert(record) }
            }
            try modelContext.save()
            status = .ready
            return documents.count
        } catch {
            modelContext.rollback()
            let failure = Status.packageFailure(error.localizedDescription)
            status = failure
            retainWorstActionableStatus(failure)
            throw error
        }
    }

    private func loadFromCanonicalPackage(for source: EditSourceReference)
        -> EditDocumentLoadResult
    {
        guard let packageRoot = canonicalPackageRoot else {
            return finishLoad(document: EditDocument(), found: false, status: .ready)
        }
        do {
            let package = try PortableLibraryPackage.openForQuery(at: packageRoot)
            let record = try package.readAssetRecord(for: source.portableAssetID)
            guard record.currentRevision > 0 else {
                return finishLoad(document: EditDocument(), found: false, status: .ready)
            }
            let sidecar = try package.readEditSidecar(for: source.portableAssetID)
            let document = sidecar.native.document

            // This write is deliberately best-effort. It is a projection refresh, not part of the
            // durable edit commit, and losing it must never turn a valid package edit into a blank
            // document on the next open.
            try? cacheProjection(document, encoded: try JSONEncoder().encode(document), for: source)
            return finishLoad(document: document, found: true, status: .ready)
        } catch {
            let failure = Status.packageFailure(error.localizedDescription)
            return finishLoad(document: EditDocument(), found: false, status: failure)
        }
    }

    private func saveToCanonicalPackage(
        _ document: EditDocument,
        for source: EditSourceReference,
        lookBytes: [Data] = []
    ) async throws {
        guard let packageRoot = canonicalPackageRoot, let packageLease else {
            throw StoreError.cannotWrite("the canonical edit package is unavailable")
        }

        // Match the legacy store's contract: invalid documents fail before an I/O attempt and do
        // not create an empty projection row.
        let encodedDocument = try JSONEncoder().encode(document)
        saveAttemptCount += 1
        do {
            if failuresRemaining > 0 {
                failuresRemaining -= 1
                throw StoreError.cannotWrite("injected persistence failure")
            }
            let package = try PortableLibraryPackage.openForQuery(at: packageRoot)
            let resolvedLookBytes = document.lut.lutID.flatMap { embeddedLookBytes[$0.raw] }
            _ = try package.appendEditRevision(
                for: source.portableAssetID, document: document,
                lookBytes: lookBytes + (resolvedLookBytes.map { [$0] } ?? []),
                lease: packageLease
            )
            // The package commit is complete before this projection update begins. If the local
            // cache cannot be updated, the canonical sidecar remains the source of truth.
            try? cacheProjection(document, encoded: encodedDocument, for: source)
            writeCount += 1
            status = .ready
            writeStartSignal?.yield(())
            if artificialWriteDelay > .zero {
                let delay = artificialWriteDelay
                await Task.detached {
                    try? await Task.sleep(for: delay)
                }.value
            }
        } catch {
            status = .writeFailure(error.localizedDescription)
            throw error
        }
    }

    private func cacheProjection(
        _ document: EditDocument,
        encoded: Data,
        for source: EditSourceReference
    ) throws {
        let record = try fetchRecord(assetID: source.portableAssetID.uuid)
            ?? EditRecord(assetID: source.portableAssetID, documentData: encoded)
        record.documentData = encoded
        if record.modelContext == nil { modelContext.insert(record) }
        updateLocator(on: record, for: source.url)
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    private func deleteProjection(for source: EditSourceReference) throws {
        var records: [EditRecord] = []
        if let direct = try fetchRecord(assetID: source.portableAssetID.uuid) {
            records.append(direct)
        }
        if let url = source.url,
           let located = try fetchRecord(sourcePath: sourcePath(for: url)),
           !records.contains(where: { $0 === located }) {
            records.append(located)
        }
        guard !records.isEmpty else { return }
        records.forEach(modelContext.delete)
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    private func rebuildProjectionFromLocalStore() throws -> Int {
        try modelContext.fetch(FetchDescriptor<EditRecord>()).count
    }

    private func fetchRecord(assetID: UUID) throws -> EditRecord? {
        var descriptor = FetchDescriptor<EditRecord>(
            predicate: #Predicate { $0.assetID == assetID })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    /// Resolves the common moved-key case in SQLite before falling back to bookmark resolution.
    private func fetchRecord(sourcePath: String) throws -> EditRecord? {
        var descriptor = FetchDescriptor<EditRecord>(
            predicate: #Predicate { $0.sourcePath == sourcePath })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    /// Fetches only the fields needed to identify a moved source. `documentData` can be a large
    /// encoded edit graph, so leaving it out keeps an unedited-photo open from deserializing every
    /// saved document before the matching record is known. Accessing `record.documentData` below
    /// still faults in the document for the one record that actually matches.
    private func fetchRecordsForRelinking() throws -> [EditRecord] {
        relinkFallbackScanCount += 1
        var descriptor = FetchDescriptor<EditRecord>()
        descriptor.propertiesToFetch = [
            \EditRecord.assetID,
            \EditRecord.sourcePath,
            \EditRecord.sourceBookmark,
        ]
        return try modelContext.fetch(descriptor)
    }

    private func persist() throws {
        saveAttemptCount += 1
        if failuresRemaining > 0 {
            failuresRemaining -= 1
            throw StoreError.cannotWrite("injected persistence failure")
        }
        do {
            try modelContext.save()
            writeCount += 1
        } catch {
            throw StoreError.cannotWrite(error.localizedDescription)
        }
    }

    /// Relinks a record using a keep-newest policy. The record discovered through the current
    /// source URL is the newest observation, so an occupied target record is the loser. Deleting
    /// that loser before assigning the unique key avoids a uniqueness violation. If persistence
    /// fails, roll back the deletion, rekey, and locator update so a later load starts cleanly.
    private func relink(
        _ record: EditRecord,
        document: EditDocument,
        to key: UUID,
        for url: URL,
        replacing occupiedRecord: EditRecord?
    ) -> EditDocumentLoadResult {
        if let occupiedRecord, occupiedRecord !== record {
            modelContext.delete(occupiedRecord)
        }
        record.assetID = key
        updateLocator(on: record, for: url)
        var loadStatus: Status = .relinked
        do {
            try persist()
        } catch {
            modelContext.rollback()
            loadStatus = .writeFailure(error.localizedDescription)
        }
        return finishLoad(document: document, found: true, status: loadStatus)
    }

    private func markIO() {
        lastIOWasMainThread = Thread.isMainThread
    }

    /// Every load reports only the status produced while resolving that source. Store-level
    /// persistence health is updated separately so a prior photo cannot taint this result.
    private func finishLoad(
        document: EditDocument,
        found: Bool,
        status loadStatus: Status
    ) -> EditDocumentLoadResult {
        status = loadStatus
        if loadStatus.isActionable {
            retainWorstActionableStatus(loadStatus)
        }
        return EditDocumentLoadResult(document: document, found: found, status: loadStatus)
    }

    private var loadBaselineStatus: Status {
        // A store that fell back to memory cannot provide a normal ready load. A transient
        // write failure on a previous operation, however, belongs to that operation only and
        // must not leak into an unrelated read.
        persistenceUnavailable ? status : .ready
    }

    private func retainWorstActionableStatus(_ candidate: Status) {
        guard candidate.isActionable else { return }
        guard let current = worstActionableStatus else {
            worstActionableStatus = candidate
            return
        }
        if candidate.severity >= current.severity {
            worstActionableStatus = candidate
        }
    }

    private func sourcePath(for url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }

    /// Explicit portable identities are already relocation-stable. Only the compatibility API
    /// needs the old locator-based relink behavior while callers finish adopting the new value.
    private func usesLegacyIdentityBridge(for source: EditSourceReference) -> Bool {
        source.portableAssetID == PortablePhotoAssetID.compatibility(from: source.assetID)
    }

    private func updateLocator(on record: EditRecord, for url: URL?) {
        guard let url else { return }
        let canonicalPath = sourcePath(for: url)
        guard record.sourcePath != canonicalPath else { return }
        record.sourcePath = canonicalPath
        record.sourceFileName = url.lastPathComponent
        record.sourceBookmark =
            (try? url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )) ?? (try? url.bookmarkData())
    }

    private func matches(_ record: EditRecord, url: URL) -> Bool {
        let canonical = url.standardizedFileURL.resolvingSymlinksInPath()
        if record.sourcePath == canonical.path { return true }
        guard let bookmarkData = record.sourceBookmark else { return false }
        var stale = false
        guard
            let resolved = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            )
        else { return false }
        return resolved.standardizedFileURL.resolvingSymlinksInPath() == canonical
    }
}

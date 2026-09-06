import Foundation
import SwiftData

/// The source information persisted alongside an edit document.
struct EditSourceReference: Codable, Sendable, Equatable {
    let assetID: PhotoAssetID
    let url: URL?

    init(assetID: PhotoAssetID, url: URL? = nil) {
        self.assetID = assetID
        self.url = url
    }
}

/// The result of looking up one source in the edit store.
struct EditDocumentLoadResult: Sendable, Equatable {
    let document: EditDocument
    let found: Bool
    let status: EditDocumentStore.Status
}

/// Actor-isolated SwiftData persistence for per-photo edit documents.
///
/// Each photo is an `EditRecord`, so saving one edit only saves the changed SwiftData row. The
/// store deliberately has no migration path from the former JSON catalog: the product has not
/// shipped, so old local edits may be orphaned when this schema is first opened.
@ModelActor
actor EditDocumentStore {

    enum Status: Sendable, Equatable {
        case ready
        case relinked
        case writeFailure(String)

        var message: String? {
            switch self {
            case .ready:
                return nil
            case .relinked:
                return "Restored edits after the source photo moved."
            case .writeFailure(let detail):
                return "Could not save edit records: \(detail)"
            }
        }

        var isActionable: Bool {
            switch self {
            case .ready:
                return false
            case .relinked, .writeFailure:
                return true
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

    private var artificialWriteDelay: Duration = .zero
    private var writeStartSignal: AsyncStream<Void>.Continuation? = nil
    private var failuresRemaining: Int = 0
    private var persistenceUnavailable = false
    private(set) var status: Status = .ready

    /// The production store lives beside the other Lumo application-support data.
    static var defaultFileURL: URL {
        let base =
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return
            base
            .appendingPathComponent("Lumo", isDirectory: true)
            .appendingPathComponent("EditStore.store")
    }

    /// Builds a local-only SwiftData container. CloudKit is explicitly disabled for this store.
    static func makeContainer(url: URL) throws -> ModelContainer {
        let schema = Schema([EditRecord.self])
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let configuration = ModelConfiguration(
            "EditStore",
            schema: schema,
            url: url,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private static func makeInMemoryContainer() -> ModelContainer {
        let schema = Schema([EditRecord.self])
        let configuration = ModelConfiguration(
            "EditStore",
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        // A schema made from the same model that is accepted by makeContainer cannot fail here.
        return try! ModelContainer(for: schema, configurations: [configuration])
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
        self.writeStartSignal = writeStartSignal
        self.status = initialStatus
    }

    func load(for source: EditSourceReference) -> EditDocumentLoadResult {
        markIO()
        let key = source.assetID.description

        do {
            if let record = try fetchRecord(assetID: key) {
                if let url = source.url, sourcePath(for: url) != record.sourcePath {
                    let previousStatus = status
                    updateLocator(on: record, for: url)
                    status = .relinked
                    do {
                        try persist()
                    } catch {
                        status = .writeFailure(error.localizedDescription)
                    }
                    restoreActionableStatus(after: previousStatus)
                }
                return EditDocumentLoadResult(
                    document: record.document, found: true, status: status)
            }

            guard let url = source.url,
                let record = try fetchRecords().first(where: { matches($0, url: url) })
            else {
                return EditDocumentLoadResult(
                    document: EditDocument(), found: false, status: status)
            }

            record.assetID = key
            updateLocator(on: record, for: url)
            let previousStatus = status
            status = .relinked
            do {
                try persist()
            } catch {
                status = .writeFailure(error.localizedDescription)
            }
            restoreActionableStatus(after: previousStatus)
            return EditDocumentLoadResult(document: record.document, found: true, status: status)
        } catch {
            status = .writeFailure(error.localizedDescription)
            return EditDocumentLoadResult(document: EditDocument(), found: false, status: status)
        }
    }

    func load(for assetID: PhotoAssetID) -> EditDocumentLoadResult {
        load(for: EditSourceReference(assetID: assetID))
    }

    func document(for source: EditSourceReference) -> EditDocument? {
        let result = load(for: source)
        return result.found ? result.document : nil
    }

    func save(_ document: EditDocument, for source: EditSourceReference) async throws {
        markIO()
        do {
            guard !persistenceUnavailable else {
                throw StoreError.cannotWrite(status.message ?? "edit database is unavailable")
            }
            let record =
                try fetchRecord(assetID: source.assetID.description)
                ?? EditRecord(
                    assetID: source.assetID.description,
                    document: document
                )
            record.document = document
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

    private func fetchRecord(assetID: String) throws -> EditRecord? {
        var descriptor = FetchDescriptor<EditRecord>(
            predicate: #Predicate { $0.assetID == assetID })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func fetchRecords() throws -> [EditRecord] {
        try modelContext.fetch(FetchDescriptor<EditRecord>())
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

    private func markIO() {
        lastIOWasMainThread = Thread.isMainThread
    }

    private func restoreActionableStatus(after previousStatus: Status) {
        if previousStatus.isActionable, case .writeFailure = status {
            return
        }
        if previousStatus.isActionable {
            status = previousStatus
        }
    }

    private func sourcePath(for url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
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

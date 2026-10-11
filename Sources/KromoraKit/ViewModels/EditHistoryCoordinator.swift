import Foundation

/// The package edit-history operations the coordinator needs. `EditDocumentStore` conforms; tests
/// supply a fake.
protocol EditHistoryStore: Sendable {
    func history(for source: EditSourceReference) async throws -> [PortablePackageEditRevision]
    func currentRevision(for source: EditSourceReference) async throws -> UInt64
    func selectRevision(_ revision: UInt64, for source: EditSourceReference) async throws
    func saveSnapshot(_ document: EditDocument, named name: String, for source: EditSourceReference) async throws
    func save(_ document: EditDocument, for source: EditSourceReference) async throws
}

extension EditDocumentStore: EditHistoryStore {}

/// Main-actor owner of the durable (package-backed) edit history of the active photo and of the
/// store I/O that browses, restores, snapshots and branches it.
///
/// Every async store call is fenced: its result is applied only if the active source reference is
/// still the one it was issued for. Writes (restore, snapshot, virtual copy) first end the open
/// undo gesture and wait for the persistence flush, so the package sees the latest document.
/// `AppViewModel` stays the sole owner of the published `EditDocument`; it supplies narrow closures
/// and applies the restored document itself. The coordinator never holds the view model.
@MainActor
final class EditHistoryCoordinator {

    /// The root's side of the boundary.
    struct Environment {
        var activeSourceReference: @MainActor () -> EditSourceReference?
        var currentDocument: @MainActor () -> EditDocument
        var endUndoGrouping: @MainActor () -> Void
        /// Wait for pending edits to reach the package. `false` aborts the operation silently; the
        /// persistence coordinator reports its own failure.
        var flushPersistence: @MainActor () async -> Bool
        /// Move the in-memory session and document to a restored revision. `priorDocuments` are the
        /// non-snapshot revisions before it, oldest first.
        var adoptRestoredRevision: @MainActor (_ document: EditDocument, _ priorDocuments: [EditDocument]) -> Void
        var reportStatus: @MainActor (String) -> Void
    }

    /// A virtual copy the root has created in the package, ready to receive the current edits.
    struct VirtualCopy {
        let sourceReference: EditSourceReference
        let displayName: String
        let assetID: PortablePhotoAssetID
    }

    private(set) var history: [PortablePackageEditRevision] = [] {
        willSet { willChange() }
    }
    private(set) var currentRevision: UInt64 = 0 {
        willSet { willChange() }
    }

    private let store: any EditHistoryStore
    private let environment: Environment
    private let willChange: @MainActor () -> Void

    /// `willChange` runs before each published-state mutation so the root can forward
    /// `objectWillChange`.
    init(
        store: any EditHistoryStore,
        environment: Environment,
        willChange: @escaping @MainActor () -> Void
    ) {
        self.store = store
        self.environment = environment
        self.willChange = willChange
    }

    private func clear() {
        history = []
        currentRevision = 0
    }

    /// Reload the active photo's history. Clears it when no photo is active or the read fails.
    @discardableResult
    func refresh() -> Task<Void, Never>? {
        guard let reference = environment.activeSourceReference() else {
            clear()
            return nil
        }
        return Task { [weak self, store] in
            do {
                let history = try await store.history(for: reference)
                let currentRevision = try await store.currentRevision(for: reference)
                guard let self, self.environment.activeSourceReference() == reference else { return }
                self.history = history
                self.currentRevision = currentRevision
            } catch {
                guard let self, self.environment.activeSourceReference() == reference else { return }
                self.clear()
            }
        }
    }

    /// Navigate to a durable edit state without creating a new revision.
    @discardableResult
    func restore(_ revision: UInt64) -> Task<Void, Never>? {
        guard let value = history.first(where: { $0.revision == revision }) else { return nil }
        environment.endUndoGrouping()
        guard let reference = environment.activeSourceReference() else { return nil }
        return Task { [weak self, store, environment] in
            guard await environment.flushPersistence() else { return }
            do {
                try await store.selectRevision(revision, for: reference)
                guard let self, environment.activeSourceReference() == reference else { return }
                self.currentRevision = revision
                let priorDocuments = self.history
                    .filter { $0.revision < revision && $0.snapshotName == nil }
                    .map(\.document)
                environment.adoptRestoredRevision(value.document, priorDocuments)
                self.refresh()
            } catch {
                guard environment.activeSourceReference() == reference else { return }
                environment.reportStatus("Could not navigate edit history: \(error.localizedDescription)")
            }
        }
    }

    @discardableResult
    func saveSnapshot(named name: String) -> Task<Void, Never>? {
        guard let reference = environment.activeSourceReference() else { return nil }
        environment.endUndoGrouping()
        let document = environment.currentDocument()
        return Task { [weak self, store, environment] in
            guard await environment.flushPersistence() else { return }
            do {
                try await store.saveSnapshot(document, named: name, for: reference)
                guard let self, environment.activeSourceReference() == reference else { return }
                environment.reportStatus("Saved snapshot ‘\(name)’")
                self.refresh()
            } catch {
                guard environment.activeSourceReference() == reference else { return }
                environment.reportStatus("Could not save snapshot: \(error.localizedDescription)")
            }
        }
    }

    /// Flush, create the copy through `makeCopy`, give it the current edits, then hand it to
    /// `didCreate` (which reloads the collection, reports and opens it). A throw from any step is
    /// reported once.
    @discardableResult
    func createVirtualCopy(
        of reference: EditSourceReference,
        makeCopy: @escaping @MainActor () throws -> VirtualCopy,
        didCreate: @escaping @MainActor (VirtualCopy) throws -> Void
    ) -> Task<Void, Never> {
        environment.endUndoGrouping()
        let document = environment.currentDocument()
        return Task { [store, environment] in
            guard await environment.flushPersistence() else { return }
            guard environment.activeSourceReference() == reference else { return }
            do {
                let copy = try makeCopy()
                try await store.save(document, for: copy.sourceReference)
                guard environment.activeSourceReference() == reference else { return }
                try didCreate(copy)
            } catch {
                guard environment.activeSourceReference() == reference else { return }
                environment.reportStatus("Could not create virtual copy: \(error.localizedDescription)")
            }
        }
    }
}

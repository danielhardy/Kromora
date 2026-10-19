import Foundation

/// Reviews a Photos picker selection before anything is imported. The system picker cannot show
/// library membership, so the choice it returns is confirmed here: each item is tagged when its
/// bytes are already in the open library, and tagged items start unselected.
///
/// The package does not record Photos local identifiers, so membership is the same content-digest
/// rule `PortablePackageImporter` applies. Each item is transferred and hashed one at a time off
/// the main actor, progressively and cancellably; a later import transfers only what is confirmed.
@MainActor
@Observable
final class PhotosImportReviewCoordinator {
    struct Item: Identifiable, Equatable, Sendable {
        let selection: PhotosImportSelection
        let name: String
        var id: String { String(selection.ordinal) }
    }

    private(set) var items: [Item] = []
    private(set) var inLibrary: Set<String> = []
    /// Items whose original bytes do not match their filename; the import will skip them.
    private(set) var mismatched: [String: String] = [:]
    private(set) var checked = 0
    private(set) var isChecking = false
    private(set) var selection = MediaVolumeSelectionModel()
    var hidesInLibrary = false
    var isPresented = false

    /// Loads the open library's content hashes off the main actor. Nil when no library is open,
    /// in which case nothing is tagged.
    var libraryMatcherLoader: (@Sendable () async throws -> LibraryMembershipMatcher)?
    var onImport: (@MainActor ([PhotosImportSelection], any PhotosImportProviding) -> Void)?

    private var provider: (any PhotosImportProviding)?
    private var checkTask: Task<Void, Never>?
    private var reviewID = UUID()

    var visibleItems: [Item] {
        guard hidesInLibrary else { return items }
        return items.filter { !inLibrary.contains($0.id) }
    }

    var selectedItems: [Item] {
        items.filter { selection.contains(id: $0.id) }
    }

    func begin(selections: [PhotosImportSelection], provider: any PhotosImportProviding) {
        stopChecking()
        let id = UUID()
        reviewID = id
        self.provider = provider
        items = PhotosImportNaming.resolve(selections, provider: provider).map {
            Item(selection: $0, name: $0.name ?? "")
        }
        inLibrary = []
        mismatched = [:]
        checked = 0
        hidesInLibrary = false
        selection = MediaVolumeSelectionModel()
        selection.selectAll(ids: items.map(\.id))
        isPresented = !items.isEmpty
        startChecking(operationID: id)
    }

    func toggle(_ item: Item) {
        selection.toggle(id: item.id)
    }

    func selectRange(to item: Item) {
        selection.selectRange(toID: item.id, in: visibleItems.map(\.id))
    }

    func selectAll() {
        selection.selectAll(ids: items.map(\.id), excluding: inLibrary)
    }

    func selectNone() {
        selection.clear()
    }

    /// Imports the confirmed items and closes the review.
    func confirm() {
        let chosen = selectedItems.map(\.selection)
        guard !chosen.isEmpty, let provider else { return }
        close()
        onImport?(chosen, provider)
    }

    func cancel() {
        close()
    }

    func shutdown() {
        close()
        onImport = nil
        libraryMatcherLoader = nil
    }

    private func close() {
        stopChecking()
        reviewID = UUID()
        isPresented = false
        provider = nil
        items = []
        inLibrary = []
        mismatched = [:]
        selection = MediaVolumeSelectionModel()
    }

    private func stopChecking() {
        checkTask?.cancel()
        checkTask = nil
        isChecking = false
    }

    private func startChecking(operationID: UUID) {
        guard let loader = libraryMatcherLoader, let provider, !items.isEmpty else { return }
        let pending = items
        isChecking = true
        checkTask = Task { [weak self] in
            let matcher = try? await loader()
            for item in pending {
                guard !Task.isCancelled else { return }
                let result = await Self.inspect(item, provider: provider, matcher: matcher)
                guard let self, self.reviewID == operationID, !Task.isCancelled else { return }
                self.record(item, result: result)
            }
            guard let self, self.reviewID == operationID else { return }
            self.isChecking = false
            self.checkTask = nil
        }
    }

    /// An item whose bytes cannot be transferred stays untagged: the import reports it as a
    /// failure, and the review must not claim membership it cannot prove.
    private static func inspect(
        _ item: Item, provider: any PhotosImportProviding, matcher: LibraryMembershipMatcher?
    ) async -> (isMember: Bool, mismatch: String?) {
        guard let data = try? await provider.transferData(for: item.selection) else { return (false, nil) }
        let mismatch = OriginalFileTypeCheck.mismatchReason(name: item.name, data: data)
        guard let matcher, !matcher.isEmpty else { return (false, mismatch) }
        return (await contains(data, in: matcher), mismatch)
    }

    @concurrent private static func contains(_ data: Data, in matcher: LibraryMembershipMatcher) async -> Bool {
        matcher.contains(contentHash: LibraryMembershipMatcher.contentHash(of: data))
    }

    /// Tags a match and drops it from the default selection. An item the user already clicked
    /// keeps its state, so a late result never undoes a deliberate choice.
    private func record(_ item: Item, result: (isMember: Bool, mismatch: String?)) {
        checked += 1
        if let reason = result.mismatch {
            mismatched[item.id] = reason
            selection.deselectDefaults([item.id])
        }
        guard result.isMember else { return }
        inLibrary.insert(item.id)
        selection.deselectDefaults([item.id])
    }
}

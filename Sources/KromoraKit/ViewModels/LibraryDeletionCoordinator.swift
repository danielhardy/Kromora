import Foundation

/// Owns the destructive half of a library deletion. It flushes edits before touching an item,
/// clears analysis caches, preserves referenced originals, trashes managed originals, and removes
/// the corresponding edit record. Presentation cleanup is returned as a value to the root.
@MainActor
final class LibraryDeletionCoordinator {
    private let collection: ImageCollection
    private let persistence: EditPersistenceCoordinator
    private let editStore: EditDocumentStore
    private let photoAnalysis: PhotoAnalysisCoordinator
    private let portableLibrary: PortableLibrarySession?
    private let persistenceIdentity: (ImageCollection.Item) -> PortablePhotoIdentity?

    init(
        collection: ImageCollection,
        persistence: EditPersistenceCoordinator,
        editStore: EditDocumentStore,
        photoAnalysis: PhotoAnalysisCoordinator,
        portableLibrary: PortableLibrarySession?,
        persistenceIdentity: @escaping (ImageCollection.Item) -> PortablePhotoIdentity?
    ) {
        self.collection = collection
        self.persistence = persistence
        self.editStore = editStore
        self.photoAnalysis = photoAnalysis
        self.portableLibrary = portableLibrary
        self.persistenceIdentity = persistenceIdentity
    }

    func delete(_ candidates: [ImageCollection.DeletionCandidate]) async -> LibraryDeletionResult {
        guard !candidates.isEmpty else {
            return LibraryDeletionResult(deletedIDs: [], failures: [])
        }

        let flushResult = await persistence.flush()
        guard flushResult.succeeded else {
            let detail: String
            if case .failure(let message) = flushResult {
                detail = message
            } else {
                detail = "pending edits were not saved"
            }
            return LibraryDeletionResult(
                deletedIDs: [],
                failures: ["Could not remove photos because their edits could not be saved: \(detail)"]
            )
        }

        var deletedIDs: [PhotoAssetID] = []
        var failures: [String] = []
        guard let portableLibrary else {
            return LibraryDeletionResult(
                deletedIDs: [],
                failures: ["Could not remove photos because the library package is unavailable."]
            )
        }
        for candidate in candidates {
            guard let item = collection.items.first(where: { $0.id == candidate.id }) else {
                continue
            }
            do {
                try await photoAnalysis.removeCaches(for: item.asset.source.portableIdentity.assetID)
            } catch {
                failures.append(
                    "Could not clear cached analysis for \(candidate.displayName): "
                        + error.localizedDescription
                )
                continue
            }

            do {
                try portableLibrary.removeFromLibrary(item.asset.source.portableIdentity.assetID)
                try await editStore.delete(
                    for: EditSourceReference(
                        assetID: candidate.id,
                        portableIdentity: persistenceIdentity(item),
                        url: candidate.url
                    )
                )
                deletedIDs.append(candidate.id)
            } catch {
                failures.append(
                    "Could not remove \(candidate.displayName): " + error.localizedDescription
                )
            }
        }
        return LibraryDeletionResult(deletedIDs: deletedIDs, failures: failures)
    }
}

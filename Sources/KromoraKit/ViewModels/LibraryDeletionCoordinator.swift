import Foundation

/// Cross-feature cleanup a deletion fans out to. The root implements it with the stores it owns;
/// the coordinator never sees `AppViewModel`.
@MainActor
protocol LibraryDeletionCleanupDestination: AnyObject {
    var activeDeletionAssetID: PhotoAssetID? { get }
    func removeEditedThumbnails(for assetIDs: Set<PhotoAssetID>)
    func removeThumbnailFrames(for assetIDs: Set<PortablePhotoAssetID>)
    func removeEditorSessions(for assetIDs: Set<PhotoAssetID>)
    func syncPortableSelectionAfterDeletion()
    func invalidatePreviewIdentities(_ identities: Set<PortablePhotoIdentity>) async
    func invalidateRenderCaches() async
}

/// What the root applies to the active photo after a deletion.
enum LibraryDeletionActivePhotoAction: Equatable, Sendable {
    case none
    case openSelection
    case clearSource
}

/// What the root presents after a deletion.
enum LibraryDeletionMessage: Equatable, Sendable {
    case none
    case status(String)
    case error(String)
}

struct LibraryDeletionOutcome: Equatable, Sendable {
    let result: LibraryDeletionResult
    let activePhoto: LibraryDeletionActivePhotoAction
    let message: LibraryDeletionMessage
}

/// Owns library deletion: the destructive half (flush edits, clear analysis caches, preserve
/// referenced originals, trash managed originals, remove the edit record) and the cleanup
/// fan-out after it. The active-photo decision and messaging are returned as values to the root.
@MainActor
final class LibraryDeletionCoordinator {
    weak var destination: (any LibraryDeletionCleanupDestination)?
    private let collection: ImageCollection
    private let persistence: EditPersistenceCoordinator
    private let editStore: EditDocumentStore
    private let photoAnalysis: PhotoAnalysisCoordinator
    private var portableLibrary: PortableLibrarySession?
    private let persistenceIdentity: (ImageCollection.Item) -> PortablePhotoIdentity?
    private let allowsUnregisteredSourceDeletion: Bool
    private var inFlightIDs: Set<PhotoAssetID> = []

    /// True while a deletion batch is running; the root rejects overlapping requests.
    var isDeleting: Bool { !inFlightIDs.isEmpty }

    init(
        collection: ImageCollection,
        persistence: EditPersistenceCoordinator,
        editStore: EditDocumentStore,
        photoAnalysis: PhotoAnalysisCoordinator,
        portableLibrary: PortableLibrarySession?,
        persistenceIdentity: @escaping (ImageCollection.Item) -> PortablePhotoIdentity?,
        allowsUnregisteredSourceDeletion: Bool = false
    ) {
        self.collection = collection
        self.persistence = persistence
        self.editStore = editStore
        self.photoAnalysis = photoAnalysis
        self.portableLibrary = portableLibrary
        self.persistenceIdentity = persistenceIdentity
        self.allowsUnregisteredSourceDeletion = allowsUnregisteredSourceDeletion
    }

    /// Supplies the opened session to a coordinator composed before the package was open.
    func bind(portableLibrary: PortableLibrarySession) { self.portableLibrary = portableLibrary }

    /// Delete, then clean up dependent state in a fixed order: per-asset stores and sessions,
    /// collection removal, then awaited preview/render cache invalidation before the caller
    /// decides what to do with the active photo.
    func deleteAndCleanUp(
        _ candidates: [ImageCollection.DeletionCandidate]
    ) async -> LibraryDeletionOutcome {
        let identitiesByID: [PhotoAssetID: PortablePhotoIdentity] = Dictionary(
            uniqueKeysWithValues: candidates.compactMap { candidate in
                guard let item = collection.items.first(where: { $0.id == candidate.id }) else {
                    return nil
                }
                return (candidate.id, item.asset.source.portableIdentity)
            }
        )
        let result = await delete(candidates)
        guard !result.deletedIDs.isEmpty else {
            return LibraryDeletionOutcome(
                result: result,
                activePhoto: .none,
                message: result.failures.first.map { .error($0) } ?? .none
            )
        }

        let deletedSet = Set(result.deletedIDs)
        destination?.removeEditedThumbnails(for: deletedSet)
        destination?.removeThumbnailFrames(
            for: Set(deletedSet.map { PortablePhotoAssetID.compatibility(from: $0) })
        )
        // Deletion is the lifecycle boundary for editor sessions, so removed photos cannot leave
        // their undo snapshots retained.
        destination?.removeEditorSessions(for: deletedSet)
        _ = collection.removeItems(with: deletedSet)
        if collection.isPortableWindowed {
            // Query controller already dropped tombstones via index delta; mirror the single
            // authority back into the window adapter so selection never points at a deleted ID.
            destination?.syncPortableSelectionAfterDeletion()
        }
        await destination?.invalidatePreviewIdentities(
            Set(result.deletedIDs.compactMap { identitiesByID[$0] })
        )
        await destination?.invalidateRenderCaches()

        var activePhoto = LibraryDeletionActivePhotoAction.none
        if let active = destination?.activeDeletionAssetID, deletedSet.contains(active) {
            activePhoto = collection.selectedItem != nil ? .openSelection : .clearSource
        }

        let message: LibraryDeletionMessage
        if !result.failures.isEmpty {
            message = .error(
                "Removed \(result.deletedIDs.count) photo(s), but some photos could not be removed: "
                    + result.failures.joined(separator: " ")
            )
        } else {
            message = .status(
                result.deletedIDs.count == 1
                    ? "Photo removed from Library"
                    : "Removed \(result.deletedIDs.count) photos from Library"
            )
        }
        return LibraryDeletionOutcome(result: result, activePhoto: activePhoto, message: message)
    }

    func delete(_ candidates: [ImageCollection.DeletionCandidate]) async -> LibraryDeletionResult {
        guard !candidates.isEmpty else {
            return LibraryDeletionResult(deletedIDs: [], failures: [])
        }
        let ids = Set(candidates.map(\.id))
        // PortableLibrarySession serializes removals through one replaceable scheduler job ID.
        // Letting a disjoint batch enter would cancel the active job and could report a committed
        // tombstone as a failure, so keep the entire deletion workflow single-flight.
        guard !isDeleting else {
            return LibraryDeletionResult(
                deletedIDs: [],
                failures: ["A photo removal is already in progress."]
            )
        }
        inFlightIDs.formUnion(ids)
        defer { inFlightIDs.subtract(ids) }

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
                do {
                    try await portableLibrary.removeFromLibraryOffMain(item.asset.source.portableIdentity.assetID)
                } catch PortablePackageTrashError.alreadyRemoved {
                    // Membership is already tombstoned by an earlier, partially completed removal.
                    // Removal is idempotent: fall through to finish the edit-record cleanup so the
                    // item leaves the grid instead of failing on every retry.
                } catch let error as PortablePackageTrashError
                    where allowsUnregisteredSourceDeletion && isAssetNotFound(error)
                {
                    // Tests and headless clients can inject a legacy/current-folder projection
                    // while the package session remains a separate, empty package. In that
                    // compatibility boundary there is no package membership to tombstone: remove
                    // only the caller-owned edit record and leave the referenced source untouched.
                }
                try await editStore.delete(
                    for: EditSourceReference(
                        assetID: candidate.id,
                        portableIdentity: persistenceIdentity(item),
                        url: candidate.url
                    )
                )
                deletedIDs.append(candidate.id)
                // Publish each removal as it lands so the grid shrinks during a large batch.
                _ = collection.removeItems(with: [candidate.id])
            } catch {
                failures.append(
                    "Could not remove \(candidate.displayName): " + error.localizedDescription
                )
            }
        }
        return LibraryDeletionResult(deletedIDs: deletedIDs, failures: failures)
    }

    private func isAssetNotFound(_ error: PortablePackageTrashError) -> Bool {
        if case .assetNotFound = error { return true }
        return false
    }
}

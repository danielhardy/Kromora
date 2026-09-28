import Foundation

/// Narrow application boundary for the presentation bridge around a streamed Photos package
/// import. Package writes remain in `LibraryImportCoordinator`; this owner only sequences their
/// results with one collection refresh and the initial editor handoff.
@MainActor
protocol PhotosImportBatchDestination: AnyObject {
    func isCurrentPhotosImportBatch(_ operationID: UUID) -> Bool
    func writePhotosImportItem(
        _ item: ImageCollection.PhotoImportItem, rebuildIndex: Bool
    ) throws -> PortablePackageImportResult
    func writePhotosImportItemAsync(
        _ item: ImageCollection.PhotoImportItem, rebuildIndex: Bool
    ) async throws -> PortablePackageImportResult
    func refreshPhotosImportCollection() throws
    func openPhotosImportAsset(_ assetID: PortablePhotoAssetID)
    func presentPhotosImportInspector()
    func reportPhotosImportBatchError(_ message: String)
}

/// Owns only the batch bridge between Photos package writes and library/editor presentation.
/// It has no package, importer, document store, or application-model reference.
@MainActor
final class PhotosImportBatchCoordinator {
    private struct Batch {
        let operationID: UUID
        let packageWasEmpty: Bool
        var needsRefresh = false
        var firstAssetID: PortablePhotoAssetID?
    }

    weak var destination: (any PhotosImportBatchDestination)?
    private var batch: Batch?
    private var didPresentInspector = false

    init(destination: (any PhotosImportBatchDestination)? = nil) {
        self.destination = destination
    }

    var isBatchActive: Bool { batch != nil }

    func begin(operationID: UUID, totalCount: Int, packageWasEmpty: Bool, packageAvailable: Bool) {
        _ = totalCount
        batch = nil
        didPresentInspector = false
        guard packageAvailable else { return }
        batch = Batch(operationID: operationID, packageWasEmpty: packageWasEmpty)
    }

    func insert(
        _ item: ImageCollection.PhotoImportItem, ordinal: Int
    ) -> PhotosImportInsertionOutcome {
        _ = ordinal
        guard let destination else { return .failed("The import destination is no longer available.") }
        guard let operationID = batch?.operationID, isCurrentBatch(operationID) else {
            return .failed("Photos import was superseded.")
        }
        do {
            let result = try destination.writePhotosImportItem(
                item, rebuildIndex: !isBatchActive
            )
            guard isCurrentBatch(operationID) else { return .failed("Photos import was superseded.") }
            return publish(result, item: item)
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    func insertAsync(
        _ item: ImageCollection.PhotoImportItem, ordinal: Int
    ) async -> PhotosImportInsertionOutcome {
        _ = ordinal
        guard let destination else { return .failed("The import destination is no longer available.") }
        guard let operationID = batch?.operationID, isCurrentBatch(operationID) else {
            return .failed("Photos import was superseded.")
        }
        do {
            let result = try await destination.writePhotosImportItemAsync(
                item, rebuildIndex: !isBatchActive
            )
            // A newer import may have started while the package worker was suspended.
            guard isCurrentBatch(operationID) else { return .failed("Photos import was superseded.") }
            return publish(result, item: item)
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    func finish() {
        guard let finishingBatch = batch else {
            reset()
            return
        }
        defer { reset() }
        guard isCurrent(finishingBatch) else { return }
        guard finishingBatch.needsRefresh else { return }
        do {
            try destination?.refreshPhotosImportCollection()
            guard isCurrent(finishingBatch) else { return }
            if finishingBatch.packageWasEmpty, let assetID = finishingBatch.firstAssetID {
                destination?.openPhotosImportAsset(assetID)
                presentInspectorOnce()
            }
        } catch {
            destination?.reportPhotosImportBatchError(
                "Kromora could not refresh the library after Photos import: "
                    + error.localizedDescription
            )
        }
    }

    func shutdown() {
        reset()
        destination = nil
    }

    private func isCurrentBatch(_ operationID: UUID) -> Bool {
        guard let batch, batch.operationID == operationID else { return false }
        return isCurrent(batch)
    }

    private func isCurrent(_ batch: Batch) -> Bool {
        destination?.isCurrentPhotosImportBatch(batch.operationID) == true
    }

    private func publish(
        _ result: PortablePackageImportResult,
        item: ImageCollection.PhotoImportItem
    ) -> PhotosImportInsertionOutcome {
        let assetID = result.imported.first?.assetID ?? result.duplicates.first?.existingAssetID
        if var batch {
            if batch.firstAssetID == nil { batch.firstAssetID = assetID }
            batch.needsRefresh = batch.needsRefresh || !result.imported.isEmpty
            self.batch = batch
        } else {
            do {
                try destination?.refreshPhotosImportCollection()
                if let assetID, result.imported.count > 0 {
                    destination?.openPhotosImportAsset(assetID)
                    presentInspectorOnce()
                }
            } catch {
                destination?.reportPhotosImportBatchError(error.localizedDescription)
                return .failed(error.localizedDescription)
            }
        }

        if let assetID = result.imported.first?.assetID {
            return .inserted("portable:\(assetID.raw)")
        }
        if let assetID = result.duplicates.first?.existingAssetID {
            return .duplicate("portable:\(assetID.raw)")
        }
        if let failure = result.failures.first { return .failed(failure.reason) }
        _ = item
        return result.cancelled
            ? .failed("Photos import was cancelled before the package write completed.")
            : .failed("The package did not report an import outcome.")
    }

    private func presentInspectorOnce() {
        guard !didPresentInspector else { return }
        didPresentInspector = true
        destination?.presentPhotosImportInspector()
    }

    private func reset() {
        batch = nil
        didPresentInspector = false
    }
}

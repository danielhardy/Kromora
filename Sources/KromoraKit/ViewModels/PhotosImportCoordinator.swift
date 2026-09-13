import Foundation
import Photos
import PhotosUI
import SwiftUI

struct PhotosImportProgress: Equatable, Sendable {
    enum Phase: String, Sendable {
        case transferring
        case inserting

        var label: String {
            switch self {
            case .transferring: return "Transferring"
            case .inserting: return "Adding"
            }
        }
    }

    let total: Int
    var processed: Int
    var imported: Int
    var failed: Int
    var currentName: String?
    var phase: Phase

    var fraction: Double {
        guard total > 0 else { return 1 }
        return min(1, Double(processed) / Double(total))
    }
}

/// The value that crosses the Photos picker/UI boundary. The picker item itself stays inside the
/// provider so the import workflow can be exercised with a deterministic test provider.
struct PhotosImportSelection: Equatable, Sendable {
    let ordinal: Int
    let localIdentifier: String?
}

/// The small provider boundary needed by the import workflow. Production code adapts
/// `PhotosPickerItem`; tests can provide bytes, names, failures, and cancellation behavior without
/// constructing PhotosUI objects.
@MainActor
protocol PhotosImportProviding: AnyObject {
    func originalFilename(for selection: PhotosImportSelection) -> String?
    func transferData(for selection: PhotosImportSelection) async throws -> Data?
}

/// The PhotosUI/Photos implementation of the provider boundary. Filename lookup intentionally
/// remains here because it is provider metadata, not durable collection policy.
@MainActor
final class PhotosPickerImportProvider: PhotosImportProviding {
    private let items: [PhotosPickerItem]

    init(items: [PhotosPickerItem]) {
        self.items = items
    }

    func originalFilename(for selection: PhotosImportSelection) -> String? {
        guard let identifier = selection.localIdentifier else { return nil }
        let result = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
        guard let asset = result.firstObject else { return nil }
        return PHAssetResource.assetResources(for: asset)
            .first(where: { $0.type == .photo && !$0.originalFilename.isEmpty })?.originalFilename
    }

    func transferData(for selection: PhotosImportSelection) async throws -> Data? {
        guard items.indices.contains(selection.ordinal) else { return nil }
        return try await items[selection.ordinal].loadTransferable(type: Data.self)
    }
}

/// A provider failure is item-local: the controller records it and continues with the remaining
/// selections so successful originals are never discarded because a later transfer failed.
struct PhotosImportFailure: Equatable, Sendable {
    let ordinal: Int
    let name: String
    let reason: String
}

/// Application-side sink for the Photos import workflow. It admits durable payloads and owns the
/// source-load side effect; it does not own transfer progress or provider errors.
@MainActor
protocol PhotosImportDestination: AnyObject {
    func preparePhotosImport(totalCount: Int)
    func insertPhotosImport(_ item: ImageCollection.PhotoImportItem, ordinal: Int)
    func recordPhotosImportFailureDestination(name: String, ordinal: Int?)
    func finishPhotosImportDestination(cancelled: Bool)
}

/// Coordinates Photos provider interaction and the streamed durable import boundary. The view only
/// creates selections, supplies a provider, and forwards cancellation; all asynchronous item
/// iteration, hashing, progress, and failure handling lives here.
@MainActor
final class PhotosImportCoordinator: ObservableObject {
    @Published private(set) var progress: PhotosImportProgress?
    @Published private(set) var failures: [PhotosImportFailure] = []
    @Published private(set) var wasCancelled = false

    weak var destination: (any PhotosImportDestination)?
    private var task: Task<Void, Never>?
    private var operationID = UUID()
    var onStatus: ((String) -> Void)?
    var onProgress: ((PhotosImportProgress?) -> Void)?

    init(destination: (any PhotosImportDestination)? = nil) {
        self.destination = destination
    }

    /// Source compatibility for integrations created before the destination protocol became the
    /// public seam. New composition-root code injects `PhotosImportDestination` directly.
    @available(*, deprecated, message: "Inject PhotosImportDestination instead")
    convenience init(viewModel: AppViewModel) {
        self.init(destination: viewModel)
        onStatus = { [weak viewModel] message in viewModel?.statusMessage = message }
        onProgress = { [weak viewModel] progress in
            viewModel?.photosImportCoordinator.setProgressForCompatibility(progress)
        }
    }

    func start(
        selections: [PhotosImportSelection],
        provider: any PhotosImportProviding
    ) {
        task?.cancel()
        let currentOperationID = UUID()
        operationID = currentOperationID
        failures = []
        wasCancelled = false

        begin(totalCount: selections.count)

        task = Task { @MainActor [weak self] in
            guard let self else { return }
            var wasCancelled = false

            for selection in selections {
                guard self.isCurrent(currentOperationID) else { return }
                if Task.isCancelled {
                    wasCancelled = true
                    break
                }

                let name = provider.originalFilename(for: selection)
                    ?? "Photo \(selection.ordinal + 1)"
                self.updatePhase(.transferring, name: name)

                var transferInterval = KromoraSignpostInterval(
                    .photoTransfer,
                    context: KromoraTraceContext(
                        sourceFingerprint: selection.localIdentifier ?? "ordinal:\(selection.ordinal)",
                        quality: "photosImport"
                    )
                )

                do {
                    guard let data = try await provider.transferData(for: selection) else {
                        transferInterval.end()
                        self.recordFailure(
                            name: name, ordinal: selection.ordinal,
                            reason: "Photos returned no transferable data."
                        )
                        continue
                    }
                    transferInterval.end()

                    guard self.isCurrent(currentOperationID), !Task.isCancelled else {
                        wasCancelled = true
                        break
                    }

                    // Compute the full-buffer digest once at the provider boundary. The value is
                    // passed through the durable source, thumbnail, and first-render paths.
                    let contentDigest = await Task.detached(priority: .utility) {
                        PhotoAssetID.contentDigest(data)
                    }.value

                    guard self.isCurrent(currentOperationID), !Task.isCancelled else {
                        wasCancelled = true
                        break
                    }

                    self.append(
                        ImageCollection.PhotoImportItem(
                            name: name,
                            data: data,
                            localIdentifier: selection.localIdentifier,
                            contentDigest: contentDigest
                        ),
                        ordinal: selection.ordinal
                    )
                } catch is CancellationError {
                    transferInterval.end()
                    wasCancelled = true
                    break
                } catch {
                    transferInterval.end()
                    self.recordFailure(
                        name: name,
                        ordinal: selection.ordinal,
                        reason: error.localizedDescription
                    )
                }
            }

            guard self.isCurrent(currentOperationID) else { return }
            wasCancelled = wasCancelled || Task.isCancelled
            self.finish(cancelled: wasCancelled)
            self.wasCancelled = wasCancelled
            self.task = nil
        }
    }

    func begin(totalCount: Int) {
        destination?.preparePhotosImport(totalCount: totalCount)
        progress = PhotosImportProgress(
            total: max(0, totalCount), processed: 0, imported: 0, failed: 0,
            currentName: nil, phase: .transferring
        )
        onProgress?(progress)
        if let progress { onStatus?("Importing Photos 0/\(progress.total)…") }
    }

    func updatePhase(_ phase: PhotosImportProgress.Phase, name: String) {
        guard var progress else { return }
        progress.phase = phase
        progress.currentName = name
        self.progress = progress
        onProgress?(progress)
        onStatus?("\(phase.label) \(name)  \(progress.processed)/\(progress.total)…")
    }

    func append(_ item: ImageCollection.PhotoImportItem, ordinal: Int) {
        guard var progress else { return }
        updatePhase(.inserting, name: item.name)
        destination?.insertPhotosImport(item, ordinal: ordinal)
        progress = self.progress ?? progress
        progress.processed += 1
        progress.imported += 1
        progress.currentName = item.name
        progress.phase = .transferring
        self.progress = progress
        onProgress?(progress)
        onStatus?("Imported \(progress.processed)/\(progress.total)  \(item.name)…")
    }

    func recordFailure(name: String, ordinal: Int? = nil, reason: String) {
        guard var progress else { return }
        failures.append(PhotosImportFailure(ordinal: ordinal ?? progress.processed, name: name, reason: reason))
        destination?.recordPhotosImportFailureDestination(name: name, ordinal: ordinal)
        progress.processed += 1
        progress.failed += 1
        progress.currentName = name
        progress.phase = .transferring
        self.progress = progress
        onProgress?(progress)
        onStatus?("Skipped \(name)  \(progress.processed)/\(progress.total)…")
    }

    func finish(cancelled: Bool) {
        guard let progress else {
            destination?.finishPhotosImportDestination(cancelled: cancelled)
            return
        }
        destination?.finishPhotosImportDestination(cancelled: cancelled)
        let suffix = progress.failed == 0 ? "" : ", \(progress.failed) skipped"
        onStatus?(
            cancelled
                ? "Photos import cancelled — \(progress.imported) imported\(suffix)"
                : "Photos import complete — \(progress.imported) imported\(suffix)"
        )
        self.progress = nil
        onProgress?(nil)
    }

    func cancel() {
        task?.cancel()
    }

    func shutdown() async {
        let current = task
        current?.cancel()
        if let current { await current.value }
        task = nil
        destination = nil
        progress = nil
        onProgress?(nil)
    }

    private func isCurrent(_ id: UUID) -> Bool {
        operationID == id
    }

    fileprivate func setProgressForCompatibility(_ progress: PhotosImportProgress?) {
        self.progress = progress
    }

}

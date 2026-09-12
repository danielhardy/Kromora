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

/// Coordinates Photos provider interaction and the streamed durable import boundary. The view only
/// creates selections, supplies a provider, and forwards cancellation; all asynchronous item
/// iteration, hashing, progress, and failure handling lives here.
@MainActor
final class PhotosImportCoordinator: ObservableObject {
    @Published private(set) var progress: PhotosImportProgress?
    @Published private(set) var failures: [PhotosImportFailure] = []
    @Published private(set) var wasCancelled = false

    private weak var viewModel: AppViewModel?
    private var task: Task<Void, Never>?
    private var operationID = UUID()

    init(viewModel: AppViewModel) {
        self.viewModel = viewModel
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

        guard let viewModel else { return }
        viewModel.beginPhotosImport(totalCount: selections.count)
        syncProgress(from: viewModel)

        task = Task { @MainActor [weak self, weak viewModel] in
            guard let self, let viewModel else { return }
            var wasCancelled = false

            for selection in selections {
                guard self.isCurrent(currentOperationID) else { return }
                if Task.isCancelled {
                    wasCancelled = true
                    break
                }

                let name = provider.originalFilename(for: selection)
                    ?? "Photo \(selection.ordinal + 1)"
                viewModel.updatePhotosImportPhase(.transferring, name: name)
                self.syncProgress(from: viewModel)

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
                            reason: "Photos returned no transferable data.", viewModel: viewModel
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

                    viewModel.appendPhotosImport(
                        ImageCollection.PhotoImportItem(
                            name: name,
                            data: data,
                            localIdentifier: selection.localIdentifier,
                            contentDigest: contentDigest
                        ),
                        ordinal: selection.ordinal
                    )
                    self.syncProgress(from: viewModel)
                } catch is CancellationError {
                    transferInterval.end()
                    wasCancelled = true
                    break
                } catch {
                    transferInterval.end()
                    self.recordFailure(
                        name: name,
                        ordinal: selection.ordinal,
                        reason: error.localizedDescription,
                        viewModel: viewModel
                    )
                }
            }

            guard self.isCurrent(currentOperationID) else { return }
            wasCancelled = wasCancelled || Task.isCancelled
            viewModel.finishPhotosImport(cancelled: wasCancelled)
            self.wasCancelled = wasCancelled
            self.syncProgress(from: viewModel)
            self.task = nil
        }
    }

    func cancel() {
        task?.cancel()
    }

    private func isCurrent(_ id: UUID) -> Bool {
        operationID == id
    }

    private func syncProgress(from viewModel: AppViewModel) {
        progress = viewModel.photosImportProgress
    }

    private func recordFailure(
        name: String,
        ordinal: Int,
        reason: String,
        viewModel: AppViewModel
    ) {
        guard !Task.isCancelled else { return }
        failures.append(PhotosImportFailure(ordinal: ordinal, name: name, reason: reason))
        viewModel.recordPhotosImportFailure(name: name, ordinal: ordinal)
        syncProgress(from: viewModel)
    }
}

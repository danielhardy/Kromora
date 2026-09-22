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
    var duplicates: Int
    var skipped: Int
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
    /// Package mode hashes while staging on the package-I/O lane; the Photos payload must not be
    /// walked a second time on the main actor merely to prepare a legacy cache key.
    var packageImportDoesNotNeedDigest: Bool { get }
    func preparePhotosImport(totalCount: Int)
    func insertPhotosImport(
        _ item: ImageCollection.PhotoImportItem, ordinal: Int
    ) -> PhotosImportInsertionOutcome
    func recordPhotosImportFailureDestination(name: String, ordinal: Int?, reason: String)
    func finishPhotosImportDestination(summary: ImportOutcomeSummary)
}

extension PhotosImportDestination {
    var packageImportDoesNotNeedDigest: Bool { false }
}

/// Optional asynchronous destination hook used by package mode. The compatibility destination
/// remains synchronous for the legacy managed-folder path and for small deterministic tests.
@MainActor
protocol AsyncPhotosImportDestination: AnyObject {
    func insertPhotosImportAsync(
        _ item: ImageCollection.PhotoImportItem, ordinal: Int
    ) async -> PhotosImportInsertionOutcome
}

enum PhotosImportInsertionOutcome: Equatable, Sendable {
    case inserted(String)
    case duplicate(String)
    case failed(String)
}

/// Coordinates Photos provider interaction and the streamed durable import boundary. The view only
/// creates selections, supplies a provider, and forwards cancellation; all asynchronous item
/// iteration, hashing, progress, and failure handling lives here.
///
/// Migrated to Observation (KRMA-521): progress publishes through this object's own boundary.
/// Views observe the coordinator directly through `@Bindable` so import progress never passes
/// through AppViewModel's former objectWillChange fan-in.
@MainActor
@Observable
final class PhotosImportCoordinator {
    private(set) var progress: PhotosImportProgress?
    private(set) var failures: [PhotosImportFailure] = []
    private(set) var wasCancelled = false

    weak var destination: (any PhotosImportDestination)?
    private var task: Task<Void, Never>?
    private var operationID = UUID()
    var onStatus: ((String) -> Void)?
    var onProgress: ((PhotosImportProgress?) -> Void)?

    init(destination: (any PhotosImportDestination)? = nil) {
        self.destination = destination
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
                        guard self.isCurrent(currentOperationID), !Task.isCancelled else {
                            wasCancelled = true
                            break
                        }
                        self.recordFailure(
                            name: name, ordinal: selection.ordinal,
                            reason: "Photos returned no transferable data.", outcome: .skipped
                        )
                        continue
                    }
                    transferInterval.end()

                    guard self.isCurrent(currentOperationID), !Task.isCancelled else {
                        wasCancelled = true
                        break
                    }

                    // Legacy folder imports share this digest with source/thumbnail identity.
                    // Package imports compute their digest in the detached package staging pass.
                    let contentDigest: String?
                    if self.destination?.packageImportDoesNotNeedDigest == true {
                        contentDigest = nil
                    } else {
                        contentDigest = await Task.detached(priority: .utility) {
                            PhotoAssetID.contentDigest(data)
                        }.value
                    }

                    guard self.isCurrent(currentOperationID), !Task.isCancelled else {
                        wasCancelled = true
                        break
                    }

                    await self.appendAsync(
                        ImageCollection.PhotoImportItem(
                            name: name,
                            data: data,
                            localIdentifier: selection.localIdentifier,
                            contentDigest: contentDigest,
                            calculateContentDigest: contentDigest != nil
                        ),
                        ordinal: selection.ordinal
                    )
                } catch is CancellationError {
                    transferInterval.end()
                    wasCancelled = true
                    break
                } catch {
                    transferInterval.end()
                    guard self.isCurrent(currentOperationID), !Task.isCancelled else {
                        wasCancelled = true
                        break
                    }
                    self.recordFailure(
                        name: name,
                        ordinal: selection.ordinal,
                        reason: error.localizedDescription
                    )
                }
            }

            guard self.isCurrent(currentOperationID) else { return }
            wasCancelled = wasCancelled || Task.isCancelled
            self.finish(cancelled: wasCancelled, operationID: currentOperationID)
            guard self.isCurrent(currentOperationID) else { return }
            self.wasCancelled = wasCancelled
            self.task = nil
        }
    }

    func begin(totalCount: Int) {
        destination?.preparePhotosImport(totalCount: totalCount)
        progress = PhotosImportProgress(
            total: max(0, totalCount), processed: 0, imported: 0, duplicates: 0, skipped: 0,
            failed: 0,
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
        append(outcome: destination?.insertPhotosImport(item, ordinal: ordinal), item: item, ordinal: ordinal)
    }

    private func append(outcome: PhotosImportInsertionOutcome?, item: ImageCollection.PhotoImportItem, ordinal: Int) {
        guard var progress else { return }
        updatePhase(.inserting, name: item.name)
        let outcome = outcome ?? .failed("The import destination is no longer available.")
        progress = self.progress ?? progress
        progress.processed += 1
        switch outcome {
        case .inserted:
            progress.imported += 1
        case .duplicate:
            progress.duplicates += 1
        case .failed(let reason):
            progress.failed += 1
            failures.append(.init(ordinal: ordinal, name: item.name, reason: reason))
            destination?.recordPhotosImportFailureDestination(
                name: item.name, ordinal: ordinal, reason: reason
            )
        }
        progress.currentName = item.name
        progress.phase = .transferring
        self.progress = progress
        onProgress?(progress)
        let label: String
        switch outcome {
        case .inserted: label = "Imported"
        case .duplicate: label = "Duplicate"
        case .failed: label = "Failed"
        }
        onStatus?("\(label) \(progress.processed)/\(progress.total)  \(item.name)…")
    }

    private func appendAsync(
        _ item: ImageCollection.PhotoImportItem, ordinal: Int
    ) async {
        let outcome: PhotosImportInsertionOutcome?
        if let destination = destination as? any AsyncPhotosImportDestination {
            outcome = await destination.insertPhotosImportAsync(item, ordinal: ordinal)
        } else {
            outcome = destination?.insertPhotosImport(item, ordinal: ordinal)
        }
        append(outcome: outcome, item: item, ordinal: ordinal)
    }

    func recordFailure(
        name: String, ordinal: Int? = nil, reason: String,
        outcome: PhotosImportFailureOutcome = .failed
    ) {
        guard var progress else { return }
        failures.append(PhotosImportFailure(ordinal: ordinal ?? progress.processed, name: name, reason: reason))
        destination?.recordPhotosImportFailureDestination(
            name: name, ordinal: ordinal, reason: reason
        )
        progress.processed += 1
        switch outcome {
        case .skipped: progress.skipped += 1
        case .failed: progress.failed += 1
        }
        progress.currentName = name
        progress.phase = .transferring
        self.progress = progress
        onProgress?(progress)
        onStatus?(
            "\(outcome == .skipped ? "Skipped" : "Failed") \(name)  "
                + "\(progress.processed)/\(progress.total)…"
        )
    }

    func recordSkipped(name: String, ordinal: Int? = nil, reason: String) {
        recordFailure(name: name, ordinal: ordinal, reason: reason, outcome: .skipped)
    }

    func finish(cancelled: Bool, operationID: UUID? = nil) {
        if let operationID, !isCurrent(operationID) { return }
        guard let progress else {
            destination?.finishPhotosImportDestination(
                summary: ImportOutcomeSummary(total: 0, cancelled: cancelled)
            )
            return
        }
        let summary = ImportOutcomeSummary(
            total: progress.total,
            imported: progress.imported,
            duplicates: progress.duplicates,
            skipped: progress.skipped,
            failed: progress.failed,
            failureReasons: failures.map { "\($0.name): \($0.reason)" },
            cancelled: cancelled
        )
        destination?.finishPhotosImportDestination(summary: summary)
        if let operationID, !isCurrent(operationID) { return }
        onStatus?(summary.status(prefix: "Photos import"))
        self.progress = nil
        onProgress?(nil)
    }

    func cancel() {
        task?.cancel()
    }

    func shutdown() async {
        operationID = UUID()
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

}

enum PhotosImportFailureOutcome: Equatable {
    case skipped
    case failed
}

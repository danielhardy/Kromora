import AppKit
import Foundation

/// The narrow surface the application root exposes to package-source import orchestration. The
/// coordinator reports value outcomes here and never reaches back into `AppViewModel`.
@MainActor
protocol PackageSourceImportDestination: AnyObject {
    var isShuttingDown: Bool { get }
    var isPackageAvailable: Bool { get }
    func reportPackageUnavailable()
    /// Fold the batches committed so far into the visible Library window.
    func mergeCommittedImports()
    func reloadCollection() throws
    func openAsset(_ assetID: PortablePhotoAssetID)
    func presentOutcome(_ summary: ImportOutcomeSummary, prefix: String)
    func presentStatus(_ message: String)
    func presentError(_ message: String)
    /// Worker-backed dialog-style open used for URLs redeemed from a Photos drop. `completion`
    /// fires once for the current operation and not at all when it is superseded.
    func openImages(
        urls: [URL], operationID: UUID,
        completion: @escaping @MainActor (ImportOutcomeSummary?) -> Void)
    func finishMediaImport(_ summary: ImportOutcomeSummary, operationID: UUID)
    func cancelMediaImport()
}

/// Owns the shape shared by folder, removable-media and Photos-drop imports: start a package
/// import, observe it, reload the collection, open the first imported or duplicate asset, and
/// report an `ImportOutcomeSummary`. Operation-ID fencing stays in `LibraryImportCoordinator`.
@MainActor
final class PackageSourceImportCoordinator {
    typealias PromiseReceiver =
        @MainActor ([NSFilePromiseReceiver], URL) async -> ImageDrop.PromiseReceiveResult

    private let imports: LibraryImportCoordinator
    private let receivePromises: PromiseReceiver
    private weak var destination: (any PackageSourceImportDestination)?
    private var droppedPromiseTask: Task<Void, Never>?

    init(
        imports: LibraryImportCoordinator,
        destination: any PackageSourceImportDestination,
        receivePromises: @escaping PromiseReceiver = { await ImageDrop.receive($0, into: $1) }
    ) {
        self.imports = imports
        self.destination = destination
        self.receivePromises = receivePromises
    }

    // MARK: Shared observation

    /// Multi-photo imports fold each committed batch into the Library grid as it lands; a single
    /// photo has nothing to stream and is published by its completion handler.
    func observe(
        _ handle: PortablePackageImportHandle,
        operationID: UUID,
        total: Int,
        prefix: String,
        onSuccess: @escaping @MainActor (PortablePackageImportResult) -> Void,
        onFailure: @escaping @MainActor (Error) -> Void
    ) {
        let streamsToGrid = total > 1
        imports.observe(
            handle, operationID: operationID, prefix: prefix,
            onCommitted: { [weak self] in
                guard streamsToGrid else { return }
                self?.destination?.mergeCommittedImports()
            },
            onSuccess: onSuccess, onFailure: onFailure
        )
    }

    private func openFirstAsset(of result: PortablePackageImportResult) {
        if let assetID = result.imported.first?.assetID
            ?? result.duplicates.first?.existingAssetID
        {
            destination?.openAsset(assetID)
        }
    }

    // MARK: Folder

    /// Import supported images from `url` and open the first imported image. Takes ownership of
    /// `access`; it is released on every path that does not hand it to the package import.
    @discardableResult
    func openSourceFolder(
        url: URL,
        access: SecurityScopedResourceAccess? = nil
    ) -> ImportOutcomeSummary? {
        var transferredAccess = false
        defer {
            if !transferredAccess { access?.release() }
        }
        let operationID = imports.beginOperation()
        guard let destination else { return nil }
        guard destination.isPackageAvailable else {
            destination.reportPackageUnavailable()
            return nil
        }
        let files = Self.supportedImageURLs(in: url)
        guard !files.isEmpty else {
            destination.presentStatus("No supported images were found in \(url.lastPathComponent).")
            return nil
        }
        do {
            let handle = try imports.startImportURLs(files, access: access.map { [$0] } ?? [])
            transferredAccess = access != nil
            observe(
                handle, operationID: operationID, total: files.count, prefix: "Folder import",
                onSuccess: { [weak self] result in
                    guard let self, let destination = self.destination else { return }
                    do {
                        try destination.reloadCollection()
                        self.openFirstAsset(of: result)
                        destination.presentOutcome(
                            ImportOutcomeSummary(result: result, total: files.count),
                            prefix: "Folder import"
                        )
                    } catch { destination.presentError(error.localizedDescription) }
                },
                onFailure: { [weak self] error in
                    guard let self, self.imports.isCurrent(operationID) else { return }
                    self.destination?.presentOutcome(
                        .failure(total: files.count, reason: error.localizedDescription),
                        prefix: "Folder import"
                    )
                }
            )
            return nil
        } catch {
            guard imports.isCurrent(operationID) else { return nil }
            let summary = ImportOutcomeSummary.failure(
                total: files.count, reason: error.localizedDescription
            )
            destination.presentOutcome(summary, prefix: "Folder import")
            return summary
        }
    }

    static func supportedImageURLs(in folder: URL) -> [URL] {
        guard
            let enumerator = FileManager.default.enumerator(
                at: folder, includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
        else { return [] }
        return enumerator.compactMap { value in
            guard let url = value as? URL,
                  (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
                  ImageDecoder.supportedExtensions.contains(url.pathExtension.lowercased()),
                FileManager.default.isReadableFile(atPath: url.path)
            else { return nil }
            return url
        }.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    // MARK: Removable media

    func importRemovableMedia(_ request: RemovableMediaImportRequest) {
        guard let destination, !destination.isShuttingDown else { return }
        let files = request.files
        let operationID = request.operationID
        imports.adoptOperation(operationID)
        guard destination.isPackageAvailable else {
            destination.reportPackageUnavailable()
            destination.cancelMediaImport()
            return
        }
        func finish(failing error: Error) {
            self.destination?.finishMediaImport(
                .failure(total: request.totalSelected, reason: error.localizedDescription),
                operationID: operationID
            )
        }
        do {
            let handle = try imports.startImportURLs(
                files.map(\.url), access: request.access.map { [$0] } ?? []
            )
            observe(
                handle, operationID: operationID, total: files.count,
                prefix: request.source.statusPrefix,
                onSuccess: { [weak self] result in
                    guard let self, let destination = self.destination else { return }
                    do {
                        try destination.reloadCollection()
                        self.openFirstAsset(of: result)
                        destination.finishMediaImport(
                            ImportOutcomeSummary(
                                result: result,
                                total: request.totalSelected,
                                preflightSkipped: request.totalSelected - files.count
                            ),
                            operationID: operationID
                        )
                    } catch { finish(failing: error) }
                },
                onFailure: { [weak self] error in
                    guard let self, self.imports.isCurrent(operationID) else { return }
                    finish(failing: error)
                }
            )
        } catch {
            guard imports.isCurrent(operationID) else { return }
            finish(failing: error)
        }
    }

    // MARK: Photos drop

    func importDroppedPromises(_ receivers: [NSFilePromiseReceiver]) {
        let operationID = imports.beginOperation()
        droppedPromiseTask?.cancel()
        droppedPromiseTask = Task { @MainActor [weak self] in
            guard let self, self.imports.isCurrent(operationID) else { return }
            ImageDrop.purgeDropDirectories()
            let directory: URL
            do {
                directory = try ImageDrop.makeDropDirectory()
            } catch {
                guard self.imports.isCurrent(operationID) else { return }
                self.destination?.presentStatus(
                    "Photos drop failed: \(error.localizedDescription)")
                self.droppedPromiseTask = nil
                return
            }

            let received = await self.receivePromises(receivers, directory)
            // Photos redeems an edited RAW as a rendered JPEG under the original RAW name
            // (KRMA-1031); refuse it rather than store it as the original.
            var urls: [URL] = []
            var failures = received.failures
            for url in received.urls {
                if let reason = OriginalFileTypeCheck.mismatchReason(forFileAt: url) {
                    failures.append(reason)
                } else {
                    urls.append(url)
                }
            }
            let result = ImageDrop.PromiseReceiveResult(urls: urls, failures: failures)
            guard self.imports.isCurrent(operationID), let destination = self.destination else {
                ImageDrop.purgeDropDirectories()
                return
            }
            // The worker reads the redeemed files after this task body returns, so the drop
            // directory is purged on completion; a superseded import leaves it for the next drop
            // or shutdown to purge.
            let finish: @MainActor (ImportOutcomeSummary?) -> Void = { [weak self] summary in
                ImageDrop.purgeDropDirectories()
                guard let self, let destination = self.destination else { return }
                if !result.failures.isEmpty {
                    let promiseSummary = ImportOutcomeSummary(
                        total: result.failures.count,
                        failed: result.failures.count,
                        failureReasons: result.failures
                    )
                    let combined = (summary ?? ImportOutcomeSummary(total: 0))
                        .adding(promiseSummary)
                    destination.presentOutcome(combined, prefix: "Photos drop")
                } else if let summary {
                    destination.presentOutcome(summary, prefix: "Photos drop")
                } else {
                    destination.presentStatus(
                        "Photos drop complete — 0 imported, 0 duplicate, 0 skipped, 0 failed")
                }
                self.droppedPromiseTask = nil
            }
            if result.urls.isEmpty {
                finish(nil)
            } else {
                // Promise URLs are already known to be files. Use the same durable multi-file
                // path as other library imports; the drop outcome is reported on completion.
                destination.openImages(
                    urls: result.urls, operationID: operationID, completion: finish)
            }
        }
    }

    func shutdown() {
        droppedPromiseTask?.cancel()
        droppedPromiseTask = nil
        ImageDrop.purgeDropDirectories()
    }
}

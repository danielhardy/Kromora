import Foundation

private enum LibraryImportCoordinatorError: Error {
    case packageUnavailable
}

/// Owns the replaceable package-import operation shared by open, folder, Photos, and removable
/// media entry points. Presentation and collection mutations stay with the application root.
@MainActor
final class LibraryImportCoordinator {
    private let package: PortableLibrarySession?
    private let isShuttingDown: @MainActor () -> Bool
    private let publishProgress: @MainActor (PortablePackageImportProgress?) -> Void
    private let publishStatus: @MainActor (String) -> Void

    private var operationID = UUID()
    private var handle: PortablePackageImportHandle?
    private var observation: Task<Void, Never>?
    /// Minimum spacing between live window merges. Merging re-queries the loaded pages, so a
    /// fast import is folded into the grid a few times per second instead of once per photo.
    static let liveMergeInterval: Duration = .milliseconds(250)

    init(
        package: PortableLibrarySession?,
        isShuttingDown: @escaping @MainActor () -> Bool,
        publishProgress: @escaping @MainActor (PortablePackageImportProgress?) -> Void,
        publishStatus: @escaping @MainActor (String) -> Void
    ) {
        self.package = package
        self.isShuttingDown = isShuttingDown
        self.publishProgress = publishProgress
        self.publishStatus = publishStatus
    }

    /// Package import entry points stay behind this owner so source-specific workflows share one
    /// package boundary and one cancellation/progress lifecycle.
    func importURLs(
        _ urls: [URL],
        duplicatePolicy: PortablePackageDuplicatePolicy = .skip,
        access: [SecurityScopedResourceAccess] = []
    ) throws -> PortablePackageImportResult {
        try requirePackage().importURLs(
            urls, duplicatePolicy: duplicatePolicy, access: access
        )
    }

    func startImportURLs(
        _ urls: [URL],
        duplicatePolicy: PortablePackageDuplicatePolicy = .skip,
        access: [SecurityScopedResourceAccess] = []
    ) throws -> PortablePackageImportHandle {
        try requirePackage().startImportURLs(
            urls, duplicatePolicy: duplicatePolicy, access: access
        )
    }

    func startImportData(
        _ data: Data,
        name: String,
        duplicatePolicy: PortablePackageDuplicatePolicy = .skip,
        rebuildIndex: Bool = true
    ) throws -> PortablePackageImportHandle {
        try requirePackage().startImportData(
            data, name: name, duplicatePolicy: duplicatePolicy, rebuildIndex: rebuildIndex
        )
    }

    func importData(
        _ data: Data,
        name: String,
        duplicatePolicy: PortablePackageDuplicatePolicy = .skip,
        rebuildIndex: Bool = true
    ) throws -> PortablePackageImportResult {
        try requirePackage().importData(
            data, name: name, duplicatePolicy: duplicatePolicy, rebuildIndex: rebuildIndex
        )
    }

    func finishImportBatch() {
        package?.finishImportBatch()
    }

    private func requirePackage() throws -> PortableLibrarySession {
        guard let package else { throw LibraryImportCoordinatorError.packageUnavailable }
        return package
    }

    /// Starting any new import invalidates late callbacks and cancels the previous package write.
    func beginOperation() -> UUID {
        handle?.cancel()
        observation?.cancel()
        handle = nil
        observation = nil
        publishProgress(nil)
        let id = UUID()
        operationID = id
        return id
    }

    /// Adopts the generation created by a provider coordinator for its current request.
    func adoptOperation(_ id: UUID) {
        handle?.cancel()
        observation?.cancel()
        handle = nil
        observation = nil
        publishProgress(nil)
        operationID = id
    }

    func isCurrent(_ id: UUID) -> Bool {
        operationID == id && !isShuttingDown()
    }

    /// Stops the running import. Sources already committed stay in the package and the grid; the
    /// observation then completes through its normal success or failure path.
    func cancelCurrent() {
        handle?.cancel()
    }

    func observe(
        _ newHandle: PortablePackageImportHandle,
        operationID id: UUID,
        prefix: String,
        onCommitted: @escaping @MainActor () -> Void = {},
        onSuccess: @escaping @MainActor (PortablePackageImportResult) -> Void,
        onFailure: @escaping @MainActor (Error) -> Void
    ) {
        handle = newHandle
        observation = Task { @MainActor [weak self] in
            guard let self else { return }
            var lastMerge: ContinuousClock.Instant?
            var importedSoFar = 0
            for await progress in newHandle.progress {
                guard self.isCurrent(id) else { return }
                self.publishProgress(progress)
                self.publishStatus("\(prefix) \(progress.processed)/\(progress.total)…")
                importedSoFar = progress.imported
                let now = ContinuousClock.now
                if lastMerge.map({ $0.duration(to: now) >= Self.liveMergeInterval }) ?? true,
                   newHandle.publishCommitted() > 0 {
                    lastMerge = now
                    onCommitted()
                }
            }
            do {
                let result = try await newHandle.value()
                guard self.isCurrent(id) else { return }
                // The success handler reloads the window, which supersedes any live merge.
                newHandle.publishCommitted()
                self.handle = nil
                self.observation = nil
                self.publishProgress(nil)
                onSuccess(result)
            } catch {
                guard self.isCurrent(id) else { return }
                // A cancelled or failed import may still have committed sources first; the session
                // already published them to the index, so only the grid needs to catch up.
                newHandle.publishCommitted()
                if importedSoFar > 0 { onCommitted() }
                self.handle = nil
                self.observation = nil
                self.publishProgress(nil)
                onFailure(error)
            }
        }
    }

    func shutdown() async {
        operationID = UUID()
        handle?.cancel()
        handle = nil
        let currentObservation = observation
        currentObservation?.cancel()
        observation = nil
        publishProgress(nil)
        if let currentObservation { await currentObservation.value }
    }
}

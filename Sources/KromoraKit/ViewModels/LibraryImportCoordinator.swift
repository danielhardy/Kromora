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
        duplicatePolicy: PortablePackageDuplicatePolicy = .skip
    ) throws -> PortablePackageImportResult {
        try requirePackage().importURLs(urls, duplicatePolicy: duplicatePolicy)
    }

    func startImportURLs(
        _ urls: [URL],
        duplicatePolicy: PortablePackageDuplicatePolicy = .skip
    ) throws -> PortablePackageImportHandle {
        try requirePackage().startImportURLs(urls, duplicatePolicy: duplicatePolicy)
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

    func observe(
        _ newHandle: PortablePackageImportHandle,
        operationID id: UUID,
        prefix: String,
        onSuccess: @escaping @MainActor (PortablePackageImportResult) -> Void,
        onFailure: @escaping @MainActor (Error) -> Void
    ) {
        handle = newHandle
        observation = Task { @MainActor [weak self] in
            guard let self else { return }
            for await progress in newHandle.progress {
                guard self.isCurrent(id) else { return }
                self.publishProgress(progress)
                self.publishStatus("\(prefix) \(progress.processed)/\(progress.total)…")
            }
            do {
                let result = try await newHandle.value()
                guard self.isCurrent(id) else { return }
                self.handle = nil
                self.observation = nil
                self.publishProgress(nil)
                onSuccess(result)
            } catch {
                guard self.isCurrent(id) else { return }
                self.handle = nil
                self.observation = nil
                self.publishProgress(nil)
                onFailure(error)
            }
        }
    }

    func cancelCurrent() {
        handle?.cancel()
        handle = nil
        publishProgress(nil)
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

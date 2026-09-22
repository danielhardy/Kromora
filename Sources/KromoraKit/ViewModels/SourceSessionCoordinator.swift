import AppKit
import Foundation

/// Owns the asynchronous lifetime of one selected source.
///
/// The application model remains the owner of the published active document and of presentation
/// state. This collaborator owns everything that can outlive an open action: one in-flight source
/// preparation, the newest pending selection, stored-edit reconciliation, decoder probes,
/// metadata extraction, and the optional embedded RAW first frame. Every callback is tagged with
/// the source request that admitted it; a late framework completion is therefore harmless.
@MainActor
final class SourceSessionCoordinator {
    struct Request: Sendable, Equatable {
        let plan: SourceImportPlan
        let sourceRevision: UInt64
        let editSessionRevision: UInt64
        let hadInMemorySession: Bool

        var assetID: PhotoAssetID { plan.assetID }
        var sourceReference: EditSourceReference { plan.sourceReference }
    }

    struct PreparationPublication {
        let request: Request
        let preparation: ImageSourcePreparation
    }

    struct StoredDocumentPublication {
        let request: Request
        let result: EditDocumentLoadResult
    }

    struct MetadataPublication {
        let request: Request
        let metadata: ImageMetadata
    }

    struct CapabilitiesPublication {
        let request: Request
        let capabilities: RAWCapabilities?
    }

    struct FirstFramePublication {
        let request: Request
        let preparation: ImageSourcePreparation
        let image: NSImage
    }

    typealias PreparationHandler = @MainActor (PreparationPublication) -> Void
    typealias StoredDocumentHandler = @MainActor (StoredDocumentPublication) -> Void
    typealias MetadataHandler = @MainActor (MetadataPublication) -> Void
    typealias CapabilitiesHandler = @MainActor (CapabilitiesPublication) -> Void
    typealias FirstFrameHandler = @MainActor (FirstFramePublication) -> Void
    typealias FailureHandler = @MainActor (Request, String) -> Void

    private let engine: any RenderEngining
    private let editStore: EditDocumentStore
    private let embeddedFirstFrameProvider: @Sendable (URL) async -> NSImage?
    private var pendingRequest: Request?
    private var workerTask: Task<Void, Never>?
    private var storedLoadTask: Task<EditDocumentLoadResult, Never>?
    private var metadataTask: Task<Void, Never>?
    private var capabilitiesTask: Task<Void, Never>?
    private var firstFrameTask: Task<Void, Never>?
    private var storedDocumentBarrier: Task<PersistenceFlushResult, Never>?
    private(set) var sourceRevision: UInt64 = 0
    /// The request whose preparation was last published to the application model. A newer
    /// request may be pending while this source is still on screen; probes belong to this request
    /// until the replacement actually prepares successfully.
    private var publishedRequest: Request?
    private(set) var activeRequest: Request?
    private var isShutdown = false

    var isBusy: Bool { pendingRequest != nil || workerTask != nil }

    var onPreparation: PreparationHandler?
    var onStoredDocument: StoredDocumentHandler?
    var onMetadata: MetadataHandler?
    var onCapabilities: CapabilitiesHandler?
    var onFirstFrame: FirstFrameHandler?
    var onFailure: FailureHandler?

    init(
        engine: any RenderEngining,
        editStore: EditDocumentStore,
        embeddedFirstFrameProvider: @escaping @Sendable (URL) async -> NSImage?
    ) {
        self.engine = engine
        self.editStore = editStore
        self.embeddedFirstFrameProvider = embeddedFirstFrameProvider
    }

    /// Begins a source session. Preparation is intentionally not cancelled: Core Image/RAW calls
    /// may be non-cancellable, and retaining only the newest pending request prevents a navigation
    /// burst from creating a queue of obsolete decoder operations.
    @discardableResult
    func begin(
        plan: SourceImportPlan,
        editSessionRevision: UInt64,
        hadInMemorySession: Bool,
        persistenceBarrier: Task<PersistenceFlushResult, Never>? = nil
    ) -> UInt64 {
        guard !isShutdown else { return sourceRevision }
        sourceRevision &+= 1
        let request = Request(
            plan: plan, sourceRevision: sourceRevision,
            editSessionRevision: editSessionRevision,
            hadInMemorySession: hadInMemorySession
        )
        activeRequest = request
        pendingRequest = request
        storedDocumentBarrier = persistenceBarrier
        firstFrameTask?.cancel()
        firstFrameTask = nil
        storedLoadTask?.cancel()
        if workerTask == nil { startWorker() }
        return sourceRevision
    }

    /// Invalidates the current source even when the next source has equal-valued bytes.
    func cancel() {
        sourceRevision &+= 1
        activeRequest = nil
        publishedRequest = nil
        pendingRequest = nil
        storedDocumentBarrier = nil
        firstFrameTask?.cancel()
        firstFrameTask = nil
        metadataTask?.cancel()
        metadataTask = nil
        capabilitiesTask?.cancel()
        capabilitiesTask = nil
        storedLoadTask?.cancel()
        storedLoadTask = nil
    }

    func shutdown() async {
        guard !isShutdown else { return }
        isShutdown = true
        sourceRevision &+= 1
        activeRequest = nil
        publishedRequest = nil
        pendingRequest = nil
        storedDocumentBarrier = nil
        firstFrameTask?.cancel()
        storedLoadTask?.cancel()
        metadataTask?.cancel()
        capabilitiesTask?.cancel()
        let worker = workerTask
        let stored = storedLoadTask
        let metadata = metadataTask
        let capabilities = capabilitiesTask
        let firstFrame = firstFrameTask
        workerTask = nil
        storedLoadTask = nil
        metadataTask = nil
        capabilitiesTask = nil
        firstFrameTask = nil
        await worker?.value
        _ = await stored?.value
        _ = await metadata?.value
        _ = await capabilities?.value
        _ = await firstFrame?.value
    }

    private func startWorker() {
        workerTask = Task { [weak self] in
            while let self, !self.isShutdown, let request = self.pendingRequest {
                self.pendingRequest = nil
                await self.prepare(request)
            }
            self?.workerTask = nil
        }
    }

    private func isCurrent(_ request: Request) -> Bool {
        !isShutdown && publishedRequest == request
    }

    private func isExpected(_ request: Request) -> Bool {
        !isShutdown && activeRequest == request && sourceRevision == request.sourceRevision
    }

    private func prepare(_ request: Request) async {
        let persistenceBarrier = storedDocumentBarrier
        let storedTask = Task {
            if let persistenceBarrier {
                _ = await persistenceBarrier.value
            }
            return await editStore.load(for: request.sourceReference)
        }
        storedLoadTask = storedTask
        let preparation = await engine.prepareSource(request.plan.source)
        guard isExpected(request) else {
            storedTask.cancel()
            _ = await storedTask.value
            if storedLoadTask == storedTask { storedLoadTask = nil }
            return
        }
        guard let preparation else {
            onFailure?(request, "Error: Cannot load \(request.plan.name)")
            storedTask.cancel()
            _ = await storedTask.value
            if storedLoadTask == storedTask { storedLoadTask = nil }
            return
        }

        // This is the refresh site: only now is there definitely a replacement source. A failed
        // prepare leaves `publishedRequest` and its metadata/capability work untouched, so the
        // source that remains on screen can finish describing itself.
        metadataTask?.cancel()
        metadataTask = nil
        capabilitiesTask?.cancel()
        capabilitiesTask = nil
        publishedRequest = request
        onPreparation?(PreparationPublication(request: request, preparation: preparation))
        startMetadata(for: request)
        startCapabilities(for: request, source: preparation.source)
        startFirstFrameIfNeeded(for: request, preparation: preparation)

        let stored = await storedTask.value
        if storedLoadTask == storedTask { storedLoadTask = nil }
        // Stored edits belong to the request that admitted them. Unlike probes, they must not
        // publish while a newer request is pending, even if that request later fails.
        guard isCurrent(request), activeRequest == request else { return }
        onStoredDocument?(StoredDocumentPublication(request: request, result: stored))
    }

    private func startMetadata(for request: Request) {
        metadataTask?.cancel()
        let url = request.plan.url
        let data = request.plan.data
        // Keep the read itself in the stored task. The detached work must not outlive an
        // unstored handle and race a later source's Info panel.
        metadataTask = Task.detached(priority: .utility) { [weak self] in
            let metadata: ImageMetadata
            if let url {
                metadata = ImageMetadata.read(from: url)
            } else if let data {
                metadata = ImageMetadata.read(from: data)
            } else {
                metadata = ImageMetadata()
            }
            guard !Task.isCancelled else { return }
            await self?.publishMetadata(metadata, for: request)
        }
    }

    private func publishMetadata(_ metadata: ImageMetadata, for request: Request) {
        guard isCurrent(request), !Task.isCancelled else { return }
        onMetadata?(MetadataPublication(request: request, metadata: metadata))
    }

    private func startCapabilities(for request: Request, source: ImageSource) {
        capabilitiesTask?.cancel()
        capabilitiesTask = Task { [weak self, engine] in
            let capabilities = await engine.rawCapabilities(for: source)
            guard let self, self.isCurrent(request), !Task.isCancelled else { return }
            self.onCapabilities?(CapabilitiesPublication(request: request, capabilities: capabilities))
        }
    }

    private func startFirstFrameIfNeeded(
        for request: Request, preparation: ImageSourcePreparation
    ) {
        guard preparation.isRAW, case .url(let url) = preparation.source.backing else { return }
        let provider = embeddedFirstFrameProvider
        let extractionTask = Task.detached(priority: .userInitiated) { await provider(url) }
        firstFrameTask = Task { [weak self, extractionTask] in
            guard let image = await extractionTask.value, let self,
                self.isCurrent(request), !Task.isCancelled else { return }
            self.onFirstFrame?(FirstFramePublication(
                request: request, preparation: preparation, image: image
            ))
        }
    }
}

import AppKit
import CoreGraphics
import Foundation

/// The rendering operations needed by edited-thumbnail work. Keeping this seam small lets the
/// coordinator tests exercise scheduling and late-result fences without constructing a renderer.
protocol EditedThumbnailRendering: Sendable {
    func prepareSource(_ source: ImageSource) async -> ImageSourcePreparation?
    func makeThumbnailCGImage(_ request: RenderRequest) async -> sending CGImage?
}

/// The application values edited-thumbnail scheduling reads and publishes. The collection and
/// active document remain owned by `AppViewModel`; this seam only exposes their current values.
@MainActor
protocol EditedThumbnailDestination: AnyObject {
    var activeEditedThumbnailAssetID: PhotoAssetID? { get }
    var editedThumbnailSourceRevision: UInt64 { get }
    var editedThumbnailDocumentRevision: UInt64 { get }
    var isEditedThumbnailShuttingDown: Bool { get }
    var isEditedThumbnailInteractionActive: Bool { get }
    var isEditedThumbnailPreviewDebouncing: Bool { get }
    var editedThumbnailItems: [ImageCollection.Item] { get }
    var visibleEditedThumbnailAssetIDs: Set<PhotoAssetID> { get }
    func editedThumbnailItem(for assetID: PhotoAssetID) -> ImageCollection.Item?
    func editedThumbnailDocument(for assetID: PhotoAssetID) -> EditDocument?
    func editedThumbnailDocumentRevision(for assetID: PhotoAssetID) -> UInt64
    func resolvedEditedThumbnailLUT(_ id: LUTID?) -> CubeLUT?
    func markEditedThumbnailStale(for assetID: PhotoAssetID)
    func applyEditedThumbnail(_ image: NSImage?, for assetID: PhotoAssetID, revision: String)
    /// Show a persisted frame that has not been confirmed against the current edit. It carries no
    /// revision, so demand still classifies and, if stale, refines it once.
    func applyStoredEditedThumbnail(_ image: NSImage, for assetID: PhotoAssetID)
    func setEditedThumbnailPresentedCrop(
        _ crop: CropAdjustments, rotation: ImageRotation, for assetID: PhotoAssetID
    )
}

/// Owns demand admission, debounce tasks, generations, and job IDs for edit-aware collection
/// thumbnails. Documents and collection presentation remain with the application model.
@MainActor
final class EditedThumbnailCoordinator {
    private struct MaterializedThumbnail: Equatable {
        let sourceIdentity: PortablePhotoIdentity
        let revision: String
        /// The Look the published pixels were rendered with; scopes a scan delta to this asset.
        let look: LookSignature
    }

    private var editedThumbnailGenerations: [PhotoAssetID: UInt64] = [:]
    private var materializedThumbnails: [PhotoAssetID: MaterializedThumbnail] = [:]
    private var editedThumbnailDebounceTasks: [PhotoAssetID: Task<Void, Never>] = [:]
    private var deferredEditedThumbnailPriorities: [PhotoAssetID: ImageWorkScheduler.Priority] = [:]
    private var pendingEditedThumbnailAssetID: PhotoAssetID?
    private let editedThumbnailJobPrefix = "edited-thumbnail-"

    private let workScheduler: ImageWorkScheduler
    private let engine: any EditedThumbnailRendering
    private let editStore: EditDocumentStore
    /// Persisted thumbnail frames. With none, every demand renders, exactly as an unpersisted
    /// collection always did.
    var frameStore: ThumbnailFrameStore?
    weak var destination: (any EditedThumbnailDestination)?

    init(
        workScheduler: ImageWorkScheduler,
        engine: any EditedThumbnailRendering,
        editStore: EditDocumentStore,
        frameStore: ThumbnailFrameStore? = nil,
        destination: (any EditedThumbnailDestination)? = nil
    ) {
        self.workScheduler = workScheduler
        self.engine = engine
        self.editStore = editStore
        self.frameStore = frameStore
        self.destination = destination
    }

    var pendingAssetID: PhotoAssetID? { pendingEditedThumbnailAssetID }

    func clearPendingRequest() { pendingEditedThumbnailAssetID = nil }

    /// Invalidate an edited-thumbnail operation while keeping its current bitmap visible. The
    /// revision marker is cleared so demand can replace stale pixels. Cancellation is cooperative
    /// — a renderer may still be returning from a framework call — so the generation bump is the
    /// durable fence for that late result.
    func invalidateWork(for assetID: PhotoAssetID?) {
        guard let assetID else { return }
        editedThumbnailGenerations[assetID] = (editedThumbnailGenerations[assetID] ?? 0) &+ 1
        destination?.markEditedThumbnailStale(for: assetID)
        editedThumbnailDebounceTasks[assetID]?.cancel()
        editedThumbnailDebounceTasks[assetID] = nil
        workScheduler.cancel(
            id: ImageWorkScheduler.JobID(editedThumbnailJobPrefix + assetID.raw), pump: false
        )
    }

    func cancelActiveRequest(for assetID: PhotoAssetID?) {
        guard let assetID else { return }
        cancelDebounce(for: assetID)
        workScheduler.cancel(
            id: ImageWorkScheduler.JobID(editedThumbnailJobPrefix + assetID.raw), pump: false
        )
    }

    func removeAssets(_ assetIDs: Set<PhotoAssetID>) {
        for id in assetIDs {
            editedThumbnailDebounceTasks[id]?.cancel()
            editedThumbnailDebounceTasks.removeValue(forKey: id)
            editedThumbnailGenerations.removeValue(forKey: id)
            materializedThumbnails.removeValue(forKey: id)
            deferredEditedThumbnailPriorities.removeValue(forKey: id)
            workScheduler.cancel(
                id: ImageWorkScheduler.JobID(editedThumbnailJobPrefix + id.raw), pump: false
            )
        }
        if let pendingEditedThumbnailAssetID, assetIDs.contains(pendingEditedThumbnailAssetID) {
            self.pendingEditedThumbnailAssetID = nil
        }
    }

    /// Request one bounded edited-thumbnail render for a photo. The original thumbnail is already
    /// visible while this work runs, so a slow RAW or LUT render never blocks the editor or blanks a
    /// browsing cell. The job identity is per photo; the document hash and resolved Look fingerprint
    /// are the effective pixel revision applied at publication time.
    func request(
        for assetID: PhotoAssetID,
        priority: ImageWorkScheduler.Priority,
        force: Bool = false
    ) {
        guard let destination, !destination.isEditedThumbnailShuttingDown,
            let item = destination.editedThumbnailItem(for: assetID)
        else { return }

        // A demand callback can arrive while the preview debounce is already pending (or after a
        // cell reappears during a gesture). Keep the active photo's request as value state and let
        // the settle path admit it; no thumbnail should enter the shared render actor in either
        // interval.
        if destination.isEditedThumbnailInteractionActive
            || destination.isEditedThumbnailPreviewDebouncing
        {
            if assetID == destination.activeEditedThumbnailAssetID {
                pendingEditedThumbnailAssetID = assetID
                editedThumbnailDebounceTasks[assetID]?.cancel()
                editedThumbnailDebounceTasks[assetID] = nil
                workScheduler.cancel(
                    id: ImageWorkScheduler.JobID(editedThumbnailJobPrefix + assetID.raw),
                    pump: false
                )
            } else {
                // The editor owns the renderer during an interaction. Keep visible-library
                // demand as value state even when an older edited bitmap is already published:
                // that bitmap may no longer match the saved document, and the viewport callback
                // does not have to fire again after settling.
                let previous = deferredEditedThumbnailPriorities[assetID]
                if let previous {
                    deferredEditedThumbnailPriorities[assetID] =
                        previous.rawValue <= priority.rawValue ? previous : priority
                } else {
                    deferredEditedThumbnailPriorities[assetID] = priority
                }
            }
            return
        }

        let jobID = ImageWorkScheduler.JobID(editedThumbnailJobPrefix + assetID.raw)
        if workScheduler.contains(jobID) {
            if force {
                workScheduler.cancel(id: jobID, pump: false)
            } else {
                workScheduler.updatePriority(for: jobID, to: priority)
                return
            }
        }

        let generation = (editedThumbnailGenerations[assetID] ?? 0) &+ 1
        editedThumbnailGenerations[assetID] = generation

        let source: ImageSource?
        if let url = item.url {
            source = ImageSource(
                url: url, nativeExtent: item.thumbnailNativeExtent,
                portableIdentity: item.asset.source.portableIdentity
            )
        } else if let data = item.imageData {
            source = ImageSource(
                data: data, nativeExtent: item.thumbnailNativeExtent,
                dataFingerprint: item.dataFingerprint,
                portableIdentity: item.asset.source.portableIdentity
            )
        } else {
            source = nil
        }
        guard let source else { return }

        let inMemoryDocument = destination.editedThumbnailDocument(for: assetID)
        if let inMemoryDocument, inMemoryDocument.isIdentity {
            let revision = editedThumbnailRevision(document: inMemoryDocument, look: .none)
            presentIdentity(
                revision: revision, assetID: assetID, portableAssetID: source.cacheIdentity.assetID
            )
            return
        }
        let sourceReference = EditSourceReference(
            assetID: assetID, portableIdentity: item.asset.source.portableIdentity,
            url: item.url
        )
        // Active thumbnails need a navigation fence as well as the per-asset generation: A → B → A
        // can otherwise let a cancelled A request publish into the second A session. Non-active
        // thumbnails remain useful across navigation, so their session revision is the document
        // fence and they are not tied to the active source generation.
        let thumbnailSourceRevision: UInt64? =
            assetID == destination.activeEditedThumbnailAssetID
            ? destination.editedThumbnailSourceRevision : nil
        let thumbnailDocumentRevision =
            assetID == destination.activeEditedThumbnailAssetID
            ? destination.editedThumbnailDocumentRevision
            : destination.editedThumbnailDocumentRevision(for: assetID)
        let thumbnailSourceIdentity = source.cacheIdentity
        let engine = self.engine
        let editStore = self.editStore
        workScheduler.enqueue(id: jobID, lane: .thumbnail, priority: priority) {
            [weak self, engine, editStore, source, sourceReference, assetID, generation,
             thumbnailSourceRevision, thumbnailDocumentRevision, thumbnailSourceIdentity,
             inMemoryDocument] in
            guard let self, self.isCurrentEditedThumbnailRequest(
                assetID: assetID, generation: generation,
                sourceRevision: thumbnailSourceRevision,
                documentRevision: thumbnailDocumentRevision,
                sourceIdentity: thumbnailSourceIdentity
            ) else { return }

            let document: EditDocument
            // The Look a saved revision was written with, from its content-addressed package
            // reference. It is known without the Look browser, so a persisted frame can be judged
            // exact before a scan has resolved anything.
            var savedLook: LookSignature?
            if let inMemoryDocument {
                document = inMemoryDocument
            } else {
                let loaded = await editStore.load(for: sourceReference)
                document = loaded.document
                savedLook = loaded.found ? loaded.lookSignature : nil
            }
            guard !Task.isCancelled, self.isCurrentEditedThumbnailRequest(
                assetID: assetID, generation: generation,
                sourceRevision: thumbnailSourceRevision,
                documentRevision: thumbnailDocumentRevision,
                sourceIdentity: thumbnailSourceIdentity
            ), let destination = self.destination
            else { return }

            destination.setEditedThumbnailPresentedCrop(
                document.crop, rotation: document.rotation, for: assetID
            )
            let lut = destination.resolvedEditedThumbnailLUT(document.lut.lutID)
            let look = LookSignature(settings: document.lut, resolved: lut)
            // What to compare persisted pixels against: the live Look when it resolved, else the
            // saved revision's own. Pixels rendered here are always labelled with `look`, so an
            // ungraded provisional render can never claim the saved Look's identity.
            let frameLook = look.permitsExactReuse ? look : (savedLook ?? look)
            let revision = self.editedThumbnailRevision(document: document, look: look)
            let frameRevision = self.editedThumbnailRevision(document: document, look: frameLook)
            let materialized = MaterializedThumbnail(
                sourceIdentity: thumbnailSourceIdentity, revision: frameRevision, look: frameLook
            )
            // Appearance callbacks are repeated by both browsing surfaces. Reuse only a result
            // whose edit/Look revision and source identity still match; a non-nil revision alone
            // can describe an older saved edit or an earlier source at the same asset ID. Pixels
            // rendered while the Look was unresolved are provisional and never count as a match, so
            // they are replaced as soon as demand finds the Look resolvable.
            if !force, frameLook.permitsExactReuse, item.editedThumbnailRevision == frameRevision,
                self.materializedThumbnails[assetID] == materialized
            {
                return
            }
            guard !document.isIdentity else {
                self.presentIdentity(
                    revision: revision, assetID: assetID,
                    portableAssetID: thumbnailSourceIdentity.assetID
                )
                self.materializedThumbnails[assetID] = MaterializedThumbnail(
                    sourceIdentity: thumbnailSourceIdentity, revision: revision, look: look
                )
                return
            }

            // A persisted frame is judged by the shared classifier. Exact pixels are published
            // and nothing renders; stale pixels are shown, inert, while one render refines them.
            if let frameStore = self.frameStore,
               let hit = await frameStore.read(.edited, for: thumbnailSourceIdentity)
            {
                guard !Task.isCancelled, self.isCurrentEditedThumbnailRequest(
                    assetID: assetID, generation: generation,
                    sourceRevision: thumbnailSourceRevision,
                    documentRevision: thumbnailDocumentRevision,
                    sourceIdentity: thumbnailSourceIdentity
                ), let destination = self.destination
                else { return }
                let storedImage = NSImage(
                    cgImage: hit.image,
                    size: NSSize(width: hit.image.width, height: hit.image.height)
                )
                switch FrameClassifier.classify(
                    hit.frame.metadata,
                    against: FrameCurrentInputs(
                        source: thumbnailSourceIdentity, editHash: document.editHash, look: frameLook
                    )
                ) {
                case .exact:
                    destination.applyEditedThumbnail(storedImage, for: assetID, revision: frameRevision)
                    self.materializedThumbnails[assetID] = materialized
                    return
                case .staleCompatible, .provisionalOnly:
                    destination.applyStoredEditedThumbnail(storedImage, for: assetID)
                case .unusable:
                    break
                }
            }

            // Keep the last published raster visible while a replacement is prepared. It belongs
            // to this item, and the generation/source/document fences below ensure that only the
            // current request can replace it. Clearing to the source here makes both navigation
            // refreshes and ordinary edit changes visibly cycle through an unedited frame.

            // Metadata normally supplies the extent before a cell appears. Preparing the source
            // here is the safe fallback for a just-discovered cell and keeps the thumbnail render
            // at preview scale instead of accidentally rasterizing a full-resolution image.
            let renderSource = await engine.prepareSource(source)?.source ?? source
            let request = RenderRequest(
                source: renderSource,
                assetID: assetID,
                document: document,
                lut: lut,
                targetSize: CGSize(
                    width: Thumbnails.libraryMaxPixelSize,
                    height: Thumbnails.libraryMaxPixelSize),
                quality: .thumbnail,
                output: .raster, space: .current
            )
            let rendered: CGImage? = await engine.makeThumbnailCGImage(request)
            guard !Task.isCancelled, self.isCurrentEditedThumbnailRequest(
                assetID: assetID, generation: generation,
                sourceRevision: thumbnailSourceRevision,
                documentRevision: thumbnailDocumentRevision,
                sourceIdentity: thumbnailSourceIdentity
            ), let destination = self.destination
            else { return }
            // A failed render leaves the last published image in place — a stale persisted frame,
            // else the original. Its revision remains unchanged, so the next visible demand can
            // retry this request.
            guard let rendered else {
                self.materializedThumbnails.removeValue(forKey: assetID)
                return
            }
            let image = NSImage(
                cgImage: rendered, size: NSSize(width: rendered.width, height: rendered.height))
            destination.applyEditedThumbnail(image, for: assetID, revision: revision)
            self.materializedThumbnails[assetID] = MaterializedThumbnail(
                sourceIdentity: thumbnailSourceIdentity, revision: revision, look: look
            )
            // Only a render of the real Look is worth persisting: an ungraded provisional frame
            // would replace a good stored one.
            if let frameStore = self.frameStore, look.permitsExactReuse {
                let signature = FrameSignature(
                    source: thumbnailSourceIdentity, editHash: document.editHash, look: look,
                    workingSpace: request.space, pixelEpoch: RenderPipeline.pixelEpoch
                )
                let crop = document.crop
                let rotation = document.rotation
                let identity = thumbnailSourceIdentity
                let frame = await Task.detached {
                    ThumbnailFrameEncoder.editedFrame(
                        image: rendered, identity: identity, signature: signature,
                        crop: crop, rotation: rotation
                    )
                }.value
                // Encoding can outlive a rapid edit or source switch. Recheck the same fences used
                // for pixel publication before allowing obsolete work to replace the stable key.
                guard !Task.isCancelled, self.isCurrentEditedThumbnailRequest(
                    assetID: assetID, generation: generation,
                    sourceRevision: thumbnailSourceRevision,
                    documentRevision: thumbnailDocumentRevision,
                    sourceIdentity: thumbnailSourceIdentity
                ) else { return }
                if let frame { await frameStore.enqueueWrite(frame) }
            }
        }
    }

    /// Publish "no edited appearance": the original shows fitted in the source-shaped cell, and the
    /// persisted edited record is removed so a relaunch cannot revive a crop or fill that no longer
    /// applies.
    private func presentIdentity(
        revision: String, assetID: PhotoAssetID, portableAssetID: PortablePhotoAssetID
    ) {
        guard let destination else { return }
        destination.setEditedThumbnailPresentedCrop(.neutral, rotation: .zero, for: assetID)
        destination.applyEditedThumbnail(nil, for: assetID, revision: revision)
        if let frameStore {
            Task { await frameStore.remove(.edited, for: portableAssetID) }
        }
    }

    /// Validate every value that can make an edited thumbnail stale. The collection item is checked
    /// again because a file-backed source can be replaced in place while a thumbnail is rendering.
    private func isCurrentEditedThumbnailRequest(
        assetID: PhotoAssetID,
        generation: UInt64,
        sourceRevision: UInt64?,
        documentRevision: UInt64,
        sourceIdentity: PortablePhotoIdentity
    ) -> Bool {
        guard let destination, !destination.isEditedThumbnailShuttingDown,
            editedThumbnailGenerations[assetID] == generation,
            let item = destination.editedThumbnailItem(for: assetID)
        else { return false }

        let currentSource: ImageSource?
        if let url = item.url {
            currentSource = ImageSource(
                url: url, nativeExtent: item.thumbnailNativeExtent,
                portableIdentity: item.asset.source.portableIdentity
            )
        } else if let data = item.imageData {
            currentSource = ImageSource(
                data: data, nativeExtent: item.thumbnailNativeExtent,
                dataFingerprint: item.dataFingerprint,
                portableIdentity: item.asset.source.portableIdentity
            )
        } else {
            currentSource = nil
        }
        guard currentSource?.cacheIdentity == sourceIdentity else { return false }

        if let sourceRevision {
            guard destination.activeEditedThumbnailAssetID == assetID,
                destination.editedThumbnailSourceRevision == sourceRevision,
                destination.editedThumbnailDocumentRevision == documentRevision
            else { return false }
        } else {
            guard destination.editedThumbnailDocumentRevision(for: assetID) == documentRevision
            else { return false }
        }
        return true
    }

    private func editedThumbnailRevision(document: EditDocument, look: LookSignature) -> String {
        document.editHash + ":" + look.cacheComponent
    }

    /// Keep the active photo's badge out of the shared renderer while a preview burst is active.
    /// One task survives the quiet period, so a slider drag can invalidate and replace a queued
    /// thumbnail without submitting one thumbnail per document tick.
    func scheduleAfterSettle(
        for assetID: PhotoAssetID, priority: ImageWorkScheduler.Priority
    ) {
        guard let destination, !destination.isEditedThumbnailShuttingDown,
            assetID == destination.activeEditedThumbnailAssetID else { return }
        pendingEditedThumbnailAssetID = assetID
        editedThumbnailDebounceTasks[assetID]?.cancel()
        editedThumbnailDebounceTasks[assetID] = nil
        guard !destination.isEditedThumbnailInteractionActive,
            !destination.isEditedThumbnailPreviewDebouncing else { return }

        let sourceRevision = destination.editedThumbnailSourceRevision
        editedThumbnailDebounceTasks[assetID] = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled, let self, let destination = self.destination,
                !destination.isEditedThumbnailShuttingDown,
                destination.editedThumbnailSourceRevision == sourceRevision,
                destination.activeEditedThumbnailAssetID == assetID,
                !destination.isEditedThumbnailInteractionActive,
                !destination.isEditedThumbnailPreviewDebouncing
            else { return }
            self.editedThumbnailDebounceTasks[assetID] = nil
            self.pendingEditedThumbnailAssetID = nil
            self.request(for: assetID, priority: priority, force: true)
        }
    }

    func cancelDebounce(for assetID: PhotoAssetID?) {
        guard let assetID else { return }
        editedThumbnailDebounceTasks[assetID]?.cancel()
        editedThumbnailDebounceTasks[assetID] = nil
    }

    /// Every Look ID a published edited thumbnail was rendered against, resolved or not.
    var referencedLookIDs: Set<LUTID> {
        Set(materializedThumbnails.values.compactMap(\.look.lutID))
    }

    /// A LUT scan can resolve, replace, or remove a file-backed Look without changing any edit
    /// document. Only thumbnails already published against one of `ids` are revisited; a scan that
    /// touched none of them — including any byte-identical rescan — does no image work. Demand
    /// admission still bounds the re-renders.
    func refreshMaterializedThumbnails(affecting ids: Set<LUTID>) {
        guard let destination, !ids.isEmpty else { return }
        var demanded = destination.visibleEditedThumbnailAssetIDs
        if let active = destination.activeEditedThumbnailAssetID { demanded.insert(active) }
        let affected = materializedThumbnails.filter { $0.value.look.references(anyOf: ids) }.keys
        for assetID in affected where demanded.contains(assetID) {
            let priority: ImageWorkScheduler.Priority =
                assetID == destination.activeEditedThumbnailAssetID
                ? .activeEditor : .visibleGrid
            request(for: assetID, priority: priority, force: true)
        }
    }

    /// Admit library thumbnails that arrived while the editor owned preview rendering.
    /// Their demand was already bounded by the visible grid/filmstrip window.
    func admitDeferredDemands() {
        guard let destination, !destination.isEditedThumbnailShuttingDown,
            !destination.isEditedThumbnailInteractionActive,
            !destination.isEditedThumbnailPreviewDebouncing
        else { return }
        let deferred = deferredEditedThumbnailPriorities
            .sorted { $0.value.rawValue < $1.value.rawValue }
        deferredEditedThumbnailPriorities.removeAll(keepingCapacity: true)
        for (assetID, priority) in deferred {
            request(for: assetID, priority: priority)
        }
    }

    func shutdown() async {
        let debounceTasks = Array(editedThumbnailDebounceTasks.values)
        for task in debounceTasks { task.cancel() }
        editedThumbnailDebounceTasks.removeAll()
        for assetID in Array(editedThumbnailGenerations.keys) {
            editedThumbnailGenerations[assetID, default: 0] &+= 1
            workScheduler.cancel(
                id: ImageWorkScheduler.JobID(editedThumbnailJobPrefix + assetID.raw), pump: false
            )
        }
        materializedThumbnails.removeAll()
        pendingEditedThumbnailAssetID = nil
        deferredEditedThumbnailPriorities.removeAll()
        for task in debounceTasks { await task.value }
    }
}

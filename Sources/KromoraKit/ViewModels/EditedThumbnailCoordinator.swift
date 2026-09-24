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
    func editedThumbnailItem(for assetID: PhotoAssetID) -> ImageCollection.Item?
    func editedThumbnailDocument(for assetID: PhotoAssetID) -> EditDocument?
    func editedThumbnailDocumentRevision(for assetID: PhotoAssetID) -> UInt64
    func resolvedEditedThumbnailLUT(_ id: LUTID?) -> CubeLUT?
    func invalidateEditedThumbnail(for assetID: PhotoAssetID)
    func applyEditedThumbnail(_ image: NSImage?, for assetID: PhotoAssetID, revision: String)
    func setEditedThumbnailPresentedCrop(_ crop: CropAdjustments, for assetID: PhotoAssetID)
}

/// Owns demand admission, debounce tasks, generations, and job IDs for edit-aware collection
/// thumbnails. Documents and collection presentation remain with the application model.
@MainActor
final class EditedThumbnailCoordinator {
    private var editedThumbnailGenerations: [PhotoAssetID: UInt64] = [:]
    private var editedThumbnailDebounceTasks: [PhotoAssetID: Task<Void, Never>] = [:]
    private var pendingEditedThumbnailAssetID: PhotoAssetID?
    private let editedThumbnailJobPrefix = "edited-thumbnail-"

    private let workScheduler: ImageWorkScheduler
    private let engine: any EditedThumbnailRendering
    private let editStore: EditDocumentStore
    weak var destination: (any EditedThumbnailDestination)?

    init(
        workScheduler: ImageWorkScheduler,
        engine: any EditedThumbnailRendering,
        editStore: EditDocumentStore,
        destination: (any EditedThumbnailDestination)? = nil
    ) {
        self.workScheduler = workScheduler
        self.engine = engine
        self.editStore = editStore
        self.destination = destination
    }

    var pendingAssetID: PhotoAssetID? { pendingEditedThumbnailAssetID }

    func clearPendingRequest() { pendingEditedThumbnailAssetID = nil }

    /// Invalidate an edited-thumbnail operation without removing a bitmap that has already been
    /// published for the item. Cancellation is cooperative — a renderer may still be returning
    /// from a framework call — so the generation bump is the durable fence for that late result.
    func invalidateWork(for assetID: PhotoAssetID?) {
        guard let assetID else { return }
        editedThumbnailGenerations[assetID] = (editedThumbnailGenerations[assetID] ?? 0) &+ 1
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

        // A completed result is shared by both surfaces. Repeated SwiftUI appearance callbacks
        // should not re-render it; a force request is reserved for explicit edit/look changes.
        if !force, item.editedThumbnailRevision != nil { return }

        let generation = (editedThumbnailGenerations[assetID] ?? 0) &+ 1
        editedThumbnailGenerations[assetID] = generation
        destination.invalidateEditedThumbnail(for: assetID)

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
            let revision = editedThumbnailRevision(document: inMemoryDocument, lut: nil)
            destination.applyEditedThumbnail(nil, for: assetID, revision: revision)
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
            if let inMemoryDocument {
                document = inMemoryDocument
            } else {
                document = await editStore.load(for: sourceReference).document
            }
            guard !Task.isCancelled, self.isCurrentEditedThumbnailRequest(
                assetID: assetID, generation: generation,
                sourceRevision: thumbnailSourceRevision,
                documentRevision: thumbnailDocumentRevision,
                sourceIdentity: thumbnailSourceIdentity
            ), let destination = self.destination
            else { return }

            destination.setEditedThumbnailPresentedCrop(document.crop, for: assetID)
            let lut = destination.resolvedEditedThumbnailLUT(document.lut.lutID)
            let revision = self.editedThumbnailRevision(document: document, lut: lut)
            guard !document.isIdentity else {
                destination.applyEditedThumbnail(nil, for: assetID, revision: revision)
                return
            }

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
                    width: Thumbnails.defaultMaxPixelSize,
                    height: Thumbnails.defaultMaxPixelSize),
                quality: .thumbnail,
                output: .raster, space: .current
            )
            let image: NSImage?
            if let cgImage = await engine.makeThumbnailCGImage(request) {
                image = NSImage(
                    cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            } else {
                image = nil
            }
            guard !Task.isCancelled, self.isCurrentEditedThumbnailRequest(
                assetID: assetID, generation: generation,
                sourceRevision: thumbnailSourceRevision,
                documentRevision: thumbnailDocumentRevision,
                sourceIdentity: thumbnailSourceIdentity
            ), let destination = self.destination
            else { return }
            destination.applyEditedThumbnail(image, for: assetID, revision: revision)
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

    private func editedThumbnailRevision(document: EditDocument, lut: CubeLUT?) -> String {
        document.editHash + ":" + (lut?.cacheFingerprint ?? "unresolved")
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

    /// A LUT scan can resolve or replace a file-backed Look without changing the edit document.
    /// Only items that already produced an edited thumbnail are revisited; demand admission still
    /// keeps the work bounded and avoids a full-library render after every Look-folder scan.
    func refreshMaterializedThumbnails() {
        guard let destination else { return }
        for item in destination.editedThumbnailItems where item.editedThumbnailRevision != nil {
            let priority: ImageWorkScheduler.Priority =
                item.id == destination.activeEditedThumbnailAssetID
                ? .activeEditor : .visibleGrid
            request(for: item.id, priority: priority, force: true)
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
        pendingEditedThumbnailAssetID = nil
        for task in debounceTasks { await task.value }
    }
}

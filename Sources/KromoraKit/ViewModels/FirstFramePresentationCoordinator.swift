import CoreGraphics
import CoreImage
import Foundation

/// Owns the first-paint candidates held back while a photo loads: the thumbnail staged at
/// selection, the camera JPEG waiting on edit geometry or the stored-frame lookup, and the
/// short fallback timer that releases them when the stored-frame read is slow.
///
/// It holds no presentation surface and no `AppViewModel` reference. Each decision returns a
/// value (`Release`, `EmbeddedDecision`) that the root applies to the surface, and every
/// decision is fenced by the presentation session's generation so a stale generation can never
/// publish. `PreviewPresentationCoordinator` remains the owner of the session itself.
@MainActor
final class FirstFramePresentationCoordinator {
    struct DeferredThumbnail {
        let image: CIImage
        let source: PreviewPresentationCoordinator.CandidateSource
        let assetID: PhotoAssetID
        let identity: PortablePhotoIdentity
        let generation: UInt64
        let nativeExtent: CGSize
    }

    /// Candidates that may now be presented. The thumbnail must be presented before the
    /// embedded frame is re-evaluated, because an admitted thumbnail suppresses the embedded one.
    struct Release {
        var thumbnail: DeferredThumbnail?
        var embedded: SourceSessionCoordinator.FirstFramePublication?
    }

    /// Current load state the embedded-frame decision depends on.
    struct EmbeddedContext {
        let sourceRevision: UInt64
        let activeAssetID: PhotoAssetID?
        let isSourceDocumentResolved: Bool
        let isPreviewLoading: Bool
        let hasPublishedFrame: Bool
    }

    enum EmbeddedDecision {
        /// Dropped, or parked in the deferred slot until a later release.
        case hold
        case present
    }

    static let storedFrameFirstPaintBudget: Duration = .milliseconds(50)

    private let presentation: PreviewPresentationCoordinator
    private let fallbackBudget: Duration
    private(set) var deferredThumbnail: DeferredThumbnail?
    private(set) var deferredEmbedded: SourceSessionCoordinator.FirstFramePublication?
    private var fallbackTask: Task<Void, Never>?
    private var fallbackGeneration: UInt64?

    init(
        presentation: PreviewPresentationCoordinator,
        fallbackBudget: Duration = FirstFramePresentationCoordinator.storedFrameFirstPaintBudget
    ) {
        self.presentation = presentation
        self.fallbackBudget = fallbackBudget
    }

    /// Clears every deferred candidate and the fallback timer for a new selection.
    func resetForSource() {
        deferredThumbnail = nil
        deferredEmbedded = nil
        cancelFallback()
    }

    func stage(thumbnail: DeferredThumbnail?) {
        deferredThumbnail = thumbnail
    }

    /// Arms the budget timer for `generation`. If the stored-frame lookup is still loading when
    /// it expires, `onExpiry` runs with the candidates that may now be presented.
    func armFallback(
        generation: UInt64,
        onExpiry: @escaping @MainActor @Sendable (Release) -> Void
    ) {
        fallbackGeneration = generation
        fallbackTask?.cancel()
        let budget = fallbackBudget
        fallbackTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: budget) } catch { return }
            guard let self, self.fallbackGeneration == generation,
                self.presentation.isStoredFrameLookupLoading
            else { return }
            self.fallbackGeneration = nil
            self.fallbackTask = nil
            onExpiry(self.takeReleasable(generation: generation))
        }
    }

    func cancelFallback() {
        fallbackTask?.cancel()
        fallbackTask = nil
        fallbackGeneration = nil
    }

    /// The stored-frame lookup finished. A hit supersedes every deferred candidate; a miss
    /// releases them.
    func storedFrameLookupFinished(generation: UInt64, hit: Bool) -> Release {
        cancelFallback()
        if hit {
            deferredThumbnail = nil
            deferredEmbedded = nil
            return Release()
        }
        return takeReleasable(generation: generation)
    }

    /// Edit geometry resolved. A cropped or rotated document discards the source-only
    /// candidates; otherwise they are released unless the stored-frame head start is pending.
    func sourceGeometryResolved(document: EditDocument, generation: UInt64) -> Release {
        presentation.resolveSourceGeometry(document: document, generation: generation)
        if presentation.presentationSession?.allowsSourceGeometry != true {
            if deferredThumbnail?.source == .originalThumbnail { deferredThumbnail = nil }
            deferredEmbedded = nil
            return Release()
        }
        guard fallbackGeneration != generation else { return Release() }
        return takeReleasable(generation: generation)
    }

    /// A non-embedded candidate was admitted; it supersedes any waiting camera JPEG.
    func candidateAdmitted(_ source: PreviewPresentationCoordinator.CandidateSource) {
        if source != .embeddedJPEG { deferredEmbedded = nil }
    }

    /// Decides whether the camera JPEG may be painted now, parking it when it must wait.
    func evaluateEmbedded(
        _ publication: SourceSessionCoordinator.FirstFramePublication,
        context: EmbeddedContext
    ) -> EmbeddedDecision {
        let request = publication.request
        guard request.sourceRevision == context.sourceRevision,
            request.assetID == context.activeAssetID
        else { return .hold }
        if presentation.presentationSession?.allowsSourceGeometry != true {
            // The document read may still be pending. Retry after it resolves; a cropped or
            // rotated document will discard this source-only frame rather than flash it.
            if !context.isSourceDocumentResolved { deferredEmbedded = publication }
            return .hold
        }
        if presentation.isStoredFrameLookupLoading,
            fallbackGeneration == request.sourceRevision,
            presentation.presentationSession?.candidateSource == nil
        {
            deferredEmbedded = publication
            return .hold
        }
        guard context.isPreviewLoading,
            !context.hasPublishedFrame,
            presentation.presentationSession?.candidateSource == nil,
            presentation.admitsPublication(
                assetID: request.assetID,
                identity: publication.preparation.source.portableIdentity,
                generation: request.sourceRevision
            )
        else { return .hold }
        return .present
    }

    /// Takes the staged thumbnail when it is still the current generation's to present.
    func takeDeferredThumbnail(for generation: UInt64) -> DeferredThumbnail? {
        guard let deferred = deferredThumbnail,
            deferred.generation == generation,
            presentation.presentationSession?.generation == generation,
            presentation.presentationSession?.candidateSource == nil
        else { return nil }
        if deferred.source == .originalThumbnail,
            presentation.presentationSession?.allowsSourceGeometry != true
        { return nil }
        deferredThumbnail = nil
        return deferred
    }

    private func takeReleasable(generation: UInt64) -> Release {
        let thumbnail = takeDeferredThumbnail(for: generation)
        let embedded = deferredEmbedded
        deferredEmbedded = nil
        return Release(thumbnail: thumbnail, embedded: embedded)
    }
}

extension PreviewSurface {
    /// Camera previews are often still sensor-landscape when the RAW's display size is portrait.
    /// Stretching that JPEG onto the native frame looks like a 90° rotation; one quarter-turn
    /// that matches native aspect is enough, and a matching pair of axes is a no-op.
    static func alignedEmbeddedFirstFrame(_ image: CIImage, to native: CGSize) -> CIImage {
        let src = image.extent.size
        guard src.width > 1, src.height > 1, native.width > 1, native.height > 1,
            src.width.isFinite, src.height.isFinite,
            native.width.isFinite, native.height.isFinite
        else {
            return image
        }
        let srcLandscape = src.width >= src.height
        let nativeLandscape = native.width >= native.height
        guard srcLandscape != nativeLandscape else { return image }
        let nativeAspect = native.width / native.height
        func aspectMismatch(_ candidate: CIImage) -> CGFloat {
            let size = candidate.extent.size
            guard size.height > 0 else { return .greatestFiniteMagnitude }
            return abs(size.width / size.height - nativeAspect)
        }
        let right = image.oriented(.right)
        let left = image.oriented(.left)
        return aspectMismatch(right) <= aspectMismatch(left) ? right : left
    }
}

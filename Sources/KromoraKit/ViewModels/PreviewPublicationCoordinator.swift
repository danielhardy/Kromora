import CoreGraphics
import CoreImage
import Foundation

/// Values and surface hooks used by the preview publication funnel. The root keeps the published
/// editor state and surfaces; publication state and lifecycle checks live here.
@MainActor
protocol PreviewPublicationDestination: AnyObject {
    var publicationIsShuttingDown: Bool { get }
    var publicationActiveAssetID: PhotoAssetID? { get }
    var publicationImageSource: ImageSource? { get }
    var publicationSourceRevision: UInt64 { get }
    var publicationDisplayRevision: UInt64 { get }
    var publicationDisplayDocument: EditDocument { get }
    var publicationSourceName: String { get }
    var publicationIsAutoAdjustmentInProgress: Bool { get }
    var publicationIsSideBySideVisible: Bool { get }
    var publicationStoredEditsResolvedSourceRevision: UInt64? { get }

    func publishPreviewReady()
    func publishPreviewFailure()
    func publishAutoAdjustmentReady()
    func publishAutoAdjustmentFailure()
    func publishStatusMessage(_ message: String)
    func publishStatusMessageIfLoading(_ expected: String, replacement: String)
    func presentAdjustedFrame(
        _ image: CIImage, request: RenderRequest, revision: UInt64,
        onPresented: (@MainActor () -> Void)?
    ) -> Bool
    func publicationScheduleOriginalPreview(
        allowHiddenPreparation: Bool, allowBeforePresentationConfirmation: Bool
    )
    func publicationCancelComparisonPreview()
    func publicationUpdateHistogram(for request: RenderRequest, presentedImage: CIImage?)
    func publicationScheduleIdlePreviewBuild()
    func writeCanonicalPreview(_ image: CIImage, request: RenderRequest)
}

/// Owns settled and interactive preview publication without owning a view model or surface.
@MainActor
final class PreviewPublicationCoordinator {
    private(set) var lastPresentedVisibleRequest: RenderRequest?
    private(set) var lastPresentedVisibleImage: CIImage?
    private(set) var lastPublishedVisibleRequest: RenderRequest?
    private var pendingDevelopChange = false
    weak var destination: (any PreviewPublicationDestination)?

    init(destination: (any PreviewPublicationDestination)? = nil) {
        self.destination = destination
    }

    var hasPublishedFrame: Bool { lastPublishedVisibleRequest != nil }

    func resetForSource() {
        lastPresentedVisibleRequest = nil
        lastPresentedVisibleImage = nil
        lastPublishedVisibleRequest = nil
        pendingDevelopChange = false
    }

    func noteDevelopChange(_ changed: Bool = true) {
        pendingDevelopChange = pendingDevelopChange || changed
    }

    func publish(_ publication: PreviewCoordinator.Publication) {
        guard let destination, !destination.publicationIsShuttingDown,
            publication.assetID == destination.publicationActiveAssetID,
            publication.sourceRevision == destination.publicationSourceRevision,
            publication.displayRevision == destination.publicationDisplayRevision,
            publication.request.source == destination.publicationImageSource
        else { return }

        let request = publication.request
        let image = publication.gpuImage ?? publication.image.map(CIImage.init)
        if publication.phase == .settled, let image {
            presentSettledRaster(
                image, request: request, assetID: publication.assetID,
                sourceRevision: publication.sourceRevision,
                displayRevision: publication.displayRevision,
                surfaceRevision: publication.revision
            )
        } else if let image {
            _ = destination.presentAdjustedFrame(
                image, request: request, revision: publication.revision, onPresented: nil
            )
        }

        guard publication.gpuImage != nil || publication.image != nil else {
            if publication.phase == .settled {
                destination.publishPreviewFailure()
                destination.publishAutoAdjustmentFailure()
                destination.publishStatusMessage("Could not render \(destination.publicationSourceName)")
            }
            return
        }

        if publication.phase == .settled {
            lastPublishedVisibleRequest = request
            if destination.publicationIsSideBySideVisible {
                destination.publicationScheduleOriginalPreview(
                    allowHiddenPreparation: false,
                    allowBeforePresentationConfirmation: true
                )
            }
        }
    }

    @discardableResult
    func presentSettledRaster(
        _ image: CIImage, request: RenderRequest, assetID: PhotoAssetID?,
        sourceRevision: UInt64, displayRevision: UInt64, surfaceRevision: UInt64? = nil
    ) -> Bool {
        guard let destination else { return false }
        let presented = destination.presentAdjustedFrame(
            image, request: request, revision: surfaceRevision ?? displayRevision,
            onPresented: { [weak self] in
                self?.didPresentVisibleFrame(
                    request, assetID: assetID, sourceRevision: sourceRevision,
                    displayRevision: displayRevision, presentedImage: image
                )
            }
        )
        if presented { lastPublishedVisibleRequest = request }
        return presented
    }

    private func didPresentVisibleFrame(
        _ request: RenderRequest, assetID: PhotoAssetID?, sourceRevision: UInt64,
        displayRevision: UInt64, presentedImage: CIImage?
    ) {
        guard let destination,
            assetID == destination.publicationActiveAssetID,
            sourceRevision == destination.publicationSourceRevision,
            displayRevision == destination.publicationDisplayRevision,
            request.source == destination.publicationImageSource,
            request.document == destination.publicationDisplayDocument
        else { return }

        destination.publishPreviewReady()
        if request.source.kind == .raw {
            let loadingPrefix = "Loading \(destination.publicationSourceName)..."
            destination.publishStatusMessageIfLoading(
                loadingPrefix,
                replacement: "\(destination.publicationSourceName)  \(Int(request.source.nativeExtent.width))\u{00D7}\(Int(request.source.nativeExtent.height))"
            )
        }
        if !destination.publicationIsAutoAdjustmentInProgress {
            destination.publishAutoAdjustmentReady()
        }
        lastPresentedVisibleRequest = request
        lastPresentedVisibleImage = presentedImage
        let needsComparisonRefresh = pendingDevelopChange
        if destination.publicationIsSideBySideVisible || needsComparisonRefresh {
            destination.publicationScheduleOriginalPreview(
                allowHiddenPreparation: needsComparisonRefresh,
                allowBeforePresentationConfirmation: false
            )
        } else {
            destination.publicationCancelComparisonPreview()
        }
        pendingDevelopChange = false

        if destination.publicationStoredEditsResolvedSourceRevision == sourceRevision {
            destination.publicationUpdateHistogram(for: request, presentedImage: presentedImage)
        }
        destination.publicationScheduleIdlePreviewBuild()

        guard request.quality == .preview, request.sourceROI == nil, let presentedImage else {
            return
        }
        destination.writeCanonicalPreview(presentedImage, request: request)
    }
}

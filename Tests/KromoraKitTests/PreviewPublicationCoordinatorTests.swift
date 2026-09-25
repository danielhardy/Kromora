import CoreGraphics
import CoreImage
import Foundation
import XCTest

@testable import KromoraKit

@MainActor
final class PreviewPublicationCoordinatorTests: XCTestCase {
    func testStaleAssetOrDisplayRevisionDoesNotPresent() throws {
        let destination = FakeDestination()
        let coordinator = PreviewPublicationCoordinator(destination: destination)
        let publication = try makePublication(destination: destination)

        let staleAsset = PreviewCoordinator.Publication(
            request: publication.request, image: publication.image, gpuImage: nil,
            revision: publication.revision, assetID: PhotoAssetID(rawValue: "stale-asset"),
            sourceRevision: publication.sourceRevision,
            displayRevision: publication.displayRevision, phase: publication.phase
        )
        coordinator.publish(staleAsset)
        XCTAssertEqual(destination.presentCount, 0)

        destination.displayRevision &+= 1
        coordinator.publish(publication)
        XCTAssertEqual(destination.presentCount, 0)
    }

    func testInteractiveFramePresentsWithoutHistogramOrIdleAdmission() throws {
        let destination = FakeDestination()
        let coordinator = PreviewPublicationCoordinator(destination: destination)
        let settled = try makePublication(destination: destination)
        let interactive = PreviewCoordinator.Publication(
            request: settled.request, image: settled.image, gpuImage: nil,
            revision: settled.revision, assetID: settled.assetID,
            sourceRevision: settled.sourceRevision,
            displayRevision: settled.displayRevision, phase: .interactive
        )

        coordinator.publish(interactive)

        XCTAssertEqual(destination.presentCount, 1)
        XCTAssertEqual(destination.histogramCount, 0)
        XCTAssertEqual(destination.idleCount, 0)
    }

    func testSettledCompleteFrameAdmitsSupportingWorkAndCanonicalCache() throws {
        let destination = FakeDestination()
        destination.storedEditsResolvedSourceRevision = destination.sourceRevision
        let coordinator = PreviewPublicationCoordinator(destination: destination)
        let publication = try makePublication(destination: destination)

        coordinator.publish(publication)

        XCTAssertEqual(destination.presentCount, 1)
        XCTAssertEqual(destination.histogramCount, 1)
        XCTAssertEqual(destination.idleCount, 1)
        XCTAssertEqual(destination.canonicalWriteCount, 1)
        XCTAssertEqual(destination.previewState, .ready)
        XCTAssertEqual(coordinator.lastPresentedVisibleRequest, publication.request)
    }

    func testSettledROIFrameDoesNotWriteCanonicalCache() throws {
        let destination = FakeDestination()
        let coordinator = PreviewPublicationCoordinator(destination: destination)
        let source = destination.imageSource
        let request = RenderRequest(
            source: source, document: EditDocument(),
            sourceROI: CGRect(x: 1, y: 1, width: 10, height: 10), quality: .preview
        )
        let publication = PreviewCoordinator.Publication(
            request: request, image: try Fixtures.makeCGImage(width: 32, height: 24),
            gpuImage: nil, revision: 1, assetID: destination.activeAssetID,
            sourceRevision: destination.sourceRevision,
            displayRevision: destination.displayRevision, phase: .settled
        )

        coordinator.publish(publication)

        XCTAssertEqual(destination.canonicalWriteCount, 0)
        XCTAssertEqual(destination.idleCount, 1)
    }

    func testDevelopChangeSchedulesOneComparisonRefreshAndThenClears() throws {
        let destination = FakeDestination()
        let coordinator = PreviewPublicationCoordinator(destination: destination)
        let publication = try makePublication(destination: destination)
        coordinator.noteDevelopChange()

        coordinator.publish(publication)
        coordinator.publish(publication)

        XCTAssertEqual(destination.originalScheduleCount, 1)
        XCTAssertTrue(destination.lastOriginalScheduleAllowedHiddenPreparation)
    }

    func testResetForSourceClearsPublishedFrameAccessor() throws {
        let destination = FakeDestination()
        let coordinator = PreviewPublicationCoordinator(destination: destination)
        coordinator.publish(try makePublication(destination: destination))
        XCTAssertTrue(coordinator.hasPublishedFrame)

        coordinator.resetForSource()

        XCTAssertFalse(coordinator.hasPublishedFrame)
        XCTAssertNil(coordinator.lastPresentedVisibleRequest)
        XCTAssertNil(coordinator.lastPresentedVisibleImage)
    }

    private func makePublication(
        destination: FakeDestination
    ) throws -> PreviewCoordinator.Publication {
        let request = RenderRequest(
            source: destination.imageSource, document: EditDocument(), quality: .preview
        )
        return PreviewCoordinator.Publication(
            request: request, image: try Fixtures.makeCGImage(width: 32, height: 24),
            gpuImage: nil, revision: 1, assetID: destination.activeAssetID,
            sourceRevision: destination.sourceRevision,
            displayRevision: destination.displayRevision, phase: .settled
        )
    }
}

@MainActor
private final class FakeDestination: PreviewPublicationDestination {
    let activeAssetID = PhotoAssetID(rawValue: "preview-publication-test-asset")
    let imageSource = ImageSource(
        backing: .data(Data("preview-publication-test".utf8)),
        kind: .standard, nativeExtent: CGSize(width: 32, height: 24)
    )
    var isShuttingDown = false
    var sourceRevision: UInt64 = 4
    var displayRevision: UInt64 = 7
    var displayDocument = EditDocument()
    var sourceName = "Test"
    var isAutoAdjustmentInProgress = false
    var isSideBySideVisible = false
    var storedEditsResolvedSourceRevision: UInt64?
    var previewState: AppViewModel.PreviewState = .loading
    var statusMessage = "Loading Test..."
    var presentCount = 0
    var histogramCount = 0
    var idleCount = 0
    var canonicalWriteCount = 0
    var originalScheduleCount = 0
    var lastOriginalScheduleAllowedHiddenPreparation = false
    var comparisonCancelCount = 0

    var publicationIsShuttingDown: Bool { isShuttingDown }
    var publicationActiveAssetID: PhotoAssetID? { activeAssetID }
    var publicationImageSource: ImageSource? { imageSource }
    var publicationSourceRevision: UInt64 { sourceRevision }
    var publicationDisplayRevision: UInt64 { displayRevision }
    var publicationDisplayDocument: EditDocument { displayDocument }
    var publicationSourceName: String { sourceName }
    var publicationIsAutoAdjustmentInProgress: Bool { isAutoAdjustmentInProgress }
    var publicationIsSideBySideVisible: Bool { isSideBySideVisible }
    var publicationStoredEditsResolvedSourceRevision: UInt64? {
        storedEditsResolvedSourceRevision
    }

    func publishPreviewReady() { previewState = .ready }
    func publishPreviewFailure() { previewState = .failed }
    func publishAutoAdjustmentReady() {}
    func publishAutoAdjustmentFailure() {}
    func publishStatusMessage(_ message: String) { statusMessage = message }
    func publishStatusMessageIfLoading(_ expected: String, replacement: String) {
        if statusMessage == expected { statusMessage = replacement }
    }
    func presentAdjustedFrame(
        _ image: CIImage, request: RenderRequest, revision: UInt64,
        onPresented: (@MainActor () -> Void)?
    ) -> Bool {
        presentCount += 1
        onPresented?()
        return true
    }
    func publicationScheduleOriginalPreview(
        allowHiddenPreparation: Bool, allowBeforePresentationConfirmation: Bool
    ) {
        originalScheduleCount += 1
        lastOriginalScheduleAllowedHiddenPreparation = allowHiddenPreparation
    }
    func publicationCancelComparisonPreview() { comparisonCancelCount += 1 }
    func publicationUpdateHistogram(for request: RenderRequest, presentedImage: CIImage?) {
        histogramCount += 1
    }
    func publicationScheduleIdlePreviewBuild() { idleCount += 1 }
    func writeCanonicalPreview(_ image: CIImage, request: RenderRequest) {
        canonicalWriteCount += 1
    }
}

import XCTest
import CoreImage
import MetalKit
@testable import LumoKit

@MainActor
final class PreviewSurfaceTests: XCTestCase {

    private final class TrackingMTKView: MTKView {
        private(set) var redrawRequestCount = 0

        override func setNeedsDisplay(_ rect: NSRect) {
            redrawRequestCount += 1
            super.setNeedsDisplay(rect)
        }
    }

    func testPresentStoresTheWorkingSpaceForThePresentedImage() {
        let surface = PreviewSurface()
        let image = CIImage(color: CIColor(red: 0.5, green: 0.25, blue: 0.75))

        surface.present(image, space: .displayP3)

        XCTAssertTrue(surface.image === image)
        XCTAssertEqual(surface.space, .displayP3)
    }

    func testClearResetsTheWorkingSpace() {
        let surface = PreviewSurface()
        surface.present(CIImage(color: .red), space: .displayP3)

        surface.clear()

        XCTAssertNil(surface.image)
        XCTAssertEqual(surface.space, .current)
    }

    func testHeadlessSurfaceConfirmsACompletedPresentationImmediately() {
        let surface = PreviewSurface()
        let telemetry = LiveEditTelemetry()
        let source = ImageSource(
            url: URL(fileURLWithPath: "/tmp/presentation-test.png"),
            nativeExtent: CGSize(width: 2, height: 2)
        )
        var confirmed = false

        surface.present(
            CIImage(color: .red), revision: 1, telemetry: telemetry, source: source,
            onPresented: { confirmed = true }
        )

        XCTAssertTrue(confirmed, "headless tests should not wait for a drawable that does not exist")
    }

    func testPublicationRequestsRedrawOnAnExistingMetalView() {
        let surface = PreviewSurface()
        let view = TrackingMTKView(frame: CGRect(x: 0, y: 0, width: 32, height: 24), device: nil)
        surface.attachDisplayView(view)
        let requestsBeforePublication = view.redrawRequestCount

        XCTAssertTrue(surface.present(CIImage(color: .red)))
        XCTAssertGreaterThan(view.redrawRequestCount, requestsBeforePublication,
                             "publishing a frame must invalidate a paused MTKView")
    }

    func testAttachingAViewRequestsAFramePublishedBeforeTheViewWasCreated() {
        let surface = PreviewSurface()
        XCTAssertTrue(surface.present(CIImage(color: .red)))

        let view = TrackingMTKView(frame: CGRect(x: 0, y: 0, width: 32, height: 24), device: nil)
        surface.attachDisplayView(view)

        XCTAssertGreaterThan(view.redrawRequestCount, 0,
                             "a newly-created view must draw an already-published frame")
    }

    func testSkippedDrawableStaysPendingUntilARealPresentation() {
        let surface = PreviewSurface()
        surface.attachPresentationLifecycle()
        let telemetry = LiveEditTelemetry()
        let source = ImageSource(
            url: URL(fileURLWithPath: "/tmp/skipped-presentation-test.png"),
            nativeExtent: CGSize(width: 2, height: 2)
        )
        let request = RenderRequest(
            source: source, document: EditDocument(), quality: .interactive, output: .raster
        )
        telemetry.input(source: source, request: request, revision: 1, time: 10)
        var confirmed = false

        surface.present(
            CIImage(color: .red), revision: 1, telemetry: telemetry, source: source,
            onPresented: { confirmed = true }
        )

        XCTAssertTrue(
            surface.markDrawablePresented(revision: 1, time: 0),
            "a skipped drawable must be replayed into a fresh drawable"
        )
        XCTAssertFalse(confirmed, "an occluded drawable must not count as visible presentation")

        XCTAssertFalse(
            surface.markDrawablePresented(revision: 1, time: 1),
            "a retry with a presented timestamp is a real presentation, not another retry"
        )
        XCTAssertTrue(confirmed, "the confirmation should fire after the retry reaches a drawable")
        XCTAssertTrue(telemetry.measurements[0].skippedDrawable)
        XCTAssertNil(telemetry.report().p50InputToPresentMS,
                     "a skipped-then-retried frame must not enter presentation statistics")
    }

    func testSkippedDrawRetriesAreBoundedAndQuietAfterConsecutiveSkips() async throws {
        let coordinator = PreviewSurfaceView.Coordinator()
        let view = TrackingMTKView(frame: CGRect(x: 0, y: 0, width: 32, height: 24), device: nil)
        coordinator.view = view
        let baseline = view.redrawRequestCount

        // Coalescing: two skips landing in the same turn schedule a single invalidation.
        coordinator.handleSkippedDrawable(revision: 7)
        coordinator.handleSkippedDrawable(revision: 7)
        try await waitForRedrawCount(view, toBecome: baseline + 1)

        // Bound: the third consecutive skip suppresses retries; later skips stay quiet.
        coordinator.handleSkippedDrawable(revision: 7)
        try await assertRedrawCountSettles(view, at: baseline + 1)
        coordinator.handleSkippedDrawable(revision: 7)
        coordinator.handleSkippedDrawable(revision: 7)
        try await assertRedrawCountSettles(view, at: baseline + 1)
    }

    func testVisibilityRestoreRearmsSkippedDrawRetries() async throws {
        let coordinator = PreviewSurfaceView.Coordinator()
        let view = TrackingMTKView(frame: CGRect(x: 0, y: 0, width: 32, height: 24), device: nil)
        coordinator.view = view
        let baseline = view.redrawRequestCount

        coordinator.handleSkippedDrawable(revision: 9)
        try await waitForRedrawCount(view, toBecome: baseline + 1)
        coordinator.handleSkippedDrawable(revision: 9)
        try await waitForRedrawCount(view, toBecome: baseline + 2)
        coordinator.handleSkippedDrawable(revision: 9)
        try await assertRedrawCountSettles(view, at: baseline + 2)

        // A visibility restore repaints the latest revision and lifts the suppression so the
        // still-pending revision can retry once it has a drawable again.
        coordinator.visibilityDidChange()
        try await waitForRedrawCount(view, toBecome: baseline + 3)
        coordinator.handleSkippedDrawable(revision: 9)
        try await waitForRedrawCount(view, toBecome: baseline + 4)
    }

    /// The retry scheduler paces invalidations through a yielded main-actor task, so poll
    /// briefly rather than assuming a fixed number of yields drains it.
    private func waitForRedrawCount(
        _ view: TrackingMTKView, toBecome expected: Int,
        file: StaticString = #filePath, line: UInt = #line
    ) async throws {
        for _ in 0..<200 {
            if view.redrawRequestCount == expected { return }
            try await Task.sleep(nanoseconds: 2_000_000)
        }
        XCTFail("redraw count settled at \(view.redrawRequestCount), expected \(expected)",
                file: file, line: line)
    }

    /// Asserting quiet requires waiting out any in-flight paced task, then confirming silence.
    private func assertRedrawCountSettles(
        _ view: TrackingMTKView, at expected: Int,
        file: StaticString = #filePath, line: UInt = #line
    ) async throws {
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(view.redrawRequestCount, expected,
                       "suppressed skipped draws must not schedule further redraws",
                       file: file, line: line)
    }

    func testLatestPublicationRemainsAvailableAcrossSkippedReplacement() {
        let surface = PreviewSurface()
        surface.attachPresentationLifecycle()
        let telemetry = LiveEditTelemetry()
        let source = ImageSource(
            url: URL(fileURLWithPath: "/tmp/skipped-replacement-test.png"),
            nativeExtent: CGSize(width: 2, height: 2)
        )
        var presentedRevision: UInt64?
        let first = CIImage(color: .red)
        let latest = CIImage(color: .blue)

        surface.present(
            first, revision: 1, telemetry: telemetry, source: source,
            onPresented: { presentedRevision = 1 }
        )
        XCTAssertTrue(surface.markDrawablePresented(revision: 1, time: 0))
        XCTAssertTrue(surface.image === first)

        surface.present(
            latest, revision: 2, telemetry: telemetry, source: source,
            onPresented: { presentedRevision = 2 }
        )

        XCTAssertTrue(surface.image === latest)
        XCTAssertFalse(surface.markDrawablePresented(revision: 2, time: 1))
        XCTAssertEqual(presentedRevision, 2)
        XCTAssertTrue(surface.image === latest)
    }

    func testAFailedReplacementKeepsTheLastValidFrame() throws {
        let surface = PreviewSurface()
        let first = CIImage(color: .red)
        let replacement = CIImage(color: .blue)

        surface.present(first)
        let firstRevision = try XCTUnwrap(surface.pendingDisplayRevision())
        surface.markPresentationSucceeded(displayRevision: firstRevision)

        surface.present(replacement)
        let replacementRevision = try XCTUnwrap(surface.pendingDisplayRevision())
        surface.rejectPresentation(displayRevision: replacementRevision)

        XCTAssertTrue(surface.image === first)
        XCTAssertNil(surface.pendingDisplayRevision())
    }

    func testAStalePresentationCompletionCannotCommitOverANewerFrame() throws {
        let surface = PreviewSurface()
        let first = CIImage(color: .red)
        let second = CIImage(color: .green)

        surface.present(first)
        let firstRevision = try XCTUnwrap(surface.pendingDisplayRevision())
        surface.present(second)
        surface.markPresentationSucceeded(displayRevision: firstRevision)

        XCTAssertTrue(surface.image === second)
        XCTAssertNotNil(surface.pendingDisplayRevision())
    }

    func testNavigationCannotReplaceAValidSharperFrameWithALowerDetailFrame() throws {
        let surface = PreviewSurface()
        let identity = PreviewFrameIdentity(sourceToken: "source", documentHash: "document", space: .current)
        let sharp = CIImage(color: .red)
        let cheap = CIImage(color: .blue)

        surface.present(sharp, detailIdentity: identity, detailFactor: 1)
        let sharpRevision = try XCTUnwrap(surface.pendingDisplayRevision())
        surface.markPresentationSucceeded(displayRevision: sharpRevision)

        XCTAssertFalse(surface.present(cheap, detailIdentity: identity, detailFactor: 0.5))
        XCTAssertTrue(surface.image === sharp)
        XCTAssertNil(surface.pendingDisplayRevision())
    }

    func testPresentationImageRemainsBoundedAbove100PercentAndKeepsTheSourceVisible() throws {
        let source = CIImage(color: CIColor(red: 0.9, green: 0.2, blue: 0.1, alpha: 1))
            .cropped(to: CGRect(x: 37, y: 19, width: 640, height: 400))
        let destination = CGRect(x: 0, y: 0, width: 320, height: 240)

        for zoom in [1.01, 8.0] {
            var navigation = CanvasNavigation()
            navigation.setZoom(zoom)
            let output = try XCTUnwrap(
                PreviewSurfaceView.Coordinator.presentationImage(
                    source, navigation: navigation, destination: destination
                )
            )

            XCTAssertEqual(output.extent, destination)
            let rendered = try XCTUnwrap(
                RenderEngine.presentationContext.createCGImage(output, from: destination)
            )
            XCTAssertGreaterThan(rendered.width, 0)
            XCTAssertGreaterThan(rendered.height, 0)
            let bytes = try Pixels.bytes(of: rendered)
            let center = ((rendered.height / 2) * rendered.width + rendered.width / 2) * 4
            XCTAssertGreaterThan(bytes[center], 100, "zoom " + String(zoom) + " must present source pixels")
        }
    }

    func testInvalidCandidateCannotBlankTheLastConfirmedFrame() throws {
        let surface = PreviewSurface()
        let first = CIImage(color: .red)
        surface.present(first)
        let firstRevision = try XCTUnwrap(surface.pendingDisplayRevision())
        surface.markPresentationSucceeded(displayRevision: firstRevision)

        XCTAssertFalse(surface.present(nil))
        XCTAssertTrue(surface.image === first)
        XCTAssertNil(surface.pendingDisplayRevision())
    }
}

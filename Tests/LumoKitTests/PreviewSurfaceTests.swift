import XCTest
import CoreImage
import CoreGraphics
import MetalKit
import AppKit
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

    /// The required LUMO-312 acceptance test: presentation-only navigation must sample the
    /// retained texture and never fall back to a new Core Image evaluation.
    func testNoCIEvalOnRepaintTest() async throws {
        let surface = PreviewSurface()
        let image = try makeOrientationAsymmetricFixture()
        XCTAssertTrue(surface.present(image))
        _ = try await waitForPresentationTexture(surface)
        let coordinator = PreviewSurfaceView.Coordinator()

        PreviewSurface.resetPresentationCoreImageEvaluationCount()
        var navigation = CanvasNavigation()
        for zoom in [1.0, 1.5, 2.5, 0.75] {
            navigation.setZoom(zoom)
            XCTAssertNotNil(coordinator.renderRetainedTextureForTesting(
                surface: surface, navigation: navigation, destinationSize: CGSize(width: 31, height: 19)
            ))
        }

        XCTAssertEqual(PreviewSurface.presentationCoreImageEvaluationCount, 0,
                       "pan/zoom repainting must not evaluate the Core Image presentation graph")
    }

    /// The required LUMO-312 acceptance test: compare ultrawide, square, and portrait quad output
    /// against the CPU-composited reference, including an orientation-asymmetric fixture and the
    /// letterbox color. The top/bottom assertions make a vertical flip fail loudly.
    func testGeometryGoldenTest() async throws {
        let surface = PreviewSurface()
        let image = try makeOrientationAsymmetricFixture()
        XCTAssertTrue(surface.present(image))
        _ = try await waitForPresentationTexture(surface)
        let coordinator = PreviewSurfaceView.Coordinator()
        let navigation = CanvasNavigation()

        for size in [CGSize(width: 24, height: 8),
                     CGSize(width: 12, height: 12),
                     CGSize(width: 8, height: 24)] {
            let destination = CGRect(origin: .zero, size: size)
            let reference = try XCTUnwrap(
                PreviewSurfaceView.Coordinator.presentationImage(
                    image, navigation: navigation, destination: destination
                )
            )
            let actualTexture = try XCTUnwrap(coordinator.renderRetainedTextureForTesting(
                surface: surface, navigation: navigation, destinationSize: size
            ))
            let actual = try XCTUnwrap(CIImage(
                mtlTexture: actualTexture,
                options: [CIImageOption.colorSpace: WorkingSpace.current.cgColorSpace]
            ))
            let actualBytes = try Pixels.bytes(of: actual)
            let referenceBytes = try Pixels.bytes(of: reference)
            let transform = navigation.transform(imageExtent: image.extent,
                                                  viewportSize: destination.size)
            var worstDelta = 0
            for y in 0..<Int(size.height) {
                for x in 0..<Int(size.width) {
                    // Core Image's CPU compositor blends one edge sample just outside the
                    // transformed image rectangle; the Metal quad has a hard rasterized edge.
                    // Compare the stable interior and assert the sampled border independently.
                    let inside = CGFloat(x) >= ceil(transform.origin.x) + 1 &&
                        CGFloat(x) < floor(transform.origin.x + transform.imageSize.width) - 1 &&
                        CGFloat(y) >= ceil(transform.origin.y) + 1 &&
                        CGFloat(y) < floor(transform.origin.y + transform.imageSize.height) - 1
                    guard inside else { continue }
                    let offset = (y * Int(size.width) + x) * 4
                    for channel in 0..<4 {
                        worstDelta = max(worstDelta,
                                         abs(Int(actualBytes[offset + channel]) -
                                             Int(referenceBytes[offset + channel])))
                    }
                }
            }
            XCTAssertLessThanOrEqual(worstDelta, 1,
                                     "retained quad geometry for \(Int(size.width))x\(Int(size.height))")

            let bytes = try Pixels.bytes(of: actual)
            let width = Int(size.width)
            let height = Int(size.height)
            let border = try XCTUnwrap(windowBackgroundBytes())
            for point in [(0, 0), (width - 1, height - 1)] {
                let offset = (point.1 * width + point.0) * 4
                if isLetterbox(point: point, imageExtent: image.extent, destination: destination) {
                    XCTAssertEqual(Array(bytes[offset..<(offset + 4)]), border,
                                   "letterbox pixel \(point) must equal LumoTheme.windowBackground")
                }
            }

            let bottomPoint = (Int(transform.origin.x + transform.imageSize.width / 2),
                               Int(transform.origin.y + transform.imageSize.height * 0.25))
            let topPoint = (Int(transform.origin.x + transform.imageSize.width / 2),
                            Int(transform.origin.y + transform.imageSize.height * 0.75))
            let bottom = pixel(in: bytes, width: width, at: bottomPoint)
            let top = pixel(in: bytes, width: width, at: topPoint)
            XCTAssertTrue(bottom.0 != top.0 || bottom.1 != top.1 || bottom.2 != top.2,
                          "orientation-asymmetric fixture must not be flattened")
            XCTAssertGreaterThan(bottom.0, top.0,
                                 "the fixture's bottom half must remain the red half after quad mapping")
        }
    }

    /// The required LUMO-312 acceptance test: a settled visible-frame callback is one-shot even
    /// if the surface receives duplicate drawable callbacks for the same revision.
    func testConfirmationOnceTest() {
        let surface = PreviewSurface()
        surface.attachPresentationLifecycle()
        var confirmations: [UInt64] = []
        for revision in UInt64(1)...3 {
            let telemetry = LiveEditTelemetry()
            XCTAssertTrue(surface.present(
                CIImage(color: .red), revision: revision,
                telemetry: telemetry,
                onPresented: { confirmations.append(revision) }
            ))
            XCTAssertFalse(surface.markDrawablePresented(revision: revision, time: 1))
            XCTAssertFalse(surface.markDrawablePresented(revision: revision, time: 1))
        }
        XCTAssertEqual(confirmations, [1, 2, 3])
    }

    /// The required LUMO-312 acceptance test: a simulated display change redraws the latest
    /// retained revision once, without a second publication or visible-frame confirmation.
    func testDisplayChangeTest() async throws {
        let surface = PreviewSurface()
        surface.attachPresentationLifecycle()
        let image = try makeOrientationAsymmetricFixture()
        var presentCount = 0
        var confirmationCount = 0
        let telemetry = LiveEditTelemetry()
        presentCount += 1
        XCTAssertTrue(surface.present(image, revision: 1, telemetry: telemetry,
                                      onPresented: { confirmationCount += 1 }))
        let retainedTexture = try await waitForPresentationTexture(surface)
        let coordinator = PreviewSurfaceView.Coordinator()
        var quadRenderCount = 0
        XCTAssertNotNil(coordinator.renderRetainedTextureForTesting(
            surface: surface, navigation: CanvasNavigation(), destinationSize: CGSize(width: 20, height: 12)
        ))
        quadRenderCount += 1
        XCTAssertFalse(surface.markDrawablePresented(revision: 1, time: 1))
        XCTAssertEqual(confirmationCount, 1)

        coordinator.visibilityDidChange()
        XCTAssertNotNil(coordinator.renderRetainedTextureForTesting(
            surface: surface, navigation: CanvasNavigation(), destinationSize: CGSize(width: 20, height: 12)
        ))
        quadRenderCount += 1
        XCTAssertTrue(surface.presentationTexture === retainedTexture,
                      "display changes must repaint the retained publication")
        XCTAssertEqual(presentCount, 1, "display changes must not publish a new render")
        XCTAssertEqual(quadRenderCount, 2, "display changes must cause one repaint")
        XCTAssertEqual(confirmationCount, 1, "a repaint must not duplicate settled confirmation")
    }

    private func makeOrientationAsymmetricFixture() throws -> CIImage {
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        var pixels = [UInt8](repeating: 0, count: 8 * 4 * 4)
        for y in 0..<4 {
            for x in 0..<8 {
                let offset = (y * 8 + x) * 4
                let isBottom = y < 2
                pixels[offset] = isBottom ? 220 : 25
                pixels[offset + 1] = isBottom ? 40 : 180
                pixels[offset + 2] = isBottom ? 30 : 220
                pixels[offset + 3] = 255
            }
        }
        let provider = CGDataProvider(data: Data(pixels) as CFData)
        let cgImage = try XCTUnwrap(CGImage(
            width: 8, height: 4, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 32,
            space: space,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: try XCTUnwrap(provider), decode: nil, shouldInterpolate: false,
            intent: .defaultIntent
        ))
        return CIImage(cgImage: cgImage)
    }

    private func waitForPresentationTexture(_ surface: PreviewSurface) async throws -> MTLTexture {
        for _ in 0..<200 {
            if let texture = surface.presentationTexture {
                return texture
            }
            try await Task.sleep(nanoseconds: 2_000_000)
        }
        return try XCTUnwrap(surface.presentationTexture,
                             "async presentation texture did not complete")
    }

    private func pixel(in bytes: [UInt8], width: Int, at point: (Int, Int)) -> (UInt8, UInt8, UInt8) {
        let x = min(max(point.0, 0), width - 1)
        let y = min(max(point.1, 0), bytes.count / (width * 4) - 1)
        let offset = (y * width + x) * 4
        return (bytes[offset], bytes[offset + 1], bytes[offset + 2])
    }

    private func isLetterbox(point: (Int, Int), imageExtent: CGRect, destination: CGRect) -> Bool {
        let transform = CanvasNavigation().transform(imageExtent: imageExtent,
                                                       viewportSize: destination.size)
        return CGFloat(point.0) < transform.origin.x ||
            CGFloat(point.0) >= transform.origin.x + transform.imageSize.width ||
            CGFloat(point.1) < transform.origin.y ||
            CGFloat(point.1) >= transform.origin.y + transform.imageSize.height
    }

    private func windowBackgroundBytes() throws -> [UInt8] {
        let color = try XCTUnwrap(NSColor.windowBackgroundColor.usingColorSpace(.deviceRGB))
        return [UInt8((color.redComponent * 255).rounded()),
                UInt8((color.greenComponent * 255).rounded()),
                UInt8((color.blueComponent * 255).rounded()), 255]
    }
}

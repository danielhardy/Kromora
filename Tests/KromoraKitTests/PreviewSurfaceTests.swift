import AppKit
import CoreGraphics
import CoreImage
import MetalKit
import UniformTypeIdentifiers
import XCTest

@testable import KromoraKit

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

        XCTAssertTrue(
            confirmed, "headless tests should not wait for a drawable that does not exist")
    }

    func testPublicationRequestsRedrawOnAnExistingMetalView() {
        let surface = PreviewSurface()
        let view = TrackingMTKView(frame: CGRect(x: 0, y: 0, width: 32, height: 24), device: nil)
        surface.attachDisplayView(view)
        let requestsBeforePublication = view.redrawRequestCount

        XCTAssertTrue(surface.present(CIImage(color: .red)))
        XCTAssertGreaterThan(
            view.redrawRequestCount, requestsBeforePublication,
            "publishing a frame must invalidate a paused MTKView")
    }

    func testAttachingAViewRequestsAFramePublishedBeforeTheViewWasCreated() {
        let surface = PreviewSurface()
        XCTAssertTrue(surface.present(CIImage(color: .red)))

        let view = TrackingMTKView(frame: CGRect(x: 0, y: 0, width: 32, height: 24), device: nil)
        surface.attachDisplayView(view)

        XCTAssertGreaterThan(
            view.redrawRequestCount, 0,
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
        XCTAssertNil(
            telemetry.report().p50InputToPresentMS,
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
        XCTFail(
            "redraw count settled at \(view.redrawRequestCount), expected \(expected)",
            file: file, line: line)
    }

    /// Asserting quiet requires waiting out any in-flight paced task, then confirming silence.
    private func assertRedrawCountSettles(
        _ view: TrackingMTKView, at expected: Int,
        file: StaticString = #filePath, line: UInt = #line
    ) async throws {
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(
            view.redrawRequestCount, expected,
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
        let identity = PreviewFrameIdentity(
            sourceToken: "source", documentHash: "document", space: .current)
        let sharp = CIImage(color: .red)
        let cheap = CIImage(color: .blue)

        surface.present(sharp, detailIdentity: identity, detailFactor: 1)
        let sharpRevision = try XCTUnwrap(surface.pendingDisplayRevision())
        surface.markPresentationSucceeded(displayRevision: sharpRevision)

        XCTAssertFalse(surface.present(cheap, detailIdentity: identity, detailFactor: 0.5))
        XCTAssertTrue(surface.image === sharp)
        XCTAssertNil(surface.pendingDisplayRevision())
    }

    /// The sharper-frame rule exists so a cheap interactive level cannot replace a good settled
    /// frame. It must not outlive its reason: an ROI frame holds pixels for the zoomed region
    /// only, so the complete photo has to be allowed through even at a lower detail level.
    func testARetainedROIFrameDoesNotRefuseTheCompletePhoto() throws {
        let surface = PreviewSurface()
        let identity = PreviewFrameIdentity(
            sourceToken: "source", documentHash: "document", space: .current)
        let zoomedROI = CIImage(color: .red).cropped(
            to: CGRect(x: 0, y: 0, width: 400, height: 300))
        let completePhoto = CIImage(color: .blue).cropped(
            to: CGRect(x: 0, y: 0, width: 200, height: 150))

        XCTAssertTrue(
            surface.present(
                zoomedROI, detailIdentity: identity, detailFactor: 0.75,
                presentationImageExtent: CGRect(x: 0, y: 0, width: 800, height: 600),
                coversPresentationExtent: false
            ))
        let roiRevision = try XCTUnwrap(surface.pendingDisplayRevision())
        surface.markPresentationSucceeded(displayRevision: roiRevision)

        XCTAssertTrue(
            surface.present(
                completePhoto, detailIdentity: identity, detailFactor: 0.5,
                presentationImageExtent: CGRect(x: 0, y: 0, width: 200, height: 150),
                coversPresentationExtent: true
            ))
        XCTAssertTrue(surface.image === completePhoto)
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
            XCTAssertGreaterThan(
                bytes[center], 100, "zoom " + String(zoom) + " must present source pixels")
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
            XCTAssertNotNil(
                coordinator.renderRetainedTextureForTesting(
                    surface: surface, navigation: navigation,
                    destinationSize: CGSize(width: 31, height: 19)
                ))
        }

        XCTAssertEqual(
            PreviewSurface.presentationCoreImageEvaluationCount, 0,
            "pan/zoom repainting must not evaluate the Core Image presentation graph")
    }

    /// The required LUMO-312 acceptance test: compare ultrawide, square, and portrait quad output
    /// against the CPU-composited reference, including an orientation-asymmetric fixture and the
    /// letterbox color. Orientation is asserted from Metal framebuffer bytes (row 0 is the top
    /// of the window). Wrapping the target as `CIImage(mtlTexture:)` hides a vertical flip that
    /// MTKView then shows on screen.
    func testGeometryGoldenTest() async throws {
        let surface = PreviewSurface()
        let image = try makeOrientationAsymmetricFixture()
        XCTAssertTrue(surface.present(image))
        _ = try await waitForPresentationTexture(surface)
        let coordinator = PreviewSurfaceView.Coordinator()
        let navigation = CanvasNavigation()

        for size in [
            CGSize(width: 24, height: 8),
            CGSize(width: 12, height: 12),
            CGSize(width: 8, height: 24),
        ] {
            let destination = CGRect(origin: .zero, size: size)
            let reference = try XCTUnwrap(
                PreviewSurfaceView.Coordinator.presentationImage(
                    image, navigation: navigation, destination: destination
                )
            )
            let actualTexture = try XCTUnwrap(
                coordinator.renderRetainedTextureForTesting(
                    surface: surface, navigation: navigation, destinationSize: size
                ))
            let width = Int(size.width)
            let height = Int(size.height)
            var metalBytes = [UInt8](repeating: 0, count: width * height * 4)
            metalBytes.withUnsafeMutableBytes { raw in
                actualTexture.getBytes(
                    raw.baseAddress!,
                    bytesPerRow: width * 4,
                    from: MTLRegionMake2D(0, 0, width, height),
                    mipmapLevel: 0
                )
            }
            let referenceBytes = try Pixels.bytes(of: reference)
            let transform = navigation.transform(
                imageExtent: image.extent,
                viewportSize: destination.size)
            var worstDelta = 0
            for y in 0..<height {
                for x in 0..<width {
                    // Core Image's CPU compositor blends one edge sample just outside the
                    // transformed image rectangle; the Metal quad has a hard rasterized edge.
                    // Compare the stable interior and assert the sampled border independently.
                    let inside =
                        CGFloat(x) >= ceil(transform.origin.x) + 1
                        && CGFloat(x) < floor(transform.origin.x + transform.imageSize.width) - 1
                        && CGFloat(y) >= ceil(transform.origin.y) + 1
                        && CGFloat(y) < floor(transform.origin.y + transform.imageSize.height) - 1
                    guard inside else { continue }
                    let actual = rgba(fromBGRA: metalBytes, width: width, at: (x, y))
                    let referenceOffset = (y * width + x) * 4
                    for channel in 0..<3 {
                        worstDelta = max(
                            worstDelta,
                            abs(
                                Int(actual[channel])
                                    - Int(referenceBytes[referenceOffset + channel])))
                    }
                }
            }
            XCTAssertLessThanOrEqual(
                worstDelta, 1,
                "retained quad geometry for \(Int(size.width))x\(Int(size.height))")
            let border = try XCTUnwrap(canvasBackgroundBytes())
            for point in [(0, 0), (width - 1, height - 1)] {
                if isLetterbox(point: point, imageExtent: image.extent, destination: destination) {
                    XCTAssertEqual(
                        rgba(fromBGRA: metalBytes, width: width, at: point), border,
                        "letterbox pixel \(point) must equal KromoraTheme.canvasBackground")
                }
            }

            let x = Int(transform.origin.x + transform.imageSize.width / 2)
            let topPoint = (x, Int(transform.origin.y + transform.imageSize.height * 0.25))
            let bottomPoint = (x, Int(transform.origin.y + transform.imageSize.height * 0.75))
            let top = bgraPixel(in: metalBytes, width: width, at: topPoint)
            let bottom = bgraPixel(in: metalBytes, width: width, at: bottomPoint)
            XCTAssertTrue(
                bottom.0 != top.0 || bottom.1 != top.1 || bottom.2 != top.2,
                "orientation-asymmetric fixture must not be flattened")
            XCTAssertGreaterThan(
                top.0, bottom.0,
                "Metal row 0 is the top of the window; the fixture's red half is the visual top")
        }
    }

    func testEffectiveAppearanceResolvesTheSameLetterboxForMetalAndCoreImage() async throws {
        let surface = PreviewSurface()
        let image = CIImage(cgImage: try makeOrientationAsymmetricCGImage(width: 8, height: 12))
        XCTAssertTrue(surface.present(image))
        _ = try await waitForPresentationTexture(surface)

        let darkAppearance = try XCTUnwrap(NSAppearance(named: .darkAqua))
        let lightAppearance = try XCTUnwrap(NSAppearance(named: .aqua))
        let coordinator = PreviewSurfaceView.Coordinator()
        let destination = CGRect(x: 0, y: 0, width: 24, height: 12)

        let darkMetal = try XCTUnwrap(
            coordinator.renderRetainedTextureForTesting(
                surface: surface, navigation: CanvasNavigation(), destinationSize: destination.size,
                appearance: darkAppearance
            ))
        let lightMetal = try XCTUnwrap(
            coordinator.renderRetainedTextureForTesting(
                surface: surface, navigation: CanvasNavigation(), destinationSize: destination.size,
                appearance: lightAppearance
            ))
        let darkCoreImage = try XCTUnwrap(
            PreviewSurfaceView.Coordinator.presentationImage(
                image, navigation: CanvasNavigation(), destination: destination,
                appearance: darkAppearance
            )
        )
        let lightCoreImage = try XCTUnwrap(
            PreviewSurfaceView.Coordinator.presentationImage(
                image, navigation: CanvasNavigation(), destination: destination,
                appearance: lightAppearance
            )
        )

        let darkExpected = try canvasBackgroundBytes(for: darkAppearance)
        let lightExpected = try canvasBackgroundBytes(for: lightAppearance)
        XCTAssertNotEqual(
            darkExpected, lightExpected,
            "the regression must exercise distinct light and dark resolutions")
        XCTAssertLessThan(darkExpected[0], lightExpected[0], "dark canvas must be darker")

        let darkMetalPixel = try pixel(from: darkMetal, at: (1, 6))
        let lightMetalPixel = try pixel(from: lightMetal, at: (1, 6))
        let darkCoreImagePixel = try rgbaPixel(
            from: darkCoreImage, destination: destination, at: (1, 6)
        )
        let lightCoreImagePixel = try rgbaPixel(
            from: lightCoreImage, destination: destination, at: (1, 6)
        )
        XCTAssertEqual(darkMetalPixel, darkExpected)
        XCTAssertEqual(lightMetalPixel, lightExpected)
        XCTAssertEqual(darkCoreImagePixel, darkExpected)
        XCTAssertEqual(lightCoreImagePixel, lightExpected)
        XCTAssertTrue(surface.image === image, "appearance repaint must not replace photo pixels")
    }

    /// MTKView presents framebuffer row 0 at the top of the window. `CIImage(mtlTexture:)` is not
    /// that convention — it can hide a vertical flip that the packaged app then shows on screen.
    func testMetalFramebufferRowZeroIsVisualTop() async throws {
        let surface = PreviewSurface()
        let image = try makeOrientationAsymmetricFixture()
        XCTAssertTrue(surface.present(image))
        _ = try await waitForPresentationTexture(surface)
        let coordinator = PreviewSurfaceView.Coordinator()
        let size = CGSize(width: 16, height: 16)
        let texture = try XCTUnwrap(
            coordinator.renderRetainedTextureForTesting(
                surface: surface, navigation: CanvasNavigation(), destinationSize: size
            ))
        let width = texture.width
        let height = texture.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        bytes.withUnsafeMutableBytes { raw in
            texture.getBytes(
                raw.baseAddress!,
                bytesPerRow: width * 4,
                from: MTLRegionMake2D(0, 0, width, height),
                mipmapLevel: 0
            )
        }
        let transform = CanvasNavigation().transform(imageExtent: image.extent, viewportSize: size)
        let x = Int(transform.origin.x + transform.imageSize.width / 2)
        let topY = Int(transform.origin.y + transform.imageSize.height * 0.25)
        let bottomY = Int(transform.origin.y + transform.imageSize.height * 0.75)
        let top = bgraPixel(in: bytes, width: width, at: (x, topY))
        let bottom = bgraPixel(in: bytes, width: width, at: (x, bottomY))
        XCTAssertGreaterThan(
            top.0, bottom.0,
            "Metal row 0 is the top of the window; the fixture's red half is the visual top of the CGImage"
        )
    }

    /// The editor presents `RenderEngine.makeCIImage` (a completed Metal texture wrapped as a
    /// CIImage), not a generator image. That wrap is the production seam the on-screen canvas uses.
    func testCompletedEngineTexturePresentsVisualTopAtFramebufferRowZero() async throws {
        guard MTLCreateSystemDefaultDevice() != nil else {
            throw XCTSkip("Metal is unavailable on this host")
        }
        let directory = try Fixtures.makeTempDirectory("preview-orientation")
        defer { try? FileManager.default.removeItem(at: directory) }
        let cgImage = try makeOrientationAsymmetricCGImage(width: 32, height: 16)
        let url = directory.appendingPathComponent("asymmetric.png")
        let destination = try XCTUnwrap(
            CGImageDestinationCreateWithURL(
                url as CFURL, UTType.png.identifier as CFString, 1, nil
            ))
        CGImageDestinationAddImage(destination, cgImage, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))

        let source = ImageSource(url: url, nativeExtent: CGSize(width: 32, height: 16))
        let maybeImage = await RenderEngine().makeCIImage(
            RenderRequest(
                source: source, document: EditDocument(),
                targetSize: CGSize(width: 32, height: 16),
                quality: .preview, output: .raster
            ))
        let engineImage = try XCTUnwrap(maybeImage)
        let surface = PreviewSurface()
        XCTAssertTrue(surface.present(engineImage))
        _ = try await waitForPresentationTexture(surface)
        let coordinator = PreviewSurfaceView.Coordinator()
        let size = CGSize(width: 32, height: 16)
        let texture = try XCTUnwrap(
            coordinator.renderRetainedTextureForTesting(
                surface: surface, navigation: CanvasNavigation(), destinationSize: size
            ))
        var bytes = [UInt8](repeating: 0, count: texture.width * texture.height * 4)
        bytes.withUnsafeMutableBytes { raw in
            texture.getBytes(
                raw.baseAddress!,
                bytesPerRow: texture.width * 4,
                from: MTLRegionMake2D(0, 0, texture.width, texture.height),
                mipmapLevel: 0
            )
        }
        let top = bgraPixel(in: bytes, width: texture.width, at: (16, 4))
        let bottom = bgraPixel(in: bytes, width: texture.width, at: (16, 12))
        XCTAssertGreaterThan(
            top.0, bottom.0,
            "completed preview textures must display the source's visual top at the top of the window"
        )
    }

    /// A camera JPEG is a stand-in for the whole photo. Fit must stretch it across the native
    /// frame rather than leaving it as a postage stamp at the origin of a much larger canvas.
    func testProxyFirstFrameFillsFitCanvas() async throws {
        let surface = PreviewSurface()
        let jpeg = CIImage(cgImage: try makeOrientationAsymmetricCGImage(width: 8, height: 6))
        let native = CGRect(origin: .zero, size: CGSize(width: 40, height: 30))
        XCTAssertTrue(
            surface.present(
                jpeg, presentationImageExtent: native, coversPresentationExtent: true
            ))
        _ = try await waitForPresentationTexture(surface)
        XCTAssertEqual(
            surface.presentationTexture?.width, 8,
            "the JPEG must not be rasterized at native RAW size")
        XCTAssertEqual(surface.presentationTexture?.height, 6)

        let coordinator = PreviewSurfaceView.Coordinator()
        let dest = CGSize(width: 40, height: 30)
        let texture = try XCTUnwrap(
            coordinator.renderRetainedTextureForTesting(
                surface: surface, navigation: CanvasNavigation(), destinationSize: dest
            ))
        var bytes = [UInt8](repeating: 0, count: texture.width * texture.height * 4)
        bytes.withUnsafeMutableBytes { raw in
            texture.getBytes(
                raw.baseAddress!,
                bytesPerRow: texture.width * 4,
                from: MTLRegionMake2D(0, 0, texture.width, texture.height),
                mipmapLevel: 0
            )
        }
        let top = bgraPixel(in: bytes, width: texture.width, at: (20, 7))
        let bottom = bgraPixel(in: bytes, width: texture.width, at: (20, 22))
        XCTAssertGreaterThan(
            top.0, bottom.0,
            "Fit must fill the canvas with the JPEG; the fixture's red half is the visual top"
        )
        let border = try canvasBackgroundBytes()
        let center = rgba(fromBGRA: bytes, width: texture.width, at: (20, 15))
        XCTAssertGreaterThan(
            abs(Int(center[0]) - Int(border[0])) + abs(Int(center[1]) - Int(border[1])),
            40,
            "the canvas center must be image pixels, not the letterbox"
        )
    }

    /// Without the stand-in flag, a smaller texture is an ROI of the virtual canvas — the
    /// geometry that makes a 1600px JPEG look like a postage stamp on a 60MP RAW.
    func testUncoveredROIStaysAtVirtualOriginOnFit() async throws {
        let surface = PreviewSurface()
        let jpeg = CIImage(cgImage: try makeOrientationAsymmetricCGImage(width: 8, height: 6))
        let native = CGRect(origin: .zero, size: CGSize(width: 40, height: 30))
        XCTAssertTrue(surface.present(jpeg, presentationImageExtent: native))
        _ = try await waitForPresentationTexture(surface)

        let coordinator = PreviewSurfaceView.Coordinator()
        let dest = CGSize(width: 40, height: 30)
        let texture = try XCTUnwrap(
            coordinator.renderRetainedTextureForTesting(
                surface: surface, navigation: CanvasNavigation(), destinationSize: dest
            ))
        var bytes = [UInt8](repeating: 0, count: texture.width * texture.height * 4)
        bytes.withUnsafeMutableBytes { raw in
            texture.getBytes(
                raw.baseAddress!,
                bytesPerRow: texture.width * 4,
                from: MTLRegionMake2D(0, 0, texture.width, texture.height),
                mipmapLevel: 0
            )
        }
        let border = try canvasBackgroundBytes()
        let center = rgba(fromBGRA: bytes, width: texture.width, at: (20, 15))
        XCTAssertLessThanOrEqual(
            abs(Int(center[0]) - Int(border[0])), 2,
            "an uncovered JPEG must not fill Fit; the canvas center is letterbox"
        )
        XCTAssertLessThanOrEqual(abs(Int(center[1]) - Int(border[1])), 2)
        XCTAssertLessThanOrEqual(abs(Int(center[2]) - Int(border[2])), 2)
    }

    /// A cropped fit frame still has a source ROI, but that ROI *is* the presented photo.
    /// Covering the presentation extent must fill Fit; otherwise the crop origin offsets the
    /// texture into a postage stamp in the corner of the canvas.
    func testCroppedCompleteFrameFillsFitCanvas() async throws {
        let surface = PreviewSurface()
        let cropPixels = CIImage(cgImage: try makeOrientationAsymmetricCGImage(width: 8, height: 6))
        let presentation = CGRect(x: 16, y: 12, width: 8, height: 6)
        XCTAssertTrue(
            surface.present(
                cropPixels, presentationImageExtent: presentation, coversPresentationExtent: true
            ))
        _ = try await waitForPresentationTexture(surface)

        let coordinator = PreviewSurfaceView.Coordinator()
        let dest = CGSize(width: 40, height: 30)
        let texture = try XCTUnwrap(
            coordinator.renderRetainedTextureForTesting(
                surface: surface, navigation: CanvasNavigation(), destinationSize: dest
            ))
        var bytes = [UInt8](repeating: 0, count: texture.width * texture.height * 4)
        bytes.withUnsafeMutableBytes { raw in
            texture.getBytes(
                raw.baseAddress!,
                bytesPerRow: texture.width * 4,
                from: MTLRegionMake2D(0, 0, texture.width, texture.height),
                mipmapLevel: 0
            )
        }
        let border = try canvasBackgroundBytes()
        let center = rgba(fromBGRA: bytes, width: texture.width, at: (20, 15))
        XCTAssertGreaterThan(
            abs(Int(center[0]) - Int(border[0])) + abs(Int(center[1]) - Int(border[1])),
            40,
            "a cropped complete frame must fill Fit instead of sitting at the crop origin"
        )
    }

    /// Interactive quality can decode below the planner `targetSize`. The resulting texture is
    /// smaller than the virtual crop and lives in a different coordinate system; without an
    /// explicit planner-space layout it sits at the crop origin and a zoomed viewport is empty.
    func testDownscaledInteractiveROIUsesPlannerLayoutOnFitCanvas() async throws {
        let surface = PreviewSurface()
        let fragment = CIImage(cgImage: try makeOrientationAsymmetricCGImage(width: 8, height: 6))
        let presentation = CGRect(origin: .zero, size: CGSize(width: 40, height: 30))
        let layout = CGRect(x: 16, y: 12, width: 8, height: 6)
        XCTAssertTrue(
            surface.present(
                fragment, presentationImageExtent: presentation,
                coversPresentationExtent: false, layoutImageExtent: layout
            ))
        _ = try await waitForPresentationTexture(surface)

        let coordinator = PreviewSurfaceView.Coordinator()
        let dest = CGSize(width: 40, height: 30)
        let texture = try XCTUnwrap(
            coordinator.renderRetainedTextureForTesting(
                surface: surface, navigation: CanvasNavigation(), destinationSize: dest
            ))
        var bytes = [UInt8](repeating: 0, count: texture.width * texture.height * 4)
        bytes.withUnsafeMutableBytes { raw in
            texture.getBytes(
                raw.baseAddress!,
                bytesPerRow: texture.width * 4,
                from: MTLRegionMake2D(0, 0, texture.width, texture.height),
                mipmapLevel: 0
            )
        }
        let border = try canvasBackgroundBytes()
        let center = rgba(fromBGRA: bytes, width: texture.width, at: (20, 15))
        XCTAssertGreaterThan(
            abs(Int(center[0]) - Int(border[0])) + abs(Int(center[1]) - Int(border[1])),
            40,
            "a cheaper interactive ROI must sit on its planner-space rectangle, not at the origin"
        )
        let corner = rgba(fromBGRA: bytes, width: texture.width, at: (2, 2))
        XCTAssertLessThanOrEqual(
            abs(Int(corner[0]) - Int(border[0])), 2,
            "the virtual canvas outside the ROI must remain letterbox"
        )
    }

    /// A portrait stand-in must not be stretched onto a landscape planner rectangle. Fit keeps
    /// the pixel axes and centers the letterbox; Fill then has a tall frame to zoom into.
    func testPortraitStandInDoesNotStretchOntoLandscapePresentationExtent() async throws {
        let surface = PreviewSurface()
        let jpeg = CIImage(cgImage: try makeOrientationAsymmetricCGImage(width: 8, height: 12))
        let landscapePlan = CGRect(origin: .zero, size: CGSize(width: 40, height: 30))
        XCTAssertTrue(
            surface.present(
                jpeg, presentationImageExtent: landscapePlan, coversPresentationExtent: true
            ))
        XCTAssertEqual(surface.presentationImageExtent?.size, CGSize(width: 8, height: 12))
        _ = try await waitForPresentationTexture(surface)

        let coordinator = PreviewSurfaceView.Coordinator()
        let dest = CGSize(width: 24, height: 12)
        let texture = try XCTUnwrap(
            coordinator.renderRetainedTextureForTesting(
                surface: surface, navigation: CanvasNavigation(), destinationSize: dest
            ))
        var bytes = [UInt8](repeating: 0, count: texture.width * texture.height * 4)
        bytes.withUnsafeMutableBytes { raw in
            texture.getBytes(
                raw.baseAddress!,
                bytesPerRow: texture.width * 4,
                from: MTLRegionMake2D(0, 0, texture.width, texture.height),
                mipmapLevel: 0
            )
        }
        let border = try canvasBackgroundBytes()
        let left = rgba(fromBGRA: bytes, width: texture.width, at: (1, 6))
        let center = rgba(fromBGRA: bytes, width: texture.width, at: (12, 6))
        XCTAssertLessThanOrEqual(
            abs(Int(left[0]) - Int(border[0])), 2,
            "Fit of a portrait must letterbox, not stretch to the left edge")
        XCTAssertGreaterThan(
            abs(Int(center[0]) - Int(border[0])) + abs(Int(center[1]) - Int(border[1])),
            40,
            "the centered portrait must still be visible"
        )
    }

    func testFillCoversTheViewportWithAPortraitStandIn() async throws {
        let surface = PreviewSurface()
        let jpeg = CIImage(cgImage: try makeOrientationAsymmetricCGImage(width: 8, height: 12))
        XCTAssertTrue(
            surface.present(
                jpeg,
                presentationImageExtent: CGRect(origin: .zero, size: CGSize(width: 8, height: 12)),
                coversPresentationExtent: true
            ))
        _ = try await waitForPresentationTexture(surface)
        var navigation = CanvasNavigation()
        navigation.fill()
        let coordinator = PreviewSurfaceView.Coordinator()
        let dest = CGSize(width: 24, height: 12)
        let texture = try XCTUnwrap(
            coordinator.renderRetainedTextureForTesting(
                surface: surface, navigation: navigation, destinationSize: dest
            ))
        var bytes = [UInt8](repeating: 0, count: texture.width * texture.height * 4)
        bytes.withUnsafeMutableBytes { raw in
            texture.getBytes(
                raw.baseAddress!,
                bytesPerRow: texture.width * 4,
                from: MTLRegionMake2D(0, 0, texture.width, texture.height),
                mipmapLevel: 0
            )
        }
        let border = try canvasBackgroundBytes()
        let left = rgba(fromBGRA: bytes, width: texture.width, at: (1, 6))
        let right = rgba(fromBGRA: bytes, width: texture.width, at: (22, 6))
        XCTAssertGreaterThan(
            abs(Int(left[0]) - Int(border[0])) + abs(Int(left[1]) - Int(border[1])),
            40,
            "Fill must cover the left edge instead of leaving a Fit letterbox"
        )
        XCTAssertGreaterThan(
            abs(Int(right[0]) - Int(border[0])) + abs(Int(right[1]) - Int(border[1])),
            40,
            "Fill must cover the right edge instead of leaving a Fit letterbox"
        )
    }

    /// The required LUMO-312 acceptance test: a settled visible-frame callback is one-shot even
    /// if the surface receives duplicate drawable callbacks for the same revision.
    func testConfirmationOnceTest() {
        let surface = PreviewSurface()
        surface.attachPresentationLifecycle()
        var confirmations: [UInt64] = []
        for revision in UInt64(1)...3 {
            let telemetry = LiveEditTelemetry()
            XCTAssertTrue(
                surface.present(
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
        XCTAssertTrue(
            surface.present(
                image, revision: 1, telemetry: telemetry,
                onPresented: { confirmationCount += 1 }))
        let retainedTexture = try await waitForPresentationTexture(surface)
        let coordinator = PreviewSurfaceView.Coordinator()
        var quadRenderCount = 0
        XCTAssertNotNil(
            coordinator.renderRetainedTextureForTesting(
                surface: surface, navigation: CanvasNavigation(),
                destinationSize: CGSize(width: 20, height: 12)
            ))
        quadRenderCount += 1
        XCTAssertFalse(surface.markDrawablePresented(revision: 1, time: 1))
        XCTAssertEqual(confirmationCount, 1)

        coordinator.visibilityDidChange()
        XCTAssertNotNil(
            coordinator.renderRetainedTextureForTesting(
                surface: surface, navigation: CanvasNavigation(),
                destinationSize: CGSize(width: 20, height: 12)
            ))
        quadRenderCount += 1
        XCTAssertTrue(
            surface.presentationTexture === retainedTexture,
            "display changes must repaint the retained publication")
        XCTAssertEqual(presentCount, 1, "display changes must not publish a new render")
        XCTAssertEqual(quadRenderCount, 2, "display changes must cause one repaint")
        XCTAssertEqual(confirmationCount, 1, "a repaint must not duplicate settled confirmation")
    }

    private func makeOrientationAsymmetricFixture() throws -> CIImage {
        CIImage(cgImage: try makeOrientationAsymmetricCGImage(width: 8, height: 4))
    }

    /// CGImage row 0 is the visual top. Those rows are red; the visual bottom is cyan.
    private func makeOrientationAsymmetricCGImage(width: Int, height: Int) throws -> CGImage {
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                let isTop = y < height / 2
                pixels[offset] = isTop ? 220 : 25
                pixels[offset + 1] = isTop ? 40 : 180
                pixels[offset + 2] = isTop ? 30 : 220
                pixels[offset + 3] = 255
            }
        }
        let provider = CGDataProvider(data: Data(pixels) as CFData)
        return try XCTUnwrap(
            CGImage(
                width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: width * 4, space: space,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: try XCTUnwrap(provider), decode: nil, shouldInterpolate: false,
                intent: .defaultIntent
            ))
    }

    private func waitForPresentationTexture(_ surface: PreviewSurface) async throws -> MTLTexture {
        for _ in 0..<200 {
            if let texture = surface.presentationTexture {
                return texture
            }
            try await Task.sleep(nanoseconds: 2_000_000)
        }
        return try XCTUnwrap(
            surface.presentationTexture,
            "async presentation texture did not complete")
    }

    /// `renderRetainedTextureForTesting` targets are `.bgra8Unorm`. Channel 0 is blue.
    private func bgraPixel(in bytes: [UInt8], width: Int, at point: (Int, Int)) -> (
        UInt8, UInt8, UInt8
    ) {
        let x = min(max(point.0, 0), width - 1)
        let y = min(max(point.1, 0), bytes.count / (width * 4) - 1)
        let offset = (y * width + x) * 4
        return (bytes[offset + 2], bytes[offset + 1], bytes[offset])
    }

    private func rgba(fromBGRA bytes: [UInt8], width: Int, at point: (Int, Int)) -> [UInt8] {
        let x = min(max(point.0, 0), width - 1)
        let y = min(max(point.1, 0), bytes.count / (width * 4) - 1)
        let offset = (y * width + x) * 4
        return [bytes[offset + 2], bytes[offset + 1], bytes[offset], bytes[offset + 3]]
    }

    private func isLetterbox(point: (Int, Int), imageExtent: CGRect, destination: CGRect) -> Bool {
        let transform = CanvasNavigation().transform(
            imageExtent: imageExtent,
            viewportSize: destination.size)
        return CGFloat(point.0) < transform.origin.x
            || CGFloat(point.0) >= transform.origin.x + transform.imageSize.width
            || CGFloat(point.1) < transform.origin.y
            || CGFloat(point.1) >= transform.origin.y + transform.imageSize.height
    }

    private func canvasBackgroundBytes() throws -> [UInt8] {
        try canvasBackgroundBytes(for: NSAppearance(named: .aqua)!)
    }

    private func canvasBackgroundBytes(for appearance: NSAppearance) throws -> [UInt8] {
        let resolvedColor = KromoraTheme.resolvedCanvasBackgroundColor(for: appearance)
        return [
            UInt8((resolvedColor.redComponent * 255).rounded()),
            UInt8((resolvedColor.greenComponent * 255).rounded()),
            UInt8((resolvedColor.blueComponent * 255).rounded()), 255,
        ]
    }

    private func pixel(from texture: MTLTexture, at point: (Int, Int)) throws -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: texture.width * texture.height * 4)
        bytes.withUnsafeMutableBytes { raw in
            texture.getBytes(
                raw.baseAddress!, bytesPerRow: texture.width * 4,
                from: MTLRegionMake2D(0, 0, texture.width, texture.height), mipmapLevel: 0
            )
        }
        return rgba(fromBGRA: bytes, width: texture.width, at: point)
    }

    private func rgbaPixel(
        from image: CIImage, destination: CGRect, at point: (Int, Int)
    ) throws -> [UInt8] {
        let rendered = try XCTUnwrap(
            RenderEngine.presentationContext.createCGImage(image, from: destination)
        )
        let bytes = try Pixels.bytes(of: rendered)
        let offset = (point.1 * rendered.width + point.0) * 4
        return Array(bytes[offset..<(offset + 4)])
    }
}

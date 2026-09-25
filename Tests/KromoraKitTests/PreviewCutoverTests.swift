import XCTest
import CoreImage
import CoreGraphics
import AppKit
@testable import KromoraKit

/// Phase 2 Step 5 — the first step a user could see.
///
/// The gate is that the preview reflects **develop + adjustments + intensity**, all three of which
/// were unreachable before: the old path graded a baked `CIImage` with a LUT and nothing else.
///
/// Two kinds of test here, deliberately. The fake engine pins *what was asked for* — which document,
/// which scale, how many renders — without a GPU or a comparison tolerance. The real engine pins that
/// the pixels actually move, because a view model that assembles a perfect request and never renders
/// it would satisfy the first kind entirely.
@MainActor
final class PreviewCutoverTests: TempDirectoryTestCase {

    /// Written per test rather than in `setUp`: `XCTestCase.setUpWithError` is nonisolated, and this
    /// suite is `@MainActor` because the view model is.
    private func makeImageFile() throws -> URL {
        try Fixtures.writeGradientPNG(width: 64, height: 48, named: "shot.png", in: tempDirectory)
    }

    private func makeRealViewModel() -> AppViewModel {
        makeAppViewModel(
            engine: RenderEngine(),
            editStore: makeInMemoryEditStore()
        )
    }

    // MARK: - Waiting

    /// The load and the render are both unstructured tasks, so tests wait on published state rather
    /// than reading it straight after the call.
    private func waitUntil(
        _ description: String,
        timeout: TimeInterval = 5,
        _ condition: @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline {
                throw TestSynchronizationError.timedOut(description, "published state did not settle")
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    /// The renderer is an actor, so conditions about *what it was asked for* are async. Kept
    /// separate from the synchronous published-state wait above rather than making every caller
    /// await its own state.
    private func waitUntil(
        _ description: String,
        timeout: TimeInterval = 5,
        _ condition: @escaping @MainActor () async -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !(await condition()) {
            if Date() > deadline {
                throw TestSynchronizationError.timedOut(description, "the renderer was never asked")
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    private func openImage(_ viewModel: AppViewModel) async throws {
        viewModel.openImage(url: try makeImageFile())
        try await waitUntil("the image to load") { viewModel.sourceImage != nil }
    }

    /// Open a fake-backed image using the renderer's source-preparation milestone. Preview events
    /// remain in the reader so each test can await the exact opening or edited request it asserts.
    private func openImage(
        _ viewModel: AppViewModel, using fake: FakeRenderEngine
    ) async throws -> FakeRenderEventReader {
        let reader = FakeRenderEventReader(await fake.eventStream())
        viewModel.openImage(url: try makeImageFile())
        _ = try await TestSynchronization.nextEvent(from: reader, "source preparation") {
            if case .sourcePreparationCompleted = $0 { return true }
            return false
        } diagnostics: {
            "source preparations=\(await fake.sourcePreparationCount)"
        }
        return reader
    }

    /// Wait for a render request matching `predicate`.
    ///
    /// Polling for "the last request" is not good enough: several renders are in flight at once (the
    /// preview and the side-by-side baseline are separate requests), and an early one can satisfy a
    /// loose condition by accident — which is exactly how the first draft of the A/B test passed
    /// against the *opening* render instead of the one it meant to check.
    private func awaitRequest(
        _ reader: FakeRenderEventReader,
        _ fake: FakeRenderEngine,
        _ description: String,
        timeout: TimeInterval = 5,
        matching predicate: @Sendable @escaping (FakeRenderEngine.Request) -> Bool
    ) async throws -> FakeRenderEngine.Request {
        let event = try await TestSynchronization.nextEvent(
            from: reader, description, timeout: .seconds(timeout), matching: { event in
                if case .previewRequested(let request) = event { return predicate(request) }
                return false
            }, diagnostics: {
                let seen = await fake.previewRequests
                return "preview requests=\(seen.count), revisions=\(await fake.renderRequests.map(\.requestRevision)), seen=\(seen)"
            }
        )
        guard case .previewRequested(let request) = event else {
            throw TestSynchronizationError.streamEnded(description)
        }
        return request
    }

    private func previewBytes(
        _ viewModel: AppViewModel, targetSize: CGSize? = nil
    ) throws -> [UInt8] {
        let image = try XCTUnwrap(viewModel.previewSurface.image)
        guard let targetSize else {
            let cg = try XCTUnwrap(
                RenderEngine.presentationContext.createCGImage(image, from: image.extent.integral)
            )
            return try Pixels.bytes(of: cg)
        }
        let extent = image.extent.integral
        let translated = image.transformed(
            by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY)
        )
        let normalized = translated.transformed(
            by: CGAffineTransform(
                scaleX: targetSize.width / extent.width,
                y: targetSize.height / extent.height
            )
        )
        let cg = try XCTUnwrap(
            RenderEngine.presentationContext.createCGImage(
                normalized,
                from: CGRect(origin: .zero, size: targetSize)
            )
        )
        return try Pixels.bytes(of: cg)
    }

    // MARK: - What the engine is asked for

    /// The whole document reaches the engine — not a LUT and an intensity, the document.
    func testTheDocumentReachesTheEngine() async throws {
        let fake = FakeRenderEngine()
        let viewModel = makeAppViewModel(engine: fake)
        let reader = try await openImage(viewModel, using: fake)

        let first = try await awaitRequest(reader, fake, "the opening render") { _ in true }
        XCTAssertEqual(first.document, EditDocument(), "an unedited image renders the empty document")
        XCTAssertNil(first.lutID)
        XCTAssertEqual(first.space, .current)

        try await waitUntil("the opening preview to settle") {
            viewModel.previewState == .ready
        }

        // The initial source marker is published before the stored-edit lookup completes, but it
        // must not admit a pristine render that is immediately superseded by the stored document.
        let all = await fake.previewRequests
        XCTAssertEqual(all.count, 1, "an open admits exactly one settled preview")
        for request in all {
            guard case .preview(let box) = request.scale else {
                return XCTFail("every on-screen render must use a preview scale, got \(request.scale)")
            }
            XCTAssertEqual(box, CGSize(width: 64, height: 48),
                           "preview planning must respect the native source bounds")
        }
    }

    func testOpeningStoredEditsSpeculatesThenSubmitsTheStoredDocument() async throws {
        let image = try makeImageFile()
        let storedDocument = EditDocument(
            rawDevelop: RAWDevelopSettings(exposure: 0.75),
            adjustments: [.vibrance(amount: 0.4)]
        )
        let store = makeInMemoryEditStore()
        try await store.save(
            storedDocument,
            for: EditSourceReference(assetID: .file(image), url: image)
        )

        let fake = FakeRenderEngine()
        let reader = FakeRenderEventReader(await fake.eventStream())
        let viewModel = makeAppViewModel(engine: fake, editStore: store)
        viewModel.collection.loadFromFolder(tempDirectory)
        await viewModel.collection.scanCompletion()
        let index = try XCTUnwrap(viewModel.collection.items.firstIndex { $0.url == image })

        viewModel.selectCollectionImage(at: index)
        let speculative = try await awaitRequest(reader, fake, "the speculative opening render") { _ in true }
        XCTAssertEqual(speculative.document, EditDocument())

        let stored = try await awaitRequest(reader, fake, "the stored-edit corrective render") { request in
            request.document == storedDocument
        }
        XCTAssertEqual(stored.document, storedDocument)

        try await waitUntil("the stored-edit preview to settle") {
            viewModel.previewState == .ready
        }
        let previewCount = await fake.previewRequests.count
        XCTAssertEqual(previewCount, 2, "stored edits correct the speculative opening preview")
    }

    /// LUMO-317's `submitCorrective` intentionally leaves the speculative predecessor running
    /// instead of cancelling it, so both renders can be observed in order. That predecessor must
    /// not become a permanent lease on the single editor lane once the caller moves on: navigating
    /// away before it finishes must still free the lane for the next photo immediately, not once
    /// the abandoned render happens to finish on its own.
    func testOrphanedSpeculativePredecessorDoesNotBlockTheNextPhoto() async throws {
        let first = try Fixtures.writeGradientPNG(
            width: 16, height: 12, named: "orphan-first.png", in: tempDirectory
        )
        let second = try Fixtures.writeGradientPNG(
            width: 16, height: 12, named: "orphan-second.png", in: tempDirectory
        )
        let storedDocument = EditDocument(
            rawDevelop: RAWDevelopSettings(exposure: 0.75),
            adjustments: [.vibrance(amount: 0.4)]
        )
        let store = makeInMemoryEditStore()
        try await store.save(
            storedDocument,
            for: EditSourceReference(assetID: .file(first), url: first)
        )

        let fake = FakeRenderEngine()
        await fake.gatePreviews()
        let reader = FakeRenderEventReader(await fake.eventStream())
        let viewModel = makeAppViewModel(engine: fake, editStore: store)
        viewModel.collection.loadFromFolder(tempDirectory)
        await viewModel.collection.scanCompletion()
        let firstIndex = try XCTUnwrap(viewModel.collection.items.firstIndex { $0.url == first })
        let secondIndex = try XCTUnwrap(viewModel.collection.items.firstIndex { $0.url == second })

        viewModel.selectCollectionImage(at: firstIndex)
        // The speculative identity render enters the fake and parks there, modeling a real render
        // that is still running when the corrective is submitted behind it.
        _ = try await TestSynchronization.nextEvent(from: reader, "speculative parked") {
            if case .previewRequested(let request) = $0 { return request.document == EditDocument() }
            return false
        } diagnostics: { "" }

        // Give the in-memory store lookup time to resolve and submit the corrective behind it,
        // before the parked speculative render is ever released.
        try await Task.sleep(for: .milliseconds(50))

        // Navigate away before the parked speculative predecessor ever finishes.
        viewModel.selectCollectionImage(at: secondIndex)

        // The second photo's own preview must reach the engine without waiting for the abandoned
        // first-photo render to be released.
        _ = try await TestSynchronization.nextEvent(from: reader, "second photo's opening render") {
            if case .previewRequested(let request) = $0 { return request.source?.backing == .url(second) }
            return false
        } diagnostics: {
            let seen = await fake.previewRequests
            return "preview requests=\(seen.count), seen=\(seen)"
        }

        await fake.releasePreviews()
    }

    /// Navigation changes must remain a display concern while still driving a fresh render when
    /// more source detail is useful. The surface is intentionally asserted too: a request-only
    /// regression can look correct in the coordinator while leaving the visible canvas unchanged.
    func testFitFillAndExplicitZoomPublishNonBlankSurfaceFrames() async throws {
        let fake = FakeRenderEngine()
        let viewModel = makeAppViewModel(engine: fake)
        _ = try await openImage(viewModel, using: fake)
        try await waitUntil("the opening surface") { viewModel.previewSurface.image != nil }

        for action in [
            { viewModel.fitCanvas() },
            { viewModel.fillCanvas() },
            { viewModel.setCanvasZoom(4) },
        ] {
            let before = viewModel.previewSurface.revision
            action()
            try await waitUntil("the navigation render") {
                viewModel.previewSurface.revision > before && viewModel.previewSurface.image != nil
            }
        }

        let requests = await fake.previewRequests
        XCTAssertTrue(
            requests.contains {
                if case .preview(let size) = $0.scale {
                    return size == CGSize(width: 64, height: 48)
                }
                return false
            },
            "explicit zoom must request native detail without exceeding the source bounds"
        )
    }

    func testZoomJustAboveAndFarAbove100PercentUsesNativePreviewAndKeepsSurfaceFrame() async throws {
        let fake = FakeRenderEngine()
        let viewModel = makeAppViewModel(engine: fake)
        _ = try await openImage(viewModel, using: fake)
        try await waitUntil("the opening surface") { viewModel.previewSurface.image != nil }

        for zoom in [1.01, 8.0] {
            let before = viewModel.previewSurface.revision
            viewModel.setCanvasZoom(zoom)
            try await waitUntil("the " + String(zoom) + "x navigation render") {
                viewModel.previewSurface.revision > before && viewModel.previewSurface.image != nil
            }
        }

        let requests = await fake.previewRequests
        XCTAssertTrue(
            requests.contains {
                if case .preview(let size) = $0.scale {
                    return size == CGSize(width: 64, height: 48)
                }
                return false
            },
            "zoom above 100% must use the native source detail rather than a blank oversized target"
        )
    }

    /// Develop, adjustments and intensity each reach the engine as part of the document. This is the
    /// step's gate, asserted at the request level.
    func testDevelopAdjustmentsAndIntensityAllReachTheEngine() async throws {
        let fake = FakeRenderEngine()
        let viewModel = makeAppViewModel(engine: fake)
        let reader = try await openImage(viewModel, using: fake)

        let lut = TestImages.warmLUT()
        viewModel.selectLUT(lut)
        viewModel.updateDocument {
            $0.rawDevelop.exposure = 0.75
            $0.adjustments = [.vibrance(amount: 0.5), .exposure(ev: -0.25)]
            $0.lut.intensity = 0.4
        }

        // Match on the fully edited document, not on one field — several renders are in flight.
        let request = try await awaitRequest(reader, fake, "the fully edited document") {
            $0.document.rawDevelop.exposure == 0.75 && !$0.document.adjustments.isEmpty
        }
        XCTAssertEqual(request.document.rawDevelop.exposure, 0.75, "develop must reach the renderer")
        XCTAssertEqual(request.document.adjustments,
                       [.vibrance(amount: 0.5), .exposure(ev: -0.25)],
                       "adjustments must reach the renderer, in order")
        XCTAssertEqual(request.document.lut.intensity, 0.4, "intensity must reach the renderer")
        XCTAssertEqual(request.lutID, lut.lutID, "the resolved LUT must reach the renderer")
    }

    /// Holding Space asks for the *comparison baseline* — develop kept, look removed (§8.5) — rather
    /// than a differently-decoded image.
    func testShowingOriginalRequestsTheDevelopAppliedBaseline() async throws {
        let fake = FakeRenderEngine()
        let viewModel = makeAppViewModel(engine: fake)
        let reader = try await openImage(viewModel, using: fake)

        viewModel.selectLUT(TestImages.warmLUT())
        viewModel.updateDocument {
            $0.rawDevelop.exposure = 1.25
            $0.adjustments = [.vibrance(amount: 0.6)]
        }
        viewModel.showOriginal(true)

        // The baseline is a *specific* document: develop kept, everything else stripped. Waiting for
        // exactly that avoids matching the opening render, which also has no adjustments.
        let expected = EditDocument(
            rawDevelop: RAWDevelopSettings(exposure: 1.25), adjustments: [], lut: .none
        )
        let request = try await awaitRequest(reader, fake, "the A/B baseline render") {
            $0.document == expected
        }
        XCTAssertEqual(request.document.rawDevelop.exposure, 1.25,
                       "the A/B baseline keeps develop — it is the same negative, without the look")
        XCTAssertTrue(request.document.adjustments.isEmpty, "the baseline drops adjustments")
        XCTAssertNil(request.document.lut.lutID, "the baseline drops the LUT")
    }

    // MARK: - What actually reaches the screen

    /// The gate, at the pixels. Each of the three knobs must visibly move the preview — a request
    /// that is assembled correctly and never rendered would pass every test above.
    func testEachKnobVisiblyChangesThePreview() async throws {
        let viewModel = makeRealViewModel()
        try await openImage(viewModel)
        try await waitUntil("the first preview") { viewModel.previewSurface.image != nil }
        let pixelSize = viewModel.sourceSize
        let plain = try previewBytes(viewModel, targetSize: pixelSize)

        // 1. Adjustments.
        viewModel.updateDocument { $0.adjustments = [.exposure(ev: 1.0)] }
        try await waitUntil("the adjusted preview") {
            (try? self.previewBytes(viewModel, targetSize: pixelSize)) != plain
        }
        let adjusted = try previewBytes(viewModel, targetSize: pixelSize)
        assertPixelsDiffer(adjusted, plain, "an adjustment must change the preview")

        // 2. Develop. (Neutral develop is the plain decode, so this is a real change even for a
        //    standard image: `boostAmount` and friends are RAW-only, but exposure is not.)
        viewModel.updateDocument { $0.adjustments = [] }
        try await waitUntil("the reset preview") {
            guard let current = try? self.previewBytes(viewModel, targetSize: pixelSize),
                let delta = Pixels.worstDelta(current, plain)?.delta
            else { return false }
            return delta <= 48
        }
        assertPixelsEqual(
            try previewBytes(viewModel, targetSize: pixelSize), plain, tolerance: 48,
            "resetting adjustments must restore the source"
        )

        // 3. LUT and intensity.
        let lut = TestImages.warmLUT()
        viewModel.selectLUT(lut)
        try await waitUntil("the graded preview") {
            (try? self.previewBytes(viewModel, targetSize: pixelSize)) != plain
        }
        let graded = try previewBytes(viewModel, targetSize: pixelSize)
        assertPixelsDiffer(graded, plain, "selecting a LUT must change the preview")

        viewModel.setLUTIntensity(0.3)
        try await waitUntil("the weakened preview") {
            (try? self.previewBytes(viewModel, targetSize: pixelSize)) != graded
        }
        let weakened = try previewBytes(viewModel, targetSize: pixelSize)
        assertPixelsDiffer(weakened, graded, "intensity must change the preview")
        assertPixelsDiffer(weakened, plain, "…without collapsing back to ungraded")
    }

    /// **What Step 9 changed on screen**, through the real engine and the real preview property.
    ///
    /// The bug was not that the document held the wrong reference — it held the right one. It was
    /// that resolution missed, so `RenderPipeline` was handed `lut: nil` and rendered the image
    /// ungraded while the sidebar showed nothing selected. Every other Step 9 test drives the fake
    /// and asserts on the *request*; a request carrying the right LUT ID proves nothing about pixels
    /// if resolution hands the engine a nil.
    ///
    /// So this one rasterizes the GPU surface in the test: derive-shaped LUT, real `RenderEngine`,
    /// compare the published surface image
    /// before and after. It needs no RAW — the resolution path does not care what the source is —
    /// which is why it runs on CI too, unlike the derive gate proper.
    func testAFreshDerivePutsAGradedImageOnScreen() async throws {
        let viewModel = makeRealViewModel()
        try await openImage(viewModel)
        try await waitUntil("the first preview") { viewModel.previewSurface.image != nil }
        let ungraded = try previewBytes(viewModel)

        // Built the way DeriveCoordinator builds one, and delivered the way a finished derive
        // delivers it — through `onDerived`, which is the only path that selects a fresh derive.
        let derived = DeriveCoordinator.makeDerivedLUT(
            cube: TestImages.toBlackCube(size: 2), size: 2, name: "shot_recipe_2_Rec709"
        )
        viewModel.derive.onDerived?(derived)

        try await waitUntil("the derived preview") { (try? self.previewBytes(viewModel)) != ungraded }
        assertPixelsDiffer(try previewBytes(viewModel), ungraded,
                           "a finished derive must reach the screen, not leave it ungraded")
        XCTAssertEqual(viewModel.selectedLUT, derived, "…and show as selected in the sidebar")
    }

    /// Holding Space must actually put the ungraded image on screen.
    ///
    /// The fake cannot prove this: the side-by-side baseline issues an identical request, so a
    /// mutation that ignored `isShowingOriginal` entirely still produced a matching request and
    /// survived. What distinguishes them is which surface is published for the main panel, so this
    /// checks the pixels there.
    func testHoldingSpaceShowsTheUngradedImageInTheMainPanel() async throws {
        let viewModel = makeRealViewModel()
        try await openImage(viewModel)
        try await waitUntil("the settled opening preview") {
            viewModel.previewState == .ready && viewModel.previewSurface.image != nil
        }
        let pixelSize = viewModel.sourceSize
        let ungraded = try previewBytes(viewModel, targetSize: pixelSize)

        viewModel.selectLUT(TestImages.warmLUT())
        try await waitUntil("the graded preview") {
            (try? self.previewBytes(viewModel, targetSize: pixelSize)) != ungraded
        }
        let graded = try previewBytes(viewModel, targetSize: pixelSize)
        assertPixelsDiffer(graded, ungraded, "the LUT should be visible before comparing")

        viewModel.showOriginal(true)
        try await waitUntil("the comparison render") {
            (try? self.previewBytes(viewModel, targetSize: pixelSize)) != graded
        }
        assertPixelsEqual(try previewBytes(viewModel, targetSize: pixelSize), ungraded,
                          tolerance: 3,
                          "holding Space must show the image without the look")

        viewModel.showOriginal(false)
        try await waitUntil("the graded preview to return") {
            (try? self.previewBytes(viewModel, targetSize: pixelSize)) != ungraded
        }
        assertPixelsEqual(try previewBytes(viewModel, targetSize: pixelSize), graded, tolerance: 48,
                          "releasing Space must restore the look")
    }

    /// RAW develop reaching the screen, which is the half a standard image cannot exercise —
    /// `CIRAWFilter` is the only thing `rawDevelop` talks to. Skipped without a local RAW.
    func testRAWDevelopReachesThePreview() async throws {
        guard let rawURL = Fixtures.localRAWURL else {
            throw XCTSkip("no local RAW to develop; see Fixtures.localRAWURL")
        }
        guard let filter = CIRAWFilter(imageURL: rawURL), filter.outputImage != nil else {
            throw XCTSkip("current decoder cannot develop \(rawURL.lastPathComponent) through CIRAWFilter")
        }
        let viewModel = makeRealViewModel()
        viewModel.openImage(url: rawURL)
        try await waitUntil("the RAW to load", timeout: 30) { viewModel.sourceImage != nil }
        try await waitUntil("the first preview", timeout: 30) { viewModel.previewSurface.image != nil }
        let neutral = try previewBytes(viewModel)

        viewModel.updateDocument { $0.rawDevelop.exposure = 1.5 }
        try await waitUntil("the developed preview", timeout: 30) {
            (try? self.previewBytes(viewModel)) != neutral
        }
        assertPixelsDiffer(try previewBytes(viewModel), neutral,
                           "rawDevelop must reach CIRAWFilter through the preview path")
    }

    // MARK: - The shims still hold
    //
    // `processedImage` is gone — Step 6 deleted it along with the old export path. The test that
    // pinned its behaviour lived here and went with it; `ExportCutoverTests` is what replaces it.


    /// Views read `selectedLUT` and `lutIntensity`; both are now computed off the document. If they
    /// stopped tracking it the toolbar and sidebar would show stale state.
    func testTheShimsTrackTheDocument() async throws {
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())
        XCTAssertNil(viewModel.selectedLUT)
        XCTAssertEqual(viewModel.lutIntensity, 1.0)

        viewModel.setLUTIntensity(0.35)
        XCTAssertEqual(viewModel.lutIntensity, 0.35)
        XCTAssertEqual(viewModel.document.lut.intensity, 0.35)

        // Built the way `DeriveCoordinator` builds one, not with a hand-rolled `CubeLUT`. The
        // hand-rolled version differed from production in exactly the field this line reads —
        // `lutID` — which is why this assertion was green while a fresh derive resolved to nothing.
        let lut = DeriveCoordinator.makeDerivedLUT(
            cube: TestImages.toBlackCube(size: 2), size: 2, name: "shot_recipe_2_Rec709"
        )
        viewModel.selectLUT(lut)
        XCTAssertEqual(viewModel.selectedLUT, lut, "an unsaved derived LUT must still resolve")
        XCTAssertEqual(viewModel.document.lut.lutID, lut.lutID)

        viewModel.selectLUT(nil)
        XCTAssertNil(viewModel.selectedLUT)
        XCTAssertNil(viewModel.document.lut.lutID)
        XCTAssertEqual(viewModel.lutIntensity, 0.35, "clearing the LUT keeps the chosen strength")
    }

    /// A file-backed LUT resolves out of the library by ID, and keeps resolving after a rescan —
    /// the property `LUTID` exists to guarantee (§4.3), now exercised through the view model.
    func testAFileBackedLUTResolvesAndSurvivesARescan() async throws {
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())
        try Fixtures.writeCube(Fixtures.identityCubeText(size: 4), named: "Look.cube", in: tempDirectory)
        viewModel.library.scan(tempDirectory)
        try await waitUntil("the library scan") { !viewModel.library.isScanning }

        let lut = try XCTUnwrap(viewModel.library.allLUTs.first)
        viewModel.selectLUT(lut)
        XCTAssertEqual(viewModel.selectedLUT, lut)

        // What saving a derived LUT does: a new file lands and the library rescans.
        try Fixtures.writeCube(Fixtures.identityCubeText(size: 4), named: "Another.cube", in: tempDirectory)
        viewModel.library.scan(tempDirectory)
        try await waitUntil("the rescan") { !viewModel.library.isScanning }

        XCTAssertEqual(viewModel.library.allLUTs.count, 2)
        XCTAssertEqual(viewModel.selectedLUT, lut, "the selection must survive a library rescan")
    }

    /// End to end: adding a smart-mask layer must not hold the canvas hostage while Vision runs.
    /// The editor's first request for the masked document skips semantic resolution and the second
    /// refines it, and both describe the same document.
    func testAddingASmartMaskPublishesABaseFrameThenRefinesIt() async throws {
        let fake = FakeRenderEngine()
        let viewModel = makeAppViewModel(engine: fake)
        _ = try await openImage(viewModel, using: fake)
        try await waitUntil("the opening preview to settle") { viewModel.previewState == .ready }
        let opening = await fake.renderRequests.count

        viewModel.updateDocument {
            $0.localAdjustments = [LocalAdjustmentLayer(
                components: [MaskComponent(
                    source: .semantic(SemanticMaskDefinition(target: .subject))
                )],
                adjustments: LocalAdjustments(exposure: 0.8)
            )]
        }
        try await waitUntil("both masked frames") {
            await fake.renderRequests.count >= opening + 2
        }

        let masked = await fake.renderRequests.dropFirst(opening)
        XCTAssertEqual(masked.count, 2, "a masked edit publishes a base frame and one refinement")
        let base = try XCTUnwrap(masked.first)
        let refined = try XCTUnwrap(masked.last)
        XCTAssertEqual(base.maskResolution, .deferSemantic)
        XCTAssertEqual(refined.maskResolution, .resolved)
        XCTAssertEqual(base.document, refined.document,
                       "the refinement refines the document the base frame showed")
        XCTAssertTrue(base.document.hasSemanticMasks)

        // The opening render of an unmasked document, and every render before it, stays exact.
        let openingRequests = await fake.renderRequests.prefix(opening)
        XCTAssertTrue(openingRequests.allSatisfy { $0.maskResolution == .resolved },
                      "a document without semantic masks has nothing to defer")

        try await waitUntil("the refined preview to settle") { viewModel.previewState == .ready }
        XCTAssertEqual(viewModel.document.localAdjustments.count, 1)
    }

    /// Everything that is not the on-screen preview keeps the single exact path: an edited
    /// thumbnail, an export and a histogram must never be built from a partially resolved mask.
    func testOnlyTheVisiblePreviewTakesTheProgressivePath() async throws {
        let fake = FakeRenderEngine()
        let viewModel = makeAppViewModel(engine: fake)
        _ = try await openImage(viewModel, using: fake)
        try await waitUntil("the opening preview to settle") { viewModel.previewState == .ready }

        viewModel.updateDocument {
            $0.localAdjustments = [LocalAdjustmentLayer(
                components: [MaskComponent(
                    source: .semantic(SemanticMaskDefinition(target: .subject))
                )],
                adjustments: LocalAdjustments(exposure: 0.8)
            )]
        }
        try await waitUntil("the refined frame") {
            await fake.renderRequests.contains {
                $0.document.hasSemanticMasks && $0.maskResolution == .resolved
            }
        }

        let deferred = await fake.renderRequests.filter { $0.maskResolution == .deferSemantic }
        XCTAssertTrue(deferred.allSatisfy { $0.quality == .preview || $0.quality == .interactive },
                      "only visible preview tiers may defer semantic masks, got \(deferred.map(\.quality))")
        XCTAssertTrue(deferred.allSatisfy { $0.output == .raster && $0.exportOptions == nil },
                      "an encoded or export request must never defer semantic masks")
        let thumbnails = await fake.thumbnailRequests
        XCTAssertTrue(thumbnails.allSatisfy { $0.maskResolution == .resolved },
                      "browsing thumbnails stay on the exact path")
    }

}

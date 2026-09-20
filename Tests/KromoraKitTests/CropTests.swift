import CoreGraphics
import CoreImage
import SwiftUI
import XCTest

@testable import KromoraKit

final class CropModelTests: XCTestCase {
    func testCommonCropAspectRatiosHaveClearCentralizedLabels() {
        XCTAssertEqual(
            CropAspectRatio.allCases.map(\.label),
            ["Original", "Freeform", "1:1", "16:9", "4:5", "5:7", "4:3", "3:5", "3:2", "Custom"])
    }

    func testOrientationLabelsMatchTheNormalizedFrameRatio() throws {
        let imageSize = CGSize(width: 1_000, height: 1_000)
        let expected: [(CropAspectRatio, String, String, CGFloat, CGFloat)] = [
            (.sixteenToNine, "16:9 Landscape", "9:16 Portrait", 16.0 / 9.0, 9.0 / 16.0),
            (.fourToThree, "4:3 Landscape", "3:4 Portrait", 4.0 / 3.0, 3.0 / 4.0),
            (.threeToTwo, "3:2 Landscape", "2:3 Portrait", 3.0 / 2.0, 2.0 / 3.0),
            (.fiveToSeven, "7:5 Landscape", "5:7 Portrait", 7.0 / 5.0, 5.0 / 7.0),
            (.fourToFive, "5:4 Landscape", "4:5 Portrait", 5.0 / 4.0, 4.0 / 5.0),
            (.threeToFive, "5:3 Landscape", "3:5 Portrait", 5.0 / 3.0, 3.0 / 5.0),
        ]

        for (ratio, landscapeLabel, portraitLabel, landscapeValue, portraitValue) in expected {
            XCTAssertEqual(ratio.selectionLabel(for: .landscape), landscapeLabel)
            XCTAssertEqual(ratio.selectionLabel(for: .portrait), portraitLabel)
            XCTAssertEqual(
                landscapeLabel, "\(ratio.shapeLabel(for: .landscape)) Landscape")
            XCTAssertEqual(
                portraitLabel, "\(ratio.shapeLabel(for: .portrait)) Portrait")
            XCTAssertEqual(
                try XCTUnwrap(ratio.normalizedRatio(for: imageSize, orientation: .landscape)),
                landscapeValue, accuracy: 0.000001)
            XCTAssertEqual(
                try XCTUnwrap(ratio.normalizedRatio(for: imageSize, orientation: .portrait)),
                portraitValue, accuracy: 0.000001)
        }
    }

    func testPresetSelectionPreservesCenterAndAdaptsToImageOrientation() throws {
        let sourceRect = CGRect(x: 0.1, y: 0.2, width: 0.6, height: 0.5)
        let landscape = CropOverlayInteraction.applying(
            .threeToTwo, to: sourceRect, imageSize: CGSize(width: 400, height: 200)
        )
        let portrait = CropOverlayInteraction.applying(
            .threeToTwo, to: sourceRect, imageSize: CGSize(width: 200, height: 400)
        )

        XCTAssertEqual(landscape.midX, sourceRect.midX, accuracy: 0.000001)
        XCTAssertEqual(landscape.midY, sourceRect.midY, accuracy: 0.000001)
        XCTAssertEqual(landscape.width * 400 / (landscape.height * 200), 1.5, accuracy: 0.000001)
        XCTAssertEqual(portrait.midX, sourceRect.midX, accuracy: 0.000001)
        XCTAssertEqual(portrait.midY, sourceRect.midY, accuracy: 0.000001)
        XCTAssertEqual(
            portrait.width * 200 / (portrait.height * 400), 2.0 / 3.0, accuracy: 0.000001)
        XCTAssertGreaterThanOrEqual(landscape.minX, 0)
        XCTAssertGreaterThanOrEqual(landscape.minY, 0)
        XCTAssertLessThanOrEqual(landscape.maxX, 1)
        XCTAssertLessThanOrEqual(landscape.maxY, 1)
        XCTAssertGreaterThanOrEqual(portrait.minX, 0)
        XCTAssertGreaterThanOrEqual(portrait.minY, 0)
        XCTAssertLessThanOrEqual(portrait.maxX, 1)
        XCTAssertLessThanOrEqual(portrait.maxY, 1)

        let freeform = CropOverlayInteraction.applying(
            .freeform, to: sourceRect, imageSize: CGSize(width: 400, height: 200)
        )
        XCTAssertEqual(freeform, sourceRect)
    }

    func testPresetResizePreservesPixelRatioAndClampsToBounds() {
        let start = CropOverlayInteraction.applying(
            .sixteenToNine, to: CropAdjustments.unitRect,
            imageSize: CGSize(width: 1600, height: 900)
        )
        let resized = CropOverlayInteraction.resized(
            start,
            handle: .bottomTrailing,
            delta: CGSize(width: 10_000, height: 10_000),
            imageRect: CGRect(x: 0, y: 0, width: 800, height: 450),
            aspectRatio: .sixteenToNine,
            imageSize: CGSize(width: 1600, height: 900)
        )

        XCTAssertEqual(
            resized.width * 1600 / (resized.height * 900), 16.0 / 9.0, accuracy: 0.000001)
        XCTAssertGreaterThanOrEqual(resized.minX, 0)
        XCTAssertGreaterThanOrEqual(resized.minY, 0)
        XCTAssertLessThanOrEqual(resized.maxX, 1)
        XCTAssertLessThanOrEqual(resized.maxY, 1)
    }

    func testTopLeftFixedRatioHorizontalInwardDragMovesLeftEdgeRight() {
        let imageSize = CGSize(width: 1600, height: 900)
        let start = CropOverlayInteraction.applying(
            .threeToTwo,
            orientation: .landscape,
            to: CGRect(x: 0.1, y: 0.1, width: 0.7, height: 0.7),
            imageSize: imageSize
        )
        let resized = CropOverlayInteraction.resized(
            start,
            handle: .topLeading,
            delta: CGSize(width: 80, height: 0),
            imageRect: CGRect(x: 0, y: 0, width: 800, height: 450),
            aspectRatio: .threeToTwo,
            orientation: .landscape,
            imageSize: imageSize
        )

        XCTAssertGreaterThan(resized.minX, start.minX)
        XCTAssertLessThan(resized.width, start.width)
        XCTAssertEqual(
            resized.width * imageSize.width / (resized.height * imageSize.height),
            1.5,
            accuracy: 0.000001
        )
    }

    func testFixedRatioOneAxisResizesSymmetricallyFromEveryCorner() {
        let imageSize = CGSize(width: 1600, height: 900)
        let imageRect = CGRect(x: 0, y: 0, width: 800, height: 450)
        let start = CGRect(x: 0.2, y: 0.2, width: 0.5, height: 0.5)

        for handle in CropHandle.allCases {
            let horizontal = CropOverlayInteraction.resized(
                start,
                handle: handle,
                delta: CGSize(
                    width: handle == .topLeading || handle == .bottomLeading ? 40 : -40, height: 0),
                imageRect: imageRect,
                aspectRatio: .threeToTwo,
                orientation: .landscape,
                imageSize: imageSize
            )
            let vertical = CropOverlayInteraction.resized(
                start,
                handle: handle,
                delta: CGSize(
                    width: 0, height: handle == .topLeading || handle == .topTrailing ? 40 : -40),
                imageRect: imageRect,
                aspectRatio: .threeToTwo,
                orientation: .landscape,
                imageSize: imageSize
            )

            XCTAssertEqual(
                horizontal.width * imageSize.width / (horizontal.height * imageSize.height), 1.5,
                accuracy: 0.000001)
            XCTAssertEqual(
                vertical.width * imageSize.width / (vertical.height * imageSize.height), 1.5,
                accuracy: 0.000001)
            XCTAssertGreaterThan(horizontal.width, 0)
            XCTAssertGreaterThan(vertical.height, 0)
        }
    }

    func testDraggingCropAreaTranslatesInNormalizedBottomLeftSpace() {
        let rect = CGRect(x: 0.2, y: 0.25, width: 0.5, height: 0.4)
        let imageRect = CGRect(x: 10, y: 20, width: 800, height: 400)

        let moved = CropOverlayInteraction.translated(
            rect, delta: CGSize(width: 80, height: -40), imageRect: imageRect
        )

        XCTAssertEqual(moved.origin.x, 0.3, accuracy: 0.000001)
        XCTAssertEqual(moved.origin.y, 0.35, accuracy: 0.000001)
        XCTAssertEqual(moved.width, 0.5, accuracy: 0.000001)
        XCTAssertEqual(moved.height, 0.4, accuracy: 0.000001)
    }

    func testDraggingCropAreaClampsTheWholeFrameToImageBounds() {
        let rect = CGRect(x: 0.2, y: 0.25, width: 0.5, height: 0.4)
        let imageRect = CGRect(x: 0, y: 0, width: 100, height: 100)

        let moved = CropOverlayInteraction.translated(
            rect, delta: CGSize(width: 100, height: 100), imageRect: imageRect
        )

        XCTAssertEqual(moved, rect.offsetBy(dx: 0.3, dy: -0.25))
    }

    func testDraggingCropAreaKeepsNormalizedMovementStableAcrossCanvasScales() {
        let rect = CGRect(x: 0.15, y: 0.2, width: 0.6, height: 0.5)
        let fitImageRect = CGRect(x: 20, y: 10, width: 800, height: 600)
        let zoomedImageRect = CGRect(x: -380, y: -290, width: 1_600, height: 1_200)

        let fitMoved = CropOverlayInteraction.translated(
            rect, delta: CGSize(width: 80, height: -60), imageRect: fitImageRect
        )
        let zoomedMoved = CropOverlayInteraction.translated(
            rect, delta: CGSize(width: 160, height: -120), imageRect: zoomedImageRect
        )

        XCTAssertEqual(fitMoved.origin.x, zoomedMoved.origin.x, accuracy: 0.000001)
        XCTAssertEqual(fitMoved.origin.y, zoomedMoved.origin.y, accuracy: 0.000001)
        XCTAssertEqual(fitMoved.size.width, rect.size.width, accuracy: 0.000001)
        XCTAssertEqual(fitMoved.size.height, rect.size.height, accuracy: 0.000001)
        XCTAssertEqual(zoomedMoved.size.width, rect.size.width, accuracy: 0.000001)
        XCTAssertEqual(zoomedMoved.size.height, rect.size.height, accuracy: 0.000001)
    }

    func testDraggingCropAreaPreservesFixedFrameSize() {
        let rect = CGRect(x: 0.2, y: 0.25, width: 0.5, height: 0.4)
        let moved = CropOverlayInteraction.translated(
            rect, delta: CGSize(width: -30, height: 55),
            imageRect: CGRect(x: 0, y: 0, width: 600, height: 400)
        )

        XCTAssertEqual(moved.size, rect.size)
        XCTAssertGreaterThanOrEqual(moved.minX, 0)
        XCTAssertGreaterThanOrEqual(moved.minY, 0)
        XCTAssertLessThanOrEqual(moved.maxX, 1)
        XCTAssertLessThanOrEqual(moved.maxY, 1)
    }

    func testExplicitPortraitAndLandscapeRatiosIgnoreSourceOrientationAndPersist() throws {
        let imageSize = CGSize(width: 400, height: 800)
        let sourceRect = CGRect(x: 0.3, y: 0.3, width: 0.4, height: 0.4)
        let landscape = CropOverlayInteraction.applying(
            .threeToTwo, orientation: .landscape, to: sourceRect, imageSize: imageSize
        )
        let portrait = CropOverlayInteraction.applying(
            .threeToTwo, orientation: .portrait, to: sourceRect, imageSize: imageSize
        )

        XCTAssertEqual(
            landscape.width * imageSize.width / (landscape.height * imageSize.height), 1.5,
            accuracy: 0.000001)
        XCTAssertEqual(
            portrait.width * imageSize.width / (portrait.height * imageSize.height), 2.0 / 3.0,
            accuracy: 0.000001)
        XCTAssertEqual(landscape.midX, sourceRect.midX, accuracy: 0.000001)
        XCTAssertEqual(portrait.midY, sourceRect.midY, accuracy: 0.000001)

        let crop = CropAdjustments(
            normalizedRect: portrait,
            aspectRatio: .threeToTwo,
            orientation: .portrait
        )
        let restored = try JSONDecoder().decode(
            CropAdjustments.self, from: JSONEncoder().encode(crop)
        )
        XCTAssertEqual(restored, crop)
        XCTAssertEqual(restored.orientation, .portrait)
    }

    func testCropIsNormalizedBoundedAndCodable() throws {
        let crop = CropAdjustments(normalizedRect: CGRect(x: -0.1, y: 0.2, width: 0.8, height: 0.9))
        let rect = try XCTUnwrap(crop.normalizedRect)
        XCTAssertEqual(rect.minX, 0, accuracy: 0.000001)
        XCTAssertEqual(rect.minY, 0.2, accuracy: 0.000001)
        XCTAssertEqual(rect.width, 0.7, accuracy: 0.000001)
        XCTAssertEqual(rect.height, 0.8, accuracy: 0.000001)
        XCTAssertFalse(crop.isIdentity)

        let document = EditDocument(crop: crop)
        let data = try JSONEncoder().encode(document)
        XCTAssertEqual(try JSONDecoder().decode(EditDocument.self, from: data), document)
    }

    func testMissingCropFieldKeepsLegacyDocumentsNeutral() throws {
        let document = try JSONDecoder().decode(
            EditDocument.self, from: Data("{\"version\":1}".utf8))
        XCTAssertEqual(document.crop, .neutral)
        XCTAssertTrue(document.isIdentity)
    }

    func testCropIsCopiedSelectivelyAndComparisonKeepsItsFrame() {
        let crop = CropAdjustments(
            normalizedRect: CGRect(x: 0.1, y: 0.2, width: 0.7, height: 0.6),
            aspectRatio: .fourToThree
        )
        let document = EditDocument(crop: crop, adjustments: [.exposure(ev: 0.5)])
        let clipboard = EditClipboardPayload(document: document)
        XCTAssertEqual(clipboard.crop.normalizedRect, crop.normalizedRect)
        XCTAssertEqual(clipboard.crop.aspectRatio, .fourToThree)

        let result = clipboard.applying(
            to: EditDocument(), destinationIsRAW: false, categories: [.crop]
        )
        XCTAssertEqual(result.crop, crop)
        XCTAssertEqual(document.comparisonBaseline.crop, crop)
        XCTAssertTrue(document.hasVisibleLookEdits)
    }

    func testPresetSelectionIsPersistedAsPartOfTheCropEdit() throws {
        let crop = CropAdjustments(
            normalizedRect: CGRect(x: 0, y: 0.125, width: 1, height: 0.75),
            aspectRatio: .sixteenToNine
        )
        let document = EditDocument(crop: crop)
        let restored = try JSONDecoder().decode(
            EditDocument.self, from: JSONEncoder().encode(document)
        )
        XCTAssertEqual(restored.crop, crop)
        XCTAssertFalse(restored.isIdentity)
    }

    func testCropClampingRejectsDegenerateInput() {
        XCTAssertEqual(
            CropAdjustments(normalizedRect: CGRect(x: 0, y: 0, width: 0, height: 1)), .neutral)
        XCTAssertEqual(CropAdjustments(normalizedRect: nil), .neutral)
    }

    func testGeometryDefaultsAndCodableMigrationAreNeutral() throws {
        let legacy = try JSONDecoder().decode(
            CropAdjustments.self,
            from: Data("{\"normalizedRect\":null,\"aspectRatio\":\"Freeform\"}".utf8)
        )
        XCTAssertEqual(legacy, .neutral)

        let crop = CropAdjustments(
            normalizedRect: CGRect(x: 0.1, y: 0.2, width: 0.7, height: 0.6),
            aspectRatio: .fourToFive,
            orientation: .portrait,
            straightenAngle: 18.5,
            flipHorizontal: true,
            flipVertical: true
        )
        XCTAssertEqual(
            try JSONDecoder().decode(CropAdjustments.self, from: JSONEncoder().encode(crop)), crop)
        XCTAssertEqual(CropAdjustments(straightenAngle: 100).straightenAngle, 45)
        XCTAssertEqual(CropAdjustments(straightenAngle: -100).straightenAngle, -45)
    }

    func testPerspectiveDefaultsAreBoundedAndCodable() throws {
        XCTAssertEqual(CropAdjustments().verticalPerspective, 0)
        XCTAssertEqual(CropAdjustments().horizontalPerspective, 0)
        XCTAssertEqual(
            CropAdjustments(verticalPerspective: 2, horizontalPerspective: -2),
            CropAdjustments(
                verticalPerspective: CropAdjustments.maximumPerspective,
                horizontalPerspective: -CropAdjustments.maximumPerspective
            )
        )

        let crop = CropAdjustments(
            normalizedRect: CGRect(x: 0.1, y: 0.2, width: 0.7, height: 0.6),
            verticalPerspective: 0.35,
            horizontalPerspective: -0.2
        )
        XCTAssertEqual(
            try JSONDecoder().decode(CropAdjustments.self, from: JSONEncoder().encode(crop)), crop)
        XCTAssertFalse(crop.isIdentity)
        XCTAssertTrue(crop.hasGeometryTransform)
    }

    func testOriginalAspectIsSourcePixelIdentityWithoutResettingCrop() {
        let crop = CGRect(x: 0.1, y: 0.15, width: 0.6, height: 0.5)
        let original = CropOverlayInteraction.applying(
            .original, to: crop, imageSize: CGSize(width: 400, height: 200))
        XCTAssertEqual(original.midX, crop.midX, accuracy: 0.000001)
        XCTAssertEqual(original.midY, crop.midY, accuracy: 0.000001)
        XCTAssertEqual(
            original.width * 400 / (original.height * 200), 2, accuracy: 0.000001)
    }
}

final class CropPipelineTests: TempDirectoryTestCase {
    private var source: ImageSource!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let url = try Fixtures.writeGradientPNG(
            width: 96, height: 64, named: "crop.png", in: tempDirectory)
        source = ImageSource(url: url, nativeExtent: CGSize(width: 96, height: 64))
    }

    func testNormalizedCropChangesExtentWithoutRasterizingTheGraph() throws {
        let input = CIImage(color: CIColor(red: 1, green: 0, blue: 0)).cropped(
            to: CGRect(x: 10, y: 20, width: 80, height: 40)
        )
        let result = RenderPipeline.applyCrop(
            CropAdjustments(normalizedRect: CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)),
            to: input
        )
        XCTAssertEqual(result.extent, CGRect(x: 30, y: 30, width: 40, height: 20))
    }

    func testPreviewAndFullResolutionExportUseTheSameCropExtentAndPixels() async throws {
        let engine = RenderEngine()
        let document = EditDocument(
            effects: EffectsAdjustments(vignette: VignetteAdjustments(amount: 45)),
            crop: CropAdjustments(
                normalizedRect: CGRect(x: 0.25, y: 0.125, width: 0.5, height: 0.75),
                aspectRatio: .square
            )
        )
        let rendered = await engine.makeCGImage(
            source: source, document: document, lut: nil, scale: .full, space: .current
        )
        let preview: CGImage = try XCTUnwrap(rendered)
        let exported = try await engine.encode(
            source: source, document: document, lut: nil, scale: .full,
            format: .png, quality: 1, space: .current
        )
        let decoded = try Pixels.decode(exported)

        XCTAssertEqual(preview.width, 48)
        XCTAssertEqual(preview.height, 48)
        XCTAssertEqual(decoded.width, preview.width)
        XCTAssertEqual(decoded.height, preview.height)
        assertPixelsEqual(
            try Pixels.bytes(of: preview), try Pixels.bytes(of: decoded),
            "preview and export must retain crop and post-crop effects identically")
    }

    func testPresetCropPreviewAndFullResolutionExportHaveTheSameExtent() async throws {
        let cropRect = CropOverlayInteraction.applying(
            .sixteenToNine, to: CropAdjustments.unitRect, imageSize: CGSize(width: 96, height: 64)
        )
        let document = EditDocument(
            crop: CropAdjustments(
                normalizedRect: cropRect, aspectRatio: .sixteenToNine
            ))
        let engine = RenderEngine()
        let rendered = await engine.makeCGImage(
            source: source, document: document, lut: nil, scale: .full, space: .current
        )
        let preview = try XCTUnwrap(rendered)
        let exported = try await engine.encode(
            source: source, document: document, lut: nil, scale: .full,
            format: .png, quality: 1, space: .current
        )
        let decoded = try Pixels.decode(exported)

        XCTAssertEqual(preview.width, 96)
        XCTAssertEqual(preview.height, 54)
        XCTAssertEqual(decoded.width, preview.width)
        XCTAssertEqual(decoded.height, preview.height)
        assertPixelsEqual(
            try Pixels.bytes(of: preview), try Pixels.bytes(of: decoded),
            "preset preview and export must retain the same crop extent")
    }

    func testFlipAndStraightenComposeBeforeCrop() async throws {
        let engine = RenderEngine()
        let document = EditDocument(crop: CropAdjustments(
            normalizedRect: CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8),
            straightenAngle: 12,
            flipHorizontal: true
        ))
        let rendered = await engine.makeCGImage(
            source: source, document: document, lut: nil, scale: .full, space: .current)
        let image = try XCTUnwrap(rendered)
        XCTAssertGreaterThan(image.width, 0)
        XCTAssertGreaterThan(image.height, 0)
        XCTAssertNotEqual(image.width, 96, "straighten should change the pre-crop geometry")
    }

    func testPerspectivePreviewAndExportHaveTheSameComposition() async throws {
        let engine = RenderEngine()
        let document = EditDocument(crop: CropAdjustments(
            normalizedRect: CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8),
            straightenAngle: 7,
            flipHorizontal: true,
            verticalPerspective: 0.35,
            horizontalPerspective: -0.25
        ))
        let renderedImage = await engine.makeCGImage(
            source: source, document: document, lut: nil, scale: .full, space: .current
        )
        let rendered = try XCTUnwrap(renderedImage)
        let exported = try await engine.encode(
            source: source, document: document, lut: nil, scale: .full,
            format: .png, quality: 1, space: .current
        )
        let decoded = try Pixels.decode(exported)
        XCTAssertGreaterThan(rendered.width, 0)
        XCTAssertGreaterThan(rendered.height, 0)
        XCTAssertEqual(decoded.width, rendered.width)
        XCTAssertEqual(decoded.height, rendered.height)
        assertPixelsEqual(
            try Pixels.bytes(of: rendered), try Pixels.bytes(of: decoded),
            "perspective preview and export must share the geometry pipeline")
    }
}

@MainActor
final class CropWorkflowTests: TempDirectoryTestCase {
    private enum WaitError: Error {
        case timedOut
    }

    private func waitUntil(_ description: String, _ condition: @MainActor () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(5)
        while !condition() {
            if Date() > deadline { return XCTFail("timed out waiting for \(description)") }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    /// Wait for the request that represents a state transition, rather than merely waiting for the
    /// log to grow. A cancelled or superseded preview may still reach the fake engine after the
    /// caller has submitted a newer request, so a count increase alone does not identify which
    /// transition was captured.
    private func waitForPreviewRequest(
        after count: Int = 0,
        matching description: String,
        on engine: FakeRenderEngine,
        predicate: @MainActor (FakeRenderEngine.Request) -> Bool
    ) async throws -> FakeRenderEngine.Request {
        let deadline = Date().addingTimeInterval(5)
        while true {
            let requests = await engine.previewRequests
            if let request = requests.dropFirst(count).first(where: predicate) {
                return request
            }
            if Date() > deadline {
                XCTFail("timed out waiting for \(description)")
                throw WaitError.timedOut
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    func testDraftIsTransientCancelIsFreeAndCommitIsUndoable() async throws {
        let url = try Fixtures.writeGradientPNG(
            width: 32, height: 24, named: "workflow.png", in: tempDirectory)
        let viewModel = makeAppViewModel(
            engine: FakeRenderEngine(),
            editStore: makeInMemoryEditStore()
        )
        viewModel.openImage(url: url)
        try await waitUntil("the source image") { viewModel.sourceImage != nil }

        viewModel.beginCrop()
        viewModel.updateCropDraft(CGRect(x: 0.1, y: 0.2, width: 0.7, height: 0.6))
        XCTAssertTrue(viewModel.isCropToolActive)
        XCTAssertTrue(viewModel.document.crop.isIdentity, "a draft must not change the document")
        viewModel.cancelCrop()
        XCTAssertFalse(viewModel.isCropToolActive)
        XCTAssertTrue(viewModel.document.crop.isIdentity)
        XCTAssertEqual(viewModel.undoDepth, 0)

        viewModel.beginCrop()
        viewModel.updateCropDraft(CGRect(x: 0.1, y: 0.2, width: 0.7, height: 0.6))
        viewModel.commitCrop()
        let committed = CropAdjustments(
            normalizedRect: CGRect(x: 0.1, y: 0.2, width: 0.7, height: 0.6))
        XCTAssertEqual(viewModel.document.crop, committed)
        XCTAssertEqual(viewModel.undoDepth, 1)

        viewModel.undo()
        XCTAssertTrue(viewModel.document.crop.isIdentity)
        viewModel.redo()
        XCTAssertEqual(viewModel.document.crop, committed)
    }

    func testCropModeOwnsAndRestoresEditChromeState() {
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())
        viewModel.sourceImage = CIImage(color: .gray).cropped(
            to: CGRect(x: 0, y: 0, width: 100, height: 80)
        )
        viewModel.inspectorState.isPresented = false
        viewModel.inspectorState.tab = .effects
        viewModel.isSourceBrowserPresented = true

        viewModel.beginCrop()

        XCTAssertTrue(viewModel.isCropToolActive)
        XCTAssertTrue(viewModel.inspectorState.isPresented)
        XCTAssertTrue(viewModel.availableInspectorTabs.isEmpty)
        XCTAssertFalse(viewModel.isSourceBrowserPresented)

        viewModel.cancelCrop()

        XCTAssertFalse(viewModel.isCropToolActive)
        XCTAssertFalse(viewModel.inspectorState.isPresented)
        XCTAssertEqual(viewModel.inspectorState.tab, .effects)
        XCTAssertTrue(viewModel.isSourceBrowserPresented)
    }

    func testCropToolOpenUnchangedTestRequestsTheFullUncroppedSource() async throws {
        let fake = FakeRenderEngine()
        let viewModel = makeAppViewModel(
            engine: fake,
            editStore: makeInMemoryEditStore()
        )
        let url = try Fixtures.writeGradientPNG(
            width: 32, height: 24, named: "roi-tool.png", in: tempDirectory)
        viewModel.openImage(url: url)
        try await waitUntil("the source image") { viewModel.sourceImage != nil }
        while (await fake.previewRequests).isEmpty {
            try await Task.sleep(for: .milliseconds(10))
        }

        viewModel.beginCrop()
        viewModel.updateCropDraft(CGRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6))
        viewModel.commitCrop()
        while !(await fake.previewRequests).contains(where: { !$0.document.crop.isIdentity }) {
            try await Task.sleep(for: .milliseconds(10))
        }

        let before = await fake.previewRequests.count
        viewModel.beginCrop()
        while !(await fake.previewRequests).dropFirst(before).contains(where: {
            $0.document.crop.isIdentity && $0.sourceROI == nil
        }) {
            try await Task.sleep(for: .milliseconds(10))
        }
        let requests = await fake.previewRequests
        let request = try XCTUnwrap(
            requests.dropFirst(before).first {
                $0.document.crop.isIdentity && $0.sourceROI == nil
            })
        if case .preview(let size) = request.scale {
            XCTAssertEqual(size, CGSize(width: 32, height: 24))
        } else {
            XCTFail("crop-tool-open must remain a preview request")
        }
    }

    func testSelectingPresetStaysDraftUntilApplyAndUndoRedoRestoresTheRatio() async throws {
        let url = try Fixtures.writeGradientPNG(
            width: 32, height: 24, named: "preset-workflow.png", in: tempDirectory)
        let viewModel = makeAppViewModel(
            engine: FakeRenderEngine(),
            editStore: makeInMemoryEditStore()
        )
        viewModel.openImage(url: url)
        try await waitUntil("the source image") { viewModel.sourceImage != nil }

        viewModel.beginCrop()
        let beforeSelection = viewModel.document
        viewModel.selectCropAspectRatio(.sixteenToNine, orientation: .portrait)
        XCTAssertEqual(viewModel.document, beforeSelection, "preset selection must remain a draft")
        XCTAssertEqual(viewModel.cropAspectRatio, .sixteenToNine)
        XCTAssertEqual(viewModel.cropOrientation, .portrait)
        XCTAssertTrue(viewModel.cropDraft != CropAdjustments.unitRect)

        viewModel.commitCrop()
        XCTAssertEqual(viewModel.document.crop.aspectRatio, .sixteenToNine)
        XCTAssertEqual(viewModel.document.crop.orientation, .portrait)
        XCTAssertEqual(viewModel.undoDepth, 1)
        viewModel.undo()
        XCTAssertEqual(viewModel.document.crop, .neutral)
        viewModel.redo()
        XCTAssertEqual(viewModel.document.crop.aspectRatio, .sixteenToNine)
        XCTAssertEqual(viewModel.document.crop.orientation, .portrait)
    }

    func testStraightenAndFlipAreDraftedUntilDoneAndCancelRestoresCommittedGeometry() async throws {
        let url = try Fixtures.writeGradientPNG(
            width: 32, height: 24, named: "geometry-workflow.png", in: tempDirectory)
        let viewModel = makeAppViewModel(
            engine: FakeRenderEngine(), editStore: makeInMemoryEditStore())
        viewModel.openImage(url: url)
        try await waitUntil("the source image") { viewModel.sourceImage != nil }

        viewModel.beginCrop()
        viewModel.setCropStraightenAngle(22.5)
        viewModel.toggleCropFlip(horizontal: true)
        XCTAssertTrue(viewModel.document.crop.isIdentity)
        XCTAssertEqual(viewModel.cropStraightenAngle, 22.5, accuracy: 0.000001)
        XCTAssertTrue(viewModel.cropFlipHorizontal)
        viewModel.cancelCrop()
        XCTAssertTrue(viewModel.document.crop.isIdentity)

        viewModel.beginCrop()
        viewModel.setCropStraightenAngle(-12)
        viewModel.toggleCropFlip(horizontal: false)
        viewModel.commitCrop()
        XCTAssertEqual(viewModel.document.crop.straightenAngle, -12, accuracy: 0.000001)
        XCTAssertTrue(viewModel.document.crop.flipVertical)
        viewModel.undo()
        XCTAssertTrue(viewModel.document.crop.isIdentity)
        viewModel.redo()
        XCTAssertEqual(viewModel.document.crop.straightenAngle, -12, accuracy: 0.000001)
        XCTAssertTrue(viewModel.document.crop.flipVertical)
    }

    func testCropAutoNoOpDoesNotTouchGeometryOrGlobalTone() async throws {
        let url = try Fixtures.writeGradientPNG(
            width: 32, height: 24, named: "auto-no-op.png", in: tempDirectory)
        let viewModel = makeAppViewModel(
            engine: FakeRenderEngine(), editStore: makeInMemoryEditStore())
        viewModel.openImage(url: url)
        try await waitUntil("the source image") { viewModel.sourceImage != nil }

        viewModel.beginCrop()
        let before = viewModel.document
        viewModel.runCropAuto()

        XCTAssertEqual(viewModel.document, before)
        XCTAssertEqual(viewModel.cropStraightenAngle, 0)
        XCTAssertEqual(viewModel.cropVerticalPerspective, 0)
        XCTAssertEqual(viewModel.cropHorizontalPerspective, 0)
        XCTAssertEqual(viewModel.statusMessage, "Auto crop: no reliable horizon detected")
    }

    /// Covers the LUMO-115 fix directly: while Crop is open, the pixels under the full-source
    /// overlay must come from the same adjusted stage with the composition crop stripped, not the
    /// already-cropped committed render. Asserting on the render *request* handed to the engine
    /// (rather than only `document.crop`) is what the issue's verification plan means by testing
    /// geometry/UI behavior instead of only the normalized rectangle.
    func testReenteringCropRequestsTheFullUncroppedStageAndRestoresOnExit() async throws {
        let url = try Fixtures.writeGradientPNG(
            width: 32, height: 24, named: "reentry.png", in: tempDirectory)
        let fake = FakeRenderEngine()
        let viewModel = makeAppViewModel(
            engine: fake,
            editStore: makeInMemoryEditStore()
        )
        viewModel.openImage(url: url)
        try await waitUntil("the source image") { viewModel.sourceImage != nil }

        let committedRect = CGRect(x: 0.1, y: 0.2, width: 0.5, height: 0.4)
        viewModel.beginCrop()
        viewModel.updateCropDraft(committedRect)
        viewModel.commitCrop()
        let committed = CropAdjustments(normalizedRect: committedRect)
        XCTAssertEqual(viewModel.document.crop, committed)

        // Do not take the re-entry baseline while the commit render is still in flight. Otherwise
        // that older request can be captured after `beginCrop()` and satisfy a count-only wait.
        _ = try await waitForPreviewRequest(
            matching: "the committed crop preview", on: fake
        ) { $0.document.crop == committed }

        let requestsBeforeReentry = await fake.previewRequests.count
        viewModel.beginCrop()
        let reentryRequest = try await waitForPreviewRequest(
            after: requestsBeforeReentry,
            matching: "the uncropped re-entry preview",
            on: fake
        ) { $0.document.crop.isIdentity }
        XCTAssertTrue(
            reentryRequest.document.crop.isIdentity,
            "reopening Crop must render the full source stage, not the already-cropped committed frame"
        )
        XCTAssertEqual(
            viewModel.document.crop, committed,
            "the committed document must be untouched while editing")

        let requestsBeforeCancel = await fake.previewRequests.count
        viewModel.cancelCrop()
        let cancelRequest = try await waitForPreviewRequest(
            after: requestsBeforeCancel,
            matching: "the committed cancel preview",
            on: fake
        ) { $0.document.crop == committed }
        XCTAssertEqual(
            cancelRequest.document.crop, committed,
            "Cancel must restore the committed framing under the overlay"
        )
    }

    func testCommittedCropSurvivesRelaunch() async throws {
        let url = try Fixtures.writeGradientPNG(
            width: 32, height: 24, named: "persisted.png", in: tempDirectory)
        let container = makeInMemoryEditContainer()
        let first = makeAppViewModel(
            engine: FakeRenderEngine(), editStore: EditDocumentStore(modelContainer: container)
        )
        first.openImage(url: url)
        try await waitUntil("the first source") { first.sourceImage != nil }
        first.beginCrop()
        first.updateCropDraft(CGRect(x: 0.2, y: 0.1, width: 0.6, height: 0.8))
        first.commitCrop()
        await first.flushPendingWrites()

        let second = makeAppViewModel(
            engine: FakeRenderEngine(), editStore: EditDocumentStore(modelContainer: container)
        )
        second.openImage(url: url)
        try await waitUntil("the restored crop") {
            second.sourceImage != nil
                && second.document.crop
                    == CropAdjustments(
                        normalizedRect: CGRect(x: 0.2, y: 0.1, width: 0.6, height: 0.8)
                    )
        }
    }
}

final class CropOverlayViewTests: XCTestCase {
    private func makeOverlay() -> CropOverlayView {
        CropOverlayView(
            normalizedRect: CGRect(x: 0, y: 0, width: 1, height: 1),
            imageSize: CGSize(width: 400, height: 300),
            aspectRatio: .freeform,
            orientation: .automatic,
            onChange: { _ in }
        )
    }

    // KRMA-387: the top-left handle's hit target must sit inside the crop rect (inset by half
    // the hit-target size), not on the boundary where it can be clipped or covered.
    func testHandleHitPositionsAreInsetFromEveryCorner() {
        let overlay = makeOverlay()
        let rect = CGRect(x: 10, y: 20, width: 200, height: 150)
        let inset = overlay.handleHitTargetSize / 2

        XCTAssertEqual(
            overlay.handleHitPosition(.topLeading, in: rect),
            CGPoint(x: rect.minX + inset, y: rect.minY + inset)
        )
        XCTAssertEqual(
            overlay.handleHitPosition(.topTrailing, in: rect),
            CGPoint(x: rect.maxX - inset, y: rect.minY + inset)
        )
        XCTAssertEqual(
            overlay.handleHitPosition(.bottomLeading, in: rect),
            CGPoint(x: rect.minX + inset, y: rect.maxY - inset)
        )
        XCTAssertEqual(
            overlay.handleHitPosition(.bottomTrailing, in: rect),
            CGPoint(x: rect.maxX - inset, y: rect.maxY - inset)
        )
    }

    // A crop rect smaller than the hit-target size must still produce hit positions within the
    // rect's bounds rather than overshooting past the opposite edge.
    func testHandleHitPositionClampsInsetForTinyCropRects() {
        let overlay = makeOverlay()
        let rect = CGRect(x: 0, y: 0, width: 10, height: 8)

        for handle in CropHandle.allCases {
            let point = overlay.handleHitPosition(handle, in: rect)
            XCTAssertGreaterThanOrEqual(point.x, rect.minX)
            XCTAssertLessThanOrEqual(point.x, rect.maxX)
            XCTAssertGreaterThanOrEqual(point.y, rect.minY)
            XCTAssertLessThanOrEqual(point.y, rect.maxY)
        }
    }

    // A press on the visible top-left handle of a full-image crop must resize, not translate.
    // Translation of a unit crop is clamped, so a stolen move gesture looks like a dead handle.
    func testPressOnTopLeftCornerOfFullImageCropResizesRatherThanMoves() {
        let bounds = CGRect(x: 0, y: 0, width: 800, height: 500)
        XCTAssertEqual(
            CropOverlayInteraction.hit(at: .zero, cropRect: bounds, bounds: bounds),
            .resize(.topLeading)
        )
        XCTAssertEqual(
            CropOverlayInteraction.hit(at: CGPoint(x: 8, y: 6), cropRect: bounds, bounds: bounds),
            .resize(.topLeading)
        )
    }

    func testPressInCropInteriorMoves() {
        let bounds = CGRect(x: 0, y: 0, width: 800, height: 500)
        let crop = CGRect(x: 40, y: 30, width: 400, height: 300)
        XCTAssertEqual(
            CropOverlayInteraction.hit(
                at: CGPoint(x: crop.midX, y: crop.midY), cropRect: crop, bounds: bounds),
            .move
        )
    }

    func testPressOutsideCropAndHandlesIsIgnored() {
        let bounds = CGRect(x: 0, y: 0, width: 800, height: 500)
        let crop = CGRect(x: 200, y: 150, width: 200, height: 150)
        XCTAssertNil(
            CropOverlayInteraction.hit(at: CGPoint(x: 10, y: 10), cropRect: crop, bounds: bounds)
        )
    }

    func testTopLeftHandleHitRectStaysInsideOverlayAndCoversTheVisibleCorner() {
        let bounds = CGRect(x: 0, y: 0, width: 800, height: 500)
        let crop = bounds
        let rect = CropOverlayInteraction.handleHitRect(
            .topLeading, cropRect: crop, bounds: bounds)
        XCTAssertTrue(bounds.contains(rect))
        XCTAssertTrue(
            rect.minX <= crop.minX && rect.maxX >= crop.minX
                && rect.minY <= crop.minY && rect.maxY >= crop.minY)
        XCTAssertEqual(rect.width, CropOverlayInteraction.handleHitTargetSize)
        XCTAssertEqual(rect.height, CropOverlayInteraction.handleHitTargetSize)
    }
}

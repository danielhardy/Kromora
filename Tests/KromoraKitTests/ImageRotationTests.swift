import CoreGraphics
import XCTest
@testable import KromoraKit

@MainActor
final class ImageRotationTests: TempDirectoryTestCase {
    private func waitUntil(
        _ description: String, _ condition: @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(5)
        while !condition() {
            guard Date() < deadline else {
                throw TestSynchronizationError.timedOut(description, "state did not settle")
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    func testRotationStateIsCodableVisibleAndIdentityAware() throws {
        let document = EditDocument(rotation: .clockwise90)
        let restored = try JSONDecoder().decode(
            EditDocument.self, from: JSONEncoder().encode(document)
        )

        XCTAssertEqual(restored, document)
        XCTAssertFalse(document.isIdentity)
        XCTAssertTrue(document.hasVisibleLookEdits)
        XCTAssertEqual(EditDocument().rotation, .zero)
        XCTAssertEqual(
            try JSONDecoder().decode(EditDocument.self, from: Data("{\"version\":2}".utf8)).rotation,
            .zero
        )
    }

    func testQuarterTurnsSwapGeometryAndFourTurnsRestoreIt() {
        let size = CGSize(width: 96, height: 64)

        XCTAssertEqual(ImageRotation.clockwise90.orientedExtent(size), CGSize(width: 64, height: 96))
        XCTAssertEqual(ImageRotation.counterClockwise90.orientedExtent(size), CGSize(width: 64, height: 96))
        XCTAssertEqual(ImageRotation.half.orientedExtent(size), size)
        XCTAssertEqual(
            ImageRotation.zero.addingClockwiseQuarterTurns(4), .zero
        )
        XCTAssertEqual(
            ImageRotation.zero.addingClockwiseQuarterTurns(-1), .counterClockwise90
        )
    }

    func testRotationHistoryUndoRedoDoesNotLoseOtherEdits() {
        let original = EditDocument(adjustments: [.exposure(ev: 0.5)])
        let rotated = EditDocument(
            rotation: .clockwise90, adjustments: original.adjustments
        )
        var history = EditHistory()
        history.recordChange(from: original, to: rotated)

        XCTAssertEqual(history.undo(current: rotated), original)
        XCTAssertEqual(history.redo(current: original), rotated)

        let reset = EditDocument(adjustments: original.adjustments)
        XCTAssertEqual(reset.rotation, .zero)
        XCTAssertEqual(reset.adjustments, original.adjustments)
    }

    func testRotationControlsUseDocumentHistoryAndResetOnlyRotation() async throws {
        let url = try Fixtures.writeGradientPNG(
            width: 96, height: 64, named: "rotation-controls.png", in: tempDirectory
        )
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())
        viewModel.openImage(url: url)
        try await waitUntil("the selected image") { viewModel.sourceImage != nil }

        viewModel.updateDocument { $0.adjustments = [.exposure(ev: 0.5)] }
        viewModel.rotateClockwise()
        XCTAssertEqual(viewModel.document.rotation, .clockwise90)
        XCTAssertEqual(viewModel.document.adjustments, [.exposure(ev: 0.5)])

        viewModel.undo()
        XCTAssertEqual(viewModel.document.rotation, .zero)
        XCTAssertEqual(viewModel.document.adjustments, [.exposure(ev: 0.5)])
        viewModel.redo()
        XCTAssertEqual(viewModel.document.rotation, .clockwise90)

        viewModel.resetRotation()
        XCTAssertEqual(viewModel.document.rotation, .zero)
        XCTAssertEqual(viewModel.document.adjustments, [.exposure(ev: 0.5)])
    }

    func testRenderPipelineRotationSwapsPreviewAndExportGeometryWithCrop() throws {
        let url = try Fixtures.writeGradientPNG(
            width: 96, height: 64, named: "rotation-pipeline.png", in: tempDirectory
        )
        let source = ImageSource(url: url, nativeExtent: CGSize(width: 96, height: 64))
        let rotated = try XCTUnwrap(RenderPipeline.buildImage(
            source: source, document: EditDocument(rotation: .clockwise90), lut: nil,
            scale: .full
        ))
        XCTAssertEqual(rotated.extent.integral.size, CGSize(width: 64, height: 96))

        let cropped = try XCTUnwrap(RenderPipeline.buildImage(
            source: source,
            document: EditDocument(
                crop: CropAdjustments(
                    normalizedRect: CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
                ),
                rotation: .clockwise90
            ),
            lut: nil,
            scale: .full
        ))
        XCTAssertEqual(cropped.extent.integral.size, CGSize(width: 32, height: 48))
    }

    func testRenderEnginePreviewAndExportAgreeForRotatedCrop() async throws {
        let url = try Fixtures.writeGradientPNG(
            width: 96, height: 64, named: "rotation-export.png", in: tempDirectory
        )
        let source = ImageSource(url: url, nativeExtent: CGSize(width: 96, height: 64))
        let document = EditDocument(
            crop: CropAdjustments(
                normalizedRect: CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
            ),
            rotation: .counterClockwise90
        )
        let engine = RenderEngine()
        let preview = try await engine.render(RenderRequest(
            source: source, document: document, targetSize: CGSize(width: 64, height: 96),
            quality: .preview, output: .raster
        ))
        let export = try await engine.render(RenderRequest(
            source: source, document: document, quality: .export, output: .raster
        ))

        XCTAssertEqual(preview.extent, CGSize(width: 32, height: 48))
        XCTAssertEqual(export.extent, preview.extent)
        assertPixelsEqual(
            try Pixels.bytes(of: try Pixels.decode(preview.data)),
            try Pixels.bytes(of: try Pixels.decode(export.data)),
            tolerance: 0,
            "rotated preview and export must share orientation and crop geometry"
        )
    }
}

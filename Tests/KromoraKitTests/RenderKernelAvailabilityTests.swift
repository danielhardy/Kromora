import CoreImage
import XCTest
@testable import KromoraKit

/// KRMA-1169: a kernel needed to reproduce a saved edit must fail the render or export visibly
/// instead of letting the edit be silently omitted.
@MainActor
final class RenderKernelAvailabilityTests: TempDirectoryTestCase {
    private struct LoadFailure: LocalizedError {
        var errorDescription: String? { "simulated metallib load failure" }
    }

    private func status(failing names: String...) -> CIKernelLibraryStatus {
        CIKernelLibraryStatus(failures: Dictionary(uniqueKeysWithValues: names.map {
            ($0, CIKernelLibraryError.kernelUnavailable(name: $0, underlying: LoadFailure()))
        }))
    }

    private func source() throws -> ImageSource {
        let url = try Fixtures.writeGradientPNG(width: 16, height: 8, named: "kernel.png", in: tempDirectory)
        return ImageSource(url: url, nativeExtent: CGSize(width: 16, height: 8))
    }

    private var maskedDocument: EditDocument {
        EditDocument(localAdjustments: [LocalAdjustmentLayer(
            components: [MaskComponent(source: .linear(LinearGradientDefinition()))],
            adjustments: LocalAdjustments(exposure: 1)
        )])
    }

    private func exportRequest(_ source: ImageSource, _ document: EditDocument) -> RenderRequest {
        let options = ExportOptions(format: .jpeg, destination: nil)
        return RenderRequest(
            source: source, document: document, lut: nil, quality: .export,
            output: .encoded(format: .jpeg, quality: CGFloat(options.quality)),
            space: options.colorSpace, exportOptions: options
        )
    }

    // MARK: - Validation

    func testShippingBundleValidatesEveryKernel() {
        XCTAssertEqual(CIKernelLibraryStatus.bundled.failures.count, 0)
        XCTAssertNoThrow(try CIKernelLibraryStatus.bundled.require(CIKernelLibrary.expectedKernelNames))
    }

    func testRequirementFailurePreservesTheUnderlyingLoadError() throws {
        XCTAssertThrowsError(try status(failing: "hslMixer").require(["hslMixer", "colorGrading"])) { error in
            guard case .kernelUnavailable(let name, let underlying)? = error as? CIKernelLibraryError else {
                return XCTFail("unexpected error \(error)")
            }
            XCTAssertEqual(name, "hslMixer")
            XCTAssertTrue(underlying is LoadFailure)
            XCTAssertTrue(error.localizedDescription.contains("simulated metallib load failure"))
        }
        XCTAssertNoThrow(try status(failing: "hslMixer").require(["colorGrading"]))
    }

    // MARK: - Requirements follow the document

    func testNeutralDocumentRequiresNoKernels() {
        XCTAssertTrue(RenderKernelRequirements.names(for: EditDocument()).isEmpty)
    }

    func testEachPixelProducingEditNamesItsKernels() {
        var mixer = EditDocument()
        mixer.color.mixer.red.saturation = 20
        XCTAssertEqual(RenderKernelRequirements.names(for: mixer), ["hslMixer"])

        var grading = EditDocument()
        grading.color.grading.shadows.saturation = 20
        XCTAssertEqual(RenderKernelRequirements.names(for: grading), ["colorGrading"])

        var vignette = EditDocument()
        vignette.effects.vignette.amount = 30
        XCTAssertEqual(RenderKernelRequirements.names(for: vignette), ["effectsVignette"])

        var grain = EditDocument()
        grain.effects.grain.amount = 30
        XCTAssertEqual(RenderKernelRequirements.names(for: grain), ["effectsGrain"])

        var clarity = EditDocument()
        clarity.effects.clarity = 30
        XCTAssertEqual(RenderKernelRequirements.names(for: clarity), ["effectsMidtoneMask"])

        XCTAssertEqual(
            RenderKernelRequirements.names(for: maskedDocument),
            ["localCombineMask", "localAnalyticMask"])

        var heal = EditDocument()
        heal.retouch.spots = [RetouchSpot(mode: .heal)]
        XCTAssertEqual(
            RenderKernelRequirements.names(for: heal),
            ["retouchMembraneApply", "retouchPull", "retouchPush", "retouchApplyCorrection"])
        var clone = EditDocument()
        clone.retouch.spots = [RetouchSpot(mode: .clone)]
        XCTAssertEqual(RenderKernelRequirements.names(for: clone), ["retouchMembraneApply"])
    }

    func testInvertedMaskAndDisabledLayerRequirements() {
        var document = maskedDocument
        document.localAdjustments[0].isInverted = true
        XCTAssertTrue(RenderKernelRequirements.names(for: document).contains("localInvertMask"))
        document.localAdjustments[0].isEnabled = false
        XCTAssertTrue(
            RenderKernelRequirements.names(for: document).isEmpty,
            "a layer that does not render must not require its kernels")
    }

    // MARK: - Mask composition

    func testMaskInversionAndCombinationThrowWhenTheirKernelIsUnavailable() throws {
        let extent = CGRect(x: 0, y: 0, width: 4, height: 4)
        let mask = CIImage(color: .white).cropped(to: extent)
        let invert = LocalMaskRenderer(kernelStatus: status(failing: "localInvertMask"))
        XCTAssertThrowsError(try invert.inverted(mask, extent: extent))
        let combine = LocalMaskRenderer(kernelStatus: status(failing: "localCombineMask"))
        XCTAssertThrowsError(try combine.combined(mask, with: mask, mode: .add, extent: extent))

        let healthy = LocalMaskRenderer()
        XCTAssertNoThrow(try healthy.inverted(mask, extent: extent))
        XCTAssertNoThrow(try healthy.combined(mask, with: mask, mode: .add, extent: extent))
    }

    // MARK: - Render and export

    func testRenderFailsVisiblyWhenAMaskKernelIsUnavailable() async throws {
        let engine = RenderEngine(kernelStatus: status(failing: "localAnalyticMask"))
        let request = RenderRequest(
            source: try source(), document: maskedDocument,
            targetSize: CGSize(width: 16, height: 8), quality: .preview, output: .raster
        )
        do {
            _ = try await engine.render(request)
            XCTFail("render must not succeed without the mask kernel")
        } catch let error as CIKernelLibraryError {
            guard case .kernelUnavailable(let name, _) = error else { return XCTFail("\(error)") }
            XCTAssertEqual(name, "localAnalyticMask")
        }
        let image = await engine.makeCIImage(request)
        XCTAssertNil(image, "the preview path reports failure rather than an unedited frame")
    }

    func testExportFailsWithoutCommittingAFileAndPreservesTheDocument() async throws {
        let engine = RenderEngine(kernelStatus: status(failing: "localCombineMask"))
        let document = maskedDocument
        let original = document
        let staged = tempDirectory.appendingPathComponent("staged.jpg")
        do {
            try await engine.encode(exportRequest(try source(), document), to: staged)
            XCTFail("export must not succeed without the mask kernel")
        } catch is CIKernelLibraryError {}
        XCTAssertFalse(FileManager.default.fileExists(atPath: staged.path))
        XCTAssertEqual(document, original)
    }

    func testBatchExportReportsTheKernelFailureAndWritesNothing() async throws {
        let engine = RenderEngine(kernelStatus: status(failing: "localAnalyticMask"))
        let coordinator = ExportCoordinator(engine: engine, exportEngine: engine)
        let folder = tempDirectory.appendingPathComponent("out")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = try Fixtures.writeGradientPNG(
            width: 16, height: 8, named: "batch.png", in: tempDirectory)
        let item = ExportCoordinator.BatchItem(url: url, data: nil, name: "shot")

        let outcome = await coordinator.performBatchExport(
            [item], document: maskedDocument, lut: nil, format: .jpeg, to: folder)

        XCTAssertEqual(outcome.exported, 0)
        XCTAssertEqual(outcome.failed, 1)
        XCTAssertTrue(
            outcome.failures.first?.reason.contains("localAnalyticMask") == true,
            "the failure reason names the unavailable step")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), [])
    }

    func testUnrelatedKernelOutagesDoNotAffectNeutralOrOtherEdits() async throws {
        let engine = RenderEngine(kernelStatus: status(failing: "localAnalyticMask", "hslMixer"))
        let src = try source()
        let neutral = try await engine.render(RenderRequest(
            source: src, document: EditDocument(),
            targetSize: CGSize(width: 16, height: 8), quality: .preview, output: .raster))
        XCTAssertFalse(neutral.data.isEmpty)

        var other = EditDocument()
        other.effects.vignette.amount = -30
        let vignetted = try await engine.render(RenderRequest(
            source: src, document: other,
            targetSize: CGSize(width: 16, height: 8), quality: .preview, output: .raster))
        XCTAssertFalse(vignetted.data.isEmpty)
    }
}

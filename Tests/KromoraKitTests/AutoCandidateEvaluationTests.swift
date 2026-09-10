import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import KromoraKit

/// KRMA-342: the evaluation harness must invoke the real render seam (not a CSS approximation),
/// emit matching-geometry before/after/diff/mask-overlay pixels, identify renderer failures, and
/// prove preview/export parity on at least one fixture.
final class AutoCandidateEvaluationTests: TempDirectoryTestCase {

    // MARK: - Pure analysis-view transform

    func testAnalysisViewExcludesDecorativeStagesButRetainsGeometry() {
        var complete = EditDocument()
        complete.lut = LUTSettings(lutID: LUTID(raw: "test-cube"), intensity: 1)
        complete.color.grading.shadows = ColorGradingWheel(hue: 30, saturation: 40)
        complete.effects.grain = GrainAdjustments(amount: 50, size: 50, roughness: 50)
        complete.effects.vignette = VignetteAdjustments(amount: 40)
        complete.effects.clarity = 20
        complete.light.exposure = 0.5
        complete.crop = CropAdjustments(normalizedRect: CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8))
        complete.rotation = .clockwise90

        let view = AutoCandidateEvaluation.analysisDocument(from: complete)

        XCTAssertTrue(view.lut.isIdentity)
        XCTAssertEqual(view.color.grading, .neutral)
        XCTAssertTrue(view.effects.grain.isIdentity)
        XCTAssertTrue(view.effects.vignette.isIdentity)
        // Photographic intent and geometry survive the view transform.
        XCTAssertEqual(view.light.exposure, 0.5)
        XCTAssertEqual(view.effects.clarity, 20)
        XCTAssertEqual(view.crop, complete.crop)
        XCTAssertEqual(view.rotation, .clockwise90)
    }

    func testChangedControlsIsEmptyForIdenticalDocuments() {
        XCTAssertEqual(
            AutoCandidateEvaluation.changedControls(baseline: EditDocument(), candidate: EditDocument()),
            []
        )
        var candidate = EditDocument()
        candidate.light.exposure = 0.75
        candidate.lut = LUTSettings(lutID: LUTID(raw: "x"), intensity: 1)
        let changed = AutoCandidateEvaluation.changedControls(
            baseline: EditDocument(), candidate: candidate
        )
        XCTAssertTrue(changed.contains("light"))
        XCTAssertTrue(changed.contains("lut"))
    }

    // MARK: - Pixel comparison math (deterministic, no renderer)

    func testIdenticalRendersProduceZeroDiff() throws {
        let image = try Fixtures.makeCGImage(width: 8, height: 6, red: 0.5, green: 0.4, blue: 0.3)
        let png = try XCTUnwrap(AutoCandidateEvaluator.pngData(for: image))
        let render = AutoEvaluatedRender(pngData: png, width: 8, height: 6)
        let comparison = AutoCandidateEvaluator.compare(base: render, proposed: render)
        XCTAssertEqual(comparison.measurements.meanAbsoluteDifference, 0)
        XCTAssertEqual(comparison.measurements.maxDifference, 0)
        XCTAssertEqual(comparison.measurements.changedPixelFraction, 0)
        XCTAssertNotNil(comparison.diffPNG)
    }

    func testKnownEditChangesDiffImage() throws {
        let baseImage = try Fixtures.makeCGImage(width: 8, height: 6, red: 0.2, green: 0.2, blue: 0.2)
        let proposedImage = try Fixtures.makeCGImage(width: 8, height: 6, red: 0.8, green: 0.8, blue: 0.8)
        let base = AutoEvaluatedRender(
            pngData: try XCTUnwrap(AutoCandidateEvaluator.pngData(for: baseImage)), width: 8, height: 6
        )
        let proposed = AutoEvaluatedRender(
            pngData: try XCTUnwrap(AutoCandidateEvaluator.pngData(for: proposedImage)), width: 8, height: 6
        )
        let comparison = AutoCandidateEvaluator.compare(base: base, proposed: proposed)
        XCTAssertGreaterThan(comparison.measurements.meanAbsoluteDifference, 0.3)
        XCTAssertGreaterThan(comparison.measurements.changedPixelFraction, 0.9)
        XCTAssertNotNil(comparison.diffPNG)
        // The diff image decodes at the shared extent.
        let diffPixels = try XCTUnwrap(AutoCandidateEvaluator.rgba8Pixels(
            pngData: try XCTUnwrap(comparison.diffPNG)
        ))
        XCTAssertEqual(diffPixels.width, 8)
        XCTAssertEqual(diffPixels.height, 6)
    }

    // MARK: - Evaluator seam against a document-dependent stub (no GPU)

    func testEvaluateRendersMatchingGeometryAndMeasuresKnownEdit() async throws {
        let engine = DocumentBrightnessEngine()
        let source = ImageSource(
            backing: .data(Data("stub".utf8)), kind: .standard,
            nativeExtent: CGSize(width: 96, height: 64)
        )
        var proposed = EditDocument()
        proposed.light.exposure = 1.0

        let evaluator = AutoCandidateEvaluator()
        let evaluation = await evaluator.evaluate(
            fixtureID: "stub-exposure", source: source,
            baseDocument: EditDocument(), proposedDocument: proposed,
            engine: engine
        )

        XCTAssertFalse(evaluation.report.hasFailures, "failures: \(evaluation.report.renderFailures)")
        let base = try XCTUnwrap(evaluation.base)
        let result = try XCTUnwrap(evaluation.proposed)
        // Matching orientation, crop geometry, and dimensions across roles.
        XCTAssertEqual(base.width, result.width)
        XCTAssertEqual(base.height, result.height)
        XCTAssertEqual(evaluation.report.renderWidth, base.width)
        XCTAssertEqual(evaluation.report.renderHeight, base.height)
        XCTAssertTrue(evaluation.report.changedControls.contains("light"))
        let measurements = try XCTUnwrap(evaluation.report.measurements)
        XCTAssertGreaterThan(measurements.meanAbsoluteDifference, 0)
        XCTAssertGreaterThan(measurements.changedPixelFraction, 0.5)
        XCTAssertNotNil(evaluation.diffPNG)
    }

    func testEvaluateRotationSwapsDimensions() async {
        let engine = DocumentBrightnessEngine()
        let source = ImageSource(
            backing: .data(Data("stub-rot".utf8)), kind: .standard,
            nativeExtent: CGSize(width: 96, height: 64)
        )
        var rotated = EditDocument()
        rotated.rotation = .clockwise90

        // Geometry is evaluated per-document: a rotated edit orients its own target box,
        // so both roles render portrait from the oriented extent.
        let evaluation = await AutoCandidateEvaluator().evaluate(
            fixtureID: "stub-rotation", source: source,
            baseDocument: rotated, proposedDocument: rotated,
            engine: engine
        )
        XCTAssertFalse(evaluation.report.hasFailures)
        // The evaluation target fits the *oriented* extent: 64×96 native becomes portrait.
        XCTAssertGreaterThan(evaluation.report.renderHeight, evaluation.report.renderWidth)
    }

    func testEvaluateRecordsFailuresInsteadOfPresentingMissingRenderAsSuccess() async {
        let engine = DocumentBrightnessEngine()
        await engine.setShouldFail(true)
        let source = ImageSource(
            backing: .data(Data("stub-fail".utf8)), kind: .standard,
            nativeExtent: CGSize(width: 32, height: 32)
        )
        let evaluation = await AutoCandidateEvaluator().evaluate(
            fixtureID: "stub-failure", source: source,
            baseDocument: EditDocument(), proposedDocument: EditDocument(),
            engine: engine
        )
        XCTAssertTrue(evaluation.report.hasFailures)
        XCTAssertTrue(evaluation.report.renderFailures.contains("base"))
        XCTAssertTrue(evaluation.report.renderFailures.contains("proposed"))
        XCTAssertNil(evaluation.report.measurements)
        XCTAssertNil(evaluation.diffPNG)
        XCTAssertNil(evaluation.base)
    }

    func testArtifactWriteRoundTripsOutsideSourceTree() async throws {
        let engine = DocumentBrightnessEngine()
        let source = ImageSource(
            backing: .data(Data("stub-artifact".utf8)), kind: .standard,
            nativeExtent: CGSize(width: 48, height: 32)
        )
        var proposed = EditDocument()
        proposed.light.exposure = 0.5
        let evaluator = AutoCandidateEvaluator()
        let evaluation = await evaluator.evaluate(
            fixtureID: "artifact-check", source: source,
            baseDocument: EditDocument(), proposedDocument: proposed,
            engine: engine
        )
        let dir = try evaluator.writeArtifact(evaluation, fixtureID: "artifact-check", directory: tempDirectory)
        XCTAssertEqual(dir.lastPathComponent, "artifact-check")
        let names = try Set(FileManager.default.contentsOfDirectory(atPath: dir.path))
        XCTAssertTrue(names.contains("unchanged.png"))
        XCTAssertTrue(names.contains("proposed.png"))
        XCTAssertTrue(names.contains("diff.png"))
        XCTAssertTrue(names.contains("report.json"))
        XCTAssertTrue(names.contains("report.md"))
        let decoded = try JSONDecoder().decode(
            AutoEvaluationReport.self,
            from: try Data(contentsOf: dir.appendingPathComponent("report.json"))
        )
        XCTAssertEqual(decoded, evaluation.report)
    }

    // MARK: - Real pipeline evidence (representative fixture)

    /// A known exposure edit through the actual `RenderEngine` must change the real diff image,
    /// and preview/export extents must agree. Small gradient fixture keeps this to milliseconds.
    func testRealEngineDiffAndParityOnGradientFixture() async throws {
        let url = try Fixtures.writeGradientPNG(width: 96, height: 64, named: "auto-eval.png", in: tempDirectory)
        let source = ImageSource(url: url, nativeExtent: CGSize(width: 96, height: 64))
        let engine = RenderEngine()
        var proposed = EditDocument()
        proposed.light.exposure = 1.0

        let evaluator = AutoCandidateEvaluator()
        let evaluation = await evaluator.evaluate(
            fixtureID: "real-gradient", source: source,
            baseDocument: EditDocument(), proposedDocument: proposed,
            engine: engine
        )
        XCTAssertFalse(
            evaluation.report.hasFailures, "failures: \(evaluation.report.renderFailures)"
        )
        let measurements = try XCTUnwrap(evaluation.report.measurements)
        XCTAssertGreaterThan(measurements.meanAbsoluteDifference, 0)
        XCTAssertGreaterThan(measurements.changedPixelFraction, 0)
        let parity = await evaluator.checkPreviewExportParity(
            source: source, document: proposed, engine: engine
        )
        XCTAssertTrue(parity)
        // Opt-in artifact generation for `scripts/auto-evaluation-report.sh`: when set, the
        // real-pipeline evaluation is written outside the source tree for human/agent review.
        if let artifactRoot = ProcessInfo.processInfo.environment["KROMORA_AUTO_EVAL_ARTIFACT_DIR"] {
            let root = URL(fileURLWithPath: artifactRoot, isDirectory: true)
            let dir = try evaluator.writeArtifact(evaluation, fixtureID: "real-gradient", directory: root)
            print("Auto evaluation artifact: \(dir.path)")
        }
    }
}

/// Document-dependent stub: renders a solid gray whose brightness follows
/// `document.light.exposure` at the request's own target size. This exercises the evaluator's
/// geometry/measurement/artifact logic deterministically without a GPU; pixel assertions about
/// the real pipeline belong to the `RenderEngine` test above.
private actor DocumentBrightnessEngine: RenderEngining {
    private var shouldFail = false

    func setShouldFail(_ value: Bool) { shouldFail = value }

    func histogram(
        source: ImageSource,
        document: EditDocument,
        lut: CubeLUT?,
        scale: RenderScale,
        space: WorkingSpace,
        maxDimension: Int
    ) async -> HistogramData? { nil }

    func invalidateLUTCache() async {}

    func rawCapabilities(for source: ImageSource) async -> RAWCapabilities? { nil }

    func render(_ request: RenderRequest) async throws -> RenderResult {
        if shouldFail { throw ImageError.processingFailed }
        let size = request.targetSize ?? CGSize(width: 32, height: 32)
        let width = max(1, Int(size.width.rounded()))
        let height = max(1, Int(size.height.rounded()))
        let brightness = min(max(0.25 + request.document.light.exposure * 0.25, 0), 1)
        let space = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw ImageError.processingFailed }
        context.setFillColor(
            red: brightness, green: brightness, blue: brightness, alpha: 1
        )
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let image = context.makeImage(),
              let png = AutoCandidateEvaluator.pngData(for: image)
        else { throw ImageError.processingFailed }
        return RenderResult(
            data: png, extent: CGSize(width: width, height: height),
            colorSpace: request.space, quality: request.quality, output: request.output
        )
    }
}

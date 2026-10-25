import XCTest
import CoreImage
import CoreGraphics
import simd
@testable import KromoraKit

/// Phase 2 Step 1: the colour seam itself.
///
/// This suite was written against two code paths that "merely agreed" — `ImageProcessor.renderPreview`
/// and `ImageProcessor.export`, one of which passed no colour space at all. Step 7 deleted both, and
/// with them the reason for most of what was here: there is one funnel now, and its parity is
/// asserted where it lives. See the redirection block below.
///
/// What remains is the seam as a *value* — that `.current` resolves, that every case names a real
/// system space, that the cube interpolates in its authoring space, and that derive defaults to the current space.
final class WorkingSpaceTests: TempDirectoryTestCase {

    // MARK: - The seam itself

    func testCurrentIsSRGB() {
        XCTAssertEqual(WorkingSpace.current, .sRGB)
        XCTAssertEqual(WorkingSpace.sRGB.cgColorSpace.name, CGColorSpace.sRGB)
        XCTAssertEqual(WorkingSpace.displayP3.cgColorSpace.name, CGColorSpace.displayP3)
    }

    func testEveryCaseResolvesToARealColorSpace() {
        // The accessor force-unwraps; this is what makes that safe.
        for space in WorkingSpace.allCases {
            XCTAssertNotNil(space.cgColorSpace.name, "\(space) should resolve to a system colour space")
        }
    }

    // MARK: - Where the parity tests went
    //
    // Step 1 asserted preview/export parity here by driving `ImageProcessor.renderPreview` against
    // `ImageProcessor.export` — the two code paths that "merely agreed". Step 7 deleted both: there
    // is one funnel now, and the properties moved to tests that exercise it rather than the old
    // pair. Named individually so this is a redirection, not a quiet deletion:
    //
    // - `testPreviewRasterMatchesExportedBytes`      → `RenderEngineTests.testPreviewAndExportAreTheSamePixels`
    // - `testPreviewMatchesExportWithALUTApplied`    → same test (its document carries a warm cube and two adjustments)
    // - `testLUTInterpolationAndOutputMoveTogether`  → `RenderEngineTests.testParityHoldsInEveryWorkingSpace`
    // - `testWorkingSpaceReachesTheOutputEncoder`    → `RenderEngineTests.testTheWorkingSpaceReachesTheEncoder`
    //
    // The end-to-end half — bytes that actually reached a file on disk — is
    // `ExportCutoverTests.testExportedFileIsTheDocumentAtFullResolution`, and the NSImage-wrapping
    // half is `PreviewCutoverTests.testEachKnobVisiblyChangesThePreview`.
    //
    // What stays below is the part that has no equivalent up there: the cube's *interpolation*
    // space, asserted against `CubeLUT.apply` directly rather than through a pipeline that could be
    // passing the right space for the wrong reason.

    func testWorkingSpaceReachesTheLUTInterpolation() throws {
        // A cube that isn't the identity will interpolate differently in a wider space, so the two
        // renders must differ. If makeFilter ignored its argument they would be identical.
        let source = try gradientImage(width: 32, height: 32)
        let inSRGB = try XCTUnwrap(TestImages.warmLUT(authoringSpace: .sRGB).apply(to: source))
        let inP3 = try XCTUnwrap(TestImages.warmLUT(authoringSpace: .displayP3).apply(to: source))

        // Rasterize both through the SAME space so only the interpolation differs.
        let a = try Pixels.bytes(of: inSRGB, space: .sRGB)
        let b = try Pixels.bytes(of: inP3, space: .sRGB)

        assertPixelsDiffer(a, b, "the cube's authoring space should affect the result")
    }

    // MARK: - Derive fits in the space it stamps

    /// Preparation keeps sRGB sampling and stamps; the derive/Save defaults follow `current`.
    func testPreparationDefaultsStaySRGB() {
        XCTAssertEqual(WorkingSpace.current, .sRGB)
        XCTAssertEqual(RecipeExtractor.Options().authoringSpace, .sRGB)
    }

    // The histogram used to be a third `ImageProcessor` colour site and was pinned here. Step 6 moved
    // it onto `RenderEngine` along with export, so `testTheHistogramFollowsTheWorkingSpace` in
    // `HistogramTests` is where that property lives now — asserted against the shipping path rather
    // than against a `CIImage` the app no longer builds.

    // MARK: - Helpers

    // The gradient, the warm cube and the pixel comparison now live in `PixelAssertions.swift`,
    // shared with the Step 3 render tests — one tolerance, one fixture, no drift between suites.
    private func gradientImage(width: Int, height: Int) throws -> CIImage {
        try TestImages.gradient(width: width, height: height)
    }

}

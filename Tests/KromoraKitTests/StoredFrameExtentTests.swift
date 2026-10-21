import CoreGraphics
import XCTest

@testable import KromoraKit

/// KRMA-1042: the stored first frame must fit the canvas exactly as the settled render does.
@MainActor
final class StoredFrameExtentTests: XCTestCase {
    private func metadata(width: Int, height: Int, aspect: Double) -> PresentationFrameMetadata {
        let base = FrameFixtures.metadata(identity: FrameFixtures.identity(), width: width, height: height)
        return PresentationFrameMetadata(
            identity: base.identity, kind: base.kind, signature: base.signature,
            geometry: PresentedGeometry(
                crop: base.geometry.crop, rotation: base.geometry.rotation,
                orientedAspectRatio: aspect
            ),
            rasterColorSpace: base.rasterColorSpace, perceptualDigest: base.perceptualDigest,
            presentedAt: base.presentedAt, pixelWidth: width, pixelHeight: height
        )
    }

    func testLandscapeExtentCarriesTrueAspectOnLongAxis() {
        let aspect = 5997.0 / 4001.0
        let size = AppViewModel.storedFramePresentationExtent(
            metadata(width: 2048, height: 1366, aspect: aspect)
        )
        XCTAssertEqual(size.width, 2048)
        XCTAssertEqual(size.width / size.height, aspect, accuracy: 1e-9)
    }

    func testPortraitExtentCarriesTrueAspectOnLongAxis() {
        let aspect = 4001.0 / 5997.0
        let size = AppViewModel.storedFramePresentationExtent(
            metadata(width: 1366, height: 2048, aspect: aspect)
        )
        XCTAssertEqual(size.height, 2048)
        XCTAssertEqual(size.width / size.height, aspect, accuracy: 1e-9)
    }

    func testCanonicalDownsamplingCompensatesForStackedWholePixelRounding() {
        // A 1000×562 whole-pixel render becomes 2048×1150 after uniform downsampling and
        // flooring. For a 16:9 planned crop, the stored frame needs a virtual height of 1152;
        // the previous one-pixel limit left its aspect mismatched and caused a small canvas shift.
        let aspect = 16.0 / 9.0
        let size = AppViewModel.storedFramePresentationExtent(
            metadata(width: 2048, height: 1150, aspect: aspect)
        )
        XCTAssertEqual(size.width, 2048)
        XCTAssertEqual(size.height, 1152, accuracy: 1e-9)
        XCTAssertEqual(size.width / size.height, aspect, accuracy: 1e-9)
    }

    func testPortraitCanonicalDownsamplingCompensatesForStackedWholePixelRounding() {
        let aspect = 9.0 / 16.0
        let size = AppViewModel.storedFramePresentationExtent(
            metadata(width: 1150, height: 2048, aspect: aspect)
        )
        XCTAssertEqual(size.width, 1152, accuracy: 1e-9)
        XCTAssertEqual(size.height, 2048)
        XCTAssertEqual(size.width / size.height, aspect, accuracy: 1e-9)
    }

    func testDisagreementBeyondRoundingBoundKeepsRasterDimensions() {
        let size = AppViewModel.storedFramePresentationExtent(
            metadata(width: 2048, height: 1366, aspect: 1.0)
        )
        XCTAssertEqual(size, CGSize(width: 2048, height: 1366))
    }

    // The settled canvas fits the planner's fractional crop extent, not the whole-pixel-snapped
    // rendered extent, so the persisted aspect must come from the plan.
    private func request(planned: CGRect?) -> RenderRequest {
        RenderRequest(
            source: ImageSource(data: Data(), nativeExtent: CGSize(width: 6000, height: 4000)),
            document: EditDocument(), targetSize: CGSize(width: 1000, height: 600),
            presentationImageExtent: planned, quality: .preview, output: .raster
        )
    }

    func testPersistedAspectPrefersPlannedExtentOverSnappedRender() {
        let rendered = CGRect(x: 0, y: 0, width: 1000, height: 562)
        let planned = CGRect(x: 0, y: 0, width: 1000.4, height: 562.6)
        let aspect = PreviewPresentationCoordinator.persistedAspectRatio(
            rendered: rendered, request: request(planned: planned)
        )
        XCTAssertEqual(aspect, Double(planned.width / planned.height), accuracy: 1e-12)
    }

    func testPersistedAspectFallsBackWithoutPlanOrOnLargeDisagreement() {
        let rendered = CGRect(x: 0, y: 0, width: 1000, height: 562)
        let renderedAspect = Double(1000.0 / 562.0)
        XCTAssertEqual(
            PreviewPresentationCoordinator.persistedAspectRatio(
                rendered: rendered, request: request(planned: nil)
            ), renderedAspect, accuracy: 1e-12
        )
        XCTAssertEqual(
            PreviewPresentationCoordinator.persistedAspectRatio(
                rendered: rendered, request: request(planned: CGRect(x: 0, y: 0, width: 800, height: 800))
            ), renderedAspect, accuracy: 1e-12
        )
    }
}

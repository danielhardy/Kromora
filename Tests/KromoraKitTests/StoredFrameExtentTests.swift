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

    func testDisagreementBeyondOnePixelKeepsRasterDimensions() {
        let size = AppViewModel.storedFramePresentationExtent(
            metadata(width: 2048, height: 1366, aspect: 1.0)
        )
        XCTAssertEqual(size, CGSize(width: 2048, height: 1366))
    }
}

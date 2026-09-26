import XCTest
@testable import KromoraKit

final class CaptureMetadataOverlayTests: XCTestCase {
    func testCaptureRowsOmitMissingValuesAndKeepCameraOrder() {
        var metadata = ImageMetadata()
        metadata.iso = "ISO 400"
        metadata.aperture = "ƒ/2.8"
        metadata.focalLength = "35 mm"

        XCTAssertEqual(
            metadata.captureOverlayRows,
            [
                ImageMetadata.Row(label: "ISO", value: "ISO 400"),
                ImageMetadata.Row(label: "Aperture", value: "ƒ/2.8"),
                ImageMetadata.Row(label: "Focal length", value: "35 mm"),
            ]
        )
    }

    func testCaptureRowsAreEmptyWhenPhotoHasNoExposureMetadata() {
        XCTAssertTrue(ImageMetadata().captureOverlayRows.isEmpty)
    }
}

import XCTest
import CoreImage
import CoreGraphics
import ImageIO
@testable import KromoraKit

/// RAW orientation was baked nowhere: `CIRAWFilter.outputImage` is sensor-native, so an
/// orientation-3 ARW rendered upside-down on the canvas while its ImageIO filmstrip thumbnail
/// (transform baked) stood upright. These pin the shared helpers every RAW decode now goes
/// through, without needing a camera RAW fixture in the checkout.
final class RawOrientationTests: TempDirectoryTestCase {

    /// The ImageIO reader must report the tag the camera wrote, for both file and bytes
    /// backings, and the axis-swap rule must match the standard-image path.
    func testEXIFOrientationReaderMatchesTaggedJPEGs() throws {
        for orientation in [1, 3, 6, 8] {
            let url = try Fixtures.writeJPEG(
                width: 80, height: 60, orientation: orientation,
                named: "raw-orient-\(orientation).jpg", in: tempDirectory
            )
            let fileOrientation = ImageDecoder.exifOrientation(at: url)
            XCTAssertEqual(
                fileOrientation.rawValue, UInt32(orientation),
                "file-backed reader should report orientation \(orientation)"
            )
            let dataOrientation = ImageDecoder.exifOrientation(of: try Data(contentsOf: url))
            XCTAssertEqual(
                dataOrientation.rawValue, UInt32(orientation),
                "bytes-backed reader should report orientation \(orientation)"
            )
            let stored = CGSize(width: 80, height: 60)
            let displayed = ImageDecoder.orientedDimensions(stored, for: fileOrientation)
            if [6, 8].contains(orientation) {
                XCTAssertEqual(displayed, CGSize(width: 60, height: 80))
            } else {
                XCTAssertEqual(displayed, stored)
            }
        }
    }

    /// Missing metadata means upright, never a failure.
    func testEXIFOrientationFallsBackToUp() throws {
        let url = try Fixtures.writeGradientPNG(
            width: 80, height: 60, named: "raw-orient-none.png", in: tempDirectory
        )
        XCTAssertEqual(ImageDecoder.exifOrientation(at: url), .up)
        XCTAssertEqual(
            ImageDecoder.exifOrientation(of: Data("not an image".utf8)), .up
        )
    }

    /// Every EXIF orientation must land on the right geometry: 1–4 preserve the axes,
    /// 5–8 swap them. An extent-only check is enough here; direction is pinned below.
    func testApplyingOrientationGeometryForAllEight() {
        let stored = CIImage(color: CIColor(red: 1, green: 0, blue: 0, alpha: 1))
            .cropped(to: CGRect(x: 0, y: 0, width: 80, height: 60))
        let orientations: [CGImagePropertyOrientation] = [
            .up, .upMirrored, .down, .downMirrored,
            .leftMirrored, .left, .rightMirrored, .right,
        ]
        for orientation in orientations {
            let baked = ImageDecoder.applyingEXIFOrientation(orientation, to: stored)
            let size = baked.extent.integral.size
            switch orientation {
            case .leftMirrored, .left, .rightMirrored, .right:
                XCTAssertEqual(size, CGSize(width: 60, height: 80), "\(orientation) should swap axes")
            default:
                XCTAssertEqual(size, CGSize(width: 80, height: 60), "\(orientation) should preserve axes")
            }
        }
    }

    /// Orientation 3 (the upside-down ARW in the report) must actually flip the pixels,
    /// not just preserve the axes.
    func testOrientationThreeFlipsPixelsEndForEnd() throws {
        let red = CIImage(color: CIColor(red: 1, green: 0, blue: 0, alpha: 1))
            .cropped(to: CGRect(x: 0, y: 0, width: 1, height: 1))
        let blueField = CIImage(color: CIColor(red: 0, green: 0, blue: 1, alpha: 1))
            .cropped(to: CGRect(x: 0, y: 0, width: 2, height: 1))
        // Left pixel red, right pixel blue.
        let image = red.composited(over: blueField)

        let before = try Pixels.bytes(of: image)
        XCTAssertGreaterThan(before[0], 200, "sanity: first pixel starts red")

        let flipped = ImageDecoder.applyingEXIFOrientation(.down, to: image)
        XCTAssertEqual(flipped.extent.integral.size, CGSize(width: 2, height: 1))
        let after = try Pixels.bytes(of: flipped)
        XCTAssertLessThan(after[0], 128, "after a 180° turn the first pixel should be blue")
        XCTAssertGreaterThan(after[2], 128)
    }
}

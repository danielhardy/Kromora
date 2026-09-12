import XCTest
import CoreImage
import CoreGraphics
import ImageIO
@testable import KromoraKit

/// `CIRAWFilter` orients `outputImage` itself; `nativeSize` stays sensor-native. Re-baking
/// the ImageIO tag therefore turns a portrait RAW (EXIF 5–8) back into landscape. These pin
/// the shared helpers every RAW decode action goes through, without needing a camera RAW in
/// the checkout. An opt-in local-file case covers a real quarter-turned ARW when present.
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

    /// `CIRAWFilter` already returns display-oriented pixels for tags 5–8. Re-baking that
    /// tag swaps the axes a second time and the canvas shows a portrait RAW as landscape.
    func testAlreadyOrientedPortraitOutputIsNotBakedAgain() {
        let alreadyPortrait = CIImage(color: CIColor(red: 1, green: 0, blue: 0, alpha: 1))
            .cropped(to: CGRect(x: 0, y: 0, width: 60, height: 80))
        let sensor = CGSize(width: 80, height: 60)
        for orientation: CGImagePropertyOrientation in [.left, .right] {
            let result = ImageDecoder.displayOrientedRAWOutput(
                alreadyPortrait, sensorSize: sensor, orientation: orientation
            )
            XCTAssertEqual(
                result.extent.integral.size, CGSize(width: 60, height: 80),
                "\(orientation) must keep an already-portrait RAW output"
            )
            XCTAssertTrue(
                result.extent == alreadyPortrait.extent,
                "\(orientation) must not insert a second orientation node"
            )
        }
    }

    /// A decoder that still emits sensor-native pixels must be baked once so the canvas
    /// matches the filmstrip.
    func testSensorNativePortraitOutputIsBakedOnce() {
        let sensorNative = CIImage(color: CIColor(red: 1, green: 0, blue: 0, alpha: 1))
            .cropped(to: CGRect(x: 0, y: 0, width: 80, height: 60))
        let sensor = CGSize(width: 80, height: 60)
        for orientation: CGImagePropertyOrientation in [.left, .right] {
            let result = ImageDecoder.displayOrientedRAWOutput(
                sensorNative, sensorSize: sensor, orientation: orientation
            )
            XCTAssertEqual(
                result.extent.integral.size, CGSize(width: 60, height: 80),
                "\(orientation) must bake a sensor-native RAW output to portrait"
            )
        }
    }

    /// Landscape tags do not swap axes, so an already-display-oriented output is left alone.
    func testNonSwappingOutputIsNotBakedAgain() {
        let landscape = CIImage(color: CIColor(red: 0, green: 1, blue: 0, alpha: 1))
            .cropped(to: CGRect(x: 0, y: 0, width: 80, height: 60))
        let result = ImageDecoder.displayOrientedRAWOutput(
            landscape, sensorSize: CGSize(width: 80, height: 60), orientation: .down
        )
        XCTAssertEqual(result.extent, landscape.extent)
    }

    /// A real quarter-turned ARW must stay portrait after develop, matching its ImageIO thumbnail.
    func testLocalPortraitRAWDevelopMatchesThumbnailAxes() throws {
        let portrait = Fixtures.localRAWURLs.first { url in
            switch ImageDecoder.exifOrientation(at: url) {
            case .left, .leftMirrored, .right, .rightMirrored: return true
            default: return false
            }
        }
        guard let url = portrait else {
            throw XCTSkip("no quarter-turned local RAW; set KROMORA_RAW_FIXTURE_DIR")
        }
        let orientation = ImageDecoder.exifOrientation(at: url)

        let filter = try XCTUnwrap(CIRAWFilter(imageURL: url))
        filter.scaleFactor = 0.05
        let developed = try XCTUnwrap(
            ImageDecoder.developedImage(from: filter, orientation: orientation)
        )
        XCTAssertGreaterThan(
            developed.extent.height, developed.extent.width,
            "\(url.lastPathComponent) must develop as portrait"
        )

        let pipeline = try XCTUnwrap(RenderPipeline.developedSource(
            ImageSource(url: url, nativeExtent: .zero),
            rawDevelop: .neutral,
            scale: .preview(maxSize: CGSize(width: 400, height: 400))
        ))
        XCTAssertGreaterThan(
            pipeline.extent.height, pipeline.extent.width,
            "pipeline preview develop must keep \(url.lastPathComponent) portrait"
        )

        let thumbnail = try XCTUnwrap(Thumbnails.generate(from: url, maxPixelSize: 200))
        XCTAssertGreaterThan(
            thumbnail.size.height, thumbnail.size.width,
            "filmstrip thumbnail for \(url.lastPathComponent) is the portrait reference"
        )
    }
}

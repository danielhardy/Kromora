import CoreImage
import XCTest
@testable import KromoraKit

/// KRMA-1143: the discovery shader samples the returned matte through `MaskDiscoveryGeometry`.
/// The oracle is the real Core Image geometry graph that places the photograph (and the finished
/// mask): a coordinate-coded raster is carried through it, and the shader's source lookup for an
/// output point must name the same raster coordinate the graph put there.
final class MaskDiscoveryGeometryOracleTests: XCTestCase {
    private let native = CGSize(width: 240, height: 160)

    /// R = x, G = y in upper-left normalized coordinates of the oriented source.
    private func codedRaster() -> CIImage {
        let w = Int(native.width), h = Int(native.height)
        var floats = [Float](repeating: 1, count: w * h * 4)
        for row in 0..<h {
            for column in 0..<w {
                let i = (row * w + column) * 4   // bitmap rows run top-down
                floats[i] = Float((Double(column) + 0.5) / Double(w))
                floats[i + 1] = Float((Double(row) + 0.5) / Double(h))
                floats[i + 2] = 0
            }
        }
        return CIImage(
            bitmapData: Data(bytes: floats, count: floats.count * 4), bytesPerRow: w * 16,
            size: native, format: .RGBAf, colorSpace: nil)
    }

    private func sampler(_ crop: CropAdjustments, _ rotation: ImageRotation)
        throws -> (CGSize, (CGPoint) -> CGPoint) {
        let image = RenderPipeline.applyingGeometry(
            crop, to: RenderPipeline.applyingRotation(rotation, to: codedRaster()))
        let extent = image.extent
        let width = Int(extent.width.rounded()), height = Int(extent.height.rounded())
        var pixels = [Float](repeating: 0, count: width * height * 4)
        let context = CIContext(options: [.workingColorSpace: NSNull(), .outputColorSpace: NSNull()])
        context.render(image, toBitmap: &pixels, rowBytes: width * 16,
                       bounds: extent, format: .RGBAf, colorSpace: nil)
        return (extent.size, { point in
            let x = min(max(Int(point.x * Double(width)), 0), width - 1)
            let y = min(max(Int(point.y * Double(height)), 0), height - 1)
            let i = (y * width + x) * 4
            return CGPoint(x: Double(pixels[i]), y: Double(pixels[i + 1]))
        })
    }

    func testDiscoverySourceLookupMatchesCoreImageGeometryWithCropAndRotation() throws {
        var combined = CropAdjustments.neutral
        combined.straightenAngle = 6
        combined.normalizedRect = CGRect(x: 0.15, y: 0.2, width: 0.6, height: 0.55)
        var flipped = combined
        flipped.flipHorizontal = true
        var keystone = combined
        keystone.verticalPerspective = 0.2
        var both = combined
        both.verticalPerspective = -0.15
        both.horizontalPerspective = 0.2
        var straightenOnly = CropAdjustments.neutral
        straightenOnly.straightenAngle = -9
        for (name, crop) in [("neutral", CropAdjustments.neutral), ("combined", combined), ("flipped", flipped),
                             ("keystone", keystone), ("both", both), ("straighten", straightenOnly)] {
            for rotation in ImageRotation.allCases {
                let (extent, truth) = try sampler(crop, rotation)
                let mapping = GeometryPointMapping(sourceSize: native, rotation: rotation, crop: crop)
                XCTAssertEqual(mapping.outputSize.width, extent.width, accuracy: 1, name)
                let geometry = try XCTUnwrap(MaskDiscoveryGeometry(
                    mapping: mapping, navigation: CanvasNavigation(),
                    viewportSize: CGSize(width: 800, height: 600), backingScale: 2))
                let rect = geometry.cropRect
                for fx in [0.2, 0.5, 0.8] {
                    for fy in [0.25, 0.5, 0.75] {
                        let output = CGPoint(x: rect.minX + fx * rect.width,
                                             y: rect.minY + fy * rect.height)
                        let expected = truth(output)
                        let actual = geometry.sourcePoint(forOutput: output)
                        XCTAssertEqual(actual.x, expected.x, accuracy: 0.02,
                                       "\(name) \(rotation) x @ \(output)")
                        XCTAssertEqual(actual.y, expected.y, accuracy: 0.02,
                                       "\(name) \(rotation) y @ \(output)")
                    }
                }
            }
        }
    }
}

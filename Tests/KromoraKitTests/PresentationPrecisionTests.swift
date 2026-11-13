import CoreImage
import Metal
import XCTest

@testable import KromoraKit

/// The settled presentation path must keep more than 8 bits per channel through the drawable, or
/// smooth gradients band on the canvas while the 16-bit export does not.
@MainActor
final class PresentationPrecisionTests: XCTestCase {
    func testPresentationPixelFormatIsHalfFloat() {
        XCTAssertEqual(PreviewSurface.presentationPixelFormat, .rgba16Float)
    }

    func testShallowGradientSurvivesPresentationFormatWithoutEightBitBanding() throws {
        let width = 1024
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: PreviewSurface.presentationPixelFormat, width: width, height: 1,
            mipmapped: false)
        descriptor.usage = [.shaderRead, .shaderWrite, .renderTarget]
        descriptor.storageMode = .shared
        let texture = try XCTUnwrap(
            RenderEngine.presentationDevice.makeTexture(descriptor: descriptor))

        // A ramp spanning ~2 eight-bit codes (0.500 to 0.508) would collapse to <= 3 values at 8 bits.
        let ramp = CIFilter(name: "CILinearGradient", parameters: [
            "inputPoint0": CIVector(x: 0, y: 0), "inputPoint1": CIVector(x: CGFloat(width), y: 0),
            "inputColor0": CIColor(red: 0.5, green: 0.5, blue: 0.5),
            "inputColor1": CIColor(red: 0.508, green: 0.508, blue: 0.508),
        ])!.outputImage!
        let commandBuffer = try XCTUnwrap(RenderEngine.presentationQueue.makeCommandBuffer())
        RenderEngine.presentationContext.render(
            ramp, to: texture, commandBuffer: commandBuffer,
            bounds: CGRect(x: 0, y: 0, width: width, height: 1),
            colorSpace: WorkingSpace.sRGB.cgColorSpace)
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        var halves = [UInt16](repeating: 0, count: width * 4)
        halves.withUnsafeMutableBytes {
            texture.getBytes(
                $0.baseAddress!, bytesPerRow: width * 8,
                from: MTLRegionMake2D(0, 0, width, 1), mipmapLevel: 0)
        }
        let reds = Set(stride(from: 0, to: halves.count, by: 4).map { halves[$0] })
        XCTAssertGreaterThan(reds.count, 16, "ramp collapsed to \(reds.count) distinct levels")
    }

    func testPresentationPipelinesExistForDrawableAndReadbackTargets() {
        let coordinator = PreviewSurfaceView.Coordinator()
        XCTAssertTrue(coordinator.hasPresentationPipeline)
    }
}

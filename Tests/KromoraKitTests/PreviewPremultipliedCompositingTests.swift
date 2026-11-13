import Metal
import XCTest

@testable import KromoraKit

/// Core Image output is premultiplied, so the presentation shader must scale all four channels by
/// the transition alpha and the pipeline must blend with `.one` / `.oneMinusSourceAlpha`.
@MainActor
final class PreviewPremultipliedCompositingTests: XCTestCase {

    /// Mirrors `PreviewQuadUniforms` in PreviewSurface.metal (Metal float2 alignment is 8 bytes).
    private struct QuadUniforms {
        var transformOrigin = SIMD2<Float>(0, 0)
        var imageOrigin = SIMD2<Float>(0, 0)
        var imageSize = SIMD2<Float>(4, 4)
        var scale: Float = 1
        var viewportSize = SIMD2<Float>(4, 4)
        var rotationCenter = SIMD2<Float>(2, 2)
        var rotationRadians: Float = 0
        var alpha: Float = 1
    }

    private struct QuadVertex {
        var position: SIMD2<Float>
        var texcoord: SIMD2<Float>
    }

    /// Draws a uniform premultiplied texel over an opaque backdrop and returns the BGRA result.
    private func composite(
        texel: SIMD4<UInt8>, backdrop: SIMD4<Double>, alpha: Float
    ) throws -> [UInt8] {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let library = try device.makeLibrary(
            URL: XCTUnwrap(KromoraKitResourceBundle.presentationMetallibURL()))
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "preview_quad_vertex")
        descriptor.fragmentFunction = library.makeFunction(name: "preview_quad_fragment")
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        PreviewSurfaceView.Coordinator.configurePremultipliedBlending(
            descriptor.colorAttachments[0])
        let pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        let queue = try XCTUnwrap(device.makeCommandQueue())

        let sourceDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: 4, height: 4, mipmapped: false)
        sourceDescriptor.storageMode = .shared
        sourceDescriptor.usage = .shaderRead
        let source = try XCTUnwrap(device.makeTexture(descriptor: sourceDescriptor))
        let pixels = [UInt8](
            Array(repeating: [texel.z, texel.y, texel.x, texel.w], count: 16).joined())
        pixels.withUnsafeBytes {
            source.replace(region: MTLRegionMake2D(0, 0, 4, 4), mipmapLevel: 0,
                           withBytes: $0.baseAddress!, bytesPerRow: 16)
        }
        let targetDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: 4, height: 4, mipmapped: false)
        targetDescriptor.storageMode = .shared
        targetDescriptor.usage = [.renderTarget, .shaderRead]
        let target = try XCTUnwrap(device.makeTexture(descriptor: targetDescriptor))

        let sampler = MTLSamplerDescriptor()
        sampler.minFilter = .nearest
        sampler.magFilter = .nearest
        let samplerState = try XCTUnwrap(device.makeSamplerState(descriptor: sampler))

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColorMake(
            backdrop.x, backdrop.y, backdrop.z, backdrop.w)
        let command = try XCTUnwrap(queue.makeCommandBuffer())
        let encoder = try XCTUnwrap(command.makeRenderCommandEncoder(descriptor: pass))
        var vertices = [
            QuadVertex(position: SIMD2(0, 0), texcoord: SIMD2(0, 0)),
            QuadVertex(position: SIMD2(1, 0), texcoord: SIMD2(1, 0)),
            QuadVertex(position: SIMD2(0, 1), texcoord: SIMD2(0, 1)),
            QuadVertex(position: SIMD2(1, 1), texcoord: SIMD2(1, 1)),
        ]
        var uniforms = QuadUniforms(alpha: alpha)
        encoder.setRenderPipelineState(pipeline)
        encoder.setVertexBytes(&vertices, length: MemoryLayout<QuadVertex>.stride * 4, index: 0)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<QuadUniforms>.stride, index: 1)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<QuadUniforms>.stride, index: 1)
        encoder.setFragmentTexture(source, index: 0)
        encoder.setFragmentSamplerState(samplerState, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
        command.commit()
        command.waitUntilCompleted()
        XCTAssertEqual(command.status, .completed)
        var bytes = [UInt8](repeating: 0, count: 64)
        bytes.withUnsafeMutableBytes {
            target.getBytes($0.baseAddress!, bytesPerRow: 16,
                            from: MTLRegionMake2D(0, 0, 4, 4), mipmapLevel: 0)
        }
        return Array(bytes[20..<24])  // pixel (1, 1) as B, G, R, A
    }

    func testTranslucentTexelsAreNotDarkenedByASecondAlphaMultiply() throws {
        // Premultiplied 50% white over an opaque black backdrop: expected 0.5 gray.
        // Straight-alpha blending would give 0.25.
        for (alpha, expected) in [(Float(1), 128.0), (0.75, 96.0), (0.5, 64.0), (0.25, 32.0), (0, 0)] {
            let out = try composite(
                texel: SIMD4(128, 128, 128, 128), backdrop: SIMD4(0, 0, 0, 1), alpha: alpha)
            for channel in 0..<3 {
                XCTAssertEqual(Double(out[channel]), expected, accuracy: 2,
                               "alpha \(alpha) channel \(channel)")
            }
            XCTAssertEqual(Double(out[3]), 255, accuracy: 1, "opaque backdrop stays opaque")
        }
    }

    func testOpaqueTexelCrossfadeIsALinearMixWithTheBackdrop() throws {
        // Opaque white over opaque black at transition alpha p must yield p, not p squared.
        for alpha in [Float(0.2), 0.5, 0.8] {
            let out = try composite(
                texel: SIMD4(255, 255, 255, 255), backdrop: SIMD4(0, 0, 0, 1), alpha: alpha)
            XCTAssertEqual(Double(out[2]), Double(alpha) * 255, accuracy: 2, "alpha \(alpha)")
        }
    }
}

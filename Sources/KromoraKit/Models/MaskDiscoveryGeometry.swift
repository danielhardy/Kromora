import CoreGraphics
import Foundation
import simd

/// The value-only ABI shared with MaskDiscovery.metal; float4 fields keep alignment explicit.
struct MaskDiscoveryUniforms {
    var imageRect: SIMD4<Float>
    var cropRect: SIMD4<Float>
    var sourceX: SIMD4<Float>
    var sourceY: SIMD4<Float>
    var sourceW: SIMD4<Float>
    var timing: SIMD4<Float>
    var display: SIMD4<Float>
}

/// Inverse projective mapping lets the small presentation shader sample the original returned
/// mask through rotation, flips, straighten, perspective, crop, and canvas navigation. Geometry
/// is evaluated only when presentation inputs change, never per pixel on the CPU.
struct MaskDiscoveryGeometry {
    let imageRect: CGRect
    let cropRect: CGRect
    let sourceX: SIMD4<Float>
    let sourceY: SIMD4<Float>
    let sourceW: SIMD4<Float>

    init?(mapping: GeometryPointMapping, navigation: CanvasNavigation,
          viewportSize: CGSize, backingScale: CGFloat) {
        let canvas = CanvasMaskTransform(
            sourceSize: mapping.outputSize, crop: mapping.crop, navigation: navigation,
            viewportSize: viewportSize, backingScale: backingScale)
        guard let rect = canvas.viewportRect(forSourceNormalized: canvas.cropRect),
              rect.width > 0, rect.height > 0 else { return nil }
        let corners = [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0),
                       CGPoint(x: 1, y: 1), CGPoint(x: 0, y: 1)]
            .compactMap { mapping.inverse($0) }
        guard corners.count == 4 else { return nil }
        let p = corners.map { SIMD2<Double>(Double($0.x), Double($0.y)) }
        let d1 = p[1] - p[2], d2 = p[3] - p[2]
        let d3 = p[0] - p[1] + p[2] - p[3]
        let determinant = d1.x * d2.y - d2.x * d1.y
        guard abs(determinant) > 1e-12 else { return nil }
        let g = (d3.x * d2.y - d2.x * d3.y) / determinant
        let h = (d1.x * d3.y - d3.x * d1.y) / determinant
        sourceX = SIMD4(Float(p[1].x - p[0].x + g * p[1].x),
                        Float(p[3].x - p[0].x + h * p[3].x), Float(p[0].x), 0)
        sourceY = SIMD4(Float(p[1].y - p[0].y + g * p[1].y),
                        Float(p[3].y - p[0].y + h * p[3].y), Float(p[0].y), 0)
        sourceW = SIMD4(Float(g), Float(h), 1, 0)
        imageRect = rect
        cropRect = canvas.cropRect
    }

    func sourcePoint(forOutput point: CGPoint) -> CGPoint {
        let p = SIMD4<Float>(Float(point.x), Float(point.y), 1, 0)
        let w = simd_dot(sourceW, p)
        return CGPoint(x: Double(simd_dot(sourceX, p) / w),
                       y: Double(simd_dot(sourceY, p) / w))
    }
}

/// Small, disposable display data; the analysis store retains the original precision and size.
struct MaskDiscoveryRaster: Sendable {
    let size: PixelDimensions
    let bytes: [UInt8]

    static func make(from pixels: NormalizedMask) throws -> Self {
        let scale = min(1, 512 / Double(max(pixels.size.width, pixels.size.height)))
        let size = PixelDimensions(
            width: max(1, Int(Double(pixels.size.width) * scale)),
            height: max(1, Int(Double(pixels.size.height) * scale)))
        try Task.checkCancellation()
        let values = try MaskOperations.resized(pixels, to: size).values
        return Self(size: size, bytes: values.map { UInt8((min(max($0, 0), 1) * 255).rounded()) })
    }
}

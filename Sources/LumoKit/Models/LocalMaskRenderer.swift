import CoreImage
import CoreGraphics
import Foundation

/// Actor-confined conversion of sendable mask payloads into Core Image. The resolver never sees
/// this type and no `CIContext` is created here; RenderEngineResources owns the instance and the
/// engine's one processing context evaluates the returned graphs.
final class LocalMaskRenderer {
    static let version = 3

    private let analyticKernel: CIKernel? = CIKernel(source: """
    kernel vec4 localAnalyticMask(
        sampler image, vec4 geometry, vec4 firstPoint, vec4 secondPoint,
        vec4 transform, vec4 radial, vec4 controls
    ) {
        vec2 coordinate = samplerCoord(image);
        vec2 normalized = (coordinate - geometry.xy) / max(geometry.zw, vec2(0.00001));
        normalized.y = 1.0 - normalized.y;

        // Transform around the source centre. Translation is normalized source-space movement.
        vec2 shifted = normalized - vec2(0.5);
        float cosine = cos(-transform.z);
        float sine = sin(-transform.z);
        shifted = vec2(shifted.x * cosine - shifted.y * sine,
                       shifted.x * sine + shifted.y * cosine);
        shifted /= max(transform.xy, vec2(0.00001));
        normalized = shifted + vec2(0.5) - transform.wz;

        float alpha;
        if (controls.x < 0.5) {
            vec2 direction = secondPoint.xy - firstPoint.xy;
            float denominator = max(dot(direction, direction), 0.0000001);
            float projection = dot(normalized - firstPoint.xy, direction) / denominator;
            // This is the GPU form of LinearGradientMaskMath.smoothstep(0, 1, projection).
            // The persisted endpoints encode the falloff width, so no resolution-dependent
            // feather/raster value is introduced here.
            alpha = smoothstep(0.0, 1.0, projection);
            alpha *= controls.y;
        } else {
            vec2 delta = normalized - firstPoint.xy;
            // Rotation is defined in source-pixel space. Scaling normalized x/y by the
            // requested extent before rotating keeps an ellipse aligned on non-square sources
            // at interactive, preview, and export resolutions.
            delta *= geometry.zw;
            float radialCosine = cos(radial.z);
            float radialSine = sin(radial.z);
            delta = vec2(delta.x * radialCosine + delta.y * radialSine,
                         -delta.x * radialSine + delta.y * radialCosine);
            float distance = length(delta / max(radial.xy, vec2(0.00001)));
            float inner = max(0.0, 1.0 - radial.w);
            if (distance <= inner) {
                alpha = 1.0;
            } else if (distance >= 1.0) {
                alpha = 0.0;
            } else {
                alpha = 1.0 - smoothstep(inner, 1.0, distance);
            }
            if (controls.z < 0.5) { alpha = 1.0 - alpha; }
            alpha *= controls.y;
        }
        return vec4(0.0, 0.0, 0.0, clamp(alpha, 0.0, 1.0));
    }
    """)

    private let invertKernel: CIKernel? = CIKernel(source: """
    kernel vec4 localInvertMask(sampler image) {
        vec4 pixel = sample(image, samplerCoord(image));
        return vec4(0.0, 0.0, 0.0, 1.0 - clamp(pixel.a, 0.0, 1.0));
    }
    """)

    private let combineKernel: CIKernel? = CIKernel(source: """
    kernel vec4 localCombineMask(sampler current, sampler next, vec4 controls) {
        float a = clamp(sample(current, samplerCoord(current)).a, 0.0, 1.0);
        float b = clamp(sample(next, samplerCoord(next)).a, 0.0, 1.0);
        float result;
        if (controls.x < 0.5) {
            result = b;                 // replace
        } else if (controls.x < 1.5) {
            result = max(a, b);         // add
        } else if (controls.x < 2.5) {
            result = a * (1.0 - b);     // subtract
        } else {
            result = min(a, b);         // intersect
        }
        return vec4(0.0, 0.0, 0.0, clamp(result, 0.0, 1.0));
    }
    """)

    func image(
        for payload: LocalMaskPayload,
        extent: CGRect,
        transform: LocalMaskRenderTransform
    ) -> CIImage? {
        let dimensions = PixelDimensions(width: Int(extent.width), height: Int(extent.height))
        guard extent.width.isFinite, extent.height.isFinite,
              extent.width > 0, extent.height > 0,
              payload.targetSize == dimensions else { return nil }

        switch payload.descriptor {
        case .raster(let mask):
            return rasterImage(mask, extent: extent)
        case .brush(let brush):
            return brushImage(brush, dimensions: dimensions, extent: extent, transform: transform)
        case .linear(let definition):
            let points = [transformPoint(definition.zeroStrengthPoint, transform),
                          transformPoint(definition.fullStrengthPoint, transform)]
            return analyticImage(
                extent: extent, firstPoint: points[0], secondPoint: points[1],
                transform: .identity, radial: CIVector(x: 0, y: 0, z: 0, w: 0),
                controls: CIVector(x: 0, y: definition.density, z: 1, w: 0)
            )
        case .radial(let definition):
            let center = transformPoint(definition.center, transform)
            let radii = CGSize(
                width: max(0.0001, definition.horizontalRadius * abs(transform.scaleX) * extent.width),
                height: max(0.0001, definition.verticalRadius * abs(transform.scaleY) * extent.height)
            )
            return analyticImage(
                extent: extent, firstPoint: center, secondPoint: .zero,
                transform: .identity,
                radial: CIVector(
                    x: radii.width, y: radii.height,
                    z: definition.rotation + transform.rotation, w: definition.feather),
                controls: CIVector(x: 1, y: definition.density, z: definition.isInside ? 1 : 0, w: 0)
            )
        }
    }

    func inverted(_ image: CIImage, extent: CGRect) -> CIImage {
        invertKernel?.apply(extent: extent, roiCallback: { _, rect in rect }, arguments: [image])?
            .cropped(to: extent) ?? image
    }

    func combined(_ current: CIImage, with next: CIImage, mode: MaskCombineMode, extent: CGRect) -> CIImage {
        let value: CGFloat
        switch mode {
        case .replace: value = 0
        case .add: value = 1
        case .subtract: value = 2
        case .intersect: value = 3
        }
        return combineKernel?.apply(
            extent: extent,
            roiCallback: { _, rect in rect },
            arguments: [current, next, CIVector(x: value, y: 0, z: 0, w: 0)]
        )?.cropped(to: extent) ?? current
    }

    func emptyMask(extent: CGRect) -> CIImage {
        CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0)).cropped(to: extent)
    }

    private func analyticImage(
        extent: CGRect,
        firstPoint: CGPoint,
        secondPoint: CGPoint,
        transform: LocalMaskRenderTransform,
        radial: CIVector,
        controls: CIVector
    ) -> CIImage? {
        analyticKernel?.apply(
            extent: extent,
            roiCallback: { _, rect in rect },
            arguments: [
                CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0)).cropped(to: extent),
                CIVector(x: extent.minX, y: extent.minY, z: extent.width, w: extent.height),
                CIVector(x: firstPoint.x, y: firstPoint.y, z: 0, w: 0),
                CIVector(x: secondPoint.x, y: secondPoint.y, z: 0, w: 0),
                CIVector(x: transform.scaleX, y: transform.scaleY,
                         z: transform.rotation, w: transform.translationY),
                radial,
                controls,
            ]
        )?.cropped(to: extent)
    }

    private func rasterImage(_ mask: NormalizedMask, extent: CGRect) -> CIImage? {
        guard mask.size.width > 0, mask.size.height > 0 else { return nil }
        var pixels = [Float](repeating: 0, count: mask.values.count * 4)
        let width = mask.size.width
        let height = mask.size.height
        for y in 0..<height {
            // Persisted mask rows are upper-left oriented; Core Image bitmap rows are bottom-up.
            let sourceRow = height - 1 - y
            for x in 0..<width {
                let value = mask.values[sourceRow * width + x]
                let index = (y * width + x) * 4
                pixels[index + 3] = value
            }
        }
        let data = pixels.withUnsafeBytes { Data($0) }
        let image = CIImage(
            bitmapData: data, bytesPerRow: width * 4 * MemoryLayout<Float>.size,
            size: extent.size, format: .RGBAf, colorSpace: nil
        )
        return image.transformed(by: CGAffineTransform(translationX: extent.minX, y: extent.minY))
    }

    private func brushImage(
        _ definition: BrushMaskDefinition,
        dimensions: PixelDimensions,
        extent: CGRect,
        transform: LocalMaskRenderTransform
    ) -> CIImage? {
        guard dimensions.width > 0, dimensions.height > 0 else { return nil }
        var values = [Float](repeating: 0, count: dimensions.width * dimensions.height)
        let shorterSide = Double(min(dimensions.width, dimensions.height))
        for stroke in definition.strokes where !stroke.samples.isEmpty && stroke.radius > 0 {
            let transformed = stroke.samples.map { transformPoint($0.point, transform) }
            let radius = stroke.radius * shorterSide
            for y in 0..<dimensions.height {
                for x in 0..<dimensions.width {
                    let point = CGPoint(
                        x: (Double(x) + 0.5) / Double(dimensions.width),
                        y: (Double(y) + 0.5) / Double(dimensions.height)
                    )
                    let distance = closestDistancePixels(point, to: transformed,
                                                         width: dimensions.width, height: dimensions.height)
                    guard distance < radius else { continue }
                    let inner = radius * (1 - stroke.feather)
                    let falloff = distance <= inner ? 1 :
                        1 - smoothstep(inner, radius, distance)
                    let pressure = transformed.isEmpty ? 1 :
                        max(0, min(1, stroke.samples[0].pressure ?? 1))
                    let deposited = max(0, min(1, stroke.flow * pressure * falloff))
                    let index = y * dimensions.width + x
                    values[index] = Float(min(stroke.density,
                        1 - (1 - Double(values[index])) * (1 - deposited)))
                }
            }
        }
        let mask = try? NormalizedMask(size: dimensions, values: values)
        return mask.flatMap { rasterImage($0, extent: extent) }
    }

    private func transformPoint(_ point: CGPoint, _ transform: LocalMaskRenderTransform) -> CGPoint {
        let shifted = CGPoint(x: (point.x - 0.5) * transform.scaleX,
                              y: (point.y - 0.5) * transform.scaleY)
        let cosine = cos(transform.rotation)
        let sine = sin(transform.rotation)
        return CGPoint(
            x: shifted.x * cosine - shifted.y * sine + 0.5 + transform.translationX,
            y: shifted.x * sine + shifted.y * cosine + 0.5 + transform.translationY
        )
    }

    private func closestDistancePixels(
        _ point: CGPoint, to samples: [CGPoint], width: Int, height: Int
    ) -> Double {
        guard !samples.isEmpty else { return .greatestFiniteMagnitude }
        if samples.count == 1 {
            return distancePixels(point, samples[0], width: width, height: height)
        }
        var result = Double.greatestFiniteMagnitude
        for pair in zip(samples, samples.dropFirst()) {
            let ax = pair.0.x * Double(width), ay = pair.0.y * Double(height)
            let bx = pair.1.x * Double(width), by = pair.1.y * Double(height)
            let px = point.x * Double(width), py = point.y * Double(height)
            let dx = bx - ax, dy = by - ay
            let lengthSquared = dx * dx + dy * dy
            let t = lengthSquared > 0 ? max(0, min(1, ((px - ax) * dx + (py - ay) * dy) / lengthSquared)) : 0
            let cx = ax + t * dx, cy = ay + t * dy
            result = min(result, hypot(px - cx, py - cy))
        }
        return result
    }

    private func distancePixels(_ lhs: CGPoint, _ rhs: CGPoint, width: Int, height: Int) -> Double {
        hypot((lhs.x - rhs.x) * Double(width), (lhs.y - rhs.y) * Double(height))
    }

    private func smoothstep(_ edge0: Double, _ edge1: Double, _ value: Double) -> Double {
        guard edge1 > edge0 else { return value < edge1 ? 1 : 0 }
        let t = max(0, min(1, (value - edge0) / (edge1 - edge0)))
        return t * t * (3 - 2 * t)
    }
}

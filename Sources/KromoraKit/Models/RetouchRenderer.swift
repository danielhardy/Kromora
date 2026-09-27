import CoreImage
import CoreGraphics

/// Builds lazy, region-local Core Image graphs inside the render engine's actor boundary.
enum RetouchRenderer {
    static func apply(
        _ settings: RetouchSettings,
        to image: CIImage,
        sourceSize: CGSize,
        maskRenderer: LocalMaskRenderer
    ) -> CIImage {
        guard !settings.isIdentity, image.extent.width > 0, image.extent.height > 0,
              sourceSize.width > 0, sourceSize.height > 0 else { return image }
        var result = image
        for spot in settings.spots where !spot.isIdentity {
            // Remove's field producer is supplied by KRMA-662. Until one is attached, do not
            // invent a translated source for Remove.
            guard spot.mode != .remove, let source = spot.source else { continue }
            let maskStroke = BrushStroke(
                id: spot.id, samples: spot.region.samples, radius: spot.region.radius,
                feather: spot.feather, flow: 1, density: 1
            )
            let maskPayload = LocalMaskPayload(
                sourceFingerprint: "retouch", definitionHash: RenderCacheHash.digest(spot.region),
                targetSize: PixelDimensions(width: Int(sourceSize.width), height: Int(sourceSize.height)),
                quality: .fullResolution, descriptor: .brush(BrushMaskDefinition(strokes: [maskStroke]))
            )
            guard let fullMask = maskRenderer.image(
                for: maskPayload, extent: image.extent, transform: .identity
            ) else { continue }
            let holePayload = LocalMaskPayload(
                sourceFingerprint: "retouch", definitionHash: RenderCacheHash.digest(spot.region) + ":hole",
                targetSize: PixelDimensions(width: Int(sourceSize.width), height: Int(sourceSize.height)),
                quality: .fullResolution,
                descriptor: .brush(BrushMaskDefinition(strokes: [BrushStroke(
                    id: spot.id, samples: spot.region.samples, radius: spot.region.radius,
                    feather: 0, flow: 1, density: 1
                )]))
            )
            guard let holeMask = maskRenderer.image(
                for: holePayload, extent: image.extent, transform: .identity
            ) else { continue }
            let sourceOffset = source.offset
            let radius = CGFloat(spot.region.radius) * min(image.extent.width, image.extent.height)
            let bounds = workBounds(for: spot, extent: image.extent)
            guard bounds.width > 0, bounds.height > 0 else { continue }
            let destination = result.cropped(to: bounds)
            let dx = sourceOffset.dx * image.extent.width
            let dy = sourceOffset.dy * image.extent.height
            let fill = result.transformed(by: CGAffineTransform(translationX: -dx, y: -dy))
                .cropped(to: bounds)
            let mask = fullMask.cropped(to: bounds).applyingFilter("CIColorMatrix", parameters: [
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: spot.opacity)
            ]).cropped(to: bounds)
            let effect = spot.mode == .heal
                ? healedFill(fill, destination: destination, mask: holeMask.cropped(to: bounds), bounds: bounds, radius: radius)
                : fill
            result = blend(effect, over: result, mask: mask, bounds: bounds)
        }
        for eye in settings.eyes where !eye.isIdentity {
            let center = CGPoint(x: image.extent.minX + eye.center.x * image.extent.width,
                                 y: image.extent.maxY - eye.center.y * image.extent.height)
            let rx = max(1, CGFloat(eye.radiusX) * image.extent.width)
            let ry = max(1, CGFloat(eye.radiusY) * image.extent.height)
            let pupil = min(rx, ry) * CGFloat(eye.pupilSize / 100) * 0.72
            let corrected: CIImage
            switch eye.kind {
            case .human:
                corrected = result.applyingFilter("CIColorMatrix", parameters: [
                    "inputRVector": CIVector(x: 0.35, y: 0.65, z: 0, w: 0)
                ])
            case .pet:
                corrected = result.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0.12])
            }
            let darkened = corrected.applyingFilter("CIColorControls", parameters: [
                kCIInputBrightnessKey: -(eye.darken / 100) * 0.45,
                kCIInputContrastKey: 1.05
            ]).cropped(to: image.extent)
            let mask = ellipseMask(center: center, radiusX: max(1, pupil), radiusY: max(1, pupil),
                                   feather: 0.3, opacity: CGFloat(eye.darken / 100), extent: image.extent)
            result = blend(darkened, over: result, mask: mask, bounds: image.extent)
        }
        return result
    }

    static func workBounds(for spot: RetouchSpot, extent: CGRect) -> CGRect {
        let shortSide = min(extent.width, extent.height)
        let radius = CGFloat(spot.region.radius) * shortSide
        let padding = max(8, radius * 4)
        let points = spot.region.samples.map { sample in
            CGPoint(x: extent.minX + sample.point.x * extent.width,
                    y: extent.maxY - sample.point.y * extent.height)
        }
        guard let minX = points.map(\.x).min(), let maxX = points.map(\.x).max(),
              let minY = points.map(\.y).min(), let maxY = points.map(\.y).max() else { return .null }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
            .insetBy(dx: -radius - padding, dy: -radius - padding).intersection(extent)
    }

    /// Pull/push normalized convolution is driven by weights that are exactly zero in the hole.
    /// Thus no destination pixel inside the defect can contribute to the correction field.
    private static func healedFill(
        _ fill: CIImage, destination: CIImage, mask: CIImage, bounds: CGRect, radius: CGFloat
    ) -> CIImage {
        guard let pull = CIKernelLibrary.kernel(named: "retouchPull"),
              let push = CIKernelLibrary.kernel(named: "retouchPush") else { return fill }
        let exteriorWeight = mask.cropped(to: bounds)
        let difference = pull.apply(
            extent: bounds, roiCallback: { _, rect in rect },
            arguments: [destination, fill, exteriorWeight]
        ) ?? fill
        var levels = [difference]
        for _ in 1..<5 {
            guard let previous = levels.last else { break }
            let levelExtent = CGRect(
                x: bounds.minX, y: bounds.minY,
                width: max(1, previous.extent.width / 2),
                height: max(1, previous.extent.height / 2)
            )
            levels.append(downsample(previous, to: levelExtent))
        }
        guard let coarsest = levels.last else { return fill }
        var correction = push.apply(
            extent: coarsest.extent, roiCallback: { _, rect in rect },
            arguments: [zeroImage(coarsest.extent), zeroImage(coarsest.extent), coarsest, coarsest]
        ) ?? zeroImage(coarsest.extent)
        if levels.count > 1 {
            for index in stride(from: levels.count - 2, through: 0, by: -1) {
                let level = levels[index]
                let coarse = upsample(correction, to: level.extent)
                correction = push.apply(
                    extent: level.extent, roiCallback: { _, rect in rect },
                    arguments: [zeroImage(level.extent), coarse, level, level]
                ) ?? coarse
            }
        }
        let membrane = push.apply(
            extent: bounds, roiCallback: { _, rect in rect },
            arguments: [fill, correction, zeroImage(bounds), zeroImage(bounds)]
        ) ?? fill
        return membrane.cropped(to: bounds)
    }

    private static func zeroImage(_ extent: CGRect) -> CIImage {
        CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0)).cropped(to: extent)
    }

    private static func downsample(_ image: CIImage, to extent: CGRect) -> CIImage {
        let blurred = image.clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 0.8])
            .cropped(to: image.extent)
        let transform = CGAffineTransform(
            a: 0.5, b: 0, c: 0, d: 0.5,
            tx: extent.minX - image.extent.minX * 0.5,
            ty: extent.minY - image.extent.minY * 0.5
        )
        return blurred.transformed(by: transform).cropped(to: extent)
    }

    private static func upsample(_ image: CIImage, to extent: CGRect) -> CIImage {
        let transform = CGAffineTransform(
            a: 2, b: 0, c: 0, d: 2,
            tx: extent.minX - image.extent.minX * 2,
            ty: extent.minY - image.extent.minY * 2
        )
        return image.transformed(by: transform).cropped(to: extent)
    }

    private static func ellipseMask(
        center: CGPoint, radiusX: CGFloat, radiusY: CGFloat, feather: CGFloat,
        opacity: CGFloat, extent: CGRect
    ) -> CIImage {
        let innerX = max(0.5, radiusX * (1 - feather))
        let innerY = max(0.5, radiusY * (1 - feather))
        let gradient = CIFilter(name: "CIRadialGradient")!
        gradient.setValue(CIVector(cgPoint: center), forKey: "inputCenter")
        gradient.setValue(innerX, forKey: "inputRadius0")
        gradient.setValue(max(innerX + 0.5, radiusX), forKey: "inputRadius1")
        gradient.setValue(CIColor.white, forKey: "inputColor0")
        gradient.setValue(CIColor.black, forKey: "inputColor1")
        let base = gradient.outputImage?.cropped(to: extent) ?? CIImage(color: .black).cropped(to: extent)
        let scaled = base.transformed(by: CGAffineTransform(translationX: 0, y: center.y)
            .scaledBy(x: 1, y: innerX / innerY).translatedBy(x: 0, y: -center.y)).cropped(to: extent)
        return scaled.applyingFilter("CIColorMatrix", parameters: [
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: opacity)
        ]).cropped(to: extent)
    }

    private static func blend(_ effect: CIImage, over input: CIImage, mask: CIImage, bounds: CGRect) -> CIImage {
        guard let kernel = CIKernelLibrary.kernel(named: "retouchMembraneApply") else { return input }
        guard let result = kernel.apply(
            extent: bounds, roiCallback: { _, rect in rect }, arguments: [input, effect, mask]
        )?.cropped(to: bounds) else { return input }
        return result.composited(over: input)
    }
}

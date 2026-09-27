import CoreImage
import CoreGraphics

/// Builds lazy Core Image graphs for editable retouch recipes. This stays inside the render
/// engine's actor boundary; documents and render requests only carry Codable values.
enum RetouchRenderer {
    static func apply(
        _ settings: RetouchSettings,
        to image: CIImage,
        sourceSize: CGSize,
        rotation: ImageRotation,
        crop: CropAdjustments
    ) -> CIImage {
        guard !settings.isIdentity, image.extent.width > 0, image.extent.height > 0,
              sourceSize.width > 0, sourceSize.height > 0 else { return image }
        let mapping = GeometryPointMapping(sourceSize: sourceSize, rotation: rotation, crop: crop)
        var result = image
        for spot in settings.spots where !spot.isIdentity {
            let points: [CGPoint]
            switch spot.shape {
            case .circle(let center): points = [center]
            case .stroke(let stroke): points = stroke
            }
            for point in points {
                guard let center = mapping.forward(point),
                      let scale = mapping.forwardRadiusScale(at: point), scale.isFinite else { continue }
                let radius = CGFloat(spot.radius) * min(image.extent.width, image.extent.height) * scale
                guard radius >= 0.5 else { continue }
                let source = CGPoint(
                    x: center.x + spot.sourceOffset.dx,
                    y: center.y + spot.sourceOffset.dy
                )
                let sourceCI = CGPoint(
                    x: image.extent.minX + source.x * image.extent.width,
                    y: image.extent.maxY - source.y * image.extent.height
                )
                let destinationCI = CGPoint(
                    x: image.extent.minX + center.x * image.extent.width,
                    y: image.extent.maxY - center.y * image.extent.height
                )
                let patch = image.transformed(by: CGAffineTransform(
                    translationX: destinationCI.x - sourceCI.x,
                    y: destinationCI.y - sourceCI.y
                )).cropped(to: image.extent)
                let mask = featheredDisk(
                    center: destinationCI, radius: radius,
                    feather: CGFloat(spot.feather), opacity: CGFloat(spot.opacity), extent: image.extent
                )
                // Heal currently uses the same sampled patch as clone with a broader soft edge;
                // retaining mode in the recipe leaves room for a dedicated texture synthesis
                // kernel without changing document compatibility.
                result = blend(patch, over: result, mask: mask, extent: image.extent)
            }
        }
        for eye in settings.eyes where !eye.isIdentity {
            guard let center = mapping.forward(eye.center) else { continue }
            let point = CGPoint(
                x: image.extent.minX + center.x * image.extent.width,
                y: image.extent.maxY - center.y * image.extent.height
            )
            let scale = mapping.forwardRadiusScale(at: eye.center) ?? 1
            let rx = max(1, CGFloat(eye.radiusX) * image.extent.width * scale)
            let ry = max(1, CGFloat(eye.radiusY) * image.extent.height * scale)
            let eyeRect = CGRect(x: point.x-rx, y: point.y-ry, width: rx*2, height: ry*2)
            let channelCorrected: CIImage
            switch eye.kind {
            case .human:
                // Red-eye replaces the pupil's red channel with a green/blue estimate before
                // darkening, avoiding the magenta halo left by a simple exposure reduction.
                channelCorrected = image.applyingFilter("CIColorMatrix", parameters: [
                    "inputRVector": CIVector(x: 0.35, y: 0.65, z: 0, w: 0)
                ])
            case .pet:
                // Pet-eye reflection can be red, green, or yellow. Neutralize the reflected
                // chroma before darkening the pupil region.
                channelCorrected = image.applyingFilter("CIColorControls", parameters: [
                    kCIInputSaturationKey: 0.12
                ])
            }
            let darkened = channelCorrected.applyingFilter("CIColorControls", parameters: [
                kCIInputBrightnessKey: -(eye.darken / 100) * 0.45,
                kCIInputContrastKey: 1.05
            ]).cropped(to: image.extent)
            let pupilRadius = min(rx, ry) * CGFloat(eye.pupilSize / 100) * 0.72
            let mask = featheredEllipse(
                center: point, radiusX: max(1, pupilRadius), radiusY: max(1, pupilRadius),
                feather: 0.3, opacity: CGFloat(eye.darken / 100), extent: image.extent
            ).cropped(to: eyeRect.insetBy(dx: -rx * 0.3, dy: -ry * 0.3).intersection(image.extent))
            result = blend(darkened, over: result, mask: mask, extent: image.extent)
        }
        return result
    }

    private static func featheredDisk(
        center: CGPoint, radius: CGFloat, feather: CGFloat, opacity: CGFloat, extent: CGRect
    ) -> CIImage {
        featheredEllipse(center: center, radiusX: radius, radiusY: radius,
                         feather: feather, opacity: opacity, extent: extent)
    }

    private static func featheredEllipse(
        center: CGPoint, radiusX: CGFloat, radiusY: CGFloat, feather: CGFloat,
        opacity: CGFloat, extent: CGRect
    ) -> CIImage {
        let innerX = max(0.5, radiusX * (1 - feather))
        let innerY = max(0.5, radiusY * (1 - feather))
        let outerX = max(innerX + 0.5, radiusX)
        let gradient = CIFilter(name: "CIRadialGradient")!
        gradient.setValue(CIVector(cgPoint: center), forKey: "inputCenter")
        gradient.setValue(innerX, forKey: "inputRadius0")
        gradient.setValue(outerX, forKey: "inputRadius1")
        gradient.setValue(CIColor.white, forKey: "inputColor0")
        gradient.setValue(CIColor.black, forKey: "inputColor1")
        let horizontal = gradient.outputImage?.cropped(to: extent)
            ?? CIImage(color: .black).cropped(to: extent)
        // A vertical scale turns the radial falloff into a soft ellipse while retaining a lazy graph.
        let scaled = horizontal.transformed(by: CGAffineTransform(
            translationX: 0, y: center.y
        ).scaledBy(x: 1, y: innerX / innerY).translatedBy(x: 0, y: -center.y)).cropped(to: extent)
        return scaled.applyingFilter("CIColorMatrix", parameters: [
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: opacity)
        ]).cropped(to: extent)
    }

    private static func blend(_ effect: CIImage, over input: CIImage, mask: CIImage, extent: CGRect) -> CIImage {
        let filter = CIFilter(name: "CIBlendWithMask")!
        filter.setValue(effect, forKey: kCIInputImageKey)
        filter.setValue(input, forKey: kCIInputBackgroundImageKey)
        filter.setValue(mask, forKey: kCIInputMaskImageKey)
        return (filter.outputImage ?? input).cropped(to: extent)
    }
}

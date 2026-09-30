import CoreGraphics
import Foundation

/// Builds persisted thumbnail frames from rasters that already exist as `CGImage`.
///
/// This stays on the CGImage side of the render boundary: a rendered edited thumbnail and an ImageIO
/// original both arrive as bitmaps, so nothing here touches Core Image. The JPEG is tagged with the
/// raster's own color space, and the metadata records what that space is so the shared classifier
/// can refuse a raster the current working space cannot show losslessly.
enum ThumbnailFrameEncoder {
    static let jpegQuality = 0.8

    /// A frame for an original (unedited) thumbnail.
    static func originalFrame(
        image: CGImage, identity: PortablePhotoIdentity, presentedAt: Date = Date()
    ) -> PresentationFrame? {
        guard let normalized = normalizedRaster(image) else { return nil }
        return makeFrame(
            kind: .originalThumbnail480, raster: normalized.image,
            rasterColorSpace: normalized.space, identity: identity,
            signature: OriginalThumbnailSignature.signature(for: identity),
            geometry: PresentedGeometry(
                crop: .neutral, rotation: .zero,
                orientedAspectRatio: aspect(of: normalized.image)
            ),
            presentedAt: presentedAt
        )
    }

    /// A frame for an edited thumbnail rendered in `signature.workingSpace`.
    static func editedFrame(
        image: CGImage, identity: PortablePhotoIdentity, signature: FrameSignature,
        crop: CropAdjustments, rotation: ImageRotation, presentedAt: Date = Date()
    ) -> PresentationFrame? {
        makeFrame(
            kind: .editedThumbnail480, raster: image,
            rasterColorSpace: RasterColorSpace(signature.workingSpace), identity: identity,
            signature: signature,
            geometry: PresentedGeometry(
                crop: crop, rotation: rotation, orientedAspectRatio: aspect(of: image)
            ),
            presentedAt: presentedAt
        )
    }

    private static func makeFrame(
        kind: PresentationFrameKind, raster: CGImage, rasterColorSpace: RasterColorSpace,
        identity: PortablePhotoIdentity, signature: FrameSignature, geometry: PresentedGeometry,
        presentedAt: Date
    ) -> PresentationFrame? {
        guard raster.width > 0, raster.height > 0,
              max(raster.width, raster.height) <= FrameClassifier.previewLongEdge,
              geometry.orientedAspectRatio.isFinite, geometry.orientedAspectRatio > 0,
              let digest = digest(of: raster),
              let jpeg = RenderEngineResources.jpegData(for: raster, quality: jpegQuality)
        else { return nil }
        return PresentationFrame(
            metadata: PresentationFrameMetadata(
                identity: identity, kind: kind, signature: signature, geometry: geometry,
                rasterColorSpace: rasterColorSpace, perceptualDigest: digest,
                presentedAt: presentedAt, pixelWidth: raster.width, pixelHeight: raster.height
            ),
            rasterData: jpeg
        )
    }

    private static func aspect(of image: CGImage) -> Double {
        Double(image.width) / Double(image.height)
    }

    /// ImageIO thumbnails keep the source's own profile. The frame model knows sRGB and Display P3,
    /// so anything else is converted to sRGB — a 480 px thumbnail loses nothing it could show.
    private static func normalizedRaster(_ image: CGImage) -> (image: CGImage, space: RasterColorSpace)? {
        let name = image.colorSpace?.name
        if name == CGColorSpace.displayP3 { return (image, .displayP3) }
        if name == CGColorSpace.sRGB { return (image, .sRGB) }
        guard let srgb = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                  bytesPerRow: 0, space: srgb,
                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
              )
        else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard let converted = context.makeImage() else { return nil }
        return (converted, .sRGB)
    }

    /// The 8×8 block-mean fingerprint, computed from one 64×64 draw of the raster.
    static func digest(of image: CGImage) -> PerceptualDigest? {
        let side = PerceptualDigest.gridSide
        let block = 8
        let pixels = side * block
        let rowBytes = pixels * 4
        var buffer = [UInt8](repeating: 0, count: rowBytes * pixels)
        let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
        let space = image.colorSpace.flatMap { $0.model == .rgb && $0.supportsOutput ? $0 : nil } ?? srgb
        let drawn = buffer.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(
                data: bytes.baseAddress, width: pixels, height: pixels, bitsPerComponent: 8,
                bytesPerRow: rowBytes, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
            return true
        }
        guard drawn else { return nil }
        var cells = Data(count: PerceptualDigest.byteCount)
        let area = block * block
        for cellY in 0..<side {
            for cellX in 0..<side {
                var sums = (r: 0, g: 0, b: 0)
                for y in 0..<block {
                    let rowStart = (cellY * block + y) * rowBytes + cellX * block * 4
                    for x in 0..<block {
                        let offset = rowStart + x * 4
                        sums.r += Int(buffer[offset])
                        sums.g += Int(buffer[offset + 1])
                        sums.b += Int(buffer[offset + 2])
                    }
                }
                let out = (cellY * side + cellX) * 3
                cells[out] = UInt8((sums.r + area / 2) / area)
                cells[out + 1] = UInt8((sums.g + area / 2) / area)
                cells[out + 2] = UInt8((sums.b + area / 2) / area)
            }
        }
        return PerceptualDigest(bytes: cells)
    }
}

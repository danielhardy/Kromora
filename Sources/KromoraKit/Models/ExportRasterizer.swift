import CoreImage

/// An export render whose GPU work did not complete. The export is not committed.
struct ExportRenderError: LocalizedError, Sendable {
    let underlying: any Error

    var errorDescription: String? {
        "The export could not be rendered (\(underlying.localizedDescription)). Your edits are unchanged; try exporting again."
    }
}

/// Rasterizes a finished export graph into a `CGImage`. The live implementation renders through a
/// `CIRenderTask` and waits for completion, because `CIContext.createCGImage` collapses any GPU
/// failure into a nil image with no error. Tests inject a failing implementation.
struct ExportRasterizer: Sendable {
    let rasterize: @Sendable (
        _ image: CIImage, _ context: CIContext, _ rect: CGRect,
        _ format: CIFormat, _ colorSpace: CGColorSpace
    ) throws -> CGImage

    func callAsFunction(
        _ image: CIImage, context: CIContext, rect: CGRect, format: CIFormat, colorSpace: CGColorSpace
    ) throws -> CGImage {
        try rasterize(image, context, rect, format, colorSpace)
    }

    static let live = ExportRasterizer { image, context, rect, format, colorSpace in
        let width = Int(rect.width), height = Int(rect.height)
        let bytesPerPixel = format == .RGBA16 ? 8 : 4
        let bytesPerRow = width * bytesPerPixel
        guard width > 0, height > 0, let storage = CFDataCreateMutable(nil, bytesPerRow * height) else {
            throw ImageError.exportFailed
        }
        CFDataSetLength(storage, bytesPerRow * height)
        let bytes = CFDataGetMutableBytePtr(storage)!
        let destination = CIRenderDestination(
            bitmapData: bytes, width: width, height: height, bytesPerRow: bytesPerRow, format: format)
        destination.colorSpace = colorSpace
        destination.isFlipped = true
        do {
            let positioned = image.transformed(by: CGAffineTransform(
                translationX: -rect.minX, y: -rect.minY))
            try context.startTask(toRender: positioned, to: destination).waitUntilCompleted()
        } catch {
            throw ExportRenderError(underlying: error)
        }
        guard let provider = CGDataProvider(data: storage) else { throw ImageError.exportFailed }
        let sixteen = format == .RGBA16
        guard let cgImage = CGImage(
            width: width, height: height,
            bitsPerComponent: sixteen ? 16 : 8, bitsPerPixel: bytesPerPixel * 8,
            bytesPerRow: bytesPerRow, space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue
                | (sixteen ? CGBitmapInfo.byteOrder16Little.rawValue : 0)),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        ) else { throw ImageError.exportFailed }
        return cgImage
    }
}

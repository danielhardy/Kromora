import CoreGraphics
import CoreImage
import Foundation

/// Histogram tallying, split out of `RenderEngine.swift` (KRMA-530) because it is a self-contained
/// analysis responsibility: it reads a completed graph or builds one through the shared
/// `buildImage` funnel, then rasterizes a bounded RGBA8 buffer for the bin counts. It has no state
/// of its own beyond the actor's shared `context`.
extension RenderEngine {
    /// Tally the rendered document into 256 bins per channel.
    ///
    /// The image is rendered to a downscaled RGBA8 buffer first — `maxDimension` caps the longest
    /// side so this stays a few milliseconds even for a 60 MP source, while staying representative.
    ///
    /// `scale` is the caller's *display* scale on purpose. The developed-source memo is keyed on it
    /// (§6, "the cutover's one real trap"), so asking for a histogram at some private 512 px scale
    /// would evict the preview's entry on every tally and re-develop the RAW on the next frame —
    /// turning a cheap panel into a per-frame decode. Rendering the same graph the preview renders
    /// and shrinking only the tally buffer keeps both on one memo entry.
    ///
    /// The buffer is rendered in `space` for the same reason `makeCGImage` is: the histogram should
    /// describe the pixels the user is looking at, not a differently-encoded copy of them.
    func histogram(
        source: ImageSource,
        document: EditDocument,
        lut: CubeLUT?,
        scale: RenderScale,
        space: WorkingSpace = .current,
        maxDimension: Int = 512
    ) async -> HistogramData? {
        var interval = KromoraObservability.begin(.histogram, source: source, quality: .preview)
        defer { interval.end() }

        guard !Task.isCancelled, maxDimension > 0 else {
            return nil
        }
        let image: CIImage?
        do {
            image = try await buildImage(source, document, lut, scale, space, quality: .preview,
                                         assetID: nil, requestRevision: 0)
        } catch {
            return nil
        }
        guard let image else { return nil }
        return tallyHistogram(from: image, space: space, maxDimension: maxDimension)
    }

    /// Tally the completed preview texture without rebuilding the render graph.
    func histogram(
        presentedImage: sending CIImage,
        space: WorkingSpace = .current,
        maxDimension: Int = 512
    ) async -> HistogramData? {
        var interval = KromoraObservability.begin(.histogram, source: nil, quality: .preview)
        defer { interval.end() }
        return tallyHistogram(from: presentedImage, space: space, maxDimension: maxDimension)
    }

    fileprivate func tallyHistogram(
        from image: CIImage,
        space: WorkingSpace,
        maxDimension: Int
    ) -> HistogramData? {
        guard !Task.isCancelled, maxDimension > 0 else { return nil }
        guard !Task.isCancelled else { return nil }
        let extent = image.extent
        guard extent.isRasterizable else { return nil }

        let factor = min(
            CGFloat(maxDimension) / extent.width,
            CGFloat(maxDimension) / extent.height,
            1.0
        )
        let scaled = image.transformed(by: CGAffineTransform(scaleX: factor, y: factor))
        let rect = scaled.extent.integral
        guard rect.isRasterizable else { return nil }

        let width = Int(rect.width)
        let height = Int(rect.height)
        guard !Task.isCancelled, width > 0, height > 0 else { return nil }
        let bytesPerRow = width * 4
        var bytes = [UInt8](repeating: 0, count: height * bytesPerRow)
        guard !Task.isCancelled else { return nil }
        bytes.withUnsafeMutableBytes { ptr in
            guard let base = ptr.baseAddress else { return }
            guard !Task.isCancelled else { return }
            context.render(
                scaled, toBitmap: base, rowBytes: bytesPerRow, bounds: rect,
                format: .RGBA8, colorSpace: space.cgColorSpace
            )
        }
        guard !Task.isCancelled else { return nil }
        return HistogramData(rgba8: bytes, width: width, height: height, bytesPerRow: bytesPerRow)
    }
}

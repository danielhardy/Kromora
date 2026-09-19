import Foundation
import CoreImage
import UniformTypeIdentifiers
import ImageIO

/// What Kromora can open, and how to turn it into a `CIImage`.
///
/// **This is what is left of `ImageProcessor` after Step 7.** That type was a non-`Sendable` `final
/// class` singleton holding a `CIContext`, captured into `Task.detached` in half a dozen places —
/// the last strict-concurrency diagnostic in the module, and the second `CIContext` in the render
/// stack. Its GPU duties (`renderPreview`, `renderToNSImage`, `export`, `histogram`) moved to
/// `actor RenderEngine` across Steps 5–7; its thumbnail duties moved to `Thumbnails`, which never
/// needed a `CIContext` at all; its output vocabulary moved to `ExportFormat`.
///
/// What remains is value-level and stateless, so it is a caseless `enum` rather than an instance:
/// there is nothing left to own. `docs/ENGINEERING_GUIDE.md` named this as the shape to land on.
///
/// Note `RenderPipeline.developedSource` is the decoder the *render* stack uses — it re-develops
/// from the file at a chosen scale, because `CIRAWFilter` must be configured before it yields an
/// image (§4.2). Source preparation below deliberately does not produce a `CIImage`; it only reads
/// value geometry for standard images. RAW preparation belongs to `RenderEngine`, which can reuse
/// its renderer-owned filter session for geometry, capabilities, and development.
enum ImageDecoder {

    // MARK: - Supported formats (single source of truth)

    /// Canonical RAW file extensions (lowercased). RAW files are demosaiced via CIRAWFilter.
    /// Add a new RAW format here and it flows to RAW detection and `supportedExtensions`.
    static let rawExtensions: Set<String> = [
        "dng", "cr2", "cr3", "nef", "arw", "orf",
        "raf", "rw2", "pef", "srw", "x3f", "raw",
    ]

    /// Canonical standard (non-RAW) image extensions (lowercased), loaded directly as a `CIImage`.
    /// Add a new standard format here and it flows to `supportedExtensions` and `supportedTypes`.
    private static let standardExtensions: Set<String> = [
        "jpg", "jpeg", "png", "tiff", "tif", "bmp", "heic",
    ]

    /// Every extension Kromora can open (RAW + standard, lowercased). The one definition
    /// shared by both the open panel and folder import — derive from it, never duplicate it.
    static let supportedExtensions: Set<String> = rawExtensions.union(standardExtensions)

    /// Image types for `NSOpenPanel`, derived from the canonical extension sets above.
    /// `.rawImage` covers every RAW format in a single type; standard extensions map to system UTTypes.
    static let supportedTypes: [UTType] = {
        let standardTypes = standardExtensions.compactMap { UTType(filenameExtension: $0) }
        return [.rawImage] + Set(standardTypes).sorted { $0.identifier < $1.identifier }
    }()

    // MARK: - Loading

    /// Value state needed to admit a source into the editor. No pixel graph is requested here.
    ///
    /// The source's native extent is upright/display-oriented. It is the only geometry the render
    /// pipeline needs to choose a scale; pixels remain renderer-owned and are produced on demand.
    static func prepareStandard(from url: URL) throws -> CGSize {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw ImageError.cannotLoad(url.lastPathComponent)
        }
        return try orientedExtent(from: source, name: url.lastPathComponent)
    }

    static func prepareStandard(from data: Data, name: String) throws -> CGSize {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw ImageError.cannotLoad(name)
        }
        return try orientedExtent(from: source, name: name)
    }

    private static func orientedExtent(from source: CGImageSource, name: String) throws -> CGSize {
        guard CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber
        else {
            throw ImageError.cannotLoad(name)
        }

        let storedWidth = width.doubleValue
        let storedHeight = height.doubleValue
        guard storedWidth >= 1, storedHeight >= 1,
              storedWidth.isFinite, storedHeight.isFinite else {
            throw ImageError.cannotLoad(name)
        }

        let orientation = exifOrientation(in: properties)
        let swapsAxes = [
            CGImagePropertyOrientation.leftMirrored,
            .left,
            .rightMirrored,
            .right,
        ].contains(orientation)
        return swapsAxes
            ? CGSize(width: storedHeight, height: storedWidth)
            : CGSize(width: storedWidth, height: storedHeight)
    }

    /// Load any supported image file as a CIImage, upright.
    static func load(from url: URL) throws -> CIImage {
        var interval = KromoraSignpostInterval(
            .decode,
            context: KromoraTraceContext(sourceFingerprint: url.standardizedFileURL.path, quality: "open")
        )
        defer { interval.end() }

        if rawExtensions.contains(url.pathExtension.lowercased()) {
            guard let output = developRAWNeutral(at: url) else {
                throw ImageError.cannotLoad(url.lastPathComponent)
            }
            return output
        }
        guard let image = CIImage(contentsOf: url, options: orientedLoadOptions) else {
            throw ImageError.cannotLoad(url.lastPathComponent)
        }
        return image
    }

    /// Load in-memory image data (Photos imports, drag-and-drop payloads) as an
    /// upright CIImage.
    static func load(
        from data: Data, name: String, traceQuality: String = "open"
    ) throws -> CIImage {
        var interval = KromoraSignpostInterval(
            .decode,
            context: KromoraTraceContext(sourceFingerprint: "data:\(data.count)", quality: traceQuality)
        )
        defer { interval.end() }

        if ImageSource.kind(forData: data) == .raw {
            guard let filter = CIRAWFilter(imageData: data, identifierHint: nil),
                  let output = developedImage(from: filter, orientation: exifOrientation(of: data))
            else {
                throw ImageError.cannotLoad(name)
            }
            return output
        } else {
            guard let image = CIImage(data: data, options: orientedLoadOptions) else {
                throw ImageError.cannotLoad(name)
            }
            return image
        }
    }

    /// Decode options that bake a file's EXIF orientation into the returned
    /// image's geometry.
    ///
    /// `CIImage` does **not** honor the orientation tag by default. `CIRAWFilter` does:
    /// it copies the file tag onto `orientation` and bakes it into `outputImage`, while
    /// `nativeSize` stays sensor-native. The thumbnail path bakes the same tag via
    /// `kCGImageSourceCreateThumbnailWithTransform`. Without `orientedLoadOptions` a
    /// portrait JPEG/HEIC previewed *and exported* on its side while its filmstrip
    /// thumbnail stood upright. Every non-RAW decode goes through these options; every
    /// RAW decode goes through `developedImage(from:orientation:)` so the filter's own
    /// bake is not applied a second time.
    ///
    /// Computed rather than stored: a `static let` of `[CIImageOption: Any]` is shared mutable state
    /// as far as the compiler is concerned (`Any` is not `Sendable`), which is an error under Swift
    /// 6. Rebuilding a one-entry dictionary is free next to decoding an image.
    static var orientedLoadOptions: [CIImageOption: Any] { [.applyOrientationProperty: true] }

    /// Develop a RAW/DNG at **neutral / default `CIRAWFilter` settings** — no
    /// user develop adjustments are applied.
    ///
    /// This is the single source of truth for the "neutral baseline" RAW
    /// render. Both normal RAW loading and LUT derivation (`RecipeExtractor`)
    /// develop RAWs through here, so the derive baseline can never drift from
    /// the render path and stays independent of any user-adjustable develop
    /// path. Returns `nil` if the file can't be decoded.
    static func developRAWNeutral(at url: URL) -> CIImage? {
        guard let filter = CIRAWFilter(imageURL: url) else { return nil }
        return developedImage(from: filter, orientation: exifOrientation(at: url))
    }

    // MARK: - EXIF orientation for RAW decoding

    /// The display orientation recorded for a file-backed source. `.up` when the tag is
    /// absent or the properties cannot be read — the same fallback `orientedExtent` uses.
    ///
    /// `CIRAWFilter.nativeSize` is sensor-native and ignores this tag, so display geometry
    /// still comes from ImageIO plus `orientedDimensions`. Pixel output is a different
    /// contract: the filter bakes `orientation` itself, and `developedImage` only re-bakes
    /// when a decoder still emits sensor-native axes. Standard images bake through
    /// `orientedLoadOptions`; both spellings agree by construction.
    static func exifOrientation(at url: URL) -> CGImagePropertyOrientation {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any]
        else { return .up }
        return exifOrientation(in: properties)
    }

    /// The display orientation recorded for a bytes-backed source. Same contract as the
    /// file-backed overload.
    static func exifOrientation(of data: Data) -> CGImagePropertyOrientation {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any]
        else { return .up }
        return exifOrientation(in: properties)
    }

    /// Bake an EXIF orientation into a decoded image's geometry. `.up` returns the image
    /// unchanged so neutral sources never pay for a transform node.
    static func applyingEXIFOrientation(
        _ orientation: CGImagePropertyOrientation, to image: CIImage
    ) -> CIImage {
        guard orientation != .up else { return image }
        return image.oriented(orientation)
    }

    /// Display-oriented pixels from a configured `CIRAWFilter`.
    ///
    /// The filter already applies its `orientation` property to `outputImage`. Re-baking
    /// the ImageIO tag on top of that turns a portrait RAW (EXIF 5–8) back into landscape.
    /// `nativeSize` remains sensor-native and is *not* a substitute for the output extent.
    static func developedImage(
        from filter: CIRAWFilter,
        orientation: CGImagePropertyOrientation
    ) -> CIImage? {
        if filter.orientation != orientation {
            filter.orientation = orientation
        }
        guard let output = filter.outputImage, output.extent.isRasterizable else { return nil }
        let displayOriented = displayOrientedRAWOutput(
            output, sensorSize: filter.nativeSize, orientation: orientation
        )
        guard displayOriented.extent.isRasterizable else { return nil }
        return displayOriented
    }

    /// Skip a second bake when `output` is already on the display axes. Internal for tests
    /// so the axis rule can be pinned without a camera RAW in the checkout.
    static func displayOrientedRAWOutput(
        _ output: CIImage,
        sensorSize: CGSize,
        orientation: CGImagePropertyOrientation
    ) -> CIImage {
        let display = orientedDimensions(sensorSize, for: orientation)
        let displaySwapsAxes =
            display.width != sensorSize.width || display.height != sensorSize.height
        guard displaySwapsAxes else { return output }
        if isLandscape(output.extent.size) == isLandscape(display) {
            return output
        }
        return applyingEXIFOrientation(orientation, to: output)
    }

    private static func isLandscape(_ size: CGSize) -> Bool {
        size.width >= size.height
    }

    /// The display dimensions of a stored pixel size. Quarter-turn orientations (5–8)
    /// swap the axes; mirrors and half-turns (2–4) preserve them.
    static func orientedDimensions(
        _ storedSize: CGSize, for orientation: CGImagePropertyOrientation
    ) -> CGSize {
        switch orientation {
        case .left, .leftMirrored, .right, .rightMirrored:
            return CGSize(width: storedSize.height, height: storedSize.width)
        default:
            return storedSize
        }
    }

    private static func exifOrientation(in properties: [CFString: Any]) -> CGImagePropertyOrientation {
        if let raw = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue,
           let orientation = CGImagePropertyOrientation(rawValue: UInt32(raw)) {
            return orientation
        }
        if let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any],
           let raw = (tiff[kCGImagePropertyTIFFOrientation] as? NSNumber)?.intValue,
           let orientation = CGImagePropertyOrientation(rawValue: UInt32(raw)) {
            return orientation
        }
        return .up
    }
}

// MARK: - Extent

extension CGRect {
    /// Whether this extent can actually be turned into a pixel buffer.
    ///
    /// Rejects empty, null, and — the one that bites — **infinite** extents.
    /// `CGRect.infinite` is built from `greatestFiniteMagnitude`, not `inf`, so
    /// an `isFinite` check on its width passes while `Int(width)` traps at
    /// runtime. Generator-backed images (`CIImage(color:)` and friends) have
    /// exactly that extent, so any code path that might meet one has to test
    /// `isInfinite` explicitly.
    var isRasterizable: Bool {
        !isInfinite && !isNull && !isEmpty
            && width.isFinite && height.isFinite
            && width >= 1 && height >= 1
    }
}

// MARK: - Errors

enum ImageError: LocalizedError, Sendable {
    case cannotLoad(String)
    case processingFailed
    case exportFailed

    var errorDescription: String? {
        switch self {
        case .cannotLoad(let name): return "Cannot load \(name)"
        case .processingFailed: return "Image processing failed"
        case .exportFailed: return "Export failed"
        }
    }
}

import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import KromoraKit

/// Every rendered delivery encodes in one explicit target and embeds the matching ICC profile
/// (ADR-KRMA-1115). The explicit `space` is a preparation seam; the shipping default is
/// `WorkingSpace.current`.
final class ExportColorTaggingTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = try Fixtures.makeTempDirectory("ExportColorTagging")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    /// A Display P3 PNG holding a saturated P3 green, which sRGB cannot represent.
    private func makeP3Source() throws -> ImageSource {
        let p3 = WorkingSpace.displayP3.cgColorSpace
        let context = try XCTUnwrap(CGContext(
            data: nil, width: 16, height: 16, bitsPerComponent: 16, bytesPerRow: 0, space: p3,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(colorSpace: p3, components: [0, 1, 0, 1])!)
        context.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
        let url = try Fixtures.writePNG(
            try XCTUnwrap(context.makeImage()), named: "p3-green.png", in: directory
        )
        return ImageSource(url: url, nativeExtent: CGSize(width: 16, height: 16))
    }

    private func export(_ source: ImageSource, format: ExportFormat, space: WorkingSpace) async throws -> URL {
        try await export(source, options: ExportOptions(format: format, colorSpace: space))
    }

    private func export(_ source: ImageSource, options: ExportOptions) async throws -> URL {
        let url = directory.appendingPathComponent(
            "out-\(options.colorSpace.rawValue)-\(UUID().uuidString).\(options.format.fileExtension)"
        )
        try await RenderEngine().encode(RenderRequest(
            source: source,
            document: EditDocument(),
            quality: .export,
            output: .encoded(format: options.format, quality: CGFloat(options.quality)),
            space: options.colorSpace,
            exportOptions: options
        ), to: url)
        return url
    }

    private func profileName(of url: URL) throws -> CFString? {
        let image = try XCTUnwrap(
            CGImageSourceCreateWithURL(url as CFURL, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }
        )
        return image.colorSpace?.name
    }

    /// Reads one encoded pixel after color conversion into extended linear sRGB. A saturated P3
    /// green remains outside sRGB there; sRGB output clips it into the ordinary [0, 1] range.
    private func extendedSRGBPixel(of url: URL) throws -> [Float16] {
        let image = try XCTUnwrap(
            CGImageSourceCreateWithURL(url as CFURL, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }
        )
        let extended = try XCTUnwrap(CGColorSpace(name: CGColorSpace.extendedLinearSRGB))
        var pixel = [Float16](repeating: 0, count: 4)
        let drawn = pixel.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 16, bytesPerRow: 8,
                space: extended,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                    | CGBitmapInfo.floatComponents.rawValue | CGBitmapInfo.byteOrder16Little.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        XCTAssertTrue(drawn)
        return pixel
    }

    private func supportsEncoding(_ format: ExportFormat) -> Bool {
        let identifiers = CGImageDestinationCopyTypeIdentifiers() as? [String] ?? []
        return identifiers.contains(format.utType.identifier)
    }

    func testEveryFormatReopensTaggedWithTheExplicitTarget() async throws {
        let source = try makeP3Source()
        for format in ExportFormat.allCases {
            // Some supported Apple Silicon configurations do not register a HEIF destination.
            // Skip only that unavailable encoder; once registered, export failures must surface.
            guard supportsEncoding(format) else {
                if format == .heif { continue }
                XCTFail("Image I/O does not register an encoder for \(format)")
                continue
            }
            for space in WorkingSpace.allCases {
                let url = try await export(source, format: format, space: space)
                XCTAssertEqual(
                    try profileName(of: url), space.cgColorSpace.name, "\(format) in \(space)"
                )
            }
        }
    }

    func testP3ExportRetainsOutOfSRGBGreenWhileSRGBClipsIt() async throws {
        let source = try makeP3Source()
        for format in ExportFormat.allCases where supportsEncoding(format) {
            let p3URL = try await export(source, format: format, space: .displayP3)
            XCTAssertEqual(try profileName(of: p3URL), CGColorSpace.displayP3 as CFString, "\(format) P3 tag")
            let p3Pixel = try extendedSRGBPixel(of: p3URL)
            // Compression and integer quantization can soften the P3 primary. The generous
            // threshold leaves room for 8-bit/lossy formats while rejecting sRGB clipping.
            XCTAssertLessThan(p3Pixel[0], -0.05, "\(format) retains P3 green")
            XCTAssertGreaterThan(p3Pixel[1], 1.0, "\(format) retains P3 green")

            let sRGBURL = try await export(source, format: format, space: .sRGB)
            XCTAssertEqual(try profileName(of: sRGBURL), CGColorSpace.sRGB as CFString, "\(format) sRGB tag")
            let sRGBPixel = try extendedSRGBPixel(of: sRGBURL)
            XCTAssertGreaterThanOrEqual(sRGBPixel[0], -0.005, "\(format) clips to sRGB")
            XCTAssertLessThanOrEqual(sRGBPixel[1], 1.005, "\(format) clips to sRGB")
        }
    }

    func testShareCopyPhotosAndExternalEditorFollowTheSameTarget() async throws {
        XCTAssertEqual(ShareExportPolicy.options().colorSpace, .current)
        XCTAssertEqual(ShareCopyPolicy.options.colorSpace, .current)
        XCTAssertEqual(ExternalEditorExportPolicy.options().colorSpace, .current)
        XCTAssertEqual(ExternalEditorExportPolicy.options().format, .tiff)
        XCTAssertEqual(ExternalEditorExportPolicy.options().bitDepth, .sixteen)
        for space in WorkingSpace.allCases {
            XCTAssertEqual(ShareExportPolicy.options(space: space).colorSpace, space)
            XCTAssertEqual(ShareCopyPolicy.options(for: space).colorSpace, space)
            XCTAssertEqual(ExternalEditorExportPolicy.options(space: space).colorSpace, space)
        }

        let source = try makeP3Source()
        let photosOptions = ExportOptions(
            format: .png, colorSpace: .displayP3, photos: PhotosExportOptions()
        )
        XCTAssertNotNil(photosOptions.photos)
        let deliveries: [(String, ExportOptions)] = [
            ("Share", ShareExportPolicy.options(format: .png, space: .displayP3)),
            ("Copy", ShareCopyPolicy.options(for: .displayP3)),
            ("Photos", photosOptions),
            ("External Editor", ExternalEditorExportPolicy.options(space: .displayP3))
        ]
        for (name, options) in deliveries {
            let url = try await export(source, options: options)
            XCTAssertEqual(
                try profileName(of: url), CGColorSpace.displayP3 as CFString, "\(name) ICC profile"
            )
            let pixel = try extendedSRGBPixel(of: url)
            XCTAssertLessThan(pixel[0], -0.05, "\(name) retains P3 green")
            XCTAssertGreaterThan(pixel[1], 1.0, "\(name) retains P3 green")
        }
    }

    func testOriginalBundleCompanionIsTaggedAndLeavesOriginalByteIdentical() async throws {
        let source = try makeP3Source()
        guard case .url(let sourceURL) = source.backing else { return XCTFail("expected file source") }
        let originalBytes = try Data(contentsOf: sourceURL)
        let originalProfile = try profileName(of: sourceURL)
        for space in WorkingSpace.allCases {
            let options = OriginalBundleCompanionPolicy.options(space: space)
            let data = try await RenderEngine().render(RenderRequest(
                source: source, document: EditDocument(), quality: .export,
                output: .encoded(format: options.format, quality: CGFloat(options.quality)),
                space: options.colorSpace, exportOptions: options
            )).data
            let bundle = directory.appendingPathComponent("B-\(space.rawValue).\(OriginalSettingsBundle.fileExtension)")
            try await OriginalSettingsBundle.create(
                source: source, sourceName: "p3-green.png", document: EditDocument(),
                destination: bundle, locationMetadataIncluded: true,
                rendered: .init(filename: "p3-green_rendered.tiff", data: data)
            )
            let manifest = try OriginalSettingsBundle.verify(at: bundle)
            XCTAssertEqual(manifest.renderedFilename, "p3-green_rendered.tiff")
            let bundledOriginal = bundle.appendingPathComponent("p3-green.png")
            XCTAssertEqual(try Data(contentsOf: bundledOriginal), originalBytes)
            XCTAssertEqual(try profileName(of: bundledOriginal), originalProfile)

            let companion = bundle.appendingPathComponent("p3-green_rendered.tiff")
            XCTAssertEqual(try profileName(of: companion), space.cgColorSpace.name, "companion in \(space)")
            let pixel = try extendedSRGBPixel(of: companion)
            if space == .displayP3 {
                XCTAssertLessThan(pixel[0], -0.05)
                XCTAssertGreaterThan(pixel[1], 1.0)
            } else {
                XCTAssertGreaterThanOrEqual(pixel[0], -0.005)
                XCTAssertLessThanOrEqual(pixel[1], 1.005)
            }
            try Data("x".utf8).write(to: companion)
            XCTAssertThrowsError(try OriginalSettingsBundle.verify(at: bundle))
        }
    }
}

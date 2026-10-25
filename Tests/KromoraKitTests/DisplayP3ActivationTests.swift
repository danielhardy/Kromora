import CoreGraphics
import ImageIO
import XCTest
@testable import KromoraKit

/// KRMA-1121: Display P3 is the shipping default for the canvas and every rendered delivery. These
/// tests use no explicit `space:` — they assert what a user gets by default, for an edited
/// wide-gamut photo, in preview and in every supported export format.
final class DisplayP3ActivationTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = try Fixtures.makeTempDirectory("DisplayP3Activation")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    /// A Display P3 PNG whose left half is saturated P3 green (outside sRGB) and right half is a
    /// mid neutral.
    private func makeWideGamutSource() throws -> ImageSource {
        let p3 = WorkingSpace.displayP3.cgColorSpace
        let context = try XCTUnwrap(CGContext(
            data: nil, width: 32, height: 16, bitsPerComponent: 16, bytesPerRow: 0, space: p3,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(colorSpace: p3, components: [0, 1, 0, 1])!)
        context.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
        context.setFillColor(CGColor(colorSpace: p3, components: [0.5, 0.5, 0.5, 1])!)
        context.fill(CGRect(x: 16, y: 0, width: 16, height: 16))
        let url = try Fixtures.writePNG(try XCTUnwrap(context.makeImage()), named: "wide.png", in: directory)
        return ImageSource(url: url, nativeExtent: CGSize(width: 32, height: 16))
    }

    private var editedDocument: EditDocument {
        EditDocument(light: LightAdjustments(contrast: 10))
    }

    private func decode(_ url: URL) throws -> CGImage {
        try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil).flatMap {
            CGImageSourceCreateImageAtIndex($0, 0, nil)
        })
    }

    /// The pixel at `x` of the first row, converted to extended linear sRGB where P3 green stays
    /// outside [0, 1].
    private func extendedSRGBPixel(of image: CGImage, x: Int) throws -> [Float16] {
        let extended = try XCTUnwrap(CGColorSpace(name: CGColorSpace.extendedLinearSRGB))
        var pixel = [Float16](repeating: 0, count: 4)
        let drawn = pixel.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 16, bytesPerRow: 8,
                space: extended,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                    | CGBitmapInfo.floatComponents.rawValue | CGBitmapInfo.byteOrder16Little.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: -x, y: 0, width: image.width, height: image.height))
            return true
        }
        XCTAssertTrue(drawn)
        return pixel
    }

    func testEveryDefaultTargetsDisplayP3() {
        XCTAssertEqual(WorkingSpace.current, .displayP3)
        XCTAssertEqual(ExportOptions.default.colorSpace, .displayP3)
        XCTAssertEqual(ShareExportPolicy.options().colorSpace, .displayP3)
        XCTAssertEqual(ShareCopyPolicy.options.colorSpace, .displayP3)
        XCTAssertEqual(ExternalEditorExportPolicy.options().colorSpace, .displayP3)
        XCTAssertEqual(OriginalBundleCompanionPolicy.options(space: .current).colorSpace, .displayP3)
        XCTAssertEqual(RenderRequest(
            source: ImageSource(url: directory, nativeExtent: .zero), document: EditDocument(), quality: .export
        ).space, .displayP3)
    }

    func testPreviewKeepsOutOfSRGBColorThroughAnEdit() async throws {
        let source = try makeWideGamutSource()
        let rendered = await RenderEngine().makeCGImage(
            source: source, document: editedDocument, lut: nil, scale: .full, space: .current
        )
        let image = try XCTUnwrap(rendered)
        XCTAssertEqual(image.colorSpace?.name, CGColorSpace.displayP3)
        let green = try extendedSRGBPixel(of: image, x: 4)
        XCTAssertLessThan(green[0], -0.05, "preview keeps P3 green outside sRGB")
        XCTAssertGreaterThan(green[1], 1.0, "preview keeps P3 green outside sRGB")
    }

    func testEveryDefaultExportKeepsTheEditedWideGamutPatchAndTagsP3() async throws {
        let source = try makeWideGamutSource()
        let identity = EditDocument()
        for format in ExportFormat.allCases {
            let identifiers = CGImageDestinationCopyTypeIdentifiers() as? [String] ?? []
            guard identifiers.contains(format.utType.identifier) else {
                if format == .heif { continue }
                XCTFail("Image I/O does not register an encoder for \(format)")
                continue
            }
            for document in [identity, editedDocument] {
                let options = ExportOptions(format: format)
                let url = directory.appendingPathComponent("out-\(UUID().uuidString).\(format.fileExtension)")
                try await RenderEngine().encode(RenderRequest(
                    source: source, document: document, quality: .export,
                    output: .encoded(format: format, quality: CGFloat(options.quality)),
                    exportOptions: options
                ), to: url)
                let image = try decode(url)
                XCTAssertEqual(image.colorSpace?.name, CGColorSpace.displayP3, "\(format) ICC profile")
                let green = try extendedSRGBPixel(of: image, x: 4)
                XCTAssertLessThan(green[0], -0.05, "\(format) retains P3 green")
                XCTAssertGreaterThan(green[1], 1.0, "\(format) retains P3 green")
            }
        }
    }

    /// A re-opened export matches the preview raster for the same document within 8-bit rounding.
    func testReopenedExportMatchesThePreviewRaster() async throws {
        let source = try makeWideGamutSource()
        let document = editedDocument
        let rendered = await RenderEngine().makeCGImage(
            source: source, document: document, lut: nil, scale: .full, space: .current
        )
        let preview = try XCTUnwrap(rendered)
        let options = ExportOptions(format: .png)
        let url = directory.appendingPathComponent("parity.png")
        try await RenderEngine().encode(RenderRequest(
            source: source, document: document, quality: .export,
            output: .encoded(format: .png, quality: 1), exportOptions: options
        ), to: url)
        let exported = try decode(url)
        XCTAssertEqual(exported.colorSpace?.name, preview.colorSpace?.name)
        let a = try Pixels.bytes(of: preview)
        let b = try Pixels.bytes(of: exported)
        let worst = try XCTUnwrap(Pixels.worstDelta(a, b))
        XCTAssertLessThanOrEqual(worst.delta, 2, "export vs preview, worst at byte \(worst.index)")
    }
}

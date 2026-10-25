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
        let url = directory.appendingPathComponent("out-\(space.rawValue).\(format.fileExtension)")
        let options = ExportOptions(format: format, colorSpace: space)
        try await RenderEngine().encode(RenderRequest(
            source: source,
            document: EditDocument(),
            quality: .export,
            output: .encoded(format: format, quality: CGFloat(options.quality)),
            space: space,
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

    func testEveryFormatReopensTaggedWithTheExplicitTarget() async throws {
        let source = try makeP3Source()
        for format in ExportFormat.allCases {
            for space in WorkingSpace.allCases {
                let url: URL
                do { url = try await export(source, format: format, space: space) } catch {
                    if format == .heif { continue }  // hardware encoder may be absent
                    throw error
                }
                XCTAssertEqual(
                    try profileName(of: url), space.cgColorSpace.name, "\(format) in \(space)"
                )
            }
        }
    }

    func testP3ExportRetainsOutOfSRGBGreenWhileSRGBClipsIt() async throws {
        let source = try makeP3Source()
        let p3URL = try await export(source, format: .png, space: .displayP3)
        let image = try XCTUnwrap(
            CGImageSourceCreateWithURL(p3URL as CFURL, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }
        )
        // Draw the exported pixel into extended-sRGB float: a retained P3 primary lands outside
        // [0, 1] there (red about -0.51), a clipped one cannot.
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
        XCTAssertLessThan(pixel[0], -0.05)
        XCTAssertGreaterThan(pixel[1], 1.0)

        let sRGBURL = try await export(source, format: .png, space: .sRGB)
        XCTAssertEqual(try profileName(of: sRGBURL), CGColorSpace.sRGB as CFString)
        XCTAssertEqual(try profileName(of: p3URL), CGColorSpace.displayP3 as CFString)
    }

    func testShareCopyAndExternalEditorFollowTheSameTarget() {
        XCTAssertEqual(ShareExportPolicy.options().colorSpace, .current)
        XCTAssertEqual(ShareCopyPolicy.options.colorSpace, .current)
        XCTAssertEqual(ExternalEditorExportPolicy.options().colorSpace, .current)
        XCTAssertEqual(ExternalEditorExportPolicy.options().format, .tiff)
        XCTAssertEqual(ExternalEditorExportPolicy.options().bitDepth, .sixteen)
        for space in WorkingSpace.allCases {
            XCTAssertEqual(ShareExportPolicy.options(space: space).colorSpace, space)
            XCTAssertEqual(ExternalEditorExportPolicy.options(space: space).colorSpace, space)
        }
    }
}

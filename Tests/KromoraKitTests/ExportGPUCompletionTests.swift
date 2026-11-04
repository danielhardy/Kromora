import CoreImage
import ImageIO
import XCTest
@testable import KromoraKit

/// KRMA-1173: a failed GPU completion during export surfaces as an actionable failure, leaves no
/// staged or final file, and does not touch the edit document.
@MainActor
final class ExportGPUCompletionTests: TempDirectoryTestCase {
    private struct GPUFault: LocalizedError {
        var errorDescription: String? { "simulated GPU command buffer failure" }
    }

    private func source() throws -> ImageSource {
        let url = try Fixtures.writeGradientPNG(width: 16, height: 8, named: "gpu.png", in: tempDirectory)
        return ImageSource(url: url, nativeExtent: CGSize(width: 16, height: 8))
    }

    private func request(_ source: ImageSource, _ document: EditDocument, format: ExportFormat = .jpeg) -> RenderRequest {
        let options = ExportOptions(format: format, destination: nil)
        return RenderRequest(
            source: source, document: document, lut: nil, quality: .export,
            output: .encoded(format: format, quality: CGFloat(options.quality)),
            space: options.colorSpace, exportOptions: options
        )
    }

    private var failing: ExportRasterizer {
        ExportRasterizer { _, _, _, _, _ in throw ExportRenderError(underlying: GPUFault()) }
    }

    func testFailedCompletionFailsTheExportWithoutLeavingAFile() async throws {
        let engine = RenderEngine(exportRasterizer: failing)
        var document = EditDocument()
        document.effects.vignette.amount = -30
        let original = document
        let staged = tempDirectory.appendingPathComponent("staged.jpg")
        do {
            try await engine.encode(request(try source(), document), to: staged)
            XCTFail("export must not succeed when GPU completion failed")
        } catch let error as ExportRenderError {
            XCTAssertTrue(error.localizedDescription.contains("simulated GPU command buffer failure"))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: staged.path))
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: tempDirectory.path).filter { $0.contains("staged") },
            [], "Image I/O must not leave a temporary sibling behind")
        XCTAssertEqual(document, original)
    }

    func testBatchExportReportsTheGPUFailureAndWritesNothing() async throws {
        let engine = RenderEngine(exportRasterizer: failing)
        let coordinator = ExportCoordinator(engine: engine, exportEngine: engine)
        let folder = tempDirectory.appendingPathComponent("out")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = try Fixtures.writeGradientPNG(width: 16, height: 8, named: "batch.png", in: tempDirectory)
        let item = ExportCoordinator.BatchItem(url: url, data: nil, name: "shot")

        let outcome = await coordinator.performBatchExport(
            [item], document: EditDocument(), lut: nil, format: .jpeg, to: folder)

        XCTAssertEqual(outcome.exported, 0)
        XCTAssertEqual(outcome.failed, 1)
        XCTAssertTrue(outcome.failures.first?.reason.contains("simulated GPU command buffer failure") == true)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), [])
    }

    // MARK: - Successful behavior is retained

    func testLiveRasterizerMatchesCreateCGImage() throws {
        let context = CIContext()
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let image = CIImage(color: CIColor(red: 0.2, green: 0.5, blue: 0.8))
            .cropped(to: CGRect(x: 0, y: 0, width: 8, height: 4))
            .composited(over: CIImage(color: CIColor(red: 1, green: 0, blue: 0))
                .cropped(to: CGRect(x: 0, y: 0, width: 4, height: 2)).transformed(by: .init(translationX: 0, y: 2)))
        for format in [CIFormat.RGBA8, .RGBA16] {
            let rect = image.extent.integral
            let live = try ExportRasterizer.live(image, context: context, rect: rect, format: format, colorSpace: space)
            let reference = try XCTUnwrap(context.createCGImage(image, from: rect, format: format, colorSpace: space))
            XCTAssertEqual(live.width, reference.width)
            XCTAssertEqual(live.height, reference.height)
            XCTAssertEqual(live.bitsPerComponent, reference.bitsPerComponent)
            XCTAssertEqual(try pixels(live), try pixels(reference), "\(format)")
        }
    }

    func testSuccessfulExportsStillEncodeEveryFormat() async throws {
        let engine = RenderEngine()
        for format in ExportFormat.allCases {
            let url = tempDirectory.appendingPathComponent("ok.\(format.fileExtension)")
            try await engine.encode(request(try source(), EditDocument(), format: format), to: url)
            let imageSource = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
            XCTAssertEqual(CGImageSourceGetCount(imageSource), 1, "\(format)")
        }
    }

    private func pixels(_ image: CGImage) throws -> [UInt8] {
        // Normalize to 16-bit RGBA so both sources compare byte-for-byte.
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 8)
        let context = try XCTUnwrap(CGContext(
            data: &bytes, width: image.width, height: image.height, bitsPerComponent: 16,
            bytesPerRow: image.width * 8, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder16Little.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return bytes
    }
}

import CoreImage
import Foundation
import XCTest
@testable import KromoraKit

/// KRMA-1218: export rasterization blocks its own engine's actor on `waitUntilCompleted()`. These
/// tests hold that work deterministically and prove a visible-preview request on a separate engine
/// still completes with unchanged pixels. Preview revision and cancellation behavior is covered by
/// the coordinator and idle-warmer suites.
@MainActor
final class BackgroundRenderIsolationTests: TempDirectoryTestCase {
    /// Parks the export rasterizer until the test releases it.
    private final class Gate: @unchecked Sendable {
        let entered = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
    }

    private func source() throws -> ImageSource {
        let url = try Fixtures.writeGradientPNG(width: 64, height: 32, named: "iso.png", in: tempDirectory)
        return ImageSource(url: url, nativeExtent: CGSize(width: 64, height: 32))
    }

    private func exportRequest(_ source: ImageSource) -> RenderRequest {
        let options = ExportOptions(format: .jpeg, destination: nil)
        return RenderRequest(
            source: source, document: EditDocument(), lut: nil, quality: .export,
            output: .encoded(format: .jpeg, quality: CGFloat(options.quality)),
            space: options.colorSpace, exportOptions: options
        )
    }

    private func previewRequest(_ source: ImageSource, revision: UInt64 = 1) -> RenderRequest {
        var document = EditDocument()
        document.effects.vignette.amount = -20
        return RenderRequest(
            source: source, document: document, lut: nil, quality: .interactive,
            output: .raster, space: .sRGB, requestRevision: revision
        )
    }

    private func bytes(_ image: CGImage) -> Data? { image.dataProvider?.data as Data? }

    private func heldExport(_ source: ImageSource, gate: Gate) -> (RenderEngine, Task<Void, Error>) {
        let held = ExportRasterizer { _, _, _, _, _ in
            gate.entered.signal()
            gate.release.wait()
            throw ImageError.exportFailed
        }
        let exportEngine = RenderEngine(exportRasterizer: held)
        let staged = tempDirectory.appendingPathComponent("held.jpg")
        let request = exportRequest(source)
        return (exportEngine, Task.detached { try await exportEngine.encode(request, to: staged) })
    }

    private func waitForEntry(_ gate: Gate) async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                continuation.resume(returning: gate.entered.wait(timeout: .now() + 10) == .success)
            }
        }
    }

    func testPreviewProgressesWhileExportRasterizationIsHeld() async throws {
        let source = try source()
        let reference = await RenderEngine().makeCGImage(previewRequest(source))
        let gate = Gate()
        let (_, export) = heldExport(source, gate: gate)
        defer { gate.release.signal() }
        let entered = await waitForEntry(gate)
        XCTAssertTrue(entered, "the export rasterizer must reach the held gate")

        let preview = await RenderEngine().makeCGImage(previewRequest(source))
        XCTAssertNotNil(preview, "the preview must complete while export holds its own engine")
        XCTAssertEqual(bytes(try XCTUnwrap(preview)), bytes(try XCTUnwrap(reference)), "pixel parity")

        gate.release.signal()
        _ = try? await export.value
    }

    func testPreviewProgressesWhileCancelledExportRemainsHeld() async throws {
        let source = try source()
        let gate = Gate()
        let (_, export) = heldExport(source, gate: gate)
        defer { gate.release.signal() }
        let entered = await waitForEntry(gate)
        XCTAssertTrue(entered, "the export rasterizer must reach the held gate")
        export.cancel()
        XCTAssertTrue(export.isCancelled)

        let preview = await RenderEngine().makeCGImage(previewRequest(source))
        XCTAssertNotNil(preview)

        gate.release.signal()
        _ = try? await export.value
    }

    func testBackgroundWorkUsesAnEngineSeparateFromThePreview() throws {
        let previewEngine = RenderEngine()
        let model = AppViewModel(
            engine: previewEngine,
            portablePackageURL: tempDirectory.appendingPathComponent("lib.kromoralibrary"))
        let backgroundEngine = try XCTUnwrap(model.backgroundEngine as? RenderEngine)
        XCTAssertFalse(backgroundEngine === previewEngine)
    }
}

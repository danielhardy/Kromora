import AppKit
import Darwin
import XCTest

@testable import KromoraKit

/// KRMA-1048 — peak memory of a multi-photo Share Copy through the real render and pasteboard path.
@MainActor
final class ShareCopyMemoryTests: XCTestCase {
    private final class Destination: ExportWorkflowDestination {
        var exportSelectionCount = 0
        var exportActiveAssetID: PhotoAssetID?
        var exportSourceName = ""
        var exportSingleRequest: ExportSingleRequest?
        var statuses: [String] = []
        func exportBatchRequest(selectedOnly: Bool) -> ExportBatchRequest {
            ExportBatchRequest(items: [], document: EditDocument(), lut: nil)
        }
        func setExportStatus(_ message: String) { statuses.append(message) }
        func presentExportError(_ message: String) {}
    }

    nonisolated private static func physFootprint() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.phys_footprint : 0
    }

    private func makeWorkflow(engine: any RenderEngining) -> (ExportWorkflowCoordinator, Destination) {
        let destination = Destination()
        let workflow = ExportWorkflowCoordinator(
            export: ExportCoordinator(engine: engine, photosDelivery: nil),
            sheets: FakeSheets(), destination: destination
        )
        return (workflow, destination)
    }

    private func jpeg(width: Int, height: Int) throws -> Data {
        let rep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        return try XCTUnwrap(rep.representation(using: .jpeg, properties: [:]))
    }

    // MARK: - Production cap (deterministic)

    func testProductionCapRejectsASelectionPastItBeforeWritingAnything() async throws {
        let (workflow, destination) = makeWorkflow(engine: FakeRenderEngine())
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("kromora-test-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        workflow.sharePasteboard = pasteboard
        pasteboard.clearContents()
        pasteboard.setString("previous", forType: .string)

        // One buffer shared by every item, so the test itself holds 32 MiB regardless of count.
        let chunk = Data(count: 32 * 1024 * 1024)
        var encoded = 0
        let items = (0..<ShareCopyPolicy.maxTotalBytes / chunk.count + 2).map { _ in
            ShareCopyItem { _ in
                encoded += 1
                return chunk
            }
        }

        await workflow.copyToPasteboard(items)

        XCTAssertEqual(encoded, ShareCopyPolicy.maxTotalBytes / chunk.count + 1,
                       "rendering stops at the first image that crosses the production cap")
        XCTAssertEqual(pasteboard.string(forType: .string), "previous")
        XCTAssertNil(pasteboard.pasteboardItems?.first?.data(forType: ShareCopyPolicy.pasteboardType))
        XCTAssertEqual(
            destination.statuses.last,
            "Too many photos to copy at once. Select fewer photos and try again."
        )
    }

    func testUnderTheProductionCapEveryPhotoIsWrittenAndDecodes() async throws {
        let (workflow, destination) = makeWorkflow(engine: FakeRenderEngine())
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("kromora-test-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        workflow.sharePasteboard = pasteboard
        let data = try jpeg(width: 64, height: 48)
        let items = (0..<12).map { _ in ShareCopyItem { _ in data } }

        await workflow.copyToPasteboard(items)

        let written = try XCTUnwrap(pasteboard.pasteboardItems)
        XCTAssertEqual(written.count, 12)
        for item in written {
            let bytes = try XCTUnwrap(item.data(forType: ShareCopyPolicy.pasteboardType))
            XCTAssertEqual(try XCTUnwrap(NSBitmapImageRep(data: bytes)).pixelsWide, 64)
        }
        XCTAssertEqual(destination.statuses.last, "Copied 12 photos")
    }

    // MARK: - Measurement (opt-in; not an assertion)

    /// Copies `KROMORA_SHARE_COPY_COUNT` photos (cycling the local RAW fixtures) through the real
    /// engine and the production byte cap, sampling peak `phys_footprint`. Run with
    /// `KROMORA_SHARE_COPY_MEMORY=1`, in its own process per count for a clean peak.
    func testMeasurePeakFootprintForMultiPhotoCopy() async throws {
        let environment = ProcessInfo.processInfo.environment
        try XCTSkipUnless(environment["KROMORA_SHARE_COPY_MEMORY"] == "1", "opt-in measurement")
        let raws = Fixtures.localRAWURLs
        try XCTSkipIf(raws.isEmpty, "no RAW fixtures in realworldtest/ or KROMORA_RAW_FIXTURE_DIR")
        let count = Int(environment["KROMORA_SHARE_COPY_COUNT"] ?? "") ?? 24
        let byteLimit = Int(environment["KROMORA_SHARE_COPY_LIMIT"] ?? "") ?? ShareCopyPolicy.maxTotalBytes

        let (workflow, destination) = makeWorkflow(engine: RenderEngine())
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("kromora-test-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        workflow.sharePasteboard = pasteboard
        let export = ExportCoordinator(engine: RenderEngine(), photosDelivery: nil)
        var encodedBytes = 0
        let items = (0..<count).map { index -> ShareCopyItem in
            let url = raws[index % raws.count]
            let batchItem = ExportCoordinator.BatchItem(url: url, data: nil, name: url.lastPathComponent)
            return ShareCopyItem { options in
                let data = try await export.renderEncodedData(
                    for: batchItem, document: EditDocument(), lut: nil, options: options
                )
                encodedBytes += data.count
                return data
            }
        }

        let baseline = Self.physFootprint()
        let sampler = Task.detached {
            var peak: UInt64 = 0
            while !Task.isCancelled {
                peak = max(peak, Self.physFootprint())
                try? await Task.sleep(for: .milliseconds(10))
            }
            return peak
        }
        await workflow.copyToPasteboard(items, byteLimit: byteLimit)
        let afterCopy = Self.physFootprint()
        sampler.cancel()
        let peak = max(await sampler.value, afterCopy)
        let mb = { (v: UInt64) in Double(v) / 1_048_576 }
        print("KRMA-1048 count \(count), limit \(Double(byteLimit) / 1_048_576) MB: "
              + "baseline \(mb(baseline)) MB, peak \(mb(peak)) MB, delta \(mb(peak &- baseline)) MB, "
              + "after copy \(mb(afterCopy)) MB, encoded \(Double(encodedBytes) / 1_048_576) MB, "
              + "pasteboard items \(pasteboard.pasteboardItems?.count ?? 0), "
              + "status \(destination.statuses.last ?? "-")")
    }
}

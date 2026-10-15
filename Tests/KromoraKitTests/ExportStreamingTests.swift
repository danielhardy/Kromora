import XCTest
import ImageIO
import Darwin
@testable import KromoraKit

/// KRMA-942 — export encodes straight to a staging file instead of through an in-memory buffer.
@MainActor
final class ExportStreamingTests: TempDirectoryTestCase {

    private func makeSource(width: Int = 96, height: Int = 64) throws -> ImageSource {
        let url = try Fixtures.writeGradientPNG(
            width: width, height: height, named: "shot.png", in: tempDirectory
        )
        return ImageSource(url: url, nativeExtent: CGSize(width: width, height: height))
    }

    private func request(
        _ source: ImageSource, options: ExportOptions
    ) -> RenderRequest {
        RenderRequest(
            source: source, document: EditDocument(), lut: nil, quality: .export,
            output: .encoded(format: options.format, quality: CGFloat(options.quality)),
            space: options.colorSpace, exportOptions: options
        )
    }

    private func makeItem() throws -> ExportCoordinator.BatchItem {
        let url = try Fixtures.writeGradientPNG(
            width: 96, height: 64, named: "shot.png", in: tempDirectory
        )
        return ExportCoordinator.BatchItem(url: url, data: nil, name: "shot")
    }

    private func partials(in folder: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.hasSuffix(".partial") }
    }

    private func properties(of data: Data) throws -> [String: Any] {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let props = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any])
        return props
    }

    // MARK: - Output parity

    func testStreamedEncodeMatchesBufferedEncodePixelsAndMetadata() async throws {
        let engine = RenderEngine()
        let source = try makeSource()
        for format in [ExportFormat.jpeg, .heif, .tiff] {
            let options = ExportOptions(format: format, destination: nil)
            let req = request(source, options: options)
            let buffered = try await engine.render(req).data

            let staged = tempDirectory.appendingPathComponent("streamed.\(format.fileExtension)")
            try await engine.encode(req, to: staged)
            let streamed = try Data(contentsOf: staged)

            XCTAssertEqual(
                try Pixels.bytes(of: try Pixels.decode(streamed)),
                try Pixels.bytes(of: try Pixels.decode(buffered)),
                "\(format) pixels differ"
            )
            let a = try properties(of: streamed), b = try properties(of: buffered)
            for key in ["PixelWidth", "PixelHeight", "Depth", "ColorModel", "HasAlpha", "ProfileName"] {
                XCTAssertEqual(
                    a[key] as? NSObject, b[key] as? NSObject, "\(format) \(key) differs"
                )
            }
            XCTAssertEqual(Set(a.keys), Set(b.keys), "\(format) metadata dictionaries differ")
        }
    }

    // MARK: - Staging cleanup

    func testSuccessfulExportLeavesNoPartialFile() async throws {
        let coordinator = ExportCoordinator(engine: RenderEngine())
        coordinator.onError = { XCTFail("unexpected error: \($0)") }
        let folder = tempDirectory.appendingPathComponent("out")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let outcome = await coordinator.performBatchExport(
            [try makeItem()],
            document: EditDocument(), lut: nil, format: .tiff, to: folder
        )
        XCTAssertEqual(outcome.exported, 1)
        XCTAssertEqual(try partials(in: folder), [])
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: folder.path), ["shot.tif"]
        )
    }

    func testFailedEncodeLeavesNoPartialFile() async throws {
        let fake = FakeRenderEngine()
        await fake.setShouldFailEncode(true)
        let coordinator = ExportCoordinator(engine: fake)
        coordinator.onError = { _ in }
        let folder = tempDirectory.appendingPathComponent("out")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let outcome = await coordinator.performBatchExport(
            [try makeItem()],
            document: EditDocument(), lut: nil, format: .jpeg, to: folder
        )
        XCTAssertEqual(outcome.failed, 1)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), [])
    }

    func testFailedEncodeAfterWritingPartialStagingFileRemovesIt() async throws {
        let fake = FakeRenderEngine()
        await fake.setFailAfterWritingPartialStagingFile(true)
        let coordinator = ExportCoordinator(engine: fake)
        let folder = tempDirectory.appendingPathComponent("partial-failure")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let outcome = await coordinator.performBatchExport(
            [try makeItem()], document: EditDocument(), lut: nil, format: .jpeg, to: folder
        )

        XCTAssertEqual(outcome.failed, 1)
        let wrotePartialBeforeFailure = await fake.didWritePartialStagingFile
        XCTAssertTrue(wrotePartialBeforeFailure)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), [])
    }

    func testCancelledEncodeAfterWritingPartialStagingFileRemovesIt() async throws {
        let fake = FakeRenderEngine()
        await fake.setWaitForCancellationAfterWritingPartialStagingFile(true)
        let coordinator = ExportCoordinator(engine: fake)
        let folder = tempDirectory.appendingPathComponent("partial-cancellation")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let items = [try makeItem()]
        let task = Task {
            await coordinator.performBatchExport(
                items, document: EditDocument(), lut: nil, format: .jpeg, to: folder
            )
        }

        let deadline = Date().addingTimeInterval(10)
        while !(await fake.didWritePartialStagingFile), Date() < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        let wrotePartialBeforeCancellation = await fake.didWritePartialStagingFile
        XCTAssertTrue(wrotePartialBeforeCancellation, "encode should create the partial first")

        coordinator.cancelBatchExport()
        await fake.releasePartialStagedEncode()
        let outcome = await task.value
        XCTAssertEqual(outcome, .init(exported: 0, failed: 0, total: 1, cancelled: true))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), [])
    }

    func testScopedExportCopiesStagedFileAndRemovesTemporary() async throws {
        let coordinator = ExportCoordinator(engine: RenderEngine())
        coordinator.onError = { XCTFail("unexpected error: \($0)") }
        let destination = tempDirectory.appendingPathComponent("selected.tiff")
        let access = SecurityScopedResourceAccess.systemGranted(for: destination) { _ in }
        let before = try FileManager.default.contentsOfDirectory(
            atPath: FileManager.default.temporaryDirectory.path
        ).filter { $0.hasSuffix(".partial") }

        coordinator.performExport(
            source: try makeSource(), document: EditDocument(), lut: nil,
            options: ExportOptions(format: .tiff, destination: .file(destination)),
            to: destination, access: access
        )
        let deadline = Date().addingTimeInterval(10)
        while coordinator.isExporting, Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }

        let written = try Data(contentsOf: destination)
        XCTAssertEqual(try properties(of: written)["PixelWidth"] as? Int, 96)
        let after = try FileManager.default.contentsOfDirectory(
            atPath: FileManager.default.temporaryDirectory.path
        ).filter { $0.hasSuffix(".partial") }
        XCTAssertEqual(Set(after), Set(before), "the temp staging file must be removed")
    }

    // MARK: - Measurement (opt-in; not an assertion)

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

    /// Records peak `phys_footprint` for an 8k×6k 16-bit TIFF through the buffered and streamed
    /// paths. Run with `KROMORA_EXPORT_MEMORY=1`; each path should be run in its own process for a
    /// clean peak (`KROMORA_EXPORT_MEMORY_PATH=buffered|streamed`).
    func testMeasurePeakFootprintForLargeTIFF() async throws {
        let environment = ProcessInfo.processInfo.environment
        try XCTSkipUnless(environment["KROMORA_EXPORT_MEMORY"] == "1", "opt-in measurement")
        let path = environment["KROMORA_EXPORT_MEMORY_PATH"] ?? "streamed"
        let source = try makeSource(width: 8192, height: 6144)
        let engine = RenderEngine()
        let options = ExportOptions(format: .tiff, destination: nil)
        let req = request(source, options: options)
        let staged = tempDirectory.appendingPathComponent("big.tiff")

        let baseline = Self.physFootprint()
        let sampler = Task.detached {
            var peak: UInt64 = 0
            while !Task.isCancelled {
                peak = max(peak, Self.physFootprint())
                try? await Task.sleep(for: .milliseconds(5))
            }
            return peak
        }
        var encodedBytes = 0
        if path == "buffered" {
            encodedBytes = try await engine.render(req).data.count
        } else {
            try await engine.encode(req, to: staged)
            encodedBytes = (try FileManager.default.attributesOfItem(atPath: staged.path)[.size] as? Int) ?? 0
        }
        sampler.cancel()
        let peak = max(await sampler.value, Self.physFootprint())
        let mb = { (v: UInt64) in Double(v) / 1_048_576 }
        print("KRMA-942 \(path): baseline \(mb(baseline)) MB, peak \(mb(peak)) MB, "
              + "delta \(mb(peak &- baseline)) MB, encoded \(Double(encodedBytes) / 1_048_576) MB")
    }
}

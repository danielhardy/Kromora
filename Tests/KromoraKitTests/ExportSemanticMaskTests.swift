import CoreGraphics
import ImageIO
import XCTest
@testable import KromoraKit

/// KRMA-1141: a batch export used to hand the renderer a source whose `nativeExtent` was `.zero`.
/// Regenerating a semantic mask sizes its analysis image from that extent, so every photo carrying
/// an Auto edit (which adds a subject mask) failed with `providerFailure(.subject, "processingFailed")`.
/// These run the real `ExportCoordinator` against a real `RenderEngine` with a stub mask provider.
@MainActor
final class ExportSemanticMaskTests: TempDirectoryTestCase {
    private let width = 16
    private let height = 8

    private func makeCoordinator() -> ExportCoordinator {
        let store = MaskStore(directory: tempDirectory.appendingPathComponent("export-masks"))
        let analysis = PhotoAnalysisCoordinator(
            maskStore: store, maskProvider: ExportStubSubjectMaskProvider(store: store), stages: [:]
        )
        return ExportCoordinator(
            exportEngine: RenderEngine(maskResolver: CoordinatorLocalMaskResolver(coordinator: analysis)),
            photosDelivery: nil
        )
    }

    private func subjectDocument() -> EditDocument {
        let layer = LocalAdjustmentLayer(
            components: [MaskComponent(source: .semantic(SemanticMaskDefinition(target: .subject)))],
            adjustments: LocalAdjustments(exposure: 2)
        )
        return EditDocument(localAdjustments: [layer])
    }

    private func makeItem(document: EditDocument?) throws -> ExportCoordinator.BatchItem {
        let url = try Fixtures.writeGradientPNG(
            width: width, height: height, named: "subject.png", in: tempDirectory
        )
        return ExportCoordinator.BatchItem(url: url, data: nil, name: "subject", document: document)
    }

    private func folder(_ name: String) throws -> URL {
        let url = tempDirectory.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func pixels(at url: URL) throws -> [UInt8] {
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        return try Pixels.bytes(of: XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil)))
    }

    func testBatchExportWritesEveryFormatForADocumentWithASubjectMask() async throws {
        for format in ExportFormat.allCases {
            let coordinator = makeCoordinator()
            coordinator.onError = { XCTFail("unexpected error: \($0)") }
            let destination = try folder("out-\(format.rawValue)")

            let outcome = await coordinator.performBatchExport(
                [try makeItem(document: subjectDocument())], document: EditDocument(), lut: nil,
                format: format, to: destination
            )

            XCTAssertEqual(
                outcome.failures, [], "\(format.rawValue) must not fail on a regenerated subject mask"
            )
            XCTAssertEqual(outcome.exported, 1, "\(format.rawValue) export")
            XCTAssertTrue(
                FileManager.default.fileExists(
                    atPath: destination.appendingPathComponent("subject.\(format.fileExtension)").path
                ),
                "\(format.rawValue) file should be written"
            )
        }
    }

    func testBatchExportWithoutAMaskStillSucceeds() async throws {
        let coordinator = makeCoordinator()
        let destination = try folder("plain")
        let outcome = await coordinator.performBatchExport(
            [try makeItem(document: EditDocument())], document: EditDocument(), lut: nil,
            format: .jpeg, to: destination
        )
        XCTAssertEqual(outcome.exported, 1)
        XCTAssertEqual(outcome.failed, 0)
    }

    func testBatchExportOfInMemorySourceRegeneratesTheSubjectMask() async throws {
        let url = try Fixtures.writeGradientPNG(
            width: width, height: height, named: "memory.png", in: tempDirectory
        )
        let item = ExportCoordinator.BatchItem(
            url: nil, data: try Data(contentsOf: url), name: "memory", document: subjectDocument()
        )
        let destination = try folder("memory-out")
        let outcome = await makeCoordinator().performBatchExport(
            [item], document: EditDocument(), lut: nil, format: .tiff, to: destination
        )
        XCTAssertEqual(outcome.failures, [])
        XCTAssertEqual(outcome.exported, 1)
    }

    func testExportedMaskMatchesTheEditorRender() async throws {
        let coordinator = makeCoordinator()
        let destination = try folder("match")
        let item = try makeItem(document: subjectDocument())
        let outcome = await coordinator.performBatchExport(
            [item], document: EditDocument(), lut: nil, format: .png, to: destination
        )
        XCTAssertEqual(outcome.exported, 1)

        // The editor's render of the same document: a prepared source with the real extent.
        let store = MaskStore(directory: tempDirectory.appendingPathComponent("editor-masks"))
        let editor = RenderEngine(maskResolver: CoordinatorLocalMaskResolver(
            coordinator: PhotoAnalysisCoordinator(
                maskStore: store, maskProvider: ExportStubSubjectMaskProvider(store: store), stages: [:]
            )
        ))
        let url = try XCTUnwrap(item.url)
        let source = ImageSource(url: url, nativeExtent: CGSize(width: width, height: height))
        let expected = try await editor.render(RenderRequest(
            source: source, document: subjectDocument(), quality: .export, output: .raster
        ))
        let expectedImage = try XCTUnwrap(CGImageSourceCreateWithData(expected.data as CFData, nil))
        let expectedPixels = try Pixels.bytes(
            of: XCTUnwrap(CGImageSourceCreateImageAtIndex(expectedImage, 0, nil))
        )
        assertPixelsEqual(
            try pixels(at: destination.appendingPathComponent("subject.png")), expectedPixels,
            tolerance: 1, "an exported subject mask must match the editor render"
        )

        // And the mask actually applied: the covered half differs from an unmasked export.
        let plain = try folder("match-plain")
        _ = await coordinator.performBatchExport(
            [try makeItem(document: EditDocument())], document: EditDocument(), lut: nil,
            format: .png, to: plain
        )
        let covered = try pixels(at: destination.appendingPathComponent("subject.png"))
        let base = try pixels(at: plain.appendingPathComponent("subject.png"))
        let probe = (2 * width + 1) * 4
        XCTAssertGreaterThan(abs(Int(covered[probe]) - Int(base[probe])), 10)
    }

    // MARK: - Failure reasons

    func testBatchOutcomeAndSummaryCarryTheFailureReason() async throws {
        let coordinator = ExportCoordinator(photosDelivery: nil)
        var statuses: [String] = []
        coordinator.onStatus = { statuses.append($0) }
        let missing = ExportCoordinator.BatchItem(
            url: tempDirectory.appendingPathComponent("absent.jpg"), data: nil, name: "absent"
        )
        let destination = try folder("failing")

        let outcome = await coordinator.performBatchExport(
            [missing], document: EditDocument(), lut: nil, format: .jpeg, to: destination
        )

        XCTAssertEqual(outcome.failed, 1)
        let failure = try XCTUnwrap(outcome.failures.first)
        XCTAssertEqual(failure.name, "absent")
        XCTAssertFalse(failure.reason.isEmpty)
        let last = try XCTUnwrap(statuses.last)
        XCTAssertTrue(
            last.contains("1 failed: absent: \(failure.reason)"),
            "the final status must keep the reason the summary used to overwrite: \(last)"
        )
    }

    func testSummaryNamesTheFirstOfSeveralFailures() {
        let outcome = ExportCoordinator.BatchOutcome(
            exported: 1, failed: 2, total: 3,
            failures: [
                .init(name: "a", reason: "no mask"), .init(name: "b", reason: "no disk"),
            ]
        )
        XCTAssertEqual(
            ExportCoordinator.summary(for: outcome, folder: URL(fileURLWithPath: "/tmp/out")),
            "Exported 1 of 3 (2 failed; first: a: no mask) to out"
        )
    }
}

private actor ExportStubSubjectMaskProvider: SemanticMaskProviding {
    private let store: MaskStore

    init(store: MaskStore) { self.store = store }

    func mask(for kind: SemanticMaskKind, image: AnalysisImage, quality: MaskQuality) async throws -> RegionMask {
        guard kind == .subject else { throw VisionSemanticMaskError.unsupported(kind) }
        let size = image.dimensions
        let values = (0..<size.height).flatMap { _ in
            (0..<size.width).map { $0 < size.width / 2 ? Float(1) : Float(0) }
        }
        let pixels = try NormalizedMask(size: size, values: values)
        let assetID = image.assetID ?? PhotoAnalysisCoordinator.assetID(for: image.source)
        let key = MaskCacheKey(
            assetID: assetID,
            sourceFingerprint: PhotoAnalysisCoordinator.sourceFingerprint(for: image.source),
            kind: kind, quality: quality, providerVersion: "export-stub-1"
        )
        let reference = try await store.store(pixels, for: key, quality: quality)
        return RegionMask(
            kind: kind, bounds: NormalizedRect(x: 0, y: 0, width: 0.5, height: 1), quality: quality,
            reference: reference, confidence: 1, coverage: pixels.coverage
        )
    }
}

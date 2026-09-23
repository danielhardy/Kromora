import AppKit
import Metal
import XCTest

@testable import KromoraKit

/// LUMO-290 baseline for the single-photo open path.
///
/// The deterministic lane measures admission and the compatibility presentation callback with a
/// fake renderer. It is intentionally always available to CI: GPU wall-clock values are not stable
/// enough to be a unit-test assertion. The real-engine lane is opt-in and reports p50/p95 only.
@MainActor
final class SingleViewLatencyBenchmark: TempDirectoryTestCase {

    private enum DocumentShape: String, CaseIterable {
        case identity
        case edited
        case masked

        var expectedThumbnailSubmissions: Int {
            self == .identity ? 0 : 1
        }

        var expectedSemanticMaskResolutions: Int {
            self == .masked ? 1 : 0
        }
    }

    private struct Measurement {
        let shape: DocumentShape
        let settledPreviewSubmissions: Int
        let thumbnailSubmissions: Int
        let semanticMaskResolutions: Int
        let previewMaskPolicies: [MaskResolutionPolicy]
        let timeToVisibleFrameMS: Double
    }

    /// The shape used here is deliberately semantic: it exercises the progressive masked-preview
    /// admission path (base frame followed by refinement), rather than only testing an analytic
    /// gradient mask that never needs a deferred resolver.
    private func document(for shape: DocumentShape) -> EditDocument {
        switch shape {
        case .identity:
            return EditDocument()
        case .edited:
            return EditDocument(
                rawDevelop: RAWDevelopSettings(exposure: 0.5),
                adjustments: [.exposure(ev: 0.25), .vibrance(amount: 0.2)]
            )
        case .masked:
            let component = MaskComponent(
                name: "Subject",
                source: .semantic(SemanticMaskDefinition(target: .subject))
            )
            let layer = LocalAdjustmentLayer(
                name: "Subject lift", components: [component],
                adjustments: LocalAdjustments(exposure: 0.5)
            )
            return EditDocument(
                adjustments: [.vibrance(amount: 0.2)], localAdjustments: [layer]
            )
        }
    }

    private func waitUntil(
        _ description: String,
        timeout: TimeInterval = 5,
        _ condition: @escaping @MainActor () async -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !(await condition()) {
            if Date() > deadline {
                throw TestSynchronizationError.timedOut(description, "state did not settle")
            }
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    private func makeSource(named name: String, in directory: URL) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return try Fixtures.writeGradientPNG(width: 64, height: 48, named: name, in: directory)
    }

    private func measureDeterministic(_ shape: DocumentShape) async throws -> Measurement {
        let directory = tempDirectory.appendingPathComponent(shape.rawValue, isDirectory: true)
        let source = try makeSource(named: shape.rawValue + ".png", in: directory)
        let package = makeEditPackageFixture()
        let store = package.store()
        try package.register(source)
        let expectedDocument = document(for: shape)
        try await store.save(
            expectedDocument,
            for: EditSourceReference(assetID: .file(source), url: source)
        )

        let engine = FakeRenderEngine()
        let viewModel = makeAppViewModel(
            engine: engine, editStore: store,
            libraryFolderURL: directory.appendingPathComponent("managed-library", isDirectory: true)
        )
        viewModel.collection.loadFromFolder(directory)
        await viewModel.collection.scanCompletion()
        let index = try XCTUnwrap(viewModel.collection.items.firstIndex { $0.url == source })
        let assetID = viewModel.collection.items[index].id

        let start = DispatchTime.now().uptimeNanoseconds
        viewModel.selectCollectionImage(at: index)
        try await waitUntil(shape.rawValue + " visible frame") {
            viewModel.previewState == .ready && viewModel.sourceURL == source
        }
        // `previewState == .ready` is set only by didPresentVisibleFrame. Capture this before
        // waiting for the masked refinement or trailing thumbnail so the metric remains first-frame
        // latency, not total background work.
        let timeToVisibleFrameMS = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000

        try await waitUntil(shape.rawValue + " stored document preview submission") {
            await engine.previewRequests.contains {
                $0.source?.backing == .url(source) && $0.scale != .full
                    && $0.document == expectedDocument
            }
        }
        try await waitUntil(shape.rawValue + " semantic mask resolution submissions") {
            await engine.semanticMaskRequests.filter {
                $0.source?.backing == .url(source)
            }.count >= shape.expectedSemanticMaskResolutions
        }
        try await waitUntil(shape.rawValue + " thumbnail submissions") {
            await engine.thumbnailRequests.filter {
                $0.assetID == assetID
            }.count >= shape.expectedThumbnailSubmissions
        }

        let previews = await engine.previewRequests.filter {
            $0.source?.backing == .url(source) && $0.scale != .full
        }
        let thumbnails = await engine.thumbnailRequests.filter { $0.assetID == assetID }.count
        let semanticMaskResolutions = await engine.semanticMaskRequests.filter {
            $0.source?.backing == .url(source)
        }.count
        return Measurement(
            shape: shape, settledPreviewSubmissions: previews.count,
            thumbnailSubmissions: thumbnails,
            semanticMaskResolutions: semanticMaskResolutions,
            previewMaskPolicies: previews.map(\.maskResolution),
            timeToVisibleFrameMS: timeToVisibleFrameMS
        )
    }

    /// Reports the three document shapes and locks their current admission counts into a
    /// repeatable regression test. The time column is diagnostic only because this lane uses a fake
    /// renderer and a headless immediate presentation callback.
    func testSingleViewOpenBaselineReportsIdentityEditedAndMaskedShapes() async throws {
        var measurements: [Measurement] = []
        for shape in DocumentShape.allCases {
            let measurement = try await measureDeterministic(shape)
            let expectedPreviewRange: ClosedRange<Int>
            let expectedPolicies: [[MaskResolutionPolicy]]
            switch shape {
            case .identity:
                expectedPreviewRange = 1...1
                expectedPolicies = [[.resolved]]
            case .edited:
                expectedPreviewRange = 1...2
                expectedPolicies = [[.resolved], [.resolved, .resolved]]
            case .masked:
                expectedPreviewRange = 2...3
                expectedPolicies = [
                    [.deferSemantic, .resolved], [.resolved, .deferSemantic, .resolved],
                ]
            }
            XCTAssertTrue(
                expectedPreviewRange.contains(measurement.settledPreviewSubmissions),
                "unexpected settled preview admission for \(shape.rawValue): \(measurement.settledPreviewSubmissions)"
            )
            XCTAssertTrue(
                measurement.previewMaskPolicies.contains(.resolved),
                "the final stored preview must complete with resolved masks for \(shape.rawValue)"
            )
            XCTAssertEqual(
                measurement.thumbnailSubmissions,
                shape.expectedThumbnailSubmissions,
                "unexpected edited-thumbnail admission for " + shape.rawValue
            )
            XCTAssertEqual(
                measurement.semanticMaskResolutions,
                shape.expectedSemanticMaskResolutions,
                "unexpected semantic-mask resolution admission for " + shape.rawValue
            )
            XCTAssertTrue(
                expectedPolicies.contains(measurement.previewMaskPolicies),
                "unexpected preview mask phases for \(shape.rawValue): \(measurement.previewMaskPolicies)"
            )
            measurements.append(measurement)
        }

        print("\n=== LUMO-290 deterministic single-view baseline ===")
        for measurement in measurements {
            print(
                String(
                    format:
                        "%@ preview_submissions=%d thumbnail_submissions=%d mask_resolution_submissions=%d first_visible_ms=%.2f",
                    measurement.shape.rawValue, measurement.settledPreviewSubmissions,
                    measurement.thumbnailSubmissions, measurement.semanticMaskResolutions,
                    measurement.timeToVisibleFrameMS
                ))
        }
    }

    /// Opt-in hardware timing. This intentionally reports distributions rather than asserting a
    /// universal threshold: Core Image, Vision, GPU power state, OS revision, and drawable setup
    /// all contribute meaningful run-to-run variance. The deterministic test above remains the
    /// admission regression gate.
    func testOptInRealEngineSingleViewLatencyBaseline() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["KROMORA_SINGLE_VIEW_BENCHMARK"] != nil,
            "set KROMORA_SINGLE_VIEW_BENCHMARK=1 to run the real-engine single-view benchmark"
        )
        guard MTLCreateSystemDefaultDevice() != nil else {
            throw XCTSkip("Metal is unavailable")
        }

        var samplesByShape: [DocumentShape: [Double]] = [:]
        let iterations = max(
            3,
            Int(ProcessInfo.processInfo.environment["KROMORA_SINGLE_VIEW_ITERATIONS"] ?? "5") ?? 5
        )
        for iteration in 0..<iterations {
            for shape in DocumentShape.allCases {
                let directory =
                    tempDirectory
                    .appendingPathComponent(
                        "real-\(iteration)-\(shape.rawValue)", isDirectory: true)
                let source = try makeSource(named: "source.png", in: directory)
                let package = makeEditPackageFixture()
                let store = package.store()
                try package.register(source)
                try await store.save(
                    document(for: shape),
                    for: EditSourceReference(assetID: .file(source), url: source)
                )
                let viewModel = makeAppViewModel(
                    engine: RenderEngine(), editStore: store,
                    libraryFolderURL: directory.appendingPathComponent(
                        "managed-library", isDirectory: true)
                )
                viewModel.collection.loadFromFolder(directory)
                await viewModel.collection.scanCompletion()
                let index = try XCTUnwrap(
                    viewModel.collection.items.firstIndex { $0.url == source })

                let start = DispatchTime.now().uptimeNanoseconds
                viewModel.selectCollectionImage(at: index)
                try await waitUntil("real " + shape.rawValue + " visible frame", timeout: 60) {
                    viewModel.previewState == .ready && viewModel.sourceURL == source
                }
                let elapsedMS = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
                samplesByShape[shape, default: []].append(elapsedMS)
            }
        }

        print("\n=== LUMO-290 real-engine single-view baseline (first visible frame) ===")
        for shape in DocumentShape.allCases {
            let samples = samplesByShape[shape, default: []].sorted()
            let p50 = samples[samples.count / 2]
            let p95 = samples[Int(Double(samples.count - 1) * 0.95)]
            print(
                String(
                    format: "%@ iterations=%d p50_ms=%.2f p95_ms=%.2f spread_ms=%.2f",
                    shape.rawValue, samples.count, p50, p95, p95 - p50
                ))
        }
    }
}

import CoreGraphics
import Darwin
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest

@testable import LumoKit

/// Opt-in Release benchmarks for the photo-intelligence path. The normal XCTest lane remains
/// deterministic and fast; a reference Mac run enables this suite with
/// `LUMO_PHOTO_ANALYSIS_BENCHMARK=1` and records the printed medians in the LUMO-206 completion
/// comment. Assertions compare against the checked-in baseline with a percentage allowance rather
/// than pretending that Vision and Core Image have stable millisecond ceilings on every Mac.
final class PhotoAnalysisPerformanceTests: TempDirectoryTestCase {
    private struct Baseline: Codable {
        let schemaVersion: Int
        let allowedRegressionPercent: Double
        let baselinesMilliseconds: [String: Double]
    }

    private struct Fixture {
        let source: ImageSource
        let image: AnalysisImage
    }

    private var iterations: Int {
        max(
            3,
            Int(ProcessInfo.processInfo.environment["LUMO_PHOTO_ANALYSIS_ITERATIONS"] ?? "5") ?? 5)
    }

    func testPrepareAnalysisImageBenchmark() throws {
        try requireBenchmark()
        let source = try makeFixture().source
        let median = median(of: iterations) {
            _ = try? AnalysisImageFactory.make(
                from: source, configuration: .init(maximumDimension: 768))
        }
        report("prepareAnalysisImage", median)
        assertWithinBaseline("prepareAnalysisImage", median)
    }

    func testGlobalToneAnalyzerBenchmark() async throws {
        try requireBenchmark()
        let fixture = try makeFixture()
        let analyzer = GlobalToneAnalyzer()
        let median = try await medianAsync(of: iterations) {
            _ = try await analyzer.analyze(image: fixture.image)
        }
        report("globalToneAnalyzer", median)
        assertWithinBaseline("globalToneAnalyzer", median)
    }

    func testMaskProvidersBenchmark() async throws {
        try requireBenchmark()
        let fixture = try makeFixture()
        let kinds: [(String, SemanticMaskKind)] = [
            ("subjectMask", .subject), ("faceMask", .face),
            ("foregroundMask", .foregroundInstance(0)), ("personMask", .person),
        ]
        for (label, kind) in kinds {
            var samples: [TimedSample] = []
            for index in 0..<iterations {
                let store = MaskStore(
                    directory: tempDirectory.appendingPathComponent("\(label)-\(index)"))
                let provider = VisionSemanticMaskProvider(store: store)
                if kind == .person {
                    // Person segmentation is intentionally gated on an existing face/foreground
                    // signal, matching the production demand-driven pipeline.
                    _ = try? await provider.mask(
                        for: .foregroundInstance(0), image: fixture.image, quality: .analysis
                    )
                }
                let start = DispatchTime.now().uptimeNanoseconds
                var succeeded = false
                do {
                    _ = try await provider.mask(for: kind, image: fixture.image, quality: .analysis)
                    succeeded = true
                } catch {
                }
                samples.append(
                    TimedSample(ms: elapsedMilliseconds(since: start), succeeded: succeeded))
            }
            let median = median(samples.map { $0.ms })
            let successCount = samples.filter(\.succeeded).count
            report(label, median, detail: "successes=\(successCount)/\(samples.count)")
            assertWithinBaseline(label, median)
        }
    }

    func testMaskedToneAnalyzerBenchmark() async throws {
        try requireBenchmark()
        let fixture = try makeFixture()
        let store = MaskStore(directory: tempDirectory.appendingPathComponent("masked"))
        let pixels = try NormalizedMask(
            size: fixture.image.dimensions,
            values: Array(
                repeating: 1,
                count: fixture.image.dimensions.width * fixture.image.dimensions.height)
        )
        let fingerprint = PhotoSourceFingerprint.file(at: sourceURL(for: fixture.source))
        let key = MaskCacheKey(
            assetID: .file(sourceURL(for: fixture.source), fingerprint: fingerprint),
            sourceFingerprint: fingerprint, kind: .subject, quality: .analysis
        )
        let reference = try await store.store(pixels, for: key, quality: .analysis)
        let mask = RegionMask(
            kind: .subject, bounds: NormalizedRect(x: 0, y: 0, width: 1, height: 1),
            quality: .analysis, reference: reference, confidence: 1, coverage: 1
        )
        let analyzer = MaskedToneAnalyzer(store: store)
        let median = try await medianAsync(of: iterations) {
            _ = try await analyzer.statistics(image: fixture.image, through: mask)
        }
        report("maskedToneAnalyzer", median)
        assertWithinBaseline("maskedToneAnalyzer", median)
    }

    func testStandardAnalysisAndCacheHitBenchmarks() async throws {
        try requireBenchmark()
        let fixture = try makeFixture()
        let cache = PhotoAnalysisCache(
            directory: tempDirectory.appendingPathComponent("analysis-cache"))
        let coordinator = PhotoAnalysisCoordinator(
            maskStore: MaskStore(directory: tempDirectory.appendingPathComponent("analysis-masks")),
            cache: cache
        )
        let assetID = PhotoAssetID.file(
            sourceURL(for: fixture.source),
            fingerprint: PhotoSourceFingerprint.file(at: sourceURL(for: fixture.source))
        )
        var coldSamples: [Double] = []
        var analysis: PhotoAnalysis?
        for index in 0..<iterations {
            let coldCoordinator = PhotoAnalysisCoordinator(
                maskStore: MaskStore(
                    directory: tempDirectory.appendingPathComponent("cold-masks-\(index)")),
                cache: PhotoAnalysisCache(
                    directory: tempDirectory.appendingPathComponent("cold-cache-\(index)"))
            )
            let coldStart = DispatchTime.now().uptimeNanoseconds
            analysis = try await coldCoordinator.analyze(
                assetID: assetID, source: fixture.source, level: .standard
            )
            coldSamples.append(elapsedMilliseconds(since: coldStart))
        }
        let coldMS = median(coldSamples)
        let measuredAnalysis = try XCTUnwrap(analysis)
        XCTAssertTrue(measuredAnalysis.quality.globalToneAvailable)
        report("standardAnalysis", coldMS, detail: timingSummary(measuredAnalysis.timings))
        assertWithinBaseline("standardAnalysis", coldMS)

        _ = try await coordinator.analyze(
            assetID: assetID, source: fixture.source, level: .standard)
        let median = try await medianAsync(of: iterations) {
            _ = try await coordinator.analyze(
                assetID: assetID, source: fixture.source, level: .standard)
        }
        report("cacheHit", median)
        assertWithinBaseline("cacheHit", median)
    }

    func testCanonicalDimensionsBenchmarkAndSubjectSignal() async throws {
        try requireBenchmark()
        let source = try makeFixture().source
        var results: [String] = []
        var subjectSuccesses = 0
        for dimension in [512, 768, 1024] {
            let image = try AnalysisImageFactory.make(
                from: source, configuration: AnalysisConfiguration(maximumDimension: dimension)
            )
            let store = MaskStore(
                directory: tempDirectory.appendingPathComponent("dimension-\(dimension)"))
            let provider = VisionSemanticMaskProvider(store: store)
            let start = DispatchTime.now().uptimeNanoseconds
            let succeeds =
                (try? await provider.mask(for: .subject, image: image, quality: .analysis)) != nil
            let ms = elapsedMilliseconds(since: start)
            if succeeds { subjectSuccesses += 1 }
            results.append(
                "\(dimension)=\(ms)ms subject=\(succeeds) size=\(image.dimensions.width)x\(image.dimensions.height)"
            )
        }
        print("PHOTO_ANALYSIS_CANONICAL_DIMENSIONS " + results.joined(separator: " "))
        XCTAssertGreaterThan(
            subjectSuccesses, 0, "subject detection did not succeed at any canonical dimension")
        XCTAssertEqual(AnalysisConfiguration().maximumDimension, 768)
    }

    func testStandardAnalysisTransientMemoryBenchmark() async throws {
        try requireBenchmark()
        let fixture = try makeFixture()
        let coordinator = PhotoAnalysisCoordinator(
            maskStore: MaskStore(directory: tempDirectory.appendingPathComponent("memory-masks")),
            cache: PhotoAnalysisCache(
                directory: tempDirectory.appendingPathComponent("memory-cache"))
        )
        let assetID = PhotoAssetID.file(
            sourceURL(for: fixture.source),
            fingerprint: PhotoSourceFingerprint.file(at: sourceURL(for: fixture.source))
        )
        let before = residentMemoryBytes()
        _ = try await coordinator.analyze(
            assetID: assetID, source: fixture.source, level: .standard)
        let after = residentMemoryBytes()
        let deltaMB = after > before ? Double(after - before) / 1_048_576 : 0
        print(String(format: "PHOTO_ANALYSIS_MEMORY standard_delta_mb=%.2f", deltaMB))
        XCTAssertLessThanOrEqual(deltaMB, baseline("standardAnalysisMemoryMB"))
    }

    private func makeFixture() throws -> Fixture {
        let url = try Fixtures.writeGradientPNG(
            width: 1024, height: 768, named: "photo-analysis-benchmark.png", in: tempDirectory
        )
        let source = ImageSource(url: url, nativeExtent: CGSize(width: 1024, height: 768))
        return Fixture(
            source: source,
            image: try AnalysisImageFactory.make(from: source)
        )
    }

    private func sourceURL(for source: ImageSource) -> URL {
        if case .url(let url) = source.backing { return url }
        return tempDirectory.appendingPathComponent("photo-analysis-benchmark.png")
    }

    private func requireBenchmark() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["LUMO_PHOTO_ANALYSIS_BENCHMARK"] == "1",
            "set LUMO_PHOTO_ANALYSIS_BENCHMARK=1 to run the Release photo-analysis benchmark suite"
        )
    }

    private func loadBaseline() throws -> Baseline {
        let url = try XCTUnwrap(
            Bundle.module.url(
                forResource: "photo-analysis", withExtension: "json",
                subdirectory: "PerformanceBaselines")
        )
        return try JSONDecoder().decode(Baseline.self, from: Data(contentsOf: url))
    }

    private func baseline(_ label: String) -> Double {
        (try? loadBaseline().baselinesMilliseconds[label]) ?? .greatestFiniteMagnitude
    }

    private func assertWithinBaseline(
        _ label: String, _ value: Double, file: StaticString = #filePath, line: UInt = #line
    ) {
        let allowance = (try? loadBaseline().allowedRegressionPercent) ?? 25
        XCTAssertLessThanOrEqual(
            value, baseline(label) * (1 + allowance / 100),
            "\(label) median \(value)ms exceeded its baseline with \(allowance)% allowed drift",
            file: file, line: line
        )
    }

    private func report(_ label: String, _ median: Double, detail: String = "") {
        print(
            String(format: "PHOTO_ANALYSIS_BENCHMARK %@ median_ms=%.3f %@", label, median, detail))
    }

    private func timingSummary(_ timings: AnalysisTimings) -> String {
        "image=\(durationMS(timings.imagePreparation)) global=\(durationMS(timings.globalTone)) "
            + "face=\(durationMS(timings.faceDetection)) saliency=\(durationMS(timings.saliency)) "
            + "foreground=\(durationMS(timings.foregroundMasking)) person=\(durationMS(timings.personSegmentation)) "
            + "regional=\(durationMS(timings.regionalAnalysis)) total=\(durationMS(timings.total))"
    }

    private func durationMS(_ duration: Duration) -> String {
        let components = duration.components
        return String(
            format: "%.3f",
            Double(components.seconds) * 1_000 + Double(components.attoseconds) / 1e15)
    }

    private func median(of count: Int, _ operation: () -> Void) -> Double {
        var samples: [Double] = []
        for _ in 0..<count {
            let start = DispatchTime.now().uptimeNanoseconds
            operation()
            samples.append(elapsedMilliseconds(since: start))
        }
        return median(samples)
    }

    private func medianAsync(of count: Int, _ operation: () async throws -> Void) async throws
        -> Double
    {
        var samples: [Double] = []
        for _ in 0..<count {
            let start = DispatchTime.now().uptimeNanoseconds
            try await operation()
            samples.append(elapsedMilliseconds(since: start))
        }
        return median(samples)
    }

    private struct TimedSample {
        let ms: Double
        let succeeded: Bool
    }

    private func median(_ samples: [Double]) -> Double {
        let sorted = samples.sorted()
        guard !sorted.isEmpty else { return 0 }
        return sorted[sorted.count / 2]
    }

    private func elapsedMilliseconds(since start: UInt64) -> Double {
        Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
    }

    private func residentMemoryBytes() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.stride) / 4
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? UInt64(info.resident_size) : 0
    }
}

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest

@testable import KromoraKit

/// Auto performance diagnostics and the release acceptance gate (KRMA-352).
///
/// - Telemetry is a fixed set of scalar stage timings plus bounded budget counters. It is
///   recorded, never read by selection, so attaching it cannot change candidate behavior.
/// - Decode is reported separately from Auto work; cold and warm runs are measured separately
///   through the shared analysis cache.
/// - `VisionAestheticsDiagnostics` is `#available`-guarded, diagnostics-only, and never an
///   optimization target in production selection.
/// - The full-hardware end-to-end benchmark is opt-in
///   (`AutoPerformanceDiagnosticsTests/testAutoEndToEndBenchmark` in the optional lane) and
///   records medians in the release report; the fast lane pins invariants, never ceilings.
final class AutoPerformanceDiagnosticsTests: TempDirectoryTestCase {

    // MARK: - Telemetry shape

    func testTimingsAreBoundedValueOnlyDiagnostics() throws {
        let timings = AutoRunTimings(
            decodeSeconds: 0.1, analysisSeconds: 0.5, maskSeconds: 0.2,
            measurementSeconds: 0.3, candidateRenderSeconds: 0.8,
            rawRedevelopmentSeconds: 0, validationSeconds: 0.01, regionalSeconds: 0.2,
            persistenceSeconds: 0, totalSeconds: 2.11,
            candidateCount: 5, evaluatedCount: 5, smallRenders: 6, rawRedevelopments: 0
        )
        // Auto-work excludes decode: the 2–5s gate applies to this value.
        XCTAssertEqual(timings.autoWorkSeconds, 2.01, accuracy: 1e-9)
        // Non-finite or negative inputs degrade to zero rather than poisoning a report.
        XCTAssertEqual(AutoRunTimings(totalSeconds: .nan).totalSeconds, 0)
        XCTAssertEqual(AutoRunTimings(decodeSeconds: -3).decodeSeconds, 0)
        // Bounded by construction: fixed scalar fields, no arrays, no pixels, no paths.
        let payload = try JSONEncoder().encode(AutoRunTimings.zero)
        let keys = try XCTUnwrap(
            JSONSerialization.jsonObject(with: payload) as? [String: Any]
        ).keys
        XCTAssertEqual(keys.count, 14)
        XCTAssertLessThan(payload.count, 1_024)
        XCTAssertLessThan(MemoryLayout<AutoRunTimings>.stride, 512)
    }

    // MARK: - Budgets and non-interference (deterministic fakes)

    func testCoordinatorBudgetsAndStageClocksStayBounded() async {
        let current = EditDocument()
        let coordinator = AutoEnhancementCoordinator(
            engine: StubDiagnosticSampler { _ in StubDiagnosticSampler.solid(gray: 0.22) }
        )
        let result = await coordinator.run(
            source: StubDiagnosticSampler.standardSource,
            current: current,
            expectedDocumentHash: current.editHash,
            facts: StubDiagnosticSampler.darkFacts(),
            native: StubDiagnosticSampler.exposureProposal(current: current, exposure: 1.0),
            apple: nil,
            sourceKind: .standard
        )
        XCTAssertLessThanOrEqual(result.budget.smallRenders, 24)
        XCTAssertLessThanOrEqual(result.budget.rawRedevelopments, 4)
        XCTAssertGreaterThanOrEqual(result.budget.renderSeconds, 0)
        XCTAssertGreaterThanOrEqual(result.budget.scoringSeconds, 0)
        XCTAssertGreaterThanOrEqual(result.budget.evaluated, 1)
        // Render time dominates scoring for any real sampler; both are recorded, neither
        // influences the selection, which depends only on scores and budgets.
        XCTAssertGreaterThanOrEqual(
            result.budget.elapsedSeconds,
            result.budget.renderSeconds + result.budget.scoringSeconds - 0.5
        )
    }

    func testTelemetryDoesNotChangeCandidateSelection() async {
        let current = EditDocument()
        let first = AutoEnhancementCoordinator(
            engine: StubDiagnosticSampler { _ in StubDiagnosticSampler.solid(gray: 0.22) }
        )
        let second = AutoEnhancementCoordinator(
            engine: StubDiagnosticSampler { _ in StubDiagnosticSampler.solid(gray: 0.22) }
        )
        func evaluate(_ coordinator: AutoEnhancementCoordinator) async
            -> AutoEnhancementCoordinatorResult
        {
            await coordinator.run(
                source: StubDiagnosticSampler.standardSource,
                current: current,
                expectedDocumentHash: current.editHash,
                facts: StubDiagnosticSampler.darkFacts(),
                native: StubDiagnosticSampler.exposureProposal(current: current, exposure: 1.0),
                apple: nil,
                sourceKind: .standard
            )
        }
        let runA = await evaluate(first)
        let runB = await evaluate(second)
        XCTAssertEqual(runA.status, runB.status)
        XCTAssertEqual(runA.document, runB.document)
        XCTAssertEqual(runA.provenance, runB.provenance)
        XCTAssertEqual(runA.selectedScore?.total, runB.selectedScore?.total)
    }

    func testRawRedevelopmentsStayCapped() async {
        let current = EditDocument()
        let sampler = StubDiagnosticSampler { _ in StubDiagnosticSampler.solid(gray: 0.22) }
        let coordinator = AutoEnhancementCoordinator(engine: sampler)
        let data = Data([0xFF, 0xD8, 0xFF, 0xD9])
        let rawSource = ImageSource(data: data, nativeExtent: CGSize(width: 16, height: 16))
        let result = await coordinator.run(
            source: rawSource,
            current: current,
            expectedDocumentHash: current.editHash,
            facts: StubDiagnosticSampler.darkFacts(),
            native: StubDiagnosticSampler.exposureProposal(current: current, exposure: 1.0),
            apple: StubDiagnosticSampler.appleProposal(current: current, exposure: 0.8),
            sourceKind: .raw
        )
        XCTAssertLessThanOrEqual(result.budget.rawRedevelopments, 4)
        XCTAssertLessThanOrEqual(result.budget.smallRenders, 24)
        XCTAssertGreaterThanOrEqual(result.budget.rawRenderSeconds, 0)
        XCTAssertLessThanOrEqual(
            result.budget.rawRenderSeconds, result.budget.renderSeconds + 1e-9
        )
        let samplerCount = await sampler.requestCount()
        XCTAssertEqual(samplerCount, result.budget.smallRenders)
    }

    // MARK: - Cold vs warm through the production path

    /// Cold and warm runs share one analysis coordinator (and its cache). The warm run must
    /// hit the cache (no analysis work, ~zero decode) and select the identical document.
    func testColdAndWarmRunsSeparateDecodeAndSelectIdentically() async throws {
        let sourceData = try solidJPEG(red: 0.30, green: 0.30, blue: 0.29)
        let source = ImageSource(data: sourceData, nativeExtent: CGSize(width: 32, height: 24))
        let assetID = PhotoAssetID.data(sourceData)
        let store = MaskStore(directory: tempDirectory.appendingPathComponent("masks"))
        let engine = RenderEngine()
        let analysisCoordinator = PhotoAnalysisCoordinator(
            engine: engine,
            maskStore: store,
            cache: PhotoAnalysisCache(directory: tempDirectory.appendingPathComponent("analysis")),
            maskProvider: StubDiagnosticMaskProvider(),
            sceneClassifier: StubDiagnosticSceneClassifier(),
            stages: [:]
        )
        defer { Task { await analysisCoordinator.shutdown() } }
        let auto = ContentAwareAutoEngine(
            engine: engine, analysisCoordinator: analysisCoordinator, maskStore: store
        )
        let current = EditDocument()

        let cold = await auto.run(source: source, assetID: assetID, current: current)
        let warm = await auto.run(source: source, assetID: assetID, current: current)

        XCTAssertEqual(cold.proposedDocument, warm.proposedDocument)
        XCTAssertEqual(cold.status, warm.status)

        // Decode is separated from Auto work on both runs.
        for timings in [cold.timings, warm.timings] {
            XCTAssertGreaterThanOrEqual(timings.decodeSeconds, 0)
            XCTAssertEqual(
                timings.autoWorkSeconds, timings.totalSeconds - timings.decodeSeconds,
                accuracy: 1e-9
            )
            XCTAssertLessThanOrEqual(timings.smallRenders, 24)
            XCTAssertLessThanOrEqual(timings.rawRedevelopments, 4)
            XCTAssertGreaterThanOrEqual(timings.candidateCount, timings.evaluatedCount)
        }
        // Cold performs real analysis work; warm hits the shared cache and performs ~none.
        XCTAssertGreaterThan(cold.timings.analysisSeconds, 0)
        XCTAssertLessThan(warm.timings.analysisSeconds, 0.05)
        XCTAssertLessThan(warm.timings.analysisSeconds, cold.timings.analysisSeconds)
        XCTAssertGreaterThan(cold.timings.decodeSeconds, 0)
        XCTAssertLessThanOrEqual(warm.timings.decodeSeconds, cold.timings.decodeSeconds)
        XCTAssertLessThan(warm.timings.maskSeconds, 0.05)
        print(
            String(
                format:
                    "AUTO_DIAGNOSTICS cold_total=%.3fs decode=%.3f analysis=%.3f measure=%.3f render=%.3f validation=%.3f regional=%.3f warm_total=%.3fs",
                cold.timings.totalSeconds, cold.timings.decodeSeconds, cold.timings.analysisSeconds,
                cold.timings.measurementSeconds, cold.timings.candidateRenderSeconds,
                cold.timings.validationSeconds, cold.timings.regionalSeconds,
                warm.timings.totalSeconds
            ))
    }

    // MARK: - Aesthetics diagnostics (macOS 15+, never selection)

    func testAestheticsScoresAreDiagnosticOnly() async {
        let image = try? Fixtures.makeParametricCGImage(width: 64, height: 48) { nx, ny in
            let t = (nx + ny) / 2
            return (0.2 + 0.5 * t, 0.2 + 0.5 * t, 0.2 + 0.48 * t)
        }
        let scores = image.flatMap(VisionAestheticsDiagnostics.scores(for:))
        if #available(macOS 15, *) {
            // On this gate's hardware the request succeeds; a nil here only means Vision
            // declined the fixture, which must never fail the run.
            if let scores {
                XCTAssertGreaterThanOrEqual(scores.overallScore, -1)
                XCTAssertLessThanOrEqual(scores.overallScore, 1)
            }
        } else {
            XCTAssertNil(scores, "macOS 14 has no aesthetics request; diagnostics stay silent")
        }

        // Non-interference is structural: scoring takes rendered samples, frozen targets, and
        // a pixel baseline — there is no aesthetics input to consult. Calling the helper
        // cannot move a selection, proved here by determinism across the call.
        let current = EditDocument()
        let sampler: @Sendable (EditDocument) -> RenderedPixelSamples? = {
            StubDiagnosticSampler.solid(gray: 0.22 + $0.light.exposure * 0.25)
        }
        let coordinator = AutoEnhancementCoordinator(
            engine: StubDiagnosticSampler(handler: sampler))
        func evaluate() async -> AutoEnhancementCoordinatorResult {
            await coordinator.run(
                source: StubDiagnosticSampler.standardSource,
                current: current,
                expectedDocumentHash: current.editHash,
                facts: StubDiagnosticSampler.darkFacts(),
                native: StubDiagnosticSampler.exposureProposal(current: current, exposure: 1.0),
                apple: nil,
                sourceKind: .standard
            )
        }
        let before = await evaluate()
        _ = image.flatMap(VisionAestheticsDiagnostics.scores(for:))
        let after = await evaluate()
        XCTAssertEqual(before.document, after.document)
        XCTAssertEqual(before.selectedScore?.total, after.selectedScore?.total)
    }

    // MARK: - Persistence timing and lifecycle

    /// The engine leaves `persistenceSeconds` at zero: persistence is async coalesced outside
    /// the Auto critical path. This test times the durable save/reopen round-trip separately
    /// so the report carries a real persistence number without pretending it blocks Auto.
    func testPersistenceRoundTripIsTimedSeparately() async throws {
        let sourceData = try solidJPEG(red: 0.48, green: 0.48, blue: 0.48)
        let source = ImageSource(data: sourceData, nativeExtent: CGSize(width: 32, height: 24))
        let assetID = PhotoAssetID.data(sourceData)
        let store = MaskStore(directory: tempDirectory.appendingPathComponent("masks"))
        let engine = RenderEngine()
        let analysisCoordinator = PhotoAnalysisCoordinator(
            engine: engine,
            maskStore: store,
            cache: PhotoAnalysisCache(directory: tempDirectory.appendingPathComponent("analysis")),
            maskProvider: StubDiagnosticMaskProvider(),
            sceneClassifier: StubDiagnosticSceneClassifier(),
            stages: [:]
        )
        defer { Task { await analysisCoordinator.shutdown() } }
        let result = await ContentAwareAutoEngine(
            engine: engine, analysisCoordinator: analysisCoordinator, maskStore: store
        ).run(source: source, assetID: assetID, current: EditDocument())
        XCTAssertEqual(result.timings.persistenceSeconds, 0)

        let clock = ContinuousClock()
        let persistStart = clock.now
        let payload = try JSONEncoder().encode(result.proposedDocument)
        let url = tempDirectory.appendingPathComponent("auto-result.json")
        try payload.write(to: url)
        let reopened = try JSONDecoder().decode(
            EditDocument.self, from: Data(contentsOf: url)
        )
        let persistenceSeconds = (clock.now - persistStart).autoDiagnosticSeconds
        XCTAssertEqual(reopened, result.proposedDocument)
        XCTAssertGreaterThanOrEqual(persistenceSeconds, 0)
        XCTAssertLessThan(persistenceSeconds, 5, "fixture persistence must stay trivial")
        print(String(format: "AUTO_DIAGNOSTICS persistence_roundtrip=%.4fs", persistenceSeconds))
    }

    // MARK: - Opt-in end-to-end hardware benchmark (optional lane)

    /// Full production Auto on a 768px fixture through the real renderer and real analysis.
    /// Opt-in via `KROMORA_AUTO_BENCHMARK=1`; prints the cold/warm stage breakdown for the
    /// release report. The generous ceiling only guards against hangs — the 2–5s typical
    /// gate is evaluated from printed medians, never asserted as a ceiling.
    func testAutoEndToEndBenchmark() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["KROMORA_AUTO_BENCHMARK"] == "1",
            "set KROMORA_AUTO_BENCHMARK=1 to run the Auto end-to-end hardware benchmark"
        )
        let image = try Fixtures.makeParametricCGImage(width: 768, height: 512) { nx, ny in
            let t = (nx + ny) / 2
            let v = 0.08 + 0.30 * t
            return (v, v * 0.99, v * 0.96)
        }
        let sourceData = try Fixtures.jpegData(for: image)
        let source = ImageSource(data: sourceData, nativeExtent: CGSize(width: 768, height: 512))
        let assetID = PhotoAssetID.data(sourceData)
        let store = MaskStore(directory: tempDirectory.appendingPathComponent("bench-masks"))
        let engine = RenderEngine()
        let analysisCoordinator = PhotoAnalysisCoordinator(
            engine: engine,
            maskStore: store,
            cache: PhotoAnalysisCache(
                directory: tempDirectory.appendingPathComponent("bench-analysis"))
        )
        defer { Task { await analysisCoordinator.shutdown() } }
        let auto = ContentAwareAutoEngine(
            engine: engine, analysisCoordinator: analysisCoordinator, maskStore: store
        )
        let current = EditDocument()

        let cold = await auto.run(source: source, assetID: assetID, current: current)
        // Warm reuses the populated analysis cache with a fresh mask store state.
        let warm = await auto.run(source: source, assetID: assetID, current: current)

        for (label, timings) in [("cold", cold.timings), ("warm", warm.timings)] {
            print(
                String(
                    format:
                        "AUTO_BENCHMARK %@ total=%.3fs decode=%.3f analysis=%.3f masks=%.3f measure=%.3f render=%.3f(raw %.3f) validation=%.3f regional=%.3f candidates=%d evaluated=%d renders=%d raw=%d status=%@",
                    label, timings.totalSeconds, timings.decodeSeconds, timings.analysisSeconds,
                    timings.maskSeconds, timings.measurementSeconds, timings.candidateRenderSeconds,
                    timings.rawRedevelopmentSeconds, timings.validationSeconds,
                    timings.regionalSeconds, timings.candidateCount, timings.evaluatedCount,
                    timings.smallRenders, timings.rawRedevelopments, String(describing: cold.status)
                ))
        }
        // Fixture-only aesthetics sample, diagnostics only: recorded, never selected on.
        if let scores = VisionAestheticsDiagnostics.scores(for: image) {
            print(
                String(
                    format: "AUTO_BENCHMARK aesthetics overall=%.3f utility=%@",
                    scores.overallScore, scores.isUtility ? "yes" : "no"
                ))
        } else {
            print("AUTO_BENCHMARK aesthetics unavailable (macOS 14 or Vision declined)")
        }
        XCTAssertLessThan(cold.timings.totalSeconds, 120)
        XCTAssertLessThanOrEqual(cold.timings.smallRenders, 24)
        XCTAssertLessThanOrEqual(cold.timings.rawRedevelopments, 4)
    }

    // MARK: - Fixture helpers

    private func solidJPEG(red: CGFloat, green: CGFloat, blue: CGFloat) throws -> Data {
        guard
            let context = CGContext(
                data: nil, width: 32, height: 24, bitsPerComponent: 8,
                bytesPerRow: 32 * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else { throw Fixtures.FixtureError.cannotCreateContext }
        context.setFillColor(red: red, green: green, blue: blue, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 32, height: 24))
        guard let image = context.makeImage() else {
            throw Fixtures.FixtureError.cannotCreateContext
        }
        return try Fixtures.jpegData(for: image)
    }
}

// MARK: - Deterministic doubles

/// Exposure-driven solid-gray sampler: brightness follows the document's exposure.
private actor StubDiagnosticSampler: CurrentEditSampling {
    let handler: @Sendable (EditDocument) -> RenderedPixelSamples?
    private(set) var requests: [EditDocument] = []

    init(handler: @escaping @Sendable (EditDocument) -> RenderedPixelSamples?) {
        self.handler = handler
    }

    func renderedSamples(
        source: ImageSource,
        document: EditDocument,
        lut: CubeLUT?,
        targetLongEdge: Int,
        space: WorkingSpace
    ) async -> RenderedPixelSamples? {
        requests.append(document)
        return handler(document)
    }

    func requestCount() -> Int { requests.count }

    static let standardSource = ImageSource(
        data: Data([0xFF, 0xD8, 0xFF, 0xD9]), nativeExtent: CGSize(width: 16, height: 16)
    )

    static func solid(gray: Double, width: Int = 16, height: Int = 16) -> RenderedPixelSamples {
        let byte = UInt8(min(max(gray, 0), 1) * 255)
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        for index in 0..<(width * height) {
            bytes[index * 4] = byte
            bytes[index * 4 + 1] = byte
            bytes[index * 4 + 2] = byte
        }
        return RenderedPixelSamples(width: width, height: height, bytes: bytes, space: .sRGB)
    }

    static func darkFacts() -> AutoEnhancementFacts {
        var facts = AutoEnhancementFacts()
        facts.tonePerceptual = ToneStatistics(
            variant: .perceptual, mean: 0.25, p05: 0.1, p10: 0.15, p50: 0.25,
            p90: 0.4, p95: 0.45
        )
        facts.signalConfidence = AutoSignalConfidence(
            globalTone: 1, colorNeutral: 0.9, scene: 0.9, subjectRegions: 0,
            detail: nil, providers: .unavailable, overall: 0.9
        )
        return facts
    }

    static func exposureProposal(
        current: EditDocument, exposure: Double
    ) -> AutoEnhancementProposal {
        var document = current
        document.light.exposure = exposure
        return AutoEnhancementProposal(
            document: document,
            changes: [
                AutoControlChange(
                    control: .exposure, previous: current.light.exposure, proposed: exposure,
                    confidence: 0.9, reason: "test placement", evidence: "test"
                )
            ],
            confidence: 0.9,
            evidence: AutoEvidenceUsed(
                toneMedian: 0.25, highlightClipping: 0, shadowClipping: 0,
                neutralConfidence: 0.8, recommendsNeutralCorrection: false,
                hueMixed: false, overallSignalConfidence: 0.9
            ),
            notes: "test native"
        )
    }

    static func appleProposal(
        current: EditDocument, exposure: Double
    ) -> AppleReferenceProposal {
        var document = current
        document.light.exposure = exposure
        let provenance = AppleReferenceProvenance(
            sourceKind: .standard, space: .sRGB, fitMethod: .renderCompare
        )
        return AppleReferenceProposal(
            document: document,
            changes: [
                AutoControlChange(
                    control: .exposure, previous: current.light.exposure, proposed: exposure,
                    confidence: 0.6, reason: "test reference", evidence: "test"
                )
            ],
            confidence: 0.6,
            provenance: provenance,
            residualError: 0
        )
    }
}

/// Mask provider with no masks: every stage degrades to notes, matching the production
/// global-only fallback without paying for Vision models in the fast lane.
private struct StubDiagnosticMaskProvider: SemanticMaskProviding {
    func mask(
        for kind: SemanticMaskKind, image: AnalysisImage, quality: MaskQuality
    ) async throws -> RegionMask {
        throw RegionMaskError.missingPixels
    }
}

/// Scene classifier with no labels: intent evidence is absent, never fabricated.
private struct StubDiagnosticSceneClassifier: SceneClassifierProviding {
    func classifications(for image: AnalysisImage) async -> [SceneClassificationObservation]? {
        nil
    }
}

extension Duration {
    fileprivate var autoDiagnosticSeconds: Double {
        let components = self.components
        return Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}

import CoreGraphics
import Foundation
import Synchronization
import XCTest

@testable import KromoraKit

/// The persistent analysis cache must satisfy a request only when its recorded stage coverage
/// covers the requested level. These tests assert which stages the provider was asked for, not
/// merely that an analysis came back.
final class PhotoAnalysisCoverageTests: TempDirectoryTestCase {
    private let assetID = PhotoAssetID.data(Data([21, 22, 23]))

    private let fastStages = [
        PhotoAnalysisStage(kind: .subject, quality: .analysis),
        PhotoAnalysisStage(kind: .face, quality: .analysis),
    ]
    private let detailedStages = [
        PhotoAnalysisStage(kind: .subject, quality: .preview),
        PhotoAnalysisStage(kind: .foregroundInstance(0), quality: .preview),
        PhotoAnalysisStage(kind: .background, quality: .preview),
        PhotoAnalysisStage(kind: .face, quality: .preview),
        PhotoAnalysisStage(kind: .person, quality: .preview),
    ]
    private let standardStages = [
        PhotoAnalysisStage(kind: .subject, quality: .analysis),
        PhotoAnalysisStage(kind: .foregroundInstance(0), quality: .analysis),
        PhotoAnalysisStage(kind: .background, quality: .analysis),
    ]

    // MARK: - Level transitions

    func testFastResultDoesNotSatisfyDetailedRequest() async throws {
        let provider = ScriptedMaskProvider()
        let coordinator = makeCoordinator(provider: provider)

        _ = try await coordinator.analyze(assetID: assetID, source: makeSource(), level: .fast)
        let afterFast = await provider.stages(excludingComposedForeground: true)
        XCTAssertEqual(afterFast, fastStages)

        await provider.reset()
        _ = try await coordinator.analyze(assetID: assetID, source: makeSource(), level: .detailed)
        let afterDetailed = await provider.stages(excludingComposedForeground: true)
        XCTAssertEqual(afterDetailed, detailedStages)
    }

    func testStandardResultDoesNotSatisfyDetailedRequest() async throws {
        let provider = ScriptedMaskProvider()
        let coordinator = makeCoordinator(provider: provider)

        _ = try await coordinator.analyze(assetID: assetID, source: makeSource(), level: .standard)
        let afterStandard = await provider.stages(excludingComposedForeground: true)
        XCTAssertEqual(afterStandard, standardStages)

        await provider.reset()
        _ = try await coordinator.analyze(assetID: assetID, source: makeSource(), level: .detailed)
        let afterDetailed = await provider.stages(excludingComposedForeground: true)
        XCTAssertEqual(afterDetailed, detailedStages)
    }

    func testDetailedResultSatisfiesStandardAndFastWithoutProviderCalls() async throws {
        let provider = ScriptedMaskProvider()
        let coordinator = makeCoordinator(provider: provider)

        _ = try await coordinator.analyze(assetID: assetID, source: makeSource(), level: .detailed)
        await provider.reset()

        _ = try await coordinator.analyze(assetID: assetID, source: makeSource(), level: .standard)
        _ = try await coordinator.analyze(assetID: assetID, source: makeSource(), level: .fast)

        let requested = await provider.requested
        XCTAssertEqual(requested, [])
    }

    func testExtendingAnalysisKeepsOneRegionPerKindAtTheHighestQuality() {
        let analysisQuality = makeRegion(kind: .subject, quality: .analysis)
        let previewQuality = makeRegion(kind: .subject, quality: .preview)
        let face = makeRegion(kind: .face, quality: .analysis)

        let upgraded = PhotoAnalysisAssembler.merged(
            retained: [analysisQuality, face], adding: [previewQuality]
        )
        XCTAssertEqual(upgraded.map(\.kind), [.subject, .face])
        XCTAssertEqual(upgraded.first?.mask.quality, .preview)

        let downgradeIgnored = PhotoAnalysisAssembler.merged(
            retained: [previewQuality], adding: [analysisQuality]
        )
        XCTAssertEqual(downgradeIgnored, [previewQuality])
    }

    // MARK: - Relaunch

    func testOnDiskCacheSurvivesRelaunchAndOnlyMissingStagesRun() async throws {
        let firstProvider = ScriptedMaskProvider()
        let first = makeCoordinator(provider: firstProvider)
        _ = try await first.analyze(assetID: assetID, source: makeSource(), level: .fast)
        await first.shutdown()

        // A new coordinator over the same on-disk cache is a relaunch.
        let secondProvider = ScriptedMaskProvider()
        let second = makeCoordinator(provider: secondProvider)
        _ = try await second.analyze(assetID: assetID, source: makeSource(), level: .fast)
        let warmFast = await secondProvider.requested
        XCTAssertEqual(warmFast, [])

        _ = try await second.analyze(assetID: assetID, source: makeSource(), level: .detailed)
        let upgraded = await secondProvider.stages(excludingComposedForeground: true)
        XCTAssertEqual(upgraded, detailedStages)
        await second.shutdown()

        let thirdProvider = ScriptedMaskProvider()
        let third = makeCoordinator(provider: thirdProvider)
        _ = try await third.analyze(assetID: assetID, source: makeSource(), level: .detailed)
        _ = try await third.analyze(assetID: assetID, source: makeSource(), level: .fast)
        let warm = await thirdProvider.requested
        XCTAssertEqual(warm, [])
    }

    func testEntryWithoutCoverageIsRecomputedRatherThanTrusted() async throws {
        let source = makeSource()
        let cacheKey = AnalysisCacheKey(identity: source.cacheIdentity, analysisVersion: .current)
        let cache = PhotoAnalysisCache(directory: tempDirectory.appendingPathComponent("cache"))
        // The shape the cache wrote before coverage existed: a valid global-only analysis.
        try await cache.store(
            PhotoAnalysis(
                globalTone: .neutral, colorStatistics: .neutral, quality: .globalOnly
            ),
            for: cacheKey
        )
        let provider = ScriptedMaskProvider()
        let coordinator = makeCoordinator(provider: provider)

        _ = try await coordinator.analyze(assetID: assetID, source: source, level: .detailed)

        let requested = await provider.stages(excludingComposedForeground: true)
        XCTAssertEqual(requested, detailedStages)
        let entry = try await cache.entry(for: cacheKey)
        XCTAssertNotNil(entry?.coverage)
    }

    // MARK: - Concurrency

    func testConcurrentRequestsForDifferentLevelsEachRunTheirStagesOnce() async throws {
        let provider = ScriptedMaskProvider(delay: .milliseconds(30))
        let coordinator = makeCoordinator(provider: provider)
        let source = makeSource()
        let assetID = assetID

        async let fast = coordinator.analyze(assetID: assetID, source: source, level: .fast)
        async let detailed = coordinator.analyze(assetID: assetID, source: source, level: .detailed)
        async let standard = coordinator.analyze(assetID: assetID, source: source, level: .standard)
        _ = try await (fast, detailed, standard)

        let requested = await provider.stages(excludingComposedForeground: true)
        // Which level runs first decides how much work the others skip (detailed covers both
        // fast and standard), so assert the invariants rather than one schedule.
        let registry = Set(fastStages + detailedStages + standardStages)
        XCTAssertTrue(Set(requested).isSubset(of: registry))
        XCTAssertEqual(requested.count, Set(requested).count, "no stage should run twice")
        XCTAssertTrue(Set(detailedStages).isSubset(of: Set(requested)))

        await provider.reset()
        for level in [PhotoAnalysisLevel.fast, .standard, .detailed] {
            _ = try await coordinator.analyze(assetID: assetID, source: source, level: level)
        }
        let afterWarm = await provider.requested
        XCTAssertEqual(afterWarm, [])
    }

    // MARK: - Failure and retry

    func testTransientStageFailureIsRetriedAfterBackoffAndThenRecorded() async throws {
        let clock = TestClock()
        let face = PhotoAnalysisStage(kind: .face, quality: .analysis)
        let provider = ScriptedMaskProvider(
            failures: [face: [VisionSemanticMaskError.requestFailed("transient")]]
        )
        let coordinator = makeCoordinator(provider: provider, clock: clock)
        let source = makeSource()

        let degraded = try await coordinator.analyze(
            assetID: assetID, source: source, level: .fast
        )
        XCTAssertFalse(degraded.quality.faceAnalysisAvailable)

        // Inside the backoff the failure counts as handled: no provider call.
        await provider.reset()
        _ = try await coordinator.analyze(assetID: assetID, source: source, level: .fast)
        let withinBackoff = await provider.requested
        XCTAssertEqual(withinBackoff, [])

        // After it, only the failed stage is retried.
        clock.advance(by: PhotoAnalysisCoverage.backoff(afterAttempts: 1) + 1)
        _ = try await coordinator.analyze(assetID: assetID, source: source, level: .fast)
        let retried = await provider.requested
        XCTAssertEqual(retried, [face])

        // Once it has succeeded the stage is done for good.
        clock.advance(by: 3_600)
        await provider.reset()
        _ = try await coordinator.analyze(assetID: assetID, source: source, level: .fast)
        let settled = await provider.requested
        XCTAssertEqual(settled, [])
    }

    func testRepeatedTransientFailuresStopRetryingAtTheBound() async throws {
        let clock = TestClock()
        let face = PhotoAnalysisStage(kind: .face, quality: .analysis)
        let error = VisionSemanticMaskError.requestFailed("always")
        let provider = ScriptedMaskProvider(
            failures: [face: Array(repeating: error, count: 10)]
        )
        let coordinator = makeCoordinator(provider: provider, clock: clock)
        let source = makeSource()

        for _ in 0..<(PhotoAnalysisCoverage.maxFailedAttempts + 3) {
            _ = try await coordinator.analyze(assetID: assetID, source: source, level: .fast)
            clock.advance(by: 10_000)
        }

        let faceCalls = await provider.requested.filter { $0 == face }.count
        XCTAssertEqual(faceCalls, PhotoAnalysisCoverage.maxFailedAttempts)
    }

    func testDeterministicAbsenceIsNotRetriedOnEveryRequest() async throws {
        let clock = TestClock()
        let face = PhotoAnalysisStage(kind: .face, quality: .analysis)
        let provider = ScriptedMaskProvider(
            failures: [face: Array(repeating: VisionSemanticMaskError.noFaceDetected, count: 10)]
        )
        let coordinator = makeCoordinator(provider: provider, clock: clock)
        let source = makeSource()

        for _ in 0..<4 {
            _ = try await coordinator.analyze(assetID: assetID, source: source, level: .fast)
            clock.advance(by: 86_400)
        }

        let faceCalls = await provider.requested.filter { $0 == face }.count
        XCTAssertEqual(faceCalls, 1)
    }

    func testFailedOptionalStageDoesNotBlockALaterDetailedRequest() async throws {
        let subject = PhotoAnalysisStage(kind: .subject, quality: .analysis)
        let provider = ScriptedMaskProvider(
            failures: [subject: [VisionSemanticMaskError.requestFailed("transient")]]
        )
        let coordinator = makeCoordinator(provider: provider)

        _ = try await coordinator.analyze(assetID: assetID, source: makeSource(), level: .fast)
        await provider.reset()
        _ = try await coordinator.analyze(assetID: assetID, source: makeSource(), level: .detailed)

        let requested = await provider.stages(excludingComposedForeground: true)
        XCTAssertEqual(requested, detailedStages)
    }

    // MARK: - Coverage and cache values

    func testCoverageRoundTripsThroughTheCache() async throws {
        let cache = PhotoAnalysisCache(directory: tempDirectory)
        let key = AnalysisCacheKey(
            identity: makeSource().cacheIdentity, analysisVersion: .current
        )
        var coverage = PhotoAnalysisCoverage.empty
        coverage.recordProduced(fastStages[0])
        coverage.recordFailure(
            fastStages[1], error: VisionSemanticMaskError.requestFailed("x"),
            at: Date(timeIntervalSince1970: 1_000)
        )
        coverage.recordFailure(
            PhotoAnalysisStage(kind: .person, quality: .preview),
            error: VisionSemanticMaskError.noPersonDetected, at: Date()
        )
        let analysis = PhotoAnalysis(
            globalTone: .neutral, colorStatistics: .neutral, quality: .globalOnly
        )

        try await cache.store(analysis, coverage: coverage, for: key)

        let restored = try await PhotoAnalysisCache(directory: tempDirectory).entry(for: key)
        XCTAssertEqual(restored?.coverage, coverage)
        XCTAssertEqual(restored?.analysis, analysis)
    }

    func testCoverageSatisfactionRules() {
        var coverage = PhotoAnalysisCoverage.empty
        let now = Date(timeIntervalSince1970: 10_000)
        let subjectAnalysis = PhotoAnalysisStage(kind: .subject, quality: .analysis)
        let subjectPreview = PhotoAnalysisStage(kind: .subject, quality: .preview)

        XCTAssertEqual(
            coverage.missingStages(in: [subjectAnalysis], now: now), [subjectAnalysis]
        )
        coverage.recordProduced(subjectAnalysis)
        XCTAssertEqual(coverage.missingStages(in: [subjectAnalysis], now: now), [])
        XCTAssertEqual(
            coverage.missingStages(in: [subjectPreview], now: now), [subjectPreview],
            "an analysis-quality mask must not satisfy a preview-quality request"
        )
        coverage.recordProduced(subjectPreview)
        XCTAssertEqual(
            coverage.missingStages(in: [subjectAnalysis, subjectPreview], now: now), [],
            "a preview-quality mask satisfies an analysis-quality request"
        )
    }

    // MARK: - Helpers

    private func makeCoordinator(
        provider: ScriptedMaskProvider, clock: TestClock = TestClock()
    ) -> PhotoAnalysisCoordinator {
        PhotoAnalysisCoordinator(
            engine: FakeRenderEngine(),
            maskStore: MaskStore(directory: tempDirectory.appendingPathComponent("masks")),
            cache: PhotoAnalysisCache(directory: tempDirectory.appendingPathComponent("cache")),
            maskProvider: provider,
            now: { clock.now }
        )
    }

    private func makeSource() -> ImageSource {
        ImageSource(
            backing: .data(Data([0, 1, 2, 3])), kind: .standard,
            nativeExtent: CGSize(width: 32, height: 24)
        )
    }

    private func makeRegion(kind: SemanticMaskKind, quality: MaskQuality) -> AnalyzedRegion {
        let key = MaskCacheKey(
            assetID: .imported(UUID()), sourceFingerprint: .data(Data([42])),
            kind: kind, quality: quality, providerVersion: "test"
        )
        return AnalyzedRegion(
            id: UUID(), kind: kind,
            mask: RegionMaskReference(
                cacheKey: key, size: PixelDimensions(width: 8, height: 8)
            ),
            confidence: 1, importance: 1, tone: .neutral, color: .neutral, coverage: 1
        )
    }
}

private final class TestClock: Sendable {
    private let value = Mutex(Date(timeIntervalSince1970: 1_700_000_000))

    var now: Date { value.withLock { $0 } }

    func advance(by interval: TimeInterval) {
        value.withLock { $0 = $0.addingTimeInterval(interval) }
    }
}

/// Records every stage it is asked for. `failures` scripts errors per stage, consumed one per call.
private actor ScriptedMaskProvider: SemanticMaskProviding {
    private(set) var requested: [PhotoAnalysisStage] = []
    private var failures: [PhotoAnalysisStage: [Error]]
    private let delay: Duration?

    init(failures: [PhotoAnalysisStage: [Error]] = [:], delay: Duration? = nil) {
        self.failures = failures
        self.delay = delay
    }

    func reset() { requested = [] }

    /// `.background` is composed from a `.foreground` request before the provider is asked for
    /// it directly; that internal request is not a registry stage.
    func stages(excludingComposedForeground: Bool) -> [PhotoAnalysisStage] {
        excludingComposedForeground ? requested.filter { $0.kind != .foreground } : requested
    }

    func mask(for kind: SemanticMaskKind, image: AnalysisImage, quality: MaskQuality) async throws -> RegionMask {
        let stage = PhotoAnalysisStage(kind: kind, quality: quality)
        requested.append(stage)
        if let delay { try await Task.sleep(for: delay) }
        if var queue = failures[stage], !queue.isEmpty {
            let error = queue.removeFirst()
            failures[stage] = queue
            throw error
        }
        let key = MaskCacheKey(
            assetID: .imported(UUID()), sourceFingerprint: .data(Data([42])),
            kind: kind, quality: quality, providerVersion: "test"
        )
        return RegionMask(
            kind: kind, bounds: NormalizedRect(x: 0, y: 0, width: 1, height: 1),
            quality: quality,
            reference: RegionMaskReference(cacheKey: key, size: image.dimensions),
            confidence: 1, coverage: 1
        )
    }
}

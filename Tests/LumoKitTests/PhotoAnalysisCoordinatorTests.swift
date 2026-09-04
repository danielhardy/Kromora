import CoreGraphics
import Foundation
import XCTest

@testable import LumoKit

final class PhotoAnalysisCoordinatorTests: XCTestCase {
    func testConcurrentDirectMaskRequestsShareOneProviderTask() async throws {
        let provider = CountingMaskProvider(gated: true)
        let coordinator = PhotoAnalysisCoordinator(
            maskProvider: provider,
            stages: [:]
        )
        let source = makeSource()
        let assetID = PhotoAssetID.data(Data([1, 2, 3]))

        let masks = try await withThrowingTaskGroup(of: RegionMask.self, returning: [RegionMask].self) {
            group in
            for _ in 0..<8 {
                group.addTask {
                    try await coordinator.mask(
                        assetID: assetID, source: source, kind: .subject, quality: .preview
                    )
                }
            }
            var values: [RegionMask] = []
            for try await mask in group { values.append(mask) }
            return values
        }

        XCTAssertEqual(masks.count, 8)
        let callCount = await provider.callCount
        let requested = await provider.requested
        XCTAssertEqual(callCount, 1)
        XCTAssertEqual(requested, [PhotoAnalysisStage(kind: .subject, quality: .preview)])
    }

    func testConcurrentAnalysesShareOneInFlightAnalysisAndItsMaskStage() async throws {
        let provider = CountingMaskProvider(gated: true)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LumoAnalysisDedup-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let coordinator = PhotoAnalysisCoordinator(
            engine: FakeRenderEngine(),
            maskStore: MaskStore(directory: directory.appendingPathComponent("masks")),
            cache: PhotoAnalysisCache(directory: directory.appendingPathComponent("cache")),
            maskProvider: provider,
            stages: [.fast: [PhotoAnalysisStage(kind: .subject, quality: .analysis)]]
        )
        let source = makeSource()
        let assetID = PhotoAssetID.data(Data([4, 5, 6]))

        let analyses = try await withThrowingTaskGroup(
            of: PhotoAnalysis.self, returning: [PhotoAnalysis].self
        ) { group in
            for _ in 0..<8 {
                group.addTask {
                    try await coordinator.analyze(assetID: assetID, source: source, level: .fast)
                }
            }
            var values: [PhotoAnalysis] = []
            for try await analysis in group { values.append(analysis) }
            return values
        }

        XCTAssertEqual(analyses.count, 8)
        let callCount = await provider.callCount
        XCTAssertEqual(callCount, 1)
    }

    func testCancellingTheOnlyWaiterCancelsUnderlyingMaskWork() async throws {
        let provider = CountingMaskProvider(gated: true)
        let coordinator = PhotoAnalysisCoordinator(maskProvider: provider, stages: [:])
        let source = makeSource()
        let assetID = PhotoAssetID.data(Data([7, 8, 9]))

        let request = Task {
            try await coordinator.mask(
                assetID: assetID, source: source, kind: .subject, quality: .analysis
            )
        }
        await provider.waitUntilStarted()
        request.cancel()

        do {
            _ = try await request.value
            XCTFail("a cancelled mask request should not return a result")
        } catch is CancellationError {
            // Expected.
        }
        let wasCancelled = await provider.wasCancelled
        XCTAssertTrue(wasCancelled)
    }

    func testCancellingOneOfSeveralWaitersDoesNotCancelTheOthers() async throws {
        let provider = CountingMaskProvider(gated: true)
        let coordinator = PhotoAnalysisCoordinator(maskProvider: provider, stages: [:])
        let source = makeSource()
        let assetID = PhotoAssetID.data(Data([11, 12, 13]))

        let cancelled = Task {
            try await coordinator.mask(
                assetID: assetID, source: source, kind: .subject, quality: .preview
            )
        }
        let survivor = Task {
            try await coordinator.mask(
                assetID: assetID, source: source, kind: .subject, quality: .preview
            )
        }
        await provider.waitUntilStarted()
        cancelled.cancel()

        let result = try await survivor.value
        XCTAssertEqual(result.kind, .subject)
        let wasCancelled = await provider.wasCancelled
        XCTAssertFalse(wasCancelled)
    }

    func testDirectMaskRequestDoesNotRunGlobalAnalysis() async throws {
        let engine = FakeRenderEngine()
        let provider = CountingMaskProvider(gated: false)
        let coordinator = PhotoAnalysisCoordinator(
            engine: engine,
            maskProvider: provider,
            stages: [:]
        )

        _ = try await coordinator.mask(
            assetID: PhotoAssetID.data(Data([10])),
            source: makeSource(),
            kind: .subject,
            quality: .render
        )

        let histogramCount = await engine.histogramRequests.count
        let callCount = await provider.callCount
        XCTAssertEqual(histogramCount, 0)
        XCTAssertEqual(callCount, 1)
    }

    func testAnalysisCacheHitSkipsMaskProviderOnTheNextRequest() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LumoAnalysisCache-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let cache = PhotoAnalysisCache(directory: directory)
        let provider = CountingMaskProvider(gated: false)
        let coordinator = PhotoAnalysisCoordinator(
            engine: FakeRenderEngine(), cache: cache, maskProvider: provider,
            stages: [.fast: [PhotoAnalysisStage(kind: .subject, quality: .analysis)]]
        )
        let source = makeSource()
        let assetID = PhotoAssetID.data(Data([14, 15, 16]))

        _ = try await coordinator.analyze(assetID: assetID, source: source, level: .fast)
        _ = try await coordinator.analyze(assetID: assetID, source: source, level: .fast)

        let callCount = await provider.callCount
        XCTAssertEqual(callCount, 1)
    }

    func testAnalysisRecordsMeasuredStageTimings() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LumoAnalysisTimings-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let coordinator = PhotoAnalysisCoordinator(
            engine: FakeRenderEngine(),
            maskStore: MaskStore(directory: directory.appendingPathComponent("masks")),
            cache: PhotoAnalysisCache(directory: directory.appendingPathComponent("cache")),
            maskProvider: CountingMaskProvider(gated: false),
            stages: [.fast: [PhotoAnalysisStage(kind: .subject, quality: .analysis)]]
        )

        let analysis = try await coordinator.analyze(
            assetID: .data(Data([17, 18, 19])), source: makeSource(), level: .fast
        )

        XCTAssertGreaterThan(analysis.timings.imagePreparation, .zero)
        XCTAssertGreaterThan(analysis.timings.globalTone, .zero)
        XCTAssertGreaterThan(analysis.timings.saliency, .zero)
        XCTAssertGreaterThan(analysis.timings.total, analysis.timings.globalTone)
    }

    private func makeSource() -> ImageSource {
        ImageSource(
            backing: .data(Data([0, 1, 2, 3])), kind: .standard,
            nativeExtent: CGSize(width: 32, height: 24)
        )
    }
}

private actor CountingMaskProvider: SemanticMaskProviding {
    private(set) var callCount = 0
    private(set) var requested: [PhotoAnalysisStage] = []
    private(set) var wasCancelled = false
    private var started = false
    private let gated: Bool

    init(gated: Bool) {
        self.gated = gated
    }

    func mask(for kind: SemanticMaskKind, image: AnalysisImage, quality: MaskQuality) async throws -> RegionMask {
        callCount += 1
        requested.append(PhotoAnalysisStage(kind: kind, quality: quality))
        started = true
        guard gated else { return Self.makeMask(kind: kind, quality: quality, size: image.dimensions) }
        do {
            try await Task.sleep(for: .milliseconds(100))
        } catch is CancellationError {
            wasCancelled = true
            throw CancellationError()
        }
        return Self.makeMask(kind: kind, quality: quality, size: image.dimensions)
    }

    func waitUntilStarted() async {
        while !started {
            await Task.yield()
        }
    }

    private static func makeMask(
        kind: SemanticMaskKind, quality: MaskQuality, size: PixelDimensions
    ) -> RegionMask {
        let key = MaskCacheKey(
            assetID: .imported(UUID()),
            sourceFingerprint: .data(Data([42])),
            kind: kind,
            quality: quality,
            providerVersion: "test"
        )
        return RegionMask(
            kind: kind,
            bounds: NormalizedRect(x: 0, y: 0, width: 1, height: 1),
            quality: quality,
            reference: RegionMaskReference(cacheKey: key, size: size),
            confidence: 1,
            coverage: 1
        )
    }
}

import CoreGraphics
import Foundation
import XCTest

@testable import LumoKit

final class PhotoAnalysisAssemblyTests: TempDirectoryTestCase {
    func testAssemblyIncludesEveryAnalyzedMaskAndRoundTrips() async throws {
        let sourceData = Data("photo-analysis-all-kinds".utf8)
        let image = try makeImage(sourceData: sourceData)
        let store = MaskStore(directory: tempDirectory)
        let kinds: [SemanticMaskKind] = [
            .subject, .background, .person, .face, .faceInstance(1), .foregroundInstance(0)
        ]
        let masks = try await makeMasks(kinds, sourceData: sourceData, image: image, store: store)
        let engine = FakeRenderEngine(
            previewResult: try Fixtures.makeCGImage(width: 2, height: 2, red: 1, green: 1, blue: 1)
        )

        let analysis = try await PhotoAnalysis.assemble(
            image: image,
            masks: masks,
            globalToneAnalyzer: GlobalToneAnalyzer(engine: engine),
            maskedToneAnalyzer: MaskedToneAnalyzer(engine: engine, store: store)
        )

        XCTAssertEqual(analysis.regions.count, kinds.count)
        XCTAssertTrue(analysis.quality.globalToneAvailable)
        XCTAssertTrue(analysis.quality.attentionAvailable)
        XCTAssertTrue(analysis.quality.foregroundAvailable)
        XCTAssertTrue(analysis.quality.faceAnalysisAvailable)
        XCTAssertTrue(analysis.quality.peopleAnalysisAvailable)
        XCTAssertEqual(try roundTrip(analysis), analysis)
    }

    func testAssemblyDegradesToTierZeroAndOneAvailableMask() async throws {
        let sourceData = Data("photo-analysis-partial".utf8)
        let image = try makeImage(sourceData: sourceData)
        let store = MaskStore(directory: tempDirectory)
        let mask = try await makeMasks(
            [.subject], sourceData: sourceData, image: image, store: store
        ).first!
        let engine = FakeRenderEngine()

        let analysis = try await PhotoAnalysis.assemble(
            image: image,
            masks: [mask],
            globalToneAnalyzer: GlobalToneAnalyzer(engine: engine),
            toneAnalyzer: MaskedToneAnalyzer(engine: engine, store: store)
        )

        XCTAssertEqual(analysis.regions.map(\.kind), [.subject])
        XCTAssertTrue(analysis.quality.globalToneAvailable)
        XCTAssertTrue(analysis.quality.attentionAvailable)
        XCTAssertFalse(analysis.quality.foregroundAvailable)
        XCTAssertFalse(analysis.quality.faceAnalysisAvailable)
        XCTAssertFalse(analysis.quality.peopleAnalysisAvailable)
        XCTAssertEqual(try roundTrip(analysis), analysis)
    }

    func testAssemblyWithNoMasksStillProducesTierZeroAnalysis() async throws {
        let sourceData = Data("photo-analysis-global-only".utf8)
        let image = try makeImage(sourceData: sourceData)
        let engine = FakeRenderEngine()

        let analysis = try await PhotoAnalysis.assemble(
            image: image,
            masks: [],
            globalToneAnalyzer: GlobalToneAnalyzer(engine: engine),
            maskedToneAnalyzer: MaskedToneAnalyzer(engine: engine, store: MaskStore(directory: tempDirectory))
        )

        XCTAssertTrue(analysis.regions.isEmpty)
        XCTAssertEqual(analysis.quality, AnalysisQuality.globalOnly)
        XCTAssertEqual(try roundTrip(analysis), analysis)
    }

    private func makeImage(sourceData: Data) throws -> AnalysisImage {
        let source = ImageSource(data: sourceData, nativeExtent: CGSize(width: 2, height: 2))
        return try AnalysisImageFactory.make(
            from: source, configuration: AnalysisConfiguration(maximumDimension: 2)
        )
    }

    private func makeMasks(
        _ kinds: [SemanticMaskKind],
        sourceData: Data,
        image: AnalysisImage,
        store: MaskStore
    ) async throws -> [RegionMask] {
        let pixels = try NormalizedMask(size: image.dimensions, values: [1, 1, 1, 1])
        let fingerprint = PhotoSourceFingerprint.data(sourceData)
        return try await withThrowingTaskGroup(of: RegionMask.self, returning: [RegionMask].self) {
            group in
            for kind in kinds {
                group.addTask {
                    let key = MaskCacheKey(
                        assetID: PhotoAssetID.data(sourceData),
                        sourceFingerprint: fingerprint,
                        kind: kind,
                        quality: .analysis
                    )
                    let reference = try await store.store(pixels, for: key, quality: .analysis)
                    return RegionMask(
                        kind: kind,
                        bounds: NormalizedRect(x: 0, y: 0, width: 1, height: 1),
                        quality: .analysis,
                        reference: reference,
                        confidence: 1,
                        coverage: pixels.coverage
                    )
                }
            }
            var masks: [RegionMask] = []
            for try await mask in group { masks.append(mask) }
            return masks
        }
    }

    private func roundTrip<T: Codable & Equatable>(_ value: T) throws -> T {
        try JSONDecoder().decode(T.self, from: JSONEncoder().encode(value))
    }
}

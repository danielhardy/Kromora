import CoreGraphics
import Foundation
import XCTest

@testable import LumoKit

final class SmartMaskTests: XCTestCase {
    func testForegroundDefinitionIsDurableAndCarriesAllSmartSettings() throws {
        let component = MaskComponent(source: .semantic(SemanticMaskDefinition(
            target: .foreground, edgeFeather: 0.4, edgeShift: -0.2, density: 0.7,
            generationVersion: SemanticMaskDefinition.currentGenerationVersion
        )))
        let layer = LocalAdjustmentLayer(isInverted: true, components: [component])

        let decoded = try JSONDecoder().decode(
            LocalAdjustmentLayer.self,
            from: JSONEncoder().encode(layer)
        )
        XCTAssertEqual(decoded, layer)
        XCTAssertEqual(decoded.components.first?.source.semanticDefinition?.target, .foreground)
        XCTAssertTrue(decoded.isInverted)
    }

    func testMissingCacheRegeneratesThroughCoordinatorResolver() async throws {
        let directory = try Fixtures.makeTempDirectory("SmartMaskRegeneration")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = MaskStore(directory: directory)
        let provider = SmartTestProvider(store: store)
        let coordinator = PhotoAnalysisCoordinator(
            maskStore: store, maskProvider: provider, stages: [:]
        )
        let source = makeSource()
        let assetID = PhotoAssetID.photos(localIdentifier: "smart-regeneration")
        let component = MaskComponent(source: .semantic(SemanticMaskDefinition(target: .subject)))
        let request = LocalMaskResolveRequest(
            source: source, assetID: assetID, component: component,
            targetSize: PixelDimensions(width: 4, height: 4), quality: .preview,
            requestRevision: 12
        )
        let resolver = CoordinatorLocalMaskResolver(coordinator: coordinator)

        _ = try await resolver.resolve(request)
        let firstCallCount = await provider.callCount
        XCTAssertEqual(firstCallCount, 1)
        try FileManager.default.removeItem(at: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        _ = try await resolver.resolve(request)
        let secondCallCount = await provider.callCount
        XCTAssertEqual(secondCallCount, 2)
    }

    func testRenderQualityUpgradesPreviewSeedAndNeverPublishesAnotherAsset() async throws {
        let directory = try Fixtures.makeTempDirectory("SmartMaskRefinement")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = MaskStore(directory: directory)
        let provider = SmartTestProvider(store: store, renderIsUnavailable: true)
        let coordinator = PhotoAnalysisCoordinator(
            maskStore: store, maskProvider: provider, stages: [:]
        )
        let source = makeSource()
        let assetID = PhotoAssetID.photos(localIdentifier: "smart-render")
        let component = MaskComponent(source: .semantic(SemanticMaskDefinition(target: .foreground)))
        let request = LocalMaskResolveRequest(
            source: source, assetID: assetID, component: component,
            targetSize: PixelDimensions(width: 8, height: 8), quality: .export,
            requestRevision: 99
        )
        let payload = try await CoordinatorLocalMaskResolver(coordinator: coordinator).resolve(request)

        XCTAssertEqual(payload.assetID, assetID)
        XCTAssertEqual(payload.quality, .export)
        XCTAssertEqual(payload.requestRevision, 99)
        XCTAssertEqual(payload.targetSize, PixelDimensions(width: 8, height: 8))
        guard case .raster(let mask) = payload.descriptor else {
            return XCTFail("smart render should resolve to a raster payload")
        }
        XCTAssertEqual(mask.size, PixelDimensions(width: 8, height: 8))
        XCTAssertGreaterThan(mask.coverage, 0)
    }

    func testWrongAssetResultIsRejected() async throws {
        let provider = SmartTestProvider(returnsWrongAsset: true)
        let coordinator = PhotoAnalysisCoordinator(
            maskProvider: provider, stages: [:]
        )
        let source = makeSource()
        let component = MaskComponent(source: .semantic(SemanticMaskDefinition(target: .subject)))
        let request = LocalMaskResolveRequest(
            source: source, assetID: .photos(localIdentifier: "expected"), component: component,
            targetSize: PixelDimensions(width: 4, height: 4), quality: .preview
        )

        do {
            _ = try await CoordinatorLocalMaskResolver(coordinator: coordinator).resolve(request)
            XCTFail("a result for another asset must not be published")
        } catch let error as LocalMaskResolutionError {
            XCTAssertEqual(error, .sourceMismatch)
        }
    }

    func testIncompatibleGenerationVersionLeavesDefinitionRecoverable() async throws {
        let coordinator = PhotoAnalysisCoordinator(maskProvider: SmartTestProvider(), stages: [:])
        let component = MaskComponent(source: .semantic(SemanticMaskDefinition(
            target: .background,
            generationVersion: SemanticMaskDefinition.currentGenerationVersion + 1
        )))
        let request = LocalMaskResolveRequest(
            source: makeSource(), assetID: .photos(localIdentifier: "version"), component: component,
            targetSize: PixelDimensions(width: 8, height: 8), quality: .preview
        )

        do {
            _ = try await CoordinatorLocalMaskResolver(coordinator: coordinator).resolve(request)
            XCTFail("newer semantic definitions should not be silently interpreted")
        } catch let error as LocalMaskResolutionError {
            XCTAssertEqual(
                error,
                .incompatibleDefinition(
                    target: .background,
                    version: SemanticMaskDefinition.currentGenerationVersion + 1
                )
            )
        }
    }

    func testForegroundAndBackgroundRequestsShareOneSegmentationTask() async throws {
        let directory = try Fixtures.makeTempDirectory("SmartMaskPair")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = MaskStore(directory: directory)
        let provider = SmartTestProvider(store: store)
        let coordinator = PhotoAnalysisCoordinator(
            maskStore: store, maskProvider: provider, stages: [:]
        )
        let source = makeSource()
        let assetID = PhotoAssetID.photos(localIdentifier: "smart-pair")
        let results = try await withThrowingTaskGroup(
            of: RegionMask.self, returning: [RegionMask].self
        ) { group in
            group.addTask {
                try await coordinator.mask(
                    assetID: assetID, source: source, kind: .foreground, quality: .preview
                )
            }
            group.addTask {
                try await coordinator.mask(
                    assetID: assetID, source: source, kind: .background, quality: .preview
                )
            }
            var values: [RegionMask] = []
            for try await value in group { values.append(value) }
            return values
        }

        XCTAssertEqual(results.count, 2)
        let calls = await provider.callCount
        XCTAssertEqual(calls, 1)
        let foreground = try XCTUnwrap(results.first(where: { $0.kind == .foreground }))
        let background = try XCTUnwrap(results.first(where: { $0.kind == .background }))
        let foregroundPixels = await store.pixels(for: foreground.reference)
        let backgroundPixels = await store.pixels(for: background.reference)
        XCTAssertEqual(backgroundPixels?.values, foregroundPixels?.values.map { 1 - $0 })
    }

    private func makeSource() -> ImageSource {
        ImageSource(
            backing: .data(Data([1, 2, 3, 4])), kind: .standard,
            nativeExtent: CGSize(width: 8, height: 8)
        )
    }
}

private actor SmartTestProvider: SemanticMaskProviding {
    private(set) var callCount = 0
    private let renderIsUnavailable: Bool
    private let returnsWrongAsset: Bool
    private let store: MaskStore

    init(
        store: MaskStore = MaskStore(), renderIsUnavailable: Bool = false,
        returnsWrongAsset: Bool = false
    ) {
        self.store = store
        self.renderIsUnavailable = renderIsUnavailable
        self.returnsWrongAsset = returnsWrongAsset
    }

    func mask(for kind: SemanticMaskKind, image: AnalysisImage, quality: MaskQuality) async throws -> RegionMask {
        callCount += 1
        if renderIsUnavailable && quality == .render {
            throw VisionSemanticMaskError.unsupportedQuality(.render, kind)
        }
        let size = image.dimensions
        let values = (0..<size.width * size.height).map { index in
            Float(index.isMultiple(of: 2) ? 0.8 : 0.2)
        }
        let pixels = try NormalizedMask(size: size, values: values)
        let assetID = returnsWrongAsset
            ? PhotoAssetID.photos(localIdentifier: "wrong")
            : (image.assetID ?? PhotoAnalysisCoordinator.assetID(for: image.source))
        let key = MaskCacheKey(
            assetID: assetID,
            sourceFingerprint: PhotoAnalysisCoordinator.sourceFingerprint(for: image.source),
            kind: kind, quality: quality, providerVersion: "smart-test-1"
        )
        let reference = try await store.store(pixels, for: key, quality: quality)
        return RegionMask(
            kind: kind, bounds: NormalizedRect(x: 0, y: 0, width: 1, height: 1),
            quality: quality, reference: reference, confidence: 1, coverage: pixels.coverage
        )
    }
}

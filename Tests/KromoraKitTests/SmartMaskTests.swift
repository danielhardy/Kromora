import CoreGraphics
import Foundation
import XCTest

@testable import KromoraKit

final class SmartMaskTests: TempDirectoryTestCase {
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
            targetSize: PixelDimensions(width: 4, height: 4), quality: .preview
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
            targetSize: PixelDimensions(width: 8, height: 8), quality: .export
        )
        let payload = try await CoordinatorLocalMaskResolver(coordinator: coordinator).resolve(request)

        XCTAssertEqual(payload.assetID, assetID)
        XCTAssertEqual(payload.quality, .export)
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

    func testCoordinatorResolverAppliesSemanticSettingsBeforeResizeAndBoundsPayload() async throws {
        let size = PixelDimensions(width: 11, height: 7)
        let seed = try NormalizedMask(
            size: size,
            values: (0..<size.width * size.height).map { index in
                Float(index % size.width) / Float(size.width - 1)
            }
        )
        let source = makeSource(width: size.width, height: size.height)
        let resolver = makeCoordinatorMaskResolver(seed: seed, directory: "semantic-adjustments")
        let targetSize = PixelDimensions(width: 19, height: 13)
        let definition = SemanticMaskDefinition(
            target: .subject, edgeFeather: 0.7, edgeShift: 0.18, density: 0.73
        )

        let payload = try await resolver.resolve(LocalMaskResolveRequest(
            source: source, assetID: PhotoAnalysisCoordinator.assetID(for: source),
            component: MaskComponent(source: .semantic(definition)),
            targetSize: targetSize, quality: .preview
        ))

        XCTAssertEqual(payload.targetSize, targetSize)
        guard case .raster(let mask) = payload.descriptor else {
            return XCTFail("semantic resolution should return a raster matte")
        }
        XCTAssertEqual(mask.size, targetSize)
        XCTAssertTrue(mask.values.allSatisfy { $0.isFinite && (0...1).contains($0) })
    }

    func testSemanticStrengthAndExtremeEdgeShiftClampResolvedCoverage() async throws {
        let size = PixelDimensions(width: 8, height: 8)
        let seed = try NormalizedMask(
            size: size,
            values: (0..<size.height).flatMap { _ in
                (0..<size.width).map { $0 < size.width / 2 ? Float(1) : Float(0) }
            }
        )
        let source = makeSource(width: size.width, height: size.height)
        let resolver = makeCoordinatorMaskResolver(seed: seed, directory: "semantic-limits")
        // Keep the requested size native here so this test isolates the affine strength/shift
        // semantics from resampling-kernel edge response, which the smooth-matte test covers.
        let targetSize = size

        func resolve(_ definition: SemanticMaskDefinition) async throws -> NormalizedMask {
            let payload = try await resolver.resolve(LocalMaskResolveRequest(
                source: source, assetID: PhotoAnalysisCoordinator.assetID(for: source),
                component: MaskComponent(source: .semantic(definition)),
                targetSize: targetSize, quality: .preview
            ))
            guard case .raster(let mask) = payload.descriptor else {
                throw LocalMaskResolutionError.invalidPayload
            }
            return mask
        }

        let halfStrength = try await resolve(SemanticMaskDefinition(target: .subject, density: 0.5))
        XCTAssertEqual(try XCTUnwrap(halfStrength.values.max()), 0.5)
        let shiftedFull = try await resolve(SemanticMaskDefinition(target: .subject, edgeShift: 1))
        XCTAssertTrue(shiftedFull.values.allSatisfy { $0 == 1 })
        let shiftedEmpty = try await resolve(SemanticMaskDefinition(target: .subject, edgeShift: -1))
        XCTAssertTrue(shiftedEmpty.values.allSatisfy { $0 == 0 })
    }

    func testSofteningBeforeResizeStaysWithinToleranceOfResizeThenSoftening() async throws {
        let size = PixelDimensions(width: 73, height: 55)
        let seed = try NormalizedMask(
            size: size,
            values: (0..<size.height).flatMap { y in
                (0..<size.width).map { x in
                    let horizontal = Double(x) / Double(size.width - 1)
                    let vertical = Double(y) / Double(size.height - 1)
                    return Float(0.5 + 0.42 * sin(2 * .pi * horizontal) * cos(.pi * vertical))
                }
            }
        )
        let source = makeSource(width: size.width, height: size.height)
        let resolver = makeCoordinatorMaskResolver(seed: seed, directory: "semantic-order")
        let targetSize = PixelDimensions(width: 121, height: 97)
        // The 1 px minimum and integer radius rounding make the two filter orders differ slightly.
        // A 0.05 absolute-coverage bound allows those sampling differences while catching a visibly
        // different softness profile on this smooth matte.
        let maximumCoverageDifference: Float = 0.05

        for softness in [0.12, 0.5, 0.9] {
            let definition = SemanticMaskDefinition(target: .subject, edgeFeather: softness)
            let payload = try await resolver.resolve(LocalMaskResolveRequest(
                source: source, assetID: PhotoAnalysisCoordinator.assetID(for: source),
                component: MaskComponent(source: .semantic(definition)),
                targetSize: targetSize, quality: .preview
            ))
            guard case .raster(let resolved) = payload.descriptor else {
                return XCTFail("semantic resolution should return a raster matte")
            }

            let resizedFirst = try MaskOperations.resized(seed, to: targetSize)
            let targetRadius = max(
                1, Int((softness * Double(min(targetSize.width, targetSize.height)) * 0.05).rounded())
            )
            let resizeThenSoften = try MaskOperations.feather(resizedFirst, radius: targetRadius)
            let maximumDifference = zip(resolved.values, resizeThenSoften.values)
                .map { abs($0 - $1) }
                .max() ?? 0
            XCTAssertLessThanOrEqual(
                maximumDifference, maximumCoverageDifference,
                "softness \(softness) differs by \(maximumDifference), above the documented sampling tolerance"
            )
        }
    }

    func testIdentitySemanticDefinitionResizesWithoutCallingFeather() async throws {
        let size = PixelDimensions(width: 9, height: 7)
        let seed = try NormalizedMask(
            size: size,
            values: (0..<size.width * size.height).map { Float($0 % size.width) / Float(size.width - 1) }
        )
        var featherCallCount = 0
        let definition = SemanticMaskDefinition(target: .subject)
        let adjusted = try CoordinatorLocalMaskResolver.apply(definition, to: seed) { mask, radius in
            featherCallCount += 1
            return try MaskOperations.feather(mask, radius: radius)
        }
        XCTAssertEqual(adjusted, seed)
        XCTAssertEqual(featherCallCount, 0, "identity must bypass the feather allocation path")

        let source = makeSource(width: size.width, height: size.height)
        let resolver = makeCoordinatorMaskResolver(seed: seed, directory: "semantic-identity")
        let targetSize = PixelDimensions(width: 15, height: 11)
        let payload = try await resolver.resolve(LocalMaskResolveRequest(
            source: source, assetID: PhotoAnalysisCoordinator.assetID(for: source),
            component: MaskComponent(source: .semantic(definition)),
            targetSize: targetSize, quality: .preview
        ))
        guard case .raster(let resolved) = payload.descriptor else {
            return XCTFail("semantic resolution should return a raster matte")
        }
        XCTAssertEqual(resolved, try MaskOperations.resized(seed, to: targetSize))
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

    private func makeSource(width: Int = 8, height: Int = 8) -> ImageSource {
        ImageSource(
            backing: .data(Data([1, 2, 3, 4])), kind: .standard,
            nativeExtent: CGSize(width: width, height: height)
        )
    }

    private func makeCoordinatorMaskResolver(
        seed: NormalizedMask,
        directory: String
    ) -> CoordinatorLocalMaskResolver {
        let store = MaskStore(directory: tempDirectory.appendingPathComponent(directory))
        let provider = ResolverFixtureMaskProvider(seed: seed, store: store)
        let coordinator = PhotoAnalysisCoordinator(
            maskStore: store, maskProvider: provider, stages: [:]
        )
        return CoordinatorLocalMaskResolver(coordinator: coordinator)
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
        // Like the production provider, own the durable lookup. A background request re-enters the
        // coordinator for foreground; when the first foreground task has already finished, that
        // repeat must be a store hit rather than a second segmentation, whatever the task ordering.
        if !returnsWrongAsset {
            let cachedKey = MaskCacheKey(
                assetID: image.assetID ?? PhotoAnalysisCoordinator.assetID(for: image.source),
                sourceFingerprint: PhotoAnalysisCoordinator.sourceFingerprint(for: image.source),
                kind: kind, quality: quality, providerVersion: "smart-test-1"
            )
            if let reference = await store.mask(for: cachedKey, quality: quality),
               let pixels = await store.pixels(for: reference) {
                return RegionMask(
                    kind: kind, bounds: NormalizedRect(x: 0, y: 0, width: 1, height: 1),
                    quality: quality, reference: reference, confidence: 1, coverage: pixels.coverage
                )
            }
        }
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

private actor ResolverFixtureMaskProvider: SemanticMaskProviding {
    private let seed: NormalizedMask
    private let store: MaskStore

    init(seed: NormalizedMask, store: MaskStore) {
        self.seed = seed
        self.store = store
    }

    func mask(for kind: SemanticMaskKind, image: AnalysisImage, quality: MaskQuality) async throws -> RegionMask {
        let assetID = image.assetID ?? PhotoAnalysisCoordinator.assetID(for: image.source)
        let key = MaskCacheKey(
            assetID: assetID,
            sourceFingerprint: PhotoAnalysisCoordinator.sourceFingerprint(for: image.source),
            kind: kind,
            quality: quality,
            providerVersion: "resolver-fixture-1"
        )
        let reference = try await store.store(seed, for: key, quality: quality)
        return RegionMask(
            kind: kind,
            bounds: NormalizedRect(x: 0, y: 0, width: 1, height: 1),
            quality: quality,
            reference: reference,
            confidence: 1,
            coverage: seed.coverage
        )
    }
}

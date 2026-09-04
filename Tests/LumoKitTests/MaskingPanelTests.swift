import CoreGraphics
import Foundation
import XCTest

@testable import LumoKit

@MainActor
final class MaskingPanelTests: XCTestCase {
    func testPanelModelUsesCoordinatorMasksAndSharedMaskOperationsForInvert() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LumoMaskPanel-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = MaskStore(directory: directory)
        let provider = PanelMaskProvider(store: store)
        let coordinator = PhotoAnalysisCoordinator(
            engine: FakeRenderEngine(), maskStore: store, maskProvider: provider, stages: [:]
        )
        let source = ImageSource(
            backing: .data(Data([1, 2, 3])), kind: .standard,
            nativeExtent: CGSize(width: 2, height: 2)
        )
        let model = MaskingPanelModel(
            coordinator: coordinator,
            assetID: PhotoAssetID.data(Data([1, 2, 3])),
            source: source
        )

        model.load()
        while model.isLoading {
            await Task.yield()
        }

        XCTAssertEqual(model.availableSelections.map(\.kind), [.subject])
        XCTAssertEqual(model.selectedPixels?.values, [1, 0, 0, 1])
        model.isInverted = true
        XCTAssertEqual(model.selectedPixels?.values, [0, 1, 1, 0])
    }

    func testSelectInvertApplyHandsDerivedMaskAndCurrentAssetToLocalWorkflow() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LumoMaskApply-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = MaskStore(directory: directory)
        let coordinator = PhotoAnalysisCoordinator(
            engine: FakeRenderEngine(), maskStore: store, maskProvider: PanelMaskProvider(store: store), stages: [:]
        )
        let sourceData = Data([7, 8, 9])
        let assetID = PhotoAssetID.data(sourceData)
        let source = ImageSource(
            backing: .data(sourceData), kind: .standard,
            nativeExtent: CGSize(width: 2, height: 2)
        )
        var receivedAssetID: PhotoAssetID?
        var receivedMask: RegionMask?
        let model = MaskingPanelModel(
            coordinator: coordinator,
            assetID: assetID,
            source: source,
            onApply: { id, mask in
                receivedAssetID = id
                receivedMask = mask
            }
        )

        model.load()
        while model.isLoading { await Task.yield() }
        model.isInverted = true
        await model.apply()

        XCTAssertEqual(receivedAssetID, assetID)
        XCTAssertEqual(receivedMask?.kind, .unknown("invert"))
        XCTAssertEqual(receivedMask?.reference.cacheKey.assetID, assetID)
        let appliedReference = try XCTUnwrap(receivedMask?.reference)
        let appliedPixels = await coordinator.pixels(for: appliedReference)
        XCTAssertEqual(appliedPixels?.values, [0, 1, 1, 0])
        XCTAssertEqual(model.appliedMask, receivedMask)
    }

    func testApplyIsTruthfullyDisabledWhenNoLocalAdjustmentHookExists() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LumoMaskDisabled-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = MaskStore(directory: directory)
        let coordinator = PhotoAnalysisCoordinator(
            engine: FakeRenderEngine(), maskStore: store, maskProvider: PanelMaskProvider(store: store), stages: [:]
        )
        let source = ImageSource(
            backing: .data(Data([10, 11, 12])), kind: .standard,
            nativeExtent: CGSize(width: 2, height: 2)
        )
        let model = MaskingPanelModel(
            coordinator: coordinator,
            assetID: PhotoAssetID.data(Data([10, 11, 12])),
            source: source
        )

        model.load()
        while model.isLoading { await Task.yield() }
        XCTAssertFalse(model.canApplyMask)
        XCTAssertTrue(model.applyHelp.contains("cannot own a mask"))
        await model.apply()
        XCTAssertNil(model.appliedMask)
    }

    func testUnavailableMasksExplainFailureAndRemainRetryable() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LumoMaskUnavailable-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = MaskStore(directory: directory)
        let coordinator = PhotoAnalysisCoordinator(
            engine: FakeRenderEngine(), maskStore: store,
            maskProvider: UnavailablePanelMaskProvider(), stages: [:]
        )
        let source = ImageSource(
            backing: .data(Data([13, 14, 15])), kind: .standard,
            nativeExtent: CGSize(width: 2, height: 2)
        )
        let model = MaskingPanelModel(
            coordinator: coordinator,
            assetID: PhotoAssetID.data(Data([13, 14, 15])),
            source: source
        )

        model.load()
        while model.isLoading { await Task.yield() }

        XCTAssertTrue(model.availableSelections.isEmpty)
        XCTAssertEqual(model.errorMessage, "Mask generation failed for this photo. Retry to try again.")
        XCTAssertFalse(model.canApplyMask)
    }

    func testMaskingPanelConstructsWithoutAnImage() {
        let coordinator = PhotoAnalysisCoordinator(stages: [:])
        let source = ImageSource(
            backing: .data(Data([4, 5, 6])), kind: .standard,
            nativeExtent: CGSize(width: 2, height: 2)
        )
        let panel = MaskingPanel(
            coordinator: coordinator,
            assetID: PhotoAssetID.data(Data([4, 5, 6])),
            source: source
        )

        XCTAssertNotNil(panel.body)
    }
}

private actor PanelMaskProvider: SemanticMaskProviding {
    private let store: MaskStore

    init(store: MaskStore) { self.store = store }

    func mask(for kind: SemanticMaskKind, image: AnalysisImage, quality: MaskQuality) async throws -> RegionMask {
        guard kind == .subject else { throw PanelMaskError.unavailable }
        let sourceData: Data
        switch image.source.backing {
        case .data(let data): sourceData = data
        case .url(let url): sourceData = Data(url.absoluteString.utf8)
        }
        let key = MaskCacheKey(
            assetID: PhotoAssetID.data(sourceData),
            sourceFingerprint: PhotoSourceFingerprint.data(sourceData),
            kind: kind,
            quality: quality,
            providerVersion: "panel-test"
        )
        let pixels = try NormalizedMask(
            size: PixelDimensions(width: 2, height: 2), values: [1, 0, 0, 1]
        )
        let reference = try await store.store(pixels, for: key, quality: quality)
        return RegionMask(
            kind: kind,
            bounds: NormalizedRect(x: 0, y: 0, width: 1, height: 1),
            quality: quality,
            reference: reference,
            confidence: 1,
            coverage: pixels.coverage
        )
    }
}

private actor UnavailablePanelMaskProvider: SemanticMaskProviding {
    func mask(for kind: SemanticMaskKind, image: AnalysisImage, quality: MaskQuality) async throws -> RegionMask {
        throw PanelMaskError.unavailable
    }
}

private enum PanelMaskError: Error {
    case unavailable
}

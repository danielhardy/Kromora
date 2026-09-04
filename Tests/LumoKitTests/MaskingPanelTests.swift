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
        let sourceData = Data("panel".utf8)
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

private enum PanelMaskError: Error {
    case unavailable
}

import CoreGraphics
import Foundation
import XCTest

@testable import KromoraKit

#if DEBUG
@MainActor
final class AnalysisDebugPanelTests: XCTestCase {
    func testModelLoadsMasksMapsProviderErrorsAndControlsOverlayVisibility() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("KromoraAnalysisPanel-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = MaskStore(directory: directory)
        let coordinator = PhotoAnalysisCoordinator(
            engine: FakeRenderEngine(),
            maskStore: store,
            maskProvider: AnalysisPanelMaskProvider(store: store),
            stages: [:]
        )
        let sourceData = Data([21, 22, 23])
        let source = ImageSource(
            backing: .data(sourceData), kind: .standard,
            nativeExtent: CGSize(width: 2, height: 2)
        )
        let model = AnalysisDebugPanelModel(
            coordinator: coordinator,
            assetID: PhotoAssetID.data(sourceData),
            source: source
        )

        model.load()
        while model.isLoading { await Task.yield() }

        XCTAssertNotNil(model.analysis)
        XCTAssertEqual(model.masks.count, 5)
        XCTAssertTrue(model.isVisible(.subject))
        XCTAssertFalse(model.isVisible(.person))
        XCTAssertTrue(model.masks.contains { $0.kind == .person && $0.providerError != nil })

        model.setVisible(.subject, false)
        XCTAssertFalse(model.isVisible(.subject))
        model.setVisible(.subject, true)
        XCTAssertTrue(model.isVisible(.subject))

        await coordinator.shutdown()
    }
}
#endif

private actor AnalysisPanelMaskProvider: SemanticMaskProviding {
    private let store: MaskStore

    init(store: MaskStore) { self.store = store }

    func mask(for kind: SemanticMaskKind, image: AnalysisImage, quality: MaskQuality) async throws -> RegionMask {
        guard kind == .subject else { throw AnalysisPanelError.unavailable }
        let pixels = try NormalizedMask(
            size: PixelDimensions(width: 2, height: 2), values: [1, 0, 0, 1]
        )
        let assetID = image.assetID ?? PhotoAnalysisCoordinator.assetID(for: image.source)
        let key = MaskCacheKey(
            assetID: assetID,
            sourceFingerprint: PhotoAnalysisCoordinator.sourceFingerprint(for: image.source),
            kind: kind,
            quality: quality,
            providerVersion: "analysis-panel-test"
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

private enum AnalysisPanelError: Error {
    case unavailable
}

import CoreGraphics
import Foundation
import XCTest

@testable import KromoraKit

#if DEBUG
@MainActor
final class AnalysisDebugPanelTests: XCTestCase {
    func testAnalysisMaskOverlayLayoutMapsNonOriginCropAndFitsItsAspectRatio() throws {
        let sourceSize = CGSize(width: 2400, height: 1200)
        let crop = CropAdjustments(normalizedRect: CGRect(x: 0.2, y: 0.25, width: 0.5, height: 0.4))
        let layout = AnalysisMaskOverlayLayout(
            sourceSize: sourceSize, crop: crop, viewportSize: CGSize(width: 300, height: 130)
        )

        XCTAssertEqual(layout.cropFrame.width / layout.cropFrame.height, 2.5, accuracy: 0.000_001)
        XCTAssertEqual(layout.cropFrame.width, 300, accuracy: 0.000_001)
        XCTAssertEqual(layout.sourceFrame.width / layout.sourceFrame.height, 2, accuracy: 0.000_001)
        XCTAssertLessThan(layout.sourceFrame.minX, layout.cropFrame.minX)
        XCTAssertLessThan(layout.sourceFrame.minY, layout.cropFrame.minY)
        XCTAssertEqual(layout.sourceFrame.minX + 0.2 * layout.sourceFrame.width,
                       layout.cropFrame.minX, accuracy: 0.000_001)
        // CropAdjustments uses a bottom-left origin; the mask and viewport use top-left.
        XCTAssertEqual(layout.sourceFrame.minY + 0.35 * layout.sourceFrame.height,
                       layout.cropFrame.minY, accuracy: 0.000_001)

        // A subject sample inside the crop must land at the same fractional position in the
        // fitted preview. This catches overlays that fit the mask independently of the photo.
        let subjectPoint = CGPoint(x: 0.45, y: 0.55)
        let transform = CanvasMaskTransform(
            sourceSize: sourceSize, crop: crop, viewportSize: CGSize(width: 300, height: 130)
        )
        let presentedSubjectPoint = try XCTUnwrap(
            transform.viewportPoint(forSourceNormalized: subjectPoint)
        )
        XCTAssertEqual(
            presentedSubjectPoint.x,
            layout.cropFrame.minX + 0.5 * layout.cropFrame.width,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            presentedSubjectPoint.y,
            layout.cropFrame.minY + 0.5 * layout.cropFrame.height,
            accuracy: 0.000_001
        )
    }

    func testAnalysisMaskOverlayIdentityCropMatchesFittedPhotoFrame() {
        let layout = AnalysisMaskOverlayLayout(
            sourceSize: CGSize(width: 2400, height: 1200),
            crop: .neutral,
            viewportSize: CGSize(width: 300, height: 130)
        )

        XCTAssertEqual(layout.sourceFrame, layout.cropFrame)
        XCTAssertEqual(layout.cropFrame.width / layout.cropFrame.height, 2, accuracy: 0.000_001)
    }

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

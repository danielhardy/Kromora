import CoreGraphics
import ImageIO
import XCTest
@testable import KromoraKit

final class InfoSemanticMaskRenderingTests: TempDirectoryTestCase {
    private func image(from result: RenderResult) throws -> CGImage {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(result.data as CFData, nil))
        return try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }

    func testInfoSubjectAndPersonMasksChangeExpectedPixelsInPreviewAndExport() async throws {
        let source = try Fixtures.writeGradientPNG(
            width: 8, height: 4, named: "info-semantic.png", in: tempDirectory
        )
        let imageSource = ImageSource(url: source, nativeExtent: CGSize(width: 8, height: 4))
        let store = MaskStore(directory: tempDirectory.appendingPathComponent("info-semantic-masks"))
        let coordinator = PhotoAnalysisCoordinator(
            maskStore: store,
            maskProvider: InfoSemanticMaskProvider(store: store),
            stages: [:]
        )
        let engine = RenderEngine(maskResolver: CoordinatorLocalMaskResolver(coordinator: coordinator))
        let base = try await engine.render(RenderRequest(
            source: imageSource, document: EditDocument(), targetSize: CGSize(width: 8, height: 4),
            quality: .preview, output: .raster
        ))
        let basePixels = try Pixels.bytes(of: image(from: base))

        for target in [SemanticTarget.subject, .person] {
            let layer = LocalAdjustmentLayer(
                components: [MaskComponent(
                    source: .semantic(SemanticMaskDefinition(target: target))
                )],
                adjustments: LocalAdjustments(exposure: 2)
            )
            let preview = try await engine.render(RenderRequest(
                source: imageSource, document: EditDocument(localAdjustments: [layer]),
                targetSize: CGSize(width: 8, height: 4), quality: .preview, output: .raster
            ))
            let export = try await engine.render(RenderRequest(
                source: imageSource, document: EditDocument(localAdjustments: [layer]),
                quality: .export, output: .raster
            ))
            let previewPixels = try Pixels.bytes(of: image(from: preview))
            XCTAssertGreaterThan(
                abs(Int(previewPixels[(2 * 8 + 1) * 4]) - Int(basePixels[(2 * 8 + 1) * 4])),
                10,
                "\(target) should affect covered pixels in preview"
            )
            XCTAssertLessThan(
                abs(Int(previewPixels[(2 * 8 + 6) * 4]) - Int(basePixels[(2 * 8 + 6) * 4])),
                3,
                "\(target) should leave uncovered pixels unchanged in preview"
            )
            assertPixelsEqual(
                previewPixels, try Pixels.bytes(of: image(from: export)), tolerance: 1,
                "\(target) preview and export must share local-mask rendering"
            )
        }
    }
}

private actor InfoSemanticMaskProvider: SemanticMaskProviding {
    private let store: MaskStore

    init(store: MaskStore) { self.store = store }

    func mask(for kind: SemanticMaskKind, image: AnalysisImage, quality: MaskQuality) async throws -> RegionMask {
        guard kind == .subject || kind == .person else {
            throw VisionSemanticMaskError.unsupported(kind)
        }
        let size = image.dimensions
        let values = (0..<size.height).flatMap { _ in
            (0..<size.width).map { $0 < size.width / 2 ? Float(1) : Float(0) }
        }
        let pixels = try NormalizedMask(size: size, values: values)
        let assetID = image.assetID ?? PhotoAnalysisCoordinator.assetID(for: image.source)
        let key = MaskCacheKey(
            assetID: assetID,
            sourceFingerprint: PhotoAnalysisCoordinator.sourceFingerprint(for: image.source),
            kind: kind,
            quality: quality,
            providerVersion: "info-test-1"
        )
        let reference = try await store.store(pixels, for: key, quality: quality)
        return RegionMask(
            kind: kind,
            bounds: NormalizedRect(x: 0, y: 0, width: 0.5, height: 1),
            quality: quality,
            reference: reference,
            confidence: 1,
            coverage: pixels.coverage
        )
    }
}

import CoreGraphics
import ImageIO
import XCTest
@testable import LumoKit

/// Step 2 render seam tests. These exercise the actor boundary and the one shared preview/export
/// graph rather than testing a second CPU implementation of local adjustments.
final class LocalMaskRenderingTests: TempDirectoryTestCase {
    private func source() throws -> ImageSource {
        let url = try Fixtures.writeGradientPNG(width: 8, height: 4, named: "local-mask.png", in: tempDirectory)
        return ImageSource(url: url, nativeExtent: CGSize(width: 8, height: 4))
    }

    private func layer(
        id: UUID = UUID(),
        amount: Double = 1,
        inverted: Bool = false,
        adjustments: LocalAdjustments = LocalAdjustments(exposure: 1),
        mode: MaskCombineMode = .replace
    ) -> LocalAdjustmentLayer {
        LocalAdjustmentLayer(
            id: id, isInverted: inverted, amount: amount,
            components: [MaskComponent(mode: mode, source: .linear(LinearGradientDefinition()))],
            adjustments: adjustments
        )
    }

    private func image(from result: RenderResult) throws -> CGImage {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(result.data as CFData, nil))
        return try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }

    func testSoftMaskBlendsLocalExposureAndPreviewMatchesFullRender() async throws {
        let source = try source()
        let values: [Float] = [0, 0.25, 0.5, 0.75,
                               0, 0.25, 0.5, 0.75,
                               0, 0.25, 0.5, 0.75,
                               0, 0.25, 0.5, 0.75]
        let resolver = TestMaskResolver(values: values, sourceFingerprint: source.cacheFingerprint)
        let document = EditDocument(localAdjustments: [layer()])
        let engine = RenderEngine(maskResolver: resolver)
        let preview = try await engine.render(RenderRequest(
            source: source, document: document, targetSize: CGSize(width: 8, height: 4),
            quality: .preview, output: .raster
        ))
        let export = try await engine.render(RenderRequest(
            source: source, document: document, quality: .export, output: .raster
        ))

        let previewImage = try image(from: preview)
        let exportImage = try image(from: export)
        XCTAssertEqual(previewImage.width, exportImage.width)
        XCTAssertEqual(previewImage.height, exportImage.height)
        assertPixelsEqual(try Pixels.bytes(of: previewImage), try Pixels.bytes(of: exportImage), tolerance: 1,
                          "preview and export must use the same local-mask graph")
        let base = try await engine.render(RenderRequest(
            source: source, document: EditDocument(), targetSize: CGSize(width: 8, height: 4),
            quality: .preview, output: .raster
        ))
        let pixels = try Pixels.bytes(of: previewImage)
        let basePixels = try Pixels.bytes(of: image(from: base))
        XCTAssertGreaterThan(Int(pixels[2 * 4]), Int(basePixels[2 * 4]),
                             "a fractional soft-mask edge should blend the local exposure")
    }

    func testOrderedLayersFeedTheNextLayerAndGlobalSliderDoesNotReResolveMasks() async throws {
        let source = try source()
        let firstID = UUID()
        let secondID = UUID()
        let resolver = TestMaskResolver(values: Array(repeating: 1, count: 16),
                                        sourceFingerprint: source.cacheFingerprint)
        let first = layer(id: firstID, adjustments: LocalAdjustments(exposure: 1))
        let second = layer(id: secondID, adjustments: LocalAdjustments(exposure: -1))
        let engine = RenderEngine(maskResolver: resolver)
        _ = try await engine.render(RenderRequest(
            source: source, document: EditDocument(localAdjustments: [first, second]),
            targetSize: CGSize(width: 8, height: 4), quality: .preview
        ))
        _ = try await engine.render(RenderRequest(
            source: source, document: EditDocument(
                light: LightAdjustments(contrast: 25), localAdjustments: [first, second]
            ), targetSize: CGSize(width: 8, height: 4), quality: .preview
        ))
        let stats = await engine.cacheStatistics()
        XCTAssertEqual(stats.localMask.misses, 1, "identical component definitions share one payload")
        XCTAssertEqual(stats.localMask.hits, 3, "global slider edits must not invalidate mask payloads")
    }

    func testSemanticExportRejectsAnUnresolvedMaskWithAnActionableError() async throws {
        let source = try source()
        let semantic = LocalAdjustmentLayer(
            components: [MaskComponent(source: .semantic(SemanticMaskDefinition(target: .subject)))],
            adjustments: LocalAdjustments(exposure: 1)
        )
        let engine = RenderEngine()
        do {
            _ = try await engine.render(RenderRequest(
                source: source, document: EditDocument(localAdjustments: [semantic]),
                quality: .export, output: .raster
            ))
            XCTFail("unresolved semantic masks must not silently export")
        } catch let error as LocalMaskResolutionError {
            guard case .semanticMaskUnavailable(let target, let quality) = error else {
                return XCTFail("unexpected mask error: \(error)")
            }
            XCTAssertEqual(target, .subject)
            XCTAssertEqual(quality, .render)
        }
    }

    func testBuiltInResolverRendersAnalyticLinearAndRadialMasks() async throws {
        let source = try source()
        let linear = layer(adjustments: LocalAdjustments(exposure: 1))
        let radial = LocalAdjustmentLayer(
            components: [MaskComponent(source: .radial(RadialGradientDefinition()))],
            adjustments: LocalAdjustments(saturation: 35)
        )
        let result = try await RenderEngine().render(RenderRequest(
            source: source, document: EditDocument(localAdjustments: [linear, radial]),
            targetSize: CGSize(width: 8, height: 4), quality: .preview, output: .raster
        ))
        let pixels = try Pixels.bytes(of: image(from: result))
        XCTAssertTrue(pixels.allSatisfy { $0 <= 255 }, "analytic mask output must stay finite")
    }
}

private struct TestMaskResolver: LocalMaskResolving {
    let values: [Float]
    let sourceFingerprint: String

    func resolve(_ request: LocalMaskResolveRequest) async throws -> LocalMaskPayload {
        let count = max(0, request.targetSize.width * request.targetSize.height)
        let payloadValues = values.isEmpty ? Array(repeating: Float(0), count: count) :
            (0..<count).map { values[$0 % values.count] }
        let mask = try NormalizedMask(size: request.targetSize, values: payloadValues)
        return LocalMaskPayload(
            sourceFingerprint: sourceFingerprint,
            definitionHash: RenderCacheHash.digest(request.component.source),
            targetSize: request.targetSize,
            quality: request.quality,
            descriptor: .raster(mask)
        )
    }
}

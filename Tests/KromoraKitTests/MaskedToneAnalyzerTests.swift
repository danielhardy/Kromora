import CoreGraphics
import Foundation
import XCTest

@testable import KromoraKit

final class MaskedToneAnalyzerTests: TempDirectoryTestCase {
    func testRegionalStatisticsUseOnlyTheSelectedPixels() async throws {
        let sourceData = Data("regional-statistics".utf8)
        let source = ImageSource(data: sourceData, nativeExtent: CGSize(width: 4, height: 1))
        let image = try AnalysisImageFactory.make(
            from: source,
            configuration: AnalysisConfiguration(maximumDimension: 4))
        let store = MaskStore(directory: tempDirectory)
        let dark = try await makeMask(
            values: [1, 1, 0, 0], sourceData: sourceData, store: store, image: image,
            kind: .foregroundInstance(0)
        )
        let bright = try await makeMask(
            values: [0, 0, 1, 1], sourceData: sourceData, store: store, image: image,
            kind: .foregroundInstance(1)
        )
        let engine = FakeRenderEngine(
            previewResult: try makeStrip(
                values: [0, 0, 255, 255], width: 4, height: 1
            ))
        let analyzer = MaskedToneAnalyzer(engine: engine, store: store)

        let darkStats = try await analyzer.statistics(image: image, through: dark)
        let brightStats = try await analyzer.statistics(image: image, through: bright)

        XCTAssertLessThan(darkStats.tone.mean, brightStats.tone.mean)
        XCTAssertEqual(darkStats.tone.mean, 0, accuracy: 0.01)
        XCTAssertEqual(brightStats.tone.mean, 1, accuracy: 0.01)
    }

    func testSoftMaskRetainsFractionalEdgeWeights() async throws {
        let sourceData = Data("soft-mask".utf8)
        let source = ImageSource(data: sourceData, nativeExtent: CGSize(width: 4, height: 1))
        let image = try AnalysisImageFactory.make(
            from: source,
            configuration: AnalysisConfiguration(maximumDimension: 4))
        let store = MaskStore(directory: tempDirectory)
        let mask = try await makeMask(
            values: [0, 0.5, 0.5, 1], sourceData: sourceData, store: store, image: image
        )
        let engine = FakeRenderEngine(
            previewResult: try makeStrip(
                values: [0, 0, 255, 255], width: 4, height: 1
            ))
        let stats = try await MaskedToneAnalyzer(engine: engine, store: store)
            .statistics(image: image, through: mask)

        // One bright pixel contributes 0.5 and the other contributes 1.0: 1.5 / 2.0.
        XCTAssertEqual(stats.tone.mean, 0.75, accuracy: 0.02)
    }

    func testMaskFromAnotherSourceIsRejectedBeforeRendering() async throws {
        let sourceData = Data("source-a".utf8)
        let source = ImageSource(data: sourceData, nativeExtent: CGSize(width: 2, height: 1))
        let image = try AnalysisImageFactory.make(
            from: source,
            configuration: AnalysisConfiguration(maximumDimension: 2))
        let store = MaskStore(directory: tempDirectory)
        let mask = try await makeMask(
            values: [1, 0], sourceData: sourceData, store: store, image: image
        )
        let otherSource = ImageSource(
            data: Data("source-b".utf8), nativeExtent: CGSize(width: 2, height: 1))
        let otherImage = try AnalysisImageFactory.make(
            from: otherSource,
            configuration: AnalysisConfiguration(maximumDimension: 2))

        do {
            _ = try await MaskedToneAnalyzer(engine: FakeRenderEngine(), store: store)
                .statistics(image: otherImage, through: mask)
            XCTFail("expected a source identity mismatch")
        } catch let error as MaskedToneAnalysisError {
            XCTAssertEqual(error, .mismatchedImage)
        }
    }

    private func makeMask(
        values: [Float], sourceData: Data, store: MaskStore, image: AnalysisImage,
        kind: SemanticMaskKind = .foregroundInstance(0)
    ) async throws -> RegionMask {
        let pixels = try NormalizedMask(
            size: image.dimensions, values: values
        )
        let fingerprint = PhotoSourceFingerprint.data(sourceData)
        let key = MaskCacheKey(
            assetID: PhotoAssetID.data(sourceData), sourceFingerprint: fingerprint,
            kind: kind, quality: .analysis
        )
        let reference = try await store.store(pixels, for: key, quality: .analysis)
        return RegionMask(
            kind: kind, bounds: NormalizedRect(x: 0, y: 0, width: 1, height: 1),
            quality: .analysis, reference: reference, confidence: 1, coverage: pixels.coverage
        )
    }

    private func makeStrip(values: [UInt8], width: Int, height: Int) throws -> CGImage {
        let bytes = values.flatMap { value -> [UInt8] in [value, value, value, 255] }
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        guard
            let image = CGImage(
                width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
            )
        else { throw ImageError.processingFailed }
        return image
    }
}

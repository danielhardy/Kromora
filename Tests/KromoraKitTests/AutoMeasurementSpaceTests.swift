import CoreGraphics
import Foundation
import XCTest

@testable import KromoraKit

/// Real-render coverage for the fixed sRGB calibration used by photo analysis and Auto.
final class AutoMeasurementSpaceTests: TempDirectoryTestCase {
    func testFixedDocumentProducesEquivalentAutoInSRGBAndDisplayP3() async throws {
        let source = try makeSource()
        let engine = RenderEngine()
        let store = MaskStore(directory: tempDirectory)
        let maskPixels = try NormalizedMask(
            size: PixelDimensions(width: 96, height: 64),
            values: (0..<(96 * 64)).map { $0 % 96 < 48 ? 1 : 0.25 }
        )
        let reference = try await store.store(
            maskPixels,
            for: MaskCacheKey(
                identity: source.cacheIdentity, kind: .subject, quality: .analysis
            ), quality: .analysis
        )
        let mask = RegionMask(
            kind: .subject, bounds: NormalizedRect(x: 0, y: 0, width: 1, height: 1),
            quality: .analysis, reference: reference, confidence: 0.9,
            coverage: maskPixels.coverage
        )
        var document = EditDocument()
        document.light.exposure = -0.1
        let measurer = CurrentEditMeasurer(engine: engine, store: store)
        var measurements: [CurrentEditMeasurement] = []
        var proposals: [AutoEnhancementProposal] = []
        var appleReferences: [AppleReferenceResult] = []
        var results: [AutoEnhancementCoordinatorResult] = []
        for space in [WorkingSpace.sRGB, .displayP3] {
            let measurement = try await measurer.measure(
                source: source, document: document, expectedDocumentHash: document.editHash,
                configuration: CurrentEditMeasurementConfiguration(
                    maximumDimension: 96, space: space, nativePatchCount: 0
                ), masks: [mask]
            )
            XCTAssertEqual(measurement.space, .sRGB)
            XCTAssertEqual(measurement.regions.count, 1)
            let scene = SceneCharacteristicsAnalyzer.analyze(measurement: measurement)
            let confidence = AutoSignalConfidence.make(
                globalToneAvailable: true, color: SceneColorFacts.from(measurement.color),
                sceneConfidence: scene.sceneConfidence, regions: measurement.regions,
                primarySubject: PrimarySubjectSelector.select(from: measurement.regions),
                classifications: nil, detailAvailable: false, failedMaskCount: 0
            )
            let facts = AutoEnhancementFacts(
                measurement: measurement, scene: scene, signalConfidence: confidence
            )
            let native = AutoEnhancementPolicy.propose(
                facts: facts, current: document, sourceKind: .standard
            )
            let apple = await AppleEnhancementReferenceAdapter(engine: engine).referenceProposal(
                source: source, document: document, sourceKind: .standard,
                scene: scene, signalConfidence: confidence
            )
            let result = await AutoEnhancementCoordinator(
                engine: engine, configuration: AutoCoordinatorConfiguration(timeBudgetSeconds: 60)
            ).run(
                source: source, current: document, expectedDocumentHash: document.editHash,
                facts: facts, regions: measurement.regions, native: native,
                apple: apple.proposal, sourceKind: .standard
            )
            measurements.append(measurement)
            proposals.append(native)
            appleReferences.append(apple)
            results.append(result)
        }

        // The reference pixels are identical: use exact facts/proposals and a 1e-6 slider
        // tolerance for the final Auto output, well below any visible or stored slider step.
        XCTAssertEqual(measurements[0].globalTone, measurements[1].globalTone)
        XCTAssertEqual(measurements[0].color, measurements[1].color)
        XCTAssertEqual(measurements[0].regions, measurements[1].regions)
        XCTAssertEqual(measurements[0].localContrast, measurements[1].localContrast)
        XCTAssertEqual(proposals[0], proposals[1])
        XCTAssertEqual(appleReferences[0], appleReferences[1])
        XCTAssertFalse(proposals[0].isNoOp, "the fixture must exercise a real Auto correction")
        XCTAssertEqual(results[0].status, .improved, results[0].message)
        XCTAssertEqual(results[0].status, results[1].status)
        XCTAssertEqual(results[0].provenance, results[1].provenance)
        let srgbScore = try XCTUnwrap(results[0].selectedScore)
        let p3Score = try XCTUnwrap(results[1].selectedScore)
        XCTAssertEqual(srgbScore.total, p3Score.total, accuracy: 1e-6)
        XCTAssertEqual(srgbScore.movement, p3Score.movement, accuracy: 1e-6)
        XCTAssertEqual(results[0].document.light.exposure, results[1].document.light.exposure,
                       accuracy: 1e-6)
        XCTAssertEqual(results[0].document, results[1].document)

        // This colored fixture would expose accidentally measuring in the canvas encoding.
        let srgbSamples = await engine.renderedSamples(
            source: source, document: document, lut: nil, targetLongEdge: 96, space: .sRGB
        )
        let p3Samples = await engine.renderedSamples(
            source: source, document: document, lut: nil, targetLongEdge: 96, space: .displayP3
        )
        let srgb = try XCTUnwrap(srgbSamples)
        let p3 = try XCTUnwrap(p3Samples)
        XCTAssertNotEqual(srgb.bytes, p3.bytes)
    }

    func testSRGBSamplingAndMaskedHistogramPreserveLegacyBytes() async throws {
        let source = try makeSource()
        let engine = RenderEngine()
        let document = EditDocument()
        let rendered = await engine.makeCGImage(RenderRequest(
            source: source, document: document, lut: nil,
            targetSize: CGSize(width: 96, height: 64), quality: .preview,
            output: .raster, space: .sRGB
        ))
        let image = try XCTUnwrap(rendered)
        var legacyBytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let captured = legacyBytes.withUnsafeMutableBytes { storage -> Bool in
            guard let bitmap = CGContext(
                data: storage.baseAddress, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            bitmap.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        XCTAssertTrue(captured)
        let sampled = await engine.renderedSamples(
            source: source, document: document, lut: nil, targetLongEdge: 96, space: .sRGB
        )
        let samples = try XCTUnwrap(sampled)
        XCTAssertEqual(samples.bytes, legacyBytes, "sRGB behavior must remain byte-identical")
        let mask = try NormalizedMask(
            size: PixelDimensions(width: image.width, height: image.height),
            values: [Float](repeating: 0.5, count: image.width * image.height)
        )
        let histogram = await engine.maskedHistogram(
            source: source, document: document, lut: nil, scale: .full, space: .sRGB, mask: mask
        )
        XCTAssertEqual(histogram, WeightedHistogramData(
            rgba8: legacyBytes, width: image.width, height: image.height,
            bytesPerRow: image.width * 4, mask: mask
        ))
    }

    private func makeSource() throws -> ImageSource {
        let image = try Fixtures.makeParametricCGImage(width: 96, height: 64) { x, y in
            let level = 0.02 + 0.8 * pow((x + y) / 2, 2)
            return x < 0.5 ? (level, level, level * 0.98)
                : (level * 0.98, level, level)
        }
        // Author the fixture in P3 so input-profile conversion is exercised too.
        let p3Image = try XCTUnwrap(image.copy(colorSpace: WorkingSpace.displayP3.cgColorSpace))
        return ImageSource(
            data: try Fixtures.jpegData(for: p3Image), nativeExtent: CGSize(width: 96, height: 64)
        )
    }
}

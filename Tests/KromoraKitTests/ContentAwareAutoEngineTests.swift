import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest

@testable import KromoraKit

/// Production-path coverage for KRMA-355. These tests use the real RenderEngine for both global
/// candidate evaluation and post-global regional measurement; only semantic mask production is
/// deterministic fixture data so the test does not depend on Vision's model output.
final class ContentAwareAutoEngineTests: TempDirectoryTestCase {

    func testRegionalConflictAddsEditableAutoLayersThroughProductionPath() async throws {
        let sourceData = try splitToneJPEG()
        let source = ImageSource(data: sourceData, nativeExtent: CGSize(width: 64, height: 48))
        let assetID = PhotoAssetID.data(sourceData)
        let store = MaskStore(directory: tempDirectory.appendingPathComponent("masks"))
        let masks = try await makeRegionalMasks(sourceData: sourceData, store: store)
        let provider = FixtureRegionalMaskProvider(masks: masks)
        let engine = RenderEngine()
        let analysisCoordinator = PhotoAnalysisCoordinator(
            engine: engine,
            maskStore: store,
            cache: PhotoAnalysisCache(directory: tempDirectory.appendingPathComponent("analysis")),
            maskProvider: provider,
            stages: [
                .standard: [PhotoAnalysisStage(kind: .subject, quality: .analysis)]
            ]
        )
        defer { Task { await analysisCoordinator.shutdown() } }

        let result = await ContentAwareAutoEngine(
            engine: engine,
            analysisCoordinator: analysisCoordinator,
            maskStore: store
        ).run(source: source, assetID: assetID, current: EditDocument())

        XCTAssertEqual(result.status, .improved)
        let autoLayers = result.proposedDocument.localAdjustments.filter(\.isAutoOwned)
        XCTAssertFalse(autoLayers.isEmpty, result.reasons.joined(separator: " "))
        XCTAssertLessThanOrEqual(autoLayers.count, AutoRegionalPurpose.maximumLayers)
        XCTAssertTrue(autoLayers.contains { $0.name == "Auto — Subject" })

        let userLayer = LocalAdjustmentLayer(name: "Photographer layer")
        let withUserLayer = EditDocument(localAdjustments: [userLayer])
        let firstApplied = result.applying(to: withUserLayer)
        XCTAssertEqual(firstApplied.localAdjustments.first, userLayer)
        XCTAssertLessThanOrEqual(
            firstApplied.localAdjustments.filter(\.isAutoOwned).count,
            AutoRegionalPurpose.maximumLayers
        )

        // A second Auto application reconciles by stable purpose identity instead of stacking a
        // second set of generated recipes, while the user-owned layer remains byte-for-byte.
        let secondApplied = result.applying(to: firstApplied)
        XCTAssertEqual(secondApplied.localAdjustments.count, firstApplied.localAdjustments.count)
        XCTAssertEqual(secondApplied.localAdjustments.first, userLayer)

        let repeated = await ContentAwareAutoEngine(
            engine: engine,
            analysisCoordinator: analysisCoordinator,
            maskStore: store
        ).run(source: source, assetID: assetID, current: firstApplied)
        XCTAssertEqual(
            repeated.proposedDocument.localAdjustments.count,
            firstApplied.localAdjustments.count
        )
    }

    func testNoMasksKeepBalancedDocumentUnchangedWithRegionalReasons() async throws {
        let sourceData = try solidJPEG(red: 0.48, green: 0.48, blue: 0.48)
        let source = ImageSource(data: sourceData, nativeExtent: CGSize(width: 32, height: 24))
        let assetID = PhotoAssetID.data(sourceData)
        let store = MaskStore(directory: tempDirectory.appendingPathComponent("masks"))
        let engine = RenderEngine()
        let analysisCoordinator = PhotoAnalysisCoordinator(
            engine: engine,
            maskStore: store,
            cache: PhotoAnalysisCache(directory: tempDirectory.appendingPathComponent("analysis")),
            maskProvider: FixtureRegionalMaskProvider(masks: [:]),
            stages: [:]
        )
        defer { Task { await analysisCoordinator.shutdown() } }

        let current = EditDocument()
        let result = await ContentAwareAutoEngine(
            engine: engine,
            analysisCoordinator: analysisCoordinator,
            maskStore: store
        ).run(source: source, assetID: assetID, current: current)

        XCTAssertEqual(result.status, .unchanged)
        XCTAssertEqual(result.proposedDocument, current)
        XCTAssertTrue(result.proposedDocument.localAdjustments.isEmpty)
        XCTAssertTrue(result.reasons.contains { $0.contains("no subject evidence") })
        XCTAssertTrue(result.reasons.contains { $0.contains("no background evidence") })
        XCTAssertTrue(result.reasons.contains { $0.contains("no material regional cast") })
    }

    func testUnderexposedFrameSelectsMeaningfulExposureThroughProductionRenderer() async throws {
        let sourceData = try Fixtures.jpegData(
            for: Fixtures.makeParametricCGImage(width: 96, height: 64) { nx, ny in
                let value = 0.04 + 0.56 * ((nx + ny) / 2)
                return (value, value, value * 0.98)
            }
        )
        let source = ImageSource(data: sourceData, nativeExtent: CGSize(width: 96, height: 64))
        let assetID = PhotoAssetID.data(sourceData)
        let store = MaskStore(directory: tempDirectory.appendingPathComponent("masks-underexposed"))
        let engine = RenderEngine()
        let analysisCoordinator = PhotoAnalysisCoordinator(
            engine: engine,
            maskStore: store,
            cache: PhotoAnalysisCache(
                directory: tempDirectory.appendingPathComponent("analysis-underexposed")
            ),
            maskProvider: FixtureRegionalMaskProvider(masks: [:]),
            stages: [:]
        )
        defer { Task { await analysisCoordinator.shutdown() } }

        let result = await ContentAwareAutoEngine(
            engine: engine,
            analysisCoordinator: analysisCoordinator,
            maskStore: store
        ).run(source: source, assetID: assetID, current: EditDocument())

        XCTAssertEqual(result.status, .improved, result.reasons.joined(separator: " "))
        XCTAssertGreaterThan(
            result.proposedDocument.light.exposure, 0.45,
            "a materially dark developed render must not collapse to a near-no-op"
        )
        XCTAssertTrue(result.changedControls.contains(.exposure))
        XCTAssertTrue(result.proposedDocument.localAdjustments.isEmpty)
    }

    func testAutoReplacesExistingGlobalValuesWhilePreservingUnrelatedEdits() async throws {
        let sourceData = try Fixtures.jpegData(
            for: Fixtures.makeParametricCGImage(width: 96, height: 64) { nx, ny in
                let value = 0.04 + 0.56 * ((nx + ny) / 2)
                return (value, value, value * 0.98)
            }
        )
        let source = ImageSource(data: sourceData, nativeExtent: CGSize(width: 96, height: 64))
        let assetID = PhotoAssetID.data(sourceData)
        let store = MaskStore(directory: tempDirectory.appendingPathComponent("masks-replace"))
        let engine = RenderEngine()
        let analysisCoordinator = PhotoAnalysisCoordinator(
            engine: engine,
            maskStore: store,
            cache: PhotoAnalysisCache(
                directory: tempDirectory.appendingPathComponent("analysis-replace")
            ),
            maskProvider: FixtureRegionalMaskProvider(masks: [:]),
            stages: [:]
        )
        defer { Task { await analysisCoordinator.shutdown() } }

        var edited = EditDocument()
        edited.light.exposure = 4
        edited.color.saturation = 40
        let mask = LocalAdjustmentLayer(name: "Photographer mask")
        edited.localAdjustments = [mask]

        let result = await ContentAwareAutoEngine(
            engine: engine,
            analysisCoordinator: analysisCoordinator,
            maskStore: store
        ).run(source: source, assetID: assetID, current: edited)

        XCTAssertEqual(result.status, .improved, result.reasons.joined(separator: " "))
        let applied = result.applying(to: edited)
        XCTAssertNotEqual(applied.light.exposure, edited.light.exposure)
        XCTAssertNotEqual(applied.color.saturation, edited.color.saturation)
        XCTAssertEqual(applied.crop, edited.crop)
        XCTAssertEqual(applied.rotation, edited.rotation)
        XCTAssertEqual(applied.localAdjustments, edited.localAdjustments)
    }

    private static let maskSize = PixelDimensions(width: 64, height: 48)

    private func makeRegionalMasks(
        sourceData: Data, store: MaskStore
    ) async throws -> [SemanticMaskKind: RegionMask] {
        let subjectPixels = try softDisc(center: (0.28, 0.5), radius: 0.4)
        let foregroundKey = MaskCacheKey(
            assetID: .data(sourceData), sourceFingerprint: .data(sourceData),
            kind: .foreground, quality: .analysis
        )
        let subjectKey = foregroundKey.with(kind: .subject)
        let foregroundReference = try await store.store(
            subjectPixels, for: foregroundKey, quality: .analysis
        )
        let subjectReference = try await store.store(
            subjectPixels, for: subjectKey, quality: .analysis
        )
        let subject = RegionMask(
            kind: .subject,
            bounds: NormalizedRect(x: 0.02, y: 0.2, width: 0.52, height: 0.6),
            quality: .analysis, reference: subjectReference, confidence: 0.95,
            coverage: subjectPixels.coverage
        )
        let foreground = RegionMask(
            kind: .foreground,
            bounds: subject.bounds,
            quality: .analysis, reference: foregroundReference, confidence: 0.95,
            coverage: subjectPixels.coverage
        )
        return [.subject: subject, .foreground: foreground]
    }

    private func softDisc(
        center: (Double, Double), radius: Double
    ) throws -> NormalizedMask {
        var values = [Float](repeating: 0, count: Self.maskSize.width * Self.maskSize.height)
        for y in 0..<Self.maskSize.height {
            for x in 0..<Self.maskSize.width {
                let nx = (Double(x) + 0.5) / Double(Self.maskSize.width)
                let ny = (Double(y) + 0.5) / Double(Self.maskSize.height)
                let distance = hypot(nx - center.0, ny - center.1)
                values[y * Self.maskSize.width + x] = Float(min(max(1 - distance / radius, 0), 1))
            }
        }
        return try NormalizedMask(size: Self.maskSize, values: values)
    }

    private func splitToneJPEG() throws -> Data {
        let width = Self.maskSize.width
        let height = Self.maskSize.height
        guard
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else { throw Fixtures.FixtureError.cannotCreateContext }
        context.setFillColor(red: 0.12, green: 0.12, blue: 0.12, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
        context.setFillColor(red: 0.92, green: 0.92, blue: 0.92, alpha: 1)
        context.fill(CGRect(x: width / 2, y: 0, width: width / 2, height: height))
        return try encodeJPEG(context.makeImage())
    }

    private func solidJPEG(red: CGFloat, green: CGFloat, blue: CGFloat) throws -> Data {
        guard
            let context = CGContext(
                data: nil, width: 32, height: 24, bitsPerComponent: 8,
                bytesPerRow: 32 * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else { throw Fixtures.FixtureError.cannotCreateContext }
        context.setFillColor(red: red, green: green, blue: blue, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 32, height: 24))
        return try encodeJPEG(context.makeImage())
    }

    private func encodeJPEG(_ image: CGImage?) throws -> Data {
        guard let image else { throw Fixtures.FixtureError.cannotCreateContext }
        let data = NSMutableData()
        guard
            let destination = CGImageDestinationCreateWithData(
                data, UTType.jpeg.identifier as CFString, 1, nil
            )
        else { throw Fixtures.FixtureError.cannotCreateDestination }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw Fixtures.FixtureError.cannotCreateDestination
        }
        return data as Data
    }
}

private actor FixtureRegionalMaskProvider: SemanticMaskProviding {
    private let masks: [SemanticMaskKind: RegionMask]

    init(masks: [SemanticMaskKind: RegionMask]) {
        self.masks = masks
    }

    func mask(
        for kind: SemanticMaskKind, image: AnalysisImage, quality: MaskQuality
    ) async throws -> RegionMask {
        guard let mask = masks[kind] else { throw RegionMaskError.missingPixels }
        return mask
    }
}

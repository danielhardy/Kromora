import CoreGraphics
import Foundation
import XCTest

@testable import LumoKit

final class MaskRefinementTests: XCTestCase {
    func testRefinementUpsamplesSeedIntoRenderQualityAndPersistsIt() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LumoMaskRefine-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = MaskStore(directory: directory)
        let sourceData = Data("refinement".utf8)
        let key = MaskCacheKey(
            assetID: PhotoAssetID.data(sourceData),
            sourceFingerprint: PhotoSourceFingerprint.data(sourceData),
            kind: .subject,
            quality: .preview,
            providerVersion: "test"
        )
        let seedPixels = try NormalizedMask(
            size: PixelDimensions(width: 2, height: 2), values: [1, 1, 0, 0]
        )
        let reference = try await store.store(seedPixels, for: key, quality: .preview)
        let seed = RegionMask(
            kind: .subject,
            bounds: NormalizedRect(x: 0, y: 0, width: 1, height: 0.5),
            quality: .preview,
            reference: reference,
            confidence: 0.9,
            coverage: seedPixels.coverage
        )
        let service = MaskRefinementService(store: store)
        let source = ImageSource(
            backing: .data(sourceData), kind: .standard,
            nativeExtent: CGSize(width: 8, height: 8)
        )

        let refined = try await service.refine(mask: seed, source: source, tileSize: 2)
        let pixels = await store.pixels(for: refined.reference)

        XCTAssertEqual(refined.quality, .render)
        XCTAssertEqual(refined.reference.quality, .render)
        XCTAssertEqual(refined.reference.cacheKey.quality, .render)
        XCTAssertEqual(pixels?.size, PixelDimensions(width: 8, height: 8))
        XCTAssertEqual(pixels?.values.first, 1)
        XCTAssertEqual(pixels?.values.last, 0)
        XCTAssertEqual(refined.confidence, seed.confidence)
    }

    func testCancellationDoesNotPersistAnIncompleteRenderMask() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LumoMaskCancel-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = MaskStore(directory: directory)
        let data = Data("cancellation".utf8)
        let key = MaskCacheKey(
            assetID: PhotoAssetID.data(data),
            sourceFingerprint: PhotoSourceFingerprint.data(data),
            kind: .subject,
            quality: .preview,
            providerVersion: "cancel-test"
        )
        let seedPixels = try NormalizedMask(
            size: PixelDimensions(width: 2, height: 2), values: [1, 1, 1, 1]
        )
        let reference = try await store.store(seedPixels, for: key, quality: .preview)
        let seed = RegionMask(
            kind: .subject,
            bounds: NormalizedRect(x: 0, y: 0, width: 1, height: 1),
            quality: .preview,
            reference: reference,
            confidence: 1,
            coverage: 1
        )
        let service = MaskRefinementService(store: store)
        let source = ImageSource(
            backing: .data(data), kind: .standard,
            nativeExtent: CGSize(width: 2048, height: 2048)
        )
        let task = Task {
            try await service.refine(mask: seed, source: source, tileSize: 1)
        }
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("cancelled refinement should not finish")
        } catch is CancellationError {
            // Expected.
        }

        let renderKey = key.with(quality: .render)
        let persisted = await store.mask(for: renderKey, quality: .render)
        XCTAssertNil(persisted)
    }
}

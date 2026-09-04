import Foundation
import XCTest

@testable import LumoKit

final class RegionMaskTests: XCTestCase {
    func testSemanticKindsAndQualityRoundTrip() throws {
        let kinds: [SemanticMaskKind] = [.subject, .background, .person, .face, .faceInstance(1), .foregroundInstance(2), .unknown("sky")]
        for kind in kinds {
            let data = try JSONEncoder().encode(kind)
            XCTAssertEqual(try JSONDecoder().decode(SemanticMaskKind.self, from: data), kind)
        }

        XCTAssertLessThan(MaskQuality.analysis, .preview)
        XCTAssertLessThan(MaskQuality.preview, .render)
    }

    func testRegionMaskCarriesReferenceInsteadOfPixels() throws {
        let source = PhotoSourceFingerprint.data(Data([1, 2, 3]))
        let asset = PhotoAssetID.data(Data([1, 2, 3]))
        let key = MaskCacheKey(
            assetID: asset, sourceFingerprint: source,
            kind: .subject, quality: .analysis, providerVersion: "vision-1"
        )
        let reference = RegionMaskReference(
            cacheKey: key, size: PixelDimensions(width: 8, height: 4)
        )
        let mask = RegionMask(
            kind: .subject, bounds: NormalizedRect(x: 0.1, y: 0.2, width: 0.5, height: 0.6),
            quality: .analysis, reference: reference, confidence: 0.9, coverage: 0.3
        )

        let data = try JSONEncoder().encode(mask)
        XCTAssertEqual(try JSONDecoder().decode(RegionMask.self, from: data), mask)
        XCTAssertEqual(reference.cacheKey.quality, .analysis)
    }

    func testNormalizedMaskValidatesPixelPayload() throws {
        let size = PixelDimensions(width: 2, height: 2)
        let mask = try NormalizedMask(size: size, values: [0, 0.5, 1, 2])
        XCTAssertEqual(mask.values, [0, 0.5, 1, 1])
        XCTAssertEqual(mask.coverage, 0.625, accuracy: 0.0001)
        XCTAssertThrowsError(try NormalizedMask(size: size, values: [0, 1]))
    }

    func testMaskStoreKeepsQualityLevelsIndependentAcrossReopen() async throws {
        let directory = try Fixtures.makeTempDirectory("MaskStoreTests")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = MaskStore(directory: directory)
        let key = MaskCacheKey(
            assetID: .data(Data([4, 5, 6])), sourceFingerprint: .data(Data([4, 5, 6])),
            kind: .subject, providerVersion: "vision-1"
        )
        let pixels = try NormalizedMask(size: PixelDimensions(width: 2, height: 2), values: [0, 1, 0.5, 0.25])

        let analysis = try await store.store(pixels, for: key, quality: .analysis)
        let renderReference = await store.mask(for: key, quality: .render)
        let storedPixels = await store.pixels(for: analysis)
        XCTAssertNil(renderReference)
        XCTAssertEqual(storedPixels, pixels)

        let reopened = MaskStore(directory: directory)
        let reopenedPixels = await reopened.pixels(for: analysis)
        XCTAssertEqual(reopenedPixels, pixels)
    }

    func testMaskOperationsComposeAndRejectDifferentSizes() throws {
        let size = PixelDimensions(width: 2, height: 2)
        let left = try NormalizedMask(size: size, values: [1, 1, 0, 0])
        let right = try NormalizedMask(size: size, values: [1, 0, 1, 0])

        XCTAssertEqual(try MaskOperations.intersect(left, right).values, [1, 0, 0, 0])
        XCTAssertEqual(try MaskOperations.union(left, right).values, [1, 1, 1, 0])
        XCTAssertEqual(try MaskOperations.subtract(right, from: left).values, [0, 1, 0, 0])
        XCTAssertEqual(try MaskOperations.invert(left).values, [0, 0, 1, 1])
        XCTAssertThrowsError(try MaskOperations.intersect(
            left, try NormalizedMask(size: PixelDimensions(width: 1, height: 1), values: [1])
        ))
    }
}

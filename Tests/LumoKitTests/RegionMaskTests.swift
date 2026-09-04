import Foundation
import XCTest

@testable import LumoKit

final class RegionMaskTests: XCTestCase {
    func testSemanticKindsAndQualityRoundTrip() throws {
        let kinds: [SemanticMaskKind] = [.subject, .background, .person, .face, .foregroundInstance(2), .unknown("sky")]
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
}

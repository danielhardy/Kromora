import CoreGraphics
import Foundation
import XCTest
@testable import KromoraKit

final class RetouchModelTests: XCTestCase {
    func testSettingsRoundTripAndIdentitySemantics() throws {
        let spot = RetouchSpot(
            mode: .clone,
            region: RetouchRegion(samples: [
                BrushSample(point: CGPoint(x: 0.2, y: 0.3), pressure: 0.6),
                BrushSample(point: CGPoint(x: 0.4, y: 0.5)),
            ], radius: 0.04),
            source: .manual(offset: CGVector(dx: 0.2, dy: -0.1)), seed: 17
        )
        let eye = EyeCorrection(kind: .pet, center: CGPoint(x: 0.6, y: 0.4), addCatchlight: true)
        let settings = RetouchSettings(spots: [spot], eyes: [eye])
        let data = try JSONEncoder().encode(settings)
        XCTAssertEqual(try JSONDecoder().decode(RetouchSettings.self, from: data), settings)
        XCTAssertFalse(settings.isIdentity)
        XCTAssertTrue(RetouchSettings(spots: [RetouchSpot(opacity: 0)], eyes: [EyeCorrection(isVisible: false)]).isIdentity)
        XCTAssertTrue(RetouchSettings(spots: [RetouchSpot(region: RetouchRegion(samples: []))]).isIdentity)
        XCTAssertTrue(RetouchSettings(eyes: [EyeCorrection(darken: 0)]).isIdentity)
    }

    func testLegacyRemoveSpotsMigrateToHealWhenDecoded() throws {
        let legacy = Data(#"{"spots":[{"id":"00000000-0000-0000-0000-000000000001","mode":"remove","region":{"samples":[{"point":[0.4,0.6]}],"radius":0.03},"seed":7}]}"#.utf8)
        let settings = try JSONDecoder().decode(RetouchSettings.self, from: legacy)
        let spot = try XCTUnwrap(settings.spots.first)
        XCTAssertEqual(spot.mode, .heal)
        XCTAssertEqual(spot.region.radius, 0.03)
        XCTAssertEqual(spot.seed, 7)
        let migrated = try JSONEncoder().encode(settings)
        XCTAssertTrue(String(decoding: migrated, as: UTF8.self).contains("\"mode\":\"heal\""))
        XCTAssertFalse(String(decoding: migrated, as: UTF8.self).contains("remove"))
    }

    func testNewRetouchSpotsDefaultToHeal() {
        XCTAssertEqual(RetouchSpot().mode, .heal)
    }

    func testLegacyDocumentDefaultsRetouchAndNewerVersionIsRejected() throws {
        let legacy = Data(#"{"version":6,"light":{},"color":{},"effects":{},"crop":{},"rotation":0,"adjustments":[],"lut":{},"localAdjustments":[]}"#.utf8)
        let decoded = try JSONDecoder().decode(EditDocument.self, from: legacy)
        XCTAssertEqual(decoded.version, 7)
        XCTAssertEqual(decoded.retouch, .neutral)

        let future = Data(#"{"version":8}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(EditDocument.self, from: future))
    }

    func testNewRecipeDecodeIsTolerantAndIgnoresV1SpotFields() throws {
        let data = Data(#"{"spots":[{"id":"00000000-0000-0000-0000-000000000001","mode":"heal","shape":{"kind":"circle","center":[8,-4]},"radius":9,"sourceOffset":[9,-9],"feather":-2,"opacity":2,"region":{"samples":[{"point":[0.3,0.4],"pressure":0.5}],"radius":0.08},"source":{"kind":"manual","offset":[0.1,-0.2]}}]}"#.utf8)
        let value = try JSONDecoder().decode(RetouchSettings.self, from: data)
        let spot = try XCTUnwrap(value.spots.first)
        XCTAssertEqual(spot.region.radius, 0.08)
        XCTAssertEqual(spot.region.samples.first?.point, CGPoint(x: 0.3, y: 0.4))
        XCTAssertEqual(spot.source, .manual(offset: CGVector(dx: 0.1, dy: -0.2)))
        XCTAssertEqual(spot.feather, 0)
        XCTAssertEqual(spot.opacity, 1)

        let v1Only = Data(#"{"spots":[{"shape":{"kind":"circle","center":[0.9,0.8]},"radius":0.2,"sourceOffset":[0.1,0.1]}]}"#.utf8)
        let decodedV1 = try JSONDecoder().decode(RetouchSettings.self, from: v1Only)
        XCTAssertEqual(decodedV1.spots.first?.region.samples.first?.point, CGPoint(x: 0.5, y: 0.5))
        XCTAssertEqual(decodedV1.spots.first?.region.radius, 0.02)
    }

    func testSpotWorkBoundsStayLocalAtLargeSourceSizes() {
        let spot = RetouchSpot(
            mode: .heal,
            region: RetouchRegion(samples: [BrushSample(point: CGPoint(x: 0.5, y: 0.5))], radius: 0.01),
            source: .manual(offset: CGVector(dx: 0.1, dy: 0))
        )
        let bounds = RetouchRenderer.workBounds(for: spot, extent: CGRect(x: 0, y: 0, width: 6000, height: 4000))
        XCTAssertLessThan(bounds.width * bounds.height, 300_000)
        XCTAssertLessThan(bounds.width * bounds.height, 0.02 * 6000 * 4000)
    }

    func testSpotWorkBoundsStayConstantForTheSamePixelRadiusAtHigherResolution() {
        func bounds(width: CGFloat, height: CGFloat, radiusPixels: CGFloat) -> CGRect {
            let spot = RetouchSpot(
                mode: .heal,
                region: RetouchRegion(
                    samples: [BrushSample(point: CGPoint(x: 0.5, y: 0.5))],
                    radius: Double(radiusPixels / min(width, height))
                ),
                source: .manual(offset: CGVector(dx: 0.1, dy: 0))
            )
            return RetouchRenderer.workBounds(for: spot, extent: CGRect(x: 0, y: 0, width: width, height: height))
        }

        let standardResolution = bounds(width: 4000, height: 3000, radiusPixels: 60)
        let doubleResolution = bounds(width: 8000, height: 6000, radiusPixels: 60)
        XCTAssertEqual(doubleResolution.size, standardResolution.size,
                       "a fixed pixel-radius spot should keep the same heal work-window size as source resolution grows")
    }

    func testRetouchAffectsIdentityButComparisonRemovesItAndAutoKeepsIt() {
        let spot = RetouchSpot()
        var document = EditDocument(retouch: RetouchSettings(spots: [spot]))
        XCTAssertFalse(document.isIdentity)
        XCTAssertTrue(document.originalForComparison.retouch.isIdentity)
        XCTAssertEqual(document.autoAdjustmentBaseline.retouch, document.retouch)
        document.retouch = .neutral
        XCTAssertTrue(document.isIdentity)
    }
}

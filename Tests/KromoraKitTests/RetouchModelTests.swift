import CoreGraphics
import Foundation
import XCTest
@testable import KromoraKit

final class RetouchModelTests: XCTestCase {
    func testSettingsRoundTripAndIdentitySemantics() throws {
        let spot = RetouchSpot(
            mode: .clone, shape: .stroke(points: [CGPoint(x: 0.2, y: 0.3), CGPoint(x: 0.4, y: 0.5)]),
            radius: 0.04, sourceOffset: CGVector(dx: 0.2, dy: -0.1)
        )
        let eye = EyeCorrection(kind: .pet, center: CGPoint(x: 0.6, y: 0.4), addCatchlight: true)
        let settings = RetouchSettings(spots: [spot], eyes: [eye])
        let data = try JSONEncoder().encode(settings)
        XCTAssertEqual(try JSONDecoder().decode(RetouchSettings.self, from: data), settings)
        XCTAssertFalse(settings.isIdentity)
        XCTAssertTrue(RetouchSettings(spots: [RetouchSpot(opacity: 0)], eyes: [EyeCorrection(isVisible: false)]).isIdentity)
        XCTAssertTrue(RetouchSettings(spots: [RetouchSpot(shape: .stroke(points: []))]).isIdentity)
        XCTAssertTrue(RetouchSettings(eyes: [EyeCorrection(darken: 0)]).isIdentity)
    }

    func testLegacyDocumentDefaultsRetouchAndNewerVersionIsRejected() throws {
        let legacy = Data(#"{"version":6,"light":{},"color":{},"effects":{},"crop":{},"rotation":0,"adjustments":[],"lut":{},"localAdjustments":[]}"#.utf8)
        let decoded = try JSONDecoder().decode(EditDocument.self, from: legacy)
        XCTAssertEqual(decoded.version, 7)
        XCTAssertEqual(decoded.retouch, .neutral)

        let future = Data(#"{"version":8}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(EditDocument.self, from: future))
    }

    func testRetouchClampsMalformedFiniteValues() throws {
        let data = Data(#"{"spots":[{"id":"00000000-0000-0000-0000-000000000001","mode":"heal","shape":{"kind":"circle","center":[8,-4]},"radius":9,"sourceOffset":[9,-9],"feather":-2,"opacity":2}],"eyes":[{"kind":"human","center":[2,-1],"radiusX":0,"radiusY":4,"pupilSize":200,"darken":-1}]}"#.utf8)
        let value = try JSONDecoder().decode(RetouchSettings.self, from: data)
        let spot = try XCTUnwrap(value.spots.first)
        XCTAssertEqual(spot.radius, 0.25)
        XCTAssertEqual(spot.feather, 0)
        XCTAssertEqual(spot.opacity, 1)
        guard case .circle(let center) = spot.shape else { return XCTFail("Expected circle") }
        XCTAssertEqual(center, CGPoint(x: 1.25, y: -0.25))
        let eye = try XCTUnwrap(value.eyes.first)
        XCTAssertEqual(eye.radiusX, 0.001)
        XCTAssertEqual(eye.radiusY, 0.1)
        XCTAssertEqual(eye.pupilSize, 100)
        XCTAssertEqual(eye.darken, 0)
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

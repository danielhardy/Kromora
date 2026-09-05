import XCTest
import CoreGraphics
@testable import LumoKit

final class LocalMaskTests: XCTestCase {
    private func roundTrip<T: Codable & Equatable>(_ value: T) throws -> T {
        try JSONDecoder().decode(T.self, from: JSONEncoder().encode(value))
    }

    func testCompleteRecipeRoundTripsAndUsesNormalizedGeometry() throws {
        let stroke = BrushStroke(
            samples: [BrushSample(point: CGPoint(x: 2, y: -1), pressure: 2)],
            radius: 0.2, feather: 0.3, flow: 0.8, density: 0.9
        )
        let layer = LocalAdjustmentLayer(
            name: "Sky", amount: 0.75,
            components: [
                MaskComponent(source: .brush(BrushMaskDefinition(strokes: [stroke]))),
                MaskComponent(mode: .intersect, source: .linear(LinearGradientDefinition()))
            ],
            adjustments: LocalAdjustments(exposure: 1.25, temperature: 9000)
        )
        XCTAssertEqual(try roundTrip(layer), layer)
        let sample = try XCTUnwrap(layer.components.first?.source.brushDefinition?.strokes.first?.samples.first)
        XCTAssertEqual(sample.point, CGPoint(x: 1, y: 0))
        XCTAssertEqual(sample.pressure, 1)
    }

    func testNeutralAndDisabledLayersAreIdentity() {
        let source = MaskComponent(source: .radial(RadialGradientDefinition()))
        XCTAssertTrue(LocalAdjustmentLayer(components: [source]).isIdentity)
        XCTAssertTrue(LocalAdjustmentLayer(isEnabled: false, components: [source], adjustments: LocalAdjustments(exposure: 1)).isIdentity)
        XCTAssertFalse(LocalAdjustmentLayer(components: [source], adjustments: LocalAdjustments(exposure: 1)).isIdentity)
    }

    func testCompositionIsBoundedAndDeterministic() {
        XCTAssertEqual(MaskCombineMode.add.combining(current: 0.4, next: 0.8), 0.8)
        XCTAssertEqual(MaskCombineMode.subtract.combining(current: 0.8, next: 0.25), 0.6, accuracy: 0.000_001)
        XCTAssertEqual(MaskCombineMode.intersect.combining(current: 0.4, next: 0.8), 0.4)
        XCTAssertEqual(MaskCombineMode.replace.combining(current: 0.4, next: 4), 1)
    }

    func testV1DocumentMigratesToV2WithEmptyLocalState() throws {
        let decoded = try JSONDecoder().decode(EditDocument.self, from: Data("{\"version\":1}".utf8))
        XCTAssertEqual(decoded.version, EditDocument.currentVersion)
        XCTAssertTrue(decoded.localAdjustments.isEmpty)
        XCTAssertTrue(decoded.isIdentity)
    }
}

@MainActor
final class MaskInteractionStateTests: XCTestCase {
    func testDraftCommitAndCancelDoNotRequireDocumentState() {
        let state = MaskInteractionState()
        let layer = LocalAdjustmentLayer(name: "Draft")
        state.beginDraft(layer)
        XCTAssertEqual(state.draftLayer, layer)
        XCTAssertEqual(state.commitDraft(), layer)
        XCTAssertFalse(state.hasDraft)
        state.beginDraft(layer)
        state.cancelDraft()
        XCTAssertFalse(state.hasDraft)
    }
}

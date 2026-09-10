import XCTest
import CoreGraphics
@testable import KromoraKit

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

    func testMaskCompositionIsOrderedAndStableForDisabledAndEmptyComponents() {
        let first = 0.8
        let add = MaskCombineMode.add.combining(current: first, next: 0.3)
        let subtract = MaskCombineMode.subtract.combining(current: add, next: 0.25)
        let intersect = MaskCombineMode.intersect.combining(current: subtract, next: 0.9)
        XCTAssertEqual(add, 0.8, accuracy: 0.000_001)
        XCTAssertEqual(subtract, 0.6, accuracy: 0.000_001)
        XCTAssertEqual(intersect, 0.6, accuracy: 0.000_001)

        let empty = MaskComponent(isEnabled: false, source: .brush(BrushMaskDefinition()))
        XCTAssertFalse(empty.isUsable)
        XCTAssertEqual(MaskComposition.inverted(intersect), 0.4, accuracy: 0.000_001)
        XCTAssertEqual(
            MaskComposition.inverted(MaskComposition.inverted(intersect)), intersect,
            accuracy: 0.000_001)
    }

    func testMaskComponentNameAndOperationRoundTripWithLegacyPayload() throws {
        let component = MaskComponent(
            name: "Sky Brush", mode: .subtract, isInverted: true,
            source: .brush(BrushMaskDefinition()))
        XCTAssertEqual(try roundTrip(component), component)

        var legacyComponent = component
        legacyComponent.mode = .add
        legacyComponent.name = ""
        var legacyObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(legacyComponent)) as? [String: Any])
        legacyObject.removeValue(forKey: "name")
        let decoded = try JSONDecoder().decode(
            MaskComponent.self,
            from: try JSONSerialization.data(withJSONObject: legacyObject))
        XCTAssertEqual(decoded.name, "")
        XCTAssertEqual(decoded.mode, .add)
    }

    func testComponentOperationAndNameParticipateInDocumentHash() {
        let id = UUID()
        let source = MaskSource.linear(LinearGradientDefinition())
        let base = EditDocument(localAdjustments: [LocalAdjustmentLayer(
            components: [MaskComponent(id: id, source: source)]
        )])
        var operationChanged = base
        operationChanged.localAdjustments[0].components[0].mode = .subtract
        var nameChanged = base
        nameChanged.localAdjustments[0].components[0].name = "Sky"

        XCTAssertNotEqual(base.editHash, operationChanged.editHash)
        XCTAssertNotEqual(base.editHash, nameChanged.editHash)
    }

    func testBrushMathUsesMousePressureAndSmoothRepeatedStampAccumulation() {
        XCTAssertEqual(BrushMaskMath.normalizedPressure(nil), 1)
        XCTAssertEqual(BrushMaskMath.normalizedPressure(2), 1)
        XCTAssertEqual(
            BrushMaskMath.stampAlpha(
                distance: 0, radius: 0.1, feather: 0.5, flow: 0.4, pressure: nil),
            0.4, accuracy: 0.000_001)
        let first = BrushMaskMath.accumulatedOpacity(current: 0, stamp: 0.4, density: 0.7)
        let second = BrushMaskMath.accumulatedOpacity(current: first, stamp: 0.4, density: 0.7)
        XCTAssertEqual(first, 0.4, accuracy: 0.000_001)
        XCTAssertEqual(second, 0.64, accuracy: 0.000_001)
        XCTAssertLessThanOrEqual(second, 0.7)
        XCTAssertEqual(
            BrushMaskMath.stampAlpha(
                distance: 0.1, radius: 0.1, feather: 0.5, flow: 1, pressure: nil), 0)
    }

    func testBrushResamplingIsDistanceBasedAndBoundedForLongGestures() {
        let samples = (0..<30_000).map { index in
            BrushSample(point: CGPoint(
                x: min(Double(index) / 30_000, 1),
                y: 0.5 + sin(Double(index) * 0.02) * 0.001
            ))
        }
        let compact = BrushMaskMath.resampledAndSimplified(
            samples, sourceSize: CGSize(width: 6_000, height: 4_000), radius: 0.04)
        XCTAssertLessThanOrEqual(compact.count, 4_096)
        XCTAssertEqual(compact.first?.point, samples.first?.point)
        XCTAssertEqual(compact.last?.point, samples.last?.point)
        XCTAssertLessThan(compact.count, samples.count)
    }

    func testBrushResamplingFillsSparseNativeEventSegmentsWithoutChangingEndpoints() {
        let sourceSize = CGSize(width: 1_000, height: 1_000)
        let samples = [
            BrushSample(point: CGPoint(x: 0.1, y: 0.5), pressure: 0.2),
            BrushSample(point: CGPoint(x: 0.9, y: 0.5), pressure: 0.8),
        ]
        let radius = 0.02
        let result = BrushMaskMath.resampledAndSimplified(
            samples, sourceSize: sourceSize, radius: radius)
        let spacing = BrushMaskMath.samplingSpacing(sourceSize: sourceSize, radius: radius)

        XCTAssertEqual(result.first?.point, samples.first?.point)
        XCTAssertEqual(result.last?.point, samples.last?.point)
        XCTAssertGreaterThan(result.count, 2)
        for (lhs, rhs) in zip(result, result.dropFirst()) {
            XCTAssertLessThanOrEqual(
                BrushMaskMath.physicalDistance(lhs.point, rhs.point, sourceSize: sourceSize),
                spacing + 0.000_001,
                "every stamped segment must remain within the gap-free spacing budget")
        }
    }

    func testLinearGradientMathUsesEndpointsForAngleFalloffAndSmoothAlpha() {
        let definition = LinearGradientDefinition(
            zeroStrengthPoint: CGPoint(x: 0.2, y: 0.5),
            fullStrengthPoint: CGPoint(x: 0.8, y: 0.5), density: 0.75)

        XCTAssertEqual(definition.angle, 0, accuracy: 0.000_001)
        XCTAssertEqual(definition.angleDegrees, 0, accuracy: 0.000_001)
        XCTAssertEqual(definition.falloff, 0.6, accuracy: 0.000_001)
        XCTAssertEqual(LinearGradientMaskMath.alpha(at: CGPoint(x: 0.2, y: 0.5), definition: definition), 0)
        XCTAssertEqual(LinearGradientMaskMath.alpha(at: CGPoint(x: 0.5, y: 0.5), definition: definition), 0.375, accuracy: 0.000_001)
        XCTAssertEqual(LinearGradientMaskMath.alpha(at: CGPoint(x: 0.8, y: 0.5), definition: definition), 0.75, accuracy: 0.000_001)

        let rotated = definition.changingAngle(to: .pi / 2)
        XCTAssertEqual(rotated.centerPoint, definition.centerPoint)
        XCTAssertEqual(rotated.falloff, definition.falloff, accuracy: 0.000_001)
        let resized = definition.changingFalloff(to: 0.3, keeping: .fullStrength)
        XCTAssertEqual(resized.fullStrengthPoint, definition.fullStrengthPoint)
        XCTAssertEqual(resized.falloff, 0.3, accuracy: 0.000_001)

        let zeroEdited = LinearGradientMaskMath.endpointEdited(
            definition, edge: .zeroStrength, to: CGPoint(x: 0.4, y: 0.52))
        XCTAssertEqual(zeroEdited.fullStrengthPoint, definition.fullStrengthPoint)
        XCTAssertEqual(zeroEdited.angle, definition.angle, accuracy: 0.000_001)
        XCTAssertEqual(zeroEdited.falloff, 0.4, accuracy: 0.000_001)

        let fullEdited = LinearGradientMaskMath.endpointEdited(
            definition, edge: .fullStrength, to: CGPoint(x: 0.6, y: 0.48))
        XCTAssertEqual(fullEdited.zeroStrengthPoint, definition.zeroStrengthPoint)
        XCTAssertEqual(fullEdited.angle, definition.angle, accuracy: 0.000_001)
        XCTAssertEqual(fullEdited.falloff, 0.4, accuracy: 0.000_001)

        let crossed = LinearGradientMaskMath.endpointEdited(
            definition, edge: .fullStrength, to: CGPoint(x: 0.1, y: 0.5))
        XCTAssertEqual(crossed.zeroStrengthPoint, definition.zeroStrengthPoint)
        XCTAssertGreaterThanOrEqual(crossed.falloff, 0)
    }

    func testNewLinearGradientsDefaultToVerticalWithoutChangingEndpointSemantics() {
        let definition = LinearGradientDefinition()

        XCTAssertEqual(definition.zeroStrengthPoint, CGPoint(x: 0.5, y: 0))
        XCTAssertEqual(definition.fullStrengthPoint, CGPoint(x: 0.5, y: 1))
        XCTAssertEqual(definition.angleDegrees, 90, accuracy: 0.000_001)
        XCTAssertEqual(
            LinearGradientMaskMath.alpha(at: CGPoint(x: 0.5, y: 0), definition: definition), 0)
        XCTAssertEqual(
            LinearGradientMaskMath.alpha(at: CGPoint(x: 0.5, y: 0.5), definition: definition), 0.5,
            accuracy: 0.000_001)
        XCTAssertEqual(
            LinearGradientMaskMath.alpha(at: CGPoint(x: 0.5, y: 1), definition: definition), 1)

        let persisted = LinearGradientDefinition(
            zeroStrengthPoint: CGPoint(x: 0.1, y: 0.8),
            fullStrengthPoint: CGPoint(x: 0.9, y: 0.2), density: 0.7)
        XCTAssertEqual(try? roundTrip(persisted), persisted)
    }

    func testRadialGradientMathUsesSourcePixelsForRotationAndFalloff() {
        let sourceSize = CGSize(width: 400, height: 200)
        let definition = RadialGradientDefinition(
            center: CGPoint(x: 0.5, y: 0.5), horizontalRadius: 0.25, verticalRadius: 0.25,
            rotation: .pi / 2, feather: 0.5, density: 0.8)
        XCTAssertEqual(try roundTrip(definition), definition)

        // A 90-degree rotation swaps the physical axes: the source point one normalized
        // vertical radius above the center is on the ellipse's horizontal axis.
        let rotatedAxis = CGPoint(x: 0.5, y: 0.25)
        XCTAssertEqual(
            RadialGradientMaskMath.alpha(
                at: rotatedAxis, definition: definition, sourceSize: sourceSize),
            0.8, accuracy: 0.000_001)
        XCTAssertEqual(
            RadialGradientMaskMath.alpha(
                at: CGPoint(x: 0.5, y: 0.125), definition: definition, sourceSize: sourceSize),
            0.4, accuracy: 0.000_001)

        let inner = RadialGradientMaskMath.innerPoint(
            -.pi / 2, definition: definition, sourceSize: sourceSize)
        XCTAssertEqual(inner.x, 0.5625, accuracy: 0.000_001)
        XCTAssertEqual(inner.y, 0.5, accuracy: 0.000_001)

        var outside = definition
        outside.isInside = false
        XCTAssertEqual(
            RadialGradientMaskMath.alpha(
                at: definition.center, definition: outside, sourceSize: sourceSize),
            0, accuracy: 0.000_001)
        XCTAssertEqual(
            RadialGradientMaskMath.alpha(
                at: CGPoint(x: 0.1, y: 0.1), definition: outside, sourceSize: sourceSize),
            0.8, accuracy: 0.000_001)
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

import CoreGraphics
import Foundation
import XCTest

@testable import LumoKit

@MainActor
final class MaskingWorkspaceTests: XCTestCase {
    private func waitUntil(
        _ description: String,
        timeout: TimeInterval = 5,
        _ condition: @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline { return XCTFail("timed out waiting for \(description)") }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    func testLayerActionsPersistThroughTheDocumentAndUndo() throws {
        let viewModel = AppViewModel(engine: FakeRenderEngine())

        viewModel.createMask(.linear)
        let original = try XCTUnwrap(viewModel.document.localAdjustments.first)
        XCTAssertEqual(original.name, "Linear Gradient")

        viewModel.renameMask(original.id, name: "Sky")
        viewModel.updateMask(original.id) { layer in
            layer.amount = 0.6
            layer.adjustments.exposure = 1.25
        }
        viewModel.duplicateMask(original.id)

        XCTAssertEqual(viewModel.document.localAdjustments.count, 2)
        XCTAssertEqual(viewModel.document.localAdjustments.first?.name, "Sky")
        XCTAssertEqual(viewModel.document.localAdjustments.first?.amount, 0.6)
        XCTAssertEqual(viewModel.document.localAdjustments.first?.adjustments.exposure, 1.25)

        viewModel.undo()
        XCTAssertEqual(viewModel.document.localAdjustments.count, 1)
        XCTAssertEqual(viewModel.document.localAdjustments.first?.adjustments.exposure, 1.25)

        viewModel.selectMaskLayer(original.id)
        viewModel.resetSelectedMask()
        XCTAssertEqual(viewModel.document.localAdjustments.first?.amount, 1)
        XCTAssertEqual(viewModel.document.localAdjustments.first?.adjustments, .neutral)
    }

    func testGestureEditsTheSelectedComponentNotJustTheFirstEnabledOne() throws {
        let viewModel = AppViewModel(engine: FakeRenderEngine())

        viewModel.createMask(.linear)
        let layerID = try XCTUnwrap(viewModel.document.localAdjustments.first?.id)
        viewModel.addMaskComponent(to: layerID, source: .brush(BrushMaskDefinition()))
        let brushComponentID = try XCTUnwrap(
            viewModel.document.localAdjustments.first?.components.last?.id)

        // addMaskComponent already selects the new component; the brush tool should therefore
        // draw into it, not into the pre-existing linear component at index 0.
        viewModel.setMaskTool(.brush)
        viewModel.beginMaskGesture(at: CGPoint(x: 0.2, y: 0.3))
        viewModel.endMaskGesture()

        let layer = try XCTUnwrap(viewModel.document.localAdjustments.first)
        XCTAssertEqual(layer.components.count, 2)
        guard case .linear = layer.components[0].source else {
            return XCTFail("Linear component at index 0 should be untouched")
        }
        guard case .brush(let definition) = layer.components[1].source else {
            return XCTFail("Selected brush component should have received the stroke")
        }
        XCTAssertEqual(layer.components[1].id, brushComponentID)
        XCTAssertFalse(definition.strokes.isEmpty)
    }

    func testBrushGestureCommitsOneCompactStrokeWithSettings() throws {
        let viewModel = AppViewModel(engine: FakeRenderEngine())
        viewModel.createMask(.brush)
        viewModel.maskingState.brushRadius = 0.03
        viewModel.maskingState.brushFeather = 0.25
        viewModel.maskingState.brushFlow = 0.6
        viewModel.maskingState.brushDensity = 0.8
        viewModel.setMaskTool(.brush)
        viewModel.beginMaskGesture(
            at: CGPoint(x: 0.1, y: 0.5), sourceSize: CGSize(width: 6_000, height: 4_000))
        for index in 1...10_000 {
            viewModel.updateMaskGesture(
                to: CGPoint(x: 0.1 + Double(index) / 12_500, y: 0.5),
                pressure: index.isMultiple(of: 2) ? 0.5 : nil)
        }
        viewModel.endMaskGesture()

        let layer = try XCTUnwrap(viewModel.document.localAdjustments.first)
        let stroke = try XCTUnwrap(layer.components.first?.source.brushDefinition?.strokes.first)
        XCTAssertEqual(stroke.radius, 0.03, accuracy: 0.000_001)
        XCTAssertEqual(stroke.feather, 0.25, accuracy: 0.000_001)
        XCTAssertEqual(stroke.flow, 0.6, accuracy: 0.000_001)
        XCTAssertEqual(stroke.density, 0.8, accuracy: 0.000_001)
        XCTAssertLessThanOrEqual(stroke.samples.count, 4_096)
        XCTAssertEqual(viewModel.document.localAdjustments.count, 1)
    }

    func testSeparateBrushGesturesAppendStrokesWithoutRewritingHistory() throws {
        let viewModel = AppViewModel(engine: FakeRenderEngine())
        viewModel.createMask(.brush)
        viewModel.setMaskTool(.brush)

        viewModel.beginMaskGesture(at: CGPoint(x: 0.1, y: 0.5))
        viewModel.updateMaskGesture(to: CGPoint(x: 0.2, y: 0.5))
        viewModel.endMaskGesture()
        viewModel.beginMaskGesture(at: CGPoint(x: 0.7, y: 0.5))
        viewModel.updateMaskGesture(to: CGPoint(x: 0.8, y: 0.5))
        viewModel.endMaskGesture()

        let definition = try XCTUnwrap(
            viewModel.document.localAdjustments.first?.components.first?.source.brushDefinition)
        XCTAssertEqual(definition.strokes.count, 2)
        XCTAssertEqual(definition.strokes[0].samples.first?.point, CGPoint(x: 0.1, y: 0.5))
        XCTAssertEqual(definition.strokes[1].samples.first?.point, CGPoint(x: 0.7, y: 0.5))
    }

    func testEraseBrushIsASeparateSubtractingComponent() throws {
        let viewModel = AppViewModel(engine: FakeRenderEngine())
        viewModel.createMask(.erase)
        let component = try XCTUnwrap(viewModel.document.localAdjustments.first?.components.first)
        XCTAssertEqual(component.mode, .subtract)
        XCTAssertEqual(viewModel.maskingState.activeTool, .erase)
    }

    func testComponentCreationSupportsEverySourceAndOperationWithExplicitFirstReplace() throws {
        let viewModel = AppViewModel(engine: FakeRenderEngine())
        viewModel.createMask(.foreground)
        let layerID = try XCTUnwrap(viewModel.document.localAdjustments.first?.id)

        let sources: [MaskSource] = [
            .semantic(SemanticMaskDefinition(target: .background)),
            .brush(BrushMaskDefinition()),
            .linear(LinearGradientDefinition()),
            .radial(RadialGradientDefinition()),
        ]
        let modes: [MaskCombineMode] = [.add, .subtract, .intersect, .add]
        for (source, mode) in zip(sources, modes) {
            viewModel.addMaskComponent(to: layerID, source: source, mode: mode)
        }

        let components = try XCTUnwrap(viewModel.document.localAdjustments.first?.components)
        XCTAssertEqual(components.map(\.mode), [.replace, .add, .subtract, .intersect, .add])
        XCTAssertEqual(components.map(\.source.maskingTypeTitle), [
            "Foreground", "Background", "Brush", "Linear Gradient", "Radial Gradient",
        ])
    }

    func testComponentActionsPreserveOrderNamesAndSoloInspection() throws {
        let viewModel = AppViewModel(engine: FakeRenderEngine())
        viewModel.createMask(.foreground)
        let layerID = try XCTUnwrap(viewModel.document.localAdjustments.first?.id)
        viewModel.addMaskComponent(
            to: layerID, source: .brush(BrushMaskDefinition()), mode: .subtract)
        let brushID = try XCTUnwrap(viewModel.document.localAdjustments.first?.components.last?.id)

        viewModel.renameMaskComponent(brushID, in: layerID, name: "Sky Brush")
        viewModel.moveMaskComponent(brushID, in: layerID, by: -1)
        XCTAssertEqual(viewModel.document.localAdjustments.first?.components.first?.name, "Sky Brush")
        XCTAssertEqual(viewModel.document.localAdjustments.first?.components.first?.mode, .replace)
        XCTAssertEqual(viewModel.document.localAdjustments.first?.maskingSummary, "Sky Brush · replace Foreground")

        viewModel.maskingState.toggleSolo(componentID: brushID, layerID: layerID)
        XCTAssertEqual(viewModel.maskingState.soloComponentID, brushID)
        XCTAssertEqual(viewModel.maskingState.soloLayerID, layerID)
        viewModel.deleteMaskComponent(brushID, from: layerID)
        XCTAssertNil(viewModel.maskingState.soloComponentID)
        XCTAssertEqual(viewModel.document.localAdjustments.first?.components.count, 1)
    }

    func testLinearDragCreatesAndSelectsATransientLayerUntilMouseUp() throws {
        let viewModel = AppViewModel(engine: FakeRenderEngine())
        viewModel.setMaskTool(.linear)
        viewModel.beginMaskGesture(at: CGPoint(x: 0.2, y: 0.3))
        XCTAssertTrue(viewModel.document.localAdjustments.isEmpty)
        XCTAssertNotNil(viewModel.maskInteractionState.selectedLayerID)

        viewModel.updateMaskGesture(to: CGPoint(x: 0.8, y: 0.7))
        viewModel.endMaskGesture()

        let layer = try XCTUnwrap(viewModel.document.localAdjustments.first)
        XCTAssertEqual(viewModel.maskInteractionState.selectedLayerID, layer.id)
        guard case .linear(let definition) = try XCTUnwrap(layer.components.first).source else {
            return XCTFail("linear drag should create a linear component")
        }
        XCTAssertEqual(definition.zeroStrengthPoint, CGPoint(x: 0.2, y: 0.3))
        XCTAssertEqual(definition.fullStrengthPoint, CGPoint(x: 0.8, y: 0.7))
    }

    func testLinearHandleEditsKeepOppositeEdgeAndCenterStable() throws {
        let viewModel = AppViewModel(engine: FakeRenderEngine())
        viewModel.createMask(.linear)
        let layerID = try XCTUnwrap(viewModel.maskInteractionState.selectedLayerID)
        let componentID = try XCTUnwrap(viewModel.maskInteractionState.selectedComponentID)
        let original = try XCTUnwrap(viewModel.document.localAdjustments.first?.components.first?.source.linearDefinition)

        viewModel.setMaskTool(.linear)
        viewModel.beginMaskGesture(at: original.fullStrengthPoint, linearHandle: .fullStrength)
        viewModel.updateMaskGesture(to: CGPoint(x: 0.75, y: 0.5))
        viewModel.endMaskGesture()
        let resized = try XCTUnwrap(viewModel.document.localAdjustments.first?.components.first?.source.linearDefinition)
        XCTAssertEqual(resized.zeroStrengthPoint, original.zeroStrengthPoint)
        XCTAssertEqual(resized.angle, original.angle, accuracy: 0.000_001)

        viewModel.beginMaskGesture(at: resized.centerPoint, linearHandle: .center)
        viewModel.updateMaskGesture(to: CGPoint(x: resized.centerPoint.x + 0.1, y: resized.centerPoint.y + 0.1))
        viewModel.endMaskGesture()
        let moved = try XCTUnwrap(viewModel.document.localAdjustments.first?.components.first?.source.linearDefinition)
        XCTAssertEqual(moved.centerPoint, CGPoint(x: resized.centerPoint.x + 0.1, y: resized.centerPoint.y + 0.1))
        XCTAssertEqual(moved.falloff, resized.falloff, accuracy: 0.000_001)
        XCTAssertEqual(viewModel.maskInteractionState.selectedComponentID, componentID)
        XCTAssertEqual(viewModel.maskInteractionState.selectedLayerID, layerID)
    }

    func testNewLinearLayerStartsWithCreationDragEvenWhenDefaultGuideIsUnderPointer() throws {
        let viewModel = AppViewModel(engine: FakeRenderEngine())
        viewModel.createMask(.linear)
        viewModel.beginMaskGesture(at: CGPoint(x: 0.25, y: 0.25))
        viewModel.updateMaskGesture(to: CGPoint(x: 0.75, y: 0.75))
        viewModel.endMaskGesture()

        let definition = try XCTUnwrap(
            viewModel.document.localAdjustments.first?.components.first?.source.linearDefinition)
        XCTAssertEqual(definition.zeroStrengthPoint, CGPoint(x: 0.25, y: 0.25))
        XCTAssertEqual(definition.fullStrengthPoint, CGPoint(x: 0.75, y: 0.75))
    }

    func testInspectorChangesFollowTheLiveLinearDraftUntilMouseUp() throws {
        let viewModel = AppViewModel(engine: FakeRenderEngine())
        viewModel.createMask(.linear)
        let layerID = try XCTUnwrap(viewModel.maskInteractionState.selectedLayerID)
        let componentID = try XCTUnwrap(viewModel.maskInteractionState.selectedComponentID)

        viewModel.setMaskTool(.linear)
        viewModel.beginMaskGesture(at: CGPoint(x: 0.2, y: 0.5))
        viewModel.updateMaskComponent(componentID, in: layerID) { component in
            if case .linear(var definition) = component.source {
                definition.density = 0.4
                component.source = .linear(definition)
            }
        }

        XCTAssertEqual(
            viewModel.document.localAdjustments.first?.components.first?.source.linearDefinition?.density,
            1
        )
        XCTAssertEqual(
            viewModel.maskInteractionState.draftLayer?.components.first?.source.linearDefinition?.density,
            0.4
        )

        viewModel.updateMaskGesture(to: CGPoint(x: 0.8, y: 0.5))
        viewModel.endMaskGesture()
        XCTAssertEqual(
            viewModel.document.localAdjustments.first?.components.first?.source.linearDefinition?.density,
            0.4
        )
    }

    func testCancellingLinearCreationDoesNotPersistAnEmptyLayer() {
        let viewModel = AppViewModel(engine: FakeRenderEngine())
        viewModel.setMaskTool(.linear)
        viewModel.beginMaskGesture(at: CGPoint(x: 0.2, y: 0.3))
        viewModel.cancelMaskGesture()
        XCTAssertTrue(viewModel.document.localAdjustments.isEmpty)
        XCTAssertNil(viewModel.maskInteractionState.selectedLayerID)
    }

    func testRadialDragCreatesAndSelectsATransientLayerUntilMouseUp() throws {
        let viewModel = AppViewModel(engine: FakeRenderEngine())
        viewModel.setMaskTool(.radial)
        viewModel.beginMaskGesture(
            at: CGPoint(x: 0.3, y: 0.4), sourceSize: CGSize(width: 400, height: 200))
        XCTAssertTrue(viewModel.document.localAdjustments.isEmpty)

        viewModel.updateMaskGesture(
            to: CGPoint(x: 0.55, y: 0.65), modifiers: [])
        viewModel.endMaskGesture()

        let layer = try XCTUnwrap(viewModel.document.localAdjustments.first)
        XCTAssertEqual(layer.name, "Radial Gradient")
        guard case .radial(let definition) = try XCTUnwrap(layer.components.first).source else {
            return XCTFail("radial drag should create a radial component")
        }
        XCTAssertEqual(definition.center, CGPoint(x: 0.3, y: 0.4))
        XCTAssertEqual(definition.horizontalRadius, 0.25, accuracy: 0.000_001)
        XCTAssertEqual(definition.verticalRadius, 0.25, accuracy: 0.000_001)
        XCTAssertEqual(viewModel.maskInteractionState.selectedLayerID, layer.id)
    }

    func testRadialHandlesResizeTranslateRotateAndOptionShiftModifiers() throws {
        let viewModel = AppViewModel(engine: FakeRenderEngine())
        viewModel.createMask(.radial)
        let layerID = try XCTUnwrap(viewModel.maskInteractionState.selectedLayerID)
        let componentID = try XCTUnwrap(viewModel.maskInteractionState.selectedComponentID)
        let original = try XCTUnwrap(
            viewModel.document.localAdjustments.first?.components.first?.source.radialDefinition)
        let sourceSize = CGSize(width: 400, height: 200)
        viewModel.setMaskTool(.radial)
        // The Add-mask action leaves the first canvas drag in creation mode. Consume that
        // presentation-only pending state here so the following gestures exercise re-editing.
        viewModel.maskInteractionState.consumeRadialCreationPending()

        let right = CGPoint(x: original.center.x + original.horizontalRadius, y: original.center.y)
        viewModel.beginMaskGesture(
            at: right, radialHandle: .horizontalRadius, sourceSize: sourceSize)
        viewModel.updateMaskGesture(
            to: CGPoint(x: 0.8, y: original.center.y), modifiers: [])
        viewModel.endMaskGesture()
        let resized = try XCTUnwrap(
            viewModel.document.localAdjustments.first?.components.first?.source.radialDefinition)
        XCTAssertEqual(resized.center.x, 0.4, accuracy: 0.000_001)
        XCTAssertEqual(resized.horizontalRadius, 0.4, accuracy: 0.000_001)
        XCTAssertEqual(resized.verticalRadius, original.verticalRadius, accuracy: 0.000_001)

        let center = resized.center
        viewModel.beginMaskGesture(at: center, radialHandle: .center, sourceSize: sourceSize)
        viewModel.updateMaskGesture(to: CGPoint(x: center.x + 0.1, y: center.y - 0.05))
        viewModel.endMaskGesture()
        let moved = try XCTUnwrap(
            viewModel.document.localAdjustments.first?.components.first?.source.radialDefinition)
        XCTAssertEqual(moved.center.x, center.x + 0.1, accuracy: 0.000_001)
        XCTAssertEqual(moved.center.y, center.y - 0.05, accuracy: 0.000_001)

        let movedRight = CGPoint(x: moved.center.x + moved.horizontalRadius, y: moved.center.y)
        viewModel.beginMaskGesture(
            at: movedRight, radialHandle: .horizontalRadius, sourceSize: sourceSize)
        viewModel.updateMaskGesture(
            to: CGPoint(x: moved.center.x + 0.2, y: moved.center.y),
            modifiers: [.option, .shift])
        viewModel.endMaskGesture()
        let constrained = try XCTUnwrap(
            viewModel.document.localAdjustments.first?.components.first?.source.radialDefinition)
        XCTAssertEqual(
            constrained.horizontalRadius * sourceSize.width,
            constrained.verticalRadius * sourceSize.height,
            accuracy: 0.000_001)
        XCTAssertEqual(constrained.center, moved.center)

        viewModel.beginMaskGesture(
            at: CGPoint(x: constrained.center.x, y: constrained.center.y - constrained.verticalRadius),
            radialHandle: .rotation, sourceSize: sourceSize)
        viewModel.updateMaskGesture(to: CGPoint(
            x: constrained.center.x + 0.1, y: constrained.center.y), modifiers: [])
        viewModel.endMaskGesture()
        let rotated = try XCTUnwrap(
            viewModel.document.localAdjustments.first?.components.first?.source.radialDefinition)
        XCTAssertEqual(rotated.rotation, .pi / 2, accuracy: 0.000_001)
        XCTAssertEqual(viewModel.maskInteractionState.selectedComponentID, componentID)
        XCTAssertEqual(viewModel.maskInteractionState.selectedLayerID, layerID)
    }

    func testCancellingRadialCreationDoesNotPersistAnEmptyLayer() {
        let viewModel = AppViewModel(engine: FakeRenderEngine())
        viewModel.setMaskTool(.radial)
        viewModel.beginMaskGesture(at: CGPoint(x: 0.2, y: 0.3))
        viewModel.cancelMaskGesture()
        XCTAssertTrue(viewModel.document.localAdjustments.isEmpty)
        XCTAssertNil(viewModel.maskInteractionState.selectedLayerID)
    }

    func testSourceSwitchResetClearsTransientMaskPresentationState() {
        let viewModel = AppViewModel(engine: FakeRenderEngine())
        viewModel.createMask(.brush)
        let layerID = viewModel.document.localAdjustments[0].id
        viewModel.maskInteractionState.toggleSolo(layerID: layerID)
        viewModel.maskInteractionState.beginDraft(viewModel.document.localAdjustments[0])

        viewModel.maskInteractionState.resetForSource()

        XCTAssertNil(viewModel.maskInteractionState.selectedLayerID)
        XCTAssertNil(viewModel.maskInteractionState.soloLayerID)
        XCTAssertFalse(viewModel.maskInteractionState.hasDraft)
    }

    func testOverlayPresentationControlsDoNotChangeDocumentOrUndoHistory() throws {
        let viewModel = AppViewModel(engine: FakeRenderEngine())
        viewModel.createMask(.brush)
        let before = viewModel.document
        let undoBefore = viewModel.undoDepth
        let layerID = try XCTUnwrap(viewModel.maskInteractionState.selectedLayerID)

        viewModel.maskInteractionState.showOverlay = false
        viewModel.maskInteractionState.overlayInspection = .grayscale
        viewModel.maskInteractionState.overlayColor = .blue
        viewModel.maskInteractionState.overlayOpacity = 0.08
        viewModel.maskInteractionState.toggleSolo(layerID: layerID)

        XCTAssertEqual(viewModel.document, before)
        XCTAssertEqual(viewModel.undoDepth, undoBefore)
        XCTAssertEqual(viewModel.maskInteractionState.soloLayerID, layerID)
    }

    func testProductionCreationExposesEverySupportedSmartKindAndPersistsIt() throws {
        XCTAssertEqual(MaskCreationKind.smartKinds, [
            .subject, .person, .face, .foreground, .background,
        ])

        let viewModel = AppViewModel(engine: FakeRenderEngine())
        for kind in MaskCreationKind.smartKinds {
            viewModel.createMask(kind)
        }

        let layers = viewModel.document.localAdjustments
        XCTAssertEqual(layers.count, MaskCreationKind.smartKinds.count)
        XCTAssertEqual(
            layers.compactMap { $0.components.first?.source.semanticDefinition?.target },
            MaskCreationKind.smartKinds.compactMap(\.semanticTarget)
        )

        let reopened = try JSONDecoder().decode(
            EditDocument.self, from: JSONEncoder().encode(viewModel.document)
        )
        XCTAssertEqual(reopened.localAdjustments, layers)
    }

    func testSmartCreationFailureWithoutSupportedSourceDoesNotCreateAnInertLayer() {
        let viewModel = AppViewModel(engine: FakeRenderEngine())

        viewModel.createSmartMask(.subject)

        XCTAssertTrue(viewModel.document.localAdjustments.isEmpty)
        XCTAssertEqual(
            viewModel.maskingState.resolutionState,
            .unavailable("Smart masks require an open photo with supported analysis.")
        )
    }

    func testSmartActionPreflightsSharedProviderThenSelectsDurableMask() async throws {
        let directory = try Fixtures.makeTempDirectory("ProductionSmartMask")
        defer { try? FileManager.default.removeItem(at: directory) }
        let imageURL = try Fixtures.writeGradientPNG(
            width: 16, height: 12, named: "smart.png", in: directory)
        let store = MaskStore(directory: directory.appendingPathComponent("masks"))
        let coordinator = PhotoAnalysisCoordinator(
            maskStore: store,
            maskProvider: ProductionSmartMaskProvider(store: store),
            stages: [:]
        )
        let viewModel = AppViewModel(
            engine: FakeRenderEngine(),
            editStore: EditDocumentStore(fileURL: directory.appendingPathComponent("edits.json")),
            photoAnalysisCoordinator: coordinator
        )

        viewModel.openImage(url: imageURL)
        try await waitUntil("the photo to load") { viewModel.sourceImage != nil }
        viewModel.createSmartMask(.subject)
        try await waitUntil("the smart mask to be created") {
            viewModel.document.localAdjustments.count == 1
        }

        let component = try XCTUnwrap(viewModel.document.localAdjustments.first?.components.first)
        XCTAssertEqual(component.source.semanticDefinition?.target, .subject)
        XCTAssertEqual(viewModel.maskingState.selectedComponentID, component.id)
        XCTAssertEqual(viewModel.maskingState.resolutionState, .ready)
    }
}

private actor ProductionSmartMaskProvider: SemanticMaskProviding {
    private let store: MaskStore

    init(store: MaskStore) { self.store = store }

    func mask(for kind: SemanticMaskKind, image: AnalysisImage, quality: MaskQuality) async throws -> RegionMask {
        let pixels = try NormalizedMask(
            size: image.dimensions,
            values: Array(repeating: 1, count: image.dimensions.width * image.dimensions.height)
        )
        let assetID = image.assetID ?? PhotoAnalysisCoordinator.assetID(for: image.source)
        let key = MaskCacheKey(
            assetID: assetID,
            sourceFingerprint: PhotoAnalysisCoordinator.sourceFingerprint(for: image.source),
            kind: kind,
            quality: quality,
            providerVersion: "production-test-1"
        )
        let reference = try await store.store(pixels, for: key, quality: quality)
        return RegionMask(
            kind: kind,
            bounds: NormalizedRect(x: 0, y: 0, width: 1, height: 1),
            quality: quality,
            reference: reference,
            confidence: 1,
            coverage: pixels.coverage
        )
    }
}

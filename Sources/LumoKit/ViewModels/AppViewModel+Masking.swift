import Foundation
import CoreGraphics

/// The creation actions exposed by the persistent masking workspace. A layer is created with a
/// durable recipe immediately; semantic pixels and other render resources remain derived state.
enum MaskCreationKind: String, CaseIterable, Sendable {
    case foreground, background, brush, linear, radial

    var title: String {
        switch self {
        case .foreground: return "Foreground"
        case .background: return "Background"
        case .brush: return "Brush"
        case .linear: return "Linear Gradient"
        case .radial: return "Radial Gradient"
        }
    }
}

extension MaskSource {
    var maskingTypeTitle: String {
        switch self {
        case .semantic(let definition):
            return definition.target.rawValue.capitalized
        case .brush: return "Brush"
        case .linear: return "Linear Gradient"
        case .radial: return "Radial Gradient"
        }
    }
}

extension LocalAdjustmentLayer {
    var maskingTypeTitle: String {
        components.first?.source.maskingTypeTitle ?? "Empty mask"
    }

    /// The component a pointer gesture should edit: the selected component if it belongs to this
    /// layer and is enabled, otherwise the first enabled component. Without this, a gesture always
    /// hit the first enabled component regardless of which one was selected in the inspector,
    /// silently overwriting the wrong component's saved definition on layers with more than one.
    func targetComponentIndex(selected componentID: UUID?) -> Int? {
        if let componentID,
            let index = components.firstIndex(where: { $0.id == componentID && $0.isEnabled })
        {
            return index
        }
        return components.firstIndex(where: { $0.isEnabled })
    }
}

extension AppViewModel {
    /// One narrow observation boundary owns selection, transient creation, and presentation state
    /// for the masking workspace. The document itself remains owned by AppViewModel.
    var maskingState: MaskInteractionState { maskInteractionState }

    /// Render only the presentation overlay for the masking canvas. The request carries transient
    /// selection/style state and never goes through `schedulePreview`, persistence, or history.
    func renderMaskOverlay(
        layers: [LocalAdjustmentLayer],
        selectedLayerID: UUID?,
        soloLayerID: UUID?,
        targetSize: PixelDimensions,
        style: MaskOverlayStyle,
        transform: LocalMaskRenderTransform = .identity
    ) async -> sending CGImage? {
        guard let source = maskOverlaySource else { return nil }
        return await maskOverlayEngine.makeMaskOverlayImage(MaskOverlayRequest(
            source: source,
            layers: layers,
            selectedLayerID: selectedLayerID,
            soloLayerID: soloLayerID,
            targetSize: targetSize,
            transform: transform,
            style: style
        ))
    }

    func openMaskingWorkspace() {
        guard sourceImage != nil, maskingAssetID != nil else { return }
        endUndoGrouping()
        if document.localAdjustments.isEmpty {
            maskInteractionState.select(layerID: nil)
        } else if maskInteractionState.selectedLayerID == nil {
            restoreMaskSelection()
        }
        inspectorState.isMaskingWorkspacePresented = true
        inspectorState.isPresented = true
        isMaskingPanelPresented = false
    }

    func selectMaskLayer(_ id: UUID?) {
        guard let id, document.localAdjustments.contains(where: { $0.id == id }) else {
            maskInteractionState.select(layerID: nil)
            return
        }
        maskInteractionState.select(layerID: id)
    }

    func selectMaskComponent(_ componentID: UUID, in layerID: UUID) {
        guard
            document.localAdjustments.contains(where: {
                $0.id == layerID && $0.components.contains(where: { $0.id == componentID })
            })
        else { return }
        maskInteractionState.select(componentID: componentID, in: layerID)
    }

    func createMask(_ kind: MaskCreationKind) {
        let source: MaskSource
        switch kind {
        case .foreground:
            source = .semantic(SemanticMaskDefinition(target: .foreground))
        case .background:
            source = .semantic(SemanticMaskDefinition(target: .background))
        case .brush:
            source = .brush(BrushMaskDefinition())
        case .linear:
            source = .linear(LinearGradientDefinition())
        case .radial:
            source = .radial(RadialGradientDefinition())
        }

        let layerID = UUID()
        let component = MaskComponent(source: source)
        let name = nextMaskName(for: kind.title)
        updateDocument { document in
            document.localAdjustments.append(
                LocalAdjustmentLayer(id: layerID, name: name, components: [component])
            )
        }
        maskInteractionState.setTool(
            kind == .foreground
                ? .foreground
                : kind == .background
                    ? .background : MaskInteractionState.Tool(rawValue: kind.rawValue) ?? .selection
        )
        maskInteractionState.select(componentID: component.id, in: layerID)
        if kind == .linear {
            maskInteractionState.markLinearCreationPending()
        }
        statusMessage = "Created \(name)"
    }

    func duplicateMask(_ id: UUID) {
        guard let index = document.localAdjustments.firstIndex(where: { $0.id == id }) else {
            return
        }
        var copy = document.localAdjustments[index]
        copy.id = UUID()
        copy.name = nextMaskName(for: "\(copy.name) Copy")
        copy.components = copy.components.map { component in
            var component = component
            component.id = UUID()
            if case .brush(let brush) = component.source {
                component.source = .brush(brush)
            }
            return component
        }
        updateDocument { $0.localAdjustments.insert(copy, at: index + 1) }
        maskInteractionState.select(layerID: copy.id, componentID: copy.components.first?.id)
    }

    func renameMask(_ id: UUID, name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        updateMask(id) { $0.name = String(trimmed.prefix(80)) }
    }

    func deleteMask(_ id: UUID) {
        guard let index = document.localAdjustments.firstIndex(where: { $0.id == id }) else {
            return
        }
        let nextID =
            document.localAdjustments.dropFirst(index + 1).first?.id
            ?? document.localAdjustments.dropLast(max(0, document.localAdjustments.count - index))
            .last?.id
        updateDocument { $0.localAdjustments.remove(at: index) }
        maskInteractionState.select(layerID: nextID)
        maskInteractionState.clearSolo()
    }

    func moveMask(_ id: UUID, by offset: Int) {
        guard let index = document.localAdjustments.firstIndex(where: { $0.id == id }) else {
            return
        }
        let destination = min(max(index + offset, 0), document.localAdjustments.count - 1)
        guard destination != index else { return }
        updateDocument { document in
            let moved = document.localAdjustments.remove(at: index)
            document.localAdjustments.insert(moved, at: destination)
        }
    }

    func updateMask(
        _ id: UUID, debounced: Bool = false, _ transform: (inout LocalAdjustmentLayer) -> Void
    ) {
        updateDocument(debounced: debounced) { document in
            guard let index = document.localAdjustments.firstIndex(where: { $0.id == id }) else {
                return
            }
            transform(&document.localAdjustments[index])
        }
    }

    func updateSelectedMask(
        debounced: Bool = false, _ transform: (inout LocalAdjustmentLayer) -> Void
    ) {
        guard let id = maskInteractionState.selectedLayerID else { return }
        updateMask(id, debounced: debounced, transform)
    }

    func addMaskComponent(to layerID: UUID, source: MaskSource, mode: MaskCombineMode = .add) {
        let component = MaskComponent(mode: mode, source: source)
        updateMask(layerID) { $0.components.append(component) }
        maskInteractionState.select(componentID: component.id, in: layerID)
    }

    func deleteMaskComponent(_ componentID: UUID, from layerID: UUID) {
        updateMask(layerID) { layer in
            layer.components.removeAll { $0.id == componentID }
        }
        if maskInteractionState.selectedComponentID == componentID {
            maskInteractionState.select(layerID: layerID)
        }
    }

    func resetMask(_ id: UUID) {
        updateMask(id) { layer in
            layer.isEnabled = true
            layer.isInverted = false
            layer.amount = 1
            layer.adjustments = .neutral
            for index in layer.components.indices {
                layer.components[index].isEnabled = true
                layer.components[index].isInverted = false
                layer.components[index].mode = index == 0 ? .replace : layer.components[index].mode
            }
        }
    }

    func resetMaskComponent(_ componentID: UUID, in layerID: UUID) {
        updateMaskComponent(componentID, in: layerID) { component in
            component.isEnabled = true
            component.isInverted = false
            switch component.source {
            case .linear:
                component.source = .linear(LinearGradientDefinition())
            case .radial:
                component.source = .radial(RadialGradientDefinition())
            case .brush:
                component.source = .brush(BrushMaskDefinition())
            case .semantic(let definition):
                component.source = .semantic(SemanticMaskDefinition(target: definition.target))
            }
        }
    }

    func resetSelectedMask() {
        guard let id = maskInteractionState.selectedLayerID else { return }
        resetMask(id)
    }

    func updateMaskComponent(
        _ componentID: UUID, in layerID: UUID, _ transform: (inout MaskComponent) -> Void
    ) {
        updateMask(layerID) { layer in
            guard let index = layer.components.firstIndex(where: { $0.id == componentID }) else {
                return
            }
            transform(&layer.components[index])
        }
    }

    @discardableResult
    func nudgeSelectedMask(dx: Double, dy: Double, accelerated: Bool = false) -> Bool {
        guard let layerID = maskInteractionState.selectedLayerID,
            let componentID = maskInteractionState.selectedComponentID,
            let layer = document.localAdjustments.first(where: { $0.id == layerID }),
            let component = layer.components.first(where: { $0.id == componentID }),
            component.isEnabled,
            case .linear = component.source
        else { return false }
        let step = accelerated ? 0.05 : 0.005
        updateMaskComponent(componentID, in: layerID) { component in
            guard case .linear(let definition) = component.source else { return }
            component.source = .linear(LinearGradientMaskMath.translated(
                definition, by: CGPoint(x: dx * step, y: dy * step)))
        }
        return true
    }

    func setMaskTool(_ tool: MaskInteractionState.Tool) {
        if maskInteractionState.hasDraft {
            cancelMaskGesture()
        } else {
            endUndoGrouping()
        }
        maskInteractionState.setTool(tool)
    }

    func beginMaskGesture(
        at point: CGPoint, linearHandle: MaskInteractionState.LinearHandle? = nil
    ) {
        guard maskInteractionState.activeTool != .selection else { return }
        let clamped = CGPoint(x: min(max(point.x, 0), 1), y: min(max(point.y, 0), 1))

        let layer: LocalAdjustmentLayer
        if let id = maskInteractionState.selectedLayerID,
            let existing = document.localAdjustments.first(where: { $0.id == id }) {
            layer = existing
        } else if maskInteractionState.activeTool == .linear {
            // A drag with the Linear tool is also a creation gesture. Keep the new layer transient
            // until mouse-up so Escape/cancel leaves no empty durable layer behind.
            let component = MaskComponent(source: .linear(LinearGradientDefinition(
                zeroStrengthPoint: clamped, fullStrengthPoint: clamped)))
            let newLayer = LocalAdjustmentLayer(
                name: nextMaskName(for: MaskCreationKind.linear.title), components: [component])
            maskInteractionState.select(componentID: component.id, in: newLayer.id)
            layer = newLayer
        } else {
            return
        }
        var draft = layer
        guard let componentIndex = draft.targetComponentIndex(
            selected: maskInteractionState.selectedComponentID)
        else {
            return
        }
        switch maskInteractionState.activeTool {
        case .brush:
            draft.components[componentIndex].source = .brush(
                BrushMaskDefinition(
                    strokes: [BrushStroke(samples: [BrushSample(point: clamped)])]
                ))
        case .linear:
            if case .linear(let current) = draft.components[componentIndex].source {
                if linearHandle == nil || linearHandle == .creation {
                    draft.components[componentIndex].source = .linear(
                        LinearGradientDefinition(
                            zeroStrengthPoint: clamped, fullStrengthPoint: clamped,
                            density: current.density
                        ))
                }
            }
        case .radial:
            if case .radial(let current) = draft.components[componentIndex].source {
                draft.components[componentIndex].source = .radial(
                    RadialGradientDefinition(
                        center: clamped, horizontalRadius: 0, verticalRadius: 0,
                        rotation: current.rotation, feather: current.feather,
                        density: current.density, isInside: current.isInside
                    ))
            }
        default:
            break
        }
        maskInteractionState.beginDraft(draft, at: clamped)
        if maskInteractionState.activeTool == .linear {
            let handle = maskInteractionState.linearCreationPending
                ? .creation : (linearHandle ?? .creation)
            maskInteractionState.beginLinearGesture(handle, at: clamped)
            maskInteractionState.consumeLinearCreationPending()
        }
        updateMaskGesture(to: point)
        beginPreviewInteraction()
    }

    func updateMaskGesture(to point: CGPoint) {
        guard var draft = maskInteractionState.draftLayer,
            let componentIndex = draft.targetComponentIndex(
                selected: maskInteractionState.selectedComponentID)
        else { return }
        let clamped = CGPoint(x: min(max(point.x, 0), 1), y: min(max(point.y, 0), 1))
        switch maskInteractionState.activeTool {
        case .brush:
            guard case .brush(var definition) = draft.components[componentIndex].source else {
                return
            }
            if definition.strokes.isEmpty {
                definition.strokes = [BrushStroke(samples: [BrushSample(point: clamped)])]
            } else {
                definition.strokes[definition.strokes.count - 1].samples.append(
                    BrushSample(point: clamped))
            }
            draft.components[componentIndex].source = .brush(definition)
        case .linear:
            guard case .linear(let current) = draft.components[componentIndex].source else {
                return
            }
            let handle = maskInteractionState.activeLinearHandle ?? .creation
            let updated: LinearGradientDefinition
            let original = maskInteractionState.gestureStartDefinition ?? current
            let directionLength = max(original.falloff, 0.000001)
            let direction = CGPoint(
                x: (original.fullStrengthPoint.x - original.zeroStrengthPoint.x)
                    / directionLength,
                y: (original.fullStrengthPoint.y - original.zeroStrengthPoint.y)
                    / directionLength
            )
            switch handle {
            case .zeroStrength:
                let length = max(0, min(sqrt(2.0),
                    (original.fullStrengthPoint.x - clamped.x) * direction.x
                    + (original.fullStrengthPoint.y - clamped.y) * direction.y))
                updated = original.changingFalloff(to: length, keeping: .fullStrength)
            case .fullStrength:
                let length = max(0, min(sqrt(2.0),
                    (clamped.x - original.zeroStrengthPoint.x) * direction.x
                    + (clamped.y - original.zeroStrengthPoint.y) * direction.y))
                updated = original.changingFalloff(to: length, keeping: .zeroStrength)
            case .creation:
                updated = LinearGradientDefinition(
                    zeroStrengthPoint: current.zeroStrengthPoint, fullStrengthPoint: clamped,
                    density: current.density)
            case .center:
                guard let start = maskInteractionState.gestureStartPoint,
                    let original = maskInteractionState.gestureStartDefinition else { return }
                updated = LinearGradientMaskMath.translated(
                    original, by: CGPoint(x: clamped.x - start.x, y: clamped.y - start.y))
            case .rotation:
                let center = original.centerPoint
                let targetAngle = atan2(clamped.y - center.y, clamped.x - center.x) - .pi / 2
                updated = original.changingAngle(to: targetAngle)
            }
            draft.components[componentIndex].source = .linear(updated)
        case .radial:
            guard case .radial(let current) = draft.components[componentIndex].source else {
                return
            }
            let center = current.center
            draft.components[componentIndex].source = .radial(
                RadialGradientDefinition(
                    center: center,
                    horizontalRadius: abs(clamped.x - center.x),
                    verticalRadius: abs(clamped.y - center.y),
                    rotation: current.rotation, feather: current.feather,
                    density: current.density, isInside: current.isInside
                )
            )
        default:
            break
        }
        maskInteractionState.updateDraft(draft)
    }

    func endMaskGesture() {
        guard let committed = maskInteractionState.commitDraft() else { return }
        if document.localAdjustments.contains(where: { $0.id == committed.id }) {
            updateMask(committed.id) { $0 = committed }
        } else {
            updateDocument { $0.localAdjustments.append(committed) }
        }
        endPreviewInteraction()
    }

    func cancelMaskGesture() {
        guard maskInteractionState.hasDraft else { return }
        let selectedID = maskInteractionState.selectedLayerID
        maskInteractionState.cancelDraft()
        if let selectedID, !document.localAdjustments.contains(where: { $0.id == selectedID }) {
            maskInteractionState.select(layerID: nil)
        }
        endPreviewInteraction()
    }

    func restoreMaskSelection() {
        guard let first = document.localAdjustments.first else {
            maskInteractionState.select(layerID: nil)
            return
        }
        let selected =
            document.localAdjustments.contains(where: {
                $0.id == maskInteractionState.selectedLayerID
            }) ? maskInteractionState.selectedLayerID : first.id
        maskInteractionState.select(layerID: selected)
    }

    func resetMaskingWorkspace() {
        endUndoGrouping()
        updateDocument { $0.localAdjustments.removeAll() }
        maskInteractionState.select(layerID: nil)
        maskInteractionState.clearSolo()
    }

    func closeMaskingWorkspace() {
        inspectorState.isMaskingWorkspacePresented = false
    }

    private func nextMaskName(for base: String) -> String {
        let existing = Set(document.localAdjustments.map(\.name))
        if !existing.contains(base) { return base }
        var ordinal = 2
        while existing.contains("\(base) \(ordinal)") { ordinal += 1 }
        return "\(base) \(ordinal)"
    }
}

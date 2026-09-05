import Foundation
import CoreGraphics
import AppKit

/// The creation actions exposed by the persistent masking workspace. A layer is created with a
/// durable recipe immediately; semantic pixels and other render resources remain derived state.
enum MaskCreationKind: String, CaseIterable, Sendable {
    case foreground, background, brush, erase, linear, radial

    var title: String {
        switch self {
        case .foreground: return "Foreground"
        case .background: return "Background"
        case .brush: return "Brush"
        case .erase: return "Erase Brush"
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

extension MaskComponent {
    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? source.maskingTypeTitle : trimmed
    }
}

extension LocalAdjustmentLayer {
    var maskingTypeTitle: String {
        components.first?.source.maskingTypeTitle ?? "Empty mask"
    }

    /// A compact semantic description for layer rows and accessibility. The first component is
    /// the base selection; later components retain their ordered operation in the summary.
    var maskingSummary: String {
        guard let first = components.first else { return "Empty mask" }
        return ([first.displayName] + components.dropFirst().map {
            "\($0.mode.summaryWord.lowercased()) \($0.displayName)"
        }).joined(separator: " · ")
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
        transform: LocalMaskRenderTransform = .identity,
        selectedComponentID: UUID? = nil,
        soloComponentID: UUID? = nil
    ) async -> sending CGImage? {
        guard let source = maskOverlaySource else { return nil }
        return await maskOverlayEngine.makeMaskOverlayImage(MaskOverlayRequest(
            source: source,
            assetID: maskingAssetID,
            layers: layers,
            selectedLayerID: selectedLayerID,
            soloLayerID: soloLayerID,
            targetSize: targetSize,
            transform: transform,
            style: style,
            requestRevision: maskingSourceRevision,
            selectedComponentID: selectedComponentID,
            soloComponentID: soloComponentID
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
        case .erase:
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
                LocalAdjustmentLayer(
                    id: layerID, name: name,
                    components: [MaskComponent(
                        id: component.id, mode: kind == .erase ? .subtract : .replace,
                        source: source
                    )]
                )
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
        } else if kind == .radial {
            maskInteractionState.markRadialCreationPending()
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
        let componentMode: MaskCombineMode
        if document.localAdjustments.first(where: { $0.id == layerID })?.components.isEmpty ?? true {
            componentMode = .replace
        } else {
            componentMode = mode
        }
        let component = MaskComponent(mode: componentMode, source: source)
        updateMask(layerID) { $0.components.append(component) }
        maskInteractionState.select(componentID: component.id, in: layerID)
    }

    func addMaskComponent(to layerID: UUID, kind: MaskCreationKind, mode: MaskCombineMode) {
        let source: MaskSource
        switch kind {
        case .foreground: source = .semantic(SemanticMaskDefinition(target: .foreground))
        case .background: source = .semantic(SemanticMaskDefinition(target: .background))
        case .brush, .erase: source = .brush(BrushMaskDefinition())
        case .linear: source = .linear(LinearGradientDefinition())
        case .radial: source = .radial(RadialGradientDefinition())
        }
        addMaskComponent(to: layerID, source: source, mode: mode)
    }

    func renameMaskComponent(_ componentID: UUID, in layerID: UUID, name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        updateMaskComponent(componentID, in: layerID) { component in
            component.name = String(trimmed.prefix(80))
        }
    }

    func moveMaskComponent(_ componentID: UUID, in layerID: UUID, by offset: Int) {
        updateMask(layerID) { layer in
            guard let index = layer.components.firstIndex(where: { $0.id == componentID }) else {
                return
            }
            let destination = min(max(index + offset, 0), layer.components.count - 1)
            guard destination != index else { return }
            let component = layer.components.remove(at: index)
            layer.components.insert(component, at: destination)
            if !layer.components.isEmpty {
                layer.components[0].mode = .replace
            }
        }
    }

    func setMaskComponentMode(
        _ componentID: UUID, in layerID: UUID, mode: MaskCombineMode
    ) {
        updateMask(layerID) { layer in
            guard let index = layer.components.firstIndex(where: { $0.id == componentID }) else {
                return
            }
            layer.components[index].mode = index == 0 ? .replace : mode
        }
    }

    func deleteMaskComponent(_ componentID: UUID, from layerID: UUID) {
        updateMask(layerID) { layer in
            layer.components.removeAll { $0.id == componentID }
            if !layer.components.isEmpty {
                layer.components[0].mode = .replace
            }
        }
        if maskInteractionState.selectedComponentID == componentID {
            maskInteractionState.select(layerID: layerID)
        }
        if maskInteractionState.soloComponentID == componentID {
            maskInteractionState.clearSolo()
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
            component.isEnabled
        else { return false }
        let step = accelerated ? 0.05 : 0.005
        updateMaskComponent(componentID, in: layerID) { component in
            switch component.source {
            case .linear(let definition):
                component.source = .linear(LinearGradientMaskMath.translated(
                    definition, by: CGPoint(x: dx * step, y: dy * step)))
            case .radial(var definition):
                definition.center = CGPoint(
                    x: min(max(definition.center.x + dx * step, 0), 1),
                    y: min(max(definition.center.y + dy * step, 0), 1))
                component.source = .radial(definition)
            default:
                break
            }
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
        at point: CGPoint,
        linearHandle: MaskInteractionState.LinearHandle? = nil,
        radialHandle: MaskInteractionState.RadialHandle? = nil,
        sourceSize: CGSize = CGSize(width: 1, height: 1),
        pressure: Double? = nil,
        modifiers: NSEvent.ModifierFlags = []
    ) {
        guard maskInteractionState.activeTool != .selection else { return }
        let clamped = CGPoint(x: min(max(point.x, 0), 1), y: min(max(point.y, 0), 1))

        let layer: LocalAdjustmentLayer
        if let id = maskInteractionState.selectedLayerID,
            let existing = document.localAdjustments.first(where: { $0.id == id }) {
            layer = existing
        } else if maskInteractionState.activeTool == .linear
                    || maskInteractionState.activeTool == .radial {
            // A drag with a gradient tool is also a creation gesture. Keep the new layer
            // transient until mouse-up so Escape/cancel leaves no empty durable layer behind.
            let source: MaskSource = maskInteractionState.activeTool == .radial
                ? .radial(RadialGradientDefinition(center: clamped,
                                                   horizontalRadius: 0, verticalRadius: 0))
                : .linear(LinearGradientDefinition(
                    zeroStrengthPoint: clamped, fullStrengthPoint: clamped))
            let component = MaskComponent(source: source)
            let newLayer = LocalAdjustmentLayer(
                name: nextMaskName(for: maskInteractionState.activeTool == .radial
                                   ? MaskCreationKind.radial.title : MaskCreationKind.linear.title),
                components: [component])
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
        case .brush, .erase:
            guard case .brush(var definition) = draft.components[componentIndex].source else {
                return
            }
            definition.strokes.append(BrushStroke(
                samples: [BrushSample(point: clamped, pressure: pressure)],
                radius: maskInteractionState.brushRadius,
                feather: maskInteractionState.brushFeather,
                flow: maskInteractionState.brushFlow,
                density: maskInteractionState.brushDensity
            ))
            draft.components[componentIndex].source = .brush(definition)
            if maskInteractionState.activeTool == .erase {
                draft.components[componentIndex].mode = .subtract
            }
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
                let handle = radialHandle ?? .creation
                if handle == .creation {
                    draft.components[componentIndex].source = .radial(
                        RadialGradientDefinition(
                            center: clamped, horizontalRadius: 0, verticalRadius: 0,
                            rotation: current.rotation, feather: current.feather,
                            density: current.density, isInside: current.isInside
                        ))
                }
            }
        default:
            break
        }
        maskInteractionState.beginDraft(draft, at: clamped, sourceSize: sourceSize)
        if maskInteractionState.activeTool == .brush || maskInteractionState.activeTool == .erase {
            maskInteractionState.beginBrushStroke(at: clamped)
        }
        if maskInteractionState.activeTool == .linear {
            let handle = maskInteractionState.linearCreationPending
                ? .creation : (linearHandle ?? .creation)
            maskInteractionState.beginLinearGesture(handle, at: clamped)
            maskInteractionState.consumeLinearCreationPending()
        } else if maskInteractionState.activeTool == .radial {
            let handle = maskInteractionState.radialCreationPending
                ? .creation : (radialHandle ?? .creation)
            maskInteractionState.beginRadialGesture(handle, at: clamped, sourceSize: sourceSize)
            maskInteractionState.consumeRadialCreationPending()
        }
        updateMaskGesture(to: point, modifiers: modifiers)
        beginPreviewInteraction()
    }

    func updateMaskGesture(
        to point: CGPoint, pressure: Double? = nil,
        modifiers: NSEvent.ModifierFlags = NSEvent.modifierFlags
    ) {
        guard var draft = maskInteractionState.draftLayer,
            let componentIndex = draft.targetComponentIndex(
                selected: maskInteractionState.selectedComponentID)
        else { return }
        let clamped = CGPoint(x: min(max(point.x, 0), 1), y: min(max(point.y, 0), 1))
        switch maskInteractionState.activeTool {
        case .brush, .erase:
            guard case .brush(var definition) = draft.components[componentIndex].source else {
                return
            }
            guard let strokeIndex = definition.strokes.indices.last,
                  maskInteractionState.shouldAcceptBrushSample(
                      at: clamped, sourceSize: maskInteractionState.gestureSourceSize,
                      radius: definition.strokes[strokeIndex].radius,
                      currentCount: definition.strokes[strokeIndex].samples.count)
            else { return }
            if !definition.strokes.isEmpty {
                definition.strokes[definition.strokes.count - 1].samples.append(BrushSample(
                    point: clamped, pressure: pressure))
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
            let original = maskInteractionState.gestureStartRadialDefinition ?? current
            let sourceSize = maskInteractionState.gestureSourceSize
            let handle = maskInteractionState.activeRadialHandle ?? .creation
            let shift = modifiers.contains(.shift)
            let option = modifiers.contains(.option)
            let updated: RadialGradientDefinition
            switch handle {
            case .creation:
                let center = maskInteractionState.gestureStartPoint ?? original.center
                let local = RadialGradientMaskMath.localPixelPoint(
                    at: clamped, center: center, rotation: original.rotation,
                    sourceSize: sourceSize)
                let radius = shift ? max(abs(local.x), abs(local.y)) : nil
                updated = RadialGradientDefinition(
                    center: center,
                    horizontalRadius: (radius ?? abs(local.x)) / max(sourceSize.width, 1),
                    verticalRadius: (radius ?? abs(local.y)) / max(sourceSize.height, 1),
                    rotation: original.rotation, feather: original.feather,
                    density: original.density, isInside: original.isInside)
            case .center:
                guard let start = maskInteractionState.gestureStartPoint else { return }
                var moved = original
                moved.center = CGPoint(
                    x: min(max(original.center.x + clamped.x - start.x, 0), 1),
                    y: min(max(original.center.y + clamped.y - start.y, 0), 1))
                updated = moved
            case .horizontalRadius, .verticalRadius, .corner:
                updated = resizedRadial(
                    original, handle: handle, at: clamped, sourceSize: sourceSize,
                    symmetric: option, circle: shift,
                    startPoint: maskInteractionState.gestureStartPoint)
            case .innerBoundary:
                var feathered = original
                let local = RadialGradientMaskMath.localPixelPoint(
                    at: clamped, center: original.center, rotation: original.rotation,
                    sourceSize: sourceSize)
                let outer = max(original.horizontalRadius * sourceSize.width, 0.0001)
                feathered.feather = min(max(1 - abs(local.x) / outer, 0), 1)
                updated = feathered
            case .rotation:
                var rotated = original
                let deltaX = (clamped.x - original.center.x) * max(sourceSize.width, 1)
                let deltaY = (clamped.y - original.center.y) * max(sourceSize.height, 1)
                guard hypot(deltaX, deltaY) > 0.0001 else { return }
                rotated.rotation = atan2(deltaY, deltaX) + .pi / 2
                updated = rotated
            }
            draft.components[componentIndex].source = .radial(updated)
        default:
            break
        }
        maskInteractionState.updateDraft(draft)
    }

    func endMaskGesture() {
        let sourceSize = maskInteractionState.gestureSourceSize
        guard var committed = maskInteractionState.commitDraft() else { return }
        for componentIndex in committed.components.indices {
            guard case .brush(var definition) = committed.components[componentIndex].source else {
                continue
            }
            for strokeIndex in definition.strokes.indices {
                let stroke = definition.strokes[strokeIndex]
                definition.strokes[strokeIndex].samples = BrushMaskMath.resampledAndSimplified(
                    stroke.samples, sourceSize: sourceSize, radius: stroke.radius)
            }
            committed.components[componentIndex].source = .brush(definition)
        }
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

    private func resizedRadial(
        _ original: RadialGradientDefinition,
        handle: MaskInteractionState.RadialHandle,
        at point: CGPoint,
        sourceSize: CGSize,
        symmetric: Bool,
        circle: Bool,
        startPoint: CGPoint?
    ) -> RadialGradientDefinition {
        let width = sourceSize.width.isFinite && sourceSize.width > 0 ? sourceSize.width : 1
        let height = sourceSize.height.isFinite && sourceSize.height > 0 ? sourceSize.height : 1
        let local = RadialGradientMaskMath.localPixelPoint(
            at: point, center: original.center, rotation: original.rotation,
            sourceSize: CGSize(width: width, height: height))
        let startLocal = RadialGradientMaskMath.localPixelPoint(
            at: startPoint ?? original.center, center: original.center,
            rotation: original.rotation, sourceSize: CGSize(width: width, height: height))
        let oldX = max(original.horizontalRadius * width, RadialGradientMaskMath.minimumRadius)
        let oldY = max(original.verticalRadius * height, RadialGradientMaskMath.minimumRadius)
        var centerLocal = CGPoint.zero
        var radiusX = oldX
        var radiusY = oldY

        switch handle {
        case .horizontalRadius:
            let sign = startLocal.x >= 0 ? 1.0 : -1.0
            if symmetric {
                radiusX = max(abs(local.x), RadialGradientMaskMath.minimumRadius)
            } else {
                let opposite = -sign * oldX
                let edge = local.x
                radiusX = max(abs(edge - opposite) * 0.5, RadialGradientMaskMath.minimumRadius)
                centerLocal.x = (edge + opposite) * 0.5
            }
            if circle { radiusY = radiusX }
        case .verticalRadius:
            let sign = startLocal.y >= 0 ? 1.0 : -1.0
            if symmetric {
                radiusY = max(abs(local.y), RadialGradientMaskMath.minimumRadius)
            } else {
                let opposite = -sign * oldY
                let edge = local.y
                radiusY = max(abs(edge - opposite) * 0.5, RadialGradientMaskMath.minimumRadius)
                centerLocal.y = (edge + opposite) * 0.5
            }
            if circle { radiusX = radiusY }
        case .corner:
            let signX = startLocal.x >= 0 ? 1.0 : -1.0
            let signY = startLocal.y >= 0 ? 1.0 : -1.0
            if symmetric {
                radiusX = max(abs(local.x), RadialGradientMaskMath.minimumRadius)
                radiusY = max(abs(local.y), RadialGradientMaskMath.minimumRadius)
            } else {
                let oppositeX = -signX * oldX
                let oppositeY = -signY * oldY
                radiusX = max(abs(local.x - oppositeX) * 0.5,
                              RadialGradientMaskMath.minimumRadius)
                radiusY = max(abs(local.y - oppositeY) * 0.5,
                              RadialGradientMaskMath.minimumRadius)
                centerLocal = CGPoint(
                    x: (local.x + oppositeX) * 0.5,
                    y: (local.y + oppositeY) * 0.5)
            }
            if circle {
                let radius = max(radiusX, radiusY)
                radiusX = radius
                radiusY = radius
            }
        default:
            break
        }

        var result = original
        result.center = RadialGradientMaskMath.normalizedPoint(
            fromLocalPixel: centerLocal, around: original.center,
            rotation: original.rotation, sourceSize: CGSize(width: width, height: height))
        result.horizontalRadius = min(max(radiusX / width, 0), 1)
        result.verticalRadius = min(max(radiusY / height, 0), 1)
        result.center = CGPoint(
            x: min(max(result.center.x, 0), 1), y: min(max(result.center.y, 0), 1))
        return result
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

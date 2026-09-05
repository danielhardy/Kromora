import Combine
import CoreGraphics
import Foundation

/// Pointer-frequency mask state. A draft is committed to `EditDocument` by the owning view model
/// once, on gesture completion; it is never encoded, hashed, or sent through the app-wide model
/// while the pointer is moving.
@MainActor
final class MaskInteractionState: ObservableObject {
    enum Tool: String, CaseIterable, Codable, Sendable {
        case selection, foreground, background, brush, linear, radial
    }

    @Published private(set) var selectedLayerID: UUID?
    @Published private(set) var selectedComponentID: UUID?
    @Published private(set) var activeTool: Tool = .selection
    @Published private(set) var hoverPoint: CGPoint?
    @Published private(set) var draftLayer: LocalAdjustmentLayer?

    var hasDraft: Bool { draftLayer != nil }

    func select(layerID: UUID?, componentID: UUID? = nil) {
        selectedLayerID = layerID
        selectedComponentID = componentID
    }

    func select(componentID: UUID, in layerID: UUID) {
        select(layerID: layerID, componentID: componentID)
    }

    func setTool(_ tool: Tool) { activeTool = tool }
    func updateHoverPoint(_ point: CGPoint?) { hoverPoint = point }
    func beginDraft(_ layer: LocalAdjustmentLayer) { draftLayer = layer }
    func updateDraft(_ layer: LocalAdjustmentLayer) { guard draftLayer != nil else { return }; draftLayer = layer }

    @discardableResult
    func commitDraft() -> LocalAdjustmentLayer? {
        let committed = draftLayer
        draftLayer = nil
        return committed
    }

    func cancelDraft() { draftLayer = nil }
    func resetForSource() {
        selectedLayerID = nil; selectedComponentID = nil; activeTool = .selection
        hoverPoint = nil; draftLayer = nil
    }
}

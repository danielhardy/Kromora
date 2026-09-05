import Combine
import CoreGraphics
import Foundation
import SwiftUI

/// Pointer-frequency mask state. A draft is committed to `EditDocument` by the owning view model
/// once, on gesture completion; it is never encoded, hashed, or sent through the app-wide model
/// while the pointer is moving.
@MainActor
final class MaskInteractionState: ObservableObject {
    enum Tool: String, CaseIterable, Codable, Sendable {
        case selection, foreground, background, brush, linear, radial

        var title: String {
            switch self {
            case .selection: return "Select"
            case .foreground: return "Foreground"
            case .background: return "Background"
            case .brush: return "Brush"
            case .linear: return "Linear"
            case .radial: return "Radial"
            }
        }

        var iconName: String {
            switch self {
            case .selection: return "cursorarrow"
            case .foreground: return "person.crop.square"
            case .background: return "photo"
            case .brush: return "paintbrush"
            case .linear: return "line.diagonal"
            case .radial: return "oval"
            }
        }
    }

    enum OverlayInspection: String, CaseIterable, Sendable {
        case colorWash, grayscale

        var title: String {
            switch self {
            case .colorWash: return "Color wash"
            case .grayscale: return "Grayscale"
            }
        }
    }

    @Published private(set) var selectedLayerID: UUID?
    @Published private(set) var selectedComponentID: UUID?
    @Published private(set) var activeTool: Tool = .selection
    @Published private(set) var hoverPoint: CGPoint?
    @Published private(set) var draftLayer: LocalAdjustmentLayer?

    // Presentation-only controls. These values intentionally never enter EditDocument, history,
    // or a render request; they describe how the photographer is inspecting the saved recipe.
    @Published var showOverlay = true
    @Published var overlayInspection: OverlayInspection = .colorWash
    @Published var overlayColor: Color = .orange
    @Published var overlayOpacity: Double = 0.35
    @Published private(set) var soloLayerID: UUID?

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
    func updateDraft(_ layer: LocalAdjustmentLayer) {
        guard draftLayer != nil else { return }
        draftLayer = layer
    }

    @discardableResult
    func commitDraft() -> LocalAdjustmentLayer? {
        let committed = draftLayer
        draftLayer = nil
        return committed
    }

    func cancelDraft() { draftLayer = nil }

    func toggleSolo(layerID: UUID) {
        soloLayerID = soloLayerID == layerID ? nil : layerID
    }

    func clearSolo() { soloLayerID = nil }

    func resetForSource() {
        selectedLayerID = nil
        selectedComponentID = nil
        activeTool = .selection
        hoverPoint = nil
        draftLayer = nil
        soloLayerID = nil
    }
}

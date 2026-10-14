import Observation
import CoreGraphics
import Foundation

/// Pointer-frequency state for the retouch canvas. Drafts and selection never enter the recipe.
@MainActor
@Observable
final class RetouchInteractionState {
    enum OverlayPolicy: String, CaseIterable, Sendable { case auto, always, selected, never
        var title: String { rawValue.capitalized }
    }
    enum Handle: Sendable, Equatable { case destination(UUID), source(UUID), create }

    var mode: RetouchMode = .heal
    var radius = 0.012
    var feather = 0.35
    var opacity = 1.0
    private(set) var isArmed = false
    private(set) var selectedSpotID: UUID?
    private(set) var hoveredSpotID: UUID?
    private(set) var hoverPoint: CGPoint?
    private(set) var activeHandle: Handle?
    private(set) var draftSamples: [BrushSample] = []
    private(set) var draftRadius = 0.012
    private(set) var draftFeather = 0.35
    private(set) var solvingSpotIDs: Set<UUID> = []
    private(set) var shiftClickAnchor: CGPoint?
    var overlayPolicy: OverlayPolicy = .auto
    var visualizationEnabled = false
    var visualizationThreshold = 0.025
    private(set) var dustSuggestions: [RetouchDustSuggestion] = []
    private(set) var visualizationCandidates: [RetouchDustSuggestion] = []
    var isSpacePanning = false

    var hasDraft: Bool { activeHandle != nil && !draftSamples.isEmpty }
    var shouldShowOverlay: Bool {
        switch overlayPolicy {
        case .auto: return isArmed || selectedSpotID != nil || hoveredSpotID != nil
        case .always: return true
        case .selected: return selectedSpotID != nil
        case .never: return false
        }
    }
    func arm() { isArmed = true }
    func setSpacePanning(_ value: Bool) { isSpacePanning = value }
    func disarm() {
        isArmed = false; selectedSpotID = nil; hoveredSpotID = nil; hoverPoint = nil
        activeHandle = nil; draftSamples = []; shiftClickAnchor = nil; solvingSpotIDs = []
        isSpacePanning = false
    }
    /// Clears everything tied to the previously open photo; keeps arming and user preferences.
    func resetPhotoState() {
        selectedSpotID = nil; hoveredSpotID = nil; hoverPoint = nil
        activeHandle = nil; draftSamples = []; shiftClickAnchor = nil; solvingSpotIDs = []
        dustSuggestions = []; visualizationCandidates = []
    }
    func select(_ id: UUID?) { selectedSpotID = id }
    func hover(_ id: UUID?) { hoveredSpotID = id }
    func hover(_ id: UUID?, at point: CGPoint?) { hoveredSpotID = id; hoverPoint = point }
    func setHandle(_ handle: Handle?) { activeHandle = handle }
    func setDraft(_ samples: [BrushSample], radius: Double, feather: Double) {
        draftSamples = Array(samples.prefix(4096)); draftRadius = radius; draftFeather = feather
    }
    func setShiftClickAnchor(_ point: CGPoint?) { shiftClickAnchor = point }
    func setSolving(_ id: UUID, _ solving: Bool) {
        if solving { solvingSpotIDs.insert(id) } else { solvingSpotIDs.remove(id) }
    }
    func clearGesture() { activeHandle = nil; draftSamples = [] }
    func cycleOverlayPolicy() {
        let cases = OverlayPolicy.allCases
        overlayPolicy = cases[(cases.firstIndex(of: overlayPolicy)! + 1) % cases.count]
    }
    func setDustSuggestions(_ suggestions: [RetouchDustSuggestion]) { dustSuggestions = suggestions }
    func setVisualizationCandidates(_ candidates: [RetouchDustSuggestion]) { visualizationCandidates = candidates }
    func removeDustSuggestion(_ id: UUID) { dustSuggestions.removeAll { $0.id == id } }
}

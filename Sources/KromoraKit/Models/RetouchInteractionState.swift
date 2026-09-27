import Combine
import CoreGraphics
import Foundation

/// Pointer-frequency state for the retouch canvas. Drafts and selection never enter the recipe.
@MainActor
final class RetouchInteractionState: ObservableObject {
    @MainActor static weak var active: RetouchInteractionState?
    @MainActor static func reportSolve(_ id: UUID, solving: Bool, failure: String? = nil) {
        guard let active else { return }
        active.setSolving(id, solving)
        active.solveFailures[id] = failure
    }
    enum OverlayPolicy: String, CaseIterable, Sendable { case auto, always, selected, never
        var title: String { rawValue.capitalized }
    }
    enum Handle: Sendable, Equatable { case destination(UUID), source(UUID), create }

    @Published var mode: RetouchMode = .remove
    @Published var radius = 0.012
    @Published var feather = 0.35
    @Published var opacity = 1.0
    @Published private(set) var isArmed = false
    @Published private(set) var selectedSpotID: UUID?
    @Published private(set) var hoveredSpotID: UUID?
    @Published private(set) var hoverPoint: CGPoint?
    @Published private(set) var activeHandle: Handle?
    @Published private(set) var draftSamples: [BrushSample] = []
    @Published private(set) var draftRadius = 0.012
    @Published private(set) var draftFeather = 0.35
    @Published private(set) var solvingSpotIDs: Set<UUID> = []
    @Published private(set) var solveFailures: [UUID: String] = [:]
    @Published private(set) var shiftClickAnchor: CGPoint?
    @Published var overlayPolicy: OverlayPolicy = .auto
    @Published var isSpacePanning = false

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
        activeHandle = nil; draftSamples = []; shiftClickAnchor = nil; solvingSpotIDs = []; solveFailures = [:]
        isSpacePanning = false
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
    func setSolveFailure(_ id: UUID, _ message: String?) { solveFailures[id] = message }
    func clearGesture() { activeHandle = nil; draftSamples = [] }
    func cycleOverlayPolicy() {
        let cases = OverlayPolicy.allCases
        overlayPolicy = cases[(cases.firstIndex(of: overlayPolicy)! + 1) % cases.count]
    }
}

import Combine
import CoreGraphics
import Foundation

/// Platform-neutral color payload for the mask overlay controls. SwiftUI's `Color` is reconstructed
/// by `MaskInteractionPresentationBridge` at the presentation boundary.
struct MaskOverlayColor: Codable, Equatable, Sendable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    static let orange = Self(red: 1, green: 0.5, blue: 0, alpha: 1)
}

/// How the mask overlay looks on screen. It is a preference, not part of any edit: it lives in
/// Settings, applies to every photo, and never reaches a render request or export.
struct MaskOverlayAppearance: Codable, Equatable, Sendable {
    var inspection: MaskInteractionState.OverlayInspection
    var color: MaskOverlayColor
    var opacity: Double

    static let standard = Self(inspection: .colorWash, color: .orange, opacity: 0.35)

    init(
        inspection: MaskInteractionState.OverlayInspection, color: MaskOverlayColor,
        opacity: Double
    ) {
        self.inspection = inspection
        self.color = color
        self.opacity = opacity.isFinite ? min(max(opacity, 0), 1) : Self.standardOpacity
    }

    private static let standardOpacity = 0.35
}

/// Presentation state for the selected semantic mask. An empty result is different from an
/// unavailable result: the former is a valid analysis with zero coverage, while the latter means
/// the component could not be evaluated and must not quietly look like a successful no-op.
enum MaskResolutionState: Equatable, Sendable {
    case idle
    case loading
    case ready
    case empty
    case unavailable(String)
    case failed(String)

    var message: String? {
        switch self {
        case .idle, .ready: return nil
        case .loading: return "Analyzing the selected mask…"
        case .empty: return "Analysis completed, but this mask contains no covered pixels."
        case .unavailable(let message), .failed(let message): return message
        }
    }
}

/// Pointer-frequency mask state. A draft is committed to `EditDocument` by the owning view model
/// once, on gesture completion; it is never encoded, hashed, or sent through the app-wide model
/// while the pointer is moving.
@MainActor
final class MaskInteractionState: ObservableObject {
    /// What a drag on the canvas does. Smart masks (subject, background, …) are not tools: they
    /// are created from the Add Mask menu and never respond to the pointer, so they do not appear
    /// here where they would capture the canvas without acting on it.
    enum Tool: String, CaseIterable, Codable, Sendable {
        case selection, brush, erase, linear, radial

        var title: String {
            switch self {
            case .selection: return "Select"
            case .brush: return "Brush"
            case .erase: return "Erase"
            case .linear: return "Linear"
            case .radial: return "Radial"
            }
        }

        var iconName: String {
            switch self {
            case .selection: return "cursorarrow"
            case .brush: return "paintbrush"
            case .erase: return "eraser"
            case .linear: return "line.diagonal"
            case .radial: return "oval"
            }
        }

        var helpText: String {
            switch self {
            case .selection: return "Select — leave the canvas free to pan and zoom (Esc)"
            case .brush: return "Brush — paint to add to the selected mask (B)"
            case .erase: return "Erase — paint to remove from the selected mask (E)"
            case .linear: return "Linear gradient — drag on the canvas to draw one (L)"
            case .radial: return "Radial gradient — drag on the canvas to draw one (R)"
            }
        }
    }

    enum OverlayInspection: String, CaseIterable, Codable, Sendable {
        case colorWash, grayscale

        var title: String {
            switch self {
            case .colorWash: return "Color wash"
            case .grayscale: return "Grayscale"
            }
        }
    }

    enum LinearHandle: String, Sendable, Equatable {
        case zeroStrength
        case center
        case fullStrength
        case rotation
        case creation

        var accessibilityTitle: String {
            switch self {
            case .zeroStrength: return "zero-strength edge"
            case .center: return "center translation"
            case .fullStrength: return "full-strength edge"
            case .rotation: return "rotation"
            case .creation: return "creation"
            }
        }
    }

    enum RadialHandle: String, Sendable, Equatable {
        case center
        case horizontalRadius
        case verticalRadius
        case corner
        case innerBoundary
        case rotation
        case creation
    }

    @Published private(set) var selectedLayerID: UUID?
    @Published private(set) var selectedComponentID: UUID?
    @Published private(set) var activeTool: Tool = .selection
    @Published private(set) var hoverPoint: CGPoint?
    @Published private(set) var draftLayer: LocalAdjustmentLayer?
    @Published private(set) var activeLinearHandle: LinearHandle?
    @Published private(set) var hoveredLinearHandle: LinearHandle?
    @Published private(set) var activeRadialHandle: RadialHandle?
    @Published private(set) var linearCreationPending = false
    @Published private(set) var radialCreationPending = false
    @Published private(set) var resolutionState: MaskResolutionState = .idle
    /// Monotonic generation forcing mask overlay tasks to re-resolve without disturbing the
    /// selection. Retry must heal a cold store by warming signals and then re-running the
    /// overlay task, but warming alone changes none of the task's inputs — without this the
    /// `.task(id:)` never restarts and the banner it was meant to clear persists.
    @Published private(set) var maskResolveEpoch: UInt64 = 0
    /// Transient controls used by the active brush. They are copied into a stroke at begin time;
    /// changing a slider never mutates the document or the in-progress stroke retroactively.
    @Published var brushRadius = BrushMaskMath.defaultRadius
    @Published var brushFeather = BrushMaskMath.defaultFeather
    @Published var brushFlow = BrushMaskMath.defaultFlow
    @Published var brushDensity = BrushMaskMath.defaultDensity
    @Published private(set) var isSpacePanning = false
    private(set) var gestureStartPoint: CGPoint?
    private(set) var gestureStartDefinition: LinearGradientDefinition?
    private(set) var gestureStartRadialDefinition: RadialGradientDefinition?
    private(set) var gestureSourceSize: CGSize = CGSize(width: 1, height: 1)
    private var brushLastRawPoint: CGPoint?
    private var brushLastRawPressure: Double?
    private var brushDistanceSinceAcceptedSample = 0.0
    private let maximumLiveBrushSamples = 4_096
    private var selectionBeforePendingCreationLayerID: UUID?
    private var selectionBeforePendingCreationComponentID: UUID?

    // Presentation-only controls. These values intentionally never enter EditDocument, history,
    // or a render request; they describe how the photographer is inspecting the saved recipe.
    @Published var showOverlay = true
    @Published var overlayInspection: OverlayInspection = .colorWash
    @Published var overlayColorValue: MaskOverlayColor = .orange
    @Published var overlayOpacity: Double = 0.35
    @Published private(set) var soloLayerID: UUID?
    @Published private(set) var soloComponentID: UUID?

    var hasDraft: Bool { draftLayer != nil }

    func select(layerID: UUID?, componentID: UUID? = nil) {
        let selectionChanged = selectedLayerID != layerID || selectedComponentID != componentID
        selectedLayerID = layerID
        selectedComponentID = componentID
        if selectionChanged {
            linearCreationPending = false
            radialCreationPending = false
            hoveredLinearHandle = nil
            resolutionState = .idle
        }
    }

    func select(componentID: UUID, in layerID: UUID) {
        select(layerID: layerID, componentID: componentID)
    }

    func setTool(_ tool: Tool) { activeTool = tool }
    func setSpacePanning(_ isPanning: Bool) { isSpacePanning = isPanning }

    func beginBrushStroke(at point: CGPoint, pressure: Double?) {
        brushLastRawPoint = point
        brushLastRawPressure = pressure
        brushDistanceSinceAcceptedSample = 0
    }

    /// Interpolate native event endpoints at the same physical spacing used by the durable
    /// recipe. This makes a low-frequency event stream paint continuously instead of relying on
    /// the operating system to have delivered enough intermediate mouse events.
    func brushSamples(
        to point: CGPoint, pressure: Double?, sourceSize: CGSize, radius: Double,
        currentCount: Int
    ) -> [BrushSample] {
        guard let previous = brushLastRawPoint else {
            brushLastRawPoint = point
            brushLastRawPressure = pressure
            return []
        }
        let available = maximumLiveBrushSamples - currentCount
        guard available > 0 else {
            brushLastRawPoint = point
            brushLastRawPressure = pressure
            return []
        }
        let samples = BrushMaskMath.interpolatedSamples(
            from: BrushSample(point: previous, pressure: brushLastRawPressure),
            to: BrushSample(point: point, pressure: pressure), sourceSize: sourceSize,
            spacing: BrushMaskMath.samplingSpacing(sourceSize: sourceSize, radius: radius),
            carry: &brushDistanceSinceAcceptedSample, maximumCount: available)
        brushLastRawPoint = point
        brushLastRawPressure = pressure
        return samples
    }

    /// Preserve the tail shorter than one sampling interval before durable simplification. The
    /// renderer then never leaves a visible unpainted gap at mouse-up.
    func finishBrushStroke(currentCount: Int) -> BrushSample? {
        guard currentCount < maximumLiveBrushSamples,
              let point = brushLastRawPoint else { return nil }
        return BrushSample(point: point, pressure: brushLastRawPressure)
    }

    func adjustBrushRadius(by delta: Double) {
        brushRadius = min(max(brushRadius + delta, 0.001), 1)
    }

    /// Proportional resize for continuous input (Option-scroll), so each step feels the same at
    /// any brush size. Bounded like the Size slider.
    func scaleBrushRadius(by factor: Double) {
        guard factor.isFinite, factor > 0 else { return }
        brushRadius = min(max(brushRadius * factor, 0.001), 0.5)
    }

    func adjustBrushFeather(by delta: Double) {
        brushFeather = min(max(brushFeather + delta, 0), 1)
    }
    func updateHoverPoint(_ point: CGPoint?) { hoverPoint = point }

    func beginMaskResolution() { resolutionState = .loading }
    func markMaskResolved() { resolutionState = .ready }
    /// Request a fresh overlay resolution pass, e.g. after Retry warmed the signals backing
    /// the selected semantic mask.
    func requestMaskReResolve() { maskResolveEpoch &+= 1 }
    func markMaskEmpty() { resolutionState = .empty }
    func markMaskUnavailable(_ message: String) { resolutionState = .unavailable(message) }
    func markMaskFailed(_ message: String) { resolutionState = .failed(message) }

    func beginDraft(
        _ layer: LocalAdjustmentLayer, at point: CGPoint? = nil,
        sourceSize: CGSize = CGSize(width: 1, height: 1)
    ) {
        draftLayer = layer
        gestureStartPoint = point
        gestureSourceSize = sourceSize
        if let componentID = selectedComponentID,
            let component = layer.components.first(where: { $0.id == componentID }),
            case .linear(let definition) = component.source {
            gestureStartDefinition = definition
        } else {
            gestureStartDefinition = nil
        }
        if let componentID = selectedComponentID,
            let component = layer.components.first(where: { $0.id == componentID }),
            case .radial(let definition) = component.source {
            gestureStartRadialDefinition = definition
        } else {
            gestureStartRadialDefinition = nil
        }
    }

    /// Install a gradient layer as presentation-only state. The layer becomes selected immediately
    /// so the inspector and canvas can describe the pending operation, but it is not part of the
    /// durable document until the first valid creation drag is committed by the view model.
    func beginPendingCreation(_ layer: LocalAdjustmentLayer, tool: Tool) {
        selectionBeforePendingCreationLayerID = selectedLayerID
        selectionBeforePendingCreationComponentID = selectedComponentID
        cancelDraft()
        draftLayer = layer
        selectedLayerID = layer.id
        selectedComponentID = layer.components.first?.id
        activeTool = tool
        linearCreationPending = tool == .linear
        radialCreationPending = tool == .radial
        hoveredLinearHandle = nil
    }

    /// A gradient drag that starts a new layer records the prior selection the same way a pending
    /// creation does, so cancelling the transient layer hands selection back.
    func rememberSelectionBeforeCreation() {
        selectionBeforePendingCreationLayerID = selectedLayerID
        selectionBeforePendingCreationComponentID = selectedComponentID
    }

    var selectionBeforePendingCreation: (layerID: UUID?, componentID: UUID?) {
        (selectionBeforePendingCreationLayerID, selectionBeforePendingCreationComponentID)
    }

    func clearPendingCreationSelection() {
        selectionBeforePendingCreationLayerID = nil
        selectionBeforePendingCreationComponentID = nil
    }
    func updateDraft(_ layer: LocalAdjustmentLayer) {
        guard draftLayer != nil else { return }
        draftLayer = layer
    }

    @discardableResult
    func commitDraft() -> LocalAdjustmentLayer? {
        let committed = draftLayer
        clearPendingCreationSelection()
        draftLayer = nil
        activeLinearHandle = nil
        activeRadialHandle = nil
        gestureStartPoint = nil
        gestureStartDefinition = nil
        gestureStartRadialDefinition = nil
        gestureSourceSize = CGSize(width: 1, height: 1)
        brushLastRawPoint = nil
        brushLastRawPressure = nil
        brushDistanceSinceAcceptedSample = 0
        return committed
    }

    func cancelDraft() {
        draftLayer = nil
        activeLinearHandle = nil
        activeRadialHandle = nil
        gestureStartPoint = nil
        gestureStartDefinition = nil
        gestureStartRadialDefinition = nil
        gestureSourceSize = CGSize(width: 1, height: 1)
        brushLastRawPoint = nil
        brushLastRawPressure = nil
        brushDistanceSinceAcceptedSample = 0
    }

    func beginLinearGesture(_ handle: LinearHandle, at point: CGPoint) {
        activeLinearHandle = handle
        gestureStartPoint = point
    }

    func updateLinearHover(_ handle: LinearHandle?) {
        hoveredLinearHandle = handle
    }

    func beginRadialGesture(
        _ handle: RadialHandle, at point: CGPoint, sourceSize: CGSize
    ) {
        activeRadialHandle = handle
        gestureStartPoint = point
        gestureSourceSize = sourceSize
    }

    func markLinearCreationPending() { linearCreationPending = true }
    func consumeLinearCreationPending() { linearCreationPending = false }
    func markRadialCreationPending() { radialCreationPending = true }
    func consumeRadialCreationPending() { radialCreationPending = false }

    /// Adopt the overlay appearance chosen in Settings.
    func apply(_ appearance: MaskOverlayAppearance) {
        overlayInspection = appearance.inspection
        overlayColorValue = appearance.color
        overlayOpacity = appearance.opacity
    }

    func toggleOverlay() { showOverlay.toggle() }

    func toggleSolo(layerID: UUID) {
        soloLayerID = soloLayerID == layerID ? nil : layerID
        soloComponentID = nil
    }

    func toggleSolo(componentID: UUID, layerID: UUID? = nil) {
        if soloComponentID == componentID {
            soloComponentID = nil
            soloLayerID = nil
        } else {
            soloComponentID = componentID
            soloLayerID = layerID
        }
    }

    func clearSolo() {
        soloLayerID = nil
        soloComponentID = nil
    }

    func resetForSource() {
        selectedLayerID = nil
        selectedComponentID = nil
        activeTool = .selection
        hoverPoint = nil
        draftLayer = nil
        activeLinearHandle = nil
        hoveredLinearHandle = nil
        activeRadialHandle = nil
        linearCreationPending = false
        radialCreationPending = false
        gestureStartPoint = nil
        gestureStartDefinition = nil
        gestureStartRadialDefinition = nil
        gestureSourceSize = CGSize(width: 1, height: 1)
        brushLastRawPoint = nil
        brushLastRawPressure = nil
        brushDistanceSinceAcceptedSample = 0
        soloLayerID = nil
        soloComponentID = nil
        resolutionState = .idle
        isSpacePanning = false
        clearPendingCreationSelection()
    }
}

import AppKit
import CoreGraphics
import Foundation
import SwiftUI

/// The creation actions exposed by the persistent masking workspace. A layer is created with a
/// durable recipe immediately; semantic pixels and other render resources remain derived state.
enum MaskCreationKind: String, CaseIterable, Sendable {
    case subject, person, face, foreground, background, brush, erase, linear, radial

    static let smartKinds: [MaskCreationKind] = [.subject, .person, .face, .foreground, .background]

    var isSmart: Bool { semanticTarget != nil }

    var semanticTarget: SemanticTarget? {
        switch self {
        case .subject: return .subject
        case .person: return .person
        case .face: return .face
        case .foreground: return .foreground
        case .background: return .background
        case .brush, .erase, .linear, .radial: return nil
        }
    }

    var title: String {
        switch self {
        case .subject: return "Subject"
        case .person: return "Person"
        case .face: return "Face"
        case .foreground: return "Foreground"
        case .background: return "Background"
        case .brush: return "Brush"
        case .erase: return "Erase Brush"
        case .linear: return "Linear Gradient"
        case .radial: return "Radial Gradient"
        }
    }
}

/// Identifies the exact smart-mask operation that can be retried after provider failure. A
/// component add must retain its destination layer and combine mode; retrying only the semantic
/// kind could accidentally create a new top-level layer or fall back to a preview retry.
enum SmartMaskRetryContext: Sendable, Equatable {
    case create(MaskCreationKind)
    case addComponent(layerID: UUID, kind: MaskCreationKind, mode: MaskCombineMode)
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

private extension SemanticMaskKind {
    var infoEditingTarget: SemanticTarget? {
        switch self {
        case .subject: return .subject
        case .person: return .person
        default: return nil
        }
    }

    var infoTitle: String {
        switch self {
        case .subject: return "Subject"
        case .person: return "Person"
        default: return String(describing: self)
        }
    }
}

/// The narrow async analysis boundary the masking workflow needs. `PhotoAnalysisCoordinator`
/// conforms directly; tests inject a fake so smart-mask creation, cancellation, and supersession
/// are exercised without a renderer, a Vision provider, or an `AppViewModel`.
protocol MaskAnalysisProviding: AnyObject, Sendable {
    func analyze(
        assetID: PhotoAssetID, source: ImageSource, level: PhotoAnalysisLevel
    ) async throws -> PhotoAnalysis

    func mask(
        assetID: PhotoAssetID, source: ImageSource, kind: SemanticMaskKind, quality: MaskQuality
    ) async throws -> RegionMask

    func preparePersonSignals(
        assetID: PhotoAssetID, source: ImageSource, quality: MaskQuality
    ) async
}

extension PhotoAnalysisCoordinator: MaskAnalysisProviding {}

/// The application-side seam the masking workflow needs. `AppViewModel` remains the owner of the
/// published `EditDocument`, render scheduling, and inspector chrome; this coordinator only reaches
/// into that state through this protocol, which keeps mask commands testable without constructing
/// `AppViewModel`.
@MainActor
protocol MaskingWorkflowDestination: AnyObject {
    var document: EditDocument { get }
    var hasOpenSource: Bool { get }
    var maskingSource: ImageSource? { get }
    var maskingAssetID: PhotoAssetID? { get }
    var maskingSourceRevision: UInt64 { get }
    var maskOverlaySource: ImageSource? { get }
    var maskOverlayEngine: any RenderEngining { get }

    func updateDocument(_ transform: (inout EditDocument) -> Void)
    func setMaskingStatusMessage(_ message: String)
    func endUndoGrouping()
    func beginPreviewInteraction()
    func endPreviewInteraction()
    func retryPreview()
    func presentMaskingWorkspace()
    func dismissMaskingWorkspace()
}

/// Owns the persistent masking workspace: layer/component selection, transient creation gestures,
/// and smart-mask analysis requests (invocation, cancellation, retry).
///
/// The durable `EditDocument` and its history remain owned by `AppViewModel` — a masking command
/// commits through `MaskingWorkflowDestination.updateDocument`, which gives it the normal
/// persistence/undo/copy-paste path automatically, the same as any other document mutation.
/// Selection and transient-gesture state live in `MaskInteractionState`, an `@Observable` object
/// this coordinator owns so masking UI can bind to it directly without routing through
/// `AppViewModel`'s wider publisher.
@MainActor
final class MaskingWorkflowCoordinator {
    let interactionState = MaskInteractionState()

    private var smartMaskCreationTask: Task<Void, Never>?
    private(set) var smartMaskRetryContext: SmartMaskRetryContext?
    private var personSignalWarmingTask: Task<Void, Never>?

    private let analysis: any MaskAnalysisProviding
    weak var destination: (any MaskingWorkflowDestination)?

    init(analysis: any MaskAnalysisProviding, destination: (any MaskingWorkflowDestination)? = nil) {
        self.analysis = analysis
        self.destination = destination
    }

    /// Cancel any in-flight smart-mask request without a retry offer. Used when the active source
    /// is about to change: a stale analysis result must never land on the next photo.
    func cancelInFlightSmartMask() {
        smartMaskCreationTask?.cancel()
        smartMaskCreationTask = nil
        smartMaskRetryContext = nil
    }

    /// Await completion of the current smart-mask request, if any. Widened to internal (rather
    /// than kept private) so tests can observe cancellation/supersession completion deterministically
    /// instead of polling — same precedent as `RecipeExtractor.buildCube`.
    func waitForInFlightSmartMask() async {
        await smartMaskCreationTask?.value
    }

    /// Cancel in-flight work and wait for it to quiesce. Called once, from `AppViewModel.shutdown`.
    func shutdown() async {
        personSignalWarmingTask?.cancel()
        smartMaskCreationTask?.cancel()
        await personSignalWarmingTask?.value
        await smartMaskCreationTask?.value
        personSignalWarmingTask = nil
        smartMaskCreationTask = nil
        smartMaskRetryContext = nil
    }

    /// Turn a validated result already shown by the Info inspector into the durable semantic
    /// recipe used by the masking workspace. The result is intentionally passed in from the Info
    /// model: the inspector must not start a second, debug-only inference path. Render and export
    /// continue to resolve the saved recipe through `PhotoAnalysisCoordinator`.
    func useInfoAnalysisMask(
        _ kind: SemanticMaskKind,
        demonstrated result: RegionMask,
        pixels: NormalizedMask
    ) {
        guard let destination else { return }
        guard let target = kind.infoEditingTarget,
              let source = destination.maskingSource,
              let assetID = destination.maskingAssetID else {
            let message = "\(kind.infoTitle) mask is unavailable because no supported photo is open."
            interactionState.markMaskUnavailable(message)
            destination.setMaskingStatusMessage(message)
            return
        }

        guard result.kind == kind,
              result.reference.cacheKey.identity.assetID
                == PortablePhotoAssetID.compatibility(from: assetID),
              result.reference.cacheKey.identity.sourceFingerprint
                .matches(source.cacheIdentity.sourceFingerprint),
              result.reference.quality == result.quality,
              result.reference.cacheKey.kind == kind,
              pixels.size == result.reference.size,
              pixels.coverage > 0,
              MaskPresentationPolicy.decision(for: result) == .actionable else {
            let message = "The demonstrated \(kind.infoTitle) result is no longer available for this photo."
            interactionState.markMaskUnavailable(message)
            destination.setMaskingStatusMessage(message)
            return
        }

        smartMaskCreationTask?.cancel()
        smartMaskCreationTask = nil
        smartMaskRetryContext = nil
        if interactionState.hasDraft {
            cancelMaskGesture()
        } else {
            destination.endUndoGrouping()
        }

        let existing = destination.document.localAdjustments.first { layer in
            layer.components.contains { component in
                component.source.semanticDefinition?.target == target
            }
        }
        let layerID: UUID
        let componentID: UUID
        if let existing,
           let component = existing.components.first(where: {
               $0.source.semanticDefinition?.target == target
           }) {
            layerID = existing.id
            componentID = component.id
            destination.setMaskingStatusMessage("Selected \(kind.infoTitle) mask")
        } else {
            let component = MaskComponent(
                source: .semantic(SemanticMaskDefinition(target: target))
            )
            let layer = LocalAdjustmentLayer(
                name: nextMaskName(for: kind.infoTitle, in: destination), components: [component]
            )
            layerID = layer.id
            componentID = component.id
            destination.updateDocument { $0.localAdjustments.append(layer) }
            destination.setMaskingStatusMessage("Created \(kind.infoTitle) editing mask")
        }

        interactionState.setTool(.selection)
        interactionState.select(componentID: componentID, in: layerID)
        interactionState.markMaskResolved()
        openMaskingWorkspace()
    }

    /// The preview coordinator intentionally reports only a failed render, not Core Image or
    /// provider errors. Recover the user-facing semantic context from the request so an unavailable
    /// smart mask cannot be presented as a generic, unexplained preview failure.
    func semanticMaskFailureMessage(for document: EditDocument) -> String? {
        guard let selectedLayerID = interactionState.selectedLayerID,
              let layer = document.localAdjustments.first(where: { $0.id == selectedLayerID }),
              let component = layer.components.first(where: { component in
                  guard component.id == interactionState.selectedComponentID,
                        component.isEnabled else { return false }
                  if case .semantic = component.source { return true }
                  return false
              }) ?? layer.components.first(where: { component in
                  guard component.isEnabled else { return false }
                  if case .semantic = component.source { return true }
                  return false
              }), case .semantic(let definition) = component.source else { return nil }
        return "The \(definition.target.rawValue) mask could not be analyzed for this photo. "
            + "Retry mask analysis or choose another photo."
    }

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
        guard let destination, let source = destination.maskOverlaySource else { return nil }
        return await destination.maskOverlayEngine.makeMaskOverlayImage(MaskOverlayRequest(
            source: source,
            assetID: destination.maskingAssetID,
            layers: layers,
            selectedLayerID: selectedLayerID,
            soloLayerID: soloLayerID,
            targetSize: targetSize,
            transform: transform,
            style: style,
            // The overlay is exempt from mask-request revision supersession: previews note
            // displayRevision, which grows without bound and shares one max-slot per source
            // with the overlay's sourceRevision — after the first couple of preview renders
            // every overlay resolve was cancelled forever, for every mask type (LUMO-275).
            // Staleness stays owned by the workspace `.task(id:)` teardown, which restarts on
            // any layer/selection/size/style change; revision 0 skips noting and always
            // reads current.
            requestRevision: 0,
            selectedComponentID: selectedComponentID,
            soloComponentID: soloComponentID
        ))
    }

    func openMaskingWorkspace() {
        guard let destination, destination.hasOpenSource, destination.maskingAssetID != nil else {
            return
        }
        destination.endUndoGrouping()
        if destination.document.localAdjustments.isEmpty {
            interactionState.select(layerID: nil)
        } else if interactionState.selectedLayerID == nil {
            restoreMaskSelection()
        }
        destination.presentMaskingWorkspace()
    }

    func selectMaskLayer(_ id: UUID?) {
        if let draftID = interactionState.draftLayer?.id, draftID != id {
            cancelMaskGesture()
        }
        guard let id, let destination,
              destination.document.localAdjustments.contains(where: { $0.id == id }) else {
            interactionState.select(layerID: nil)
            return
        }
        interactionState.select(layerID: id)
    }

    func selectMaskComponent(_ componentID: UUID, in layerID: UUID) {
        if let draftID = interactionState.draftLayer?.id, draftID != layerID {
            cancelMaskGesture()
        }
        guard let destination,
            destination.document.localAdjustments.contains(where: {
                $0.id == layerID && $0.components.contains(where: { $0.id == componentID })
            })
        else { return }
        interactionState.select(componentID: componentID, in: layerID)
    }

    func createMask(_ kind: MaskCreationKind) {
        guard let destination else { return }
        if interactionState.hasDraft {
            cancelMaskGesture()
        } else {
            destination.endUndoGrouping()
        }
        // “Add Erase Brush” augments the selected layer when one exists. A subtract component
        // only has meaning relative to prior coverage, so placing it in a separate empty layer
        // would silently erase nothing. Keep the no-selection path below for callers that are
        // explicitly creating a standalone recipe.
        if kind == .erase,
           let layerID = interactionState.selectedLayerID,
           destination.document.localAdjustments.contains(where: { $0.id == layerID }) {
            addMaskComponent(
                to: layerID, source: .brush(BrushMaskDefinition()), mode: .subtract)
            interactionState.setTool(.erase)
            destination.setMaskingStatusMessage("Added Erase Brush to selected mask")
            return
        }
        let source: MaskSource
        switch kind {
        case .subject:
            source = .semantic(SemanticMaskDefinition(target: .subject))
        case .person:
            source = .semantic(SemanticMaskDefinition(target: .person))
        case .face:
            source = .semantic(SemanticMaskDefinition(target: .face))
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
        let name = nextMaskName(for: kind.title, in: destination)

        // Gradient creation is intentionally a two-stage operation. Keep the layer out of the
        // document while the photographer is deciding whether/how to drag it; this makes Escape,
        // a tool switch, and a cancelled click leave the document and its history untouched.
        if kind == .linear {
            interactionState.beginPendingCreation(
                LocalAdjustmentLayer(
                    id: layerID, name: name,
                    components: [MaskComponent(
                        id: component.id, mode: .replace, source: source
                    )]
                ),
                tool: .linear
            )
            destination.setMaskingStatusMessage("Drag across the canvas to create \(name)")
            return
        }

        destination.updateDocument { document in
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
        // Smart masks have no canvas tool; returning to Select keeps the canvas navigable.
        interactionState.setTool(MaskInteractionState.Tool(rawValue: kind.rawValue) ?? .selection)
        interactionState.select(componentID: component.id, in: layerID)
        if kind == .linear {
            interactionState.markLinearCreationPending()
        } else if kind == .radial {
            interactionState.markRadialCreationPending()
        }
        destination.setMaskingStatusMessage("Created \(name)")
    }

    /// Preflight a smart-mask request through the shared analysis coordinator before committing
    /// the recipe. A durable semantic component is only added after the provider returns a
    /// validated result, so an unsupported source cannot leave a layer that renders as a no-op.
    func createSmartMask(_ kind: MaskCreationKind) {
        guard let target = kind.semanticTarget else {
            createMask(kind)
            return
        }
        guard let destination else { return }
        smartMaskCreationTask?.cancel()
        smartMaskCreationTask = nil
        smartMaskRetryContext = .create(kind)
        if interactionState.hasDraft {
            cancelMaskGesture()
        } else {
            destination.endUndoGrouping()
        }
        guard let source = destination.maskingSource, let assetID = destination.maskingAssetID else {
            let message = "Smart masks require an open photo with supported analysis."
            interactionState.markMaskUnavailable(message)
            destination.setMaskingStatusMessage(message)
            return
        }
        let sourceRevision = destination.maskingSourceRevision
        let sourceFingerprint = source.cacheFingerprint
        let coordinator = analysis
        interactionState.beginMaskResolution()
        destination.setMaskingStatusMessage("Analyzing \(kind.title) mask…")
        smartMaskCreationTask = Task { @MainActor [weak self] in
            do {
                // Person segmentation is deliberately gated by the shared provider. Detailed
                // analysis establishes the face/foreground signal without exposing diagnostics.
                // That preflight can short-circuit on the disk analysis cache without
                // repopulating the mask store, so establish the gate signals explicitly: cheap
                // cache hits when warm, Vision-backed computation when cold.
                if target == .person {
                    if (try? await coordinator.analyze(
                        assetID: assetID, source: source, level: .detailed)) != nil {
                        self?.destination?.setMaskingStatusMessage(
                            "Initial photo analysis is ready; refining the Person mask…")
                    }
                    await coordinator.preparePersonSignals(
                        assetID: assetID, source: source, quality: .preview
                    )
                }
                let mask = try await coordinator.mask(
                    assetID: assetID, source: source,
                    kind: target.semanticMaskKind, quality: .preview
                )
                try Task.checkCancellation()
                guard let self, let destination = self.destination,
                      destination.maskingSourceRevision == sourceRevision,
                      destination.maskingSource?.cacheFingerprint == sourceFingerprint,
                      destination.maskingAssetID == assetID else { return }
                switch MaskPresentationPolicy.decision(for: mask) {
                case .actionable:
                    break
                case .empty:
                    self.interactionState.markMaskEmpty()
                    destination.setMaskingStatusMessage("The \(kind.title) mask contains no usable region.")
                    return
                case .lowConfidence:
                    let message = MaskPresentationPolicy.Decision.lowConfidence.userMessage
                        ?? "The \(kind.title) mask is unavailable for this photo."
                    self.interactionState.markMaskUnavailable(message)
                    destination.setMaskingStatusMessage(message)
                    return
                }
                self.insertDurableMask(kind, destination: destination)
                self.smartMaskRetryContext = nil
                self.interactionState.markMaskResolved()
                destination.setMaskingStatusMessage("Created \(kind.title) mask")
            } catch is CancellationError {
                return
            } catch {
                guard let self, let destination = self.destination,
                      destination.maskingSourceRevision == sourceRevision,
                      destination.maskingSource?.cacheFingerprint == sourceFingerprint,
                      destination.maskingAssetID == assetID else { return }
                let message = self.userFacingSmartMaskError(error, target: target)
                self.interactionState.markMaskUnavailable(message)
                destination.setMaskingStatusMessage(message)
            }
        }
    }

    private func insertDurableMask(_ kind: MaskCreationKind, destination: any MaskingWorkflowDestination) {
        guard let target = kind.semanticTarget else { return }
        let source = MaskSource.semantic(SemanticMaskDefinition(target: target))
        let layerID = UUID()
        let component = MaskComponent(source: source)
        let name = nextMaskName(for: kind.title, in: destination)
        destination.updateDocument { document in
            document.localAdjustments.append(LocalAdjustmentLayer(
                id: layerID, name: name, components: [component]
            ))
        }
        interactionState.setTool(.selection)
        interactionState.select(componentID: component.id, in: layerID)
    }

    private func userFacingSmartMaskError(_ error: Error, target: SemanticTarget) -> String {
        if let localized = error as? LocalizedError, let description = localized.errorDescription,
           !description.isEmpty {
            return "\(target.rawValue.capitalized) mask unavailable: \(description)."
        }
        return "The \(target.rawValue) mask is unavailable for this photo. Try another photo or retry."
    }

    func retryMaskAnalysis() {
        switch smartMaskRetryContext {
        case .create(let kind):
            createSmartMask(kind)
        case .addComponent(let layerID, let kind, let mode):
            addSmartMaskComponent(to: layerID, kind: kind, mode: mode)
        case nil:
            // A bare re-render cannot heal a cold mask store: with no warmed signals the
            // overlay fails identically, forever. Warm explicit person requests first, then
            // force the overlay task to re-resolve through the epoch below.
            interactionState.beginMaskResolution()
            if selectedSemanticTarget == .person {
                personSignalWarmingTask?.cancel()
                personSignalWarmingTask = Task { [weak self] in
                    await self?.warmPersonSignals()
                    guard !Task.isCancelled else { return }
                    await MainActor.run { self?.interactionState.requestMaskReResolve() }
                }
            }
            destination?.retryPreview()
        }
    }

    /// The overlay's selected semantic target, if the selection names an enabled semantic
    /// component (falling back to the layer's first enabled component, like gestures do).
    var selectedSemanticTarget: SemanticTarget? {
        guard let destination, let layerID = interactionState.selectedLayerID,
              let layer = destination.document.localAdjustments.first(where: { $0.id == layerID })
        else { return nil }
        let componentID = interactionState.selectedComponentID
        let component = componentID.flatMap { id in
            layer.components.first(where: { $0.id == id && $0.isEnabled })
        } ?? layer.components.first(where: { $0.isEnabled })
        guard let component, case .semantic(let definition) = component.source else { return nil }
        return definition.target
    }

    /// Establish the person gate signals for the open photo at overlay quality. Cheap cache
    /// hits when warm, Vision-backed computation when cold. Only meaningful for explicit
    /// person requests — the provider gate stays cache-only for speculative callers.
    func warmPersonSignals() async {
        guard let destination, let source = destination.maskingSource,
              let assetID = destination.maskingAssetID else { return }
        await analysis.preparePersonSignals(
            assetID: assetID, source: source, quality: .preview
        )
    }

    func duplicateMask(_ id: UUID) {
        guard let destination,
              let index = destination.document.localAdjustments.firstIndex(where: { $0.id == id })
        else { return }
        var copy = destination.document.localAdjustments[index]
        copy.id = UUID()
        copy.name = nextMaskName(for: "\(copy.name) Copy", in: destination)
        copy.components = copy.components.map { component in
            var component = component
            component.id = UUID()
            if case .brush(let brush) = component.source {
                component.source = .brush(brush)
            }
            return component
        }
        destination.updateDocument { $0.localAdjustments.insert(copy, at: index + 1) }
        interactionState.select(layerID: copy.id, componentID: copy.components.first?.id)
    }

    func renameMask(_ id: UUID, name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        updateMask(id) { $0.name = String(trimmed.prefix(80)) }
    }

    func deleteMask(_ id: UUID) {
        guard let destination,
              let index = destination.document.localAdjustments.firstIndex(where: { $0.id == id })
        else { return }
        let nextID =
            destination.document.localAdjustments.dropFirst(index + 1).first?.id
            ?? destination.document.localAdjustments.dropLast(
                max(0, destination.document.localAdjustments.count - index)
            ).last?.id
        destination.updateDocument { $0.localAdjustments.remove(at: index) }
        interactionState.select(layerID: nextID)
        interactionState.clearSolo()
    }

    func moveMask(_ id: UUID, by offset: Int) {
        guard let destination,
              let index = destination.document.localAdjustments.firstIndex(where: { $0.id == id })
        else { return }
        let destinationIndex = min(
            max(index + offset, 0), destination.document.localAdjustments.count - 1)
        guard destinationIndex != index else { return }
        destination.updateDocument { document in
            let moved = document.localAdjustments.remove(at: index)
            document.localAdjustments.insert(moved, at: destinationIndex)
        }
    }

    func updateMask(
        _ id: UUID, debounced: Bool = false, _ transform: (inout LocalAdjustmentLayer) -> Void
    ) {
        if var draft = interactionState.draftLayer, draft.id == id {
            transform(&draft)
            interactionState.updateDraft(draft)
            return
        }
        destination?.updateDocument { document in
            guard let index = document.localAdjustments.firstIndex(where: { $0.id == id }) else {
                return
            }
            transform(&document.localAdjustments[index])
        }
    }

    /// Value-only access for a local control. Draft layers are included so a control never lags
    /// behind an in-progress mask creation gesture.
    func localAdjustmentValue(
        _ control: LocalAdjustmentControl, in layerID: UUID
    ) -> Double {
        let layer = interactionState.draftLayer?.id == layerID
            ? interactionState.draftLayer
            : destination?.document.localAdjustments.first(where: { $0.id == layerID })
        return control.value(in: layer?.adjustments ?? .neutral)
    }

    /// The local equivalent of the normal inspector bindings. The layer ID is explicit by design:
    /// changing a selected layer must never fall through to `document.adjustments` or another
    /// layer, and the continuous edit path remains debounced for preview and undo consistency.
    func localAdjustmentBinding(
        _ control: LocalAdjustmentControl, in layerID: UUID
    ) -> Binding<Double> {
        Binding(
            get: { self.localAdjustmentValue(control, in: layerID) },
            set: { value in
                self.updateMask(layerID, debounced: true) { layer in
                    control.setting(value, in: &layer.adjustments)
                }
            }
        )
    }

    /// Set one local adjustment to its neutral value without crossing into global state. Like the
    /// global inspector resets, this is discrete and immediate; a preceding slider group is ended
    /// first so the reset gets its own undo entry.
    func resetMaskAdjustment(_ control: LocalAdjustmentControl, in layerID: UUID) {
        destination?.endUndoGrouping()
        updateMask(layerID) { layer in
            control.setting(control.neutral, in: &layer.adjustments)
        }
    }

    func addMaskComponent(to layerID: UUID, source: MaskSource, mode: MaskCombineMode = .add) {
        let componentMode: MaskCombineMode
        if destination?.document.localAdjustments.first(where: { $0.id == layerID })?
            .components.isEmpty ?? true {
            componentMode = .replace
        } else {
            componentMode = mode
        }
        let component = MaskComponent(mode: componentMode, source: source)
        updateMask(layerID) { $0.components.append(component) }
        interactionState.select(componentID: component.id, in: layerID)
    }

    func addMaskComponent(to layerID: UUID, kind: MaskCreationKind, mode: MaskCombineMode) {
        let source: MaskSource
        switch kind {
        case .subject: source = .semantic(SemanticMaskDefinition(target: .subject))
        case .person: source = .semantic(SemanticMaskDefinition(target: .person))
        case .face: source = .semantic(SemanticMaskDefinition(target: .face))
        case .foreground: source = .semantic(SemanticMaskDefinition(target: .foreground))
        case .background: source = .semantic(SemanticMaskDefinition(target: .background))
        case .brush, .erase: source = .brush(BrushMaskDefinition())
        case .linear: source = .linear(LinearGradientDefinition())
        case .radial: source = .radial(RadialGradientDefinition())
        }
        addMaskComponent(to: layerID, source: source, mode: mode)
    }

    /// The component equivalent of `createSmartMask`. Preflight keeps a failed semantic request
    /// from changing an existing layer while still using the same coordinator/cache boundary.
    func addSmartMaskComponent(to layerID: UUID, kind: MaskCreationKind, mode: MaskCombineMode) {
        guard let target = kind.semanticTarget else {
            addMaskComponent(to: layerID, kind: kind, mode: mode)
            return
        }
        guard let destination,
              destination.document.localAdjustments.contains(where: { $0.id == layerID })
        else { return }
        smartMaskCreationTask?.cancel()
        smartMaskRetryContext = .addComponent(layerID: layerID, kind: kind, mode: mode)
        guard let source = destination.maskingSource, let assetID = destination.maskingAssetID else {
            let message = "Smart mask components require an open photo with supported analysis."
            interactionState.markMaskUnavailable(message)
            destination.setMaskingStatusMessage(message)
            return
        }
        let sourceRevision = destination.maskingSourceRevision
        let sourceFingerprint = source.cacheFingerprint
        let coordinator = analysis
        interactionState.beginMaskResolution()
        destination.setMaskingStatusMessage("Analyzing \(kind.title) component…")
        smartMaskCreationTask = Task { @MainActor [weak self] in
            do {
                if target == .person {
                    _ = try? await coordinator.analyze(
                        assetID: assetID, source: source, level: .detailed)
                    await coordinator.preparePersonSignals(
                        assetID: assetID, source: source, quality: .preview
                    )
                }
                let mask = try await coordinator.mask(
                    assetID: assetID, source: source,
                    kind: target.semanticMaskKind, quality: .preview
                )
                try Task.checkCancellation()
                guard let self, let destination = self.destination,
                      destination.maskingSourceRevision == sourceRevision,
                      destination.maskingSource?.cacheFingerprint == sourceFingerprint,
                      destination.maskingAssetID == assetID,
                      destination.document.localAdjustments.contains(where: { $0.id == layerID })
                else { return }
                guard MaskPresentationPolicy.decision(for: mask) == .actionable else {
                    self.interactionState.markMaskUnavailable(
                        "The \(kind.title) mask is unavailable because no usable region was found."
                    )
                    destination.setMaskingStatusMessage(
                        self.interactionState.resolutionState.message ?? "Mask unavailable")
                    return
                }
                self.addMaskComponent(
                    to: layerID,
                    source: .semantic(SemanticMaskDefinition(target: target)), mode: mode)
                self.smartMaskRetryContext = nil
                self.interactionState.markMaskResolved()
                destination.setMaskingStatusMessage("Added \(kind.title) component")
            } catch is CancellationError {
                return
            } catch {
                guard let self, let destination = self.destination,
                      destination.maskingSourceRevision == sourceRevision,
                      destination.maskingSource?.cacheFingerprint == sourceFingerprint else { return }
                let message = self.userFacingSmartMaskError(error, target: target)
                self.interactionState.markMaskUnavailable(message)
                destination.setMaskingStatusMessage(message)
            }
        }
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
            let destinationIndex = min(max(index + offset, 0), layer.components.count - 1)
            guard destinationIndex != index else { return }
            let component = layer.components.remove(at: index)
            layer.components.insert(component, at: destinationIndex)
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
        if interactionState.selectedComponentID == componentID {
            interactionState.select(layerID: layerID)
        }
        if interactionState.soloComponentID == componentID {
            interactionState.clearSolo()
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
        guard let id = interactionState.selectedLayerID else { return }
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
        let selectedLayer: LocalAdjustmentLayer?
        if let draft = interactionState.draftLayer,
            draft.id == interactionState.selectedLayerID
        {
            selectedLayer = draft
        } else {
            selectedLayer = destination?.document.localAdjustments.first(where: {
                $0.id == interactionState.selectedLayerID
            })
        }
        guard let layerID = interactionState.selectedLayerID,
            let componentID = interactionState.selectedComponentID,
            let layer = selectedLayer,
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
        if interactionState.hasDraft {
            if interactionState.activeTool == tool,
                interactionState.linearCreationPending
                    || interactionState.radialCreationPending
            {
                return
            }
            cancelMaskGesture()
        } else {
            destination?.endUndoGrouping()
        }
        interactionState.setTool(tool)
    }

    func beginMaskGesture(
        at point: CGPoint,
        linearHandle: MaskInteractionState.LinearHandle? = nil,
        radialHandle: MaskInteractionState.RadialHandle? = nil,
        sourceSize: CGSize = CGSize(width: 1, height: 1),
        pressure: Double? = nil,
        modifiers: NSEvent.ModifierFlags = []
    ) {
        guard let destination, interactionState.activeTool != .selection else { return }
        let clamped = CGPoint(x: min(max(point.x, 0), 1), y: min(max(point.y, 0), 1))

        let layer: LocalAdjustmentLayer
        if let draft = interactionState.draftLayer,
           draft.id == interactionState.selectedLayerID {
            layer = draft
        } else if let id = interactionState.selectedLayerID,
                  let existing = destination.document.localAdjustments.first(where: { $0.id == id }),
                  gradientToolCanEdit(existing) {
            layer = existing
        } else if interactionState.activeTool == .linear
                    || interactionState.activeTool == .radial {
            // A drag with a gradient tool is also a creation gesture. Keep the new layer
            // transient until mouse-up so Escape/cancel leaves no empty durable layer behind.
            // A selected mask whose target is not this kind of gradient cannot be edited by the
            // drag, so the drag draws a new gradient instead of silently doing nothing; the prior
            // selection is remembered so a click that never becomes a gradient restores it.
            interactionState.rememberSelectionBeforeCreation()
            let source: MaskSource = interactionState.activeTool == .radial
                ? .radial(RadialGradientDefinition(center: clamped,
                                                   horizontalRadius: 0, verticalRadius: 0))
                : .linear(LinearGradientDefinition(
                    zeroStrengthPoint: clamped, fullStrengthPoint: clamped))
            let component = MaskComponent(source: source)
            let newLayer = LocalAdjustmentLayer(
                name: nextMaskName(
                    for: interactionState.activeTool == .radial
                        ? MaskCreationKind.radial.title : MaskCreationKind.linear.title,
                    in: destination),
                components: [component])
            interactionState.select(componentID: component.id, in: newLayer.id)
            layer = newLayer
        } else {
            return
        }
        var draft = layer
        // Painting is always an additive component and erasing is always a subtractive brush
        // component.  Do not mutate a selected analytic or semantic component into a brush: that
        // would discard its resolved coverage.  Instead append the transient brush intent to the
        // same layer so subtract composes against the effective mask when the gesture commits.
        if interactionState.activeTool == .brush || interactionState.activeTool == .erase {
            let selectedIndex = draft.targetComponentIndex(
                selected: interactionState.selectedComponentID)
            let selectedComponent = selectedIndex.map { draft.components[$0] }
            let wantsSubtract = interactionState.activeTool == .erase
            let canReuse = selectedComponent.map { component in
                guard case .brush = component.source else { return false }
                return wantsSubtract ? component.mode == .subtract : component.mode != .subtract
            } ?? false
            if !canReuse {
                let component = MaskComponent(
                    mode: wantsSubtract ? .subtract : .add,
                    source: .brush(BrushMaskDefinition()))
                draft.components.append(component)
                interactionState.select(componentID: component.id, in: draft.id)
            }
        }
        guard let componentIndex = draft.targetComponentIndex(
            selected: interactionState.selectedComponentID)
        else {
            return
        }
        switch interactionState.activeTool {
        case .brush, .erase:
            guard case .brush(var definition) = draft.components[componentIndex].source else {
                return
            }
            definition.strokes.append(BrushStroke(
                samples: [BrushSample(point: clamped, pressure: pressure)],
                radius: interactionState.brushRadius,
                feather: interactionState.brushFeather,
                flow: interactionState.brushFlow,
                density: interactionState.brushDensity
            ))
            draft.components[componentIndex].source = .brush(definition)
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
        interactionState.beginDraft(draft, at: clamped, sourceSize: sourceSize)
        if interactionState.activeTool == .brush || interactionState.activeTool == .erase {
            interactionState.beginBrushStroke(at: clamped, pressure: pressure)
        }
        if interactionState.activeTool == .linear {
            let handle = interactionState.linearCreationPending
                ? .creation : (linearHandle ?? .creation)
            interactionState.beginLinearGesture(handle, at: clamped)
            interactionState.consumeLinearCreationPending()
        } else if interactionState.activeTool == .radial {
            let handle = interactionState.radialCreationPending
                ? .creation : (radialHandle ?? .creation)
            interactionState.beginRadialGesture(handle, at: clamped, sourceSize: sourceSize)
            interactionState.consumeRadialCreationPending()
        }
        updateMaskGesture(to: point, modifiers: modifiers)
        destination.beginPreviewInteraction()
    }

    /// Brush and erase always paint into the selected layer. A gradient tool edits the selected
    /// layer only when its target component is that same gradient; the handles on the canvas
    /// belong to that component, and nothing else in the layer can respond to the drag.
    private func gradientToolCanEdit(_ layer: LocalAdjustmentLayer) -> Bool {
        let tool = interactionState.activeTool
        guard tool == .linear || tool == .radial else { return true }
        guard let index = layer.targetComponentIndex(
            selected: interactionState.selectedComponentID) else { return false }
        switch layer.components[index].source {
        case .linear: return tool == .linear
        case .radial: return tool == .radial
        case .brush, .semantic: return false
        }
    }

    func updateMaskGesture(
        to point: CGPoint, pressure: Double? = nil,
        modifiers: NSEvent.ModifierFlags = NSEvent.modifierFlags,
        sourceDelta: CGPoint? = nil
    ) {
        guard var draft = interactionState.draftLayer,
            let componentIndex = draft.targetComponentIndex(
                selected: interactionState.selectedComponentID)
        else { return }
        let clamped = CGPoint(x: min(max(point.x, 0), 1), y: min(max(point.y, 0), 1))
        switch interactionState.activeTool {
        case .brush, .erase:
            guard case .brush(var definition) = draft.components[componentIndex].source else {
                return
            }
            guard let strokeIndex = definition.strokes.indices.last else { return }
            definition.strokes[strokeIndex].samples.append(contentsOf:
                interactionState.brushSamples(
                    to: clamped, pressure: pressure,
                    sourceSize: interactionState.gestureSourceSize,
                    radius: definition.strokes[strokeIndex].radius,
                    currentCount: definition.strokes[strokeIndex].samples.count))
            draft.components[componentIndex].source = .brush(definition)
        case .linear:
            guard case .linear(let current) = draft.components[componentIndex].source else {
                return
            }
            let handle = interactionState.activeLinearHandle ?? .creation
            let updated: LinearGradientDefinition
            let original = interactionState.gestureStartDefinition ?? current
            switch handle {
            case .zeroStrength:
                updated = LinearGradientMaskMath.endpointEdited(
                    original, edge: .zeroStrength, to: clamped)
            case .fullStrength:
                updated = LinearGradientMaskMath.endpointEdited(
                    original, edge: .fullStrength, to: clamped)
            case .creation:
                updated = LinearGradientDefinition(
                    zeroStrengthPoint: current.zeroStrengthPoint, fullStrengthPoint: clamped,
                    density: current.density)
            case .center:
                guard let start = interactionState.gestureStartPoint,
                    let original = interactionState.gestureStartDefinition else { return }
                updated = LinearGradientMaskMath.translated(
                    original,
                    by: sourceDelta ?? CGPoint(x: clamped.x - start.x, y: clamped.y - start.y))
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
            let original = interactionState.gestureStartRadialDefinition ?? current
            let sourceSize = interactionState.gestureSourceSize
            let handle = interactionState.activeRadialHandle ?? .creation
            let shift = modifiers.contains(.shift)
            let option = modifiers.contains(.option)
            let updated: RadialGradientDefinition
            switch handle {
            case .creation:
                let center = interactionState.gestureStartPoint ?? original.center
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
                guard let start = interactionState.gestureStartPoint else { return }
                var moved = original
                let delta = sourceDelta ?? CGPoint(
                    x: clamped.x - start.x, y: clamped.y - start.y)
                moved.center = CGPoint(
                    x: min(max(original.center.x + delta.x, 0), 1),
                    y: min(max(original.center.y + delta.y, 0), 1))
                updated = moved
            case .horizontalRadius, .verticalRadius, .corner:
                updated = resizedRadial(
                    original, handle: handle, at: clamped, sourceSize: sourceSize,
                    symmetric: option, circle: shift,
                    startPoint: interactionState.gestureStartPoint)
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
        interactionState.updateDraft(draft)
    }

    func endMaskGesture() {
        guard let destination else { return }
        let sourceSize = interactionState.gestureSourceSize
        let activeLinearHandle = interactionState.activeLinearHandle
        if activeLinearHandle == .creation,
            let draft = interactionState.draftLayer,
            let componentIndex = draft.targetComponentIndex(
                selected: interactionState.selectedComponentID),
            case .linear(let definition) = draft.components[componentIndex].source,
            definition.falloff <= 0.000001
        {
            // A click, or a drag that never separated its endpoints, is not a creation. Discard
            // the transient layer (or leave an existing component unchanged) without history.
            cancelMaskGesture()
            return
        }
        guard var committed = interactionState.draftLayer else { return }
        if interactionState.activeTool == .brush || interactionState.activeTool == .erase,
           let componentIndex = committed.targetComponentIndex(
               selected: interactionState.selectedComponentID),
           case .brush(var definition) = committed.components[componentIndex].source,
           let strokeIndex = definition.strokes.indices.last,
           let terminal = interactionState.finishBrushStroke(
               currentCount: definition.strokes[strokeIndex].samples.count),
           definition.strokes[strokeIndex].samples.last != terminal {
            definition.strokes[strokeIndex].samples.append(terminal)
            committed.components[componentIndex].source = .brush(definition)
            interactionState.updateDraft(committed)
        }
        guard let committedDraft = interactionState.commitDraft() else { return }
        committed = committedDraft
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
        if destination.document.localAdjustments.contains(where: { $0.id == committed.id }) {
            updateMask(committed.id) { $0 = committed }
        } else {
            destination.updateDocument { $0.localAdjustments.append(committed) }
        }
        destination.endPreviewInteraction()
    }

    func cancelMaskGesture() {
        guard interactionState.hasDraft, let destination else { return }
        let selectedID = interactionState.selectedLayerID
        let previousSelection = interactionState.selectionBeforePendingCreation
        interactionState.cancelDraft()
        interactionState.clearPendingCreationSelection()
        if let previousLayerID = previousSelection.layerID,
           destination.document.localAdjustments.contains(where: { $0.id == previousLayerID }) {
            let previousComponentID = previousSelection.componentID.flatMap { componentID in
                destination.document.localAdjustments.first(where: { $0.id == previousLayerID })?
                    .components.first(where: { $0.id == componentID && $0.isEnabled })?.id
            }
            interactionState.select(
                layerID: previousLayerID, componentID: previousComponentID)
        } else if let selectedID,
            !destination.document.localAdjustments.contains(where: { $0.id == selectedID }) {
            interactionState.select(layerID: nil)
        }
        destination.endPreviewInteraction()
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
        guard let destination else { return }
        if interactionState.hasDraft {
            return
        }
        guard let first = destination.document.localAdjustments.first else {
            interactionState.select(layerID: nil)
            return
        }
        let selected =
            destination.document.localAdjustments.contains(where: {
                $0.id == interactionState.selectedLayerID
            }) ? interactionState.selectedLayerID : first.id
        let component = selected.flatMap { layerID in
            destination.document.localAdjustments.first(where: { $0.id == layerID })?.components
                .first(where: {
                    $0.id == interactionState.selectedComponentID && $0.isEnabled
                })?.id
        }
        interactionState.select(layerID: selected, componentID: component)
    }

    func closeMaskingWorkspace() {
        if interactionState.hasDraft {
            cancelMaskGesture()
        }
        destination?.dismissMaskingWorkspace()
    }

    private func nextMaskName(for base: String, in destination: any MaskingWorkflowDestination) -> String {
        let existing = Set(destination.document.localAdjustments.map(\.name))
        if !existing.contains(base) { return base }
        var ordinal = 2
        while existing.contains("\(base) \(ordinal)") { ordinal += 1 }
        return "\(base) \(ordinal)"
    }
}

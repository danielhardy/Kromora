import AppKit
import CoreGraphics
import Foundation

@MainActor
protocol RetouchWorkflowDestination: AnyObject {
    var document: EditDocument { get }
    var sourceSize: CGSize { get }
    func updateDocument(_ transform: (inout EditDocument) -> Void)
    func pickRetouchSource(spotID: UUID, rank: Int) async
    func retouchAnalysisProxy() async -> RetouchAnalysisProxy?
    func setRetouchCanvasActive(_ active: Bool)
    func beginUndoGrouping()
    func endUndoGrouping()
}

extension RetouchWorkflowDestination {
    func retouchAnalysisProxy() async -> RetouchAnalysisProxy? { nil }
}

/// Owns transient retouch selection and gestures; each completed pointer action is one document edit.
@MainActor
final class RetouchWorkflowCoordinator {
    enum Gesture: Equatable { case create, move(UUID), source(UUID), suggestion(UUID) }
    let interactionState = RetouchInteractionState()
    weak var destination: (any RetouchWorkflowDestination)?
    private var gesture: Gesture?
    private var startPoint: CGPoint = .zero
    private var startRegion: RetouchRegion?
    private var startSource: RetouchSource?
    private var samples: [BrushSample] = []
    private var manualSourceOffset: CGVector?
    private var pendingRegion: RetouchRegion?
    private var pendingSource: RetouchSource?
    private var isShiftSegment = false
    private var isCommandCreatingSource = false
    private var startSuggestion: RetouchDustSuggestion?
    private var suggestionWasMoved = false
    private var isResizingSuggestion = false
    private var wireRefinementTask: Task<Void, Never>?
    private var wireAnalysisTask: Task<RetouchWireRefiner.Proposal, Error>?

    init(destination: (any RetouchWorkflowDestination)? = nil) {
        self.destination = destination
        RetouchInteractionState.active = interactionState
    }

    func setArmed(_ armed: Bool) {
        if armed {
            interactionState.arm()
        } else {
            cancelGesture()
            interactionState.disarm()
        }
        destination?.setRetouchCanvasActive(armed)
    }

    func beginGesture(at point: CGPoint, pressure: Double? = nil, modifiers: NSEvent.ModifierFlags = []) {
        guard let destination, interactionState.isArmed, normalized(point) else { return }
        startPoint = point
        isShiftSegment = modifiers.contains(.shift)
        isCommandCreatingSource = modifiers.contains(.command)
        if let suggestion = hitSuggestion(point) {
            interactionState.select(nil)
            gesture = .suggestion(suggestion.id)
            startSuggestion = suggestion
            let size = destination.sourceSize
            let distance = hypot((point.x - suggestion.point.x) * size.width,
                                 (point.y - suggestion.point.y) * size.height)
            isResizingSuggestion = distance >= suggestion.radius * min(size.width, size.height) * 0.65
            return
        }
        if modifiers.contains(.option), let hit = hitTest(point, spots: destination.document.retouch.spots) {
            deleteSpot(hit.id); return
        }
        if let sourceHit = destination.document.retouch.spots.reversed().first(where: {
            $0.mode != .remove && $0.source != nil && distance(point, sourcePoint(of: $0)) < max($0.region.radius * 1.5, 0.006)
        }) {
            interactionState.select(sourceHit.id)
            gesture = .source(sourceHit.id); startSource = sourceHit.source
            interactionState.setHandle(.source(sourceHit.id))
            return
        }
        if let hit = hitTest(point, spots: destination.document.retouch.spots) {
            interactionState.select(hit.id)
            if let source = hit.source, hit.mode != .remove,
               distance(point, sourcePoint(of: hit)) < max(hit.region.radius * 1.5, 0.006) {
                gesture = .source(hit.id); startSource = source
                interactionState.setHandle(.source(hit.id))
            } else {
                gesture = .move(hit.id); startRegion = hit.region; startSource = hit.source
                interactionState.setHandle(.destination(hit.id))
            }
            return
        }
        interactionState.select(nil)
        gesture = .create
        interactionState.setHandle(.create)
        let anchor = isShiftSegment ? interactionState.shiftClickAnchor : nil
        samples = anchor.map { [BrushSample(point: $0), BrushSample(point: point, pressure: pressure)] }
            ?? [BrushSample(point: point, pressure: pressure)]
        interactionState.setDraft(samples, radius: interactionState.radius, feather: interactionState.feather)
    }

    func updateGesture(to point: CGPoint, pressure: Double? = nil) {
        guard let destination, let gesture, normalized(point) else { return }
        switch gesture {
        case .create:
            if isCommandCreatingSource {
                pendingSource = .manual(offset: CGVector(dx: point.x - startPoint.x, dy: point.y - startPoint.y))
                return
            }
            if isShiftSegment {
                let anchor = interactionState.shiftClickAnchor ?? startPoint
                samples = [BrushSample(point: anchor), BrushSample(point: point, pressure: pressure)]
            } else {
                if let previous = samples.last,
                   BrushMaskMath.physicalDistance(previous.point, point, sourceSize: destination.sourceSize) >= 0.5,
                   samples.count < 4_096 {
                    samples.append(BrushSample(point: point, pressure: pressure))
                }
            }
            interactionState.setDraft(samples, radius: interactionState.radius, feather: interactionState.feather)
        case .move:
            guard let initial = startRegion else { return }
            var moved = initial
            let dx = point.x - startPoint.x, dy = point.y - startPoint.y
            moved.samples = initial.samples.map { BrushSample(point: CGPoint(x: $0.point.x + dx, y: $0.point.y + dy), pressure: $0.pressure) }
            pendingRegion = moved
            if case .manual(let offset)? = startSource {
                pendingSource = .manual(offset: CGVector(dx: offset.dx - dx, dy: offset.dy - dy))
            }
            interactionState.setDraft(moved.samples, radius: moved.radius, feather: interactionState.feather)
        case .source(let id):
            guard let spot = destination.document.retouch.spots.first(where: { $0.id == id }) else { return }
            let dest = spot.region.samples.first?.point ?? startPoint
            manualSourceOffset = CGVector(dx: point.x - dest.x, dy: point.y - dest.y)
            pendingSource = .manual(offset: manualSourceOffset ?? .zero)
        case .suggestion(let id):
            guard let original = startSuggestion else { return }
            let size = destination.sourceSize
            suggestionWasMoved = hypot((point.x - original.point.x) * size.width,
                                       (point.y - original.point.y) * size.height) > 2
            let radius = isResizingSuggestion
                ? min(0.25, max(0.0005, hypot((point.x - original.point.x) * destination.sourceSize.width,
                                             (point.y - original.point.y) * destination.sourceSize.height)
                                / min(destination.sourceSize.width, destination.sourceSize.height)))
                : original.radius
            let moved = RetouchDustSuggestion(id: original.id, point: isResizingSuggestion ? original.point : point, radius: radius,
                                               confidence: original.confidence, seed: original.seed)
            interactionState.setDustSuggestions(interactionState.dustSuggestions.map { $0.id == id ? moved : $0 })
        }
    }

    func endGesture() {
        guard let destination, let gesture else { return }
        switch gesture {
        case .create:
            guard !samples.isEmpty else { cancelGesture(); return }
            let id = UUID()
            let sourceSamples = BrushMaskMath.resampledAndSimplified(
                samples, sourceSize: destination.sourceSize, radius: interactionState.radius)
            let region = RetouchRegion(samples: sourceSamples, radius: interactionState.radius)
            var spot = RetouchSpot(id: id, mode: interactionState.mode, region: region,
                                   feather: interactionState.feather, opacity: interactionState.opacity)
            if let pendingSource { spot.source = pendingSource }
            if samples.count == 1, pendingSource == nil { spot.source = nil }
            let needsAutoPick = pendingSource == nil && spot.mode != .remove
            if needsAutoPick { destination.beginUndoGrouping() }
            destination.updateDocument { $0.retouch.spots.append(spot) }
            interactionState.select(id)
            interactionState.setShiftClickAnchor(samples.last?.point)
            if needsAutoPick {
                interactionState.setSolving(id, true)
                Task { [weak self] in
                    await destination.pickRetouchSource(spotID: id, rank: 0)
                    self?.interactionState.setSolving(id, false)
                    destination.endUndoGrouping()
                }
            }
        case .move(let id):
            let needsAutoPick: Bool = {
                guard pendingSource == nil,
                      let spot = destination.document.retouch.spots.first(where: { $0.id == id }),
                      spot.mode != .remove,
                      case .auto? = spot.source
                else { return false }
                return true
            }()
            if needsAutoPick { destination.beginUndoGrouping() }
            if let pendingRegion { updateSpot(id) { $0.region = pendingRegion; if let pendingSource { $0.source = pendingSource } } }
            if needsAutoPick {
                interactionState.setSolving(id, true)
                Task { [weak self] in
                    await destination.pickRetouchSource(spotID: id, rank: 0)
                    self?.interactionState.setSolving(id, false)
                    destination.endUndoGrouping()
                }
            }
        case .source(let id):
            if let pendingSource { updateSpot(id) { $0.source = pendingSource } }
        case .suggestion(let id):
            if !suggestionWasMoved { acceptDustSuggestion(id) }
            startSuggestion = nil
        }
        self.gesture = nil; startRegion = nil; startSource = nil; samples = []; manualSourceOffset = nil; pendingRegion = nil; pendingSource = nil; isCommandCreatingSource = false; startSuggestion = nil; suggestionWasMoved = false; isResizingSuggestion = false
        interactionState.clearGesture()
    }

    func cancelGesture() {
        gesture = nil; startRegion = nil; startSource = nil; samples = []; manualSourceOffset = nil; pendingRegion = nil; pendingSource = nil; isCommandCreatingSource = false; startSuggestion = nil; suggestionWasMoved = false; isResizingSuggestion = false
        interactionState.clearGesture()
    }

    func deleteSelected() { if let id = interactionState.selectedSpotID { deleteSpot(id) } }
    func deleteSpot(_ id: UUID) {
        if interactionState.wireProposalSpotID == id { cancelWireRefinement() }
        destination?.updateDocument { $0.retouch.spots.removeAll { $0.id == id } }
        if interactionState.selectedSpotID == id { interactionState.select(nil) }
        if interactionState.shiftClickAnchor != nil { interactionState.setShiftClickAnchor(nil) }
    }
    func refineSelectedSpotToWire() {
        guard let destination, let id = interactionState.selectedSpotID,
              let spot = destination.document.retouch.spots.first(where: { $0.id == id }),
              spot.mode == .remove, spot.region.samples.count >= 2 else { return }
        wireRefinementTask?.cancel()
        interactionState.beginWireRefinement(id)
        let region = spot.region, sourceSize = destination.sourceSize
        wireRefinementTask = Task { [weak self] in
            let proxy = await destination.retouchAnalysisProxy()
            guard !Task.isCancelled else { return }
            guard let proxy else {
                self?.interactionState.failWireRefinement("Wire analysis is unavailable for this source.")
                return
            }
            do {
                let analysisTask = Task.detached(priority: .userInitiated) {
                    try RetouchWireRefiner.refine(
                        region: region, in: proxy, sourceWidth: Int(sourceSize.width),
                        sourceHeight: Int(sourceSize.height), isCancelled: { Task.isCancelled }
                    )
                }
                self?.wireAnalysisTask = analysisTask
                let proposal = try await analysisTask.value
                guard !Task.isCancelled else { return }
                self?.wireAnalysisTask = nil
                self?.interactionState.setWireProposal(proposal)
            } catch is CancellationError {
                self?.wireAnalysisTask = nil
                self?.interactionState.clearWireRefinement()
            } catch RetouchWireRefiner.Failure.cancelled {
                self?.wireAnalysisTask = nil
                self?.interactionState.clearWireRefinement()
            } catch {
                self?.wireAnalysisTask = nil
                self?.interactionState.failWireRefinement("No unambiguous wire ridge was found. The brush region is unchanged.")
            }
        }
    }
    func cancelWireRefinement() {
        wireRefinementTask?.cancel(); wireRefinementTask = nil
        wireAnalysisTask?.cancel(); wireAnalysisTask = nil
        interactionState.clearWireRefinement()
    }
    func acceptWireRefinement() {
        guard let destination, let id = interactionState.wireProposalSpotID,
              let proposal = interactionState.wireProposal,
              let index = destination.document.retouch.spots.firstIndex(where: { $0.id == id }) else { return }
        destination.updateDocument { $0.retouch.spots[index].region = proposal.region }
        interactionState.clearWireRefinement()
    }
    func acceptDustSuggestion(_ id: UUID) {
        guard let suggestion = interactionState.dustSuggestions.first(where: { $0.id == id }) else { return }
        addDustSpot(suggestion)
        interactionState.removeDustSuggestion(id)
    }
    func acceptAllDustSuggestions() {
        let suggestions = interactionState.dustSuggestions
        guard !suggestions.isEmpty else { return }
        destination?.beginUndoGrouping()
        for suggestion in suggestions { addDustSpot(suggestion) }
        destination?.endUndoGrouping()
        interactionState.setDustSuggestions([])
    }
    func dismissDustSuggestion(_ id: UUID) { interactionState.removeDustSuggestion(id) }
    func dismissAllDustSuggestions() { interactionState.setDustSuggestions([]) }
    private func addDustSpot(_ suggestion: RetouchDustSuggestion) {
        let sample = BrushSample(point: suggestion.point)
        let spot = RetouchSpot(id: suggestion.id, mode: .remove,
            region: RetouchRegion(samples: [sample], radius: suggestion.radius), seed: suggestion.seed)
        destination?.updateDocument { $0.retouch.spots.append(spot) }
        interactionState.select(spot.id)
    }
    private func hitSuggestion(_ point: CGPoint) -> RetouchDustSuggestion? {
        let size = destination?.sourceSize ?? CGSize(width: 1, height: 1)
        return interactionState.dustSuggestions.reversed().first { suggestion in
            hypot((point.x - suggestion.point.x) * size.width, (point.y - suggestion.point.y) * size.height)
                <= max(suggestion.radius * min(size.width, size.height) * 1.5, 0.008 * min(size.width, size.height))
        }
    }
    func nextSource() {
        guard let d = destination, let id = interactionState.selectedSpotID,
              let spot = d.document.retouch.spots.first(where: { $0.id == id }) else { return }
        let rank: Int = { if case .auto(_, let r)? = spot.source { return r + 1 }; return 0 }()
        interactionState.setSolving(id, true)
        Task { [weak self] in
            await d.pickRetouchSource(spotID: id, rank: rank)
            self?.interactionState.setSolving(id, false)
        }
    }
    func hover(at point: CGPoint) {
        interactionState.hover(hitTest(point, spots: destination?.document.retouch.spots ?? [])?.id, at: point)
    }
    func hitTest(_ point: CGPoint, spots: [RetouchSpot]) -> RetouchSpot? {
        spots.reversed().first { spot in
            guard let center = spot.region.samples.first?.point else { return false }
            return distance(point, center) <= max(spot.region.radius * 0.25, 0.006)
        }
    }
    private func updateSpot(_ id: UUID, _ change: (inout RetouchSpot) -> Void) {
        destination?.updateDocument { doc in
            guard let index = doc.retouch.spots.firstIndex(where: { $0.id == id }) else { return }
            change(&doc.retouch.spots[index])
        }
    }
    private func sourcePoint(of spot: RetouchSpot) -> CGPoint {
        let p = spot.region.samples.first?.point ?? .zero
        let o = spot.source?.offset ?? .zero
        return CGPoint(x: p.x + o.dx, y: p.y + o.dy)
    }
    private func normalized(_ p: CGPoint) -> Bool { p.x >= 0 && p.x <= 1 && p.y >= 0 && p.y <= 1 }
    private func distance(_ a: CGPoint, _ b: CGPoint) -> Double {
        let size = destination?.sourceSize ?? CGSize(width: 1, height: 1)
        return hypot((a.x-b.x)*size.width, (a.y-b.y)*size.height) / max(min(size.width,size.height),1)
    }
}

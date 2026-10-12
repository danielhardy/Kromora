import AppKit
import CoreGraphics
import Foundation

@MainActor
protocol RetouchWorkflowDestination: AnyObject {
    var document: EditDocument { get }
    var sourceSize: CGSize { get }
    func updateDocument(_ transform: (inout EditDocument) -> Void)
    func pickRetouchSource(spotID: UUID, rank: Int) async
    func setRetouchCanvasActive(_ active: Bool)
    func beginUndoGrouping()
    func endUndoGrouping()
    /// The open photo, or `nil` when none is installed. Analysis results are only valid for it.
    var retouchAnalysisSource: ImageSource? { get }
    func retouchAnalysisProxy(source: ImageSource) async -> RetouchAnalysisProxy?
    func publishRetouchStatus(_ message: String)
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

    // Analysis lifecycle. A generation is bumped to invalidate a request *before* anything is
    // awaited, because cancellation alone cannot stop a cancellation-oblivious proxy provider from
    // returning and publishing. Each lane runs at most one request and holds one replaceable pending one.
    private struct AnalysisRequest {
        let generation: Int
        let epoch: Int
        let source: ImageSource
        let fingerprint: String
        let threshold: Double
    }
    @MainActor private final class Lane {
        let maximum: Int
        var generation = 0
        /// Bumped by invalidation; a loop belonging to an older epoch drains nothing further.
        var epoch = 0
        var runningEpoch: Int?
        var task: Task<Void, Never>?
        var pending: AnalysisRequest?
        init(maximum: Int) { self.maximum = maximum }
    }
    private var isShutDown = false
    private let detectLane = Lane(maximum: 500)
    private let visualizationLane = Lane(maximum: 1_000)
    private let worker: RetouchDustAnalysisWorker
    /// Fingerprint of the photo that owns `interactionState.dustSuggestions`.
    private var suggestionOwner: String?

    init(destination: (any RetouchWorkflowDestination)? = nil,
         worker: RetouchDustAnalysisWorker = RetouchDustAnalysisWorker()) {
        self.destination = destination
        self.worker = worker
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
            $0.source != nil && distance(point, sourcePoint(of: $0)) < max($0.region.radius * 1.5, 0.006)
        }) {
            interactionState.select(sourceHit.id)
            gesture = .source(sourceHit.id); startSource = sourceHit.source
            interactionState.setHandle(.source(sourceHit.id))
            return
        }
        if let hit = hitTest(point, spots: destination.document.retouch.spots) {
            interactionState.select(hit.id)
            if let source = hit.source, distance(point, sourcePoint(of: hit)) < max(hit.region.radius * 1.5, 0.006) {
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
            let needsAutoPick = pendingSource == nil
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
        destination?.updateDocument { $0.retouch.spots.removeAll { $0.id == id } }
        if interactionState.selectedSpotID == id { interactionState.select(nil) }
        if interactionState.shiftClickAnchor != nil { interactionState.setShiftClickAnchor(nil) }
    }
    func acceptDustSuggestion(_ id: UUID) {
        guard suggestionsBelongToCurrentSource() else { return }
        guard let suggestion = interactionState.dustSuggestions.first(where: { $0.id == id }) else { return }
        addDustSpot(suggestion)
        interactionState.removeDustSuggestion(id)
    }
    func acceptAllDustSuggestions() {
        guard suggestionsBelongToCurrentSource() else { return }
        let suggestions = interactionState.dustSuggestions
        guard !suggestions.isEmpty else { return }
        destination?.beginUndoGrouping()
        for suggestion in suggestions { addDustSpot(suggestion) }
        destination?.endUndoGrouping()
        interactionState.setDustSuggestions([])
    }
    func dismissDustSuggestion(_ id: UUID) { interactionState.removeDustSuggestion(id) }
    func dismissAllDustSuggestions() { interactionState.setDustSuggestions([]) }
    /// A stale command must never insert one photo's coordinates into another photo's document.
    private func suggestionsBelongToCurrentSource() -> Bool {
        if interactionState.dustSuggestions.isEmpty { return false }
        if let owner = suggestionOwner, owner == destination?.retouchAnalysisSource?.cacheFingerprint { return true }
        interactionState.setDustSuggestions([])
        suggestionOwner = nil
        return false
    }

    // MARK: Analysis lifecycle

    func detectDust() {
        guard !isShutDown else { return }
        guard let destination, let source = destination.retouchAnalysisSource else {
            invalidate(detectLane)
            destination?.publishRetouchStatus("Dust detection could not analyze this photo")
            return
        }
        submit(source: source, to: detectLane)
    }

    /// Publishes suggestions together with the photo that owns them.
    func install(_ suggestions: [RetouchDustSuggestion], owner: String) {
        suggestionOwner = owner
        interactionState.setDustSuggestions(suggestions)
    }

    func toggleVisualization() {
        interactionState.visualizationEnabled.toggle()
        refreshVisualization()
    }

    func setVisualizationThreshold(_ threshold: Double) {
        interactionState.visualizationThreshold = min(0.12, max(0.005, threshold))
        guard interactionState.visualizationEnabled else { return }
        refreshVisualization()
    }

    private func refreshVisualization() {
        guard !isShutDown, interactionState.visualizationEnabled,
              let source = destination?.retouchAnalysisSource else {
            invalidate(visualizationLane)
            interactionState.setVisualizationCandidates([])
            return
        }
        submit(source: source, to: visualizationLane)
    }

    /// Latest request wins: it replaces any pending one, and starts a drain loop only when none is alive
    /// for the current epoch. A loop that outlives an invalidation is awaited, never run concurrently.
    private func submit(source: ImageSource, to lane: Lane) {
        lane.generation &+= 1
        lane.pending = AnalysisRequest(generation: lane.generation, epoch: lane.epoch, source: source,
                                       fingerprint: source.cacheFingerprint,
                                       threshold: interactionState.visualizationThreshold)
        guard lane.runningEpoch != lane.epoch else { return }
        let epoch = lane.epoch
        let previous = lane.task
        lane.runningEpoch = epoch
        lane.task = Task { [weak self] in
            await previous?.value
            while let self, lane.epoch == epoch, let request = lane.pending {
                lane.pending = nil
                await self.run(request, in: lane)
            }
            if lane.runningEpoch == epoch { lane.runningEpoch = nil }
        }
    }

    private func invalidate(_ lane: Lane) {
        lane.generation &+= 1
        lane.epoch &+= 1
        lane.pending = nil
        lane.task?.cancel()
    }

    private func run(_ request: AnalysisRequest, in lane: Lane) async {
        guard let destination, isLive(request, in: lane) else { return }
        let isDetect = lane === detectLane
        if !(await worker.hasAnalysis(for: request.fingerprint)) {
            let proxy = await destination.retouchAnalysisProxy(source: request.source)
            // A superseded request on the same photo still builds the shared analysis for its successor.
            guard isLive(request, in: lane) else { return }
            guard let proxy else {
                if isCurrent(request, in: lane) {
                    if isDetect { destination.publishRetouchStatus("Dust detection could not analyze this photo") }
                    else { interactionState.setVisualizationCandidates([]) }
                }
                return
            }
            guard await worker.prepare(key: request.fingerprint, proxy: proxy) else { return }
        }
        guard isCurrent(request, in: lane) else { return }
        let found = await worker.select(key: request.fingerprint, threshold: request.threshold, maximum: lane.maximum)
        guard isCurrent(request, in: lane), let found else { return }
        if isDetect {
            install(found, owner: request.fingerprint)
            destination.publishRetouchStatus("Found \(found.count) dust suggestions")
        } else {
            interactionState.setVisualizationCandidates(found)
        }
    }

    /// The request still targets the open photo in a live epoch, even if a newer request supersedes it.
    private func isLive(_ request: AnalysisRequest, in lane: Lane) -> Bool {
        !isShutDown && request.epoch == lane.epoch
            && destination?.retouchAnalysisSource?.cacheFingerprint == request.fingerprint
    }

    private func isCurrent(_ request: AnalysisRequest, in lane: Lane) -> Bool {
        isLive(request, in: lane) && request.generation == lane.generation
            && (lane !== visualizationLane || interactionState.visualizationEnabled)
    }

    /// The open photo changed or was removed: drop everything that belonged to the previous one.
    /// User preferences (threshold, overlay policy, visualization toggle) are preserved.
    func activeSourceDidChange() {
        invalidateAnalysis()
        cancelGesture()
        interactionState.resetPhotoState()
        if destination?.retouchAnalysisSource == nil { Task { [worker] in await worker.reset() } }
        if !isShutDown { refreshVisualization() }
    }

    func shutdown() async {
        isShutDown = true
        invalidateAnalysis()
        cancelGesture()
        interactionState.resetPhotoState()
        interactionState.setVisualizationCandidates([])
        // Each loop chains after its predecessor, so the latest task covers all owned work.
        await detectLane.task?.value
        await visualizationLane.task?.value
        await worker.reset()
    }

    private func invalidateAnalysis() {
        invalidate(detectLane)
        invalidate(visualizationLane)
        suggestionOwner = nil
    }

    private func addDustSpot(_ suggestion: RetouchDustSuggestion) {
        let sample = BrushSample(point: suggestion.point)
        let spot = RetouchSpot(id: suggestion.id, mode: .heal,
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

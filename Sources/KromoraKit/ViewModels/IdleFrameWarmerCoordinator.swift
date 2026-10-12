import AppKit
import CoreGraphics
import CoreImage
import Foundation

struct IdleFrameWarmerConditions: Sendable, Equatable {
    let isLowPowerModeEnabled: Bool
    let isThermalStateSeriousOrWorse: Bool
    let isApplicationActive: Bool

    var permitsWork: Bool {
        !isLowPowerModeEnabled && !isThermalStateSeriousOrWorse && isApplicationActive
    }
}

struct IdleFrameWarmerProgress: Sendable, Equatable {
    let done: Int
    let remaining: Int

    static let zero = Self(done: 0, remaining: 0)
}

struct IdleFrameWarmCandidate: Sendable {
    let index: Int
    let assetID: PhotoAssetID
    let source: ImageSource
    let reference: EditSourceReference
    let inMemoryDocument: EditDocument?
    let inMemoryLookSignature: LookSignature?
    let distanceFromViewport: Int
    let launchHintRecencyRank: Int

    var identity: PortablePhotoIdentity { source.cacheIdentity }
}

/// Immutable inputs for ranking the library once, off the main actor.
struct IdleFrameWarmPlanInput: Sendable {
    let controller: LibraryQueryController
    let anchorIDs: Set<PortablePhotoAssetID>
    let fallbackSelection: Int
    let recencyOrder: [PortablePhotoAssetID]
    /// The destination's index generation when the input was captured.
    let generation: UInt64
}

/// One lightweight ranked slot: no asset, source, or record is materialized for it.
struct IdleFrameWarmPlanEntry: Sendable, Equatable {
    let assetID: PortablePhotoAssetID
    let index: Int
    let distanceFromViewport: Int
    let launchHintRecencyRank: Int
}

typealias IdleFrameWarmPlanProvider = @Sendable (IdleFrameWarmPlanInput) async -> [IdleFrameWarmPlanEntry]

enum IdleFrameWarmPlanner {
    /// Orders the whole library once by viewport distance, launch-hint recency, then stable
    /// index position, and runs that work off the main actor.
    static let detached: IdleFrameWarmPlanProvider = { input in
        let task = Task.detached(priority: .background) { rank(input) }
        return await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
    }

    static func rank(_ input: IdleFrameWarmPlanInput) -> [IdleFrameWarmPlanEntry] {
        let ids = input.controller.orderedAssetIDs()
        // Keep the first position of a repeated ID rather than trapping on a duplicate key.
        var positions: [PortablePhotoAssetID: Int] = [:]
        positions.reserveCapacity(ids.count)
        for (offset, id) in ids.enumerated() where positions[id] == nil { positions[id] = offset }
        let anchors = input.anchorIDs.compactMap { positions[$0] }.sorted()
        let fallback = min(max(input.fallbackSelection, 0), max(ids.count - 1, 0))
        var recency: [PortablePhotoAssetID: Int] = [:]
        for (offset, id) in input.recencyOrder.enumerated() where recency[id] == nil {
            recency[id] = offset
        }
        var entries: [IdleFrameWarmPlanEntry] = []
        entries.reserveCapacity(positions.count)
        for (offset, id) in ids.enumerated() where positions[id] == offset {
            entries.append(IdleFrameWarmPlanEntry(
                assetID: id, index: offset,
                distanceFromViewport: nearestDistance(to: offset, in: anchors)
                    ?? abs(offset - fallback),
                launchHintRecencyRank: recency[id] ?? Int.max
            ))
        }
        return entries.sorted {
            if $0.distanceFromViewport != $1.distanceFromViewport {
                return $0.distanceFromViewport < $1.distanceFromViewport
            }
            if $0.launchHintRecencyRank != $1.launchHintRecencyRank {
                return $0.launchHintRecencyRank < $1.launchHintRecencyRank
            }
            return $0.index < $1.index
        }
    }

    private static func nearestDistance(to position: Int, in sorted: [Int]) -> Int? {
        guard !sorted.isEmpty else { return nil }
        var low = 0, high = sorted.count
        while low < high {
            let mid = (low + high) / 2
            if sorted[mid] < position { low = mid + 1 } else { high = mid }
        }
        var best = Int.max
        if low < sorted.count { best = sorted[low] - position }
        if low > 0 { best = min(best, position - sorted[low - 1]) }
        return best
    }
}

@MainActor
protocol IdleFrameWarmerDestination: AnyObject {
    var idleFrameWarmerIsReady: Bool { get }
    var idleFrameWarmerIsBlocked: Bool { get }
    var idleFrameWarmerConditions: IdleFrameWarmerConditions { get }
    /// An immutable snapshot for ranking, or nil when there is no library to warm.
    func idleFrameWarmerPlanInput() -> IdleFrameWarmPlanInput?
    /// Whether a plan captured at `generation` still matches the published library.
    func idleFrameWarmerPlanIsCurrent(generation: UInt64) -> Bool
    /// Materializes one bounded page of ranked entries; ineligible or removed assets are omitted.
    func idleFrameWarmerCandidates(for entries: [IdleFrameWarmPlanEntry]) -> [IdleFrameWarmCandidate]
    var idleFrameWarmerActivePortableAssetID: PortablePhotoAssetID? { get }
    var idleFrameWarmerVisiblePortableAssetIDs: Set<PortablePhotoAssetID> { get }
    func idleFrameWarmerSavedLookSignature(for assetID: PhotoAssetID) -> LookSignature?
    func idleFrameWarmerResolvedLUT(_ id: LUTID?) -> CubeLUT?
    func idleFrameWarmerCanonicalRequest(
        source: ImageSource, assetID: PhotoAssetID, document: EditDocument, lut: CubeLUT?
    ) -> RenderRequest
}

/// Sequentially fills the three persisted presentation tiers for package photos. Cache metadata
/// decides which pixels are missing before any source decode or render is requested.
@MainActor
final class IdleFrameWarmerCoordinator {
    enum PhotoOutcome: Sendable, Equatable {
        case completed
        case capacityReached
        case cancelled
    }

    @MainActor
    private final class PhotoCompletion {
        private var outcome: PhotoOutcome = .cancelled
        private var continuation: CheckedContinuation<PhotoOutcome, Never>?

        init(_ continuation: CheckedContinuation<PhotoOutcome, Never>) {
            self.continuation = continuation
        }

        func set(_ outcome: PhotoOutcome) { self.outcome = outcome }

        func finish() {
            guard let continuation else { return }
            self.continuation = nil
            continuation.resume(returning: outcome)
        }
    }

    let jobID = ImageWorkScheduler.JobID("idle-preview-build")

    private let scheduler: ImageWorkScheduler
    private let engine: any RenderEngining
    private let editStore: EditDocumentStore
    private let thumbnailStore: ThumbnailFrameStore
    private let previewPresentation: PreviewPresentationCoordinator
    private let originalDecodeObserver: (@Sendable () async -> Void)?
    private let idleDelay: Duration
    private let notificationCenter: NotificationCenter
    private let planProvider: IdleFrameWarmPlanProvider
    private let pageSize: Int
    private weak var destination: (any IdleFrameWarmerDestination)?
    private var idleTask: Task<Void, Never>?
    private var generation: UInt64 = 0
    private var inFlightPhotoCount = 0
    private var photoCompletionWaiters: [CheckedContinuation<Void, Never>] = []
    private var environmentObservers: [NSObjectProtocol] = []
    private(set) var progress = IdleFrameWarmerProgress.zero

    init(
        scheduler: ImageWorkScheduler,
        engine: any RenderEngining,
        editStore: EditDocumentStore,
        thumbnailStore: ThumbnailFrameStore,
        previewPresentation: PreviewPresentationCoordinator,
        originalDecodeObserver: (@Sendable () async -> Void)? = nil,
        idleDelay: Duration = .milliseconds(1500),
        notificationCenter: NotificationCenter = .default,
        observesSystemChanges: Bool = true,
        planProvider: @escaping IdleFrameWarmPlanProvider = IdleFrameWarmPlanner.detached,
        pageSize: Int = 24,
        destination: (any IdleFrameWarmerDestination)? = nil
    ) {
        self.scheduler = scheduler
        self.engine = engine
        self.editStore = editStore
        self.thumbnailStore = thumbnailStore
        self.previewPresentation = previewPresentation
        self.originalDecodeObserver = originalDecodeObserver
        self.idleDelay = idleDelay
        self.notificationCenter = notificationCenter
        self.destination = destination
        self.planProvider = planProvider
        self.pageSize = max(1, pageSize)
        if observesSystemChanges { observeSystemChanges() }
    }

    func schedule() {
        guard idleTask == nil, canStartNow else { return }
        generation &+= 1
        let scheduledGeneration = generation
        idleTask = Task { [weak self] in
            guard let self else { return }
            do { try await Task.sleep(for: self.idleDelay) } catch { return }
            await self.run(generation: scheduledGeneration)
            if self.generation == scheduledGeneration { self.idleTask = nil }
        }
    }

    func cancel(resetProgress: Bool = false) {
        generation &+= 1
        idleTask?.cancel()
        idleTask = nil
        scheduler.cancel(id: jobID, pump: false)
        if resetProgress { progress = .zero }
    }

    func shutdown() async {
        let task = idleTask
        cancel(resetProgress: true)
        for observer in environmentObservers { notificationCenter.removeObserver(observer) }
        environmentObservers.removeAll()
        await task?.value
        await waitForPhotoWorkToFinish()
        destination = nil
    }

    private var canStartNow: Bool {
        guard let destination, destination.idleFrameWarmerIsReady,
              !destination.idleFrameWarmerIsBlocked,
              destination.idleFrameWarmerConditions.permitsWork else { return false }
        return true
    }

    private func run(generation scheduledGeneration: UInt64) async {
        guard canContinue(generation: scheduledGeneration), let destination else { return }
        await waitForPhotoWorkToFinish()
        guard canContinue(generation: scheduledGeneration) else { return }
        await waitForEditorLane(generation: scheduledGeneration)
        guard canContinue(generation: scheduledGeneration) else { return }

        // A membership change while planning or paging abandons the snapshot; replan a bounded
        // number of times so a steady stream of mutations cannot spin the warmer.
        for _ in 0..<Self.maximumPlanAttempts {
            guard await warmPlan(destination: destination, generation: scheduledGeneration) == .stale
            else { return }
        }
    }

    private enum PlanOutcome { case finished, stale }

    private static let maximumPlanAttempts = 4

    private func warmPlan(
        destination: any IdleFrameWarmerDestination, generation scheduledGeneration: UInt64
    ) async -> PlanOutcome {
        guard let input = destination.idleFrameWarmerPlanInput() else { return .finished }
        let plan = await planProvider(input)
        guard canContinue(generation: scheduledGeneration) else { return .finished }
        guard destination.idleFrameWarmerPlanIsCurrent(generation: input.generation) else {
            return .stale
        }
        progress = IdleFrameWarmerProgress(done: 0, remaining: plan.count)
        guard !plan.isEmpty else { return .finished }
        await previewPresentation.setPinnedFrameAssets(pinnedAssetIDs(for: destination))

        var pageStart = 0
        while pageStart < plan.count {
            guard canContinue(generation: scheduledGeneration) else { return .finished }
            guard destination.idleFrameWarmerPlanIsCurrent(generation: input.generation) else {
                return .stale
            }
            let slice = Array(plan[pageStart..<min(plan.count, pageStart + pageSize)])
            pageStart += slice.count
            let candidates = destination.idleFrameWarmerCandidates(for: slice)
            let skipped = slice.count - candidates.count
            progress = IdleFrameWarmerProgress(
                done: progress.done, remaining: max(0, progress.remaining - skipped)
            )
            for candidate in candidates {
                await waitForEditorLane(generation: scheduledGeneration)
                guard canContinue(generation: scheduledGeneration) else { return .finished }
                guard destination.idleFrameWarmerPlanIsCurrent(generation: input.generation)
                else { return .stale }
                let outcome = await withCheckedContinuation {
                    (continuation: CheckedContinuation<PhotoOutcome, Never>) in
                    let completion = PhotoCompletion(continuation)
                    _ = scheduler.enqueue(
                        id: jobID, lane: .editor, priority: .background,
                        onTerminal: { _ in completion.finish() }
                    ) { [weak self] in
                        guard let self else { return }
                        let outcome = await self.performOnePhoto(
                            candidate, generation: scheduledGeneration
                        )
                        completion.set(outcome)
                    }
                }
                guard canContinue(generation: scheduledGeneration) else { return .finished }
                if outcome == .capacityReached { return .finished }
                guard outcome == .completed else { return .finished }
                progress = IdleFrameWarmerProgress(
                    done: progress.done + 1,
                    remaining: max(0, progress.remaining - 1)
                )
            }
        }
        return .finished
    }

    private func performOnePhoto(
        _ candidate: IdleFrameWarmCandidate, generation scheduledGeneration: UInt64
    ) async -> PhotoOutcome {
        inFlightPhotoCount += 1
        defer {
            inFlightPhotoCount -= 1
            if inFlightPhotoCount == 0 {
                let waiters = photoCompletionWaiters
                photoCompletionWaiters.removeAll(keepingCapacity: true)
                for waiter in waiters { waiter.resume() }
            }
        }
        return await warm(candidate, generation: scheduledGeneration)
    }

    private func warm(
        _ candidate: IdleFrameWarmCandidate, generation scheduledGeneration: UInt64
    ) async -> PhotoOutcome {
        guard canContinue(generation: scheduledGeneration),
              !candidate.identity.sourceFingerprint.isBrowsingPlaceholder else {
            return .completed
        }
        let loaded: EditDocumentLoadResult
        if let document = candidate.inMemoryDocument {
            loaded = EditDocumentLoadResult(
                document: document, found: true, status: .ready,
                lookSignature: candidate.inMemoryLookSignature ?? .none
            )
        } else {
            loaded = await editStore.load(for: candidate.reference)
        }
        guard canContinue(generation: scheduledGeneration) else { return .cancelled }
        guard loaded.isUsableForPrefetch else { return .completed }

        let document = loaded.document
        let savedLook: LookSignature? = candidate.inMemoryLookSignature ?? loaded.lookSignature
        let lut = destination?.idleFrameWarmerResolvedLUT(document.lut.lutID)
        let renderLook = LookSignature(settings: document.lut, resolved: lut)
        let hasSavedLookReference = savedLook?.permitsExactReuse == true
            && savedLook?.lutID == document.lut.lutID
        guard renderLook.permitsExactReuse || hasSavedLookReference else { return .completed }
        let storedLook: LookSignature = renderLook.permitsExactReuse
            ? renderLook
            : (savedLook?.lutID == document.lut.lutID ? (savedLook ?? renderLook) : renderLook)
        let mayRenderEditedPixels = renderLook.permitsExactReuse

        let originalMetadata = await thumbnailStore.metadata(.original, for: candidate.identity)
        let originalIsExact = originalMetadata.map {
            FrameClassifier.classify(
                $0, against: OriginalThumbnailSignature.currentInputs(for: candidate.identity)
            ) == .exact
        } ?? false

        let editedRequired = !document.isIdentity
        let editedMetadata = editedRequired
            ? await thumbnailStore.metadata(.edited, for: candidate.identity) : nil
        let editedIsExact = !editedRequired || editedMetadata.map {
            FrameClassifier.classify(
                $0,
                against: FrameCurrentInputs(
                    source: candidate.identity, editHash: document.editHash,
                    look: storedLook, workingSpace: .current
                )
            ) == .exact
        } == true

        let previewRequest: RenderRequest? = storedLook.permitsExactReuse
            ? destination?.idleFrameWarmerCanonicalRequest(
                source: candidate.source, assetID: candidate.assetID,
                document: document, lut: lut
            ) : nil
        let previewIsExact: Bool
        if let previewRequest {
            previewIsExact = await previewPresentation.storedFrameIsExact(
                for: previewRequest, savedLookSignature: savedLook
            )
        } else {
            previewIsExact = false
        }

        guard canContinue(generation: scheduledGeneration) else { return .cancelled }
        if !previewIsExact, mayRenderEditedPixels,
           !(await previewPresentation.store.isBelowWarmingLowWaterMark())
        {
            return .capacityReached
        }

        if !originalIsExact {
            guard let image = await makeOriginalThumbnail(for: candidate),
                  canContinue(generation: scheduledGeneration) else {
                return canContinue(generation: scheduledGeneration) ? .completed : .cancelled
            }
            let identity = candidate.identity
            let frame = await Task.detached {
                ThumbnailFrameEncoder.originalFrame(image: image, identity: identity)
            }.value
            guard canContinue(generation: scheduledGeneration) else { return .cancelled }
            if let frame { await thumbnailStore.enqueueWrite(frame) }
        }

        if !editedRequired {
            if editedMetadata != nil, canContinue(generation: scheduledGeneration) {
                await thumbnailStore.remove(.edited, for: candidate.identity.assetID)
            }
        } else if !editedIsExact, mayRenderEditedPixels,
                  canContinue(generation: scheduledGeneration)
        {
            guard canContinue(generation: scheduledGeneration) else { return .cancelled }
            let request = RenderRequest(
                source: candidate.source, assetID: candidate.assetID, document: document,
                lut: lut, targetSize: CGSize(
                    width: Thumbnails.libraryMaxPixelSize,
                    height: Thumbnails.libraryMaxPixelSize
                ), quality: .thumbnail, output: .raster, space: .current
            )
            if request.quality == .thumbnail, request.sourceROI == nil,
               request.presentationROI == nil, request.output == .raster,
               request.lookSignature.permitsExactReuse,
               let image = await engine.makeThumbnailCGImage(request),
               canContinue(generation: scheduledGeneration)
            {
                let signature = FrameSignature(
                    source: candidate.identity, editHash: document.editHash,
                    look: request.lookSignature, workingSpace: request.space,
                    pixelEpoch: RenderPipeline.pixelEpoch
                )
                let frame = await Task.detached {
                    ThumbnailFrameEncoder.editedFrame(
                        image: image, identity: candidate.identity, signature: signature,
                        crop: document.crop, rotation: document.rotation
                    )
                }.value
                guard canContinue(generation: scheduledGeneration) else { return .cancelled }
                if let frame { await thumbnailStore.enqueueWrite(frame) }
            }
        }

        if !previewIsExact, mayRenderEditedPixels, let previewRequest,
           canContinue(generation: scheduledGeneration)
        {
            guard let image = await engine.makeCIImage(previewRequest),
                  canContinue(generation: scheduledGeneration) else {
                return canContinue(generation: scheduledGeneration) ? .completed : .cancelled
            }
            let admitted = await previewPresentation.writeCanonicalForWarmer(
                image, for: previewRequest
            )
            if !admitted, !(await previewPresentation.store.isBelowWarmingLowWaterMark()) {
                return .capacityReached
            }
        }
        return .completed
    }

    private func makeOriginalThumbnail(for candidate: IdleFrameWarmCandidate) async -> CGImage? {
        switch candidate.source.backing {
        case .url(let url):
            return await OriginalThumbnailLoader.load(
                url: url, data: nil, dataFingerprint: nil, identity: candidate.identity,
                store: nil, surface: .idleWarm,
                decodeObserver: originalDecodeObserver
            )
        case .data(let data):
            return await OriginalThumbnailLoader.load(
                url: nil, data: data,
                dataFingerprint: candidate.source.sourceDataFingerprint,
                identity: candidate.identity, store: nil, surface: .idleWarm,
                decodeObserver: originalDecodeObserver
            )
        }
    }

    private func canContinue(generation expected: UInt64) -> Bool {
        guard !Task.isCancelled, generation == expected,
              let destination, destination.idleFrameWarmerIsReady,
              !destination.idleFrameWarmerIsBlocked,
              destination.idleFrameWarmerConditions.permitsWork else { return false }
        return true
    }

    private func pinnedAssetIDs(
        for destination: any IdleFrameWarmerDestination
    ) -> Set<PortablePhotoAssetID> {
        var ids = destination.idleFrameWarmerVisiblePortableAssetIDs
        if let active = destination.idleFrameWarmerActivePortableAssetID { ids.insert(active) }
        return ids
    }

    private func waitForPhotoWorkToFinish() async {
        guard inFlightPhotoCount > 0 else { return }
        await withCheckedContinuation { photoCompletionWaiters.append($0) }
    }

    private func waitForEditorLane(generation expected: UInt64) async {
        while scheduler.pendingEditorCount > 0 || scheduler.runningEditorCount > 0 {
            do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
            guard canContinue(generation: expected) else { return }
        }
    }

    private func observeSystemChanges() {
        let powerName = Notification.Name.NSProcessInfoPowerStateDidChange
        let thermalName = ProcessInfo.thermalStateDidChangeNotification
        for name in [powerName, thermalName] {
            environmentObservers.append(
                notificationCenter.addObserver(forName: name, object: nil, queue: .main) {
                    [weak self] _ in
                    Task { @MainActor [weak self] in self?.systemConditionsChanged() }
                }
            )
        }
    }

    private func systemConditionsChanged() {
        guard let destination else { return }
        if !destination.idleFrameWarmerConditions.permitsWork {
            cancel()
        } else {
            schedule()
        }
    }
}

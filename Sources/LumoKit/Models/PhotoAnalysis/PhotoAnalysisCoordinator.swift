import Foundation

/// The amount of photo understanding a caller is willing to request.
///
/// The coordinator keeps the level-to-stage mapping in one registry. Adding a later analysis
/// stage therefore changes that registry rather than changing the request and de-duplication
/// machinery.
enum PhotoAnalysisLevel: Sendable, Equatable, Hashable {
    case fast
    case standard
    case detailed
}

/// One optional mask stage in a full analysis request.
struct PhotoAnalysisStage: Sendable, Equatable, Hashable {
    let kind: SemanticMaskKind
    let quality: MaskQuality

    init(kind: SemanticMaskKind, quality: MaskQuality) {
        self.kind = kind
        self.quality = quality
    }
}

/// Coordinates source analysis for all consumers of photo intelligence.
///
/// The actor owns only transient in-flight work. Mask pixels remain in `MaskStore`, and the
/// persistent scalar analysis cache belongs to LUMO-196. A direct mask request consequently does
/// not create a `PhotoAnalysis` or pay for unrelated analysis stages.
actor PhotoAnalysisCoordinator {
    private struct AnalysisRequestKey: Hashable, Sendable {
        let assetID: PhotoAssetID
        let sourceFingerprint: PhotoSourceFingerprint
        let level: PhotoAnalysisLevel
    }

    private struct MaskRequestKey: Hashable, Sendable {
        let assetID: PhotoAssetID
        let sourceFingerprint: PhotoSourceFingerprint
        let kind: SemanticMaskKind
        let quality: MaskQuality
    }

    private let maskProvider: any SemanticMaskProviding
    let maskStore: MaskStore
    private let assembler: PhotoAnalysisAssembler
    private let cache: PhotoAnalysisCache
    private let stages: [PhotoAnalysisLevel: [PhotoAnalysisStage]]

    /// `waiters` is the count of callers currently attached to `task`. The shared task is only
    /// cancelled once every attached waiter has cancelled — otherwise cancelling one of several
    /// concurrent callers (e.g. a thumbnail prefetch scrolled off-screen) would cancel the work
    /// out from under an unrelated caller (e.g. the editor) sharing the same in-flight request.
    private struct InFlightEntry<Value: Sendable> {
        let task: Task<Value, Error>
        var waiters: Int
    }

    private var inFlightAnalyses: [AnalysisRequestKey: InFlightEntry<PhotoAnalysis>] = [:]
    private var inFlightMasks: [MaskRequestKey: InFlightEntry<RegionMask>] = [:]

    init(
        engine: any RenderEngining = RenderEngine.shared,
        maskStore: MaskStore = MaskStore(),
        cache: PhotoAnalysisCache = PhotoAnalysisCache(),
        maskProvider: (any SemanticMaskProviding)? = nil,
        stages: [PhotoAnalysisLevel: [PhotoAnalysisStage]]? = nil
    ) {
        self.maskStore = maskStore
        self.maskProvider = maskProvider ?? VisionSemanticMaskProvider(store: maskStore)
        self.cache = cache
        self.assembler = PhotoAnalysisAssembler(
            globalToneAnalyzer: GlobalToneAnalyzer(engine: engine),
            maskedToneAnalyzer: MaskedToneAnalyzer(engine: engine, store: maskStore)
        )
        self.stages = stages ?? Self.defaultStages
    }

    /// Analyze one source at the requested level. Concurrent identical requests await one task.
    func analyze(
        assetID: PhotoAssetID,
        source: ImageSource,
        level: PhotoAnalysisLevel
    ) async throws -> PhotoAnalysis {
        try Task.checkCancellation()
        let key = AnalysisRequestKey(
            assetID: assetID,
            sourceFingerprint: Self.fingerprint(for: source),
            level: level
        )

        let cacheKey = AnalysisCacheKey(
            assetID: key.assetID,
            sourceFingerprint: key.sourceFingerprint,
            analysisVersion: .current
        )
        do {
            if let cached = try await cache.analysis(for: cacheKey) {
                LumoObservability.event(
                    .cacheHit, source: source, maskQuality: .analysis, detail: "photoAnalysis"
                )
                return cached
            }
            LumoObservability.event(
                .cacheMiss, source: source, maskQuality: .analysis, detail: "photoAnalysis"
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // A damaged or unavailable cache must never prevent Tier 0 analysis.
        }

        let task: Task<PhotoAnalysis, Error>
        if let existing = inFlightAnalyses[key] {
            task = existing.task
            inFlightAnalyses[key]?.waiters += 1
        } else {
            task = Task { [self] in
                do {
                    let result = try await performAnalysis(
                        assetID: assetID, source: source, level: level, cacheKey: cacheKey
                    )
                    inFlightAnalyses.removeValue(forKey: key)
                    return result
                } catch {
                    inFlightAnalyses.removeValue(forKey: key)
                    throw error
                }
            }
            inFlightAnalyses[key] = InFlightEntry(task: task, waiters: 1)
        }

        let result = try await sharedValue(of: task) { [self] in
            await analysisWaiterCancelled(key)
        }
        try Task.checkCancellation()
        return result
    }

    /// Request one semantic mask without assembling a full `PhotoAnalysis`.
    ///
    /// The provider owns the durable `MaskStore` lookup. The coordinator adds the in-memory
    /// request de-duplication layer, so simultaneous callers do not enter Vision more than once.
    func mask(
        assetID: PhotoAssetID,
        source: ImageSource,
        kind: SemanticMaskKind,
        quality: MaskQuality
    ) async throws -> RegionMask {
        try Task.checkCancellation()
        let key = MaskRequestKey(
            assetID: assetID,
            sourceFingerprint: Self.fingerprint(for: source),
            kind: kind,
            quality: quality
        )

        let task: Task<RegionMask, Error>
        if let existing = inFlightMasks[key] {
            task = existing.task
            inFlightMasks[key]?.waiters += 1
        } else {
            task = Task { [self] in
                do {
                    let result = try await performMask(source: source, kind: kind, quality: quality)
                    inFlightMasks.removeValue(forKey: key)
                    return result
                } catch {
                    inFlightMasks.removeValue(forKey: key)
                    throw error
                }
            }
            inFlightMasks[key] = InFlightEntry(task: task, waiters: 1)
        }

        let result = try await sharedValue(of: task) { [self] in
            await maskWaiterCancelled(key)
        }
        try Task.checkCancellation()
        return result
    }

    /// Read a cached/provider-produced payload without exposing MaskStore to UI consumers. Pixel
    /// access remains behind the coordinator boundary, just like mask production itself.
    func pixels(for reference: RegionMaskReference) async -> NormalizedMask? {
        await maskStore.pixels(for: reference)
    }

    // MARK: - Pipeline

    private func performAnalysis(
        assetID: PhotoAssetID,
        source: ImageSource,
        level: PhotoAnalysisLevel,
        cacheKey: AnalysisCacheKey
    ) async throws -> PhotoAnalysis {
        try Task.checkCancellation()
        let clock = ContinuousClock()
        let totalStart = clock.now
        var totalInterval = LumoObservability.begin(
            .analysisTotal, source: source, maskQuality: .analysis
        )
        defer { totalInterval.end() }

        let preparationStart = clock.now
        var preparationInterval = LumoObservability.begin(
            .analysisImagePreparation, source: source, maskQuality: .analysis
        )
        let image = try AnalysisImageFactory.make(from: source)
        preparationInterval.end()
        var timings = AnalysisTimings(
            imagePreparation: preparationStart.duration(to: clock.now)
        )

        var masks: [RegionMask] = []
        masks.reserveCapacity(stages[level, default: []].count)

        for stage in stages[level, default: []] {
            try Task.checkCancellation()
            let stageStart = clock.now
            do {
                let result = try await performMask(
                    image: image, kind: stage.kind, quality: stage.quality
                )
                try Task.checkCancellation()
                masks.append(result)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // Mask stages are optional. PhotoAnalysisAssembler still requires Tier 0 and
                // records the successfully populated mask tiers in its quality value.
                timings = timings.adding(
                    duration: stageStart.duration(to: clock.now), for: stage.kind
                )
                continue
            }
            timings = timings.adding(
                duration: stageStart.duration(to: clock.now), for: stage.kind
            )
        }

        try Task.checkCancellation()
        let result = try await assembler.assemble(image: image, masks: masks, timings: timings)
        try Task.checkCancellation()
        let completed = result.withTimings(
            result.timings.replacing(total: totalStart.duration(to: clock.now))
        )
        do {
            try await cache.store(completed, for: cacheKey)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // Persistence is an optimization. Return a valid analysis even when the cache cannot
            // be written (for example, a read-only application-support volume).
        }
        try Task.checkCancellation()
        return completed
    }

    private func performMask(
        source: ImageSource,
        kind: SemanticMaskKind,
        quality: MaskQuality
    ) async throws -> RegionMask {
        try Task.checkCancellation()
        var preparationInterval = LumoObservability.begin(
            .analysisImagePreparation, source: source, maskQuality: quality
        )
        let image = try AnalysisImageFactory.make(from: source)
        preparationInterval.end()
        return try await performMask(image: image, kind: kind, quality: quality)
    }

    private func performMask(
        image: AnalysisImage,
        kind: SemanticMaskKind,
        quality: MaskQuality
    ) async throws -> RegionMask {
        try Task.checkCancellation()
        let result = try await maskProvider.mask(for: kind, image: image, quality: quality)
        try Task.checkCancellation()
        return result
    }

    /// A cancelled waiter detaches from the shared work; only once every attached waiter has
    /// cancelled does the underlying task itself get cancelled. This matches the app's
    /// cancel-on-supersede discipline while keeping one caller's cancellation (e.g. a scrolled-away
    /// thumbnail prefetch) from silently failing an unrelated caller (e.g. the editor) sharing the
    /// same in-flight request.
    private func sharedValue<Value: Sendable>(
        of task: Task<Value, Error>,
        onCancel detachWaiter: @escaping @Sendable () async -> Void
    ) async throws -> Value {
        try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            Task { await detachWaiter() }
        }
    }

    /// Decrement the analysis waiter count for `key`; cancel the shared task once none remain.
    /// The dictionary entry itself is only ever removed by the task's own completion handler
    /// above, so a late completion can't evict an unrelated later request that reused the key.
    private func analysisWaiterCancelled(_ key: AnalysisRequestKey) {
        guard var entry = inFlightAnalyses[key] else { return }
        entry.waiters -= 1
        if entry.waiters <= 0 {
            entry.task.cancel()
        }
        inFlightAnalyses[key] = entry
    }

    /// Mask-request counterpart of `analysisWaiterCancelled(_:)`.
    private func maskWaiterCancelled(_ key: MaskRequestKey) {
        guard var entry = inFlightMasks[key] else { return }
        entry.waiters -= 1
        if entry.waiters <= 0 {
            entry.task.cancel()
        }
        inFlightMasks[key] = entry
    }

    // MARK: - Stage registry and identity

    private static let defaultStages: [PhotoAnalysisLevel: [PhotoAnalysisStage]] = [
        .fast: [
            PhotoAnalysisStage(kind: .subject, quality: .analysis),
            PhotoAnalysisStage(kind: .face, quality: .analysis),
        ],
        .standard: [
            PhotoAnalysisStage(kind: .subject, quality: .analysis),
            PhotoAnalysisStage(kind: .foregroundInstance(0), quality: .analysis),
            PhotoAnalysisStage(kind: .background, quality: .analysis),
        ],
        .detailed: [
            PhotoAnalysisStage(kind: .subject, quality: .preview),
            PhotoAnalysisStage(kind: .foregroundInstance(0), quality: .preview),
            PhotoAnalysisStage(kind: .background, quality: .preview),
            PhotoAnalysisStage(kind: .face, quality: .preview),
            PhotoAnalysisStage(kind: .person, quality: .preview),
        ],
    ]

    private static func fingerprint(for source: ImageSource) -> PhotoSourceFingerprint {
        switch source.backing {
        case .url(let url):
            return .file(at: url)
        case .data(let data):
            return .data(data)
        }
    }

}

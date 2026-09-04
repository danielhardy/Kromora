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
    private let assembler: PhotoAnalysisAssembler
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
        maskProvider: (any SemanticMaskProviding)? = nil,
        stages: [PhotoAnalysisLevel: [PhotoAnalysisStage]]? = nil
    ) {
        self.maskProvider = maskProvider ?? VisionSemanticMaskProvider(store: maskStore)
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

        let task: Task<PhotoAnalysis, Error>
        if let existing = inFlightAnalyses[key] {
            task = existing.task
            inFlightAnalyses[key]?.waiters += 1
        } else {
            task = Task { [self] in
                do {
                    let result = try await performAnalysis(assetID: assetID, source: source, level: level)
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

    // MARK: - Pipeline

    private func performAnalysis(
        assetID: PhotoAssetID,
        source: ImageSource,
        level: PhotoAnalysisLevel
    ) async throws -> PhotoAnalysis {
        try Task.checkCancellation()
        let image = try AnalysisImageFactory.make(from: source)
        var masks: [RegionMask] = []
        masks.reserveCapacity(stages[level, default: []].count)

        for stage in stages[level, default: []] {
            try Task.checkCancellation()
            do {
                let result = try await mask(
                    assetID: assetID,
                    source: source,
                    kind: stage.kind,
                    quality: stage.quality
                )
                try Task.checkCancellation()
                masks.append(result)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // Mask stages are optional. PhotoAnalysisAssembler still requires Tier 0 and
                // records the successfully populated mask tiers in its quality value.
                continue
            }
        }

        try Task.checkCancellation()
        let result = try await assembler.assemble(image: image, masks: masks)
        try Task.checkCancellation()
        return result
    }

    private func performMask(
        source: ImageSource,
        kind: SemanticMaskKind,
        quality: MaskQuality
    ) async throws -> RegionMask {
        try Task.checkCancellation()
        let image = try AnalysisImageFactory.make(from: source)
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

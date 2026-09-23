import Foundation

/// The lifecycle state exposed by the Auto action.
enum AutoAdjustmentState: Equatable, Sendable {
    case unavailable(String)
    case ready
    case analyzing
    case renderingCandidates
    case validating
    case applying
    case cancelled
    case failed(String)

    var message: String {
        switch self {
        case .unavailable(let message), .failed(let message): return message
        case .ready:
            return
                "Analyze the source and replace global Light and Color with a conservative baseline."
        case .analyzing: return "Analyzing the source for Auto adjustments…"
        case .renderingCandidates: return "Rendering Auto candidates…"
        case .validating: return "Validating Auto candidates…"
        case .applying: return "Applying Auto adjustments…"
        case .cancelled: return "Auto cancelled; nothing was changed."
        }
    }
}

struct AutoWorkflowRequest: Sendable {
    let source: ImageSource
    let assetID: PhotoAssetID?
    let document: EditDocument
    let lut: CubeLUT?
}

enum AutoWorkflowPath: Sendable, Equatable {
    case contentAware
    /// Used only when the current renderer does not support content-aware sampling. The reason is
    /// attached to the outcome and included in the user-visible completion message.
    case degraded(String)
}

struct AutoWorkflowOutcome: Sendable {
    let result: AutoEnhancementResult
    let path: AutoWorkflowPath
    let message: String
}

@MainActor
protocol AutoWorkflowRunning: AnyObject {
    func run(
        _ request: AutoWorkflowRequest,
        onProgress: @escaping @MainActor @Sendable (AutoEnhancementPhase) -> Void
    ) async -> AutoWorkflowOutcome
}

/// Owns invocation revisions, cancellation, preview gating, and progress publication for Auto.
/// Work is injected so lifecycle tests do not need an AppViewModel or a renderer.
@MainActor
final class AutoWorkflowCoordinator {
    private(set) var invocationRevision: UInt64 = 0
    private var task: Task<Void, Never>?

    func start(
        request: AutoWorkflowRequest?,
        previewReady: Bool,
        runner: any AutoWorkflowRunning,
        isFenceCurrent: @escaping @MainActor () -> Bool,
        onState: @escaping @MainActor (AutoAdjustmentState, Double?) -> Void,
        completion: @escaping @MainActor (UInt64, AutoWorkflowOutcome) -> Void
    ) -> UInt64? {
        task?.cancel()
        invocationRevision &+= 1
        guard previewReady, let request else {
            onState(.unavailable("Auto is available when the photo preview is ready."), nil)
            return nil
        }
        let revision = invocationRevision
        onState(.analyzing, 0)
        let progress: @MainActor @Sendable (AutoEnhancementPhase) -> Void = { phase in
            guard self.invocationRevision == revision else { return }
            switch phase {
            case .analyzing: onState(.analyzing, 0)
            case .renderingCandidates: onState(.renderingCandidates, 0.5)
            case .validating: onState(.validating, 0.75)
            }
        }
        task = Task { @MainActor in
            let outcome = await runner.run(request, onProgress: progress)
            guard !Task.isCancelled, self.invocationRevision == revision,
                isFenceCurrent()
            else { return }
            completion(revision, outcome)
        }
        return revision
    }

    func isCurrent(_ revision: UInt64) -> Bool { invocationRevision == revision }

    func supersede() {
        invocationRevision &+= 1
        task?.cancel()
        task = nil
    }

    func cancel(onState: @MainActor (AutoAdjustmentState, Double?) -> Void) {
        guard task != nil else { return }
        invocationRevision &+= 1
        task?.cancel()
        task = nil
        onState(.cancelled, nil)
    }

    func invalidate(onState: @MainActor (AutoAdjustmentState, Double?) -> Void) {
        invocationRevision &+= 1
        task?.cancel()
        task = nil
        onState(.unavailable("Auto is available when the photo preview is ready."), nil)
    }

    func waitForCompletion() async { await task?.value }
}

/// The production workflow boundary. Content-aware sampling is primary for the shipping renderer;
/// the bounded histogram analyzer remains an explicit degraded mode for renderers without sampling.
@MainActor
final class ProductionAutoWorkflow: AutoWorkflowRunning {
    private let engine: any RenderEngining
    private let analysis: PhotoAnalysisCoordinator

    init(engine: any RenderEngining, analysis: PhotoAnalysisCoordinator) {
        self.engine = engine
        self.analysis = analysis
    }

    func run(
        _ request: AutoWorkflowRequest,
        onProgress: @escaping @MainActor @Sendable (AutoEnhancementPhase) -> Void
    ) async -> AutoWorkflowOutcome {
        let source = request.source
        let current = request.document
        if let id = request.assetID,
            let sampler = engine as? any RenderEngining & CurrentEditSampling,
            engine is RenderEngine
        {
            let value = await ContentAwareAutoEngine(
                engine: sampler, analysisCoordinator: analysis, maskStore: analysis.maskStore
            ).run(
                source: source, assetID: id, current: current, lut: request.lut,
                onProgress: onProgress)
            return AutoWorkflowOutcome(
                result: value,
                path: .contentAware,
                message: value.status == .improved
                    ? "Auto applied — \(value.changedControls.count) coordinated controls (undo to restore previous edits)"
                    : value.reasons.first ?? "No further improvement found"
            )
        }

        let reason =
            request.assetID == nil
            ? "Photo identity is unavailable; using the global histogram Auto fallback."
            : "This renderer does not support content-aware sampling; using the global histogram Auto fallback."
        if let fingerprint = current.lastAutoRunFingerprint,
            fingerprint.matches(source: source, document: current)
        {
            return AutoWorkflowOutcome(
                result: AutoEnhancementResult(
                    status: .unchanged, proposedDocument: current, fingerprint: fingerprint),
                path: .degraded(reason),
                message: "No further improvement found (degraded mode: \(reason))"
            )
        }
        onProgress(.analyzing)
        guard !Task.isCancelled else {
            return outcome(
                .cancelled, current, path: .degraded(reason),
                message: "Auto cancelled; nothing was changed.")
        }
        onProgress(.renderingCandidates)
        var baseline = current.autoAdjustmentBaseline
        baseline.lut = .none
        let histogram = await engine.histogram(
            source: source, document: baseline, lut: nil,
            scale: .preview(maxSize: CGSize(width: 1600, height: 1200)), space: .current,
            maxDimension: AutoAdjustmentSettings.default.histogramMaxDimension
        )
        guard !Task.isCancelled else {
            return outcome(
                .cancelled, current, path: .degraded(reason),
                message: "Auto cancelled; nothing was changed.")
        }
        guard let histogram, let evaluated = AutoAdjustmentAnalyzer.analyze(histogram: histogram)
        else {
            return outcome(
                .noCandidate, current, path: .degraded(reason),
                message:
                    "Auto could not analyze the photo. Try reloading it. (Degraded mode: \(reason))"
            )
        }
        onProgress(.validating)
        var proposed = current
        proposed.light = evaluated.light
        proposed.color.vibrance = evaluated.color.vibrance
        proposed.color.saturation = evaluated.color.saturation
        guard proposed.renderingHash != current.renderingHash else {
            return outcome(
                .unchanged, current, path: .degraded(reason),
                message: "No further improvement found (degraded mode: \(reason))")
        }
        let result = AutoEnhancementResult(
            proposedDocument: proposed,
            fingerprint: AutoRunFingerprint.make(source: source, document: proposed)
        )
        return AutoWorkflowOutcome(
            result: result, path: .degraded(reason),
            message: "Auto applied — global histogram fallback (degraded mode: \(reason))")
    }

    private func outcome(
        _ status: AutoEnhancementResult.Status, _ document: EditDocument,
        path: AutoWorkflowPath, message: String
    ) -> AutoWorkflowOutcome {
        AutoWorkflowOutcome(
            result: AutoEnhancementResult(status: status, proposedDocument: document),
            path: path, message: message
        )
    }
}

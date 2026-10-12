import Foundation

/// Runs the CPU-bound dust analysis off the main actor and keeps the source-dependent products of the
/// most recent photo, so threshold changes only repeat the cheap selection stage. Only `Sendable`
/// values cross this boundary.
actor RetouchDustAnalysisWorker {
    enum Stage: Sendable { case analyze, select }

    private let observer: (@Sendable (Stage) -> Void)?
    private var cached: (key: String, analysis: RetouchDustAnalysis)?

    /// `observer` runs on the worker's executor just before each stage; tests use it to assert where
    /// work executes and how often the expensive stage runs.
    init(observer: (@Sendable (Stage) -> Void)? = nil) {
        self.observer = observer
    }

    func hasAnalysis(for key: String) -> Bool { cached?.key == key }

    /// Builds and retains the analysis for `key`. Returns `false` when cancelled before completion.
    func prepare(key: String, proxy: RetouchAnalysisProxy) -> Bool {
        if cached?.key == key { return true }
        observer?(.analyze)
        guard let analysis = try? RetouchDustDetector.analyze(proxy) else { return false }
        cached = (key, analysis)
        return true
    }

    /// Threshold-specific selection from the retained analysis, or `nil` when `key` is not retained
    /// or the task was cancelled.
    func select(key: String, threshold: Double, maximum: Int) -> [RetouchDustSuggestion]? {
        guard let cached, cached.key == key else { return nil }
        observer?(.select)
        return try? RetouchDustDetector.select(from: cached.analysis, threshold: threshold, maximum: maximum)
    }

    func reset() { cached = nil }
}

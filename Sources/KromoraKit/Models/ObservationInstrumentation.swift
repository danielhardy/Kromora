import Foundation

/// Lightweight body-evaluation instrumentation for the Observation migration (KRMA-521).
///
/// Production views increment these counters once per `body` evaluation through
/// `noteContentViewBody()` / `noteInspectorBody()` / `noteGridBody()`. Tests reset the
/// counters, drive high-frequency state (thumbnail arrivals, import/export progress,
/// canvas navigation), and assert that unrelated surfaces did not reevaluate.
///
/// Counters are `@MainActor`-isolated because every increment happens from a SwiftUI body,
/// which runs on the main actor. No `nonisolated(unsafe)` or other opt-out is used, keeping
/// the Swift 6 zero-diagnostic property intact.
@MainActor
enum ViewBodyCounter {
    static var contentViewEvaluations = 0
    static var inspectorEvaluations = 0
    static var gridEvaluations = 0
    static var toolbarEvaluations = 0

    static func reset() {
        contentViewEvaluations = 0
        inspectorEvaluations = 0
        gridEvaluations = 0
        toolbarEvaluations = 0
    }

    @discardableResult
    static func noteContentViewBody() -> Bool {
        contentViewEvaluations &+= 1
        return true
    }

    @discardableResult
    static func noteInspectorBody() -> Bool {
        inspectorEvaluations &+= 1
        return true
    }

    @discardableResult
    static func noteGridBody() -> Bool {
        gridEvaluations &+= 1
        return true
    }

    @discardableResult
    static func noteToolbarBody() -> Bool {
        toolbarEvaluations &+= 1
        return true
    }

    static var snapshot: (content: Int, inspector: Int, grid: Int, toolbar: Int) {
        (contentViewEvaluations, inspectorEvaluations, gridEvaluations, toolbarEvaluations)
    }
}

/// Deterministic p95 helper shared by navigation/slider performance tests.
///
/// Keeps the percentile definition in one place so ContentView/grid/inspector benchmarks
/// report comparable numbers before and after the Observation migration.
enum ObservationPerformance {
    /// p95 of `samples` in milliseconds. Returns 0 for an empty sample set.
    nonisolated static func p95(milliseconds samples: [Double]) -> Double {
        guard !samples.isEmpty else { return 0 }
        let sorted = samples.sorted()
        let index = min(sorted.count - 1, Int(Double(sorted.count - 1) * 0.95))
        return sorted[index]
    }

    nonisolated static func median(milliseconds samples: [Double]) -> Double {
        guard !samples.isEmpty else { return 0 }
        let sorted = samples.sorted()
        return sorted[sorted.count / 2]
    }
}

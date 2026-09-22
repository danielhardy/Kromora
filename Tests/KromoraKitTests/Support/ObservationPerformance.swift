/// Deterministic percentile helpers shared by navigation/slider performance tests.
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

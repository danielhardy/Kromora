import Foundation

/// Opt-in, window-independent import profiling. Nested read/hash/write timings are part of
/// staging, rather than additional wall time. Normal imports do not read the profiling clock.
enum PortablePackageImportPhase: String, CaseIterable, Sendable {
    case catalog, begin, read, hash, write, staging, commit

    static func measure<T>(
        _ phase: Self,
        observer: (@Sendable (Self, Duration) -> Void)?,
        operation: () throws -> T
    ) rethrows -> T {
        guard let observer else { return try operation() }
        let start = ContinuousClock.now
        defer { observer(phase, start.duration(to: .now)) }
        return try operation()
    }
}

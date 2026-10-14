import Foundation

typealias ExportJobID = UUID

/// The kinds of work `ExportCoordinator` owns from acceptance until it finishes.
enum ExportJobKind: Equatable, Sendable {
    case single
    case batch
    /// One lazy Share render, started when the chosen service loads an item.
    case share
    case originalBundle
}

enum ExportJobOutcome: Equatable, Sendable {
    case completed
    case cancelled
    case failed
}

/// One accepted export, Share render, or original-bundle job.
///
/// The input snapshot (document, Look, items, options) is captured by value in the job's task at
/// admission, so later edits to the open photo or selection never change a running job.
struct ExportJob: Identifiable {
    let id: ExportJobID
    let kind: ExportJobKind
    let itemCount: Int
    var cancellationRequested = false
    var cancel: (@Sendable () -> Void)?
    var settled: (@Sendable () async -> Void)?
}

/// What the last job to reach a terminal state did, for status and tests.
struct ExportJobRecord: Equatable, Sendable {
    let id: ExportJobID
    let kind: ExportJobKind
    let outcome: ExportJobOutcome
}

struct ExportJobBusyError: LocalizedError {
    var errorDescription: String? { "Another export is already running." }
}

import Foundation

/// Schedules work that competes for the user's attention.
///
/// The scheduler owns policy, not the work itself. Editor work has its own lane and can therefore
/// start while thumbnail workers are busy. Package I/O uses the same admission policy, but its
/// operation runs off the main actor so a copy, hash, rebuild, or validation cannot occupy the UI
/// executor. Thumbnail and package-I/O queues are deliberately bounded; a fast folder scan or
/// large-library rebuild cannot allocate one task per file and leave stale work waiting behind the
/// current photo.
@MainActor
final class ImageWorkScheduler {

    enum Priority: Int, CaseIterable, Sendable {
        case activeEditor = 0
        case comparison = 1
        case histogram = 2
        case adjacentFilmstrip = 3
        case visibleGrid = 4
        /// Import copy/hash work is below visible grid demand but ahead of idle maintenance.
        case packageIO = 5
        case background = 6
    }

    enum Lane: Sendable, Equatable {
        case editor
        case thumbnail
        /// All package reads and writes share this scheduler with rendering work.
        case packageIO
    }

    enum PackageIOLane: Sendable, Equatable {
        /// Lease renewal is latency-sensitive: it must be admitted ahead of ordinary package
        /// maintenance whenever the single package-I/O worker becomes available.
        case leaseHeartbeat
        case importCopyHash
        case indexRebuild
        case validation
        case maintenance

        var defaultPriority: Priority {
            switch self {
            case .leaseHeartbeat: return .packageIO
            case .importCopyHash: return .packageIO
            case .indexRebuild, .validation, .maintenance: return .background
            }
        }
    }

    /// The single terminal notification delivered for an admitted job.
    ///
    /// A job can leave the scheduler without its operation ever running (for example when a newer
    /// thumbnail evicts it). Callers that bridge a job to a continuation must be told about those
    /// paths as well as normal execution, otherwise the continuation can remain suspended forever.
    enum TerminalOutcome: Sendable, Equatable {
        case completed
        case cancelled
        case evicted
        case rejected
    }

    struct JobID: Hashable, Sendable {
        let rawValue: String

        init(_ rawValue: String) {
            self.rawValue = rawValue
        }
    }

    struct Configuration: Sendable, Equatable {
        var maxConcurrentThumbnails: Int = 4
        var maxQueuedThumbnails: Int = 24
        /// RenderEngine is actor-serialized. Keep only a small support backlog behind the newest
        /// visible request so inspector churn cannot accumulate actor messages.
        var maxQueuedEditorJobs: Int = 4
        /// Package commits remain serialized by the package writer. Copy/hash callers can opt into
        /// a larger value after measuring their volume, while maintenance defaults to one worker.
        var maxConcurrentPackageIO: Int = 1
        var maxQueuedPackageIO: Int = 32

        static let `default` = Configuration()
    }

    struct Admission: Sendable, Equatable {
        let id: JobID
        let lane: Lane
        let priority: Priority
    }

    typealias Operation = @MainActor @Sendable () async -> Void
    /// Package work must not inherit the main actor: filesystem, hashing, and validation work are
    /// explicitly outside the UI executor. The scheduler still delivers its terminal callback on
    /// the main actor.
    typealias PackageIOOperation = @Sendable () async -> Void
    typealias TerminalHandler = @MainActor @Sendable (TerminalOutcome) -> Void

    private enum ScheduledOperation {
        case mainActor(Operation)
        case packageIO(PackageIOOperation)
    }

    private struct Job {
        let id: JobID
        let lane: Lane
        var priority: Priority
        let sequence: UInt64
        let operation: ScheduledOperation
        let onTerminal: TerminalHandler
    }

    private struct Running {
        let lane: Lane
        let priority: Priority
        let token: UInt64
        let task: Task<Void, Never>
        let onTerminal: TerminalHandler
    }

    private let configuration: Configuration
    private var queued: [JobID: Job] = [:]
    private var running: [JobID: Running] = [:]
    private var nextSequence: UInt64 = 0
    private var nextToken: UInt64 = 0

    private(set) var droppedThumbnailCount = 0
    private(set) var droppedPackageIOCount = 0
    private(set) var cancelledCount = 0
    private(set) var peakQueuedThumbnailCount = 0
    private(set) var peakQueuedPackageIOCount = 0
    /// Number of package jobs that were ready but deliberately held behind editor contention.
    /// This is useful telemetry as well as a fairness-test seam.
    private(set) var yieldedPackageIOCount = 0
    private(set) var admissionLog: [Admission] = []

    init(configuration: Configuration = .default) {
        self.configuration = Configuration(
            maxConcurrentThumbnails: max(0, configuration.maxConcurrentThumbnails),
            maxQueuedThumbnails: max(0, configuration.maxQueuedThumbnails),
            maxQueuedEditorJobs: max(0, configuration.maxQueuedEditorJobs),
            maxConcurrentPackageIO: max(0, configuration.maxConcurrentPackageIO),
            maxQueuedPackageIO: max(0, configuration.maxQueuedPackageIO)
        )
    }

    var pendingCount: Int { queued.count }

    var pendingThumbnailCount: Int {
        queued.values.filter { $0.lane == .thumbnail }.count
    }

    var pendingEditorCount: Int {
        queued.values.filter { $0.lane == .editor }.count
    }

    var pendingPackageIOCount: Int {
        queued.values.filter { $0.lane == .packageIO }.count
    }

    var runningCount: Int { running.count }

    var runningThumbnailCount: Int {
        running.values.filter { $0.lane == .thumbnail }.count
    }

    var runningPackageIOCount: Int {
        running.values.filter { $0.lane == .packageIO }.count
    }

    var canQueueThumbnail: Bool {
        runningThumbnailCount < configuration.maxConcurrentThumbnails
            || pendingThumbnailCount < configuration.maxQueuedThumbnails
    }

    var canQueuePackageIO: Bool {
        runningPackageIOCount < configuration.maxConcurrentPackageIO
            || pendingPackageIOCount < configuration.maxQueuedPackageIO
    }

    var isIdle: Bool { queued.isEmpty && running.isEmpty }

    /// Add or replace a job. Replacing a running job cancels it before the new value is admitted.
    @discardableResult
    func enqueue(
        id: JobID,
        lane: Lane,
        priority: Priority,
        onTerminal: @escaping TerminalHandler = { _ in },
        operation: @escaping Operation
    ) -> Bool {
        cancel(id: id, countAsCancellation: false)

        nextSequence &+= 1
        let job = Job(
            id: id, lane: lane, priority: priority, sequence: nextSequence,
            operation: .mainActor(operation), onTerminal: onTerminal
        )

        if lane == .thumbnail {
            guard configuration.maxConcurrentThumbnails > 0 else {
                droppedThumbnailCount += 1
                onTerminal(.rejected)
                return false
            }
            guard
                configuration.maxQueuedThumbnails > 0
                    || runningThumbnailCount < configuration.maxConcurrentThumbnails
            else {
                droppedThumbnailCount += 1
                onTerminal(.rejected)
                return false
            }
            guard admitThumbnail(job) else {
                onTerminal(.rejected)
                return false
            }
        } else {
            guard admitEditor(job) else {
                onTerminal(.rejected)
                return false
            }
        }
        let admitted = queued[job.id] != nil
        if admitted || running[job.id] != nil {
            admissionLog.append(Admission(id: job.id, lane: lane, priority: priority))
        }
        updatePeakQueue()
        pump()
        return admitted || running[job.id] != nil
    }

    /// Admit package I/O through the shared scheduler.
    ///
    /// Import copy/hash work has a priority just below visible-grid work. Rebuild, validation, and
    /// maintenance default to idle background priority. A caller may supply a different priority
    /// for a narrowly-scoped user action, but package work can never use the editor lane by
    /// accident because this API requires a non-main-actor operation.
    @discardableResult
    func enqueuePackageIO(
        id: JobID,
        lane packageIOLane: PackageIOLane,
        priority: Priority? = nil,
        onTerminal: @escaping TerminalHandler = { _ in },
        operation: @escaping PackageIOOperation
    ) -> Bool {
        cancel(id: id, countAsCancellation: false)

        nextSequence &+= 1
        let job = Job(
            id: id, lane: .packageIO,
            priority: priority ?? packageIOLane.defaultPriority, sequence: nextSequence,
            operation: .packageIO(operation), onTerminal: onTerminal
        )

        guard configuration.maxConcurrentPackageIO > 0 else {
            droppedPackageIOCount += 1
            onTerminal(.rejected)
            return false
        }
        guard
            configuration.maxQueuedPackageIO > 0
                || runningPackageIOCount < configuration.maxConcurrentPackageIO
        else {
            droppedPackageIOCount += 1
            onTerminal(.rejected)
            return false
        }
        guard admitPackageIO(job) else {
            onTerminal(.rejected)
            return false
        }

        let admitted = queued[job.id] != nil
        if admitted || running[job.id] != nil {
            admissionLog.append(Admission(id: job.id, lane: .packageIO, priority: job.priority))
        }
        updatePeakQueue()
        pump()
        return admitted || running[job.id] != nil
    }

    /// Change a queued job's priority without restarting it. Running work is left alone when it is
    /// still useful; callers can use `cancel` for work that has scrolled out of relevance.
    func updatePriority(for id: JobID, to priority: Priority) {
        guard var job = queued[id] else { return }
        job.priority = priority
        queued[id] = job
        pump()
    }

    func contains(_ id: JobID) -> Bool {
        queued[id] != nil || running[id] != nil
    }

    func cancel(id: JobID) {
        cancel(id: id, countAsCancellation: true)
        pump()
    }

    /// Remove a job without immediately starting another queued operation. This lets a caller
    /// replace support work and enqueue a visible edit as one admission decision.
    func cancel(id: JobID, pump: Bool) {
        cancel(id: id, countAsCancellation: true)
        if pump { self.pump() }
    }

    /// Cancels one admitted operation and waits for an operation that had already entered its
    /// detached body. This is the per-job teardown barrier used by the package lease heartbeat;
    /// releasing the lock before this returns could allow a late renewal to touch a new owner.
    func cancelAndWait(id: JobID) async {
        let runningTask = running[id]?.task
        cancel(id: id, countAsCancellation: true)
        pump()
        await runningTask?.value
    }

    func cancel(ids: Set<JobID>) {
        for id in ids {
            cancel(id: id, countAsCancellation: true)
        }
        pump()
    }

    func cancelAll() {
        let ids = Set(queued.keys).union(running.keys)
        cancel(ids: ids)
    }

    /// Cancel every admitted operation and wait for work that had already entered its operation.
    ///
    /// `cancelAll()` alone is not a teardown barrier: an operation may be inside a renderer or
    /// another framework call that only observes cancellation when it returns. Callers that are
    /// about to remove a fixture must await this method so that the operation cannot touch the old
    /// source after cleanup.
    func cancelAllAndWait() async {
        while !queued.isEmpty || !running.isEmpty {
            let activeTasks = running.values.map(\.task)
            cancelAll()
            for task in activeTasks {
                await task.value
            }
        }
    }

    private func cancel(id: JobID, countAsCancellation: Bool) {
        if let job = queued.removeValue(forKey: id) {
            if countAsCancellation { cancelledCount += 1 }
            job.onTerminal(.cancelled)
            return
        }
        if let active = running.removeValue(forKey: id) {
            active.task.cancel()
            if countAsCancellation { cancelledCount += 1 }
            // A detached package operation may still be inside a copy, fsync, or transaction
            // rollback after Task.cancel(). Keep the package-I/O slot occupied until its task
            // reaches `finished`; otherwise a queued writer could overlap the rollback and break
            // the single-writer invariant. Thumbnail/editor cancellation retains the historical
            // eager terminal callback because those operations do not mutate package state.
            if active.lane == .packageIO {
                running[id] = active
            } else {
                active.onTerminal(.cancelled)
            }
        }
    }

    private func admitThumbnail(_ job: Job) -> Bool {
        let pending = queued.values.filter { $0.lane == .thumbnail }
        // `pending` is only empty here when `maxQueuedThumbnails == 0` — the caller already
        // confirmed there is running capacity in that case, so there is nothing to evict and the
        // job should be queued (transiently) for `pump()` to pick straight up.
        if pending.count >= configuration.maxQueuedThumbnails,
            let worst = pending.max(by: { precedes($0, $1) })
        {
            guard precedes(job, worst) else {
                droppedThumbnailCount += 1
                return false
            }
            queued.removeValue(forKey: worst.id)
            droppedThumbnailCount += 1
            worst.onTerminal(.evicted)
        }
        queued[job.id] = job
        return true
    }

    private func admitPackageIO(_ job: Job) -> Bool {
        let pending = queued.values.filter { $0.lane == .packageIO }
        if pending.count >= configuration.maxQueuedPackageIO,
            let worst = pending.max(by: { precedes($0, $1) })
        {
            guard precedes(job, worst) else {
                droppedPackageIOCount += 1
                return false
            }
            queued.removeValue(forKey: worst.id)
            droppedPackageIOCount += 1
            worst.onTerminal(.evicted)
        }
        queued[job.id] = job
        return true
    }

    private(set) var droppedEditorCount = 0

    var runningEditorCount: Int {
        running.values.filter { $0.lane == .editor }.count
    }

    private func admitEditor(_ job: Job) -> Bool {
        // Once a visible edit arrives, queued histogram/comparison/prefetch work is obsolete. It
        // will be re-admitted after the frame is presented if it is still relevant.
        if job.priority == .activeEditor {
            let supportIDs = queued.values
                .filter { $0.lane == .editor && $0.priority != .activeEditor }
                .map(\.id)
            for id in supportIDs {
                guard let support = queued.removeValue(forKey: id) else { continue }
                droppedEditorCount += 1
                support.onTerminal(.evicted)
            }
        }

        guard configuration.maxQueuedEditorJobs > 0 || runningEditorCount == 0 else {
            droppedEditorCount += 1
            return false
        }
        let pending = queued.values.filter { $0.lane == .editor }
        if pending.count >= configuration.maxQueuedEditorJobs,
            let worst = pending.max(by: { precedes($0, $1) })
        {
            guard precedes(job, worst) else {
                droppedEditorCount += 1
                return false
            }
            queued.removeValue(forKey: worst.id)
            droppedEditorCount += 1
            worst.onTerminal(.evicted)
        }
        queued[job.id] = job
        return true
    }

    private func pump() {
        while let next = nextAdmissibleJob() {
            queued.removeValue(forKey: next.id)
            nextToken &+= 1
            let token = nextToken
            let task: Task<Void, Never>
            switch next.operation {
            case .mainActor(let operation):
                task = Task { @MainActor [weak self, operation] in
                    guard !Task.isCancelled else {
                        self?.finished(id: next.id, token: token, outcome: .cancelled)
                        return
                    }
                    await operation()
                    self?.finished(
                        id: next.id, token: token,
                        outcome: Task.isCancelled ? .cancelled : .completed
                    )
                }
            case .packageIO(let operation):
                task = Task.detached { [weak self, operation] in
                    guard !Task.isCancelled else {
                        await MainActor.run {
                            self?.finished(id: next.id, token: token, outcome: .cancelled)
                        }
                        return
                    }
                    await operation()
                    let outcome: TerminalOutcome = Task.isCancelled ? .cancelled : .completed
                    await MainActor.run {
                        self?.finished(id: next.id, token: token, outcome: outcome)
                    }
                }
            }
            running[next.id] = Running(
                lane: next.lane, priority: next.priority, token: token, task: task,
                onTerminal: next.onTerminal
            )
        }
    }

    private func nextAdmissibleJob() -> Job? {
        let candidates = queued.values
            .filter { job in
                switch job.lane {
                case .editor:
                    return !running.values.contains(where: { $0.lane == .editor })
                case .thumbnail:
                    return runningThumbnailCount < configuration.maxConcurrentThumbnails
                case .packageIO:
                    return runningPackageIOCount < configuration.maxConcurrentPackageIO
                        && !isEditorContended
                }
            }
        if candidates.isEmpty,
            queued.values.contains(where: { $0.lane == .packageIO }),
            isEditorContended
        {
            yieldedPackageIOCount += 1
        }
        return candidates.min(by: precedes)
    }

    /// A package worker yields to both editor-lane work and active thumbnails. The latter matters
    /// for an edited badge or selected grid cell, which is intentionally scheduled as a thumbnail
    /// job but still represents visible editor demand.
    private var isEditorContended: Bool {
        queued.values.contains { $0.lane == .editor || $0.priority == .activeEditor }
            || running.values.contains { $0.lane == .editor || $0.priority == .activeEditor }
    }

    private func precedes(_ lhs: Job, _ rhs: Job) -> Bool {
        if lhs.priority != rhs.priority { return lhs.priority.rawValue < rhs.priority.rawValue }
        return lhs.sequence < rhs.sequence
    }

    private func updatePeakQueue() {
        peakQueuedThumbnailCount = max(peakQueuedThumbnailCount, pendingThumbnailCount)
        peakQueuedPackageIOCount = max(peakQueuedPackageIOCount, pendingPackageIOCount)
    }

    private func finished(id: JobID, token: UInt64, outcome: TerminalOutcome) {
        guard running[id]?.token == token else { return }
        let active = running.removeValue(forKey: id)
        active?.onTerminal(outcome)
        pump()
    }
}

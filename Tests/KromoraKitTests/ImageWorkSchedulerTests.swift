import Foundation
import XCTest

@testable import KromoraKit

@MainActor
final class ImageWorkSchedulerTests: XCTestCase {

    private actor Gate {
        private var waiters: [CheckedContinuation<Void, Never>] = []

        func wait() async {
            await withCheckedContinuation { waiters.append($0) }
        }

        func releaseAll() {
            let parked = waiters
            waiters.removeAll()
            for waiter in parked { waiter.resume() }
        }
    }

    private actor Probe {
        private(set) var events: [String] = []
        private(set) var ranOnMainActor = false

        func record(_ event: String) {
            events.append(event)
            ranOnMainActor = Thread.isMainThread
        }

        func contains(_ event: String) -> Bool { events.contains(event) }
    }

    func testActiveEditorStartsAheadOfQueuedBackgroundThumbnails() async throws {
        let scheduler = ImageWorkScheduler(
            configuration: .init(
                maxConcurrentThumbnails: 1, maxQueuedThumbnails: 4
            ))
        let gate = Gate()
        var started: [String] = []

        scheduler.enqueue(id: .init("thumb-1"), lane: .thumbnail, priority: .background) {
            started.append("thumb-1")
            await gate.wait()
        }
        try await waitUntil("the first thumbnail to start") { started == ["thumb-1"] }

        scheduler.enqueue(id: .init("thumb-2"), lane: .thumbnail, priority: .background) {
            started.append("thumb-2")
        }
        scheduler.enqueue(id: .init("editor"), lane: .editor, priority: .activeEditor) {
            started.append("editor")
        }

        try await waitUntil("the editor to start") { started.contains("editor") }
        XCTAssertEqual(started.prefix(2), ["thumb-1", "editor"])

        await gate.releaseAll()
        try await waitUntil("the scheduler to drain") { scheduler.isIdle }
    }

    func testAdmissionHistoryIsCappedWhileCumulativeCountersKeepGrowing() async throws {
        let scheduler = ImageWorkScheduler(
            configuration: .init(maxConcurrentThumbnails: 1, maxQueuedThumbnails: 4))
        let total = ImageWorkScheduler.maximumRetainedAdmissions + 20
        for index in 0..<total {
            var finished = false
            scheduler.enqueue(id: .init("job-\(index)"), lane: .thumbnail, priority: .background) {
                finished = true
            }
            try await waitUntil("job \(index)") { finished }
        }
        try await waitUntil("the scheduler to drain") { scheduler.isIdle }
        XCTAssertEqual(scheduler.admissionLog.count, ImageWorkScheduler.maximumRetainedAdmissions)
        XCTAssertEqual(scheduler.admissionCount, total)
        XCTAssertEqual(scheduler.admissionCounts[.thumbnail], total)
        XCTAssertEqual(scheduler.admissionLog.last?.id, .init("job-\(total - 1)"))
    }

    func testQueuedThumbnailCanBeCancelledBeforeItStarts() async throws {
        let scheduler = ImageWorkScheduler(
            configuration: .init(
                maxConcurrentThumbnails: 1, maxQueuedThumbnails: 4
            ))
        let gate = Gate()
        var started: [String] = []

        scheduler.enqueue(id: .init("running"), lane: .thumbnail, priority: .background) {
            started.append("running")
            await gate.wait()
        }
        try await waitUntil("the running thumbnail") { started == ["running"] }

        scheduler.enqueue(id: .init("obsolete"), lane: .thumbnail, priority: .background) {
            started.append("obsolete")
        }
        scheduler.cancel(id: .init("obsolete"))
        await gate.releaseAll()

        try await waitUntil("the scheduler to drain") { scheduler.isIdle }
        XCTAssertEqual(started, ["running"])
        XCTAssertGreaterThanOrEqual(scheduler.cancelledCount, 1)
    }

    func testThumbnailQueueIsBoundedAndRetainsHigherPriorityWork() async throws {
        let scheduler = ImageWorkScheduler(
            configuration: .init(
                maxConcurrentThumbnails: 1, maxQueuedThumbnails: 2
            ))
        let gate = Gate()
        var started: [String] = []

        scheduler.enqueue(id: .init("running"), lane: .thumbnail, priority: .background) {
            started.append("running")
            await gate.wait()
        }
        try await waitUntil("the running thumbnail") { started == ["running"] }

        scheduler.enqueue(id: .init("background-a"), lane: .thumbnail, priority: .background) {
            started.append("background-a")
        }
        scheduler.enqueue(id: .init("background-b"), lane: .thumbnail, priority: .background) {
            started.append("background-b")
        }
        scheduler.enqueue(id: .init("adjacent"), lane: .thumbnail, priority: .adjacentFilmstrip) {
            started.append("adjacent")
        }

        XCTAssertEqual(scheduler.pendingThumbnailCount, 2)
        XCTAssertLessThanOrEqual(scheduler.peakQueuedThumbnailCount, 2)
        XCTAssertGreaterThanOrEqual(scheduler.droppedThumbnailCount, 1)

        await gate.releaseAll()
        try await waitUntil("the scheduler to drain") { scheduler.isIdle }
        XCTAssertEqual(started, ["running", "adjacent", "background-a"])
    }

    func testQueueEvictionCompletesTheEvictedJobExactlyOnce() async throws {
        let scheduler = ImageWorkScheduler(
            configuration: .init(
                maxConcurrentThumbnails: 1, maxQueuedThumbnails: 1
            ))
        let gate = Gate()
        var started = false
        var outcomes: [String: [ImageWorkScheduler.TerminalOutcome]] = [:]
        let record: @MainActor (String, ImageWorkScheduler.TerminalOutcome) -> Void = {
            id, outcome in outcomes[id, default: []].append(outcome)
        }

        scheduler.enqueue(id: .init("running"), lane: .thumbnail, priority: .background) {
            started = true
            await gate.wait()
        }
        try await waitUntil("the running thumbnail") { started }

        scheduler.enqueue(
            id: .init("evicted"), lane: .thumbnail, priority: .background,
            onTerminal: { record("evicted", $0) }, operation: {}
        )
        scheduler.enqueue(
            id: .init("replacement"), lane: .thumbnail, priority: .adjacentFilmstrip,
            onTerminal: { record("replacement", $0) }, operation: {}
        )

        XCTAssertEqual(outcomes["evicted"], [.evicted])
        XCTAssertTrue(outcomes["replacement", default: []].isEmpty)
        await gate.releaseAll()
        try await waitUntil("the scheduler to drain") { scheduler.isIdle }
        XCTAssertEqual(outcomes["replacement"], [.completed])
    }

    func testCancelAllCompletesQueuedAndRunningJobsExactlyOnce() async throws {
        let scheduler = ImageWorkScheduler(
            configuration: .init(
                maxConcurrentThumbnails: 1, maxQueuedThumbnails: 2
            ))
        let gate = Gate()
        var outcomes: [String: [ImageWorkScheduler.TerminalOutcome]] = [:]
        func record(_ id: String, _ outcome: ImageWorkScheduler.TerminalOutcome) {
            outcomes[id, default: []].append(outcome)
        }

        scheduler.enqueue(
            id: .init("running"), lane: .thumbnail, priority: .background,
            onTerminal: { record("running", $0) }, operation: { await gate.wait() }
        )
        try await waitUntil("the running thumbnail") { scheduler.runningThumbnailCount == 1 }
        scheduler.enqueue(
            id: .init("queued"), lane: .thumbnail, priority: .background,
            onTerminal: { record("queued", $0) }, operation: {}
        )

        scheduler.cancelAll()
        XCTAssertEqual(outcomes["running"], [.cancelled])
        XCTAssertEqual(outcomes["queued"], [.cancelled])
        XCTAssertEqual(scheduler.runningCount, 0)
        XCTAssertEqual(scheduler.pendingCount, 0)
        await gate.releaseAll()
        try await Task.sleep(for: .milliseconds(10))
        XCTAssertEqual(outcomes["running"], [.cancelled])
    }

    func testRejectedJobReportsItsTerminalOutcome() {
        let scheduler = ImageWorkScheduler(
            configuration: .init(
                maxConcurrentThumbnails: 0, maxQueuedThumbnails: 0
            ))
        var outcomes: [ImageWorkScheduler.TerminalOutcome] = []

        let admitted = scheduler.enqueue(
            id: .init("rejected"), lane: .thumbnail, priority: .visibleGrid,
            onTerminal: { outcomes.append($0) }, operation: {}
        )

        XCTAssertFalse(admitted)
        XCTAssertEqual(outcomes, [.rejected])
    }

    func testSuccessfulJobReportsCompletion() async throws {
        let scheduler = ImageWorkScheduler(
            configuration: .init(
                maxConcurrentThumbnails: 1, maxQueuedThumbnails: 1
            ))
        var outcomes: [ImageWorkScheduler.TerminalOutcome] = []

        scheduler.enqueue(
            id: .init("success"), lane: .thumbnail, priority: .visibleGrid,
            onTerminal: { outcomes.append($0) }, operation: {}
        )

        try await waitUntil("the successful job") { scheduler.isIdle }
        XCTAssertEqual(outcomes, [.completed])
    }

    func testThumbnailRunsImmediatelyWhenTheQueueIsDisabled() async throws {
        let scheduler = ImageWorkScheduler(
            configuration: .init(
                maxConcurrentThumbnails: 2, maxQueuedThumbnails: 0
            ))
        var started: [String] = []

        scheduler.enqueue(id: .init("thumb"), lane: .thumbnail, priority: .background) {
            started.append("thumb")
        }

        try await waitUntil("the thumbnail to run despite no queue capacity") {
            started == ["thumb"]
        }
        XCTAssertEqual(scheduler.droppedThumbnailCount, 0)
    }

    func testVisibleEditorDropsQueuedSupportBeforeItIsAdmitted() async throws {
        let scheduler = ImageWorkScheduler(
            configuration: .init(
                maxConcurrentThumbnails: 1, maxQueuedThumbnails: 4, maxQueuedEditorJobs: 2
            ))
        let gate = Gate()
        var started: [String] = []

        scheduler.enqueue(id: .init("support-running"), lane: .editor, priority: .histogram) {
            started.append("support-running")
            await gate.wait()
        }
        try await waitUntil("the support job to start") { started == ["support-running"] }

        scheduler.enqueue(id: .init("comparison"), lane: .editor, priority: .comparison) {
            started.append("comparison")
        }
        scheduler.enqueue(id: .init("visible"), lane: .editor, priority: .activeEditor) {
            started.append("visible")
        }

        XCTAssertEqual(scheduler.pendingEditorCount, 1)
        XCTAssertGreaterThanOrEqual(scheduler.droppedEditorCount, 1)

        await gate.releaseAll()
        try await waitUntil("the scheduler to drain") { scheduler.isIdle }
        XCTAssertEqual(started, ["support-running", "visible"])
    }

    /// KRMA-1147: an empty Original pane was blank until the full settled render finished because
    /// the newer Adjusted job evicted the queued Original and it ran only after that render.
    func testPinnedComparisonSurvivesActiveEditorAndStartsFirst() async throws {
        let scheduler = ImageWorkScheduler(
            configuration: .init(maxConcurrentThumbnails: 1, maxQueuedThumbnails: 4, maxQueuedEditorJobs: 4))
        let gate = Gate()
        var started: [String] = []

        scheduler.enqueue(id: .init("running"), lane: .editor, priority: .activeEditor) {
            started.append("running")
            await gate.wait()
        }
        try await waitUntil("the first job to start") { started == ["running"] }

        scheduler.enqueue(id: .init("original"), lane: .editor, priority: .comparison, pinned: true) {
            started.append("original")
        }
        scheduler.enqueue(id: .init("unpinned"), lane: .editor, priority: .comparison) {
            started.append("unpinned")
        }
        scheduler.enqueue(id: .init("settled"), lane: .editor, priority: .activeEditor) {
            started.append("settled")
        }

        await gate.releaseAll()
        try await waitUntil("the scheduler to drain") { scheduler.isIdle }
        XCTAssertEqual(started, ["running", "original", "settled"])
    }

    func testPackageIOUsesSharedLaneAndYieldsWhileEditorIsActive() async throws {
        let scheduler = ImageWorkScheduler(configuration: .init(
            maxConcurrentThumbnails: 1,
            maxQueuedThumbnails: 2,
            maxQueuedEditorJobs: 2,
            maxConcurrentPackageIO: 1,
            maxQueuedPackageIO: 2
        ))
        let editorGate = Gate()
        let probe = Probe()

        scheduler.enqueue(id: .init("active-editor"), lane: .editor, priority: .activeEditor) {
            await editorGate.wait()
        }
        try await waitUntil("the active editor to start") { scheduler.runningEditorCount == 1 }

        scheduler.enqueuePackageIO(
            id: .init("rebuild"), lane: .indexRebuild,
            operation: { await probe.record("rebuild") }
        )

        try await Task.sleep(for: .milliseconds(40))
        let rebuildStartedWhileEditing = await probe.contains("rebuild")
        XCTAssertFalse(rebuildStartedWhileEditing)
        XCTAssertEqual(scheduler.pendingPackageIOCount, 1)
        XCTAssertGreaterThan(scheduler.yieldedPackageIOCount, 0)

        await editorGate.releaseAll()
        try await waitUntilAsync("package I/O to run after the editor") {
            await probe.contains("rebuild")
        }
        let packageRanOnMainActor = await probe.ranOnMainActor
        XCTAssertFalse(packageRanOnMainActor)
        try await waitUntil("the scheduler to drain") { scheduler.isIdle }
    }

    func testQueuedMaintenanceYieldsToEditorArrivingWhilePackageIOIsBusy() async throws {
        let scheduler = ImageWorkScheduler(configuration: .init(
            maxConcurrentThumbnails: 1,
            maxQueuedThumbnails: 1,
            maxQueuedEditorJobs: 2,
            maxConcurrentPackageIO: 1,
            maxQueuedPackageIO: 2
        ))
        let packageGate = Gate()
        let probe = Probe()

        scheduler.enqueuePackageIO(
            id: .init("package-blocker"), lane: .importCopyHash,
            operation: {
                await probe.record("blocker-started")
                await packageGate.wait()
            }
        )
        try await waitUntilAsync("the package blocker to start") {
            await probe.contains("blocker-started")
        }
        scheduler.enqueuePackageIO(
            id: .init("maintenance"), lane: .maintenance,
            operation: { await probe.record("maintenance") }
        )
        scheduler.enqueue(
            id: .init("editor"), lane: .editor, priority: .activeEditor,
            operation: { await probe.record("editor") }
        )

        await packageGate.releaseAll()
        try await waitUntilAsync("editor and maintenance to run") {
            let editorRan = await probe.contains("editor")
            let maintenanceRan = await probe.contains("maintenance")
            return editorRan && maintenanceRan
        }
        let events = await probe.events
        XCTAssertEqual(Array(events.prefix(3)), ["blocker-started", "editor", "maintenance"])
        XCTAssertGreaterThan(scheduler.yieldedPackageIOCount, 0)
        try await waitUntil("the scheduler to drain") { scheduler.isIdle }
    }

    func testActiveThumbnailAlsoPreventsBackgroundPackageIOFromStarting() async throws {
        let scheduler = ImageWorkScheduler(configuration: .init(
            maxConcurrentThumbnails: 1,
            maxQueuedThumbnails: 1,
            maxConcurrentPackageIO: 1,
            maxQueuedPackageIO: 1
        ))
        let thumbnailGate = Gate()
        let probe = Probe()

        scheduler.enqueue(id: .init("active-thumbnail"), lane: .thumbnail, priority: .activeEditor) {
            await thumbnailGate.wait()
        }
        try await waitUntil("the active thumbnail to start") { scheduler.runningThumbnailCount == 1 }
        scheduler.enqueuePackageIO(
            id: .init("maintenance"), lane: .maintenance,
            operation: { await probe.record("maintenance") }
        )

        try await Task.sleep(for: .milliseconds(40))
        let maintenanceStartedWhileEditing = await probe.contains("maintenance")
        XCTAssertFalse(maintenanceStartedWhileEditing)
        XCTAssertEqual(scheduler.pendingPackageIOCount, 1)

        await thumbnailGate.releaseAll()
        try await waitUntilAsync("maintenance to run after the thumbnail") {
            await probe.contains("maintenance")
        }
        try await waitUntil("the scheduler to drain") { scheduler.isIdle }
    }

    func testImportPriorityIsAheadOfIdlePackageMaintenance() async throws {
        let scheduler = ImageWorkScheduler(configuration: .init(
            maxConcurrentThumbnails: 1,
            maxQueuedThumbnails: 2,
            maxConcurrentPackageIO: 1,
            maxQueuedPackageIO: 2
        ))
        let gate = Gate()
        let probe = Probe()
        let admissionStart = scheduler.admissionLog.count

        scheduler.enqueuePackageIO(
            id: .init("import"), lane: .importCopyHash,
            operation: {
                await probe.record("import-started")
                await gate.wait()
            }
        )
        try await waitUntilAsync("the import worker to start") {
            await probe.contains("import-started")
        }
        scheduler.enqueuePackageIO(
            id: .init("maintenance"), lane: .maintenance,
            operation: {}
        )

        let admissions = Array(scheduler.admissionLog.dropFirst(admissionStart))
        XCTAssertEqual(admissions.map(\.priority), [.packageIO, .background])

        await gate.releaseAll()
        try await waitUntil("the package scheduler to drain", timeout: 10) { scheduler.isIdle }
    }

    // MARK: Cancelled work keeps its slot until the operation returns

    /// Counts operations independently of the scheduler's dictionaries, so a scheduler that forgets
    /// a cancelled-but-still-executing job cannot also under-report it here.
    private actor Executions {
        private(set) var entered = 0
        private(set) var exited = 0
        private(set) var peak = 0
        private var isOpen = false
        private var waiters: [CheckedContinuation<Void, Never>] = []

        var current: Int { entered - exited }

        /// A non-cooperative operation: it parks on a continuation and ignores cancellation.
        func run() async {
            entered += 1
            peak = max(peak, entered - exited)
            if !isOpen { await withCheckedContinuation { waiters.append($0) } }
            exited += 1
        }

        func open() {
            isOpen = true
            let parked = waiters
            waiters.removeAll()
            for waiter in parked { waiter.resume() }
        }
    }

    private enum LaneUnderTest: CaseIterable {
        case thumbnail, editor, packageIO, frameRead
    }

    private func makeLimitedScheduler() -> ImageWorkScheduler {
        ImageWorkScheduler(configuration: .init(
            maxConcurrentThumbnails: 1, maxQueuedThumbnails: 4,
            maxQueuedEditorJobs: 4,
            maxConcurrentPackageIO: 1, maxQueuedPackageIO: 4,
            maxConcurrentFrameReads: 1, maxQueuedFrameReads: 4
        ))
    }

    @discardableResult
    private func enqueueGated(
        _ lane: LaneUnderTest, id: String, on scheduler: ImageWorkScheduler,
        executions: Executions,
        onTerminal: @escaping ImageWorkScheduler.TerminalHandler = { _ in }
    ) -> Bool {
        let jobID = ImageWorkScheduler.JobID(id)
        switch lane {
        case .thumbnail:
            return scheduler.enqueue(
                id: jobID, lane: .thumbnail, priority: .visibleGrid, onTerminal: onTerminal,
                operation: { await executions.run() })
        case .editor:
            return scheduler.enqueue(
                id: jobID, lane: .editor, priority: .activeEditor, onTerminal: onTerminal,
                operation: { await executions.run() })
        case .packageIO:
            return scheduler.enqueuePackageIO(
                id: jobID, lane: .importCopyHash, onTerminal: onTerminal,
                operation: { await executions.run() })
        case .frameRead:
            return scheduler.enqueueFrameRead(
                id: jobID, onTerminal: onTerminal, operation: { await executions.run() })
        }
    }

    func testCancelledOperationKeepsItsLaneSlotUntilItReturns() async throws {
        for lane in LaneUnderTest.allCases {
            let scheduler = makeLimitedScheduler()
            let executions = Executions()
            var outcomes: [ImageWorkScheduler.TerminalOutcome] = []

            enqueueGated(lane, id: "first", on: scheduler, executions: executions)
            try await waitUntilAsync("\(lane): the first operation to enter") {
                await executions.current == 1
            }
            scheduler.cancel(id: .init("first"))
            enqueueGated(
                lane, id: "second", on: scheduler, executions: executions,
                onTerminal: { outcomes.append($0) })

            // Give a (buggy) scheduler time to start the replacement on the freed slot.
            try await Task.sleep(for: .milliseconds(50))
            let entered = await executions.entered
            let peak = await executions.peak
            XCTAssertEqual(entered, 1, "\(lane): replacement started while the cancelled op ran")
            XCTAssertEqual(peak, 1, "\(lane)")
            XCTAssertEqual(scheduler.drainingCount, 1, "\(lane)")
            XCTAssertFalse(scheduler.isIdle, "\(lane)")

            await executions.open()
            try await waitUntil("\(lane): the scheduler to drain") { scheduler.isIdle }
            let finalPeak = await executions.peak
            let finalEntered = await executions.entered
            let finalExited = await executions.exited
            XCTAssertEqual(finalPeak, 1, "\(lane)")
            XCTAssertEqual(finalEntered, 2, "\(lane)")
            XCTAssertEqual(finalExited, 2, "\(lane)")
            XCTAssertEqual(outcomes, [.completed], "\(lane)")
        }
    }

    func testRepeatedJobIDReuseNeverExceedsTheLaneLimit() async throws {
        for lane in LaneUnderTest.allCases {
            let scheduler = makeLimitedScheduler()
            let executions = Executions()
            var outcomes: [String: [ImageWorkScheduler.TerminalOutcome]] = [:]

            for generation in 0..<8 {
                let key = "g\(generation)"
                enqueueGated(
                    lane, id: "same", on: scheduler, executions: executions,
                    onTerminal: { outcomes[key, default: []].append($0) })
                try await Task.sleep(for: .milliseconds(5))
                let current = await executions.current
                XCTAssertLessThanOrEqual(current, 1, "\(lane) generation \(generation)")
            }
            let peak = await executions.peak
            XCTAssertEqual(peak, 1, "\(lane)")

            await executions.open()
            await scheduler.cancelAllAndWait()
            XCTAssertTrue(scheduler.isIdle, "\(lane)")
            XCTAssertEqual(scheduler.runningCount, 0, "\(lane)")
            XCTAssertEqual(scheduler.drainingCount, 0, "\(lane)")
            let finalPeak = await executions.peak
            let entered = await executions.entered
            let exited = await executions.exited
            XCTAssertEqual(finalPeak, 1, "\(lane)")
            XCTAssertEqual(entered, exited, "\(lane)")
            // Every generation was told exactly once, however it ended.
            for generation in 0..<8 {
                XCTAssertEqual(outcomes["g\(generation)"]?.count, 1, "\(lane) g\(generation)")
            }
        }
    }

    func testCancelAllAndWaitBlocksOnPreviouslyCancelledOperations() async throws {
        for lane in LaneUnderTest.allCases {
            let scheduler = makeLimitedScheduler()
            let executions = Executions()
            var outcomes: [ImageWorkScheduler.TerminalOutcome] = []

            enqueueGated(
                lane, id: "job", on: scheduler, executions: executions,
                onTerminal: { outcomes.append($0) })
            try await waitUntilAsync("\(lane): the operation to enter") {
                await executions.current == 1
            }
            // Cancelled first, so it is no longer in `running` when the barrier starts.
            scheduler.cancel(id: .init("job"))
            XCTAssertEqual(scheduler.runningCount, 0, "\(lane)")

            var barrierReturned = false
            let barrier = Task { @MainActor in
                await scheduler.cancelAllAndWait()
                barrierReturned = true
            }
            try await Task.sleep(for: .milliseconds(50))
            XCTAssertFalse(barrierReturned, "\(lane): barrier returned with work still running")
            let during = await executions.current
            XCTAssertEqual(during, 1, "\(lane)")

            await executions.open()
            await barrier.value
            let exited = await executions.exited
            XCTAssertEqual(exited, 1, "\(lane)")
            XCTAssertTrue(scheduler.isIdle, "\(lane)")
            XCTAssertEqual(outcomes, [.cancelled], "\(lane)")
        }
    }

    func testCancelAndWaitCoversAnOperationCancelledEarlier() async throws {
        let scheduler = makeLimitedScheduler()
        let executions = Executions()
        enqueueGated(.packageIO, id: "writer", on: scheduler, executions: executions)
        try await waitUntilAsync("the writer to enter") { await executions.current == 1 }
        scheduler.cancel(id: .init("writer"))

        var returned = false
        let waiter = Task { @MainActor in
            await scheduler.cancelAndWait(id: .init("writer"))
            returned = true
        }
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertFalse(returned)
        await executions.open()
        await waiter.value
        let exited = await executions.exited
        XCTAssertEqual(exited, 1)
    }

    func testCancelledEditorStillYieldsBackgroundWorkUntilItReturns() async throws {
        let scheduler = makeLimitedScheduler()
        let editor = Executions()
        let frameRead = Executions()
        let packageIO = Executions()

        enqueueGated(.editor, id: "editor", on: scheduler, executions: editor)
        try await waitUntilAsync("the editor operation to enter") { await editor.current == 1 }
        scheduler.cancel(id: .init("editor"))

        enqueueGated(.frameRead, id: "frame-read", on: scheduler, executions: frameRead)
        scheduler.enqueuePackageIO(
            id: .init("maintenance"), lane: .maintenance,
            operation: { await packageIO.run() })

        try await Task.sleep(for: .milliseconds(50))
        let frameReadEntered = await frameRead.entered
        let packageIOEntered = await packageIO.entered
        XCTAssertEqual(frameReadEntered, 0, "frame reads must yield to draining editor work")
        XCTAssertEqual(packageIOEntered, 0, "background package I/O must yield to draining editor work")

        await editor.open()
        try await waitUntilAsync("background work to start after the editor returns") {
            let frameReadCurrent = await frameRead.current
            let packageIOCurrent = await packageIO.current
            return frameReadCurrent == 1 && packageIOCurrent == 1
        }
        await frameRead.open()
        await packageIO.open()
        try await waitUntil("the scheduler to drain") { scheduler.isIdle }
    }

    private func waitUntil(
        _ description: String,
        timeout: TimeInterval = 2,
        _ condition: @escaping @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline { return XCTFail("timed out waiting for \(description)") }
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    private func waitUntilAsync(
        _ description: String,
        timeout: TimeInterval = 10,
        _ condition: @escaping @MainActor () async -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !(await condition()) {
            if Date() > deadline { return XCTFail("timed out waiting for \(description)") }
            try await Task.sleep(for: .milliseconds(5))
        }
    }
}

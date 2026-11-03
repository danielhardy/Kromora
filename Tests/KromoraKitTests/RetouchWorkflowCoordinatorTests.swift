import AppKit
import os
import XCTest
@testable import KromoraKit

@MainActor
final class RetouchWorkflowCoordinatorTests: XCTestCase {
    private func waitUntil(
        _ description: String,
        timeout: Duration = .seconds(30),
        _ condition: @MainActor () -> Bool
    ) async throws {
        let deadline = ContinuousClock.now + timeout
        while !condition() {
            if ContinuousClock.now >= deadline {
                throw TestSynchronizationError.timedOut(description, "condition did not settle")
            }
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    func testClickAndDragCommitOneSpotEach() {
        let destination = FakeRetouchDestination()
        let workflow = RetouchWorkflowCoordinator(destination: destination)
        XCTAssertEqual(workflow.interactionState.mode, .heal)
        workflow.setArmed(true)
        workflow.beginGesture(at: CGPoint(x: 0.2, y: 0.3))
        workflow.endGesture()
        XCTAssertEqual(destination.document.retouch.spots.count, 1)
        XCTAssertEqual(destination.documentUpdates, 1)
        XCTAssertEqual(destination.document.retouch.spots[0].region.samples.first?.point, CGPoint(x: 0.2, y: 0.3))
        XCTAssertEqual(destination.document.retouch.spots[0].mode, .heal)

        workflow.beginGesture(at: CGPoint(x: 0.4, y: 0.4))
        workflow.updateGesture(to: CGPoint(x: 0.5, y: 0.5))
        workflow.updateGesture(to: CGPoint(x: 0.6, y: 0.55))
        workflow.endGesture()
        XCTAssertEqual(destination.document.retouch.spots.count, 2)
        XCTAssertEqual(destination.documentUpdates, 2)
        XCTAssertGreaterThan(destination.document.retouch.spots[1].region.samples.count, 1)
    }

    func testShiftClickChainsSegmentAndDestinationMoveCommitsOnce() {
        let destination = FakeRetouchDestination()
        let workflow = RetouchWorkflowCoordinator(destination: destination)
        workflow.setArmed(true)
        workflow.beginGesture(at: CGPoint(x: 0.2, y: 0.2))
        workflow.endGesture()
        workflow.beginGesture(at: CGPoint(x: 0.8, y: 0.8), modifiers: [.shift])
        workflow.updateGesture(to: CGPoint(x: 0.8, y: 0.8))
        workflow.endGesture()
        let wire = try! XCTUnwrap(destination.document.retouch.spots.last)
        XCTAssertGreaterThan(wire.region.samples.count, 1)
        XCTAssertEqual(wire.region.samples.first?.point, CGPoint(x: 0.2, y: 0.2))
        XCTAssertEqual(wire.region.samples.last?.point, CGPoint(x: 0.8, y: 0.8))
        XCTAssertEqual(destination.documentUpdates, 2)

        workflow.beginGesture(at: CGPoint(x: 0.2, y: 0.2))
        workflow.updateGesture(to: CGPoint(x: 0.25, y: 0.25))
        workflow.endGesture()
        XCTAssertEqual(destination.documentUpdates, 3)
        XCTAssertEqual(destination.document.retouch.spots[1].region.samples[0].point, CGPoint(x: 0.25, y: 0.25))
    }

    func testSourceHandleSwitchesToManualAndDeleteRemovesSpot() {
        let destination = FakeRetouchDestination()
        var spot = RetouchSpot(mode: .heal, region: RetouchRegion(samples: [BrushSample(point: CGPoint(x: 0.4,y:0.4))], radius: 0.05), source: .auto(offset: CGVector(dx: 0.1,dy:0), rank: 0))
        destination.document.retouch.spots = [spot]
        let workflow = RetouchWorkflowCoordinator(destination: destination)
        workflow.setArmed(true)
        workflow.beginGesture(at: CGPoint(x: 0.55, y: 0.4))
        workflow.updateGesture(to: CGPoint(x: 0.6, y: 0.5))
        workflow.endGesture()
        spot = try! XCTUnwrap(destination.document.retouch.spots.first)
        guard case .manual(let offset)? = spot.source else { return XCTFail("Expected a manual source") }
        XCTAssertEqual(offset.dx, 0.2, accuracy: 0.0001)
        XCTAssertEqual(offset.dy, 0.1, accuracy: 0.0001)
        XCTAssertEqual(destination.documentUpdates, 1)
        workflow.deleteSelected()
        XCTAssertTrue(destination.document.retouch.spots.isEmpty)
    }

    func testMovingDestinationKeepsManualSourceAtAbsolutePoint() {
        let destination = FakeRetouchDestination()
        let spot = RetouchSpot(
            mode: .clone,
            region: RetouchRegion(samples: [BrushSample(point: CGPoint(x: 0.4, y: 0.4))], radius: 0.05),
            source: .manual(offset: CGVector(dx: 0.1, dy: 0))
        )
        destination.document.retouch.spots = [spot]
        let workflow = RetouchWorkflowCoordinator(destination: destination)
        workflow.setArmed(true)
        workflow.beginGesture(at: CGPoint(x: 0.4, y: 0.4))
        workflow.updateGesture(to: CGPoint(x: 0.45, y: 0.45))
        workflow.endGesture()
        let moved = try! XCTUnwrap(destination.document.retouch.spots.first)
        XCTAssertEqual(moved.region.samples.first?.point, CGPoint(x: 0.45, y: 0.45))
        guard case .manual(let offset)? = moved.source else { return XCTFail("Expected a manual source") }
        XCTAssertEqual(offset.dx, 0.05, accuracy: 0.0001)
        XCTAssertEqual(offset.dy, -0.05, accuracy: 0.0001)
        XCTAssertEqual(destination.documentUpdates, 1)
    }

    func testAutomaticSourcePickGroupsWithGestureCommitForOneUndoEntry() async throws {
        let destination = FakeRetouchDestination()
        let workflow = RetouchWorkflowCoordinator(destination: destination)
        workflow.interactionState.mode = .heal
        workflow.setArmed(true)
        workflow.beginGesture(at: CGPoint(x: 0.3, y: 0.3))
        workflow.endGesture()
        XCTAssertEqual(destination.undoGroupingDepth, 1)
        try await Task.sleep(for: .milliseconds(5))
        XCTAssertEqual(destination.undoGroupingDepth, 0)

        var spot = try XCTUnwrap(destination.document.retouch.spots.first)
        spot.source = .auto(offset: CGVector(dx: 0.05, dy: 0), rank: 0)
        destination.document.retouch.spots = [spot]
        workflow.beginGesture(at: CGPoint(x: 0.3, y: 0.3))
        workflow.updateGesture(to: CGPoint(x: 0.35, y: 0.35))
        workflow.endGesture()
        XCTAssertEqual(destination.undoGroupingDepth, 1)
        try await Task.sleep(for: .milliseconds(5))
        XCTAssertEqual(destination.undoGroupingDepth, 0)
    }

    func testAcceptOneAcceptAllDismissAndDragSuggestion() throws {
        let destination = FakeRetouchDestination()
        let workflow = RetouchWorkflowCoordinator(destination: destination)
        let first = RetouchDustSuggestion(id: UUID(), point: CGPoint(x: 0.3, y: 0.4), radius: 0.02, confidence: 0.8, seed: 123)
        let second = RetouchDustSuggestion(id: UUID(), point: CGPoint(x: 0.7, y: 0.6), radius: 0.03, confidence: 0.9, seed: 456)
        let owner = Self.source("A")
        destination.retouchAnalysisSource = owner
        workflow.install([first, second], owner: owner.cacheFingerprint)
        workflow.setArmed(true)
        workflow.beginGesture(at: first.point)
        workflow.updateGesture(to: CGPoint(x: 0.32, y: 0.42))
        workflow.endGesture()
        XCTAssertEqual(workflow.interactionState.dustSuggestions.first?.point, CGPoint(x: 0.32, y: 0.42))
        workflow.beginGesture(at: CGPoint(x: 0.336, y: 0.42))
        workflow.updateGesture(to: CGPoint(x: 0.344, y: 0.42))
        workflow.endGesture()
        XCTAssertEqual(workflow.interactionState.dustSuggestions.first?.point, CGPoint(x: 0.32, y: 0.42))
        XCTAssertEqual(try XCTUnwrap(workflow.interactionState.dustSuggestions.first).radius, 0.03, accuracy: 0.0001)
        workflow.acceptDustSuggestion(first.id)
        let accepted = try XCTUnwrap(destination.document.retouch.spots.first)
        XCTAssertEqual(accepted.id, first.id)
        XCTAssertEqual(accepted.seed, first.seed)
        XCTAssertEqual(accepted.mode, .heal)
        XCTAssertEqual(accepted.region.samples.first?.point, CGPoint(x: 0.32, y: 0.42))
        workflow.acceptAllDustSuggestions()
        XCTAssertEqual(destination.document.retouch.spots.count, 2)
        XCTAssertEqual(destination.undoGroupingDepth, 0)
        XCTAssertTrue(workflow.interactionState.dustSuggestions.isEmpty)

        workflow.interactionState.setDustSuggestions([first])
        workflow.dismissDustSuggestion(first.id)
        XCTAssertTrue(workflow.interactionState.dustSuggestions.isEmpty)
        workflow.interactionState.setDustSuggestions([first])
        workflow.dismissAllDustSuggestions()
        XCTAssertTrue(workflow.interactionState.dustSuggestions.isEmpty)
    }

    func testClickingCanvasSuggestionAcceptsIt() {
        let destination = FakeRetouchDestination()
        let workflow = RetouchWorkflowCoordinator(destination: destination)
        let suggestion = RetouchDustSuggestion(id: UUID(), point: CGPoint(x: 0.4, y: 0.45), radius: 0.02, confidence: 0.8, seed: 71)
        let owner = Self.source("A")
        destination.retouchAnalysisSource = owner
        workflow.install([suggestion], owner: owner.cacheFingerprint)
        workflow.setArmed(true)
        workflow.beginGesture(at: suggestion.point)
        workflow.endGesture()
        XCTAssertEqual(destination.document.retouch.spots.map(\.id), [suggestion.id])
        XCTAssertTrue(workflow.interactionState.dustSuggestions.isEmpty)
    }
}

// MARK: - Source-pick lifecycle (KRMA-1158)

extension RetouchWorkflowCoordinatorTests {
    /// Suspends each pick until the test releases it, by rank.
    @MainActor private final class PickGates {
        private var continuations: [Int: [CheckedContinuation<Void, Never>]] = [:]
        private(set) var arrivals: [Int] = []
        func wait(_ rank: Int) async {
            arrivals.append(rank)
            await withCheckedContinuation { continuations[rank, default: []].append($0) }
        }
        func release(_ rank: Int) { continuations.removeValue(forKey: rank)?.forEach { $0.resume() } }
        func releaseAll() { for rank in Array(continuations.keys) { release(rank) } }
    }

    @MainActor private final class DrainFlag { var value = false }

    private func makePickHarness(_ tag: String = "A") -> (FakeRetouchDestination, RetouchWorkflowCoordinator, PickGates) {
        let destination = FakeRetouchDestination()
        destination.retouchAnalysisSource = Self.source(tag)
        let gates = PickGates()
        destination.pickProvider = { rank in await gates.wait(rank); return true }
        let workflow = RetouchWorkflowCoordinator(destination: destination)
        workflow.setArmed(true)
        return (destination, workflow, gates)
    }

    private func clickToCreateSpot(_ workflow: RetouchWorkflowCoordinator, at point: CGPoint = CGPoint(x: 0.3, y: 0.3)) {
        workflow.beginGesture(at: point)
        workflow.endGesture()
    }

    func testDelayedPickAfterNavigationDoesNotCloseNewPhotosUndoGroupOrMutateIt() async throws {
        let (destination, workflow, gates) = makePickHarness("A")
        clickToCreateSpot(workflow)
        XCTAssertEqual(destination.undoGroupingDepth, 1)
        while gates.arrivals.isEmpty { try await Task.sleep(for: .milliseconds(5)) }

        // Navigate to B, which opens its own undo group, then release A's pick.
        destination.retouchAnalysisSource = Self.source("B")
        destination.document = EditDocument()
        destination.undoGroupingDepth = 0
        workflow.activeSourceDidChange()
        destination.beginUndoGrouping()
        let updatesBefore = destination.documentUpdates
        gates.releaseAll()
        await workflow.shutdown()

        XCTAssertEqual(destination.undoGroupingDepth, 1, "A's late pick must not end B's undo group")
        XCTAssertEqual(destination.documentUpdates, updatesBefore)
        XCTAssertTrue(destination.pickPublications.isEmpty)
        XCTAssertTrue(workflow.interactionState.solvingSpotIDs.isEmpty)
    }

    func testStalePickCannotCloseUndoGroupOfNewGestureOnNewPhoto() async throws {
        let (destination, workflow, gates) = makePickHarness("A")
        clickToCreateSpot(workflow)
        while gates.arrivals.isEmpty { try await Task.sleep(for: .milliseconds(5)) }
        destination.retouchAnalysisSource = Self.source("B")
        destination.document = EditDocument()
        destination.undoGroupingDepth = 0
        workflow.activeSourceDidChange()

        // A new gesture on B is in flight with its own (gated) pick.
        clickToCreateSpot(workflow, at: CGPoint(x: 0.6, y: 0.6))
        XCTAssertEqual(destination.undoGroupingDepth, 1)
        while gates.arrivals.count < 2 { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertEqual(gates.arrivals, [0, 0])
        gates.releaseAll()
        try await waitUntil("new photo's pick to finish") { destination.undoGroupingDepth == 0 }
        await workflow.shutdown()
        // Only the pick for B's spot published; A's stale pick neither wrote nor closed B's group.
        XCTAssertEqual(destination.pickPublications, [0])
        XCTAssertEqual(destination.document.retouch.spots.count, 1)
        XCTAssertEqual(destination.undoGroupingDepth, 0)
    }

    func testOutOfOrderNextSourceCompletionsApplyOnlyNewest() async throws {
        let (destination, workflow, gates) = makePickHarness()
        var spot = RetouchSpot(mode: .heal,
                               region: RetouchRegion(samples: [BrushSample(point: CGPoint(x: 0.4, y: 0.4))], radius: 0.05),
                               source: .auto(offset: CGVector(dx: 0.1, dy: 0), rank: 0))
        destination.document.retouch.spots = [spot]
        workflow.interactionState.select(spot.id)

        workflow.nextSource()                       // rank 1
        while gates.arrivals.count < 1 { try await Task.sleep(for: .milliseconds(5)) }
        spot.source = .auto(offset: CGVector(dx: 0.1, dy: 0), rank: 1)
        destination.document.retouch.spots = [spot]
        workflow.nextSource()                       // rank 2 supersedes rank 1
        while gates.arrivals.count < 2 { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertEqual(gates.arrivals, [1, 2])

        gates.release(2)
        try await waitUntil("newest pick to publish") { destination.pickPublications == [2] }
        gates.release(1)                            // the older request finishes last
        await workflow.shutdown()
        XCTAssertEqual(destination.pickPublications, [2])
        guard case .auto(_, let rank)? = destination.document.retouch.spots.first?.source else {
            return XCTFail("Expected an automatic source")
        }
        XCTAssertEqual(rank, 2)
        XCTAssertTrue(workflow.interactionState.solvingSpotIDs.isEmpty)
    }

    func testAssetDeletionDuringPickDropsResult() async throws {
        let (destination, workflow, gates) = makePickHarness()
        clickToCreateSpot(workflow)
        while gates.arrivals.isEmpty { try await Task.sleep(for: .milliseconds(5)) }
        // The open photo is removed.
        destination.retouchAnalysisSource = nil
        destination.document = EditDocument()
        workflow.activeSourceDidChange()
        let updatesBefore = destination.documentUpdates
        gates.releaseAll()
        await workflow.shutdown()
        XCTAssertEqual(destination.documentUpdates, updatesBefore)
        XCTAssertTrue(destination.pickPublications.isEmpty)
        XCTAssertTrue(workflow.interactionState.solvingSpotIDs.isEmpty)
    }

    func testShutdownDrainsPickAndRejectsNewCommands() async throws {
        let (destination, workflow, gates) = makePickHarness()
        clickToCreateSpot(workflow)
        while gates.arrivals.isEmpty { try await Task.sleep(for: .milliseconds(5)) }
        let updatesBefore = destination.documentUpdates

        let shutdown = Task { await workflow.shutdown() }
        // Shutdown must wait for the owned pick rather than abandon it.
        try await Task.sleep(for: .milliseconds(30))
        let drained = DrainFlag()
        Task { await shutdown.value; drained.value = true }
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertFalse(drained.value)
        gates.releaseAll()
        await shutdown.value

        XCTAssertEqual(destination.documentUpdates, updatesBefore)
        XCTAssertTrue(destination.pickPublications.isEmpty)
        XCTAssertEqual(destination.undoGroupingDepth, 1, "no undo callback may arrive after the barrier")

        // Admission is closed.
        workflow.beginGesture(at: CGPoint(x: 0.5, y: 0.5))
        workflow.endGesture()
        workflow.nextSource()
        workflow.deleteSpot(destination.document.retouch.spots[0].id)
        XCTAssertEqual(destination.documentUpdates, updatesBefore)
        XCTAssertEqual(destination.pickedRanks, [0])
    }
}

// MARK: - Analysis lifecycle (KRMA-900)

extension RetouchWorkflowCoordinatorTests {
    fileprivate static func source(_ tag: String) -> ImageSource {
        ImageSource(data: Data(tag.utf8), nativeExtent: CGSize(width: 64, height: 64))
    }

    /// A proxy with one dark dust speck on a flat field.
    private static func speckProxy() -> RetouchAnalysisProxy {
        let side = 64
        var pixels = [SIMD3<Float>](repeating: SIMD3(60, 0, 0), count: side * side)
        for y in 30...33 { for x in 30...33 { pixels[y * side + x] = SIMD3(30, 0, 0) } }
        return RetouchAnalysisProxy(width: side, height: side, pixels: pixels)
    }

    @MainActor private final class Gate {
        private var continuations: [CheckedContinuation<Void, Never>] = []
        private var waiters: [CheckedContinuation<Void, Never>] = []
        var arrivals = 0
        func arrive() async {
            arrivals += 1
            let ready = waiters; waiters = []
            ready.forEach { $0.resume() }
            await withCheckedContinuation { continuations.append($0) }
        }
        func waitForArrivals(_ count: Int) async {
            while arrivals < count { await withCheckedContinuation { waiters.append($0) } }
        }
        func releaseAll() { let c = continuations; continuations = []; c.forEach { $0.resume() } }
    }

    private func makeGated() -> (FakeRetouchDestination, RetouchWorkflowCoordinator, Gate) {
        let destination = FakeRetouchDestination()
        let gate = Gate()
        destination.proxyProvider = { _ in await gate.arrive(); return Self.speckProxy() }
        return (destination, RetouchWorkflowCoordinator(destination: destination), gate)
    }

    func testLateDetectionForPreviousPhotoDoesNotPublishOnNextPhoto() async throws {
        let (destination, workflow, gate) = makeGated()
        destination.retouchAnalysisSource = Self.source("A")
        workflow.detectDust()
        await gate.waitForArrivals(1)
        destination.retouchAnalysisSource = Self.source("B")
        workflow.activeSourceDidChange()
        gate.releaseAll()
        await workflow.shutdown()
        XCTAssertTrue(workflow.interactionState.dustSuggestions.isEmpty)
        XCTAssertTrue(destination.statuses.isEmpty)
    }

    func testLateDetectionFailureForPreviousPhotoDoesNotPublishOnNextPhoto() async throws {
        let (destination, workflow, gate) = makeGated()
        destination.proxyProvider = { _ in await gate.arrive(); return nil }
        destination.retouchAnalysisSource = Self.source("A")
        workflow.detectDust()
        await gate.waitForArrivals(1)
        destination.retouchAnalysisSource = Self.source("B")
        workflow.activeSourceDidChange()
        gate.releaseAll()
        await workflow.shutdown()
        XCTAssertTrue(workflow.interactionState.dustSuggestions.isEmpty)
        XCTAssertTrue(destination.statuses.isEmpty)
    }

    func testCompletedSuggestionsAreClearedAndStaleAcceptIsHarmless() async throws {
        let (destination, workflow, gate) = makeGated()
        destination.retouchAnalysisSource = Self.source("A")
        workflow.detectDust()
        await gate.waitForArrivals(1)
        gate.releaseAll()
        try await waitUntil("dust suggestions to appear") { !workflow.interactionState.dustSuggestions.isEmpty }
        let stale = workflow.interactionState.dustSuggestions
        // The source changes without the lifecycle hook: acceptance itself must still refuse.
        destination.retouchAnalysisSource = Self.source("B")
        workflow.acceptAllDustSuggestions()
        workflow.acceptDustSuggestion(stale[0].id)
        XCTAssertTrue(destination.document.retouch.spots.isEmpty)
        XCTAssertTrue(workflow.interactionState.dustSuggestions.isEmpty)
    }

    func testSourceChangeClearsSuggestionsAndCandidates() async throws {
        let (destination, workflow, gate) = makeGated()
        destination.retouchAnalysisSource = Self.source("A")
        workflow.interactionState.setDustSuggestions([
            RetouchDustSuggestion(id: UUID(), point: CGPoint(x: 0.5, y: 0.5), radius: 0.01, confidence: 1, seed: 1)])
        workflow.interactionState.setVisualizationCandidates(workflow.interactionState.dustSuggestions)
        destination.retouchAnalysisSource = nil
        workflow.activeSourceDidChange()
        XCTAssertTrue(workflow.interactionState.dustSuggestions.isEmpty)
        XCTAssertTrue(workflow.interactionState.visualizationCandidates.isEmpty)
        gate.releaseAll()
    }

    func testDisablingVisualizationWhileSuspendedLeavesCandidatesEmpty() async throws {
        let (destination, workflow, gate) = makeGated()
        destination.retouchAnalysisSource = Self.source("A")
        workflow.toggleVisualization()
        await gate.waitForArrivals(1)
        workflow.toggleVisualization()
        gate.releaseAll()
        await workflow.shutdown()
        XCTAssertTrue(workflow.interactionState.visualizationCandidates.isEmpty)
    }

    func testSupersededRequestCannotPublishAndOnlyLatestDoes() async throws {
        let (destination, workflow, gate) = makeGated()
        destination.retouchAnalysisSource = Self.source("A")
        workflow.detectDust()
        await gate.waitForArrivals(1)
        workflow.detectDust() // replaces nothing active; becomes the single pending request
        workflow.detectDust() // replaces the pending request
        gate.releaseAll()
        try await waitUntil("dust suggestions to appear") { !workflow.interactionState.dustSuggestions.isEmpty }
        await workflow.shutdown()
        XCTAssertEqual(gate.arrivals, 1) // the analysis built for the first request served the rest
        XCTAssertEqual(destination.statuses.count, 1)
    }

    func testShutdownRejectsNewRequestsAndAwaitsOwnedWork() async throws {
        let (destination, workflow, gate) = makeGated()
        destination.retouchAnalysisSource = Self.source("A")
        workflow.detectDust()
        await gate.waitForArrivals(1)
        let shutdown = Task { await workflow.shutdown() }
        gate.releaseAll()
        await shutdown.value
        workflow.detectDust()
        workflow.toggleVisualization()
        XCTAssertEqual(gate.arrivals, 1)
        XCTAssertTrue(workflow.interactionState.dustSuggestions.isEmpty)
        XCTAssertTrue(workflow.interactionState.visualizationCandidates.isEmpty)
        XCTAssertTrue(destination.statuses.isEmpty)
    }

    func testAcceptingCurrentPhotoSuggestionsStillGroupsUndo() async throws {
        let (destination, workflow, gate) = makeGated()
        destination.retouchAnalysisSource = Self.source("A")
        workflow.detectDust()
        await gate.waitForArrivals(1)
        gate.releaseAll()
        try await waitUntil("dust suggestions to appear") { !workflow.interactionState.dustSuggestions.isEmpty }
        let count = workflow.interactionState.dustSuggestions.count
        workflow.acceptAllDustSuggestions()
        XCTAssertEqual(destination.document.retouch.spots.count, count)
        XCTAssertEqual(destination.undoGroupingDepth, 0)
    }

    // MARK: KRMA-901 — off-main, coalesced, reusable analysis

    private final class StageLog: Sendable {
        private let state = OSAllocatedUnfairLock(initialState: (analyze: 0, select: 0, onMain: false))
        var analyzeCount: Int { state.withLock { $0.analyze } }
        var selectCount: Int { state.withLock { $0.select } }
        var anyOnMain: Bool { state.withLock { $0.onMain } }
        func record(_ stage: RetouchDustAnalysisWorker.Stage) {
            state.withLock {
                if stage == .analyze { $0.analyze += 1 } else { $0.select += 1 }
                if Thread.isMainThread { $0.onMain = true }
            }
        }
    }

    private func makeObserved(log: StageLog, hold: DispatchSemaphore? = nil)
        -> (FakeRetouchDestination, RetouchWorkflowCoordinator, Gate) {
        let destination = FakeRetouchDestination()
        let gate = Gate()
        destination.proxyProvider = { _ in await gate.arrive(); return Self.speckProxy() }
        let worker = RetouchDustAnalysisWorker { stage in
            log.record(stage)
            if stage == .analyze { hold?.wait() }
        }
        return (destination, RetouchWorkflowCoordinator(destination: destination, worker: worker), gate)
    }

    func testDetectionRunsOffMainActorWhileMainActorProgresses() async throws {
        let log = StageLog()
        let hold = DispatchSemaphore(value: 0)
        let (destination, workflow, gate) = makeObserved(log: log, hold: hold)
        destination.retouchAnalysisSource = Self.source("A")
        workflow.detectDust()
        await gate.waitForArrivals(1)
        gate.releaseAll()
        try await waitUntil("first analysis stage") { log.analyzeCount > 0 }
        // The worker is parked inside the expensive stage; the main actor must still make progress.
        var sentinel = 0
        for _ in 0..<50 { sentinel += 1; await Task.yield() }
        XCTAssertEqual(sentinel, 50)
        XCTAssertTrue(workflow.interactionState.dustSuggestions.isEmpty)
        hold.signal()
        try await waitUntil("dust suggestions to appear") { !workflow.interactionState.dustSuggestions.isEmpty }
        XCTAssertFalse(log.anyOnMain)
        await workflow.shutdown()
    }

    func testThresholdBurstCoalescesAndFinalThresholdWins() async throws {
        let log = StageLog()
        let (destination, workflow, gate) = makeObserved(log: log)
        destination.retouchAnalysisSource = Self.source("A")
        workflow.toggleVisualization()
        await gate.waitForArrivals(1)
        for step in 1...40 { workflow.setVisualizationThreshold(0.005 + Double(step) * 0.001) }
        workflow.setVisualizationThreshold(0.05)
        gate.releaseAll()
        let expected = RetouchDustDetector.detect(in: Self.speckProxy(), threshold: 0.05, maximum: 1_000)
        XCTAssertFalse(expected.isEmpty)
        try await waitUntil("visualization candidates to match expected") { workflow.interactionState.visualizationCandidates == expected }
        XCTAssertEqual(gate.arrivals, 1)
        XCTAssertEqual(log.analyzeCount, 1)
        XCTAssertEqual(log.selectCount, 1) // 41 requests collapsed into one active plus one pending
        await workflow.shutdown()
    }

    func testRepeatedThresholdsReuseAnalysisAndSourceChangeInvalidatesIt() async throws {
        let log = StageLog()
        let (destination, workflow, gate) = makeObserved(log: log)
        destination.retouchAnalysisSource = Self.source("A")
        workflow.toggleVisualization()
        await gate.waitForArrivals(1)
        gate.releaseAll()
        try await waitUntil("first select stage") { log.selectCount >= 1 }
        for (index, threshold) in [0.03, 0.04, 0.06].enumerated() {
            workflow.setVisualizationThreshold(threshold)
            try await waitUntil("select stage for threshold step") { log.selectCount >= index + 2 }
        }
        XCTAssertEqual(log.analyzeCount, 1)
        XCTAssertEqual(gate.arrivals, 1)
        destination.retouchAnalysisSource = Self.source("B")
        workflow.activeSourceDidChange()
        await gate.waitForArrivals(2)
        gate.releaseAll()
        try await waitUntil("second analysis stage") { log.analyzeCount >= 2 }
        XCTAssertEqual(log.analyzeCount, 2)
        await workflow.shutdown()
    }

    func testThresholdSelectionMatchesDirectDetectionAcrossThresholdsAndCaps() throws {
        let proxy = Self.speckProxy()
        let analysis = try RetouchDustDetector.analyze(proxy)
        for threshold in [0.005, 0.025, 0.06, 0.12] {
            for maximum in [0, 1, 500] {
                XCTAssertEqual(try RetouchDustDetector.select(from: analysis, threshold: threshold, maximum: maximum),
                               RetouchDustDetector.detect(in: proxy, threshold: threshold, maximum: maximum))
            }
        }
    }

}


@MainActor
private final class FakeRetouchDestination: RetouchWorkflowDestination {
    var document = EditDocument()
    var sourceSize = CGSize(width: 1000, height: 800)
    var documentUpdates = 0
    var pickedRanks: [Int] = []
    var retouchAnalysisSource: ImageSource?
    var statuses: [String] = []
    var proxyProvider: (@MainActor (ImageSource) async -> RetouchAnalysisProxy?)?
    func retouchAnalysisProxy(source: ImageSource) async -> RetouchAnalysisProxy? { await proxyProvider?(source) }
    func publishRetouchStatus(_ message: String) { statuses.append(message) }
    func updateDocument(_ transform: (inout EditDocument) -> Void) {
        documentUpdates += 1
        transform(&document)
    }
    /// Optional per-call hook that suspends a pick (and may return `false` to model a failed search).
    var pickProvider: (@MainActor (Int) async -> Bool)?
    var pickPublications: [Int] = []
    func pickRetouchSource(spotID: UUID, rank: Int, isCurrent: @MainActor () -> Bool) async {
        pickedRanks.append(rank)
        guard let pickProvider else { return }
        guard await pickProvider(rank), isCurrent() else { return }
        pickPublications.append(rank)
        updateDocument { document in
            guard let index = document.retouch.spots.firstIndex(where: { $0.id == spotID }) else { return }
            document.retouch.spots[index].source = .auto(offset: CGVector(dx: Double(rank), dy: 0), rank: rank)
        }
    }
    func setRetouchCanvasActive(_ active: Bool) {}
    var undoGroupingDepth = 0
    func beginUndoGrouping() { undoGroupingDepth += 1 }
    func endUndoGrouping() { undoGroupingDepth -= 1 }
}

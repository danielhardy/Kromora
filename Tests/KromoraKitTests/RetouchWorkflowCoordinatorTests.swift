import AppKit
import XCTest
@testable import KromoraKit

@MainActor
final class RetouchWorkflowCoordinatorTests: XCTestCase {
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

    func testLateDetectionForPreviousPhotoDoesNotPublishOnNextPhoto() async {
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

    func testCompletedSuggestionsAreClearedAndStaleAcceptIsHarmless() async {
        let (destination, workflow, gate) = makeGated()
        destination.retouchAnalysisSource = Self.source("A")
        workflow.detectDust()
        await gate.waitForArrivals(1)
        gate.releaseAll()
        while workflow.interactionState.dustSuggestions.isEmpty { await Task.yield() }
        let stale = workflow.interactionState.dustSuggestions
        // The source changes without the lifecycle hook: acceptance itself must still refuse.
        destination.retouchAnalysisSource = Self.source("B")
        workflow.acceptAllDustSuggestions()
        workflow.acceptDustSuggestion(stale[0].id)
        XCTAssertTrue(destination.document.retouch.spots.isEmpty)
        XCTAssertTrue(workflow.interactionState.dustSuggestions.isEmpty)
    }

    func testSourceChangeClearsSuggestionsAndCandidates() async {
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

    func testDisablingVisualizationWhileSuspendedLeavesCandidatesEmpty() async {
        let (destination, workflow, gate) = makeGated()
        destination.retouchAnalysisSource = Self.source("A")
        workflow.toggleVisualization()
        await gate.waitForArrivals(1)
        workflow.toggleVisualization()
        gate.releaseAll()
        await workflow.shutdown()
        XCTAssertTrue(workflow.interactionState.visualizationCandidates.isEmpty)
    }

    func testSlowEarlierRequestCannotReplaceLaterRequestOutput() async {
        let destination = FakeRetouchDestination()
        let first = Gate(), second = Gate()
        var calls = 0
        destination.proxyProvider = { _ in
            calls += 1
            if calls == 1 { await first.arrive(); return RetouchAnalysisProxy(width: 0, height: 0, pixels: []) }
            await second.arrive(); return Self.speckProxy()
        }
        destination.retouchAnalysisSource = Self.source("A")
        let workflow = RetouchWorkflowCoordinator(destination: destination)
        workflow.detectDust()
        await first.waitForArrivals(1)
        workflow.detectDust()
        await second.waitForArrivals(1)
        second.releaseAll()
        while workflow.interactionState.dustSuggestions.isEmpty { await Task.yield() }
        let published = workflow.interactionState.dustSuggestions
        let statuses = destination.statuses
        first.releaseAll()
        await workflow.shutdown()
        XCTAssertEqual(statuses.count, 1)
        XCTAssertTrue(workflow.interactionState.dustSuggestions.isEmpty) // shutdown clears
        XCTAssertFalse(published.isEmpty)
        XCTAssertEqual(destination.statuses, statuses)
    }

    func testShutdownRejectsNewRequestsAndAwaitsOwnedWork() async {
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

    func testAcceptingCurrentPhotoSuggestionsStillGroupsUndo() async {
        let (destination, workflow, gate) = makeGated()
        destination.retouchAnalysisSource = Self.source("A")
        workflow.detectDust()
        await gate.waitForArrivals(1)
        gate.releaseAll()
        while workflow.interactionState.dustSuggestions.isEmpty { await Task.yield() }
        let count = workflow.interactionState.dustSuggestions.count
        workflow.acceptAllDustSuggestions()
        XCTAssertEqual(destination.document.retouch.spots.count, count)
        XCTAssertEqual(destination.undoGroupingDepth, 0)
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
    func pickRetouchSource(spotID: UUID, rank: Int) async { pickedRanks.append(rank) }
    func setRetouchCanvasActive(_ active: Bool) {}
    var undoGroupingDepth = 0
    func beginUndoGrouping() { undoGroupingDepth += 1 }
    func endUndoGrouping() { undoGroupingDepth -= 1 }
}

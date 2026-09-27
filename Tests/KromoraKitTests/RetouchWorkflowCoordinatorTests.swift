import AppKit
import XCTest
@testable import KromoraKit

@MainActor
final class RetouchWorkflowCoordinatorTests: XCTestCase {
    func testClickAndDragCommitOneSpotEach() {
        let destination = FakeRetouchDestination()
        let workflow = RetouchWorkflowCoordinator(destination: destination)
        workflow.setArmed(true)
        workflow.beginGesture(at: CGPoint(x: 0.2, y: 0.3))
        workflow.endGesture()
        XCTAssertEqual(destination.document.retouch.spots.count, 1)
        XCTAssertEqual(destination.documentUpdates, 1)
        XCTAssertEqual(destination.document.retouch.spots[0].region.samples.first?.point, CGPoint(x: 0.2, y: 0.3))

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

    func testNextSourceAdvancesAutomaticHealAndRemoveSeedRanks() async throws {
        let destination = FakeRetouchDestination()
        let heal = RetouchSpot(mode: .heal, source: .auto(offset: .zero, rank: 2))
        let remove = RetouchSpot(mode: .remove, source: .auto(offset: .zero, rank: 0))
        destination.document.retouch.spots = [heal, remove]
        let workflow = RetouchWorkflowCoordinator(destination: destination)
        workflow.setArmed(true)
        workflow.interactionState.select(heal.id)
        workflow.nextSource()
        try await Task.sleep(for: .milliseconds(1))
        workflow.interactionState.select(remove.id)
        workflow.nextSource()
        try await Task.sleep(for: .milliseconds(1))
        XCTAssertEqual(destination.pickedRanks, [3, 1])
    }
}

@MainActor
private final class FakeRetouchDestination: RetouchWorkflowDestination {
    var document = EditDocument()
    var sourceSize = CGSize(width: 1000, height: 800)
    var documentUpdates = 0
    var pickedRanks: [Int] = []
    func updateDocument(_ transform: (inout EditDocument) -> Void) {
        documentUpdates += 1
        transform(&document)
    }
    func pickRetouchSource(spotID: UUID, rank: Int) async { pickedRanks.append(rank) }
    func setRetouchCanvasActive(_ active: Bool) {}
}

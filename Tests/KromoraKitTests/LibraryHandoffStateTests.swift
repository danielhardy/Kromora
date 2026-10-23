import XCTest

@testable import KromoraKit

@MainActor
final class LibraryHandoffStateTests: XCTestCase {
    func testFittedRectLetterboxesWideAndTallImagesInsideBounds() {
        let bounds = CGRect(x: 100, y: 50, width: 800, height: 400)
        let wide = LibraryHandoffState.fittedRect(imageSize: CGSize(width: 400, height: 100), in: bounds)
        XCTAssertEqual(wide, CGRect(x: 100, y: 150, width: 800, height: 200))
        let tall = LibraryHandoffState.fittedRect(imageSize: CGSize(width: 100, height: 400), in: bounds)
        XCTAssertEqual(tall, CGRect(x: 450, y: 50, width: 100, height: 400))
    }

    func testFittedRectFallsBackToBoundsForDegenerateImage() {
        let bounds = CGRect(x: 0, y: 0, width: 10, height: 10)
        XCTAssertEqual(LibraryHandoffState.fittedRect(imageSize: .zero, in: bounds), bounds)
    }

    func testOnlyTheReturnTargetReportsItsCellFrame() {
        let state = LibraryHandoffState()
        let target = PhotoAssetID(rawValue: UUID().uuidString)
        let other = PhotoAssetID(rawValue: UUID().uuidString)
        state.beginReturnTarget(target)
        state.updateReturnCellFrame(CGRect(x: 1, y: 2, width: 3, height: 4), for: other)
        XCTAssertNil(state.returnCellFrame)
        state.updateReturnCellFrame(CGRect(x: 1, y: 2, width: 3, height: 4), for: target)
        XCTAssertEqual(state.returnCellFrame, CGRect(x: 1, y: 2, width: 3, height: 4))
    }

    func testFinishClearsFlightAndEntranceGate() {
        let state = LibraryHandoffState()
        state.flight = .init(image: NSImage(), frame: .zero, cornerRadius: 0, opacity: 1)
        state.isEntering = true
        state.beginReturnTarget(PhotoAssetID(rawValue: UUID().uuidString))
        state.finish()
        XCTAssertNil(state.flight)
        XCTAssertFalse(state.isEntering)
        XCTAssertNil(state.returnTargetID)
    }

    func testEntranceHoldsTheCanvasUntilFinished() {
        let state = LibraryHandoffState()
        state.runEntrance(
            image: NSImage(size: CGSize(width: 40, height: 30)),
            from: CGRect(x: 0, y: 0, width: 20, height: 20))
        XCTAssertTrue(state.isEntering)
        XCTAssertTrue(state.isCanvasHeld, "the flight must be the only copy of the photo on screen")
        state.finish()
        XCTAssertFalse(state.isEntering)
        XCTAssertFalse(state.isCanvasHeld)
        XCTAssertNil(state.flight)
    }

    func testReturnWithoutACanvasFinishesWithoutAFlight() {
        let state = LibraryHandoffState()
        state.runReturn(
            image: NSImage(size: CGSize(width: 40, height: 30)),
            assetID: PhotoAssetID(rawValue: UUID().uuidString))
        XCTAssertNil(state.flight, "no measured canvas means there is nothing to contract from")
        XCTAssertNil(state.returnTargetID)
    }

    func testCanvasFrameUpdatesAlwaysAdvanceRevision() {
        let state = LibraryHandoffState()
        let frame = CGRect(x: 0, y: 0, width: 10, height: 10)
        state.updateCanvasFrame(frame)
        let first = state.canvasFrameRevision
        state.updateCanvasFrame(frame)
        XCTAssertGreaterThan(state.canvasFrameRevision, first)
    }
}

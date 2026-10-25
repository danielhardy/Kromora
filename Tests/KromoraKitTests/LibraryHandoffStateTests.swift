import XCTest

@testable import KromoraKit

@MainActor
final class LibraryHandoffStateTests: XCTestCase {
    func testFittedRectLetterboxesWideAndTallImagesInsideBounds() {
        let bounds = CGRect(x: 100, y: 50, width: 800, height: 400)
        let wide = LibraryHandoffState.fittedRect(
            imageSize: CGSize(width: 400, height: 100), in: bounds)
        XCTAssertEqual(wide, CGRect(x: 100, y: 150, width: 800, height: 200))
        let tall = LibraryHandoffState.fittedRect(
            imageSize: CGSize(width: 100, height: 400), in: bounds)
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
            from: CGRect(x: 0, y: 0, width: 20, height: 20), inspectorWidth: 280)
        XCTAssertTrue(state.isEntering)
        XCTAssertTrue(state.isChromeHeld, "the filmstrip waits, with its space reserved, until the photo lands")
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

    func testReduceMotionSkipsBothFlights() {
        XCTAssertTrue(LibraryHandoffState.entranceFlies(reduceMotion: false, hasCell: true, hasImage: true))
        XCTAssertFalse(LibraryHandoffState.entranceFlies(reduceMotion: true, hasCell: true, hasImage: true))
        XCTAssertFalse(LibraryHandoffState.entranceFlies(reduceMotion: false, hasCell: false, hasImage: true))
        XCTAssertTrue(LibraryHandoffState.returnFlies(reduceMotion: false, hasImage: true))
        XCTAssertFalse(LibraryHandoffState.returnFlies(reduceMotion: true, hasImage: true))
        XCTAssertFalse(LibraryHandoffState.returnFlies(reduceMotion: false, hasImage: false))
    }

    func testFinishReleasesTheEditorKeptOverTheLibrary() {
        let state = LibraryHandoffState()
        state.isLeaving = true
        state.isRetractingChrome = true
        state.inspectorHeldOpen = true
        state.libraryScrim = 1
        state.isChromeHeld = true
        state.finish()
        XCTAssertFalse(state.isLeaving)
        XCTAssertFalse(state.isRetractingChrome)
        XCTAssertFalse(state.inspectorHeldOpen)
        XCTAssertFalse(state.isChromeHeld)
        XCTAssertEqual(state.libraryScrim, 0, "no handoff may leave the Library dimmed")
    }

    func testCanvasFittedRectAccountsForTheCanvasPadding() {
        // The canvas draws its image 8 pt inside the preview view; the handoff photo must match.
        let canvas = CGRect(x: 0, y: 0, width: 116, height: 116)
        XCTAssertEqual(
            LibraryHandoffState.canvasFittedRect(imageSize: CGSize(width: 50, height: 50), in: canvas),
            CGRect(x: 8, y: 8, width: 100, height: 100))
    }

    func testFinalCanvasFrameTakesTheInspectorsWidthFromTheTrailingEdge() {
        let held = CGRect(x: 0, y: 40, width: 1000, height: 600)
        XCTAssertEqual(
            LibraryHandoffState.finalCanvasFrame(held: held, inspectorWidth: 280),
            CGRect(x: 0, y: 40, width: 720, height: 600))
        XCTAssertEqual(LibraryHandoffState.finalCanvasFrame(held: held, inspectorWidth: 0), held)
        XCTAssertEqual(
            LibraryHandoffState.finalCanvasFrame(held: held, inspectorWidth: 5_000).width, 1,
            "a wider-than-window inspector must not produce a negative frame")
    }
}

import XCTest
@testable import KromoraKit

final class EditHistoryActionNameTests: XCTestCase {
    private func document(_ edit: (inout EditDocument) -> Void) -> EditDocument {
        var document = EditDocument()
        edit(&document)
        return document
    }

    func testSingleControlNamesItself() {
        let edited = document { $0.light.exposure = 0.5 }
        XCTAssertEqual(EditActionName.make(from: EditDocument(), to: edited), "Exposure")
    }

    func testSeveralControlsInOneSectionNameTheSection() {
        let edited = document { $0.light.exposure = 0.5; $0.light.contrast = 10 }
        XCTAssertEqual(EditActionName.make(from: EditDocument(), to: edited), "Light")
    }

    func testBroadEditHasNoName() {
        let edited = document { $0.light.exposure = 0.5; $0.color.saturation = 10 }
        XCTAssertNil(EditActionName.make(from: EditDocument(), to: edited))
    }

    func testUndoRedoCarryActionNames() {
        let base = EditDocument()
        let exposed = document { $0.light.exposure = 0.5 }
        let contrasted = document { $0.light.exposure = 0.5; $0.light.contrast = 20 }
        var history = EditHistory()
        history.recordChange(from: base, to: exposed)
        history.recordChange(from: exposed, to: contrasted)
        XCTAssertEqual(history.undoActionName, "Contrast")
        XCTAssertNil(history.redoActionName)

        XCTAssertEqual(history.undo(current: contrasted), exposed)
        XCTAssertEqual(history.undoActionName, "Exposure")
        XCTAssertEqual(history.redoActionName, "Contrast")

        XCTAssertEqual(history.redo(current: exposed), contrasted)
        XCTAssertEqual(history.undoActionName, "Contrast")
        XCTAssertNil(history.redoActionName)
    }

    func testGroupedGestureIsOneNamedStep() {
        let base = EditDocument()
        var history = EditHistory()
        history.beginGrouping(document: base)
        var current = base
        for value in [0.1, 0.2, 0.3] {
            let next = document { $0.light.exposure = value }
            history.recordChange(from: current, to: next)
            current = next
        }
        history.endGrouping(document: current)
        XCTAssertEqual(history.undoCount, 1)
        XCTAssertEqual(history.undoActionName, "Exposure")
    }

    func testRestoredTimelineFallsBackToPlainTitles() {
        var history = EditHistory()
        history.adoptTimeline(before: [EditDocument(), document { $0.light.exposure = 1 }])
        XCTAssertTrue(history.canUndo)
        XCTAssertNil(history.undoActionName)
        XCTAssertEqual(MenuCommandAvailability(canUndo: true, undoActionName: history.undoActionName).undoTitle, "Undo")
    }

    func testAvailabilityTitlesUseHistoryNames() {
        let availability = MenuCommandAvailability(canUndo: true, canRedo: true, undoActionName: "Exposure", redoActionName: "Contrast")
        XCTAssertEqual(availability.undoTitle, "Undo Exposure")
        XCTAssertEqual(availability.redoTitle, "Redo Contrast")
    }
}

import XCTest
@testable import KromoraKit

@MainActor
final class TerminationGuardTests: XCTestCase {
    private final class FakePresenter: QuitConfirmationPresenting {
        let answer: Bool
        private(set) var messages: [String] = []
        init(answer: Bool) { self.answer = answer }
        func confirmQuit(message: String) async -> Bool {
            messages.append(message)
            return answer
        }
    }

    func testIdleHasNoActivitiesAndNeverPrompts() async {
        let guardModel = TerminationGuard(batchExportTotal: 0)
        XCTAssertTrue(guardModel.activities.isEmpty)
        let presenter = FakePresenter(answer: false)
        let shouldQuit = await guardModel.shouldQuit(presenter: presenter)
        XCTAssertTrue(shouldQuit)
        XCTAssertTrue(presenter.messages.isEmpty)
    }

    func testBusyAndCancelKeepsRunning() async {
        let presenter = FakePresenter(answer: false)
        let shouldQuit = await TerminationGuard(batchExportTotal: 12).shouldQuit(presenter: presenter)
        XCTAssertFalse(shouldQuit)
        XCTAssertEqual(presenter.messages, ["Quit and cancel export of 12 photos?"])
    }

    func testBusyAndQuitTerminates() async {
        let presenter = FakePresenter(answer: true)
        let shouldQuit = await TerminationGuard(packageImportTotal: 1).shouldQuit(presenter: presenter)
        XCTAssertTrue(shouldQuit)
        XCTAssertEqual(presenter.messages, ["Quit and cancel import of 1 photo?"])
    }

    func testMultipleActivitiesAreListed() {
        let model = TerminationGuard(batchExportTotal: 3, photosImportTotal: 5)
        XCTAssertEqual(model.activities.map(\.kind), [.export, .importing])
        XCTAssertEqual(
            TerminationGuard.message(for: model.activities),
            "Quit and cancel export of 3 photos and Photos import of 5 photos?"
        )
    }

    func testSheetConfirmationMakesCancelDefaultAndQuitSecond() async {
        let sheets = FakeSheets()
        sheets.confirmResult = true  // first button, "Cancel"
        let cancelled = await AppKitQuitConfirmation(sheets: sheets).confirmQuit(message: "m")
        XCTAssertFalse(cancelled)
        XCTAssertEqual(sheets.lastConfirmButtons, ["Cancel", "Quit"])

        sheets.confirmResult = false  // second button, "Quit"
        let approved = await AppKitQuitConfirmation(sheets: sheets).confirmQuit(message: "m")
        XCTAssertTrue(approved)
    }
}

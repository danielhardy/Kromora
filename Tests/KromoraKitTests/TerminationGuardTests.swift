import XCTest
@testable import KromoraKit

@MainActor
final class TerminationGuardTests: XCTestCase {
    private final class FakePresenter: QuitConfirmationPresenting {
        let answer: Bool
        private(set) var messages: [String] = []
        init(answer: Bool) { self.answer = answer }
        func confirmQuit(message: String) -> Bool {
            messages.append(message)
            return answer
        }
    }

    func testIdleHasNoActivitiesAndNeverPrompts() {
        let guardModel = TerminationGuard(batchExportTotal: 0)
        XCTAssertTrue(guardModel.activities.isEmpty)
        let presenter = FakePresenter(answer: false)
        XCTAssertTrue(guardModel.shouldQuit(presenter: presenter))
        XCTAssertTrue(presenter.messages.isEmpty)
    }

    func testBusyAndCancelKeepsRunning() {
        let presenter = FakePresenter(answer: false)
        XCTAssertFalse(TerminationGuard(batchExportTotal: 12).shouldQuit(presenter: presenter))
        XCTAssertEqual(presenter.messages, ["Quit and cancel export of 12 photos?"])
    }

    func testBusyAndQuitTerminates() {
        let presenter = FakePresenter(answer: true)
        XCTAssertTrue(TerminationGuard(packageImportTotal: 1).shouldQuit(presenter: presenter))
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
}

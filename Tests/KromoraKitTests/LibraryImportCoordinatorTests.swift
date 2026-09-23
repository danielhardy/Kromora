import XCTest

@testable import KromoraKit

@MainActor
final class LibraryImportCoordinatorTests: XCTestCase {
    private final class ShutdownState {
        var isShuttingDown = false
    }

    func testStartingAnotherImportInvalidatesPreviousGeneration() {
        let coordinator = LibraryImportCoordinator(
            package: nil,
            isShuttingDown: { false },
            publishProgress: { _ in },
            publishStatus: { _ in }
        )

        let first = coordinator.beginOperation()
        XCTAssertTrue(coordinator.isCurrent(first))

        let second = coordinator.beginOperation()

        XCTAssertNotEqual(first, second)
        XCTAssertFalse(coordinator.isCurrent(first))
        XCTAssertTrue(coordinator.isCurrent(second))
    }

    func testShutdownInvalidatesCurrentGeneration() async {
        let state = ShutdownState()
        let coordinator = LibraryImportCoordinator(
            package: nil,
            isShuttingDown: { state.isShuttingDown },
            publishProgress: { _ in },
            publishStatus: { _ in }
        )
        let operation = coordinator.beginOperation()

        state.isShuttingDown = true
        XCTAssertFalse(coordinator.isCurrent(operation))

        await coordinator.shutdown()
        XCTAssertFalse(coordinator.isCurrent(operation))
    }
}

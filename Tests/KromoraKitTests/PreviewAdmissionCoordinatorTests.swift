import XCTest

@testable import KromoraKit

@MainActor
final class PreviewAdmissionCoordinatorTests: XCTestCase {
    func testIdleAndAdjacentPrefetchJobsHaveIndependentCancellationIDs() async {
        let scheduler = ImageWorkScheduler()
        let coordinator = PreviewAdmissionCoordinator(
            workScheduler: scheduler, engine: RenderEngine.shared
        )
        XCTAssertNotEqual(coordinator.idlePreviewBuildJobID, coordinator.adjacentPreviewPrefetchJobID)

        let wait: ImageWorkScheduler.Operation = {
            try? await Task.sleep(for: .seconds(30))
        }
        scheduler.enqueue(
            id: coordinator.idlePreviewBuildJobID, lane: .editor, priority: .background,
            operation: wait
        )
        scheduler.enqueue(
            id: coordinator.adjacentPreviewPrefetchJobID, lane: .editor, priority: .background,
            operation: wait
        )
        coordinator.cancelIdlePreviewBuild()
        XCTAssertTrue(scheduler.contains(coordinator.adjacentPreviewPrefetchJobID))
        XCTAssertFalse(scheduler.contains(coordinator.idlePreviewBuildJobID))

        coordinator.cancelAdjacentPreviewPrefetch()
        await scheduler.cancelAllAndWait()
    }
}

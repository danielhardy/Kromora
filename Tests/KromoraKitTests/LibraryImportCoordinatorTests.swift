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

    func testLiveCommitsReachTheGridAndCancellationKeepsCommittedPhotos() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("kromora-live-import-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let urls = try (0..<8).map { index in
            let url = directory.appendingPathComponent("live-\(index).raw")
            try Data(repeating: UInt8(index + 1), count: 512 * 1024).write(to: url)
            return url
        }
        let scheduler = ImageWorkScheduler()
        let session = try PortableLibrarySession(
            at: directory.appendingPathComponent("Live.kromoralibrary"), scheduler: scheduler
        )
        let coordinator = LibraryImportCoordinator(
            package: session, isShuttingDown: { false },
            publishProgress: { _ in }, publishStatus: { _ in }
        )
        let operation = coordinator.beginOperation()
        let handle = try coordinator.startImportURLs(urls)

        var mergedCounts: [Int] = []
        var failure: Error?
        let finished = expectation(description: "import terminal callback")
        coordinator.observe(
            handle, operationID: operation, prefix: "Import",
            onCommitted: {
                mergedCounts.append(session.assetCount)
                // Cancel as soon as the first photos are visible to queries.
                if mergedCounts.count == 1 { coordinator.cancelCurrent() }
            },
            onSuccess: { _ in finished.fulfill() },
            onFailure: { error in failure = error; finished.fulfill() }
        )
        await fulfillment(of: [finished], timeout: 10)
        await scheduler.cancelAllAndWait()

        // Whether the import was cut short or raced to completion, every photo the package
        // committed is queryable and the first live merge already saw some of them.
        var committed = 0
        for shard in PortableLibraryPackage.allShards {
            committed += try session.package.readMembershipShard(shard).entries
                .filter { !$0.isTombstone }.count
        }
        XCTAssertGreaterThan(committed, 0)
        XCTAssertEqual(session.assetCount, committed)
        XCTAssertGreaterThan(mergedCounts.first ?? 0, 0)
        if let failure { XCTAssertTrue(failure is CancellationError) }
        await session.shutdown()
    }
}

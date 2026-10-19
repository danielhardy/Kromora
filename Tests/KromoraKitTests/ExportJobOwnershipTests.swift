import XCTest

@testable import KromoraKit

/// Every accepted export, Share render, and bundle has one owner; a second command is refused
/// while one runs and a finishing job clears only its own entry.
@MainActor
final class ExportJobOwnershipTests: TempDirectoryTestCase {
    private func makeItems(_ names: [String]) throws -> [ExportCoordinator.BatchItem] {
        try names.map { name in
            let url = try Fixtures.writeJPEG(
                width: 32, height: 24, orientation: 1, named: "\(name).jpg", in: tempDirectory
            )
            return ExportCoordinator.BatchItem(url: url, data: nil, name: name)
        }
    }

    private func folder() throws -> URL {
        let url = tempDirectory.appendingPathComponent("out")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func waitUntil(timeout: TimeInterval = 5, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline { return XCTFail("condition not met within \(timeout)s") }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    func testSecondJobIsRefusedAndFirstCompletionClearsOnlyItself() async throws {
        let coordinator = ExportCoordinator(engine: FakeRenderEngine(), photosDelivery: nil)
        var statuses: [String] = []
        coordinator.onStatus = { statuses.append($0) }

        let first = try XCTUnwrap(coordinator.admitJob(.single))
        let gate = AsyncGate()
        let task = Task { await gate.wait() }
        coordinator.attach(task, to: first)

        XCTAssertNil(coordinator.admitJob(.batch, itemCount: 3), "B must not start while A runs")
        XCTAssertNil(coordinator.admitJob(.originalBundle))
        XCTAssertTrue(statuses.last?.contains("already running") == true)
        XCTAssertEqual(Array(coordinator.jobs.keys), [first])
        XCTAssertTrue(coordinator.isExporting)

        // A stale id (a job that never existed or already finished) cannot clear A.
        coordinator.finishJob(ExportJobID())
        XCTAssertEqual(Array(coordinator.jobs.keys), [first])

        gate.open()
        await task.value
        coordinator.finishJob(first)
        XCTAssertFalse(coordinator.isExporting)
        XCTAssertEqual(coordinator.lastFinishedJob, ExportJobRecord(id: first, kind: .single, outcome: .completed))
    }

    func testRefusedSingleExportLeavesRunningBatchAlone() async throws {
        let fake = FakeRenderEngine()
        await fake.gateEncodeAfterFirst()
        let coordinator = ExportCoordinator(engine: fake, photosDelivery: nil)
        var statuses: [String] = []
        coordinator.onStatus = { statuses.append($0) }
        let out = try folder()
        let items = try makeItems(["a", "b"])
        let batch = Task {
            await coordinator.performBatchExport(
                items, document: EditDocument(), lut: nil, format: .png, to: out
            )
        }
        try await waitUntil { coordinator.batchCurrentItem == "b" }
        let batchJob = try XCTUnwrap(coordinator.jobs.values.first)
        XCTAssertEqual(batchJob.kind, .batch)

        let source = ImageSource(
            url: try Fixtures.writeGradientPNG(width: 8, height: 8, named: "s.png", in: tempDirectory),
            nativeExtent: CGSize(width: 8, height: 8)
        )
        let single = tempDirectory.appendingPathComponent("single.jpg")
        coordinator.performExport(
            source: source, document: EditDocument(), lut: nil, format: .jpeg, to: single
        )
        XCTAssertEqual(Array(coordinator.jobs.keys), [batchJob.id])
        XCTAssertTrue(statuses.contains { $0.contains("already running") })

        await fake.releaseEncode()
        let outcome = await batch.value
        XCTAssertEqual(outcome.exported, 2)
        XCTAssertFalse(coordinator.isExporting)
        XCTAssertFalse(FileManager.default.fileExists(atPath: single.path))
    }

    func testShutdownCancelsAndAwaitsEveryRegisteredJob() async throws {
        let coordinator = ExportCoordinator(engine: FakeRenderEngine(), photosDelivery: nil)
        let started = AsyncGate()
        let share = Task { @MainActor in
            try await coordinator.runJob(.share) {
                started.open()
                try await Task.sleep(for: .seconds(60))
                return 1
            }
        }
        await started.wait()
        XCTAssertEqual(coordinator.activeJobCount(of: .share), 1)
        // Share renders of one picker may overlap each other.
        XCTAssertNotNil(coordinator.admitJob(.share, announce: false))

        await coordinator.shutdown()
        XCTAssertFalse(coordinator.isExporting)
        do {
            _ = try await share.value
            XCTFail("the share render should have been cancelled")
        } catch is CancellationError {
        }
    }

    func testCancellingTheCallerOfARunJobCancelsTheWork() async throws {
        let coordinator = ExportCoordinator(engine: FakeRenderEngine(), photosDelivery: nil)
        let started = AsyncGate()
        let caller = Task { @MainActor in
            try await coordinator.runJob(.share) {
                started.open()
                try await Task.sleep(for: .seconds(60))
            }
        }
        await started.wait()
        caller.cancel()
        _ = await caller.result
        try await waitUntil { !coordinator.isExporting }
        XCTAssertEqual(coordinator.lastFinishedJob?.outcome, .cancelled)
    }

    func testCancellationAfterAnOperationReturnsIsStillRecordedAsCancelled() async throws {
        let coordinator = ExportCoordinator(engine: FakeRenderEngine(), photosDelivery: nil)
        let started = AsyncGate()
        let release = AsyncGate()
        let caller = Task { @MainActor in
            try await coordinator.runJob(.originalBundle) {
                started.open()
                await release.wait()
                return true
            }
        }
        await started.wait()
        caller.cancel()
        release.open()

        do {
            _ = try await caller.value
            XCTFail("cancelled bundle work must not report success")
        } catch is CancellationError {
        }
        XCTAssertFalse(coordinator.isExporting)
        XCTAssertEqual(coordinator.lastFinishedJob?.kind, .originalBundle)
        XCTAssertEqual(coordinator.lastFinishedJob?.outcome, .cancelled)
    }

    func testTerminationGuardReportsEachJobKind() {
        let single = TerminationGuard(singleExportActive: true)
        let share = TerminationGuard(shareRenderCount: 2)
        let bundle = TerminationGuard(originalBundleActive: true)
        for model in [single, share, bundle] {
            XCTAssertEqual(model.activities.count, 1)
            XCTAssertEqual(model.activities.first?.kind, .export)
        }
        XCTAssertEqual(
            TerminationGuard.message(for: bundle.activities),
            "Quit and cancel original + settings bundle export?"
        )
    }

    func testViewModelTerminationGuardSeesRegisteredJobs() throws {
        let viewModel = AppViewModel()
        XCTAssertTrue(viewModel.terminationGuard.activities.isEmpty)
        let cases: [(ExportJobKind, String)] = [
            (.single, "export of 1 photo"),
            (.share, "Share export"),
            (.originalBundle, "original + settings bundle export"),
        ]
        for (kind, description) in cases {
            let id = try XCTUnwrap(viewModel.export.admitJob(kind))
            XCTAssertEqual(viewModel.terminationGuard.activities.map(\.description), [description])
            viewModel.export.finishJob(id)
            XCTAssertTrue(viewModel.terminationGuard.activities.isEmpty)
        }
    }

    func testMenuDisablesExportCommandsWhileBusy() {
        var availability = MenuCommandAvailability(hasPhoto: true, selectionCount: 1)
        XCTAssertTrue(availability.isEnabled(.export))
        availability.isExportBusy = true
        for command in [MenuCommand.export, .editInExternalEditor, .exportOriginalWithSettings] {
            XCTAssertFalse(availability.isEnabled(command), "\(command)")
        }
        XCTAssertTrue(availability.isEnabled(.resetPhoto))
    }
}

/// A one-shot async latch.
@MainActor
private final class AsyncGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        waiters.forEach { $0.resume() }
        waiters.removeAll()
    }
}

import XCTest

@testable import KromoraKit

@MainActor
final class AutoWorkflowCoordinatorTests: XCTestCase {
    private struct NoopSceneClassifier: SceneClassifierProviding {
        func classifications(for image: AnalysisImage) async -> [SceneClassificationObservation]? {
            nil
        }
    }

    @MainActor
    private final class Fence {
        var sourceCurrent = true
        var documentCurrent = true
    }

    private final class FakeRunner: AutoWorkflowRunning {
        let delay: Duration
        let path: AutoWorkflowPath
        private(set) var calls = 0

        init(delay: Duration = .zero, path: AutoWorkflowPath = .contentAware) {
            self.delay = delay
            self.path = path
        }

        func run(
            _ request: AutoWorkflowRequest,
            onProgress: @escaping @MainActor @Sendable (AutoEnhancementPhase) -> Void
        ) async -> AutoWorkflowOutcome {
            calls += 1
            onProgress(.renderingCandidates)
            if delay > .zero { try? await Task.sleep(for: delay) }
            return AutoWorkflowOutcome(
                result: AutoEnhancementResult(proposedDocument: request.document),
                path: path, message: "fake"
            )
        }
    }

    private func request() -> AutoWorkflowRequest {
        AutoWorkflowRequest(
            source: ImageSource(
                url: URL(fileURLWithPath: "/tmp/auto.jpg"),
                nativeExtent: CGSize(width: 1, height: 1)),
            assetID: nil, document: EditDocument(), lut: nil)
    }

    func testSuccessfulRunPublishesProgressAndValueResult() async {
        let coordinator = AutoWorkflowCoordinator()
        let runner = FakeRunner()
        var states: [AutoAdjustmentState] = []
        var completed: AutoWorkflowOutcome?
        _ = coordinator.start(
            request: request(), previewReady: true, runner: runner, isFenceCurrent: { true },
            onState: { state, _ in states.append(state) },
            completion: { _, value in completed = value })
        await coordinator.waitForCompletion()
        XCTAssertEqual(runner.calls, 1)
        XCTAssertEqual(completed?.message, "fake")
        XCTAssertTrue(states.contains(.renderingCandidates))
    }

    func testCancellationSuppressesLateResult() async {
        let coordinator = AutoWorkflowCoordinator()
        let runner = FakeRunner(delay: .milliseconds(80))
        var completed = false
        _ = coordinator.start(
            request: request(), previewReady: true, runner: runner, isFenceCurrent: { true },
            onState: { _, _ in }, completion: { _, _ in completed = true })
        coordinator.cancel { _, _ in }
        try? await Task.sleep(for: .milliseconds(120))
        XCTAssertFalse(completed)
    }

    func testSupersededInvocationCannotPublish() async {
        let coordinator = AutoWorkflowCoordinator()
        let slow = FakeRunner(delay: .milliseconds(80))
        let fast = FakeRunner()
        var results: [UInt64] = []
        _ = coordinator.start(
            request: request(), previewReady: true, runner: slow, isFenceCurrent: { true },
            onState: { _, _ in }, completion: { revision, _ in results.append(revision) })
        _ = coordinator.start(
            request: request(), previewReady: true, runner: fast, isFenceCurrent: { true },
            onState: { _, _ in }, completion: { revision, _ in results.append(revision) })
        await coordinator.waitForCompletion()
        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(results, [2])
    }

    func testNoPreviewDoesNotInvokeRunner() {
        let coordinator = AutoWorkflowCoordinator()
        let runner = FakeRunner()
        var state: AutoAdjustmentState?
        let revision = coordinator.start(
            request: request(), previewReady: false, runner: runner, isFenceCurrent: { true },
            onState: { value, _ in state = value }, completion: { _, _ in })
        XCTAssertNil(revision)
        XCTAssertEqual(runner.calls, 0)
        XCTAssertEqual(state, .unavailable("Auto is available when the photo preview is ready."))
    }

    func testDegradedPathCarriesExplicitReason() async {
        let coordinator = AutoWorkflowCoordinator()
        let reason = "Renderer sampling unavailable; histogram fallback used."
        let runner = FakeRunner(path: .degraded(reason))
        var path: AutoWorkflowPath?
        _ = coordinator.start(
            request: request(), previewReady: true, runner: runner, isFenceCurrent: { true },
            onState: { _, _ in }, completion: { _, outcome in path = outcome.path })
        await coordinator.waitForCompletion()
        XCTAssertEqual(path, .degraded(reason))
    }
    func testSourceOrDocumentRevisionFenceSuppressesResult() async {
        for staleSource in [true, false] {
            let coordinator = AutoWorkflowCoordinator()
            let runner = FakeRunner(delay: .milliseconds(40))
            let fence = Fence()
            var completed = false
            _ = coordinator.start(
                request: request(), previewReady: true, runner: runner,
                isFenceCurrent: { fence.sourceCurrent && fence.documentCurrent },
                onState: { _, _ in }, completion: { _, _ in completed = true }
            )
            if staleSource { fence.sourceCurrent = false } else { fence.documentCurrent = false }
            await coordinator.waitForCompletion()
            XCTAssertFalse(completed)
        }
    }

    func testProductionRunnerSurfacesHistogramFallbackReason() async {
        let engine = FakeRenderEngine()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("auto-workflow-\(UUID().uuidString)")
        let analysis = PhotoAnalysisCoordinator(
            engine: engine, cache: PhotoAnalysisCache(directory: directory),
            sceneClassifier: NoopSceneClassifier(), stages: [:]
        )
        let source = ImageSource(
            url: URL(fileURLWithPath: "/tmp/auto.jpg"),
            nativeExtent: CGSize(width: 64, height: 48)
        )
        let outcome = await ProductionAutoWorkflow(engine: engine, analysis: analysis).run(
            AutoWorkflowRequest(source: source, assetID: nil, document: EditDocument(), lut: nil),
            onProgress: { _ in }
        )
        guard case .degraded(let reason) = outcome.path else {
            return XCTFail("a renderer without content-aware sampling should use degraded mode")
        }
        XCTAssertTrue(reason.contains("Photo identity is unavailable"))
        XCTAssertTrue(outcome.message.contains("global histogram fallback"))
        XCTAssertTrue(outcome.message.contains(reason))
        XCTAssertEqual(outcome.result.status, .improved)
    }

}

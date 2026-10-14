import XCTest

@testable import KromoraKit

/// KRMA-910: the transition table in `docs/APP_ARCHITECTURE.md`, expressed as value tests, plus
/// lifecycle checks through the real `AppViewModel` boundary.
final class SourcePresentationStateTests: XCTestCase {
    func testSelectionRestartsEveryStageAndKeepsToolbarAvailability() {
        var state = SourcePresentationState()
        state.previewReady()
        state.beginSelection()
        XCTAssertTrue(state.isLoading)
        XCTAssertTrue(state.isNavigationLoading)
        XCTAssertTrue(state.isToolbarTransitioning)
        XCTAssertEqual(state.previewState, .loading)
        XCTAssertTrue(state.toolbarActionsAvailable, "the toolbar holds its settled availability")
    }

    func testSourcePreparationFinishesBeforeFirstFrameAndRenderedFrame() {
        var state = SourcePresentationState()
        state.beginSelection()
        state.sourcePrepared()
        XCTAssertFalse(state.isLoading)
        XCTAssertTrue(state.isNavigationLoading, "no frame is on the surface yet")
        XCTAssertEqual(state.previewState, .loading)
        state.firstFramePresented()
        XCTAssertFalse(state.isNavigationLoading)
        XCTAssertEqual(state.previewState, .loading, "full preview readiness is separate")
        XCTAssertTrue(state.isToolbarTransitioning)
        state.previewReady()
        XCTAssertEqual(state.previewState, .ready)
        XCTAssertTrue(state.toolbarActionsAvailable)
        XCTAssertFalse(state.isToolbarTransitioning)
    }

    func testSourceFailureSettlesEverythingAndFollowsSourceAvailability() {
        var state = SourcePresentationState()
        state.setInspectorDocumentPending(true)
        state.beginSelection()
        state.sourceFailed(hasSource: false)
        XCTAssertFalse(state.isLoading)
        XCTAssertFalse(state.isNavigationLoading)
        XCTAssertFalse(state.isInspectorDocumentPending)
        XCTAssertFalse(state.isToolbarTransitioning)
        XCTAssertFalse(state.toolbarActionsAvailable)
        XCTAssertEqual(state.previewState, .failed)

        state.previewFailed(hasSource: true)
        XCTAssertTrue(state.toolbarActionsAvailable)
    }

    func testEndSelectionLeavesPreviewUnlessSettledExplicitly() {
        var state = SourcePresentationState()
        state.beginSelection()
        state.endSelection()
        XCTAssertFalse(state.isLoading)
        XCTAssertEqual(state.previewState, .loading)
        state.endSelection(previewState: .empty)
        XCTAssertEqual(state.previewState, .empty)
    }

    func testClearReturnsToEmptyState() {
        var state = SourcePresentationState()
        state.beginSelection()
        state.previewReady()
        state.clear()
        XCTAssertEqual(state, SourcePresentationState())
    }

    func testShutdownLatchRejectsLateTransitions() {
        var state = SourcePresentationState()
        state.beginSelection()
        state.shutDown()
        XCTAssertFalse(state.isNavigationLoading)
        let frozen = state
        state.beginSelection()
        state.sourcePrepared()
        state.previewReady()
        state.previewFailed(hasSource: true)
        state.sourceFailed(hasSource: true)
        state.openFailed()
        state.endSelection(previewState: .ready)
        state.clear()
        state.setInspectorDocumentPending(true)
        state.inspectorDocumentSettled()
        state.beginSourcePreparation()
        XCTAssertEqual(state, frozen)
    }
}

@MainActor
final class SourcePresentationLifecycleTests: TempDirectoryTestCase {
    func testLateRenderCompletionsCannotReviveShutdownPresentation() async throws {
        let engine = FakeRenderEngine()
        await engine.gateSourcePreparation()
        let viewModel = makeAppViewModel(engine: engine)
        let url = try Fixtures.writeGradientPNG(
            width: 24, height: 16, named: "presentation.png", in: tempDirectory
        )
        viewModel.openImage(url: url)
        let deadline = Date().addingTimeInterval(5)
        while await engine.sourcePreparationCount == 0 {
            XCTAssertLessThan(Date(), deadline, "source preparation did not start")
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertTrue(viewModel.isLoading)
        XCTAssertTrue(viewModel.isNavigationLoading)
        XCTAssertEqual(viewModel.previewState, .loading)

        let shutdown = Task { @MainActor in await viewModel.shutdown() }
        try await pollUntil("presentation to shut down") { viewModel.presentation.isShutDown }
        await engine.releaseSourcePreparation()
        await shutdown.value
        let settled = viewModel.presentation
        viewModel.publishPreviewReady()
        viewModel.publishPreviewFailure()
        XCTAssertEqual(viewModel.presentation, settled)
        XCTAssertFalse(viewModel.isNavigationLoading)
        XCTAssertNotEqual(viewModel.previewState, .ready)
    }

    func testSourceSwitchFencesPreviousPhotoAndSettlesOnRenderedFrame() async throws {
        let first = try Fixtures.writeGradientPNG(width: 24, height: 16, named: "a.png", in: tempDirectory)
        let engine = FakeRenderEngine()
        let viewModel = makeAppViewModel(engine: engine)
        viewModel.openImage(url: first)
        let deadline = Date().addingTimeInterval(5)
        while viewModel.previewState != .ready {
            XCTAssertLessThan(Date(), deadline, "first photo did not settle")
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertFalse(viewModel.isNavigationLoading)
        XCTAssertTrue(viewModel.toolbarPhotoActionsAvailable)
        XCTAssertFalse(viewModel.isToolbarPhotoTransitioning)
    }
}

import XCTest
@testable import LumoKit

@MainActor
final class ThumbnailSwitchLifecycleTests: TempDirectoryTestCase {

    private func waitUntil(
        _ description: String,
        timeout: TimeInterval = 5,
        _ condition: @escaping @MainActor () async -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !(await condition()) {
            if Date() > deadline { return XCTFail("timed out waiting for \(description)") }
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    private func loadCollection(
        _ viewModel: AppViewModel,
        first: URL,
        second: URL
    ) async throws {
        viewModel.collection.loadFromFolder(tempDirectory)
        await viewModel.collection.scanCompletion()
        XCTAssertEqual(viewModel.collection.items.map(\.url), [first, second])
    }

    func testFilmstripSelectionPresentsRepeatedSelectionAndSettlesHistogram() async throws {
        let first = try Fixtures.writeGradientPNG(
            width: 16, height: 12, named: "first.png", in: tempDirectory
        )
        let second = try Fixtures.writeGradientPNG(
            width: 16, height: 12, named: "second.png", in: tempDirectory
        )
        let engine = FakeRenderEngine()
        let viewModel = makeAppViewModel(engine: engine)
        try await loadCollection(viewModel, first: first, second: second)

        viewModel.selectCollectionImage(at: 0)
        try await waitUntil("the first presented photo") {
            viewModel.sourceURL == first && viewModel.previewState == .ready
                && viewModel.previewSurface.image != nil
        }

        viewModel.isInspectorPresented = true
        try await waitUntil("the first histogram") { viewModel.histogram != nil }

        viewModel.selectCollectionImage(at: 1)
        viewModel.selectCollectionImage(at: 1)
        try await waitUntil("the repeated second selection") {
            viewModel.sourceURL == second && viewModel.previewState == .ready
                && viewModel.previewSurface.image != nil
                && viewModel.histogram != nil
        }

        XCTAssertEqual(viewModel.collection.selection.activeID, viewModel.collection.items[1].id)
        XCTAssertEqual(viewModel.histogramErrorMessage, nil)
        XCTAssertFalse(viewModel.isHistogramLoading)
        XCTAssertTrue(viewModel.canRunAutoAdjustment)
        let requests = await engine.histogramRequests
        XCTAssertTrue(requests.last?.source?.backing == .url(second))
    }

    func testSequentialOpenPresentsReplacementWithoutAnotherUserAction() async throws {
        let first = try Fixtures.writeGradientPNG(
            width: 16, height: 12, named: "sequential-first.png", in: tempDirectory
        )
        let second = try Fixtures.writeGradientPNG(
            width: 16, height: 12, named: "sequential-second.png", in: tempDirectory
        )
        let engine = FakeRenderEngine()
        let viewModel = makeAppViewModel(engine: engine)

        viewModel.openImage(url: first)
        // One-off opens are copied into the managed library before rendering. Assert the durable
        // source identity while retaining the original filename as the photo under test.
        guard let firstManagedURL = viewModel.collection.items.first(where: {
            $0.displayName == "sequential-first"
        })?.url else {
            return XCTFail("one-off open should add the first managed-library item")
        }
        try await waitUntil("the first preview") {
            viewModel.sourceURL == firstManagedURL && viewModel.previewState == .ready
                && viewModel.previewSurface.image != nil
        }

        // Keep the replacement renderer in flight. The test releases only B and never performs a
        // second model/view action after that release, matching the reported spinner failure.
        await engine.gatePreviews()
        viewModel.openImage(url: second)
        guard let secondManagedURL = viewModel.collection.items.first(where: {
            $0.displayName == "sequential-second"
        })?.url else {
            return XCTFail("one-off open should add the second managed-library item")
        }
        try await waitUntil("the second preview request") {
            let requests = await engine.previewRequests
            return viewModel.sourceURL == secondManagedURL
                && requests.contains { $0.source?.backing == .url(secondManagedURL) }
        }
        XCTAssertEqual(viewModel.previewState, .loading)
        XCTAssertFalse(viewModel.isLoading, "source preparation is complete while B renders")

        await engine.releaseNextPreview()
        try await waitUntil("the second preview") {
            viewModel.sourceURL == secondManagedURL && viewModel.previewState == .ready
                && viewModel.previewSurface.image != nil
        }
        XCTAssertFalse(viewModel.isLoading)
    }

    func testRapidThumbnailChangesCannotPublishAnObsoleteSourceOrHistogram() async throws {
        let first = try Fixtures.writeGradientPNG(
            width: 16, height: 12, named: "first.png", in: tempDirectory
        )
        let second = try Fixtures.writeGradientPNG(
            width: 16, height: 12, named: "second.png", in: tempDirectory
        )
        let engine = FakeRenderEngine()
        await engine.gateSourcePreparation()
        let viewModel = makeAppViewModel(engine: engine)
        try await loadCollection(viewModel, first: first, second: second)

        viewModel.selectCollectionImage(at: 0)
        try await waitUntil("the first source preparation") {
            await engine.sourcePreparationCount == 1
        }
        viewModel.selectCollectionImage(at: 1)
        await engine.releaseSourcePreparation()

        try await waitUntil("the latest photo presentation") {
            viewModel.sourceURL == second && viewModel.previewState == .ready
                && viewModel.previewSurface.image != nil
        }
        XCTAssertEqual(viewModel.collection.selection.activeID, viewModel.collection.items[1].id)
        XCTAssertNotEqual(viewModel.sourceURL, first)

        await engine.gateHistogram()
        viewModel.isInspectorPresented = true
        try await waitUntil("the current histogram request") {
            await engine.histogramRequests.contains { $0.source?.backing == .url(second) }
        }
        viewModel.selectCollectionImage(at: 0)
        await engine.releaseHistograms()

        try await waitUntil("the first photo after the switch back") {
            viewModel.sourceURL == first && viewModel.previewState == .ready
                && viewModel.histogram != nil
        }
        XCTAssertTrue(viewModel.canRunAutoAdjustment)
        let histogramRequests = await engine.histogramRequests
        XCTAssertTrue(histogramRequests.last?.source?.backing == .url(first))
    }

    func testDelayedAutoCompletionCannotMakeTheNextThumbnailReady() async throws {
        let first = try Fixtures.writeGradientPNG(
            width: 16, height: 12, named: "auto-first.png", in: tempDirectory
        )
        let second = try Fixtures.writeGradientPNG(
            width: 16, height: 12, named: "auto-second.png", in: tempDirectory
        )
        let engine = FakeRenderEngine()
        let viewModel = makeAppViewModel(engine: engine)
        try await loadCollection(viewModel, first: first, second: second)

        viewModel.selectCollectionImage(at: 0)
        try await waitUntil("the first photo presentation") {
            viewModel.previewState == .ready && viewModel.canRunAutoAdjustment
        }

        await engine.gateHistogram()
        viewModel.runAutoAdjustment()
        try await waitUntil("the delayed Auto analysis") {
            await engine.histogramRequests.contains { $0.source?.backing == .url(first) }
        }

        await engine.gatePreviews()
        viewModel.selectCollectionImage(at: 1)
        try await waitUntil("the next photo source") { viewModel.sourceURL == second }
        XCTAssertEqual(viewModel.autoAdjustmentState, .unavailable(
            "Auto is available when the photo preview is ready."
        ))

        await engine.releaseHistograms()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(viewModel.autoAdjustmentState, .unavailable(
            "Auto is available when the photo preview is ready."
        ), "the old analysis must not publish ready for the loading photo")
        XCTAssertFalse(viewModel.canRunAutoAdjustment)

        await engine.releasePreviews()
        try await waitUntil("the next photo presentation") {
            viewModel.previewState == .ready && viewModel.canRunAutoAdjustment
        }
    }

    func testLibraryGridHandoffPresentsTheSelectedPhotoWithoutTabSwitching() async throws {
        let first = try Fixtures.writeGradientPNG(
            width: 16, height: 12, named: "first.png", in: tempDirectory
        )
        let second = try Fixtures.writeGradientPNG(
            width: 16, height: 12, named: "second.png", in: tempDirectory
        )
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())
        try await loadCollection(viewModel, first: first, second: second)

        XCTAssertTrue(viewModel.navigate(to: .grid))
        viewModel.selectLibraryItem(at: 1)
        XCTAssertTrue(viewModel.navigate(to: .edit))

        try await waitUntil("the selected grid photo and histogram") {
            viewModel.collection.selection.activeID == viewModel.collection.items[1].id
                && viewModel.sourceURL == second
                && viewModel.previewState == .ready
                && viewModel.previewSurface.image != nil
        }
        XCTAssertNil(viewModel.histogramErrorMessage)
        XCTAssertFalse(viewModel.isHistogramLoading)
    }

    func testFailedSourceAndFailedHistogramLeaveTerminalStates() async throws {
        let missing = tempDirectory.appendingPathComponent("missing.png")
        let sourceEngine = FakeRenderEngine()
        let sourceViewModel = makeAppViewModel(engine: sourceEngine)
        sourceViewModel.openImage(url: missing)

        try await waitUntil("the source failure") {
            sourceViewModel.previewState == .failed && !sourceViewModel.isLoading
        }
        XCTAssertNil(sourceViewModel.sourceImage)
        XCTAssertNotNil(sourceViewModel.errorMessage)

        let image = try Fixtures.writeGradientPNG(
            width: 16, height: 12, named: "histogram-failure.png", in: tempDirectory
        )
        let histogramEngine = FakeRenderEngine()
        await histogramEngine.setShouldFailHistogram(true)
        let histogramViewModel = makeAppViewModel(engine: histogramEngine)
        histogramViewModel.openImage(url: image)
        try await waitUntil("the image presentation") {
            histogramViewModel.previewState == .ready
        }
        histogramViewModel.isInspectorPresented = true
        try await waitUntil("the histogram failure") {
            !histogramViewModel.isHistogramLoading
                && histogramViewModel.histogramErrorMessage != nil
        }
        XCTAssertNil(histogramViewModel.histogram)
    }
}

import XCTest
@testable import KromoraKit

@MainActor
final class AutoAdjustmentTests: TempDirectoryTestCase {
    private struct NoopSceneClassifier: SceneClassifierProviding {
        func classifications(for image: AnalysisImage) async -> [SceneClassificationObservation]? {
            nil
        }
    }

    /// Keep these editor integration tests on the legacy histogram path. The production content
    /// aware path is covered by ContentAwareAutoEngineTests; this coordinator makes the milestone
    /// under test independent of Vision availability and mask timing.
    private func makeHistogramAutoViewModel(_ fake: FakeRenderEngine) -> AppViewModel {
        let coordinator = PhotoAnalysisCoordinator(
            engine: fake,
            cache: PhotoAnalysisCache(
                directory: tempDirectory.appendingPathComponent("auto-analysis-cache")
            ),
            sceneClassifier: NoopSceneClassifier(), stages: [:]
        )
        return makeAppViewModel(engine: fake, photoAnalysisCoordinator: coordinator)
    }

    private func histogram(
        luma: [(Int, Int)],
        red: [(Int, Int)]? = nil,
        green: [(Int, Int)]? = nil,
        blue: [(Int, Int)]? = nil
    ) -> HistogramData {
        func bins(_ values: [(Int, Int)]) -> [Int] {
            var result = [Int](repeating: 0, count: 256)
            for (level, count) in values { result[level] = count }
            return result
        }
        let channels = red ?? luma
        return HistogramData(
            red: bins(channels), green: bins(green ?? channels), blue: bins(blue ?? channels),
            luma: bins(luma)
        )
    }

    func testRepresentativeFixturesProduceFiniteBoundedAndStableResults() {
        let fixtures: [HistogramData] = [
            // Neutral, clipped, low-key, high-contrast, and color-biased representatives.
            histogram(luma: [(128, 100)]),
            histogram(luma: [(0, 20), (128, 60), (255, 20)]),
            histogram(luma: [(24, 60), (48, 40)]),
            histogram(luma: [(0, 50), (255, 50)]),
            histogram(luma: [(80, 100)], red: [(240, 100)], green: [(55, 100)], blue: [(35, 100)])
        ]

        for fixture in fixtures {
            guard let first = AutoAdjustmentAnalyzer.analyze(histogram: fixture),
                  let second = AutoAdjustmentAnalyzer.analyze(histogram: fixture) else {
                return XCTFail("representative histogram should be actionable")
            }
            XCTAssertEqual(first, second, "Auto must be deterministic for one analyzed input")
            XCTAssertTrue(first.light.exposure.isFinite)
            XCTAssertTrue(first.light.contrast.isFinite)
            XCTAssertTrue(first.light.highlights.isFinite)
            XCTAssertTrue(first.light.shadows.isFinite)
            XCTAssertTrue(first.light.whites.isFinite)
            XCTAssertTrue(first.light.blacks.isFinite)
            XCTAssertTrue(first.color.vibrance.isFinite)
            XCTAssertTrue(first.color.saturation.isFinite)
            XCTAssertTrue(LightAdjustments.exposureRange.contains(first.light.exposure))
            XCTAssertTrue(LightAdjustments.contrastRange.contains(first.light.contrast))
            XCTAssertTrue(LightAdjustments.highlightsRange.contains(first.light.highlights))
            XCTAssertTrue(LightAdjustments.shadowsRange.contains(first.light.shadows))
            XCTAssertTrue(LightAdjustments.whitesRange.contains(first.light.whites))
            XCTAssertTrue(LightAdjustments.blacksRange.contains(first.light.blacks))
            XCTAssertTrue(ColorAdjustments.vibranceRange.contains(first.color.vibrance))
            XCTAssertTrue(ColorAdjustments.saturationRange.contains(first.color.saturation))
        }
    }

    func testHeuristicRespondsConservativelyToLowKeyClippingAndColorBias() {
        let lowKey = AutoAdjustmentAnalyzer.analyze(
            histogram: histogram(luma: [(24, 60), (48, 40)])
        )!
        XCTAssertGreaterThan(lowKey.light.exposure, 0)
        XCTAssertGreaterThan(lowKey.light.shadows, 0)

        let clipped = AutoAdjustmentAnalyzer.analyze(
            histogram: histogram(
                luma: [(0, 20), (128, 60), (255, 20)],
                red: [(255, 70), (100, 30)], green: [(120, 100)], blue: [(100, 100)]
            )
        )!
        XCTAssertLessThan(clipped.light.highlights, 0)
        XCTAssertGreaterThan(clipped.light.shadows, 0)
        XCTAssertLessThan(clipped.color.saturation, 0)

        let highContrast = AutoAdjustmentAnalyzer.analyze(
            histogram: histogram(luma: [(0, 50), (255, 50)])
        )!
        XCTAssertLessThanOrEqual(highContrast.light.contrast, 0)
    }

    func testMalformedOrEmptyHistogramDoesNotProduceAnEdit() {
        let empty = HistogramData(
            red: [Int](repeating: 0, count: 256),
            green: [Int](repeating: 0, count: 256),
            blue: [Int](repeating: 0, count: 256),
            luma: [Int](repeating: 0, count: 256)
        )
        XCTAssertNil(AutoAdjustmentAnalyzer.analyze(histogram: empty))
        XCTAssertNil(AutoAdjustmentAnalyzer.analyze(
            histogram: HistogramData(red: [0], green: [0], blue: [0], luma: [0])
        ))
    }

    private func openStandardImage(_ viewModel: AppViewModel) async throws {
        let url = try Fixtures.writeGradientPNG(
            width: 32, height: 24, named: "auto.png", in: tempDirectory
        )
        viewModel.openImage(url: url)
        let deadline = Date().addingTimeInterval(5)
        while viewModel.previewState != .ready {
            if Date() > deadline { return XCTFail("timed out waiting for the preview") }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    func testActionIsUnavailableBeforeASettledSupportedPhoto() {
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())
        XCTAssertFalse(viewModel.canRunAutoAdjustment)
        XCTAssertFalse(viewModel.isAutoAdjustmentInProgress)
        XCTAssertTrue(viewModel.autoAdjustmentHelp.contains("supported photo"))
    }

    func testActionRemainsAvailableWhileOptionalHistogramWorkIsLoading() async throws {
        let fake = FakeRenderEngine()
        let viewModel = makeAppViewModel(engine: fake)
        try await openStandardImage(viewModel)

        await fake.gateHistogram()
        viewModel.toggleInspector()
        try await Task.sleep(for: .milliseconds(20))

        XCTAssertTrue(viewModel.canRunAutoAdjustment)
        XCTAssertTrue(viewModel.isHistogramLoading)

        await fake.releaseHistograms()
    }

    func testAutoAvailabilityRefreshesWhenNavigatingBetweenPhotos() async throws {
        let fake = FakeRenderEngine()
        let viewModel = makeAppViewModel(engine: fake)
        try await openStandardImage(viewModel)
        XCTAssertTrue(viewModel.canRunAutoAdjustment)

        let secondURL = try Fixtures.writeGradientPNG(
            width: 40, height: 30, named: "auto-second.png", in: tempDirectory
        )
        viewModel.openImage(url: secondURL)

        XCTAssertFalse(
            viewModel.canRunAutoAdjustment,
            "the prior photo's readiness must not leak into the newly loading one"
        )

        let deadline = Date().addingTimeInterval(5)
        while viewModel.previewState != .ready {
            if Date() > deadline { return XCTFail("timed out waiting for the second preview") }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(viewModel.canRunAutoAdjustment)
    }

    func testAutoAvailableForPhotosLibraryImport() async throws {
        let fake = FakeRenderEngine()
        let viewModel = makeAppViewModel(engine: fake)
        let url = try Fixtures.writeJPEG(
            width: 60, height: 40, orientation: 1, named: "photos-import.jpg", in: tempDirectory
        )
        let data = try Data(contentsOf: url)

        viewModel.openImage(data: data, name: "Imported Photo")

        let deadline = Date().addingTimeInterval(5)
        while viewModel.previewState != .ready {
            if Date() > deadline { return XCTFail("timed out waiting for the imported preview") }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(viewModel.canRunAutoAdjustment)
    }

    func testAutoReplacesOnlyGlobalLightAndColorAsOneUndoableOperation() async throws {
        let fake = FakeRenderEngine()
        let viewModel = makeAppViewModel(engine: fake)
        try await openStandardImage(viewModel)
        viewModel.updateDocument {
            $0.rawDevelop.exposure = 0.4
            $0.light.exposure = 1
            $0.color.saturation = 20
            $0.color.mixer.blue.saturation = 15
            $0.adjustments = [.exposure(ev: 0.5)]
            $0.effects.vignette.amount = 10
            $0.crop = CropAdjustments(normalizedRect: CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8))
        }
        let before = viewModel.document
        let depthBefore = viewModel.undoDepth

        viewModel.runAutoAdjustment()
        let deadline = Date().addingTimeInterval(5)
        while !viewModel.statusMessage.hasPrefix("Auto applied") {
            if Date() > deadline { return XCTFail("timed out waiting for Auto") }
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertEqual(viewModel.undoDepth, depthBefore + 1)
        XCTAssertEqual(viewModel.document.rawDevelop, before.rawDevelop)
        XCTAssertEqual(viewModel.document.adjustments, before.adjustments)
        XCTAssertEqual(viewModel.document.effects, before.effects)
        XCTAssertEqual(viewModel.document.crop, before.crop)
        XCTAssertEqual(viewModel.document.color.mixer, before.color.mixer)
        XCTAssertNotEqual(viewModel.document.light, before.light)

        viewModel.undo()
        XCTAssertEqual(viewModel.document, before, "one undo must restore the complete prior document")
    }

    func testFailureLeavesAutoAndHistogramOutOfLoadingState() async throws {
        let fake = FakeRenderEngine()
        let viewModel = makeHistogramAutoViewModel(fake)
        try await openStandardImage(viewModel)
        await fake.setShouldFailHistogram(true)
        let reader = FakeRenderEventReader(await fake.eventStream())

        viewModel.runAutoAdjustment()
        XCTAssertEqual(viewModel.autoAdjustmentState, .analyzing)
        XCTAssertEqual(viewModel.autoAdjustmentProgress, 0)
        _ = try await TestSynchronization.nextEvent(from: reader, "Auto histogram request") {
            if case .histogramRequested = $0 { return true }
            return false
        } diagnostics: {
            "histogram requests=\(await fake.histogramRequests.count)"
        }
        _ = try await TestSynchronization.nextEvent(from: reader, "Auto histogram failure") {
            if case .histogramCompleted(_, nil) = $0 { return true }
            return false
        } diagnostics: {
            "histogram requests=\(await fake.histogramRequests.count)"
        }
        await viewModel.waitForAutoAdjustmentCompletion()
        XCTAssertTrue(viewModel.autoAdjustmentHelp.contains("could not analyze"))
        XCTAssertFalse(viewModel.isAutoAdjustmentInProgress)
        XCTAssertNil(viewModel.autoAdjustmentProgress)
        XCTAssertFalse(viewModel.isHistogramLoading)
    }

    func testAnalysisShowsProgressWithoutBorrowingHistogramLoadingState() async throws {
        let fake = FakeRenderEngine()
        let viewModel = makeHistogramAutoViewModel(fake)
        try await openStandardImage(viewModel)
        await fake.gateHistogram()
        let reader = FakeRenderEventReader(await fake.eventStream())

        viewModel.runAutoAdjustment()
        XCTAssertEqual(viewModel.autoAdjustmentState, .analyzing)
        XCTAssertEqual(viewModel.autoAdjustmentProgress, 0)
        XCTAssertFalse(viewModel.isHistogramLoading)
        XCTAssertTrue(viewModel.autoAdjustmentHelp.contains("Analyzing"))

        _ = try await TestSynchronization.nextEvent(from: reader, "Auto histogram request") {
            if case .histogramRequested = $0 { return true }
            return false
        } diagnostics: {
            "histogram requests=\(await fake.histogramRequests.count)"
        }

        await fake.releaseHistograms()
        _ = try await TestSynchronization.nextEvent(from: reader, "Auto histogram completion") {
            if case .histogramCompleted(_, let result) = $0 { return result != nil }
            return false
        } diagnostics: {
            "histogram requests=\(await fake.histogramRequests.count)"
        }
        await viewModel.waitForAutoAdjustmentCompletion()
        XCTAssertTrue(viewModel.statusMessage.hasPrefix("Auto applied"))
        XCTAssertNil(viewModel.autoAdjustmentProgress)
        let requests = await fake.histogramRequests
        XCTAssertEqual(requests.last?.lutID, nil)
        XCTAssertTrue(requests.last?.document.light.isIdentity == true)
        XCTAssertEqual(requests.last?.document.color.vibrance, 0)
        XCTAssertEqual(requests.last?.document.color.saturation, 0)
    }

    func testCancellingAutoLeavesDocumentUntouchedAndClearsLoadingState() async throws {
        let fake = FakeRenderEngine()
        let viewModel = makeHistogramAutoViewModel(fake)
        try await openStandardImage(viewModel)
        let before = viewModel.document
        await fake.gateHistogram()
        let reader = FakeRenderEventReader(await fake.eventStream())

        viewModel.runAutoAdjustment()
        _ = try await TestSynchronization.nextEvent(from: reader, "Auto histogram request") {
            if case .histogramRequested = $0 { return true }
            return false
        } diagnostics: {
            "histogram requests=\(await fake.histogramRequests.count)"
        }

        viewModel.cancelAutoAdjustment()
        XCTAssertFalse(viewModel.isAutoAdjustmentInProgress)
        XCTAssertEqual(viewModel.autoAdjustmentState, .cancelled)
        XCTAssertNil(viewModel.autoAdjustmentProgress)
        await fake.releaseHistograms()
        _ = try await TestSynchronization.nextEvent(from: reader, "cancelled Auto histogram completion") {
            if case .histogramCompleted = $0 { return true }
            return false
        } diagnostics: {
            "histogram requests=\(await fake.histogramRequests.count)"
        }
        await viewModel.waitForAutoAdjustmentCompletion()

        XCTAssertEqual(viewModel.document, before)
        XCTAssertEqual(viewModel.statusMessage, "Auto cancelled; nothing was changed.")
    }

    func testRepeatingAutoIsDeterministicAndDoesNotAddAnotherHistoryEntry() async throws {
        let fake = FakeRenderEngine()
        let viewModel = makeAppViewModel(engine: fake)
        try await openStandardImage(viewModel)

        viewModel.runAutoAdjustment()
        await viewModel.waitForAutoAdjustmentCompletion()
        XCTAssertTrue(viewModel.statusMessage.hasPrefix("Auto applied"))
        let first = viewModel.document
        let depth = viewModel.undoDepth

        viewModel.runAutoAdjustment()
        await viewModel.waitForAutoAdjustmentCompletion()
        XCTAssertEqual(viewModel.document, first)
        XCTAssertEqual(viewModel.undoDepth, depth)
    }
}

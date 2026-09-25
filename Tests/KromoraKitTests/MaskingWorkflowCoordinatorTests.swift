import XCTest

@testable import KromoraKit

@MainActor
final class MaskingWorkflowCoordinatorTests: XCTestCase {
    @MainActor
    private final class FakeDestination: MaskingWorkflowDestination {
        var document = EditDocument()
        var hasOpenSource = true
        var maskingSource: ImageSource?
        var maskingAssetID: PhotoAssetID?
        var maskingSourceRevision: UInt64 = 0
        var maskOverlaySource: ImageSource?
        let maskOverlayEngine: any RenderEngining
        private(set) var statusMessages: [String] = []
        private(set) var undoGroupingEndedCount = 0
        private(set) var previewInteractionBeginCount = 0
        private(set) var previewInteractionEndCount = 0
        private(set) var retryPreviewCount = 0
        private(set) var presentedWorkspace = false
        private(set) var dismissedWorkspace = false
        private(set) var documentUpdateDebounceValues: [Bool] = []

        init(engine: any RenderEngining) {
            maskOverlayEngine = engine
        }

        func updateDocument(_ transform: (inout EditDocument) -> Void) {
            documentUpdateDebounceValues.append(false)
            transform(&document)
        }

        func updateDocument(debounced: Bool, _ transform: (inout EditDocument) -> Void) {
            documentUpdateDebounceValues.append(debounced)
            transform(&document)
        }

        func setMaskingStatusMessage(_ message: String) { statusMessages.append(message) }
        func endUndoGrouping() { undoGroupingEndedCount += 1 }
        func beginPreviewInteraction() { previewInteractionBeginCount += 1 }
        func endPreviewInteraction() { previewInteractionEndCount += 1 }
        func retryPreview() { retryPreviewCount += 1 }
        func presentMaskingWorkspace() { presentedWorkspace = true }
        func dismissMaskingWorkspace() { dismissedWorkspace = true }
    }

    /// A fake analysis boundary. `mask(...)` is the only call exercised by the `.subject` target
    /// used throughout these tests, so `analyze` (only reached for `.person`) always fails.
    private actor FakeAnalysisProvider: MaskAnalysisProviding {
        private(set) var maskCallCount = 0
        private(set) var prepareCallCount = 0
        var delay: Duration = .zero
        var result: Result<RegionMask, Error> = .failure(CancellationError())

        func configure(delay: Duration, result: Result<RegionMask, Error>) {
            self.delay = delay
            self.result = result
        }

        func analyze(
            assetID: PhotoAssetID, source: ImageSource, level: PhotoAnalysisLevel
        ) async throws -> PhotoAnalysis {
            throw CancellationError()
        }

        func mask(
            assetID: PhotoAssetID, source: ImageSource, kind: SemanticMaskKind, quality: MaskQuality
        ) async throws -> RegionMask {
            maskCallCount += 1
            if delay > .zero { try? await Task.sleep(for: delay) }
            return try result.get()
        }

        func preparePersonSignals(
            assetID: PhotoAssetID, source: ImageSource, quality: MaskQuality
        ) async {
            prepareCallCount += 1
        }
    }

    private func makeSource() -> ImageSource {
        ImageSource(
            url: URL(fileURLWithPath: "/tmp/masking-\(UUID().uuidString).jpg"),
            nativeExtent: CGSize(width: 100, height: 100)
        )
    }

    private func regionMask(
        kind: SemanticMaskKind = .subject, confidence: Float = 0.9, coverage: Float = 0.4
    ) -> RegionMask {
        let identity = PortablePhotoIdentity.compatibility(
            assetID: PhotoAssetID(rawValue: "asset-1"),
            sourceFingerprint: PhotoSourceFingerprint.data(Data("x".utf8), digest: "x")
        )
        let cacheKey = MaskCacheKey(identity: identity, kind: kind, quality: .preview)
        let reference = RegionMaskReference(
            cacheKey: cacheKey, size: PixelDimensions(width: 10, height: 10))
        return RegionMask(
            kind: kind, bounds: NormalizedRect(x: 0, y: 0, width: 1, height: 1),
            quality: .preview, reference: reference, confidence: confidence, coverage: coverage
        )
    }

    private func makeCoordinator(
        analysis: FakeAnalysisProvider = FakeAnalysisProvider()
    ) -> (MaskingWorkflowCoordinator, FakeDestination, FakeAnalysisProvider) {
        let destination = FakeDestination(engine: FakeRenderEngine())
        let coordinator = MaskingWorkflowCoordinator(analysis: analysis, destination: destination)
        return (coordinator, destination, analysis)
    }

    func testLocalAdjustmentUpdatePreservesDebouncedPreviewIntent() throws {
        let (coordinator, destination, _) = makeCoordinator()
        let layer = LocalAdjustmentLayer()
        destination.document.localAdjustments = [layer]

        coordinator.updateMask(layer.id, debounced: true) { $0.adjustments.exposure = -5 }

        XCTAssertEqual(destination.document.localAdjustments.first?.adjustments.exposure, -5)
        XCTAssertEqual(destination.documentUpdateDebounceValues, [true])
    }

    func testCreateSmartMaskInsertsDurableLayerOnSuccess() async {
        let analysis = FakeAnalysisProvider()
        await analysis.configure(delay: .zero, result: .success(regionMask()))
        let (coordinator, destination, _) = makeCoordinator(analysis: analysis)
        destination.maskingSource = makeSource()
        destination.maskingAssetID = PhotoAssetID(rawValue: "asset-1")

        coordinator.createSmartMask(.subject)
        await coordinator.waitForInFlightSmartMask()

        XCTAssertEqual(destination.document.localAdjustments.count, 1)
        let component = destination.document.localAdjustments.first?.components.first
        if case .semantic(let definition) = component?.source {
            XCTAssertEqual(definition.target, .subject)
        } else {
            XCTFail("expected a semantic subject component")
        }
        XCTAssertEqual(destination.statusMessages.last, "Created Subject mask")
        XCTAssertNil(coordinator.smartMaskRetryContext)
    }

    func testCreateSmartMaskWithoutOpenSourceReportsUnavailable() async {
        let (coordinator, destination, analysis) = makeCoordinator()
        destination.maskingSource = nil
        destination.maskingAssetID = nil

        coordinator.createSmartMask(.subject)

        XCTAssertTrue(destination.document.localAdjustments.isEmpty)
        XCTAssertEqual(
            destination.statusMessages.last,
            "Smart masks require an open photo with supported analysis.")
        let calls = await analysis.maskCallCount
        XCTAssertEqual(calls, 0)
    }

    func testCreateSmartMaskSupersessionOnlyAdmitsLatestResult() async {
        let analysis = FakeAnalysisProvider()
        await analysis.configure(delay: .milliseconds(80), result: .success(regionMask(kind: .subject)))
        let (coordinator, destination, _) = makeCoordinator(analysis: analysis)
        destination.maskingSource = makeSource()
        destination.maskingAssetID = PhotoAssetID(rawValue: "asset-1")

        // First invocation is superseded before it can resolve; its task is cancelled by the
        // second call, so its (still in-flight) provider result must never land.
        coordinator.createSmartMask(.subject)
        try? await Task.sleep(for: .milliseconds(10))
        coordinator.createSmartMask(.background)
        await coordinator.waitForInFlightSmartMask()

        XCTAssertEqual(destination.document.localAdjustments.count, 1)
        guard case .semantic(let definition) =
            destination.document.localAdjustments.first?.components.first?.source
        else {
            return XCTFail("expected a semantic component")
        }
        XCTAssertEqual(definition.target, .background)
    }

    func testCreateSmartMaskCancellationLeavesNoLayer() async {
        let analysis = FakeAnalysisProvider()
        await analysis.configure(delay: .milliseconds(100), result: .success(regionMask()))
        let (coordinator, destination, _) = makeCoordinator(analysis: analysis)
        destination.maskingSource = makeSource()
        destination.maskingAssetID = PhotoAssetID(rawValue: "asset-1")

        coordinator.createSmartMask(.subject)
        coordinator.cancelInFlightSmartMask()
        try? await Task.sleep(for: .milliseconds(150))

        XCTAssertTrue(destination.document.localAdjustments.isEmpty)
        XCTAssertNil(coordinator.smartMaskRetryContext)
    }

    func testCreateSmartMaskFailurePreparesRetryContext() async {
        let analysis = FakeAnalysisProvider()
        await analysis.configure(delay: .zero, result: .failure(RegionMaskError.invalidPixelCount))
        let (coordinator, destination, _) = makeCoordinator(analysis: analysis)
        destination.maskingSource = makeSource()
        destination.maskingAssetID = PhotoAssetID(rawValue: "asset-1")

        coordinator.createSmartMask(.subject)
        await coordinator.waitForInFlightSmartMask()

        XCTAssertTrue(destination.document.localAdjustments.isEmpty)
        XCTAssertEqual(coordinator.smartMaskRetryContext, .create(.subject))
        XCTAssertNotNil(destination.statusMessages.last)
    }

    func testRetryMaskAnalysisReplaysCreateContext() async {
        let analysis = FakeAnalysisProvider()
        await analysis.configure(delay: .zero, result: .failure(RegionMaskError.invalidPixelCount))
        let (coordinator, destination, _) = makeCoordinator(analysis: analysis)
        destination.maskingSource = makeSource()
        destination.maskingAssetID = PhotoAssetID(rawValue: "asset-1")

        coordinator.createSmartMask(.subject)
        await coordinator.waitForInFlightSmartMask()
        XCTAssertEqual(coordinator.smartMaskRetryContext, .create(.subject))

        await analysis.configure(delay: .zero, result: .success(regionMask()))
        coordinator.retryMaskAnalysis()
        await coordinator.waitForInFlightSmartMask()

        XCTAssertEqual(destination.document.localAdjustments.count, 1)
        XCTAssertNil(coordinator.smartMaskRetryContext)
    }

    func testShutdownCancelsInFlightWorkWithoutCrashing() async {
        let analysis = FakeAnalysisProvider()
        await analysis.configure(delay: .milliseconds(200), result: .success(regionMask()))
        let (coordinator, destination, _) = makeCoordinator(analysis: analysis)
        destination.maskingSource = makeSource()
        destination.maskingAssetID = PhotoAssetID(rawValue: "asset-1")

        coordinator.createSmartMask(.subject)
        await coordinator.shutdown()

        XCTAssertTrue(destination.document.localAdjustments.isEmpty)
    }

    func testCreateMaskAppendsLayerAndSelectsIt() {
        let (coordinator, destination, _) = makeCoordinator()
        destination.maskingSource = makeSource()
        destination.maskingAssetID = PhotoAssetID(rawValue: "asset-1")

        coordinator.createMask(.brush)

        XCTAssertEqual(destination.document.localAdjustments.count, 1)
        XCTAssertEqual(
            coordinator.interactionState.selectedLayerID,
            destination.document.localAdjustments.first?.id)
        XCTAssertEqual(destination.undoGroupingEndedCount, 1)
    }

    func testDeleteMaskRemovesLayerAndClearsSolo() {
        let (coordinator, destination, _) = makeCoordinator()
        coordinator.createMask(.brush)
        let id = destination.document.localAdjustments[0].id

        coordinator.deleteMask(id)

        XCTAssertTrue(destination.document.localAdjustments.isEmpty)
        XCTAssertNil(coordinator.interactionState.selectedLayerID)
    }
}

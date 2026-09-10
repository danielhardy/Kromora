import Foundation
import XCTest

@testable import KromoraKit

/// Regression coverage for LUMO-270: a Person mask must be recoverable when the mask store is
/// cold, even while the disk analysis cache is warm (which defeats the analyze preflight that
/// used to be the only signal-warming path).
@MainActor
final class PersonSignalWarmingTests: TempDirectoryTestCase {

    // MARK: - Primitive

    func testPrepareRequestsBothSignals() async throws {
        let store = MaskStore(directory: tempDirectory.appendingPathComponent("masks"))
        let provider = GatedPersonStubProvider(store: store)
        let coordinator = PhotoAnalysisCoordinator(maskStore: store, maskProvider: provider)
        let source = try makeSource(named: "prepare.png")

        await coordinator.preparePersonSignals(
            assetID: .photos(localIdentifier: "prepare"), source: source, quality: .preview
        )

        let requested = await provider.requestedKinds
        XCTAssertTrue(requested.contains(.face))
        XCTAssertTrue(requested.contains(.foregroundInstance(0)))
    }

    func testPrepareToleratesAFailingSignal() async throws {
        let store = MaskStore(directory: tempDirectory.appendingPathComponent("masks"))
        let provider = GatedPersonStubProvider(store: store)
        await provider.setFailFace(true)
        let coordinator = PhotoAnalysisCoordinator(maskStore: store, maskProvider: provider)
        let source = try makeSource(named: "tolerant.png")

        // Must return normally: one missing signal never blocks the other.
        await coordinator.preparePersonSignals(
            assetID: .photos(localIdentifier: "tolerant"), source: source, quality: .preview
        )

        let requested = await provider.requestedKinds
        XCTAssertTrue(requested.contains(.face))
        XCTAssertTrue(requested.contains(.foregroundInstance(0)))
    }

    // MARK: - Incident replica: warm analysis cache, cold mask store

    /// Mirrors the LUMO-270 screenshot: the analysis cache is warm (preflight short-circuits)
    /// while the mask store has no signals. Person creation must warm explicitly and succeed.
    ///
    /// The assetID comes from the opened photo (not a fixture constant): the incident needs the
    /// creation-time analyze to hit the analysis cache warmed in step 1, which is keyed by the
    /// app-derived assetID.
    func testPersonCreationSucceedsWithColdStoreAndWarmAnalysisCache() async throws {
        let url = try Fixtures.writeGradientPNG(width: 64, height: 48, named: "warming.png", in: tempDirectory)

        // Step 1: open first so the assetID is the app-derived one, then warm the shared disk
        // analysis cache with a throwaway coordinator/store pair that is abandoned afterwards.
        let coldStore = MaskStore(directory: tempDirectory.appendingPathComponent("cold-masks"))
        let provider = GatedPersonStubProvider(store: coldStore)
        let coordinator = PhotoAnalysisCoordinator(maskStore: coldStore, maskProvider: provider)
        let viewModel = makeAppViewModel(
            engine: FakeRenderEngine(),
            editStore: makeInMemoryEditStore(),
            photoAnalysisCoordinator: coordinator
        )
        viewModel.openImage(url: url)
        try await waitUntil("the image to load") { viewModel.sourceImage != nil }
        let assetID = try XCTUnwrap(viewModel.maskingAssetID)
        let source = try XCTUnwrap(viewModel.maskingSource)
        let warmStore = MaskStore(directory: tempDirectory.appendingPathComponent("warm-masks"))
        let warmCoordinator = PhotoAnalysisCoordinator(
            maskStore: warmStore, maskProvider: GatedPersonStubProvider(store: warmStore)
        )
        _ = try await warmCoordinator.analyze(assetID: assetID, source: source, level: .detailed)

        // Step 2: the creation-time analyze short-circuits on that cached analysis while this
        // coordinator's mask store is cold. Without explicit warming the stub gate throws and
        // creation fails; with it, creation succeeds.
        viewModel.createSmartMask(.person)
        try await waitUntil("the person layer to be created") {
            viewModel.document.localAdjustments.contains {
                $0.components.contains {
                    $0.source.semanticDefinition?.target == .person
                }
            }
        }

        // The gate could only have passed via explicit warming at overlay quality: detailed
        // stages were skipped (analysis cache hit), so these .preview requests came from
        // preparePersonSignals.
        let requested = await provider.requestedKinds
        XCTAssertTrue(requested.contains(.face))
        XCTAssertTrue(requested.contains(.foregroundInstance(0)))
        XCTAssertEqual(viewModel.statusMessage, "Created Person mask")
    }

    // MARK: - Retry heals

    /// Retry with a selected person component and no retry context must warm the signals and
    /// force the overlay task to re-resolve (epoch bump) instead of just re-rendering.
    func testRetryWarmsSignalsAndBumpsResolveEpoch() async throws {
        let url = try Fixtures.writeGradientPNG(width: 64, height: 48, named: "retry.png", in: tempDirectory)
        let coldStore = MaskStore(directory: tempDirectory.appendingPathComponent("retry-masks"))
        let provider = GatedPersonStubProvider(store: coldStore)
        let coordinator = PhotoAnalysisCoordinator(maskStore: coldStore, maskProvider: provider)
        let viewModel = makeAppViewModel(
            engine: FakeRenderEngine(),
            editStore: makeInMemoryEditStore(),
            photoAnalysisCoordinator: coordinator
        )
        viewModel.openImage(url: url)
        try await waitUntil("the image to load") { viewModel.sourceImage != nil }

        let component = MaskComponent(source: .semantic(SemanticMaskDefinition(target: .person)))
        let layerID = UUID()
        viewModel.updateDocument {
            $0.localAdjustments.append(LocalAdjustmentLayer(
                id: layerID, name: "Person", components: [component]
            ))
        }
        viewModel.selectMaskLayer(layerID)
        viewModel.selectMaskComponent(component.id, in: layerID)
        await provider.clearRequestedKinds()
        let epochBefore = viewModel.maskingState.maskResolveEpoch

        viewModel.retryMaskAnalysis()
        try await waitUntilAsync("retry to warm the person signals") {
            let requested = await provider.requestedKinds
            return requested.contains(.face) && requested.contains(.foregroundInstance(0))
        }
        XCTAssertEqual(viewModel.maskingState.maskResolveEpoch, epochBefore + 1)
    }

    // MARK: - Epoch unit

    func testResolveEpochIncrements() {
        let state = MaskInteractionState()
        XCTAssertEqual(state.maskResolveEpoch, 0)
        state.requestMaskReResolve()
        XCTAssertEqual(state.maskResolveEpoch, 1)
    }

    // MARK: - Helpers

    private func makeSource(named name: String) throws -> ImageSource {
        let url = try Fixtures.writeGradientPNG(width: 64, height: 48, named: name, in: tempDirectory)
        return ImageSource(url: url, nativeExtent: CGSize(width: 64, height: 48))
    }

    private func waitUntil(
        _ description: String, timeout: TimeInterval = 10,
        _ condition: @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline { return XCTFail("timed out waiting for \(description)") }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    private func waitUntilAsync(
        _ description: String, timeout: TimeInterval = 10,
        _ condition: @Sendable () async -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while await !condition() {
            if Date() > deadline { return XCTFail("timed out waiting for \(description)") }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}

/// Mimics the real provider's cache-only person gate: `.person` throws
/// `personNotApplicable` unless face or foregroundInstance(0) was served first **at preview
/// quality**, mirroring the exact-quality store lookup. Every other kind is served with an
/// actionable canned mask through the shared store.
private actor GatedPersonStubProvider: SemanticMaskProviding {
    private let store: MaskStore
    private(set) var requestedKinds: [SemanticMaskKind] = []
    private var servedFacePreview = false
    private var servedForegroundPreview = false
    var failFace = false

    init(store: MaskStore) {
        self.store = store
    }

    func setFailFace(_ value: Bool) {
        failFace = value
    }

    func clearRequestedKinds() {
        requestedKinds.removeAll()
    }

    func mask(
        for kind: SemanticMaskKind, image: AnalysisImage, quality: MaskQuality
    ) async throws -> RegionMask {
        requestedKinds.append(kind)
        switch kind {
        case .face, .faceInstance:
            if failFace { throw VisionSemanticMaskError.noFaceDetected }
            if quality == .preview { servedFacePreview = true }
        case .foregroundInstance:
            if quality == .preview { servedForegroundPreview = true }
        case .person:
            guard servedFacePreview || servedForegroundPreview else {
                throw VisionSemanticMaskError.personNotApplicable
            }
        case .foreground, .subject, .background, .unknown:
            break
        }
        // Half-covered at full confidence: actionable under MaskPresentationPolicy.
        let size = PixelDimensions(width: 8, height: 8)
        let pixels = try NormalizedMask(
            size: size, values: (0..<64).map { $0 % 2 == 0 ? Float(1) : Float(0) }
        )
        let assetID = image.assetID ?? PhotoAnalysisCoordinator.assetID(for: image.source)
        let key = MaskCacheKey(
            assetID: assetID,
            sourceFingerprint: PhotoAnalysisCoordinator.sourceFingerprint(for: image.source),
            kind: kind, quality: quality, providerVersion: "warming-stub-1"
        )
        let reference = try await store.store(pixels, for: key, quality: quality)
        return RegionMask(
            kind: kind, bounds: NormalizedRect(x: 0, y: 0, width: 1, height: 1),
            quality: quality, reference: reference, confidence: 1, coverage: pixels.coverage
        )
    }
}

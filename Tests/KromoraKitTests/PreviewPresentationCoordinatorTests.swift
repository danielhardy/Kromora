import CoreGraphics
import CoreImage
import Foundation
import XCTest

@testable import KromoraKit

@MainActor
final class PreviewPresentationCoordinatorTests: TempDirectoryTestCase {
    func testGenerationFencesAreIndependentAcrossPresentationSurfaces() throws {
        let coordinator = makeCoordinator()

        coordinator.advanceDisplayRevision()
        coordinator.advanceDisplayRevision()
        coordinator.advanceComparisonRevision()

        XCTAssertEqual(coordinator.displayRevision, 2)
        XCTAssertEqual(coordinator.comparisonRevision, 1)
        coordinator.resetForSource()
        XCTAssertEqual(coordinator.displayRevision, 3)
        XCTAssertEqual(coordinator.comparisonRevision, 2)
    }

    func testResolutionPlannerStateIsIndependentAndResettable() throws {
        let coordinator = makeCoordinator()
        let document = EditDocument()
        var navigation = CanvasNavigation()
        navigation.toggleFitAndRememberedZoom()
        let zoomed = coordinator.plan(
            for: document,
            nativeExtent: CGSize(width: 4000, height: 3000),
            viewportSize: CGSize(width: 1000, height: 1000),
            surface: .mainPreview,
            navigation: navigation
        )
        navigation.fit()
        let comparisonFit = coordinator.plan(
            for: document,
            nativeExtent: CGSize(width: 4000, height: 3000),
            viewportSize: CGSize(width: 1000, height: 1000),
            surface: .comparisonBaseline,
            navigation: navigation
        )
        XCTAssertGreaterThan(zoomed.level, comparisonFit.level)

        coordinator.resetPlanners()
        let resetMain = coordinator.plan(
            for: document,
            nativeExtent: CGSize(width: 4000, height: 3000),
            viewportSize: CGSize(width: 1000, height: 1000),
            surface: .mainPreview,
            navigation: navigation
        )
        XCTAssertEqual(resetMain, comparisonFit)
    }

    func testCacheKeyDerivesEveryPresentationIdentityComponent() throws {
        let coordinator = makeCoordinator()
        let source = ImageSource(
            backing: .data(Data("cache-key-source".utf8)),
            kind: .standard,
            nativeExtent: CGSize(width: 32, height: 24)
        )
        var document = EditDocument()
        document.adjustments = [.exposure(ev: 0.4)]
        let request = RenderRequest(
            source: source,
            document: document,
            targetSize: CGSize(width: 32, height: 24),
            quality: .preview,
            space: .displayP3
        )

        let key = coordinator.cacheKey(for: request)

        XCTAssertEqual(key.identity, source.cacheIdentity)
        XCTAssertEqual(key.documentHash, document.editHash)
        XCTAssertEqual(key.lookFingerprint, "unresolved")
        XCTAssertEqual(key.targetSizeBucket, String(PreviewDiskCache.canonicalLongEdge))
        XCTAssertEqual(key.space, WorkingSpace.displayP3.rawValue)
        XCTAssertEqual(key.pipelineVersion, RenderPipeline.cacheVersion)
    }

    func testCanonicalWritesRequirePreviewQualityAndACompleteFrame() async throws {
        let coordinator = makeCoordinator()
        let source = ImageSource(
            backing: .data(Data("canonical-write-source".utf8)),
            kind: .standard,
            nativeExtent: CGSize(width: 32, height: 24)
        )
        let image = CIImage(cgImage: try Fixtures.makeCGImage(width: 32, height: 24))
        let completeRequest = RenderRequest(
            source: source, document: EditDocument(), quality: .preview
        )
        let key = coordinator.cacheKey(for: completeRequest)
        coordinator.writeCanonical(image, for: completeRequest)
        try await waitUntil("canonical cache write") { coordinator.cache.contains(key) }

        coordinator.cache.invalidateAll()
        let thumbnailRequest = RenderRequest(
            source: source, document: EditDocument(), quality: .thumbnail
        )
        coordinator.writeCanonical(image, for: thumbnailRequest)
        let roiRequest = RenderRequest(
            source: source,
            document: EditDocument(),
            sourceROI: CGRect(x: 1, y: 1, width: 10, height: 10),
            quality: .preview
        )
        coordinator.writeCanonical(image, for: roiRequest)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertFalse(coordinator.cache.contains(key))
    }

    private func makeCoordinator() -> PreviewPresentationCoordinator {
        let directory = tempDirectory.appendingPathComponent("preview-cache-\(UUID().uuidString)")
        return PreviewPresentationCoordinator(
            cache: PreviewDiskCache(directory: directory, capBytes: 10_000_000)
        )
    }

    private func waitUntil(
        _ description: String,
        timeout: Duration = .seconds(5),
        _ condition: @escaping @MainActor () -> Bool
    ) async throws {
        let deadline = ContinuousClock.now + timeout
        while !condition() {
            if ContinuousClock.now >= deadline {
                throw TestSynchronizationError.timedOut(description, "condition did not settle")
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}

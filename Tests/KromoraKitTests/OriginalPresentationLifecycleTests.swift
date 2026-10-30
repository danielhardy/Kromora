import AppKit
import MetalKit
import XCTest

@testable import KromoraKit

/// KRMA-1141: the side-by-side Original pane must present the current photo's baseline without a
/// focus transition or other user action. These tests drive the real `AppViewModel` and surfaces
/// (fake render engine, no `NSWindow` or display) through Edit entry, photo switching, and Edit
/// re-entry, and model defocus/refocus with the same window notifications the Metal view observes.
@MainActor
final class OriginalPresentationLifecycleTests: TempDirectoryTestCase {

    private final class TrackingMTKView: MTKView {
        private(set) var redrawRequestCount = 0

        override func setNeedsDisplay(_ rect: NSRect) {
            redrawRequestCount += 1
            super.setNeedsDisplay(rect)
        }
    }

    private func makeViewModel(fake: FakeRenderEngine) -> AppViewModel {
        let suite = "KromoraOriginalLifecycleTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return makeAppViewModel(
            engine: fake, editStore: makeInMemoryEditStore(), preferences: defaults)
    }

    private func waitUntil(
        _ description: String,
        _ condition: @escaping @MainActor () async -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(5)
        while !(await condition()) {
            if Date() > deadline { return XCTFail("timed out waiting for \(description)") }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    private func open(_ viewModel: AppViewModel, named name: String) async throws -> URL {
        let url = try Fixtures.writeGradientPNG(
            width: 16, height: 12, named: name, in: tempDirectory)
        viewModel.openImage(url: url)
        try await waitUntil("the \(name) source") {
            viewModel.sourceName == url.lastPathComponent && viewModel.sourceImage != nil
        }
        return url
    }

    private func waitForRedrawCount(_ view: TrackingMTKView, atLeast expected: Int) async throws {
        try await waitUntil("a redraw request") { view.redrawRequestCount >= expected }
    }

    /// Entry, photo switch, and re-entry each end with the current photo's baseline presented, and
    /// no step depends on a window or application activation event (none exists here).
    func testOriginalPresentsThroughEntrySwitchAndReentryWithoutActivation() async throws {
        let fake = FakeRenderEngine()
        let viewModel = makeViewModel(fake: fake)
        viewModel.isSideBySide = true

        let first = try await open(viewModel, named: "lifecycle-first.png")
        try await waitUntil("the first photo's Original") {
            viewModel.isSideBySideVisible
                && viewModel.previewSurface.image != nil
                && viewModel.originalPreviewSurface.image != nil
        }
        let firstSource = try XCTUnwrap(viewModel.sourceURL)

        let second = try await open(viewModel, named: "lifecycle-second.png")
        let secondSource = try XCTUnwrap(viewModel.sourceURL)
        XCTAssertNotEqual(firstSource, secondSource)
        try await waitUntil("the second photo's Original") {
            viewModel.originalPreviewSurface.image != nil
                && viewModel.previewSurface.image != nil
        }
        var requests = await fake.previewRequests
        XCTAssertTrue(requests.contains {
            $0.source?.backing == .url(secondSource) && $0.document == EditDocument()
        }, "the second photo's baseline must have been rendered")
        XCTAssertEqual(viewModel.sourceName, second.lastPathComponent)

        // Leaving and re-entering Edit on the first photo: the pane is cleared for the departing
        // source and repopulated for the returning one.
        viewModel.openImage(url: first)
        XCTAssertNil(viewModel.originalPreviewSurface.image, "no stale baseline across the switch")
        try await waitUntil("the re-entered first photo's Original") {
            viewModel.sourceName == first.lastPathComponent
                && viewModel.originalPreviewSurface.image != nil
                && viewModel.previewSurface.image != nil
        }
        requests = await fake.previewRequests
        let reentrySource = try XCTUnwrap(viewModel.sourceURL)
        XCTAssertTrue(requests.contains {
            $0.source?.backing == .url(reentrySource) && $0.document == EditDocument()
        })
    }

    /// The Adjusted render is held (a busy editor lane) while the Original is pending; the
    /// Original must still publish once the lane runs, and the Adjusted pane must publish too.
    func testOriginalAndAdjustedBothPublishWhileRendersAreGated() async throws {
        let fake = FakeRenderEngine()
        let viewModel = makeViewModel(fake: fake)
        viewModel.isSideBySide = true
        await fake.gatePreviews()

        let url = try Fixtures.writeGradientPNG(
            width: 16, height: 12, named: "gated.png", in: tempDirectory)
        viewModel.openImage(url: url)
        try await waitUntil("a gated preview request") { await fake.previewRequests.count >= 1 }
        XCTAssertNil(viewModel.originalPreviewSurface.image)

        await fake.releasePreviews()
        try await waitUntil("both panes") {
            viewModel.previewSurface.image != nil && viewModel.originalPreviewSurface.image != nil
        }
    }

    /// Single-photo mode never schedules a baseline for the Original pane.
    func testSinglePhotoModeDoesNotRenderAnOriginal() async throws {
        let fake = FakeRenderEngine()
        let viewModel = makeViewModel(fake: fake)
        viewModel.isSideBySide = false
        _ = try await open(viewModel, named: "single.png")
        try await waitUntil("the adjusted preview") { viewModel.previewSurface.image != nil }
        XCTAssertNil(viewModel.originalPreviewSurface.image)
    }

    /// An Original published while the window is defocused is already held by the surface, and
    /// the refocus (key) notification repaints it without another publication.
    func testRefocusRepaintsAnOriginalPublishedWhileDefocused() async throws {
        let surface = PreviewSurface()
        surface.attachPresentationLifecycle()
        let view = TrackingMTKView(frame: CGRect(x: 0, y: 0, width: 32, height: 24), device: nil)
        surface.attachDisplayView(view)
        let coordinator = PreviewSurfaceView.Coordinator()
        coordinator.view = view
        coordinator.startDisplayObservation()
        defer { coordinator.stopDisplayObservation() }

        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: nil)
        let baseline = view.redrawRequestCount

        // The defocused draw is skipped repeatedly until retries are suppressed.
        for _ in 0..<4 { coordinator.handleSkippedDrawable(revision: 3) }
        try await Task.sleep(for: .milliseconds(100))
        let suppressed = view.redrawRequestCount

        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: nil)
        try await waitForRedrawCount(view, atLeast: max(suppressed, baseline) + 1)
        // Retries are re-armed: the next skip schedules a fresh invalidation again.
        let afterRefocus = view.redrawRequestCount
        coordinator.handleSkippedDrawable(revision: 3)
        try await waitForRedrawCount(view, atLeast: afterRefocus + 1)
    }
}

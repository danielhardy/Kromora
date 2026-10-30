import AppKit
import MetalKit
import SwiftUI
import XCTest

@testable import KromoraKit

/// KRMA-1142: Original presentation through a real `NSWindow` hosting `ContentView`, generated
/// fixtures only. A pane counts as presented when its surface holds an image and has no pending
/// display revision, which only the drawable command-buffer completion (`markPresentationSucceeded`)
/// clears. The tests record, rather than assume, whether presentation happens while the window is
/// not key, and require it once the window regains key status with no other action.
@MainActor
final class OriginalPresentationWindowTests: TempDirectoryTestCase {
    private struct Fixture {
        let window: NSWindow
        let viewModel: AppViewModel
        let fake: FakeRenderEngine
    }

    private func makeFixture() async throws -> Fixture {
        guard MTLCreateSystemDefaultDevice() != nil else { throw XCTSkip("Metal is unavailable") }
        _ = NSApplication.shared
        for name in ["a.png", "b.png"] {
            try Fixtures.writeGradientPNG(width: 16, height: 12, named: name, in: tempDirectory)
        }
        let fake = FakeRenderEngine()
        let suite = "KromoraOriginalWindowTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let viewModel = makeAppViewModel(
            engine: fake, editStore: makeInMemoryEditStore(), preferences: defaults)
        viewModel.isSideBySide = true
        viewModel.collection.loadFromFolder(tempDirectory)
        await viewModel.collection.scanCompletion()
        // The generated fixture folder must be exactly what the app opened.
        XCTAssertEqual(viewModel.collection.items.count, 2)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 760),
            styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let hosting = NSHostingView(rootView: ContentView(viewModel: viewModel))
        window.contentView = hosting
        hosting.frame = window.contentView?.bounds ?? .zero
        window.makeKeyAndOrderFront(nil)
        return Fixture(window: window, viewModel: viewModel, fake: fake)
    }

    private func waitUntil(
        _ description: String, timeout: TimeInterval = 8,
        _ condition: @escaping @MainActor () async -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !(await condition()) {
            if Date() > deadline { return XCTFail("timed out waiting for \(description)") }
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    private func isPresented(_ surface: PreviewSurface) -> Bool {
        surface.image != nil && surface.pendingDisplayRevision() == nil
    }

    private func bothPanesPresented(_ viewModel: AppViewModel) -> Bool {
        isPresented(viewModel.previewSurface) && isPresented(viewModel.originalPreviewSurface)
    }

    private func enterEdit(_ viewModel: AppViewModel, index: Int) async throws {
        viewModel.collection.setSelection(at: index)
        XCTAssertTrue(viewModel.navigate(to: .edit))
        let expected = viewModel.collection.items[index].url?.lastPathComponent ?? ""
        try await waitUntil("Edit on \(expected)") {
            viewModel.sourceName == expected && viewModel.isSideBySideVisible
        }
    }

    /// Mirrors the user report: the Original render is pending while the window loses key status.
    func testOriginalReachesDrawableAfterRefocusWithoutAnotherAction() async throws {
        let f = try await makeFixture()
        defer { f.window.close() }
        await f.fake.gatePreviews()

        try await enterEdit(f.viewModel, index: 0)
        try await waitUntil("a gated render request") { await f.fake.previewRequests.count >= 1 }
        XCTAssertNil(f.viewModel.originalPreviewSurface.image)

        // Defocus while the render is pending, then let the renders complete.
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: f.window)
        f.window.orderBack(nil)
        await f.fake.releasePreviews()
        try await waitUntil("published images") {
            f.viewModel.originalPreviewSurface.image != nil && f.viewModel.previewSurface.image != nil
        }
        try await Task.sleep(for: .milliseconds(400))
        let originalWhileInactive = isPresented(f.viewModel.originalPreviewSurface)
        let adjustedWhileInactive = isPresented(f.viewModel.previewSurface)
        print(
            "KRMA-1142 inactive: key=\(f.window.isKeyWindow) original presented=\(originalWhileInactive) adjusted presented=\(adjustedWhileInactive)"
        )

        // Regain key status; nothing else happens.
        f.window.makeKeyAndOrderFront(nil)
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: f.window)
        try await waitUntil("both panes presented after refocus") {
            self.bothPanesPresented(f.viewModel)
        }
    }

    /// Switch photos, return to Library, re-enter Edit: neither pane keeps the departed photo, and
    /// the other comparison modes remain usable.
    func testPanesFollowSwitchAndReentryAndOtherModesStayUsable() async throws {
        let f = try await makeFixture()
        defer { f.window.close() }

        try await enterEdit(f.viewModel, index: 0)
        try await waitUntil("first photo presented") { self.bothPanesPresented(f.viewModel) }

        try await enterEdit(f.viewModel, index: 1)
        let second = try XCTUnwrap(f.viewModel.sourceURL)
        try await waitUntil("second photo presented") { self.bothPanesPresented(f.viewModel) }
        var requests = await f.fake.previewRequests
        XCTAssertTrue(requests.contains {
            $0.source?.backing == .url(second) && $0.document == EditDocument()
        })

        XCTAssertTrue(f.viewModel.navigate(to: .grid))
        f.viewModel.collection.setSelection(at: 0)
        XCTAssertTrue(f.viewModel.navigate(to: .edit))
        try await waitUntil("re-entered first photo") {
            f.viewModel.sourceName == "a.png" && self.bothPanesPresented(f.viewModel)
        }
        let first = try XCTUnwrap(f.viewModel.sourceURL)
        XCTAssertNotEqual(first, second)
        requests = await f.fake.previewRequests
        XCTAssertTrue(requests.contains {
            $0.source?.backing == .url(first) && $0.document == EditDocument()
        })

        // Other comparison modes: turning side-by-side off leaves the Adjusted pane presented.
        f.viewModel.isSideBySide = false
        try await waitUntil("single-pane Adjusted") { self.isPresented(f.viewModel.previewSurface) }
        f.viewModel.isSideBySide = true
        try await waitUntil("side-by-side restored") { self.bothPanesPresented(f.viewModel) }
    }
}

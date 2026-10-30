import AppKit
import CoreImage
import MetalKit
import SwiftUI
import XCTest

@testable import KromoraKit

/// KRMA-1142: Original presentation through a real `NSWindow` hosting `ContentView`, generated
/// fixtures only. Presentation is judged by what Metal reports for the submitted drawable
/// (`PreviewSurface.onDrawableReport`), never by command-buffer completion, which only clears the
/// pending display revision. Each generated photo renders as a distinct solid color, so a pane
/// showing the wrong photo fails on pixels, not just on request bookkeeping.
@MainActor
final class OriginalPresentationWindowTests: TempDirectoryTestCase {
    private struct Fixture {
        let window: NSWindow
        let viewModel: AppViewModel
        let fake: FakeRenderEngine
        let reports: DrawableReports
    }

    /// Drawable reports per pane, recorded together with the pane's pixels at report time.
    @MainActor
    private final class DrawableReports {
        struct Report { let revision: UInt64; let displayed: Bool; let dominant: Channel? }
        var original: [Report] = []
        var adjusted: [Report] = []
    }

    private enum Channel { case red, blue }

    private static let redPhoto = FakeRenderEngine.solidImage(red: 1, green: 0, blue: 0)!
    private static let bluePhoto = FakeRenderEngine.solidImage(red: 0, green: 0, blue: 1)!

    private static func dominantChannel(of image: CIImage?) -> Channel? {
        guard let image else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = CIContext(options: [.useSoftwareRenderer: true])
        context.render(
            image, toBitmap: &pixel, rowBytes: 4,
            bounds: CGRect(x: image.extent.midX, y: image.extent.midY, width: 1, height: 1),
            format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
        if pixel[0] > 128, pixel[2] < 128 { return .red }
        if pixel[2] > 128, pixel[0] < 128 { return .blue }
        return nil
    }

    private func makeFixture() async throws -> Fixture {
        guard MTLCreateSystemDefaultDevice() != nil else { throw XCTSkip("Metal is unavailable") }
        _ = NSApplication.shared
        for name in ["a.png", "b.png"] {
            try Fixtures.writeGradientPNG(width: 16, height: 12, named: name, in: tempDirectory)
        }
        let fake = FakeRenderEngine()
        await fake.setPreviewResult(Self.redPhoto, for: tempDirectory.appendingPathComponent("a.png"))
        await fake.setPreviewResult(Self.bluePhoto, for: tempDirectory.appendingPathComponent("b.png"))
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
        let reports = DrawableReports()
        viewModel.originalPreviewSurface.onDrawableReport = { [weak viewModel] revision, displayed in
            guard let surface = viewModel?.originalPreviewSurface else { return }
            reports.original.append(
                .init(revision: revision, displayed: displayed, dominant: Self.dominantChannel(of: surface.image)))
        }
        viewModel.previewSurface.onDrawableReport = { [weak viewModel] revision, displayed in
            guard let surface = viewModel?.previewSurface else { return }
            reports.adjusted.append(
                .init(revision: revision, displayed: displayed, dominant: Self.dominantChannel(of: surface.image)))
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        return Fixture(window: window, viewModel: viewModel, fake: fake, reports: reports)
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

    private func enterEdit(_ viewModel: AppViewModel, index: Int) async throws {
        viewModel.collection.setSelection(at: index)
        XCTAssertTrue(viewModel.navigate(to: .edit))
        let expected = viewModel.collection.items[index].url?.lastPathComponent ?? ""
        try await waitUntil("Edit on \(expected)") {
            viewModel.sourceName == expected && viewModel.isSideBySideVisible
        }
    }

    private func displayed(_ reports: [DrawableReports.Report], _ channel: Channel) -> Bool {
        reports.contains { $0.displayed && $0.dominant == channel }
    }

    /// Mirrors the user report: the Original render is still pending (held in the engine) while the
    /// window genuinely loses key status, then the window regains key with no other action.
    func testOriginalReachesDrawableAcrossRealKeyLossAndRegain() async throws {
        let f = try await makeFixture()
        defer { f.window.close() }
        for _ in 0..<100 where !f.window.isKeyWindow { try await Task.sleep(for: .milliseconds(20)) }
        guard f.window.isKeyWindow else { throw XCTSkip("native key status unavailable in this session") }

        var transitions: [String] = []
        let center = NotificationCenter.default
        let tokens = [NSWindow.didResignKeyNotification, NSWindow.didBecomeKeyNotification].map { name in
            center.addObserver(forName: name, object: f.window, queue: .main) { _ in
                MainActor.assumeIsolated { transitions.append(name.rawValue) }
            }
        }
        defer { tokens.forEach(center.removeObserver) }

        // Hold every baseline request; release them one at a time so the order is deterministic.
        await f.fake.gatePreviews()
        try await enterEdit(f.viewModel, index: 0)
        try await waitUntil("Adjusted request") { await f.fake.previewRequests.count >= 1 }
        await f.fake.releaseNextPreview()
        try await waitUntil("Adjusted drawable report") { !f.reports.adjusted.isEmpty }
        // A drawable Metal reports with a zero presented time was skipped (no scan-out in this
        // session). Command-buffer completion is not visible pixels, so report that, don't pass.
        for _ in 0..<50 where !f.reports.adjusted.contains(where: \.displayed) {
            try await Task.sleep(for: .milliseconds(20))
        }
        guard f.reports.adjusted.contains(where: \.displayed) else {
            throw XCTSkip("drawables are skipped in this session (presentedTime == 0); native presentation unavailable")
        }
        XCTAssertTrue(displayed(f.reports.adjusted, .red), "Adjusted pane must present photo a")

        // The Original request is scheduled only after the Adjusted frame is presented.
        try await waitUntil("Original request parked") { await f.fake.previewRequests.count >= 2 }
        XCTAssertNil(f.viewModel.originalPreviewSurface.image, "Original must still be pending")

        // Real key loss while the Original render is pending.
        let other = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 120), styleMask: [.titled],
            backing: .buffered, defer: false)
        other.isReleasedWhenClosed = false
        defer { other.close() }
        other.makeKeyAndOrderFront(nil)
        try await waitUntil("key loss", timeout: 3) { !f.window.isKeyWindow }
        guard !f.window.isKeyWindow else { throw XCTSkip("could not move key status away from the window") }
        XCTAssertTrue(transitions.contains(NSWindow.didResignKeyNotification.rawValue))

        await f.fake.releasePreviews()
        try await waitUntil("Original image published") { f.viewModel.originalPreviewSurface.image != nil }
        try await Task.sleep(for: .milliseconds(500))
        let reportedWhileInactive = f.reports.original
        print("KRMA-1142 inactive: key=\(f.window.isKeyWindow) original reports=\(reportedWhileInactive.map { "displayed=\($0.displayed)" })")

        // Regain key; nothing else happens.
        f.window.makeKeyAndOrderFront(nil)
        try await waitUntil("key regain", timeout: 3) { f.window.isKeyWindow }
        XCTAssertTrue(transitions.contains(NSWindow.didBecomeKeyNotification.rawValue))
        try await waitUntil("Original drawable displayed photo a after refocus") {
            self.displayed(f.reports.original, .red)
        }
        XCTAssertTrue(displayed(f.reports.adjusted, .red))
        XCTAssertFalse(f.reports.original.contains { $0.displayed && $0.dominant == .blue })
    }

    /// Switch photos, return to Library, re-enter Edit: neither pane keeps the departed photo, and
    /// the other comparison modes remain usable.
    func testPanesFollowSwitchAndReentryAndOtherModesStayUsable() async throws {
        let f = try await makeFixture()
        defer { f.window.close() }

        func paneColors() -> (adjusted: Channel?, original: Channel?) {
            (Self.dominantChannel(of: f.viewModel.previewSurface.image),
             Self.dominantChannel(of: f.viewModel.originalPreviewSurface.image))
        }

        try await enterEdit(f.viewModel, index: 0)
        try await waitUntil("photo a in both panes") { paneColors() == (.red, .red) }

        try await enterEdit(f.viewModel, index: 1)
        try await waitUntil("photo b in both panes") { paneColors() == (.blue, .blue) }

        XCTAssertTrue(f.viewModel.navigate(to: .grid))
        f.viewModel.collection.setSelection(at: 0)
        XCTAssertTrue(f.viewModel.navigate(to: .edit))
        try await waitUntil("re-entered photo a in both panes") {
            f.viewModel.sourceName == "a.png" && paneColors() == (.red, .red)
        }

        // Other comparison modes: side-by-side off keeps Adjusted on photo a; back on restores both.
        f.viewModel.isSideBySide = false
        try await waitUntil("single-pane Adjusted") { paneColors().adjusted == .red }
        f.viewModel.isSideBySide = true
        try await waitUntil("side-by-side restored") { paneColors() == (.red, .red) }
    }
}

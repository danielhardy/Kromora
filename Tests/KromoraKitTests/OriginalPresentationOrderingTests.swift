import CoreImage
import XCTest

@testable import KromoraKit

/// KRMA-1142: Original/Adjusted presentation policy across skipped and real drawables, with no
/// `NSWindow`, display, or key status. A drawable-managed surface (`attachPresentationLifecycle`)
/// waits for `markDrawablePresented`, so the test plays the compositor: a zero presented time is
/// the drawable Metal skips for a defocused or occluded window, a positive one is a real
/// presentation. Each generated photo renders as a distinct solid color, so a pane showing the
/// wrong photo fails on pixels, not only on request bookkeeping.
@MainActor
final class OriginalPresentationOrderingTests: TempDirectoryTestCase {
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

    private func makeViewModel(fake: FakeRenderEngine) async throws -> AppViewModel {
        for name in ["a.png", "b.png"] {
            try Fixtures.writeGradientPNG(width: 16, height: 12, named: name, in: tempDirectory)
        }
        await fake.setPreviewResult(Self.redPhoto, for: tempDirectory.appendingPathComponent("a.png"))
        await fake.setPreviewResult(Self.bluePhoto, for: tempDirectory.appendingPathComponent("b.png"))
        let suite = "KromoraOriginalOrderingTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let viewModel = makeAppViewModel(
            engine: fake, editStore: makeInMemoryEditStore(), preferences: defaults)
        viewModel.previewSurface.attachPresentationLifecycle()
        viewModel.originalPreviewSurface.attachPresentationLifecycle()
        viewModel.isSideBySide = true
        viewModel.collection.loadFromFolder(tempDirectory)
        await viewModel.collection.scanCompletion()
        // The generated fixture folder must be exactly what the app opened.
        XCTAssertEqual(viewModel.collection.items.count, 2)
        return viewModel
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

    private func paneColors(_ viewModel: AppViewModel) -> (adjusted: Channel?, original: Channel?) {
        (Self.dominantChannel(of: viewModel.previewSurface.image),
         Self.dominantChannel(of: viewModel.originalPreviewSurface.image))
    }

    /// While the window is defocused Metal skips every drawable. A skipped Adjusted drawable must
    /// stay pending (never confirmed as visible), the Original must still publish its pixels, and
    /// the first real presentation after regain confirms the Adjusted frame with no other action.
    func testSkippedDrawablesStayPendingAndRealPresentationConfirmsWithoutAnotherAction() async throws {
        let viewModel = try await makeViewModel(fake: FakeRenderEngine())
        let adjusted = viewModel.previewSurface
        let original = viewModel.originalPreviewSurface

        try await enterEdit(viewModel, index: 0)
        try await waitUntil("photo a in both panes") { self.paneColors(viewModel) == (.red, .red) }

        // Defocused: the compositor skips the drawable. It stays pending and the frame is kept.
        let adjustedRevision = try XCTUnwrap(adjusted.pendingPresentationRevision())
        XCTAssertTrue(adjusted.markDrawablePresented(revision: adjustedRevision, time: 0),
                      "a skipped drawable must ask for another draw")
        XCTAssertEqual(adjusted.pendingPresentationRevision(), adjustedRevision)
        XCTAssertTrue(adjusted.markDrawablePresented(revision: adjustedRevision, time: 0),
                      "still skipped, still pending: not a false presentation")
        XCTAssertEqual(paneColors(viewModel).adjusted, .red, "the pane keeps its frame while skipped")
        if let originalRevision = original.pendingPresentationRevision() {
            original.markDrawablePresented(revision: originalRevision, time: 0)
        }
        XCTAssertEqual(paneColors(viewModel).original, .red, "the Original keeps its pixels while skipped")

        // Regained: a real drawable confirms the Adjusted frame; the revision is consumed.
        XCTAssertFalse(adjusted.markDrawablePresented(revision: adjustedRevision, time: 1))
        XCTAssertFalse(adjusted.markDrawablePresented(revision: adjustedRevision, time: 0),
                       "a confirmed revision is no longer pending, so a late report cannot skip it")
        if let originalRevision = original.pendingPresentationRevision() {
            XCTAssertFalse(original.markDrawablePresented(revision: originalRevision, time: 1))
        }
        XCTAssertEqual(paneColors(viewModel).adjusted, .red)
        XCTAssertEqual(paneColors(viewModel).original, .red)
    }

    /// Switch photos, return to Library, re-enter Edit: neither pane keeps the departed photo, and
    /// the other comparison modes remain usable.
    func testPanesFollowSwitchAndReentryAndOtherModesStayUsable() async throws {
        let viewModel = try await makeViewModel(fake: FakeRenderEngine())

        try await enterEdit(viewModel, index: 0)
        try await waitUntil("photo a in both panes") { self.paneColors(viewModel) == (.red, .red) }

        try await enterEdit(viewModel, index: 1)
        try await waitUntil("photo b in both panes") { self.paneColors(viewModel) == (.blue, .blue) }

        XCTAssertTrue(viewModel.navigate(to: .grid))
        viewModel.collection.setSelection(at: 0)
        XCTAssertTrue(viewModel.navigate(to: .edit))
        try await waitUntil("re-entered photo a in both panes") {
            viewModel.sourceName == "a.png" && self.paneColors(viewModel) == (.red, .red)
        }

        // Side-by-side off keeps Adjusted on photo a; back on restores both.
        viewModel.isSideBySide = false
        try await waitUntil("single-pane Adjusted") { self.paneColors(viewModel).adjusted == .red }
        viewModel.isSideBySide = true
        try await waitUntil("side-by-side restored") { self.paneColors(viewModel) == (.red, .red) }
    }
}

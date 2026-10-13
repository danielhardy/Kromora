import XCTest
import SwiftUI
import AppKit
import CoreImage
@testable import KromoraKit

/// Whether `KeyboardSurface`'s scene values resolve through `@FocusedValue` in a real window.
/// `KromoraCommands` reads the same keys, so a nil here would leave every Photo/Tools item disabled.
@MainActor
final class FocusedSceneValueTests: TempDirectoryTestCase {
    @Observable @MainActor fileprivate final class Seen {
        var router: KeyboardCommandRouter?
        var context: KeyboardContext?
    }

    private struct Reader: View {
        @FocusedValue(\.keyboardRouter) private var router
        @FocusedValue(\.keyboardContext) private var context
        let seen: Seen
        var body: some View {
            Color.clear.onChange(of: router == nil, initial: true) { _, _ in seen.router = router }
                .onChange(of: context, initial: true) { _, new in seen.context = new }
        }
    }

    private struct Root: View {
        let router: KeyboardCommandRouter
        let viewModel: AppViewModel
        let seen: Seen
        var body: some View {
            VStack {
                Color.clear.frame(width: 20, height: 20)
                    .keyboardSurface(router: router, viewModel: viewModel)
                Reader(seen: seen)
            }
        }
    }

    func testSurfacePublishesRouterAndContextToTheScene() async throws {
        _ = NSApplication.shared
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())
        let router = KeyboardCommandRouter(viewModel: viewModel)
        let seen = Seen()
        let host = NSHostingView(rootView: Root(router: router, viewModel: viewModel, seen: seen))
        host.frame = NSRect(x: 0, y: 0, width: 100, height: 100)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        try await Task.sleep(for: .milliseconds(500))
        defer { window.close() }
        XCTAssertTrue(seen.router === router)
        XCTAssertEqual(seen.context?.hasImage, false)

        // Menu enablement follows the editor: opening a photo republishes the context.
        viewModel.sourceImage = CIImage(color: .gray).cropped(to: CGRect(x: 0, y: 0, width: 8, height: 8))
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(seen.context?.hasImage, true)
        XCTAssertTrue(seen.context.map(KeyboardCommand.toggleCrop.isAvailable) ?? false)
    }
}

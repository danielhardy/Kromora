import AppKit
import SwiftUI
import XCTest

@testable import KromoraKit

/// Reading the library projection used to write an `@Observable` cache property on every
/// hit. Hosting the library and applying a second update must return, and the grid body
/// must not keep evaluating inside that transaction.
@MainActor
final class LibraryChromeLayoutTests: TempDirectoryTestCase {
    func testLibraryChromeSecondUpdateFinishes() async throws {
        let sourceFolder = tempDirectory.appendingPathComponent("source", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceFolder, withIntermediateDirectories: true)
        _ = try Fixtures.writeJPEG(width: 32, height: 24, orientation: 1, named: "a.jpg", in: sourceFolder)
        _ = try Fixtures.writeJPEG(width: 48, height: 24, orientation: 1, named: "b.jpg", in: sourceFolder)

        let viewModel = makeAppViewModel(engine: FakeRenderEngine())
        viewModel.collection.loadFromFolder(sourceFolder)
        await viewModel.collection.scanCompletion()
        XCTAssertTrue(viewModel.navigate(to: .grid))
        viewModel.statusMessage = "Recovered interrupted writes from the previous library session."

        let hosting = NSHostingView(rootView: ContentView(viewModel: viewModel))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 720),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        hosting.frame = window.contentView?.bounds ?? .zero

        window.layoutIfNeeded()
        window.displayIfNeeded()

        viewModel.statusMessage = "Recovered interrupted writes from the previous library session."
        if let item = viewModel.collection.items.first {
            item.setOriginalThumbnail(NSImage(size: NSSize(width: 40, height: 30)))
        }

        RenderDiagnostics.reset()
        let second = Date()
        Self.pumpMainRunLoop()
        window.layoutIfNeeded()
        window.displayIfNeeded()
        XCTAssertLessThan(Date().timeIntervalSince(second), 3, "second library update")
        XCTAssertLessThan(
            RenderDiagnostics.snapshot.gridBodyEvaluations, 40,
            "library grid body kept invalidating inside one SwiftUI transaction"
        )
    }

    /// SwiftUI applies the published change on the main run loop. `RunLoop.run` is unavailable
    /// directly inside an async test.
    private static func pumpMainRunLoop() {
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
    }
}

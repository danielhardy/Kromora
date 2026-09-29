import AppKit
import SwiftUI
import XCTest

@testable import KromoraKit

/// Reading the library projection used to write an `@Observable` cache property on every
/// hit. Hosting the library and applying a second update must return, and the grid body
/// must not keep evaluating inside that transaction.
@MainActor
final class LibraryChromeLayoutTests: TempDirectoryTestCase {
    func testEditorKeepsContentBelowTheNativeWindowToolbar() {
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())
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
        Self.pumpMainRunLoop()

        XCTAssertFalse(window.styleMask.contains(.fullSizeContentView))
        XCTAssertFalse(window.titlebarAppearsTransparent)
        XCTAssertNotEqual(window.titlebarSeparatorStyle, .none)
        XCTAssertNotNil(window.toolbar)
    }

    func testInspectorReservesItsColumnAndKeepsItsToggleAtTheToolbarEdge() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let contentViewURL = packageRoot
            .appendingPathComponent("Sources/KromoraKit/Views/ContentView.swift")
        let contentView = try String(
            contentsOf: contentViewURL,
            encoding: .utf8
        )

        XCTAssertFalse(
            contentView.contains(".ignoresSafeArea(.container, edges: .trailing)"),
            "the preview must stay inside the width left by the inspector"
        )
        let toolbar = try XCTUnwrap(contentView.range(of: ".toolbar {"))
        let toolbarContents = toolbar.upperBound..<contentView.endIndex
        let transferButton = try XCTUnwrap(
            contentView.range(of: "transferToolbarPill", range: toolbarContents)
        )
        let inspectorButton = try XCTUnwrap(
            contentView.range(
                of: "inspectorToolbarButton",
                range: transferButton.upperBound..<contentView.endIndex
            )
        )
        XCTAssertLessThan(transferButton.lowerBound, inspectorButton.lowerBound)
        XCTAssertTrue(
            contentView[transferButton.upperBound..<inspectorButton.lowerBound]
                .contains("ToolbarSpacer(.fixed)"),
            "the inspector toggle is separated from the other toolbar controls"
        )
        XCTAssertTrue(
            contentView.contains(".inspectorColumnWidth(min: 240, ideal: 280, max: 360)")
        )
    }

    func testReturningFromEditRestoresTheSameLibraryViewportWidth() async throws {
        let sourceFolder = tempDirectory.appendingPathComponent("source", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceFolder, withIntermediateDirectories: true)
        try Fixtures.writeJPEG(
            width: 32, height: 24, orientation: 1, named: "photo.jpg", in: sourceFolder
        )

        let viewModel = makeAppViewModel(engine: FakeRenderEngine())
        viewModel.collection.loadFromFolder(sourceFolder)
        await viewModel.collection.scanCompletion()
        XCTAssertTrue(viewModel.navigate(to: .grid))
        viewModel.collection.select(at: 0)

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
        Self.pumpMainRunLoop()

        let initialWidth = try XCTUnwrap(Self.libraryScrollView(in: hosting)).frame.width
        viewModel.isInspectorPresented = true
        XCTAssertTrue(viewModel.navigate(to: .edit))
        Self.pumpMainRunLoop()

        XCTAssertTrue(viewModel.navigate(to: .grid))
        window.layoutIfNeeded()
        window.displayIfNeeded()
        Self.pumpMainRunLoop(for: 0.1)

        let transitionWidth = try XCTUnwrap(Self.libraryScrollView(in: hosting)).frame.width
        XCTAssertEqual(
            transitionWidth, initialWidth, accuracy: 1,
            "the grid must not pass through an inspector-constrained width"
        )

        Self.pumpMainRunLoop()
        let returnedWidth = try XCTUnwrap(Self.libraryScrollView(in: hosting)).frame.width
        XCTAssertEqual(returnedWidth, initialWidth, accuracy: 1)
        XCTAssertEqual(viewModel.collection.selection.activeID, viewModel.collection.items[0].id)
    }

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
    private static func pumpMainRunLoop(for duration: TimeInterval = 0.4) {
        RunLoop.current.run(until: Date().addingTimeInterval(duration))
    }

    private static func libraryScrollView(in view: NSView) -> NSScrollView? {
        if let scrollView = view as? NSScrollView { return scrollView }
        return view.subviews
            .compactMap(libraryScrollView(in:))
            .max { $0.frame.width < $1.frame.width }
    }
}

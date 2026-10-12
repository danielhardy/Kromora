import AppKit
import XCTest
@testable import KromoraKit

@MainActor
final class LibraryCellClickTests: TempDirectoryTestCase {
    func testNativeDoubleClickUsesEventCountAfterCallbackReplacement() throws {
        let view = LibraryCellClickNSView(frame: NSRect(x: 0, y: 0, width: 220, height: 250))
        var selections: [NSEvent.ModifierFlags] = []
        var opens = 0
        view.onSelect = { selections.append($0) }
        view.onOpen = { XCTFail("the obsolete callback must be replaced") }

        view.mouseDown(with: try event(clickCount: 1, timestamp: 1, flags: [.command]))
        // Represent SwiftUI updating the cell for selection/thumbnail publication. The native
        // second event carries the count regardless of when the main actor finally delivers it.
        view.onOpen = { opens += 1 }
        view.mouseDown(with: try event(clickCount: 2, timestamp: 1.1, flags: [.command]))
        view.mouseDown(with: try event(clickCount: 3, timestamp: 1.2, flags: [.command]))

        XCTAssertEqual(selections, [.command], "double-click must not replay a selection toggle")
        XCTAssertEqual(opens, 1)
        XCTAssertTrue(view.acceptsFirstMouse(for: nil))
    }

    func testASecondClickCanOpenOnARecreatedNativeSurface() throws {
        let replacement = LibraryCellClickNSView(frame: .zero)
        var opened = false
        replacement.onSelect = { _ in XCTFail("the second click is an open") }
        replacement.onOpen = { opened = true }
        replacement.mouseDown(with: try event(clickCount: 2, timestamp: 1.1, flags: [.shift]))
        XCTAssertTrue(opened, "opening does not require recognizer state from the first click")
    }

    func testDoubleClickKeepsItsAssetWhenAnImportChangesSelectionWithThumbnailsPending() async throws {
        let original = try Fixtures.writeGradientPNG(
            width: 48, height: 32, named: "z-original.png", in: tempDirectory
        )
        let imported = try Fixtures.writeGradientPNG(
            width: 52, height: 32, named: "a-imported.png", in: tempDirectory
        )
        let thumbnailWork = LibraryClickThumbnailWork()
        let viewModel = makeAppViewModel(originalThumbnailProvider: { _, _, _, _, _, _, _ in
            await thumbnailWork.load()
            return nil
        })
        await viewModel.openImagesAndWait(urls: [original])
        XCTAssertTrue(viewModel.navigate(to: .grid))
        let clicked = try XCTUnwrap(viewModel.collection.items.first)
        let clickedURL = try XCTUnwrap(clicked.url)
        viewModel.collection.beginThumbnailDemand()
        viewModel.collection.requestVisibleThumbnails(for: [clicked.id])
        let thumbnailDeadline = Date().addingTimeInterval(5)
        while await thumbnailWork.calls == 0 {
            guard Date() < thumbnailDeadline else { return XCTFail("thumbnail work did not start") }
            try await Task.sleep(for: .milliseconds(5))
        }
        let surface = LibraryCellClickNSView(frame: .zero)
        surface.onSelect = { _ in viewModel.selectLibraryItem(at: 0) }
        surface.onOpen = { viewModel.openLibraryImageForEditing(assetID: clicked.id) }
        surface.mouseDown(with: try event(clickCount: 1, timestamp: 1, flags: []))

        // Import publication inserts an earlier-sorted photo and changes the active selection.
        // The second event must still open the photo beneath the original click, not its offset.
        await viewModel.openImagesAndWait(urls: [imported])
        XCTAssertTrue(viewModel.navigate(to: .grid))
        XCTAssertNotEqual(viewModel.collection.selection.activeID, clicked.id)
        XCTAssertNil(clicked.originalThumbnailForPresentation)
        surface.mouseDown(with: try event(clickCount: 2, timestamp: 1.1, flags: []))

        XCTAssertTrue(viewModel.navigation.isEdit)
        XCTAssertEqual(viewModel.collection.selection.activeID, clicked.id)
        let deadline = Date().addingTimeInterval(5)
        while viewModel.sourceURL != clickedURL || viewModel.previewSurface.image == nil {
            guard Date() < deadline else { return XCTFail("the clicked asset did not open") }
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    private func event(
        clickCount: Int, timestamp: TimeInterval, flags: NSEvent.ModifierFlags
    ) throws -> NSEvent {
        try XCTUnwrap(NSEvent.mouseEvent(
            with: .leftMouseDown, location: NSPoint(x: 40, y: 40), modifierFlags: flags,
            timestamp: timestamp, windowNumber: 0, context: nil, eventNumber: clickCount,
            clickCount: clickCount, pressure: 1
        ))
    }
}

private actor LibraryClickThumbnailWork {
    private(set) var calls = 0

    func load() async {
        calls += 1
        try? await Task.sleep(for: .seconds(3))
    }
}

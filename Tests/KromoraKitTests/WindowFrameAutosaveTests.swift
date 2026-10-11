import AppKit
import XCTest

@testable import KromoraKit

@MainActor
final class WindowFrameAutosaveTests: XCTestCase {
    private let frameName = "KromoraTests-\(UUID().uuidString)"

    override func tearDown() async throws {
        await MainActor.run {
            NSWindow.removeFrame(usingName: frameName)
        }
        try await super.tearDown()
    }

    private func makeWindow() -> NSWindow {
        NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 1_200, height: 800),
            styleMask: [.titled, .resizable, .closable], backing: .buffered, defer: true
        )
    }

    /// A relaunch is a new window created at the default size: it must come back at the size the
    /// previous window was left at.
    func testANewWindowAdoptsTheFrameTheLastOneWasLeftAt() throws {
        let first = makeWindow()
        first.contentView = WindowFrameAutosave.Anchor(autosaveName: frameName)
        XCTAssertEqual(first.frameAutosaveName, frameName)

        let resized = NSRect(x: 220, y: 140, width: 1_480, height: 930)
        first.setFrame(resized, display: false)

        let second = makeWindow()
        XCTAssertNotEqual(second.frame.size, resized.size)
        second.contentView = WindowFrameAutosave.Anchor(autosaveName: frameName)

        XCTAssertEqual(second.frame.minX, resized.minX, accuracy: 1)
        XCTAssertEqual(second.frame.minY, resized.minY, accuracy: 1)
        XCTAssertEqual(second.frame.width, resized.width, accuracy: 1)
        XCTAssertEqual(second.frame.height, resized.height, accuracy: 1)
    }

    func testAttachingTwiceKeepsTheSameAutosaveName() {
        let window = makeWindow()
        WindowFrameAutosave.Anchor.attach(frameName, to: window)
        WindowFrameAutosave.Anchor.attach(frameName, to: window)
        XCTAssertEqual(window.frameAutosaveName, frameName)
    }
}

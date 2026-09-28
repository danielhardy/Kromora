import AppKit
import SwiftUI
import XCTest

@testable import KromoraKit

/// Deterministic regression harness for the KRMA-687 crash path.
///
/// The 2026-09-28 incident (`58CC0232-D467-44FA-89FA-3729C5939231`) aborted the main thread when
/// an `NSException` escaped AppKit's `-[NSWindow(NSDisplayCycle) _postWindowNeedsUpdateConstraints]`.
/// The stack shows a SwiftUI scroll-view graph update (`ScrollViewHelper` /
/// `HostingScrollView`) flushing a pending transaction — `NSHostingView.beginTransaction()` calling
/// `setNeedsUpdateConstraints:` — while AppKit was already inside a display-cycle flush
/// recalculating window-drag regions. A sibling report from 2026-09-26 (`A80DD347-...`) hits the
/// same AppKit choke point from the update-constraints phase instead. Neither report includes the
/// exception reason and neither has app frames, so the race itself cannot be reproduced
/// deterministically: it needs a pending scroll-content transaction to coincide with AppKit's
/// display-cycle flush.
///
/// What *can* be pinned deterministically are the app-owned invariants that feed that path:
/// the inspector's width-fitting layout must report a stable size (a measure/place mismatch
/// would keep the scroll view's content size churning and schedule extra transactions), and
/// repeated disclosure expand/collapse inside a hosted window — interleaved with the window
/// resizes that force drag-margin recalculation — must settle back to a stable layout.
/// An uncaught constraint exception would crash the test process, so these tests also serve
/// as a runnable record that the affected flow runs clean on the matching runtime.
@MainActor
final class InspectorScrollCrashPathTests: XCTestCase {
    /// `FitsProposedWidth` must honor the width the parent offers even when a child wants to
    /// be wider, and repeated layouts must report the identical size. A size that oscillates
    /// between passes is a layout feedback loop: every new size schedules another
    /// `ScrollViewHelper` transaction, widening the window for the KRMA-687 re-entrancy.
    func testFitsProposedWidthClampsWideChildAndReportsStableSize() {
        let view = FitsProposedWidth {
            VStack(alignment: .leading, spacing: 0) {
                Text("Narrow row")
                Color.red.frame(width: 600, height: 40)
            }
        }
        .frame(width: 280)
        let hosting = NSHostingView(rootView: view)

        let first = hosting.fittingSize
        XCTAssertEqual(first.width, 280, accuracy: 0.5)
        XCTAssertGreaterThan(first.height, 40)

        hosting.layout()
        let second = hosting.fittingSize
        hosting.layout()
        let third = hosting.fittingSize

        XCTAssertEqual(second.width, first.width, accuracy: 0.5)
        XCTAssertEqual(second.height, first.height, accuracy: 0.5)
        XCTAssertEqual(third.width, first.width, accuracy: 0.5)
        XCTAssertEqual(third.height, first.height, accuracy: 0.5)
    }

    /// Rapid disclosure toggles inside a hosted inspector scroll view, interleaved with window
    /// resizes (which force the same drag-margin / structural-region recalculation that frames
    /// the KRMA-687 throw), must complete and settle: expansion state round-trips and the
    /// collapsed layout returns to its original size rather than creeping.
    func testInspectorDisclosureToggleStormSettlesInHostedWindow() {
        var firstExpanded = true
        var secondExpanded = false
        var thirdExpanded = false

        func stormContent() -> CrashPathStormContent {
            CrashPathStormContent(
                firstExpanded: Binding(get: { firstExpanded }, set: { firstExpanded = $0 }),
                secondExpanded: Binding(get: { secondExpanded }, set: { secondExpanded = $0 }),
                thirdExpanded: Binding(get: { thirdExpanded }, set: { thirdExpanded = $0 })
            )
        }

        let hosting = NSHostingView(rootView: stormContent())
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 600),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        hosting.frame = window.contentView?.bounds ?? .zero
        window.layoutIfNeeded()
        window.displayIfNeeded()
        Self.pumpMainRunLoop()

        let collapsedHeight = hosting.fittingSize.height

        // Expand every section, then collapse again: the animated size change is the scroll
        // transaction at the center of the crash path.
        firstExpanded = true
        secondExpanded = true
        thirdExpanded = true
        hosting.rootView = stormContent()
        window.layoutIfNeeded()
        window.displayIfNeeded()
        Self.pumpMainRunLoop()

        let expandedHeight = hosting.fittingSize.height
        XCTAssertGreaterThan(expandedHeight, collapsedHeight)

        // Toggle storm with window resizes interleaved: resizing forces AppKit's structural
        // region / drag-margin pass while scroll-content transactions are still in flight.
        for index in 0..<6 {
            secondExpanded = index.isMultiple(of: 2)
            hosting.rootView = stormContent()
            let width: CGFloat = index.isMultiple(of: 2) ? 340 : 300
            window.setFrame(NSRect(x: 0, y: 0, width: width, height: 600), display: true)
            hosting.frame = window.contentView?.bounds ?? .zero
            window.layoutIfNeeded()
            window.displayIfNeeded()
        }
        Self.pumpMainRunLoop()

        firstExpanded = true
        secondExpanded = false
        thirdExpanded = false
        hosting.rootView = stormContent()
        window.setFrame(NSRect(x: 0, y: 0, width: 300, height: 600), display: true)
        hosting.frame = window.contentView?.bounds ?? .zero
        window.layoutIfNeeded()
        window.displayIfNeeded()
        Self.pumpMainRunLoop()

        XCTAssertTrue(firstExpanded)
        XCTAssertFalse(secondExpanded)
        XCTAssertFalse(thirdExpanded)
        XCTAssertEqual(hosting.fittingSize.height, collapsedHeight, accuracy: 1.0)
    }

    private static func pumpMainRunLoop() {
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
    }
}

/// Binding-driven wrapper so the toggle storm can rewrite expansion state from the test while
/// the content under test stays the production `InspectorScrollingContent` composition.
private struct CrashPathStormContent: View {
    @Binding var firstExpanded: Bool
    @Binding var secondExpanded: Bool
    @Binding var thirdExpanded: Bool

    var body: some View {
        InspectorScrollingContent {
            VStack(alignment: .leading, spacing: InspectorStyle.contentSpacing) {
                InspectorDisclosure("First", isExpanded: $firstExpanded) {
                    Text("First section body")
                        .font(InspectorStyle.helperText)
                }
                InspectorDisclosure("Second", isExpanded: $secondExpanded) {
                    Text("Second section body")
                        .font(InspectorStyle.helperText)
                    // An over-wide row must stay clamped to the column: if it became the scroll
                    // document's width, the column would clip and every layout would churn.
                    Color.red.frame(width: 600, height: 24)
                }
                InspectorDisclosure("Third", isExpanded: $thirdExpanded) {
                    Text("Third section body")
                        .font(InspectorStyle.helperText)
                }
            }
            .padding(InspectorStyle.contentInset)
        }
    }
}

import AppKit
import SwiftUI
import XCTest

@testable import KromoraKit

@MainActor
final class InfoInspectorPresentationTests: XCTestCase {
    func testInspectorDisclosureCanExpandAndCollapseItsContent() {
        var isExpanded = false
        let binding = Binding(get: { isExpanded }, set: { isExpanded = $0 })
        let view = InspectorDisclosure("Edit History", isExpanded: binding) {
            Text("Saved history content")
        }
        let hosting = NSHostingView(rootView: view)

        let collapsedHeight = hosting.fittingSize.height
        isExpanded = true
        hosting.rootView = InspectorDisclosure("Edit History", isExpanded: binding) {
            Text("Saved history content")
        }
        let expandedHeight = hosting.fittingSize.height

        XCTAssertGreaterThan(expandedHeight, collapsedHeight)

        isExpanded = false
        hosting.rootView = InspectorDisclosure("Edit History", isExpanded: binding) {
            Text("Saved history content")
        }
        XCTAssertEqual(hosting.fittingSize.height, collapsedHeight, accuracy: 0.5)
    }

    func testSharedInspectorTypeAndSpacingScale() {
        XCTAssertEqual(InspectorStyle.contentSpacing, 12)
        XCTAssertEqual(InspectorStyle.sectionSpacing, 12)
        XCTAssertEqual(InspectorStyle.contentInset, 16)
    }

    func testInspectorHeadingsUseSharedPanelSectionAndNestedLevels() {
        XCTAssertEqual(InspectorHeadingLevel.allCases, [.panel, .section, .nested])

        let headings = [
            InspectorPanelHeading(title: "Looks").level,
            InspectorHeading(title: "My Looks", level: .section).level,
            InspectorHeading(title: "Cinematic", level: .nested).level,
            InspectorHeading(title: "Histogram", level: .section).level,
        ]
        XCTAssertEqual(headings, [.panel, .section, .nested, .section])
    }
}

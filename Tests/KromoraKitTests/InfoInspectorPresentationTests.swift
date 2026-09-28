import AppKit
import SwiftUI
import XCTest

@testable import KromoraKit

@MainActor
final class InfoInspectorPresentationTests: XCTestCase {
    func testPhotoAnalysisPrecedesCollapsedEditHistoryWithExistingActions() throws {
        let source = try infoInspectorSource()
        let infoContent = try XCTUnwrap(source.range(of: "private var infoContent"))
        let followingSection = try XCTUnwrap(source.range(of: "// MARK: - Histogram"))
        let presentation = String(source[infoContent.lowerBound..<followingSection.lowerBound])

        let analysisPosition = try XCTUnwrap(presentation.range(of: "PhotoAnalysisInspectSection("))
        let historyPosition = try XCTUnwrap(presentation.range(of: "private var editHistorySection"))
        XCTAssertLessThan(analysisPosition.lowerBound, historyPosition.lowerBound)
        XCTAssertTrue(presentation.contains("@State private var editHistoryExpanded = false"))
        XCTAssertTrue(presentation.contains("InspectorDisclosure(\"Edit History\", isExpanded: $editHistoryExpanded)"))

        for action in [
            "refreshDurableEditHistory()",
            "saveEditSnapshot(named: name)",
            "createVirtualCopy()",
            "restoreEditRevision(entry.revision)",
        ] {
            XCTAssertTrue(presentation.contains(action), "Missing Edit History action: \(action)")
        }
    }

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

    private func infoInspectorSource() throws -> String {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: packageRoot.appendingPathComponent("Sources/KromoraKit/Views/InfoInspectorView.swift"),
            encoding: .utf8
        )
    }
}

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

    func testSharedInspectorTypeAndSpacingScale() throws {
        XCTAssertEqual(InspectorStyle.contentSpacing, 12)
        XCTAssertEqual(InspectorStyle.sectionSpacing, 12)
        XCTAssertEqual(InspectorStyle.contentInset, 16)

        let disclosureSource = try String(
            contentsOf: packageRoot().appendingPathComponent("Sources/KromoraKit/Views/InspectorDisclosure.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(disclosureSource.contains("static let panelTitle = Font.headline"))
        XCTAssertTrue(disclosureSource.contains("titleFont: Font = InspectorStyle.sectionTitle"))
        XCTAssertTrue(disclosureSource.contains("static let fieldLabel = Font.caption"))
        XCTAssertTrue(disclosureSource.contains("static let fieldValue = Font.callout"))
    }

    func testHealUsesSharedAccordionsWithPrimaryToolsOpen() throws {
        let packageRoot = packageRoot()
        let source = try String(
            contentsOf: packageRoot.appendingPathComponent("Sources/KromoraKit/Views/RetouchInspectorView.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(source.contains("@State private var spotsExpanded = true"))
        XCTAssertTrue(source.contains("@State private var dustExpanded = false"))
        XCTAssertTrue(source.contains("@State private var eyesExpanded = false"))
        XCTAssertTrue(source.contains("InspectorDisclosure(\"Spots\", isExpanded: $spotsExpanded)"))
        XCTAssertTrue(source.contains("InspectorDisclosure(\"Dust\", isExpanded: $dustExpanded)"))
        XCTAssertTrue(source.contains("InspectorDisclosure(\"Red-Eye / Pet-Eye\", isExpanded: $eyesExpanded)"))
        XCTAssertFalse(source.contains("GroupBox("))
    }

    private func infoInspectorSource() throws -> String {
        try String(
            contentsOf: packageRoot().appendingPathComponent("Sources/KromoraKit/Views/InfoInspectorView.swift"),
            encoding: .utf8
        )
    }

    private func packageRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

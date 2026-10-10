import XCTest

final class CropInspectorTests: XCTestCase {
    func testResetButtonUsesTheSharedAccessibleIconAction() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // KromoraKitTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // package root
        let cropInspector = try String(
            contentsOf: packageRoot.appendingPathComponent(
                "Sources/KromoraKit/Views/CropInspectorView.swift"
            ),
            encoding: .utf8
        )

        XCTAssertTrue(cropInspector.contains("ResetIconButton("))
        XCTAssertTrue(cropInspector.contains("\"Reset crop\""))
        XCTAssertTrue(cropInspector.contains("accessibilityHint: \"Return the crop frame to the full image\""))

        let resetButton = try String(
            contentsOf: packageRoot.appendingPathComponent("Sources/KromoraKit/Views/ResetIconButton.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(resetButton.contains(".buttonStyle(.plain)"))
        XCTAssertTrue(resetButton.contains(".accessibilityLabel(accessibilityLabel ?? title)"))
        XCTAssertTrue(resetButton.contains(".accessibilityHint(accessibilityHint ?? \"\")"))
    }
}

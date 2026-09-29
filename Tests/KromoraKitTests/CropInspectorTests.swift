import XCTest

final class CropInspectorTests: XCTestCase {
    func testResetButtonUsesTheSemanticPrimaryAccentAndKeepsLinkAccessibility() throws {
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

        let resetButtonStart = try XCTUnwrap(cropInspector.range(of: "Button(\"Reset\", action: onReset)"))
        let resetButtonEnd = try XCTUnwrap(
            cropInspector[resetButtonStart.upperBound...].range(of: "\n            }")
        )
        let resetButton = cropInspector[resetButtonStart.lowerBound..<resetButtonEnd.lowerBound]

        XCTAssertTrue(resetButton.contains(".buttonStyle(.link)"))
        XCTAssertTrue(resetButton.contains(".tint(KromoraTheme.primaryAccent)"))
        XCTAssertTrue(resetButton.contains(".accessibilityLabel(\"Reset crop\")"))
        XCTAssertTrue(
            resetButton.contains(
                ".accessibilityHint(\"Return the crop frame to the full image\")"
            )
        )
    }
}

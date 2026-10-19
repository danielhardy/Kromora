import SwiftUI
import XCTest

@testable import KromoraKit

@MainActor
final class CropInspectorTests: XCTestCase {
    func testCropResetButtonUsesSharedAccessibilityAndInvokesReset() {
        var resetCount = 0
        let button = CropInspectorView.resetButton { resetCount += 1 }

        XCTAssertEqual(button.title, "Reset")
        XCTAssertEqual(button.appearance, .semanticLink)
        XCTAssertEqual(button.accessibilityPresentation.label, "Reset crop")
        XCTAssertEqual(
            button.accessibilityPresentation.hint,
            "Return the crop frame to the full image"
        )

        button.action()
        XCTAssertEqual(resetCount, 1)
    }

    /// Renders the Crop Reset link and samples its pixels: the dominant text hue must be the copper
    /// accent in both appearances, not the system link blue.
    func testCropResetLinkRendersInPrimaryAccent() throws {
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            let appearance = try XCTUnwrap(NSAppearance(named: name))
            let expected = KromoraTheme.resolvedPrimaryAccentColor(for: appearance)
            let view = CropInspectorView.resetButton {}
                .environment(\.colorScheme, name == .darkAqua ? .dark : .light)
                .padding(8)
                .background(name == .darkAqua ? Color.black : Color.white)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            let cgImage = try XCTUnwrap(renderer.cgImage)
            let rep = NSBitmapImageRep(cgImage: cgImage)

            // Thin antialiased glyphs rarely reach the exact colour, so average the coloured
            // pixels and compare hue: system link blue sits far from copper.
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, n: CGFloat = 0
            for x in 0..<rep.pixelsWide {
                for y in 0..<rep.pixelsHigh {
                    guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                        c.saturationComponent > 0.3
                    else { continue }
                    r += c.redComponent; g += c.greenComponent; b += c.blueComponent; n += 1
                }
            }
            XCTAssertGreaterThan(n, 10, "no coloured text in \(name.rawValue)")
            let mean = NSColor(deviceRed: r / n, green: g / n, blue: b / n, alpha: 1)
            XCTAssertEqual(mean.hueComponent, expected.hueComponent, accuracy: 0.06, "\(name.rawValue)")
            XCTAssertGreaterThan(mean.redComponent, mean.blueComponent)
        }
    }

    func testSharedResetButtonDefaultsAccessibilityToItsTitle() {
        let button = ResetIconButton("Reset test") {}

        XCTAssertEqual(button.accessibilityPresentation.label, "Reset test")
        XCTAssertEqual(button.accessibilityPresentation.hint, "")
    }

    /// A missing SF Symbol draws nothing, so the button looks blank. `rectangle.landscape` was one.
    @MainActor
    func testOrientationButtonsUseSymbolsThatExist() {
        for name in [
            CropInspectorView.landscapeOrientationSymbol,
            CropInspectorView.portraitOrientationSymbol,
        ] {
            XCTAssertNotNil(
                NSImage(systemSymbolName: name, accessibilityDescription: nil),
                "\(name) is not an SF Symbol"
            )
        }
    }
}

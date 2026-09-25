import AppKit
import XCTest
@testable import KromoraKit

final class KromoraThemeTests: XCTestCase {
    func testPrimaryAccentResolvesToCentralizedCopperVariants() throws {
        let dark = try XCTUnwrap(
            KromoraTheme.resolvedPrimaryAccentColor(for: NSAppearance(named: .darkAqua))
                .usingColorSpace(.deviceRGB)
        )
        let light = try XCTUnwrap(
            KromoraTheme.resolvedPrimaryAccentColor(for: NSAppearance(named: .aqua))
                .usingColorSpace(.deviceRGB)
        )

        XCTAssertEqual(dark.redComponent, 206 / 255, accuracy: 0.002)
        XCTAssertEqual(dark.greenComponent, 134 / 255, accuracy: 0.002)
        XCTAssertEqual(dark.blueComponent, 92 / 255, accuracy: 0.002)
        XCTAssertEqual(light.redComponent, 157 / 255, accuracy: 0.002)
        XCTAssertEqual(light.greenComponent, 87 / 255, accuracy: 0.002)
        XCTAssertEqual(light.blueComponent, 56 / 255, accuracy: 0.002)
    }

    func testDarkPrimaryAccentHasAccessibleContrastAgainstCanvas() throws {
        let accent = try XCTUnwrap(
            KromoraTheme.resolvedPrimaryAccentColor(for: NSAppearance(named: .darkAqua))
                .usingColorSpace(.deviceRGB)
        )
        let canvas = try XCTUnwrap(
            KromoraTheme.resolvedCanvasBackgroundColor(for: NSAppearance(named: .darkAqua))
                .usingColorSpace(.deviceRGB)
        )

        XCTAssertGreaterThan(contrastRatio(accent, canvas), 4.5)
    }

    private func contrastRatio(_ lhs: NSColor, _ rhs: NSColor) -> CGFloat {
        let values = [luminance(lhs), luminance(rhs)].sorted(by: >)
        return (values[0] + 0.05) / (values[1] + 0.05)
    }

    private func luminance(_ color: NSColor) -> CGFloat {
        func linear(_ component: CGFloat) -> CGFloat {
            component <= 0.04045
                ? component / 12.92
                : pow((component + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(color.redComponent)
            + 0.7152 * linear(color.greenComponent)
            + 0.0722 * linear(color.blueComponent)
    }
}

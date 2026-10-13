import AppKit
import SwiftUI
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
        XCTAssertEqual(light.redComponent, 184 / 255, accuracy: 0.002)
        XCTAssertEqual(light.greenComponent, 99 / 255, accuracy: 0.002)
        XCTAssertEqual(light.blueComponent, 58 / 255, accuracy: 0.002)
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

    func testShellSurfacesSeparateCanvasSidebarAndToolbarInBothAppearances() throws {
        let lightChrome = try XCTUnwrap(
            KromoraTheme.resolvedSecondaryChromeColor(for: NSAppearance(named: .aqua))
                .usingColorSpace(.deviceRGB)
        )
        XCTAssertEqual(lightChrome.redComponent, 242 / 255, accuracy: 0.002)
        XCTAssertEqual(lightChrome.greenComponent, 239 / 255, accuracy: 0.002)
        XCTAssertEqual(lightChrome.blueComponent, 234 / 255, accuracy: 0.002)

        let darkAppearance = try XCTUnwrap(NSAppearance(named: .darkAqua))
        let lightAppearance = try XCTUnwrap(NSAppearance(named: .aqua))
        let darkCanvas = try XCTUnwrap(
            KromoraTheme.resolvedCanvasBackgroundColor(for: darkAppearance).usingColorSpace(.deviceRGB)
        )
        let darkSidebar = try XCTUnwrap(
            KromoraTheme.resolvedSecondaryChromeColor(for: darkAppearance).usingColorSpace(.deviceRGB)
        )
        let lightCanvas = try XCTUnwrap(
            KromoraTheme.resolvedCanvasBackgroundColor(for: lightAppearance).usingColorSpace(.deviceRGB)
        )

        XCTAssertEqual(darkCanvas.redComponent, 20.0 / 255.0, accuracy: 0.01)
        XCTAssertEqual(darkSidebar.redComponent, 34.0 / 255.0, accuracy: 0.01)
        XCTAssertGreaterThan(darkSidebar.redComponent, darkCanvas.redComponent)
        XCTAssertGreaterThan(lightChrome.redComponent, lightCanvas.redComponent)

        let lightInspector = try XCTUnwrap(
            KromoraTheme.resolvedInspectorChromeColor(for: lightAppearance).usingColorSpace(.deviceRGB)
        )
        let lightToolbar = try XCTUnwrap(
            KromoraTheme.resolvedToolbarChromeColor(for: lightAppearance).usingColorSpace(.deviceRGB)
        )
        let darkInspector = try XCTUnwrap(
            KromoraTheme.resolvedInspectorChromeColor(for: darkAppearance).usingColorSpace(.deviceRGB)
        )
        XCTAssertEqual(lightInspector.redComponent, lightToolbar.redComponent, accuracy: 0.002)
        XCTAssertEqual(lightInspector.greenComponent, lightToolbar.greenComponent, accuracy: 0.002)
        XCTAssertEqual(lightInspector.blueComponent, lightToolbar.blueComponent, accuracy: 0.002)
        XCTAssertEqual(darkInspector.redComponent, 42.0 / 255.0, accuracy: 0.01)
        XCTAssertGreaterThan(lightInspector.redComponent, lightChrome.redComponent)
    }

    func testDarkSurfaceLadderIsStrictlyOrdered() throws {
        let dark = try XCTUnwrap(NSAppearance(named: .darkAqua))
        func white(_ color: NSColor) throws -> CGFloat {
            try XCTUnwrap(color.usingColorSpace(.deviceRGB)).redComponent
        }
        let canvas = try white(KromoraTheme.resolvedCanvasBackgroundColor(for: dark))
        let secondary = try white(KromoraTheme.resolvedSecondaryChromeColor(for: dark))
        let inspector = try white(KromoraTheme.resolvedInspectorChromeColor(for: dark))
        let toolbar = try white(KromoraTheme.resolvedToolbarChromeColor(for: dark))

        XCTAssertGreaterThan(canvas, 0.03, "Canvas should not collapse to flat black")
        XCTAssertGreaterThan(secondary - canvas, 0.04)
        XCTAssertGreaterThan(inspector - secondary, 0.02)
        XCTAssertGreaterThan(toolbar - inspector, 0.02)
    }

    func testLightAccentAndLabelsAreReadableOnPaleSurfaces() throws {
        let light = try XCTUnwrap(NSAppearance(named: .aqua))
        let inspector = try XCTUnwrap(
            KromoraTheme.resolvedInspectorChromeColor(for: light).usingColorSpace(.deviceRGB)
        )
        let accent = try XCTUnwrap(
            KromoraTheme.resolvedPrimaryAccentColor(for: light).usingColorSpace(.deviceRGB)
        )
        let label = KromoraTheme.resolvedAdjustmentLabelColor(for: light)
        let canvas = try XCTUnwrap(
            KromoraTheme.resolvedCanvasBackgroundColor(for: light).usingColorSpace(.deviceRGB)
        )
        let secondary = try XCTUnwrap(
            KromoraTheme.resolvedSecondaryChromeColor(for: light).usingColorSpace(.deviceRGB)
        )

        XCTAssertGreaterThan(contrastRatio(accent, inspector), 3.5)
        XCTAssertGreaterThan(contrastRatio(label, inspector), 7)
        // The accent stays copper: red leads green leads blue.
        XCTAssertGreaterThan(accent.redComponent, accent.greenComponent + 0.2)
        XCTAssertGreaterThan(accent.greenComponent, accent.blueComponent)
        // Pale ladder: canvas < secondary < inspector, none heavy.
        XCTAssertGreaterThan(canvas.redComponent, 0.9)
        XCTAssertGreaterThan(secondary.redComponent, canvas.redComponent)
        XCTAssertGreaterThan(inspector.redComponent, secondary.redComponent)
    }

    func testAnalysisBackgroundIsLighterInLightAppearanceAndUnchangedInDark() throws {
        let dark = KromoraTheme.resolvedAnalysisBackgroundColor(for: NSAppearance(named: .darkAqua))
        let light = KromoraTheme.resolvedAnalysisBackgroundColor(for: NSAppearance(named: .aqua))
        XCTAssertEqual(dark.alphaComponent, 0.25, accuracy: 0.002)
        XCTAssertLessThan(light.alphaComponent, dark.alphaComponent)
    }

    func testAdvancedBandIsLighterInLightAppearanceAndUnchangedInDark() throws {
        let dark = KromoraTheme.resolvedAdvancedBandColor(for: NSAppearance(named: .darkAqua))
        let light = KromoraTheme.resolvedAdvancedBandColor(for: NSAppearance(named: .aqua))
        XCTAssertEqual(dark.alphaComponent, 0.22, accuracy: 0.002)
        XCTAssertLessThan(light.alphaComponent, 0.08)
    }

    func testAnalysisGridIsDarkInkInLightAndWhiteInDark() throws {
        func resolved(_ color: Color, _ name: NSAppearance.Name) -> NSColor {
            var out = NSColor.clear
            NSAppearance(named: name)!.performAsCurrentDrawingAppearance {
                out = NSColor(color).usingColorSpace(.deviceRGB) ?? .clear
            }
            return out
        }
        XCTAssertLessThan(resolved(KromoraTheme.analysisGrid, .aqua).redComponent, 0.1)
        XCTAssertGreaterThan(resolved(KromoraTheme.analysisGrid, .darkAqua).redComponent, 0.9)
        XCTAssertGreaterThan(resolved(KromoraTheme.analysisGrid, .aqua).alphaComponent, 0.1)
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

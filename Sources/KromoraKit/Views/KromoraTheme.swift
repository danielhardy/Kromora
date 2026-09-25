import AppKit
import SwiftUI

/// Appearance-aware surfaces shared by the app shell.
///
/// AppKit's named NSColors are dynamic colors: SwiftUI resolves them against the
/// current window appearance, so they update when macOS changes between light and
/// dark mode while the window is open. Keep fixed dark colors out of these shell
/// surfaces; image-analysis canvases have their own explicitly scoped colors.
enum KromoraTheme {
    // Surface roles for the editor shell:
    //
    // - Window toolbar: full-width native toolbar material; do not paint a custom fill.
    // - Inspector: the system inspector material. The histogram occupies the band beside the
    //   toolbar; the window hides the title-bar separator so it is not drawn through the plot.
    // - Canvas surround: the dedicated recessed stage below, kept distinct from chrome.
    // - Secondary chrome: source browser, filmstrip, culling, and status surfaces share the
    //   quieter semantic under-page color rather than the elevated `.bar` material.
    // - Analysis plots: locally scoped dark plot surfaces only.

    static var windowBackground: Color {
        Color(nsColor: .windowBackgroundColor)
    }

    /// Kromora's primary interactive accent. The dark variant is a muted copper chosen
    /// to harmonize with the independently configurable orange mask overlay while staying
    /// distinct from it. Keep both appearance values here so every control shares one source.
    static var primaryAccent: Color {
        Color(nsColor: primaryAccentNSColor)
    }

    /// AppKit controls use this same dynamic color at their native drawing boundary.
    static var primaryAccentNSColor: NSColor { primaryAccentColor }

    static func resolvedPrimaryAccentColor(for appearance: NSAppearance? = nil) -> NSColor {
        let effectiveAppearance = appearance ?? NSAppearance(named: .aqua)!
        var color: NSColor?
        effectiveAppearance.performAsCurrentDrawingAppearance {
            color = primaryAccentColor.usingColorSpace(.deviceRGB)
        }
        return color ?? NSColor(srgbRed: 0.616, green: 0.341, blue: 0.220, alpha: 1)
    }

    /// Quiet semantic surface for chrome that supports the canvas without competing with it.
    /// `underPageBackgroundColor` follows the active light/dark appearance and is deliberately
    /// shared by the source browser and the large bottom chrome family.
    static var secondaryChrome: Color {
        Color(nsColor: .underPageBackgroundColor)
    }

    /// Dedicated editor surface color. Secondary chrome can converge with
    /// `windowBackgroundColor` on newer macOS releases, so the image canvas needs an explicit
    /// neutral that remains visibly recessed in either appearance.
    static var canvasBackground: Color {
        Color(nsColor: canvasBackgroundNSColor)
    }

    /// Resolve the canvas surface at the native AppKit boundary so Metal and SwiftUI use the
    /// same appearance-specific color. Keep this separate from `windowBackground`: inspectors
    /// and other window chrome intentionally continue to follow the system window surface.
    static func resolvedCanvasBackgroundColor(for appearance: NSAppearance? = nil) -> NSColor {
        let effectiveAppearance = appearance ?? NSAppearance(named: .aqua)!
        var color: NSColor?
        effectiveAppearance.performAsCurrentDrawingAppearance {
            color = canvasBackgroundNSColor.usingColorSpace(.deviceRGB)
        }
        return color ?? NSColor(calibratedWhite: 0.90, alpha: 1)
    }

    private static let canvasBackgroundNSColor = NSColor(
        name: NSColor.Name("KromoraCanvasBackground")
    ) { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return NSColor(calibratedWhite: isDark ? 0.12 : 0.90, alpha: 1)
    }

    private static let primaryAccentColor = NSColor(
        name: NSColor.Name("KromoraPrimaryAccent")
    ) { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        // Dark: #CE865C (RGB 206, 134, 92), light: #9D5738 (RGB 157, 87, 56).
        return isDark
            ? NSColor(srgbRed: 206 / 255, green: 134 / 255, blue: 92 / 255, alpha: 1)
            : NSColor(srgbRed: 157 / 255, green: 87 / 255, blue: 56 / 255, alpha: 1)
    }

    static var controlBackground: Color {
        Color(nsColor: .controlBackgroundColor)
    }

    /// Deliberately dark backdrop for histogram and tone-curve plots. The plot
    /// content uses bright/primary colors so the analysis remains readable in
    /// either system appearance without darkening its containing inspector.
    static let analysisBackground = Color.black.opacity(0.25)
    static let analysisBorder = Color.white.opacity(0.08)
    static let analysisGrid = Color.white.opacity(0.10)
    static let analysisReference = Color.white.opacity(0.25)
}

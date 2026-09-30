import AppKit
import SwiftUI

/// Appearance-aware surfaces shared by the app shell.
///
/// AppKit's named NSColors are dynamic colors: SwiftUI resolves them against the
/// current window appearance, so they update when macOS changes between light and
/// dark mode while the window is open. Keep fixed dark colors out of these shell
/// surfaces; image-analysis canvases have their own explicitly scoped colors.
enum KromoraTheme {
    // Surface roles for the editor shell. Each one is a dynamic AppKit color, so it follows the
    // window appearance: system light, system dark, or the Settings "Always dark mode" override.
    //
    // - Toolbar: the lightest chrome band.
    // - Secondary chrome: source browser and library. A step lighter than the canvas in
    //   dark appearance, and the warm neutral in light appearance.
    //   In Edit, the filmstrip, culling bar, and status row use the canvas so they share
    //   the photo's plane. Library status stays on this secondary surface.
    // - Inspector: matches the toolbar in light appearance, and the sidebar step in dark.
    // - Canvas: the recessed editor stage, the darkest large surface in dark appearance.
    // - Analysis plots: locally scoped dark plot surfaces only.

    static var windowBackground: Color {
        Color(nsColor: .windowBackgroundColor)
    }

    /// The toolbar band. Dark appearance lifts it well above the sidebar and canvas, the way
    /// Xcode's toolbar sits above the editor. Light appearance stays a near-white chrome.
    static var toolbarChrome: Color {
        Color(nsColor: toolbarChromeNSColor)
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
    /// Light mode uses a warm neutral. Dark mode is a sidebar tone, lighter than the canvas
    /// and darker than the toolbar.
    static var secondaryChrome: Color {
        Color(nsColor: secondaryChromeNSColor)
    }

    /// The inspector column. Light appearance matches the toolbar so the sidebar reads as
    /// bright chrome. Dark appearance stays the sidebar step, below the toolbar.
    static var inspectorChrome: Color {
        Color(nsColor: inspectorChromeNSColor)
    }

    static func resolvedInspectorChromeColor(for appearance: NSAppearance? = nil) -> NSColor {
        let effectiveAppearance = appearance ?? NSAppearance(named: .aqua)!
        var color: NSColor?
        effectiveAppearance.performAsCurrentDrawingAppearance {
            color = inspectorChromeNSColor.usingColorSpace(.deviceRGB)
        }
        return color ?? NSColor(calibratedWhite: 0.96, alpha: 1)
    }

    static func resolvedToolbarChromeColor(for appearance: NSAppearance? = nil) -> NSColor {
        let effectiveAppearance = appearance ?? NSAppearance(named: .aqua)!
        var color: NSColor?
        effectiveAppearance.performAsCurrentDrawingAppearance {
            color = toolbarChromeNSColor.usingColorSpace(.deviceRGB)
        }
        return color ?? NSColor(calibratedWhite: 0.96, alpha: 1)
    }

    static func resolvedSecondaryChromeColor(for appearance: NSAppearance? = nil) -> NSColor {
        let effectiveAppearance = appearance ?? NSAppearance(named: .aqua)!
        var color: NSColor?
        effectiveAppearance.performAsCurrentDrawingAppearance {
            color = secondaryChromeNSColor.usingColorSpace(.deviceRGB)
        }
        return color ?? NSColor(srgbRed: 0.925, green: 0.910, blue: 0.882, alpha: 1)
    }

    /// Dedicated editor surface color. On this macOS release the system window, control, and
    /// under-page colors collapse to nearly the same dark value, so the canvas and the chrome
    /// around it use explicit neutrals that still switch with the window appearance.
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

    private static let toolbarChromeNSColor = NSColor(
        name: NSColor.Name("KromoraToolbarChrome")
    ) { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        // Dark matches the lighter Xcode toolbar band. Light stays near the system window.
        return isDark
            ? NSColor(srgbRed: 74.0 / 255.0, green: 74.0 / 255.0, blue: 74.0 / 255.0, alpha: 1)
            : NSColor(calibratedWhite: 0.96, alpha: 1)
    }

    private static let canvasBackgroundNSColor = NSColor(
        name: NSColor.Name("KromoraCanvasBackground")
    ) { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        // Dark is the recessed editor, darker than the sidebar. Light stays the existing stage.
        return isDark
            ? NSColor(srgbRed: 38.0 / 255.0, green: 38.0 / 255.0, blue: 38.0 / 255.0, alpha: 1)
            : NSColor(calibratedWhite: 0.90, alpha: 1)
    }

    private static let inspectorChromeNSColor = NSColor(
        name: NSColor.Name("KromoraInspectorChrome")
    ) { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        // Light matches the toolbar. Dark stays the sidebar step, not the toolbar band.
        return isDark
            ? NSColor(srgbRed: 52.0 / 255.0, green: 52.0 / 255.0, blue: 52.0 / 255.0, alpha: 1)
            : NSColor(calibratedWhite: 0.96, alpha: 1)
    }

    private static let secondaryChromeNSColor = NSColor(
        name: NSColor.Name("KromoraSecondaryChrome")
    ) { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        // Light: #ECE8E1, a quiet warm neutral above the canvas.
        // Dark: a sidebar step between the canvas and the toolbar.
        return isDark
            ? NSColor(srgbRed: 52.0 / 255.0, green: 52.0 / 255.0, blue: 52.0 / 255.0, alpha: 1)
            : NSColor(srgbRed: 236 / 255, green: 232 / 255, blue: 225 / 255, alpha: 1)
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

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
    // window appearance: system light, system dark, or the Settings Light or Dark override.
    //
    // Dark appearance is a graphite ladder, darkest to lightest: canvas #141414, secondary
    // chrome #222222, inspector #2A2A2A, toolbar #323232. Large adjacent planes differ by at
    // least one step, and none is flat black. Native materials are reserved for floating
    // overlays (badges, capsules) that sit over photo content; large panes stay opaque so
    // labels and analysis plots keep a stable contrast backdrop.
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
        return color ?? NSColor(srgbRed: 0.722, green: 0.388, blue: 0.227, alpha: 1)
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
        return color ?? NSColor(srgbRed: 0.949, green: 0.937, blue: 0.918, alpha: 1)
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
        // Dark is the lightest graphite step. Light stays near the system window.
        return isDark
            ? NSColor(srgbRed: 50.0 / 255.0, green: 50.0 / 255.0, blue: 50.0 / 255.0, alpha: 1)
            : NSColor(srgbRed: 249 / 255, green: 249 / 255, blue: 249 / 255, alpha: 1)
    }

    private static let canvasBackgroundNSColor = NSColor(
        name: NSColor.Name("KromoraCanvasBackground")
    ) { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        // Dark is the recessed editor, darker than the sidebar. Light stays the existing stage.
        return isDark
            ? NSColor(srgbRed: 20.0 / 255.0, green: 20.0 / 255.0, blue: 20.0 / 255.0, alpha: 1)
            : NSColor(srgbRed: 238 / 255, green: 238 / 255, blue: 238 / 255, alpha: 1)
    }

    private static let inspectorChromeNSColor = NSColor(
        name: NSColor.Name("KromoraInspectorChrome")
    ) { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        // Light matches the toolbar. Dark sits between the sidebar and the toolbar band.
        return isDark
            ? NSColor(srgbRed: 42.0 / 255.0, green: 42.0 / 255.0, blue: 42.0 / 255.0, alpha: 1)
            : NSColor(srgbRed: 249 / 255, green: 249 / 255, blue: 249 / 255, alpha: 1)
    }

    private static let secondaryChromeNSColor = NSColor(
        name: NSColor.Name("KromoraSecondaryChrome")
    ) { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        // Light: #F2EFEA, a quiet warm neutral above the canvas.
        // Dark: a sidebar step between the canvas and the inspector.
        return isDark
            ? NSColor(srgbRed: 34.0 / 255.0, green: 34.0 / 255.0, blue: 34.0 / 255.0, alpha: 1)
            : NSColor(srgbRed: 242 / 255, green: 239 / 255, blue: 234 / 255, alpha: 1)
    }

    private static let primaryAccentColor = NSColor(
        name: NSColor.Name("KromoraPrimaryAccent")
    ) { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        // Dark: #CE865C (RGB 206, 134, 92), light: #B8633A (RGB 184, 99, 58).
        return isDark
            ? NSColor(srgbRed: 206 / 255, green: 134 / 255, blue: 92 / 255, alpha: 1)
            : NSColor(srgbRed: 184 / 255, green: 99 / 255, blue: 58 / 255, alpha: 1)
    }

    /// Active adjustment-row labels. Light appearance reads as enabled text; dark keeps the
    /// system secondary label. Genuinely disabled values keep system tertiary styling.
    static var adjustmentLabel: Color {
        Color(nsColor: adjustmentLabelNSColor)
    }

    static func resolvedAdjustmentLabelColor(for appearance: NSAppearance? = nil) -> NSColor {
        let effectiveAppearance = appearance ?? NSAppearance(named: .aqua)!
        var color: NSColor?
        effectiveAppearance.performAsCurrentDrawingAppearance {
            color = adjustmentLabelNSColor.usingColorSpace(.deviceRGB)
        }
        return color ?? NSColor(white: 0.15, alpha: 1)
    }

    private static let adjustmentLabelNSColor = NSColor(
        name: NSColor.Name("KromoraAdjustmentLabel")
    ) { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        // Light: #3C3C3C on the pale inspector (about 10:1), still a step below primary text.
        return isDark
            ? NSColor.secondaryLabelColor
            : NSColor(srgbRed: 60 / 255, green: 60 / 255, blue: 60 / 255, alpha: 1)
    }

    static var controlBackground: Color {
        Color(nsColor: .controlBackgroundColor)
    }

    /// Deliberately dark backdrop for histogram and tone-curve plots. The plot
    /// content uses bright/primary colors so the analysis remains readable in
    /// either system appearance without darkening its containing inspector.
    /// Light appearance uses a lighter tint so the plot does not read as a heavy gray block.
    static var analysisBackground: Color {
        Color(nsColor: analysisBackgroundNSColor)
    }

    static func resolvedAnalysisBackgroundColor(for appearance: NSAppearance? = nil) -> NSColor {
        let effectiveAppearance = appearance ?? NSAppearance(named: .aqua)!
        var color: NSColor?
        effectiveAppearance.performAsCurrentDrawingAppearance {
            color = analysisBackgroundNSColor.usingColorSpace(.deviceRGB)
        }
        return color ?? NSColor.black.withAlphaComponent(0.25)
    }

    private static let analysisBackgroundNSColor = NSColor(
        name: NSColor.Name("KromoraAnalysisBackground")
    ) { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return NSColor.black.withAlphaComponent(isDark ? 0.25 : 0.16)
    }
    /// Light appearance draws these in dark ink, because the light plot backdrop is pale and
    /// white lines would vanish; dark appearance keeps the original white lines.
    static let analysisBorder = analysisLine(darkAlpha: 0.08, lightAlpha: 0.14)
    static let analysisGrid = analysisLine(darkAlpha: 0.10, lightAlpha: 0.16)
    static let analysisReference = analysisLine(darkAlpha: 0.25, lightAlpha: 0.38)

    /// Tint behind the "Advanced" bands (Sharpening, Vignette, Grain, Noise reduction, ...).
    /// Light appearance is a faint wash so the band stays lighter than the inspector's heavy plots.
    static var advancedBand: Color {
        Color(nsColor: advancedBandNSColor)
    }

    static func resolvedAdvancedBandColor(for appearance: NSAppearance? = nil) -> NSColor {
        let effectiveAppearance = appearance ?? NSAppearance(named: .aqua)!
        var color: NSColor?
        effectiveAppearance.performAsCurrentDrawingAppearance {
            color = advancedBandNSColor.usingColorSpace(.deviceRGB)
        }
        return color ?? NSColor.black.withAlphaComponent(0.035)
    }

    private static let advancedBandNSColor = NSColor(
        name: NSColor.Name("KromoraAdvancedBand")
    ) { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return NSColor.black.withAlphaComponent(isDark ? 0.22 : 0.035)
    }

    private static func analysisLine(darkAlpha: CGFloat, lightAlpha: CGFloat) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return isDark
                ? NSColor.white.withAlphaComponent(darkAlpha)
                : NSColor.black.withAlphaComponent(lightAlpha)
        })
    }
}

extension View {
    /// Bordered style for ordinary one-shot actions. The window-wide copper tint is reserved for
    /// what is on or selected, so actions reset the inherited tint and read as plain buttons.
    /// Stateful controls use `.buttonStyle(.bordered)` with an explicit state-driven `.tint`.
    func neutralActionButton() -> some View {
        buttonStyle(.bordered).tint(nil)
    }
}

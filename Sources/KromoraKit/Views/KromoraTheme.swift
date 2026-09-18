import AppKit
import SwiftUI

/// Appearance-aware surfaces shared by the app shell.
///
/// AppKit's named NSColors are dynamic colors: SwiftUI resolves them against the
/// current window appearance, so they update when macOS changes between light and
/// dark mode while the window is open. Keep fixed dark colors out of these shell
/// surfaces; image-analysis canvases have their own explicitly scoped colors.
enum KromoraTheme {
    static var windowBackground: Color {
        Color(nsColor: .windowBackgroundColor)
    }

    /// Dedicated editor surface color. The system `.bar` material used by the source browser
    /// can converge with `windowBackgroundColor` on newer macOS releases, so the image canvas
    /// needs an explicit neutral that remains visibly recessed in either appearance.
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

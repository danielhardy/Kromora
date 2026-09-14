import Foundation

/// Photographer-facing formatting for color controls. Display precision is intentionally separate
/// from the Double values used by bindings, persistence, and rendering.
enum ColorSettingFormatting {
    static func temperature(_ value: Double) -> String {
        String(format: "%.0f K", value)
    }

    static func tint(_ value: Double) -> String {
        String(format: "%+.0f", value)
    }
}

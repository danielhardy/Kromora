import Foundation

/// Photographer-facing formatting for color controls. Display precision is intentionally separate
/// from the Double values used by bindings, persistence, and rendering.
enum ColorSettingFormatting {
    /// The numeric-entry contract for photographer-facing colour controls. The model remains a
    /// Double, but the inspector commits the same whole-number precision that its readouts use.
    static let wholeNumberFormat: FloatingPointFormatStyle<Double> =
        .number.precision(.fractionLength(0))
    static let signedWholeNumberFormat: FloatingPointFormatStyle<Double> =
        wholeNumberFormat.sign(strategy: .always(includingZero: false))

    static func temperature(_ value: Double) -> String {
        String(format: "%.0f K", value)
    }

    static func tint(_ value: Double) -> String {
        String(format: "%+.0f", value)
    }
}

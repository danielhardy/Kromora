import Foundation

/// Where a slider's *active* fill runs, as fractions of the track measured from its minimum end.
///
/// Split out of the drawing code because this repo has no SwiftUI view tests and `NSSliderCell`
/// drawing is awkward to assert on directly. The rule that matters — no fill at neutral, fill on one
/// side of neutral only otherwise — is a pure function of three numbers, so it is one here and
/// `SliderFillTests` pins it without an `NSView`, a window, or a display.
struct SliderFill: Equatable, Sendable {
    /// Fraction of the track where the fill begins. `0` is the minimum end, `1` the maximum end.
    let start: Double

    /// Fraction of the track where the fill ends. Never less than `start`.
    let end: Double

    /// Nothing to draw — the value is sitting on its neutral, or the range is degenerate.
    var isEmpty: Bool { end <= start }

    static let none = SliderFill(start: 0, end: 0)

    /// The fill for `value`, anchored at the baseline the control does nothing at.
    ///
    /// **The baseline is the control's own neutral, not the range's midpoint and not zero.**
    /// `AdjustmentControl.contrast` is neutral at 1 in 0…2, `AdjustmentControl.highlights` at 1 in
    /// 0.3…1 (its *maximum*, so that fill only ever runs leftwards), `VignetteControl.midpoint` at 50
    /// in 0…100, and `LightControl.exposure` at 0 in −5…5. Assuming any one of those from the range
    /// alone gets the other three wrong.
    ///
    /// A genuinely unipolar control — a brush size, a Look intensity, a mask amount — passes its
    /// lower bound and gets the familiar left-origin fill out of the same formula, so there is one
    /// code path rather than a bipolar one and a normal one that can drift apart.
    static func span(value: Double, neutral: Double, in range: ClosedRange<Double>) -> SliderFill {
        let width = range.upperBound - range.lowerBound
        guard width > 0, value.isFinite, neutral.isFinite else { return .none }

        func fraction(_ point: Double) -> Double {
            min(max((point - range.lowerBound) / width, 0), 1)
        }

        let valueFraction = fraction(value)
        let neutralFraction = fraction(neutral)
        return SliderFill(
            start: min(valueFraction, neutralFraction),
            end: max(valueFraction, neutralFraction)
        )
    }
}

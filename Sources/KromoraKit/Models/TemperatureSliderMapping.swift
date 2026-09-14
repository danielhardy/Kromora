import Foundation

/// The non-linear position/value mapping shared by every photographic temperature slider.
///
/// Kelvin is a physical value, but a linear Kelvin track spends most of its travel above the
/// useful photographic range. A logarithmic scale gives 2,000...10,000 K most of the track while
/// retaining an exact, reversible path to the full upper bound. The mapping is pure so it can be
/// exercised without constructing an AppKit or SwiftUI control.
struct TemperatureSliderMapping: Equatable, Sendable {
    let kelvinRange: ClosedRange<Double>

    /// The AppKit slider's normalized coordinate. The model-facing value remains Kelvin.
    static let sliderRange: ClosedRange<Double> = 0...1

    init(kelvinRange: ClosedRange<Double>) {
        precondition(
            kelvinRange.lowerBound > 0 && kelvinRange.upperBound > kelvinRange.lowerBound,
            "Temperature slider ranges must be positive and increasing"
        )
        self.kelvinRange = kelvinRange
    }

    /// Convert a Kelvin value to the normalized physical slider position.
    func sliderPosition(for kelvin: Double) -> Double {
        let value = kelvin.clamped(to: kelvinRange)
        return log(value / kelvinRange.lowerBound)
            / log(kelvinRange.upperBound / kelvinRange.lowerBound)
    }

    /// Convert a normalized slider position back to Kelvin.
    func kelvinValue(for sliderPosition: Double) -> Double {
        let position = sliderPosition.clamped(to: Self.sliderRange)
        return kelvinRange.lowerBound
            * pow(
                kelvinRange.upperBound / kelvinRange.lowerBound, position
            )
    }
}

extension Comparable {
    fileprivate func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

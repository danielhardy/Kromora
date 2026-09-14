import SwiftUI

/// An AppKit-backed slider that presents a logarithmic Kelvin track while binding in Kelvin.
///
/// Keeping the conversion here means numeric entry, persistence, rendering, reset/as-shot
/// behavior, keyboard interaction, and accessibility all continue to use the photographer-facing
/// Kelvin value. Only the knob's internal coordinate is normalized for the non-linear track.
struct TemperatureSlider: View {
    @Binding private var value: Double
    private let range: ClosedRange<Double>
    private let neutral: Double
    private let trackStyle: SliderTrackStyle
    private let accessibilityTitle: String?
    private let accessibilityReadout: String?
    private let onEditingChanged: (Bool) -> Void

    init(
        value: Binding<Double>,
        in range: ClosedRange<Double>,
        neutral: Double,
        trackStyle: SliderTrackStyle = .temperature,
        accessibilityTitle: String? = nil,
        accessibilityReadout: String? = nil,
        onEditingChanged: @escaping (Bool) -> Void = { _ in }
    ) {
        self._value = value
        self.range = range
        self.neutral = neutral
        self.trackStyle = trackStyle
        self.accessibilityTitle = accessibilityTitle
        self.accessibilityReadout = accessibilityReadout
        self.onEditingChanged = onEditingChanged
    }

    var body: some View {
        let mapping = TemperatureSliderMapping(kelvinRange: range)
        let source = $value
        let sliderValue = Binding<Double>(
            get: { mapping.sliderPosition(for: source.wrappedValue) },
            set: { source.wrappedValue = mapping.kelvinValue(for: $0) }
        )

        NeutralOriginSlider(
            value: sliderValue,
            in: TemperatureSliderMapping.sliderRange,
            neutral: mapping.sliderPosition(for: neutral),
            trackStyle: trackStyle,
            accessibilityTitle: accessibilityTitle,
            accessibilityReadout: accessibilityReadout,
            onEditingChanged: onEditingChanged
        )
    }
}

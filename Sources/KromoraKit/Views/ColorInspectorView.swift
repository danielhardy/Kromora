import SwiftUI

/// The photographer-facing colour surface.
///
/// Each major tool is a full-width disclosure section so the inspector remains useful at its narrow
/// dock width. Sliders and numeric fields share the same view-model binding; a slider drag uses the
/// preview coordinator's interactive quality while a committed field value follows the normal
/// debounced settled path.
struct ColorInspectorView: View {
    @ObservedObject var viewModel: AppViewModel

    @State private var whiteBalanceExpanded = true
    @State private var colorExpanded = true
    @State private var mixerExpanded = false
    @State private var gradingExpanded = false
    @State private var selectedMixerChannel: ColorMixerChannelName = .red

    var body: some View {
        InspectorScrollingContent {
            VStack(alignment: .leading, spacing: InspectorStyle.contentSpacing) {
                header
                whiteBalanceSection
                colorSection
                mixerSection
                gradingSection
            }
            .padding(InspectorStyle.contentInset)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Color adjustments")
    }

    private var header: some View {
        Text("Color")
            .font(InspectorStyle.panelTitle)
            .accessibilityAddTraits(.isHeader)
    }

    private var whiteBalanceSection: some View {
        InspectorDisclosure(
            "White Balance",
            isExpanded: $whiteBalanceExpanded
        ) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Menu("Preset") {
                        ForEach(WhiteBalancePreset.allCases) { preset in
                            Button(preset.rawValue) {
                                viewModel.applyWhiteBalancePreset(preset)
                            }
                        }
                    }
                    .disabled(viewModel.sourceIsRAW && viewModel.rawCapabilities == nil)
                    .accessibilityLabel("White balance preset")
                    Button {
                        if viewModel.isWhiteBalanceSampling {
                            viewModel.cancelWhiteBalanceSampling()
                        } else {
                            viewModel.beginWhiteBalanceSampling()
                        }
                    } label: {
                        Image(systemName: viewModel.isWhiteBalanceSampling ? "xmark" : "eyedropper")
                            .font(.system(size: 13, weight: .medium))
                            .frame(width: 24, height: 22)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(viewModel.isWhiteBalanceSampling
                        ? false
                        : viewModel.sourceImage == nil ||
                            (viewModel.sourceIsRAW && viewModel.rawCapabilities == nil))
                    .help(viewModel.isWhiteBalanceSampling ? "Cancel Sample" : "Sample Neutral")
                    .accessibilityLabel(viewModel.isWhiteBalanceSampling ? "Cancel white balance sample" : "Sample Neutral")
                    .accessibilityHint(viewModel.isWhiteBalanceSampling
                        ? "Cancel sampling a neutral area"
                        : "Click a neutral area in the photo; an 11 by 11 display pixel area is averaged")
                }

                if viewModel.isWhiteBalanceSampling {
                    Text("Click a neutral area in the photo to apply")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if viewModel.sourceIsRAW && viewModel.rawCapabilities == nil {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Reading the decoder's white balance…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    valueRow(
                        title: "Temperature",
                        value: viewModel.whiteBalanceBinding(for: .temperature),
                        range: viewModel.sourceIsRAW
                            ? DevelopControl.whiteBalance.range
                            : AdjustmentControl.temperature.range,
                        // A RAW's baseline is this file's as-shot Kelvin, not a round number;
                        // a standard image's is D65, which `sliderMapped` pins as the fixed point
                        // of the reflection the adjustment slider applies.
                        neutral: viewModel.sourceIsRAW
                            ? viewModel.developNeutral(for: .whiteBalance)
                            : AdjustmentControl.temperature.sliderMapped(
                                AdjustmentControl.temperature.neutral),
                        trackStyle: .temperature,
                        readout: temperatureReadout,
                        reset: { viewModel.resetWhiteBalance(.temperature) },
                        resetActionTitle: viewModel.sourceIsRAW ? "Reset to As Shot" : "Reset to neutral",
                        disabled: viewModel.sourceIsRAW && viewModel.rawCapabilities == nil,
                        usesTemperatureSlider: true
                    )
                    valueRow(
                        title: "Tint",
                        value: viewModel.whiteBalanceBinding(for: .tint),
                        range: viewModel.sourceIsRAW
                            ? DevelopControl.tintRange
                            : AdjustmentControl.tint.range,
                        neutral: viewModel.sourceIsRAW
                            ? viewModel.developTintNeutral
                            : AdjustmentControl.tint.neutral,
                        trackStyle: .tint,
                        readout: tintReadout,
                        fieldFormat: ColorSettingFormatting.signedWholeNumberFormat,
                        reset: { viewModel.resetWhiteBalance(.tint) },
                        resetActionTitle: viewModel.sourceIsRAW ? "Reset to As Shot" : "Reset to neutral",
                        disabled: viewModel.sourceIsRAW && viewModel.rawCapabilities == nil
                    )
                }
            }
            .padding(.top, 10)
        }
        .accessibilityLabel("White Balance")
    }

    private var colorSection: some View {
        InspectorDisclosure(
            "Adjustments",
            isExpanded: $colorExpanded
        ) {
            VStack(alignment: .leading, spacing: 12) {
                InspectorSectionResetButton(
                    title: "Reset Color",
                    disabled: !viewModel.hasColorAdjustments,
                    action: viewModel.resetAllColor
                )
                ForEach(ColorGlobalControl.allCases, id: \.self) { control in
                    valueRow(
                        title: control.title,
                        value: viewModel.colorBinding(for: control),
                        range: control.range,
                        neutral: control.neutral,
                        trackStyle: control.trackStyle,
                        readout: signedWholeReadout,
                        fieldFormat: ColorSettingFormatting.signedWholeNumberFormat,
                        reset: { viewModel.resetColor(control) }
                    )
                }
            }
            .padding(.top, 10)
        }
    }

    private var mixerSection: some View {
        InspectorDisclosure(
            "Color Mixer / HSL",
            isExpanded: $mixerExpanded
        ) {
            VStack(alignment: .leading, spacing: 12) {
                InspectorSectionResetButton(
                    title: "Reset Mixer",
                    disabled: !viewModel.hasMixerAdjustments,
                    action: viewModel.resetAllMixer
                )
                ColorMixerChannelStrip(
                    selected: $selectedMixerChannel,
                    isEdited: { !viewModel.mixerChannelValue($0).isIdentity }
                )
                ColorMixerChannelPanel(
                    channel: selectedMixerChannel,
                    hue: viewModel.mixerBinding(for: selectedMixerChannel, control: .hue),
                    saturation: viewModel.mixerBinding(for: selectedMixerChannel, control: .saturation),
                    luminance: viewModel.mixerBinding(for: selectedMixerChannel, control: .luminance),
                    isIdentity: viewModel.mixerChannelValue(selectedMixerChannel).isIdentity,
                    resetChannel: { viewModel.resetMixer(selectedMixerChannel) },
                    resetControl: { viewModel.resetMixer(selectedMixerChannel, $0) },
                    beginInteraction: viewModel.beginPreviewInteraction,
                    endInteraction: viewModel.endPreviewInteraction
                )
            }
            .padding(.top, 10)
        }
    }

    private var gradingSection: some View {
        InspectorDisclosure(
            "Color Grading",
            isExpanded: $gradingExpanded
        ) {
            VStack(alignment: .leading, spacing: 8) {
                InspectorSectionResetButton(
                    title: "Reset Grading",
                    disabled: !viewModel.hasGradingAdjustments,
                    action: viewModel.resetAllGrading
                )
                ForEach(ColorGradingZone.displayOrder, id: \.self) { zone in
                    ColorGradingZoneUnit(
                        title: zone.title,
                        wheel: viewModel.gradingWheelBinding(for: zone),
                        reset: { viewModel.resetGrading(zone) },
                        beginInteraction: viewModel.beginPreviewInteraction,
                        endInteraction: viewModel.endPreviewInteraction
                    )
                    if zone != .shadows {
                        Divider()
                            .padding(.horizontal, 12)
                    }
                }
                Divider()
                    .padding(.vertical, 4)
                Text("Tonal Range")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityAddTraits(.isHeader)
                ForEach(ColorGradingGlobalControl.allCases, id: \.self) { control in
                    valueRow(
                        title: control.title,
                        value: viewModel.gradingGlobalBinding(for: control),
                        range: control.range,
                        neutral: control.neutral,
                        readout: control == .blending ? unsignedWholeReadout : signedWholeReadout,
                        fieldFormat: gradingGlobalFieldFormat(for: control),
                        reset: { viewModel.resetGrading(control) }
                    )
                }
            }
            .padding(.top, 8)
        }
    }

    private func valueRow(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        neutral: Double,
        trackStyle: SliderTrackStyle = .neutral,
        readout: @escaping (Double) -> String,
        fieldFormat: FloatingPointFormatStyle<Double> = ColorSettingFormatting.wholeNumberFormat,
        reset: @escaping () -> Void,
        resetActionTitle: String = "Reset to neutral",
        disabled: Bool = false,
        usesTemperatureSlider: Bool = false
    ) -> some View {
        ColorValueRow(
            title: title,
            value: value,
            range: range,
            neutral: neutral,
            trackStyle: trackStyle,
            readout: readout,
            fieldFormat: fieldFormat,
            reset: reset,
            resetActionTitle: resetActionTitle,
            beginInteraction: viewModel.beginPreviewInteraction,
            endInteraction: viewModel.endPreviewInteraction,
            usesTemperatureSlider: usesTemperatureSlider
        )
        .disabled(disabled)
    }

    private var temperatureReadout: (Double) -> String {
        ColorSettingFormatting.temperature
    }

    private var tintReadout: (Double) -> String {
        ColorSettingFormatting.tint
    }

    private var signedWholeReadout: (Double) -> String {
        { value in String(format: "%+.0f", value) }
    }

    private var unsignedWholeReadout: (Double) -> String {
        { value in String(format: "%.0f", value) }
    }

    private func gradingGlobalFieldFormat(
        for control: ColorGradingGlobalControl
    ) -> FloatingPointFormatStyle<Double> {
        control == .balance
            ? ColorSettingFormatting.signedWholeNumberFormat
            : ColorSettingFormatting.wholeNumberFormat
    }

}

/// Eight hue-neighborhood chips. Selection is view-local; an edit dot marks non-identity channels.
private struct ColorMixerChannelStrip: View {
    @Binding var selected: ColorMixerChannelName
    let isEdited: (ColorMixerChannelName) -> Bool

    private let chipDiameter: CGFloat = 22

    var body: some View {
        HStack(spacing: 0) {
            ForEach(ColorMixerChannelName.allCases, id: \.self) { channel in
                Button {
                    selected = channel
                } label: {
                    ZStack(alignment: .bottomTrailing) {
                        Circle()
                            .fill(channel.swatchColor)
                            .frame(width: chipDiameter, height: chipDiameter)
                            .overlay(
                                Circle()
                                    .strokeBorder(
                                        selected == channel
                                            ? KromoraTheme.primaryAccent
                                            : Color.primary.opacity(0.18),
                                        lineWidth: selected == channel ? 2 : 1
                                    )
                            )
                            .shadow(
                                color: selected == channel
                                    ? KromoraTheme.primaryAccent.opacity(0.35)
                                    : .clear,
                                radius: 2
                            )

                        if isEdited(channel) {
                            Circle()
                                .fill(KromoraTheme.primaryAccent)
                                .frame(width: 6, height: 6)
                                .overlay(
                                    Circle().stroke(Color.black.opacity(0.35), lineWidth: 0.5)
                                )
                                .offset(x: 2, y: 2)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(channel.title)
                .accessibilityLabel("\(channel.title) mixer channel")
                .accessibilityValue(selected == channel ? "Selected" : "Not selected")
                .accessibilityAddTraits(selected == channel ? .isSelected : [])
                .accessibilityHint(
                    isEdited(channel)
                        ? "Edited. Shows Hue, Saturation, and Luminance for this color."
                        : "Shows Hue, Saturation, and Luminance for this color."
                )
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Color mixer channels")
    }
}

/// Focused Hue / Saturation / Luminance controls for one mixer channel.
private struct ColorMixerChannelPanel: View {
    let channel: ColorMixerChannelName
    @Binding var hue: Double
    @Binding var saturation: Double
    @Binding var luminance: Double
    let isIdentity: Bool
    let resetChannel: () -> Void
    let resetControl: (ColorMixerControl) -> Void
    let beginInteraction: () -> Void
    let endInteraction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle()
                    .fill(channel.swatchColor)
                    .frame(width: 10, height: 10)
                    .overlay(Circle().stroke(Color.primary.opacity(0.2), lineWidth: 0.75))
                Text(channel.title)
                    .font(.subheadline.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                Button(action: resetChannel) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(isIdentity)
                .help("Reset \(channel.title)")
                .accessibilityLabel("Reset \(channel.title) mixer channel")
                .accessibilityHint("Restore Hue, Saturation, and Luminance for this color to neutral.")
            }

            ColorValueRow(
                title: "\(channel.title) Hue",
                value: $hue,
                range: ColorMixerControl.hue.range,
                neutral: ColorMixerControl.hue.neutral,
                trackStyle: ColorMixerControl.hue.trackStyle(for: channel),
                readout: { String(format: "%+.0f", $0) },
                fieldFormat: ColorSettingFormatting.signedWholeNumberFormat,
                reset: { resetControl(.hue) },
                resetActionTitle: "Reset to neutral",
                beginInteraction: beginInteraction,
                endInteraction: endInteraction,
                usesTemperatureSlider: false
            )
            ColorValueRow(
                title: "\(channel.title) Saturation",
                value: $saturation,
                range: ColorMixerControl.saturation.range,
                neutral: ColorMixerControl.saturation.neutral,
                trackStyle: ColorMixerControl.saturation.trackStyle(for: channel),
                readout: { String(format: "%+.0f", $0) },
                fieldFormat: ColorSettingFormatting.signedWholeNumberFormat,
                reset: { resetControl(.saturation) },
                resetActionTitle: "Reset to neutral",
                beginInteraction: beginInteraction,
                endInteraction: endInteraction,
                usesTemperatureSlider: false
            )
            ColorValueRow(
                title: "\(channel.title) Luminance",
                value: $luminance,
                range: ColorMixerControl.luminance.range,
                neutral: ColorMixerControl.luminance.neutral,
                trackStyle: ColorMixerControl.luminance.trackStyle(for: channel),
                readout: { String(format: "%+.0f", $0) },
                fieldFormat: ColorSettingFormatting.signedWholeNumberFormat,
                reset: { resetControl(.luminance) },
                resetActionTitle: "Reset to neutral",
                beginInteraction: beginInteraction,
                endInteraction: endInteraction,
                usesTemperatureSlider: false
            )
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(channel.title) color mixer")
    }
}

/// Shared slider + numeric-entry row. The full contextual title is applied to both controls so
/// VoiceOver can distinguish repeated Hue/Saturation/Luminance labels across channels and wheels.
private struct ColorValueRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    /// Where this row's fill is anchored — see `SliderFill`.
    let neutral: Double
    let trackStyle: SliderTrackStyle
    let readout: (Double) -> String
    let fieldFormat: FloatingPointFormatStyle<Double>
    let reset: () -> Void
    let resetActionTitle: String
    let beginInteraction: () -> Void
    let endInteraction: () -> Void
    let usesTemperatureSlider: Bool

    var body: some View {
        let wholeNumberValue = Binding<Double>(
            get: { value.rounded() },
            set: { value = $0.rounded() }
        )

        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                ResettableAdjustmentLabel(
                    title: title,
                    reset: reset,
                    resetActionTitle: resetActionTitle
                )
                Spacer()
                TextField(title, value: wholeNumberValue, format: fieldFormat)
                .textFieldStyle(.roundedBorder)
                .font(.system(.caption, design: .monospaced))
                .frame(width: 68)
                .multilineTextAlignment(.trailing)
                .accessibilityLabel(title)
                .accessibilityValue(readout(value))
                .accessibilitySortPriority(1)
            }

            Group {
                if usesTemperatureSlider {
                    TemperatureSlider(
                        value: wholeNumberValue,
                        in: range,
                        neutral: neutral,
                        trackStyle: trackStyle,
                        accessibilityTitle: title,
                        accessibilityReadout: readout(value),
                        onEditingChanged: { editing in
                            if editing { beginInteraction() } else { endInteraction() }
                        }
                    )
                } else {
                    NeutralOriginSlider(
                        value: wholeNumberValue,
                        in: range,
                        neutral: neutral,
                        step: 1,
                        trackStyle: trackStyle,
                        accessibilityTitle: title,
                        accessibilityReadout: readout(value),
                        onEditingChanged: { editing in
                            if editing { beginInteraction() } else { endInteraction() }
                        }
                    )
                }
            }
            .accessibilityLabel(title)
            .accessibilityValue(readout(value))
            .accessibilitySortPriority(0)
            .accessibilityAction(named: Text(resetActionTitle), reset)
        }
    }
}

/// The rasterized hue field, with each pixel mapped through the persisted wheel convention.
struct ColorGradingWheelDisc: View {
    private static let rasterSide = 512
    private static let rasterImage = makeRasterImage()

    var body: some View {
        Canvas { context, size in
            let diameter = min(size.width, size.height)
            guard diameter > 0 else { return }

            let rect = CGRect(
                x: (size.width - diameter) / 2,
                y: (size.height - diameter) / 2,
                width: diameter,
                height: diameter
            )
            context.draw(Image(decorative: Self.rasterImage, scale: 1), in: rect)
        }
        .accessibilityHidden(true)
    }

    private static func makeRasterImage() -> CGImage {
        let side = rasterSide
        let center = Double(side) / 2
        let radius = center
        var pixels = [UInt8](repeating: 0, count: side * side * 4)

        for row in 0..<side {
            for column in 0..<side {
                let point = ColorGradingWheelPoint(
                    x: (Double(column) + 0.5 - center) / radius,
                    y: (center - Double(row) - 0.5) / radius
                )
                let wheel = ColorGradingWheelMapping.wheel(at: point)

                let distance = hypot(point.x, point.y)
                guard distance <= 1 else { continue }

                let hueColor = ColorGradingWheelPalette.rgb(forHueDegrees: wheel.hue)
                let neutral = 0.14 + 0.36 * distance
                let hueStrength = pow(distance, 0.35)
                let color = ColorGradingWheelRGB(
                    red: neutral + (hueColor.red - neutral) * hueStrength,
                    green: neutral + (hueColor.green - neutral) * hueStrength,
                    blue: neutral + (hueColor.blue - neutral) * hueStrength
                )
                let offset = (row * side + column) * 4
                pixels[offset] = UInt8((color.red * 255).rounded())
                pixels[offset + 1] = UInt8((color.green * 255).rounded())
                pixels[offset + 2] = UInt8((color.blue * 255).rounded())
                pixels[offset + 3] = 255
            }
        }

        let data = Data(pixels)
        guard let provider = CGDataProvider(data: data as CFData),
            let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
            let image = CGImage(
                width: side,
                height: side,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: side * 4,
                space: colorSpace,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: true,
                intent: .defaultIntent
            )
        else {
            preconditionFailure("Could not create the color-grading wheel palette image")
        }
        return image
    }
}

/// One Photos-style three-way grading unit. The wheel edits hue and saturation together; the
/// flanking arcs provide precise single-axis controls for those same persisted values.
private struct ColorGradingZoneUnit: View {
    let title: String
    @Binding var wheel: ColorGradingWheel
    let reset: () -> Void
    let beginInteraction: () -> Void
    let endInteraction: () -> Void

    private let wheelDiameter: CGFloat = 112
    private let arcWidth: CGFloat = 22
    private let arcHeight: CGFloat = 112

    var body: some View {
        VStack(spacing: 4) {
            // Balance a trailing reset so the wheel unit stays centered and the
            // control sits outside the arcs (Photos Color Balance placement).
            HStack(alignment: .top, spacing: 4) {
                Color.clear
                    .frame(width: 24, height: 24)

                HStack(spacing: 7) {
                    ColorGradingArcSlider(
                        title: title,
                        control: .saturation,
                        side: .left,
                        wheel: $wheel,
                        beginInteraction: beginInteraction,
                        endInteraction: endInteraction
                    )
                    .frame(width: arcWidth, height: arcHeight)

                    ColorGradingWheelControl(
                        title: title,
                        wheel: $wheel,
                        reset: reset,
                        beginInteraction: beginInteraction,
                        endInteraction: endInteraction
                    )
                    .frame(width: wheelDiameter, height: wheelDiameter)

                    ColorGradingArcSlider(
                        title: title,
                        control: .hue,
                        side: .right,
                        wheel: $wheel,
                        beginInteraction: beginInteraction,
                        endInteraction: endInteraction
                    )
                    .frame(width: arcWidth, height: arcHeight)
                }

                Button(action: reset) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(wheel.isIdentity)
                .help("Reset \(title) color grading")
                .accessibilityLabel("Reset \(title) color grading")
                .accessibilityHint("Restore this color grading wheel to neutral.")
            }

            Text(title)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .accessibilityAddTraits(.isHeader)
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(title) color grading")
    }
}

private enum ColorGradingArcSide {
    case left, right

    var bowsOutwardLeft: Bool { self == .left }
}

private enum ColorGradingArcControl {
    case saturation, hue

    var range: ClosedRange<Double> {
        switch self {
        case .saturation: return ColorGradingWheel.saturationRange
        case .hue: return ColorGradingWheel.hueRange
        }
    }

    var title: String {
        switch self {
        case .saturation: return "Saturation"
        case .hue: return "Hue"
        }
    }

    var step: Double {
        switch self {
        case .saturation: return 5
        case .hue: return 5
        }
    }

    func value(in wheel: ColorGradingWheel) -> Double {
        switch self {
        case .saturation: return wheel.saturation
        case .hue: return wheel.hue
        }
    }

    func setting(_ value: Double, in wheel: inout ColorGradingWheel) {
        switch self {
        case .saturation: wheel.saturation = value
        case .hue: wheel.hue = value
        }
    }

    func formattedValue(_ value: Double) -> String {
        switch self {
        case .saturation: return "\(Int(value.rounded())) percent"
        case .hue: return "\(Int(value.rounded())) degrees"
        }
    }

    var accessibilityHint: String {
        switch self {
        case .saturation:
            return "Drag vertically to set this zone's saturation from 0 to 100 percent. The wheel also changes saturation."
        case .hue:
            return "Drag vertically to set this zone's hue from 0 to 360 degrees. The wheel also changes hue."
        }
    }
}

/// Shared bronze thumb — same accent family as `NeutralOriginSlider`'s knob.
private struct ColorGradingControlThumb: View {
    var diameter: CGFloat = 10

    var body: some View {
        Circle()
            .fill(KromoraTheme.primaryAccent)
            .frame(width: diameter, height: diameter)
            .overlay(
                Circle()
                    .stroke(
                        Color.black.opacity(0.35),
                        lineWidth: max(0.75, diameter * 0.045)
                    )
            )
            .shadow(color: .black.opacity(0.28), radius: 1)
            .allowsHitTesting(false)
    }
}

/// The curved side controls map directly to the existing per-zone hue and saturation values.
private struct ColorGradingArcSlider: View {
    let title: String
    let control: ColorGradingArcControl
    let side: ColorGradingArcSide
    @Binding var wheel: ColorGradingWheel
    let beginInteraction: () -> Void
    let endInteraction: () -> Void

    /// Matches `NeutralOriginSliderCell.barThickness`.
    private static let trackThickness: CGFloat = 4

    @State private var isDragging = false

    private var value: Double { control.value(in: wheel) }
    private var normalizedValue: CGFloat {
        let range = control.range
        return CGFloat((value - range.lowerBound) / (range.upperBound - range.lowerBound))
    }
    private var selectedHueColor: Color {
        let rgb = ColorGradingWheelPalette.rgb(forHueDegrees: wheel.hue)
        return Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }

    var body: some View {
        GeometryReader { proxy in
            let inset: CGFloat = 5
            let trackHeight = max(proxy.size.height - inset * 2, 1)
            let thumbPosition = point(
                at: 1 - normalizedValue,
                width: proxy.size.width,
                height: trackHeight,
                inset: inset
            )
            let neutralPosition = point(
                at: 1,
                width: proxy.size.width,
                height: trackHeight,
                inset: inset
            )

            ZStack {
                // Match NeutralOriginSlider's 4pt track so arc and linear rows read as one family.
                ColorGradingArcShape(bowsOutwardLeft: side.bowsOutwardLeft)
                    .stroke(
                        .primary.opacity(0.22),
                        style: StrokeStyle(lineWidth: Self.trackThickness, lineCap: .round)
                    )

                ColorGradingArcShape(bowsOutwardLeft: side.bowsOutwardLeft)
                    .trim(from: 1 - normalizedValue, to: 1)
                    .stroke(
                        selectedHueColor.opacity(control == .saturation ? 0.95 : 0.65),
                        style: StrokeStyle(lineWidth: Self.trackThickness, lineCap: .round)
                    )

                Rectangle()
                    .fill(.primary.opacity(0.28))
                    .frame(width: 5, height: 1)
                    .position(neutralPosition)

                ColorGradingControlThumb()
                    .position(thumbPosition)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { gesture in
                        if !isDragging {
                            isDragging = true
                            beginInteraction()
                        }
                        setValue(at: gesture.location.y, height: proxy.size.height, inset: inset)
                    }
                    .onEnded { _ in
                        isDragging = false
                        endInteraction()
                    }
            )
            .accessibilityElement()
            .accessibilityLabel("\(title) \(control.title)")
            .accessibilityValue(control.formattedValue(value))
            .accessibilityHint(control.accessibilityHint)
            .accessibilityAdjustableAction { direction in
                beginInteraction()
                let amount = direction == .increment ? control.step : -control.step
                setValue(value + amount)
                endInteraction()
            }
        }
        .accessibilitySortPriority(control == .saturation ? 1 : -1)
    }

    private func point(
        at progress: CGFloat,
        width: CGFloat,
        height: CGFloat,
        inset: CGFloat
    ) -> CGPoint {
        let startX = width * (side == .left ? 0.80 : 0.20)
        let controlX = width * (side == .left ? 0.08 : 0.92)
        let endX = startX
        let yProgress = progress.clamped(to: 0...1, default: 0)
        let inverse = 1 - yProgress
        let x = inverse * inverse * startX
            + 2 * inverse * yProgress * controlX
            + yProgress * yProgress * endX
        return CGPoint(x: x, y: inset + height * yProgress)
    }

    private func setValue(at y: CGFloat, height: CGFloat, inset: CGFloat) {
        let progress = 1 - (y - inset) / max(height - inset * 2, 1)
        let fraction = Double(progress.clamped(to: 0...1, default: 0))
        let range = control.range
        setValue(range.lowerBound + fraction * (range.upperBound - range.lowerBound))
    }

    private func setValue(_ value: Double) {
        var updated = wheel
        control.setting(value, in: &updated)
        wheel = updated
    }
}

private struct ColorGradingArcShape: Shape {
    let bowsOutwardLeft: Bool

    func path(in rect: CGRect) -> Path {
        let endInset = min(5, rect.height / 8)
        let startX = rect.width * (bowsOutwardLeft ? 0.80 : 0.20)
        let controlX = rect.width * (bowsOutwardLeft ? 0.08 : 0.92)
        var path = Path()
        path.move(to: CGPoint(x: startX, y: endInset))
        path.addQuadCurve(
            to: CGPoint(x: startX, y: rect.height - endInset),
            control: CGPoint(x: controlX, y: rect.midY)
        )
        return path
    }
}

/// A compact hue/saturation wheel. The model owns the polar conversion so wheel and arc edits
/// always round-trip through the same stored values.
private struct ColorGradingWheelControl: View {
    let title: String
    @Binding var wheel: ColorGradingWheel
    let reset: () -> Void
    let beginInteraction: () -> Void
    let endInteraction: () -> Void

    @State private var isDragging = false

    var body: some View {
        GeometryReader { proxy in
            let diameter = min(proxy.size.width, proxy.size.height)
            let indicatorPoint = ColorGradingWheelMapping.point(for: wheel)
            let indicatorOffset = CGSize(
                width: indicatorPoint.x * diameter / 2,
                height: -indicatorPoint.y * diameter / 2
            )
            ZStack {
                ColorGradingWheelDisc()
                    .clipShape(Circle())
                Circle()
                    .stroke(.white.opacity(0.28), lineWidth: 0.75)
                Path { path in
                    path.move(to: CGPoint(x: diameter / 2 - 5, y: diameter / 2))
                    path.addLine(to: CGPoint(x: diameter / 2 + 5, y: diameter / 2))
                    path.move(to: CGPoint(x: diameter / 2, y: diameter / 2 - 5))
                    path.addLine(to: CGPoint(x: diameter / 2, y: diameter / 2 + 5))
                }
                .stroke(.white.opacity(0.35), lineWidth: 0.8)
                ColorGradingControlThumb(diameter: 12)
                    .offset(indicatorOffset)
            }
            .frame(width: diameter, height: diameter)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        if !isDragging {
                            isDragging = true
                            beginInteraction()
                        }
                        wheel = ColorGradingWheelMapping.wheel(
                            at: point(for: value.location, in: proxy.size)
                        )
                    }
                    .onEnded { _ in
                        isDragging = false
                        endInteraction()
                    }
            )
            .accessibilityElement()
            .accessibilityLabel("\(title) color grading wheel")
            .accessibilityValue(ColorGradingWheelMapping.accessibilityValue(for: wheel))
            .accessibilityHint(
                "Drag in the wheel to set hue and saturation. Use the left arc for saturation and the right arc for hue."
            )
            .accessibilityAdjustableAction { direction in
                beginInteraction()
                let amount = direction == .increment
                    ? ColorGradingWheelMapping.accessibilityStep
                    : -ColorGradingWheelMapping.accessibilityStep
                wheel = ColorGradingWheelMapping.adjustingSaturation(wheel, by: amount)
                endInteraction()
            }
            .accessibilityAction(named: Text("Reset to neutral"), reset)
        }
    }

    private func point(for location: CGPoint, in size: CGSize) -> ColorGradingWheelPoint {
        let radius = max(min(size.width, size.height) / 2, 1)
        return ColorGradingWheelPoint(
            x: (location.x - size.width / 2) / radius,
            y: (size.height / 2 - location.y) / radius
        )
    }
}

import SwiftUI

/// The photographer-facing global Effects inspector.
///
/// All rows use the same value-state bindings as the render pipeline. Slider ticks take the
/// interactive quality path and a gesture becomes one undo entry; numeric edits and resets retain
/// the existing settled/debounced behavior from `AppViewModel`.
struct EffectsInspectorView: View {
    @ObservedObject var viewModel: AppViewModel

    @State private var detailExpanded = true
    @State private var sharpeningExpanded = true
    @State private var noiseExpanded = false
    @State private var vignetteExpanded = false
    @State private var grainExpanded = false

    var body: some View {
        InspectorScrollingContent {
            VStack(alignment: .leading, spacing: InspectorStyle.contentSpacing) {
                header
                detailSection
                sharpeningSection
                noiseSection
                vignetteSection
                grainSection
            }
            .padding(InspectorStyle.contentInset)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Effects adjustments")
    }

    private var header: some View {
        HStack {
            Text("Effects")
                .font(InspectorStyle.panelTitle)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Button("Reset Effects") { viewModel.resetAllEffects() }
                .buttonStyle(.link)
                .disabled(!viewModel.hasEffects)
                .accessibilityHint("Reset detail, noise, sharpening, Vignette, and Grain")
        }
    }

    private var sharpeningSection: some View {
        InspectorDisclosure("Sharpening", isExpanded: $sharpeningExpanded) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach([DetailControl.sharpeningAmount, .sharpeningRadius, .sharpeningDetail, .sharpeningMasking], id: \.self) { control in
                    detailRow(control)
                }
                Text("Masking protects smooth areas; higher values restrict sharpening to stronger edges.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .padding(.top, 10)
        }
    }

    private var noiseSection: some View {
        InspectorDisclosure("Noise Reduction", isExpanded: $noiseExpanded) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach([DetailControl.luminanceNoise, .luminanceDetail, .luminanceContrast, .colorNoise, .colorDetail, .colorContrast], id: \.self) { control in
                    detailRow(control)
                }
            }
            .padding(.top, 10)
        }
    }

    private func detailRow(_ control: DetailControl) -> some View {
        valueRow(
            title: control.title,
            value: viewModel.detailBinding(for: control),
            range: control.range,
            neutral: control.neutral,
            readout: { value in control == .sharpeningRadius ? String(format: "%.1f px", value) : String(format: "%.0f", value) },
            reset: { viewModel.resetDetail(control) }
        )
    }

    private var detailSection: some View {
        InspectorDisclosure("Texture / Clarity / Dehaze", isExpanded: $detailExpanded) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(EffectsControl.allCases, id: \.self) { control in
                    valueRow(
                        title: control.title,
                        value: viewModel.effectsBinding(for: control),
                        range: control.range,
                        neutral: control.neutral,
                        readout: signedWholeReadout,
                        reset: { viewModel.resetEffects(control) }
                    )
                }
            }
            .padding(.top, 10)
        }
    }

    private var vignetteSection: some View {
        InspectorDisclosure("Vignette", isExpanded: $vignetteExpanded) {
            VStack(alignment: .leading, spacing: 12) {
                InspectorSectionResetButton(
                    title: "Reset Vignette",
                    disabled: !viewModel.hasVignetteAdjustments,
                    action: viewModel.resetAllVignette
                )
                ForEach(VignetteControl.allCases, id: \.self) { control in
                    valueRow(
                        title: control.title,
                        value: viewModel.vignetteBinding(for: control),
                        range: control.range,
                        // Midpoint and Feather default to 50 in 0…100, so their fill is centred
                        // even though their ranges are unsigned. `VignetteControl.neutral` is the
                        // authority — the same value `resetVignette(_:)` writes.
                        neutral: control.neutral,
                        readout: control == .amount || control == .roundness
                            ? signedWholeReadout : unsignedWholeReadout,
                        reset: { viewModel.resetVignette(control) }
                    )
                }
            }
            .padding(.top, 10)
        }
    }

    private var grainSection: some View {
        InspectorDisclosure("Grain", isExpanded: $grainExpanded) {
            VStack(alignment: .leading, spacing: 12) {
                InspectorSectionResetButton(
                    title: "Reset Grain",
                    disabled: !viewModel.hasGrainAdjustments,
                    action: viewModel.resetAllGrain
                )
                ForEach(GrainControl.allCases, id: \.self) { control in
                    valueRow(
                        title: control.title,
                        value: viewModel.grainBinding(for: control),
                        range: control.range,
                        neutral: control.neutral,
                        readout: unsignedWholeReadout,
                        reset: { viewModel.resetGrain(control) }
                    )
                }
            }
            .padding(.top, 10)
        }
    }

    private func valueRow(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        neutral: Double,
        readout: @escaping (Double) -> String,
        reset: @escaping () -> Void
    ) -> some View {
        EffectsValueRow(
            title: title,
            value: value,
            range: range,
            neutral: neutral,
            readout: readout,
            reset: reset,
            beginInteraction: viewModel.beginPreviewInteraction,
            endInteraction: viewModel.endPreviewInteraction
        )
    }

    private var signedWholeReadout: (Double) -> String {
        { value in String(format: "%+.0f", value) }
    }

    private var unsignedWholeReadout: (Double) -> String {
        { value in String(format: "%.0f", value) }
    }
}

private struct EffectsValueRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    /// Where this row's fill is anchored — see `SliderFill`.
    let neutral: Double
    let readout: (Double) -> String
    let reset: () -> Void
    let beginInteraction: () -> Void
    let endInteraction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                ResettableAdjustmentLabel(title: title, reset: reset)
                Spacer()
                TextField(title, value: $value, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.caption, design: .monospaced))
                    .frame(width: 68)
                    .multilineTextAlignment(.trailing)
                    .accessibilityLabel(title)
                    .accessibilityValue(readout(value))
                    .accessibilitySortPriority(1)
            }

            NeutralOriginSlider(
                value: $value,
                in: range,
                neutral: neutral,
                step: 1,
                accessibilityTitle: title,
                accessibilityReadout: readout(value),
                onEditingChanged: { editing in
                    if editing { beginInteraction() }
                    else { endInteraction() }
                }
            )
            .accessibilityLabel(title)
            .accessibilityValue(readout(value))
            .accessibilitySortPriority(0)
            .accessibilityAction(named: Text("Reset to neutral"), reset)
        }
    }
}

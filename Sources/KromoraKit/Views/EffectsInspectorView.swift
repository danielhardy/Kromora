import SwiftUI

/// The photographer-facing global Effects inspector.
///
/// One flat list: every primary control is always visible, with no accordions. A control that has
/// refinements carries an icon beside its label; opening it slides a full-width band of the
/// advanced controls open beneath that row. All rows use the same value-state bindings as the
/// render pipeline. Slider ticks take the interactive quality path and a gesture becomes one undo
/// entry; numeric edits and resets retain the existing settled/debounced behavior from
/// `AppViewModel`.
struct EffectsInspectorView: View {
    @ObservedObject var viewModel: AppViewModel

    @State private var sharpeningAdvancedExpanded = false
    @State private var noiseAdvancedExpanded = false
    @State private var vignetteAdvancedExpanded = false
    @State private var grainAdvancedExpanded = false

    private static let sharpeningAdvanced: [DetailControl] = [.sharpeningRadius, .sharpeningDetail, .sharpeningMasking]
    private static let noiseAdvanced: [DetailControl] = [.luminanceDetail, .luminanceContrast, .colorDetail, .colorContrast]
    private static let vignetteAdvanced: [VignetteControl] = [.midpoint, .roundness, .feather, .highlights]
    private static let grainAdvanced: [GrainControl] = [.size, .roughness]

    var body: some View {
        InspectorScrollingContent {
            VStack(alignment: .leading, spacing: InspectorStyle.contentSpacing) {
                header
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
                sharpeningRow
                vignetteRow
                grainRow
                noiseGroup
            }
            .padding(InspectorStyle.contentInset)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Effects adjustments")
        .onChange(of: viewModel.document.effects, initial: true) { _, _ in
            if sharpeningHasAdvancedAdjustments { sharpeningAdvancedExpanded = true }
            if noiseHasAdvancedAdjustments { noiseAdvancedExpanded = true }
            if vignetteHasAdvancedAdjustments { vignetteAdvancedExpanded = true }
            if grainHasAdvancedAdjustments { grainAdvancedExpanded = true }
        }
    }

    private var header: some View {
        HStack {
            Text("Effects")
                .font(InspectorStyle.panelTitle)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            ResetIconButton(
                "Reset Effects",
                accessibilityHint: "Reset detail, noise, sharpening, Vignette, and Grain",
                disabled: !viewModel.hasEffects,
                action: viewModel.resetAllEffects
            )
        }
    }

    // MARK: Rows with advanced controls

    private var sharpeningRow: some View {
        VStack(alignment: .leading, spacing: 0) {
            valueRow(
                title: "Sharpening",
                value: viewModel.detailBinding(for: .sharpeningAmount),
                range: DetailControl.sharpeningAmount.range,
                neutral: DetailControl.sharpeningAmount.neutral,
                readout: unsignedWholeReadout,
                reset: { viewModel.resetDetail(.sharpeningAmount) },
                accessory: advancedToggle(
                    "Sharpening", isExpanded: $sharpeningAdvancedExpanded,
                    isModified: sharpeningHasAdvancedAdjustments
                )
            )
            if sharpeningAdvancedExpanded {
                InspectorAdvancedBand(
                    title: "Sharpening",
                    resetEnabled: sharpeningHasAdvancedAdjustments,
                    reset: viewModel.resetSharpeningAdvanced
                ) {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Self.sharpeningAdvanced, id: \.self) { detailRow($0) }
                        Text("Masking protects smooth areas; higher values restrict sharpening to stronger edges.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var vignetteRow: some View {
        VStack(alignment: .leading, spacing: 0) {
            valueRow(
                title: "Vignette",
                value: viewModel.vignetteBinding(for: .amount),
                range: VignetteControl.amount.range,
                neutral: VignetteControl.amount.neutral,
                readout: signedWholeReadout,
                reset: { viewModel.resetVignette(.amount) },
                accessory: advancedToggle(
                    "Vignette", isExpanded: $vignetteAdvancedExpanded,
                    isModified: vignetteHasAdvancedAdjustments
                )
            )
            if vignetteAdvancedExpanded {
                InspectorAdvancedBand(
                    title: "Vignette",
                    resetEnabled: vignetteHasAdvancedAdjustments,
                    reset: viewModel.resetVignetteAdvanced
                ) {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Self.vignetteAdvanced, id: \.self) { vignetteControlRow($0) }
                    }
                }
            }
        }
    }

    private var grainRow: some View {
        VStack(alignment: .leading, spacing: 0) {
            valueRow(
                title: "Grain",
                value: viewModel.grainBinding(for: .amount),
                range: GrainControl.amount.range,
                neutral: GrainControl.amount.neutral,
                readout: unsignedWholeReadout,
                reset: { viewModel.resetGrain(.amount) },
                accessory: advancedToggle(
                    "Grain", isExpanded: $grainAdvancedExpanded,
                    isModified: grainHasAdvancedAdjustments
                )
            )
            if grainAdvancedExpanded {
                InspectorAdvancedBand(
                    title: "Grain",
                    resetEnabled: grainHasAdvancedAdjustments,
                    reset: viewModel.resetGrainAdvanced
                ) {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Self.grainAdvanced, id: \.self) { grainControlRow($0) }
                    }
                }
            }
        }
    }

    /// Noise Reduction has two primary sliders, so it keeps a small heading: the Advanced icon
    /// beside its name and a reset for the whole group.
    private var noiseGroup: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Text("Noise Reduction")
                        .font(InspectorStyle.nestedSectionTitle)
                        .accessibilityAddTraits(.isHeader)
                    advancedToggle(
                        "Noise Reduction", isExpanded: $noiseAdvancedExpanded,
                        isModified: noiseHasAdvancedAdjustments
                    )
                    Spacer()
                    ResetIconButton(
                        "Reset Noise Reduction",
                        disabled: !viewModel.hasNoiseAdjustments,
                        action: viewModel.resetAllNoiseReduction
                    )
                }
                detailRow(.luminanceNoise, title: "Luminance")
                detailRow(.colorNoise, title: "Color")
            }
            if noiseAdvancedExpanded {
                InspectorAdvancedBand(
                    title: "Noise Reduction",
                    resetEnabled: noiseHasAdvancedAdjustments,
                    reset: viewModel.resetNoiseAdvanced
                ) {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Self.noiseAdvanced, id: \.self) { detailRow($0) }
                    }
                }
            }
        }
        .padding(.top, 6)
    }

    // MARK: Row builders

    private func detailRow(_ control: DetailControl, title: String? = nil) -> some View {
        valueRow(
            title: title ?? control.title,
            value: viewModel.detailBinding(for: control),
            range: control.range,
            neutral: control.neutral,
            readout: { value in control == .sharpeningRadius ? String(format: "%.1f px", value) : String(format: "%.0f", value) },
            reset: { viewModel.resetDetail(control) }
        )
    }

    private func vignetteControlRow(_ control: VignetteControl) -> some View {
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

    private func grainControlRow(_ control: GrainControl) -> some View {
        valueRow(
            title: control.title,
            value: viewModel.grainBinding(for: control),
            range: control.range,
            neutral: control.neutral,
            readout: unsignedWholeReadout,
            reset: { viewModel.resetGrain(control) }
        )
    }

    private var sharpeningHasAdvancedAdjustments: Bool {
        Self.sharpeningAdvanced.contains { $0.value(in: viewModel.document.effects.detail) != $0.neutral }
    }

    private var noiseHasAdvancedAdjustments: Bool {
        Self.noiseAdvanced.contains { $0.value(in: viewModel.document.effects.detail) != $0.neutral }
    }

    private var vignetteHasAdvancedAdjustments: Bool {
        Self.vignetteAdvanced.contains { $0.value(in: viewModel.document.effects.vignette) != $0.neutral }
    }

    private var grainHasAdvancedAdjustments: Bool {
        Self.grainAdvanced.contains { $0.value(in: viewModel.document.effects.grain) != $0.neutral }
    }

    /// An icon beside the control's label. A dot marks advanced values that differ from neutral
    /// while the band is closed.
    private func advancedToggle(
        _ section: String,
        isExpanded: Binding<Bool>,
        isModified: Bool
    ) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.25)) {
                isExpanded.wrappedValue.toggle()
            }
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 11, weight: .medium))
                .frame(width: 24, height: 24)
                .overlay(alignment: .topTrailing) {
                    if isModified && !isExpanded.wrappedValue {
                        Circle().fill(KromoraTheme.primaryAccent).frame(width: 5, height: 5)
                            .padding(3)
                            .accessibilityHidden(true)
                    }
                }
        }
        .buttonStyle(InspectorIconButtonStyle(isActive: isExpanded.wrappedValue))
        .help("\(isExpanded.wrappedValue ? "Hide" : "Show") advanced \(section) controls")
        .accessibilityLabel("Advanced \(section) controls")
        .accessibilityValue(isExpanded.wrappedValue ? "Expanded" : "Collapsed")
        .accessibilityHint("Show or hide advanced \(section) controls")
        .accessibilityAddTraits(.isToggle)
    }

    private func valueRow<Accessory: View>(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        neutral: Double,
        readout: @escaping (Double) -> String,
        reset: @escaping () -> Void,
        accessory: Accessory
    ) -> some View {
        EffectsValueRow(
            title: title,
            value: value,
            range: range,
            neutral: neutral,
            readout: readout,
            reset: reset,
            beginInteraction: viewModel.beginPreviewInteraction,
            endInteraction: viewModel.endPreviewInteraction,
            accessory: accessory
        )
    }

    private func valueRow(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        neutral: Double,
        readout: @escaping (Double) -> String,
        reset: @escaping () -> Void
    ) -> some View {
        valueRow(
            title: title, value: value, range: range, neutral: neutral,
            readout: readout, reset: reset, accessory: EmptyView()
        )
    }

    private var signedWholeReadout: (Double) -> String {
        { value in String(format: "%+.0f", value) }
    }

    private var unsignedWholeReadout: (Double) -> String {
        { value in String(format: "%.0f", value) }
    }
}

/// The advanced controls for a section: a full-width, darker band that slices open under the
/// section's main control and pushes everything below it down. It bleeds past the inspector's
/// content inset to the panel's edges and is bounded by hairlines, so it reads as part of the
/// panel rather than as a card floating on it.
struct InspectorAdvancedBand<Content: View>: View {
    let title: String
    var resetEnabled = true
    var reset: (() -> Void)?
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("\(title) · Advanced")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if let reset {
                    ResetIconButton(
                        "Reset advanced \(title) controls",
                        disabled: !resetEnabled, action: reset
                    )
                }
            }
            content()
        }
        .padding(.horizontal, InspectorStyle.contentInset)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.22))
        .overlay(alignment: .top) { Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1) }
        .overlay(alignment: .bottom) { Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1) }
        .padding(.horizontal, -InspectorStyle.contentInset)
        .padding(.top, 12)
        .transition(.modifier(active: BandRevealTransition(progress: 0), identity: BandRevealTransition(progress: 1)))
    }
}

/// Reports a fraction of the band's height and clips to it, so inserting the band grows it from a
/// slit and the rows below ride down with it instead of being overlapped.
private struct RevealHeightLayout: Layout {
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let subview = subviews.first else { return .zero }
        let size = subview.sizeThatFits(proposal)
        return CGSize(width: size.width, height: size.height * progress)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(
            at: bounds.origin, anchor: .topLeading,
            proposal: ProposedViewSize(width: bounds.width, height: nil)
        )
    }
}

private struct BandRevealTransition: ViewModifier {
    var progress: Double

    func body(content: Content) -> some View {
        RevealHeightLayout(progress: progress) {
            content
        }
        // Clip vertically to the revealed height but not horizontally: the band bleeds past the
        // content inset on both sides.
        .mask {
            Rectangle().padding(.horizontal, -InspectorStyle.contentInset)
        }
        .opacity(0.35 + 0.65 * progress)
    }
}

private struct EffectsValueRow<Accessory: View>: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    /// Where this row's fill is anchored — see `SliderFill`.
    let neutral: Double
    let readout: (Double) -> String
    let reset: () -> Void
    let beginInteraction: () -> Void
    let endInteraction: () -> Void
    /// Sits right after the label (the Advanced icon), so it reads as part of the control's name.
    let accessory: Accessory

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                ResettableAdjustmentLabel(title: title, reset: reset)
                accessory
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

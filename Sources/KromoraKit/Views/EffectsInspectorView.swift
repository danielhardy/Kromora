import SwiftUI

/// The photographer-facing global Effects inspector.
///
/// All rows use the same value-state bindings as the render pipeline. Slider ticks take the
/// interactive quality path and a gesture becomes one undo entry; numeric edits and resets retain
/// the existing settled/debounced behavior from `AppViewModel`.
struct EffectsInspectorView: View {
    @ObservedObject var viewModel: AppViewModel

    @State private var detailExpanded = true
    @State private var sharpeningExpanded = false
    @State private var sharpeningAdvancedExpanded = false
    @State private var noiseExpanded = false
    @State private var vignetteExpanded = false
    @State private var vignetteAdvancedExpanded = false
    @State private var grainExpanded = false
    @State private var grainAdvancedExpanded = false

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
            ResetIconButton(
                "Reset Effects",
                accessibilityHint: "Reset detail, noise, sharpening, Vignette, and Grain",
                disabled: !viewModel.hasEffects,
                action: viewModel.resetAllEffects
            )
        }
    }

    private var sharpeningSection: some View {
        VStack(alignment: .leading, spacing: 0) {
        InspectorDisclosure(
            "Sharpening",
            isExpanded: $sharpeningExpanded,
            trailingActionTitle: "Reset Sharpening",
            trailingActionEnabled: viewModel.hasSharpeningAdjustments,
            trailingAction: viewModel.resetAllSharpening,
            trailingAccessory: AnyView(advancedToggle(
                "Sharpening", isExpanded: $sharpeningAdvancedExpanded, sectionExpanded: $sharpeningExpanded,
                isModified: sharpeningHasAdvancedAdjustments
            ))
        ) {
            VStack(alignment: .leading, spacing: 12) {
                detailRow(.sharpeningAmount)
                            }
            .padding(.top, 10)
        }
        if sharpeningExpanded && sharpeningAdvancedExpanded {
            InspectorAdvancedBand(title: "Sharpening") {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach([DetailControl.sharpeningRadius, .sharpeningDetail, .sharpeningMasking], id: \.self) { control in
                                detailRow(control)
                            }
                            Text("Masking protects smooth areas; higher values restrict sharpening to stronger edges.")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
            }
        }
        }
        .onChange(of: viewModel.document.effects.detail, initial: true) { _, _ in
            expandSharpeningAdvancedIfNeeded()
        }
        .onChange(of: sharpeningExpanded) { _, isExpanded in
            if isExpanded { expandSharpeningAdvancedIfNeeded() }
        }
    }

    private var noiseSection: some View {
        InspectorDisclosure(
            "Noise Reduction",
            isExpanded: $noiseExpanded,
            trailingActionTitle: "Reset Noise Reduction",
            trailingActionEnabled: viewModel.hasNoiseAdjustments,
            trailingAction: viewModel.resetAllNoiseReduction
        ) {
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
        InspectorDisclosure(
            "Texture / Clarity / Dehaze",
            isExpanded: $detailExpanded,
            trailingActionTitle: "Reset Texture, Clarity, and Dehaze",
            trailingActionEnabled: viewModel.hasTextureClarityDehazeAdjustments,
            trailingAction: viewModel.resetAllTextureClarityDehaze
        ) {
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
        VStack(alignment: .leading, spacing: 0) {
        InspectorDisclosure(
            "Vignette",
            isExpanded: $vignetteExpanded,
            trailingActionTitle: "Reset Vignette",
            trailingActionEnabled: viewModel.hasVignetteAdjustments,
            trailingAction: viewModel.resetAllVignette,
            trailingAccessory: AnyView(advancedToggle(
                "Vignette", isExpanded: $vignetteAdvancedExpanded, sectionExpanded: $vignetteExpanded,
                isModified: vignetteHasAdvancedAdjustments
            ))
        ) {
            VStack(alignment: .leading, spacing: 12) {
                vignetteRow(.amount)
                            }
            .padding(.top, 10)
        }
        if vignetteExpanded && vignetteAdvancedExpanded {
            InspectorAdvancedBand(title: "Vignette") {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach([VignetteControl.midpoint, .roundness, .feather, .highlights], id: \.self) { control in
                                vignetteRow(control)
                            }
                        }
            }
        }
        }
        .onChange(of: viewModel.document.effects.vignette, initial: true) { _, _ in
            expandVignetteAdvancedIfNeeded()
        }
        .onChange(of: vignetteExpanded) { _, isExpanded in
            if isExpanded { expandVignetteAdvancedIfNeeded() }
        }
    }

    private func vignetteRow(_ control: VignetteControl) -> some View {
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

    private var grainSection: some View {
        VStack(alignment: .leading, spacing: 0) {
        InspectorDisclosure(
            "Grain",
            isExpanded: $grainExpanded,
            trailingActionTitle: "Reset Grain",
            trailingActionEnabled: viewModel.hasGrainAdjustments,
            trailingAction: viewModel.resetAllGrain,
            trailingAccessory: AnyView(advancedToggle(
                "Grain", isExpanded: $grainAdvancedExpanded, sectionExpanded: $grainExpanded,
                isModified: grainHasAdvancedAdjustments
            ))
        ) {
            VStack(alignment: .leading, spacing: 12) {
                grainRow(.amount)
                            }
            .padding(.top, 10)
        }
        if grainExpanded && grainAdvancedExpanded {
            InspectorAdvancedBand(title: "Grain") {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach([GrainControl.size, .roughness], id: \.self) { control in
                                grainRow(control)
                            }
                        }
            }
        }
        }
        .onChange(of: viewModel.document.effects.grain, initial: true) { _, _ in
            expandGrainAdvancedIfNeeded()
        }
        .onChange(of: grainExpanded) { _, isExpanded in
            if isExpanded { expandGrainAdvancedIfNeeded() }
        }
    }

    private func grainRow(_ control: GrainControl) -> some View {
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
        [DetailControl.sharpeningRadius, .sharpeningDetail, .sharpeningMasking]
            .contains { $0.value(in: viewModel.document.effects.detail) != $0.neutral }
    }

    private var vignetteHasAdvancedAdjustments: Bool {
        [VignetteControl.midpoint, .roundness, .feather, .highlights]
            .contains { $0.value(in: viewModel.document.effects.vignette) != $0.neutral }
    }

    private var grainHasAdvancedAdjustments: Bool {
        [GrainControl.size, .roughness]
            .contains { $0.value(in: viewModel.document.effects.grain) != $0.neutral }
    }

    /// An icon beside the section's reset icon. Opening it also opens its section, so the band
    /// never hides behind a collapsed header. A dot marks advanced values that differ from
    /// neutral while the band is closed.
    private func advancedToggle(
        _ section: String,
        isExpanded: Binding<Bool>,
        sectionExpanded: Binding<Bool>,
        isModified: Bool
    ) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.25)) {
                let opening = !isExpanded.wrappedValue
                isExpanded.wrappedValue = opening
                if opening { sectionExpanded.wrappedValue = true }
            }
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 11, weight: .medium))
                .frame(width: 24, height: 24)
                .background {
                    Circle().fill(Color.accentColor.opacity(isExpanded.wrappedValue ? 0.2 : 0))
                }
                .overlay(alignment: .topTrailing) {
                    if isModified && !isExpanded.wrappedValue {
                        Circle().fill(Color.accentColor).frame(width: 5, height: 5)
                            .padding(3)
                            .accessibilityHidden(true)
                    }
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isExpanded.wrappedValue ? Color.accentColor : Color.secondary)
        .help("\(isExpanded.wrappedValue ? "Hide" : "Show") advanced \(section) controls")
        .accessibilityLabel("Advanced \(section) controls")
        .accessibilityValue(isExpanded.wrappedValue ? "Expanded" : "Collapsed")
        .accessibilityHint("Show or hide advanced \(section) controls")
        .accessibilityAddTraits(.isToggle)
    }

    private func expandSharpeningAdvancedIfNeeded() {
        if sharpeningHasAdvancedAdjustments { sharpeningAdvancedExpanded = true }
    }

    private func expandVignetteAdvancedIfNeeded() {
        if vignetteHasAdvancedAdjustments { vignetteAdvancedExpanded = true }
    }

    private func expandGrainAdvancedIfNeeded() {
        if grainHasAdvancedAdjustments { grainAdvancedExpanded = true }
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

/// A subordinate, keyboard-accessible group for controls that refine a section's primary value.
/// The advanced controls for a section: a full-width, darker band that slices open under the
/// section's main control and pushes everything below it down. It bleeds past the inspector's
/// content inset to the panel's edges and is bounded by hairlines, so it reads as part of the
/// panel rather than as a card floating on it.
struct InspectorAdvancedBand<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(title) · Advanced")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
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

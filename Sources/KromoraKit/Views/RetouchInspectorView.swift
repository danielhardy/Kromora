import SwiftUI

/// Value editor for retouch recipes. Geometry stays in source-normalized coordinates so the
/// recipes remain attached to the photograph through crop, rotation and perspective changes.
struct RetouchInspectorView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var selectedSpotID: UUID?
    @State private var selectedEyeID: UUID?
    @State private var eyeKind: EyeKind = .human
    @ObservedObject private var interaction: RetouchInteractionState

    init(viewModel: AppViewModel) {
        self.viewModel = viewModel
        _interaction = ObservedObject(wrappedValue: viewModel.retouchInteractionState)
    }

    var body: some View {
        InspectorScrollingContent {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Retouch").font(.headline)
                    Spacer()
                    Button("Reset All") {
                        viewModel.updateDocument { $0.retouch = .neutral }
                        interaction.select(nil)
                    }
                        .disabled(viewModel.document.retouch.isIdentity)
                }
                GroupBox("Spots") {
                    VStack(alignment: .leading, spacing: 10) {
                        Picker("Method", selection: $interaction.mode) {
                            Text("Remove").tag(RetouchMode.remove)
                            Text("Heal").tag(RetouchMode.heal)
                            Text("Clone").tag(RetouchMode.clone)
                        }
                        .pickerStyle(.segmented)
                        HStack {
                            Text("\(viewModel.document.retouch.spots.count) spots")
                            Spacer()
                            Picker("Overlay", selection: $interaction.overlayPolicy) {
                                ForEach(RetouchInteractionState.OverlayPolicy.allCases, id: \.self) { policy in
                                    Text(policy.title).tag(policy)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 115)
                        }
                        slider("Size", value: spotRadiusBinding, range: 0.0005...0.25, format: "%.3f")
                        slider("Feather", value: featherBinding, range: 0...1, format: "%.0f%%", scale: 100)
                        slider("Opacity", value: opacityBinding, range: 0...1, format: "%.0f%%", scale: 100)
                        if let spot = selectedSpot {
                            Toggle("Visible", isOn: spotBinding(\.isVisible))
                            if let failure = interaction.solveFailures[spot.wrappedValue.id] {
                                Label(failure, systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption).foregroundStyle(.red)
                            }
                            if spot.wrappedValue.mode == .remove, spot.wrappedValue.region.samples.count > 1 {
                                if interaction.isRefiningWire, interaction.wireProposalSpotID == spot.wrappedValue.id {
                                    Button("Cancel Wire Refinement") { viewModel.retouchWorkflow.cancelWireRefinement() }
                                } else if interaction.wireProposalSpotID == spot.wrappedValue.id,
                                          let proposal = interaction.wireProposal {
                                    Text(String(format: "Proposed wire boundary · %.0f%% confidence", proposal.confidence * 100))
                                        .font(.caption).foregroundStyle(.secondary)
                                    HStack {
                                        Button("Keep Brush Region") { viewModel.retouchWorkflow.cancelWireRefinement() }
                                        Button("Accept Refinement") { viewModel.retouchWorkflow.acceptWireRefinement() }
                                            .buttonStyle(.borderedProminent)
                                    }
                                } else {
                                    Button("Refine to Wire") { viewModel.retouchWorkflow.refineSelectedSpotToWire() }
                                }
                                if let message = interaction.wireRefinementMessage {
                                    Text(message).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Text("Drag the pin to move it; drag its source ring to choose a source.")
                                .font(.caption).foregroundStyle(.secondary)
                            Button("Delete Spot", role: .destructive) { removeSpot(spot.wrappedValue.id) }
                        } else {
                            Text("Paint on the photo to add a spot. Press Q to arm the brush.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 4)
                }
                GroupBox("Dust") {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("A · Visualize Spots", isOn: Binding(
                            get: { interaction.visualizationEnabled },
                            set: { _ in viewModel.toggleRetouchVisualization() }
                        ))
                        slider("Threshold", value: Binding(
                            get: { interaction.visualizationThreshold },
                            set: { viewModel.setRetouchVisualizationThreshold($0) }
                        ), range: 0.005...0.12, format: "%.3f")
                        Button("Detect Dust") { viewModel.detectRetouchDust() }
                            .disabled(viewModel.previewSurface.image == nil)
                        if !interaction.dustSuggestions.isEmpty {
                            HStack {
                                Text("\(interaction.dustSuggestions.count) suggestions").font(.caption)
                                Spacer()
                                Button("Accept All") { viewModel.retouchWorkflow.acceptAllDustSuggestions() }
                                Button("Dismiss") { viewModel.retouchWorkflow.dismissAllDustSuggestions() }
                            }
                            ForEach(interaction.dustSuggestions.prefix(12)) { suggestion in
                                HStack(spacing: 5) {
                                    Text(String(format: "%.0f%%", suggestion.confidence * 100)).font(.caption2)
                                    Spacer()
                                    Button("Accept") { viewModel.retouchWorkflow.acceptDustSuggestion(suggestion.id) }
                                    Button("×") { viewModel.retouchWorkflow.dismissDustSuggestion(suggestion.id) }
                                        .buttonStyle(.plain).help("Dismiss suggestion")
                                }
                            }
                            Text("Drag a dashed pin to move it or its ring to resize it before accepting.")
                                .font(.caption2).foregroundStyle(.secondary)
                        } else {
                            Text("Visualization changes only the canvas overlay. Detect Dust adds editable suggestions; the brush remains available for missed spots.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 4)
                }
                GroupBox("Red-Eye / Pet-Eye") {
                    VStack(alignment: .leading, spacing: 10) {
                        Picker("Eye type", selection: $eyeKind) {
                            Text("Human").tag(EyeKind.human)
                            Text("Pet").tag(EyeKind.pet)
                        }
                        .pickerStyle(.segmented)
                        HStack {
                            Button { addEye() } label: { Label("Add Eye", systemImage: "plus.circle") }
                            Spacer()
                            Button { selectEye(-1) } label: { Image(systemName: "chevron.left") }
                                .disabled(viewModel.document.retouch.eyes.isEmpty)
                                .help("Previous eye")
                            Button { selectEye(1) } label: { Image(systemName: "chevron.right") }
                                .disabled(viewModel.document.retouch.eyes.isEmpty)
                                .help("Next eye")
                        }
                        if let eye = selectedEye {
                            Toggle("Visible", isOn: eyeBinding(\.isVisible))
                            eyeCoordinate("Center X", axis: .x)
                            eyeCoordinate("Center Y", axis: .y)
                            slider("Width", value: eyeBinding(\.radiusX), range: 0.001...0.1, format: "%.3f")
                            slider("Height", value: eyeBinding(\.radiusY), range: 0.001...0.1, format: "%.3f")
                            slider("Pupil size", value: eyeBinding(\.pupilSize), range: 0...100, format: "%.0f%%")
                            slider("Darkening", value: eyeBinding(\.darken), range: 0...100, format: "%.0f%%")
                            Button("Delete Eye", role: .destructive) { removeEye(eye.wrappedValue.id) }
                        } else {
                            Text("Add an eye correction and tune pupil size and darkening.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 4)
                }
                Text("Coordinates use the uncropped source image. Use 1:1 zoom when placing fine corrections.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .padding(16)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Retouch tools")
        .onChange(of: viewModel.document.retouch.spots) { _, spots in
            if !spots.contains(where: { $0.id == selectedSpotID }) { selectedSpotID = spots.last?.id }
        }
        .onChange(of: interaction.selectedSpotID) { _, id in selectedSpotID = id }
        .onAppear { selectedSpotID = interaction.selectedSpotID }
        .onChange(of: viewModel.document.retouch.eyes) { _, eyes in
            if !eyes.contains(where: { $0.id == selectedEyeID }) { selectedEyeID = eyes.last?.id }
        }
    }

    private var selectedSpot: Binding<RetouchSpot>? {
        guard let selectedSpotID,
              let index = viewModel.document.retouch.spots.firstIndex(where: { $0.id == selectedSpotID }) else { return nil }
        return Binding(get: { viewModel.document.retouch.spots[index] }, set: { value in
            viewModel.updateDocument { $0.retouch.spots[index] = value }
        })
    }

    private var selectedEye: Binding<EyeCorrection>? {
        guard let selectedEyeID,
              let index = viewModel.document.retouch.eyes.firstIndex(where: { $0.id == selectedEyeID }) else { return nil }
        return Binding(get: { viewModel.document.retouch.eyes[index] }, set: { value in
            viewModel.updateDocument { $0.retouch.eyes[index] = value }
        })
    }

    private func spotBinding<Value>(_ keyPath: WritableKeyPath<RetouchSpot, Value>) -> Binding<Value> {
        Binding(get: { selectedSpot?.wrappedValue[keyPath: keyPath] ?? RetouchSpot()[keyPath: keyPath] },
                set: { value in if var spot = selectedSpot?.wrappedValue { spot[keyPath: keyPath] = value; selectedSpot?.wrappedValue = spot } })
    }

    private func eyeBinding<Value>(_ keyPath: WritableKeyPath<EyeCorrection, Value>) -> Binding<Value> {
        Binding(get: { selectedEye?.wrappedValue[keyPath: keyPath] ?? EyeCorrection()[keyPath: keyPath] },
                set: { value in if var eye = selectedEye?.wrappedValue { eye[keyPath: keyPath] = value; selectedEye?.wrappedValue = eye } })
    }

    private enum Axis { case x, y }

    private func eyeCoordinate(_ title: String, axis: Axis) -> some View {
        slider(title, value: Binding(get: {
            guard let center = selectedEye?.wrappedValue.center else { return 0.5 }
            return Double(axis == .x ? center.x : center.y)
        }, set: { value in
            guard var eye = selectedEye?.wrappedValue else { return }
            if axis == .x { eye.center.x = value } else { eye.center.y = value }
            selectedEye?.wrappedValue = eye
        }), range: 0...1, format: "%.2f")
    }

    private var featherBinding: Binding<Double> {
        Binding(get: { selectedSpot?.wrappedValue.feather ?? interaction.feather }, set: { value in
            interaction.feather = value
            guard var spot = selectedSpot?.wrappedValue else { return }
            spot.feather = value; selectedSpot?.wrappedValue = spot
        })
    }

    private var opacityBinding: Binding<Double> {
        Binding(get: { selectedSpot?.wrappedValue.opacity ?? interaction.opacity }, set: { value in
            interaction.opacity = value
            guard var spot = selectedSpot?.wrappedValue else { return }
            spot.opacity = value; selectedSpot?.wrappedValue = spot
        })
    }

    private func slider(
        _ title: String, value: Binding<Double>, range: ClosedRange<Double>,
        format: String, scale: Double = 1
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack { Text(title); Spacer(); Text(String(format: format, value.wrappedValue * scale)).monospacedDigit().foregroundStyle(.secondary) }
                .font(.caption)
            Slider(value: value, in: range)
        }
    }

    private var spotRadiusBinding: Binding<Double> {
        Binding(get: { selectedSpot?.wrappedValue.region.radius ?? interaction.radius }, set: { value in
            interaction.radius = value
            guard var spot = selectedSpot?.wrappedValue else { return }
            spot.region.radius = value
            selectedSpot?.wrappedValue = spot
        })
    }

    private func addEye() {
        let eye = EyeCorrection(kind: eyeKind)
        viewModel.updateDocument { $0.retouch.eyes.append(eye) }
        selectedEyeID = eye.id
    }

    private func removeSpot(_ id: UUID) { viewModel.retouchWorkflow.deleteSpot(id) }
    private func removeEye(_ id: UUID) { viewModel.updateDocument { $0.retouch.eyes.removeAll { $0.id == id } } }

    private func selectEye(_ step: Int) {
        let values = viewModel.document.retouch.eyes
        guard !values.isEmpty else { return }
        let index = values.firstIndex(where: { $0.id == selectedEyeID }) ?? 0
        selectedEyeID = values[(index + step + values.count) % values.count].id
    }
}

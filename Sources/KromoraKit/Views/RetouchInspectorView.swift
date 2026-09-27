import SwiftUI

/// Value editor for retouch recipes. Geometry stays in source-normalized coordinates so the
/// recipes remain attached to the photograph through crop, rotation and perspective changes.
struct RetouchInspectorView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var selectedSpotID: UUID?
    @State private var selectedEyeID: UUID?
    @State private var mode: RetouchMode = .remove
    @State private var eyeKind: EyeKind = .human
    @State private var isDustFinderPresented = false

    var body: some View {
        InspectorScrollingContent {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Retouch").font(.headline)
                    Spacer()
                    Button("Reset") { viewModel.updateDocument { $0.retouch = .neutral } }
                        .disabled(viewModel.document.retouch.isIdentity)
                }
                GroupBox("Spots") {
                    VStack(alignment: .leading, spacing: 10) {
                        Picker("Method", selection: $mode) {
                            Text("Remove").tag(RetouchMode.remove)
                            Text("Heal").tag(RetouchMode.heal)
                            Text("Clone").tag(RetouchMode.clone)
                        }
                        .pickerStyle(.segmented)
                        HStack {
                            Button { addSpot() } label: { Label("Add Spot", systemImage: "plus.circle") }
                            Spacer()
                            Button { selectSpot(-1) } label: { Image(systemName: "chevron.left") }
                                .disabled(viewModel.document.retouch.spots.isEmpty)
                                .help("Previous spot")
                            Button { selectSpot(1) } label: { Image(systemName: "chevron.right") }
                                .disabled(viewModel.document.retouch.spots.isEmpty)
                                .help("Next spot")
                        }
                        if let spot = selectedSpot {
                            Toggle("Visible", isOn: spotBinding(\.isVisible))
                            normalizedCoordinate("Center X", axis: .x)
                            normalizedCoordinate("Center Y", axis: .y)
                            slider("Size", value: spotRadiusBinding, range: 0.0005...0.25, format: "%.3f")
                            slider("Feather", value: spotBinding(\.feather), range: 0...1, format: "%.0f%%", scale: 100)
                            slider("Opacity", value: spotBinding(\.opacity), range: 0...1, format: "%.0f%%", scale: 100)
                            sourceOffsetSliders
                            Button("Delete Spot", role: .destructive) { removeSpot(spot.wrappedValue.id) }
                        } else {
                            Text("Add a spot, then adjust its center and source offset.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 4)
                }
                Button {
                    isDustFinderPresented = true
                } label: {
                    Label("Dust Finder · 1:1", systemImage: "circle.dotted")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .disabled(viewModel.previewSurface.image == nil)
                .help("Open a high-contrast pixel-size view and navigate between retouch spots")
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
        .sheet(isPresented: $isDustFinderPresented) {
            DustFinderSheet(viewModel: viewModel)
                .frame(minWidth: 720, minHeight: 520)
        }
        .onChange(of: viewModel.document.retouch.spots) { _, spots in
            if !spots.contains(where: { $0.id == selectedSpotID }) { selectedSpotID = spots.last?.id }
        }
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

    private func vectorBinding(_ keyPath: WritableKeyPath<CGVector, CGFloat>) -> Binding<Double> {
        Binding(get: { Double(selectedSpot?.wrappedValue.source?.offset[keyPath: keyPath] ?? 0) }, set: { value in
            guard var spot = selectedSpot?.wrappedValue else { return }
            var offset = spot.source?.offset ?? .zero
            offset[keyPath: keyPath] = value
            spot.source = .manual(offset: offset)
            selectedSpot?.wrappedValue = spot
        })
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

    private var spotRadiusBinding: Binding<Double> {
        Binding(get: { selectedSpot?.wrappedValue.region.radius ?? 0.02 }, set: { value in
            guard var spot = selectedSpot?.wrappedValue else { return }
            spot.region.radius = value
            selectedSpot?.wrappedValue = spot
        })
    }

    private func normalizedCoordinate(_ title: String, axis: Axis) -> some View {
        slider(title, value: Binding(get: {
            guard let point = selectedSpot?.wrappedValue.region.samples.first?.point else { return 0.5 }
            return Double(axis == .x ? point.x : point.y)
        }, set: { value in
            guard var spot = selectedSpot?.wrappedValue, !spot.region.samples.isEmpty else { return }
            var sample = spot.region.samples[0]
            if axis == .x { sample.point.x = value } else { sample.point.y = value }
            spot.region.samples[0] = sample
            selectedSpot?.wrappedValue = spot
        }), range: 0...1, format: "%.2f")
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

    private var sourceOffsetSliders: some View {
        let x = vectorBinding(\.dx)
        let y = vectorBinding(\.dy)
        return VStack(alignment: .leading, spacing: 8) {
            slider("Source X", value: x, range: -1.5...1.5, format: "%+.2f")
            slider("Source Y", value: y, range: -1.5...1.5, format: "%+.2f")
        }
    }

    private func addSpot() {
        let spot = RetouchSpot(
            mode: mode, region: RetouchRegion(samples: [BrushSample(point: CGPoint(x: 0.5, y: 0.5))]),
            source: mode == .remove ? nil : .manual(offset: .zero)
        )
        viewModel.updateDocument { $0.retouch.spots.append(spot) }
        selectedSpotID = spot.id
    }

    private func addEye() {
        let eye = EyeCorrection(kind: eyeKind)
        viewModel.updateDocument { $0.retouch.eyes.append(eye) }
        selectedEyeID = eye.id
    }

    private func removeSpot(_ id: UUID) { viewModel.updateDocument { $0.retouch.spots.removeAll { $0.id == id } } }
    private func removeEye(_ id: UUID) { viewModel.updateDocument { $0.retouch.eyes.removeAll { $0.id == id } } }

    private func selectSpot(_ step: Int) {
        let values = viewModel.document.retouch.spots
        guard !values.isEmpty else { return }
        let index = values.firstIndex(where: { $0.id == selectedSpotID }) ?? 0
        selectedSpotID = values[(index + step + values.count) % values.count].id
    }

    private func selectEye(_ step: Int) {
        let values = viewModel.document.retouch.eyes
        guard !values.isEmpty else { return }
        let index = values.firstIndex(where: { $0.id == selectedEyeID }) ?? 0
        selectedEyeID = values[(index + step + values.count) % values.count].id
    }
}

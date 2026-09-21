import AppKit
import SwiftUI

/// Persistent local-mask editor. The workspace is an inspector tab, so it stays beside the canvas
/// while the photographer changes layers, reopens saved recipes, or switches tools.
struct MaskingWorkspace: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject private var maskingState: MaskInteractionState

    init(viewModel: AppViewModel) {
        self.viewModel = viewModel
        _maskingState = ObservedObject(wrappedValue: viewModel.maskInteractionState)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                toolPicker
                creationPrompt
                overlayControls
                renderStatus
                layerList
                selectedInspector
            }
            .padding(12)
        }
        .frame(minWidth: 280, idealWidth: 320)
        .onAppear { viewModel.restoreMaskSelection() }
        .onChange(of: viewModel.document.localAdjustments) { _, _ in
            viewModel.restoreMaskSelection()
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Label("Masking", systemImage: "wand.and.rays")
                .font(.title3.weight(.semibold))
            Spacer()
            Button("Done") { viewModel.closeMaskingWorkspace() }
                .buttonStyle(.borderless)
                .accessibilityLabel("Close masking workspace")
            Menu {
                Section("Smart masks") {
                    ForEach(MaskCreationKind.smartKinds, id: \.self) { kind in
                        Button {
                            viewModel.createSmartMask(kind)
                        } label: {
                            Label(kind.title, systemImage: kind.iconName)
                        }
                    }
                }
                Section("Paint and gradients") {
                    ForEach(MaskCreationKind.allCases.filter { !$0.isSmart }, id: \.self) { kind in
                        Button {
                            viewModel.createMask(kind)
                        } label: {
                            Label(kind.title, systemImage: kind.iconName)
                        }
                    }
                }
            } label: {
                Label("Add mask", systemImage: "plus")
            }
            .accessibilityLabel("Add mask layer")
            .help("Create a new mask layer")
        }
    }

    private var toolPicker: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Tools")
                .font(.subheadline.weight(.semibold))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 5)], spacing: 5) {
                ForEach(MaskInteractionState.Tool.allCases, id: \.self) { tool in
                    Button {
                        viewModel.setMaskTool(tool)
                    } label: {
                        Label(tool.title, systemImage: tool.iconName)
                            .labelStyle(.titleAndIcon)
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .tint(maskingState.activeTool == tool ? .accentColor : .secondary)
                    .accessibilityLabel("Mask tool \(tool.title)")
                    .accessibilityValue(
                        maskingState.activeTool == tool ? "Selected" : "Not selected")
                }
            }
        }
    }

    @ViewBuilder
    private var creationPrompt: some View {
        if maskingState.linearCreationPending {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "hand.draw")
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Create linear gradient")
                        .font(.caption.weight(.semibold))
                    Text(
                        "Drag from the zero-strength edge to the full-strength edge on the canvas."
                    )
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                Button("Cancel") { viewModel.cancelMaskGesture() }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .accessibilityLabel("Cancel linear gradient creation")
            }
            .padding(9)
            .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Linear gradient creation pending")
            .accessibilityHint("Drag across the canvas to create the gradient, or cancel")
        }
    }

    private var overlayControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Show overlay", isOn: $maskingState.showOverlay)
                .accessibilityHint("Presentation only; does not change the saved mask or export")
            HStack {
                Picker("Inspection", selection: $maskingState.overlayInspection) {
                    ForEach(MaskInteractionState.OverlayInspection.allCases, id: \.self) {
                        Text($0.title).tag($0)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                ColorPicker(
                    "Overlay color", selection: $maskingState.overlayColor, supportsOpacity: false
                )
                .labelsHidden()
                .accessibilityLabel("Overlay color")
            }
            HStack {
                Text("Opacity")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                NeutralOriginSlider(
                    value: $maskingState.overlayOpacity, in: 0...1, neutral: 0,
                    accessibilityTitle: "Opacity",
                    accessibilityReadout: "\(Int(maskingState.overlayOpacity * 100)) percent")
                    .accessibilityValue("\(Int(maskingState.overlayOpacity * 100)) percent")
                Text(percentage(maskingState.overlayOpacity))
                    .font(.caption.monospacedDigit())
                    .frame(width: 38, alignment: .trailing)
            }
        }
        .padding(9)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var renderStatus: some View {
        switch maskingState.resolutionState {
        case .loading:
            Label("Analyzing mask…", systemImage: "hourglass")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Selected mask is loading")
        case .empty:
            Label(
                maskingState.resolutionState.message ?? "Mask is empty",
                systemImage: "circle.dashed"
            )
            .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Selected mask is empty")
        case .unavailable(let message):
            VStack(alignment: .leading, spacing: 6) {
                Label("Mask analysis unavailable", systemImage: "exclamationmark.triangle")
                    .font(.caption.weight(.semibold))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Retry mask analysis") {
                    viewModel.retryMaskAnalysis()
                }
                .buttonStyle(.borderless)
            }
            .padding(8)
            .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
        case .failed(let message):
            VStack(alignment: .leading, spacing: 6) {
                Label("Mask analysis failed", systemImage: "exclamationmark.triangle")
                    .font(.caption.weight(.semibold))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Retry mask analysis") {
                    viewModel.retryMaskAnalysis()
                }
                .buttonStyle(.borderless)
            }
            .padding(8)
            .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
        case .idle, .ready:
            EmptyView()
        }

        switch viewModel.previewState {
        case .loading:
            Label("Rendering preview…", systemImage: "hourglass")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Mask preview is loading")
        case .failed:
            VStack(alignment: .leading, spacing: 6) {
                Label("Preview unavailable", systemImage: "exclamationmark.triangle")
                    .font(.caption.weight(.semibold))
                Text(viewModel.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Retry preview") { viewModel.retryPreview() }
                    .buttonStyle(.borderless)
                    .accessibilityHint("Retry without discarding the saved mask definition")
            }
            .padding(8)
            .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var layerList: some View {
        let layers = visibleLayers
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Layers")
                    .font(.headline)
                Spacer()
                Text("\(layers.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if viewModel.sourceImage == nil {
                ContentUnavailableView(
                    "No photo", systemImage: "photo",
                    description: Text("Open a photo to edit masks."))
            } else if layers.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("No mask layers yet", systemImage: "rectangle.dashed")
                        .font(.subheadline.weight(.semibold))
                    Text("Create a foreground, background, brush, linear, or radial mask to begin.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Create mask") { viewModel.createMask(.foreground) }
                        .buttonStyle(.bordered)
                }
                .padding(.vertical, 8)
            } else {
                ForEach(Array(layers.enumerated()), id: \.element.id) {
                    index, layer in
                    MaskLayerRow(
                        viewModel: viewModel,
                        maskingState: maskingState,
                        layer: layer,
                        index: index,
                        total: layers.count,
                        isTransient: !viewModel.document.localAdjustments.contains(where: {
                            $0.id == layer.id
                        })
                    )
                }
            }
        }
    }

    private var visibleLayers: [LocalAdjustmentLayer] {
        var layers = viewModel.document.localAdjustments
        if let draft = maskingState.draftLayer,
           !layers.contains(where: { $0.id == draft.id }) {
            layers.append(draft)
        }
        return layers
    }

    @ViewBuilder
    private var selectedInspector: some View {
        if let id = maskingState.selectedLayerID,
            let layer = inspectorLayer(id: id)
        {
            VStack(alignment: .leading, spacing: 10) {
                Divider()
                Text("Layer settings")
                    .font(.headline)
                HStack {
                    Text(layer.name)
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(layer.maskingSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Toggle("Enabled", isOn: layerBinding(id: id, keyPath: \.isEnabled))
                Toggle("Invert layer", isOn: layerBinding(id: id, keyPath: \.isInverted))
                maskSlider("Amount", value: layerBinding(id: id, keyPath: \.amount), range: 0...1)

                componentInspector(layer)
                localAdjustmentControls

                Button("Reset layer", systemImage: "arrow.counterclockwise") {
                    viewModel.resetMask(id)
                }
                .buttonStyle(.borderless)
                .accessibilityHint("Restore this layer's saved controls to their defaults")
            }
        }
    }

    /// During a canvas gesture the draft is the source of truth for the visible controls. Reading
    /// only the committed document here made the inspector appear to lag until mouse-up.
    private func inspectorLayer(id: UUID) -> LocalAdjustmentLayer? {
        if let draft = maskingState.draftLayer, draft.id == id {
            return draft
        }
        return viewModel.document.localAdjustments.first(where: { $0.id == id })
    }

    private func componentInspector(_ layer: LocalAdjustmentLayer) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("Components")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Menu {
                    ForEach([MaskCombineMode.add, .subtract, .intersect], id: \.self) { mode in
                        Menu(mode.title) {
                            Section("Smart masks") {
                                ForEach(MaskCreationKind.smartKinds, id: \.self) { kind in
                                    Button(kind.title) {
                                        viewModel.addSmartMaskComponent(
                                            to: layer.id, kind: kind, mode: mode)
                                    }
                                }
                            }
                            Section("Paint and gradients") {
                                ForEach(MaskCreationKind.allCases.filter {
                                    !$0.isSmart && $0 != .erase
                                }, id: \.self) {
                                kind in
                                Button(kind.title) {
                                    viewModel.addMaskComponent(to: layer.id, kind: kind, mode: mode)
                                }
                                }
                            }
                        }
                    }
                } label: {
                    Image(systemName: "plus.circle")
                }
                .accessibilityLabel("Add mask component")
            }

            ForEach(Array(layer.components.enumerated()), id: \.element.id) { index, component in
                DisclosureGroup(
                    isExpanded: Binding(
                        get: { maskingState.selectedComponentID == component.id },
                        set: { expanded in
                            if expanded {
                                viewModel.selectMaskComponent(component.id, in: layer.id)
                            } else if maskingState.selectedComponentID == component.id {
                                viewModel.selectMaskLayer(layer.id)
                            }
                        }
                    )
                ) {
                    componentControls(component, layerID: layer.id)
                } label: {
                    HStack(spacing: 5) {
                        Image(
                            systemName: maskingState.selectedComponentID == component.id
                                ? "checkmark.circle.fill" : "circle")
                        TextField(
                            component.source.maskingTypeTitle,
                            text: Binding(
                                get: { component.displayName },
                                set: { viewModel.renameMaskComponent(component.id, in: layer.id, name: $0) }
                            )
                        )
                        .textFieldStyle(.plain)
                        .font(.caption)
                        Text(index == 0 ? "Replace" : component.mode.title)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            maskingState.toggleSolo(componentID: component.id, layerID: layer.id)
                        } label: {
                            Image(systemName: maskingState.soloComponentID == component.id
                                ? "eye.fill" : "eye")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Solo \(component.displayName)")
                        .accessibilityValue(
                            maskingState.soloComponentID == component.id ? "On" : "Off")
                        Toggle(
                            "Enabled",
                            isOn: componentBinding(
                                component.id, layerID: layer.id, keyPath: \.isEnabled)
                        )
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .accessibilityLabel("Enable \(component.displayName)")
                        Menu {
                            Button("Move up") { viewModel.moveMaskComponent(component.id, in: layer.id, by: -1) }
                                .disabled(index == 0)
                            Button("Move down") { viewModel.moveMaskComponent(component.id, in: layer.id, by: 1) }
                                .disabled(index == layer.components.count - 1)
                            Divider()
                            componentModeMenu(component, layerID: layer.id)
                            Button("Delete", role: .destructive) {
                                viewModel.deleteMaskComponent(component.id, from: layer.id)
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .menuStyle(.borderlessButton)
                        .accessibilityLabel("Actions for \(component.displayName)")
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        viewModel.selectMaskComponent(component.id, in: layer.id)
                    }
                }
                .padding(7)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    private func componentModeMenu(_ component: MaskComponent, layerID: UUID) -> some View {
        Menu {
            ForEach([MaskCombineMode.replace, .add, .subtract, .intersect], id: \.self) { mode in
                Button {
                    viewModel.setMaskComponentMode(component.id, in: layerID, mode: mode)
                } label: {
                    Label(mode.title, systemImage: component.mode == mode ? "checkmark" : "")
                }
            }
        } label: {
            Text(component.mode.title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .accessibilityLabel("Component combine mode")
        .accessibilityValue(component.mode.title)
    }

    @ViewBuilder
    private func componentControls(_ component: MaskComponent, layerID: UUID) -> some View {
        Toggle(
            "Invert component",
            isOn: componentBinding(component.id, layerID: layerID, keyPath: \.isInverted)
        )
        .font(.caption)
        switch component.source {
        case .semantic(let definition):
            maskSlider(
                "Edge feather",
                value: componentValue(
                    component.id, layerID: layerID,
                    get: { source in
                        if case .semantic(let value) = source { return value.edgeFeather }
                        return definition.edgeFeather
                    },
                    set: { source, value in
                        if case .semantic(var current) = source {
                            current.edgeFeather = value
                            source = .semantic(current)
                        }
                    }), range: 0...1)
            maskSlider(
                "Density",
                value: componentValue(
                    component.id, layerID: layerID,
                    get: { source in
                        if case .semantic(let value) = source { return value.density }
                        return definition.density
                    },
                    set: { source, value in
                        if case .semantic(var current) = source {
                            current.density = value
                            source = .semantic(current)
                        }
                    }), range: 0...1)
        case .brush(let definition):
            Text(
                definition.strokes.isEmpty
                    ? "Paint on the canvas to add a stroke."
                    : "\(definition.strokes.count) stroke\(definition.strokes.count == 1 ? "" : "s")"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            brushControls
        case .linear(let definition):
            VStack(alignment: .leading, spacing: 5) {
                Text("Canvas guide")
                    .font(.caption.weight(.semibold))
                HStack(spacing: 8) {
                    linearGuideSwatch(.gray, title: "Zero")
                    linearGuideSwatch(.orange, title: "Transition")
                    linearGuideSwatch(.cyan, title: "Full")
                }
                Text("Drag the edge bars to resize, the orange center bar to move, or the purple handle to rotate.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Linear gradient guide: zero strength, transition, and full strength")
            .accessibilityHint("Use the canvas bars to resize, move, or rotate the gradient")
            maskSlider(
                "Angle",
                value: componentValue(
                    component.id, layerID: layerID,
                    get: { source in
                        if case .linear(let value) = source { return value.angleDegrees }
                        return definition.angleDegrees
                    },
                    set: { source, value in
                        if case .linear(var current) = source {
                            current.angleDegrees = value
                            source = .linear(current)
                        }
                    }), range: -180...180, neutral: 0)
            maskSlider(
                "Falloff",
                value: componentValue(
                    component.id, layerID: layerID,
                    get: { source in
                        if case .linear(let value) = source { return value.falloff }
                        return definition.falloff
                    },
                    set: { source, value in
                        if case .linear(var current) = source {
                            current.falloff = value
                            source = .linear(current)
                        }
                    }), range: 0...sqrt(2.0))
            maskSlider(
                "Density",
                value: componentValue(
                    component.id, layerID: layerID,
                    get: { source in
                        if case .linear(let value) = source { return value.density }
                        return definition.density
                    },
                    set: { source, value in
                        if case .linear(var current) = source {
                            current.density = value
                            source = .linear(current)
                        }
                    }), range: 0...1)
            Button("Reset linear gradient", systemImage: "arrow.counterclockwise") {
                viewModel.resetMaskComponent(component.id, in: layerID)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Reset linear gradient")
            .accessibilityHint("Restore the angle and falloff of this gradient")
        case .radial(let definition):
            Toggle(
                "Select inside",
                isOn: Binding(
                    get: {
                        guard let layer = viewModel.document.localAdjustments.first(where: {
                            $0.id == layerID
                        }), let selected = layer.components.first(where: { $0.id == component.id }),
                        case .radial(let value) = selected.source else { return definition.isInside }
                        return value.isInside
                    },
                    set: { isInside in
                        viewModel.updateMaskComponent(component.id, in: layerID) { component in
                            if case .radial(var current) = component.source {
                                current.isInside = isInside
                                component.source = .radial(current)
                            }
                        }
                    })
            )
            maskSlider(
                "Angle",
                value: componentValue(
                    component.id, layerID: layerID,
                    get: { source in
                        if case .radial(let value) = source { return value.rotation * 180 / .pi }
                        return definition.rotation * 180 / .pi
                    },
                    set: { source, value in
                        if case .radial(var current) = source {
                            current.rotation = value * .pi / 180
                            source = .radial(current)
                        }
                    }), range: -180...180, neutral: 0)
            maskSlider(
                "Feather",
                value: componentValue(
                    component.id, layerID: layerID,
                    get: { source in
                        if case .radial(let value) = source { return value.feather }
                        return definition.feather
                    },
                    set: { source, value in
                        if case .radial(var current) = source {
                            current.feather = value
                            source = .radial(current)
                        }
                    }), range: 0...1)
            maskSlider(
                "Density",
                value: componentValue(
                    component.id, layerID: layerID,
                    get: { source in
                        if case .radial(let value) = source { return value.density }
                        return definition.density
                    },
                    set: { source, value in
                        if case .radial(var current) = source {
                            current.density = value
                            source = .radial(current)
                        }
                    }), range: 0...1)
            Button("Reset radial gradient", systemImage: "arrow.counterclockwise") {
                viewModel.resetMaskComponent(component.id, in: layerID)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Reset radial gradient")
            .accessibilityHint("Restore the angle, radii, and feather of this gradient")
        }
    }

    private var brushControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Brush")
                .font(.caption.weight(.semibold))
            brushSlider("Size", value: $maskingState.brushRadius, range: 0.001...0.5)
            brushSlider("Feather", value: $maskingState.brushFeather, range: 0...1)
            brushSlider("Flow / Intensity", value: $maskingState.brushFlow, range: 0...1)
            brushSlider("Density", value: $maskingState.brushDensity, range: 0...1)
            Text("[ ] size · Shift-[ ] feather · Space pan")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func brushSlider(
        _ title: String, value: Binding<Double>, range: ClosedRange<Double>
    ) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.caption)
                .frame(width: 92, alignment: .leading)
            // Brush size, feather, flow and density are amounts: nothing is applied at the
            // bottom of the track, so the left-origin fill is the honest one for all four.
            NeutralOriginSlider(
                value: value, in: range, neutral: range.lowerBound,
                accessibilityTitle: title,
                accessibilityReadout: "\(Int(value.wrappedValue * 100)) percent")
            Text(Int(value.wrappedValue * 100).description + "%")
                .font(.caption2.monospacedDigit())
                .frame(width: 34, alignment: .trailing)
        }
    }

    private var localAdjustmentControls: some View {
        let layerID = maskingState.selectedLayerID
        return VStack(alignment: .leading, spacing: 7) {
            Text("Local adjustments")
                .font(.subheadline.weight(.semibold))
            if let layerID {
                ForEach(LocalAdjustmentControl.allCases, id: \.self) { control in
                    localAdjustmentRow(control, layerID: layerID)
                }
            }
        }
    }

    private func localAdjustmentRow(
        _ control: LocalAdjustmentControl, layerID: UUID
    ) -> some View {
        return LocalAdjustmentValueRow(
            control: control,
            value: viewModel.localAdjustmentBinding(control, in: layerID),
            reset: { viewModel.resetMaskAdjustment(control, in: layerID) },
            beginInteraction: viewModel.beginPreviewInteraction,
            endInteraction: viewModel.endPreviewInteraction
        )
    }

    /// - Parameter neutral: Where the fill is anchored. `nil` means the bottom of the range,
    ///   which is right for every amount-shaped row here — a mask's Amount, a component's Density
    ///   or Feather. The signed rows (Angle, and every local adjustment) pass theirs.
    private func maskSlider(
        _ title: String, value: Binding<Double>, range: ClosedRange<Double>,
        neutral: Double? = nil, trackStyle: SliderTrackStyle = .neutral
    ) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.caption)
                .frame(width: 82, alignment: .leading)
            NeutralOriginSlider(
                value: value, in: range, neutral: neutral ?? range.lowerBound,
                trackStyle: trackStyle,
                accessibilityTitle: title,
                accessibilityReadout: value.wrappedValue.formatted(
                    .number.precision(.fractionLength(1))),
                onEditingChanged: { editing in
                    if editing {
                        viewModel.beginPreviewInteraction()
                    } else {
                        viewModel.endPreviewInteraction()
                    }
                })
            Text(value.wrappedValue.formatted(.number.precision(.fractionLength(0))))
                .font(.caption.monospacedDigit())
                .frame(width: 42, alignment: .trailing)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
        .accessibilityValue(value.wrappedValue.formatted(.number.precision(.fractionLength(1))))
    }

    private func layerBinding<Value>(
        id: UUID, keyPath: WritableKeyPath<LocalAdjustmentLayer, Value>
    ) -> Binding<Value> {
        // SwiftUI can evaluate a binding captured by the inspector after its layer has been
        // deleted, but before the inspector subtree is removed. Keep a value snapshot for that
        // short transition instead of indexing into an array that may already be empty.
        let fallbackLayer = viewModel.document.localAdjustments.first(where: { $0.id == id })
            ?? LocalAdjustmentLayer()
        let fallbackValue = fallbackLayer[keyPath: keyPath]
        return Binding(
            get: {
                inspectorLayer(id: id)?[keyPath: keyPath] ?? fallbackValue
            },
            set: { value in viewModel.updateMask(id) { layer in layer[keyPath: keyPath] = value } }
        )
    }

    private func componentBinding(
        _ componentID: UUID, layerID: UUID, keyPath: WritableKeyPath<MaskComponent, Bool>
    ) -> Binding<Bool> {
        Binding(
            get: {
                inspectorLayer(id: layerID)?.components
                    .first(where: { $0.id == componentID })?[keyPath: keyPath] ?? false
            },
            set: { value in
                viewModel.updateMaskComponent(componentID, in: layerID) {
                    $0[keyPath: keyPath] = value
                }
            }
        )
    }

    private func componentValue(
        _ componentID: UUID, layerID: UUID, get: @escaping (MaskSource) -> Double,
        set: @escaping (inout MaskSource, Double) -> Void
    ) -> Binding<Double> {
        Binding(
            get: {
                guard let component = inspectorLayer(id: layerID)?.components.first(where: {
                    $0.id == componentID
                })
                else { return 0 }
                return get(component.source)
            },
            set: { value in
                viewModel.updateMaskComponent(componentID, in: layerID) { set(&$0.source, value) }
            }
        )
    }

    private func percentage(_ value: Double) -> String { "\(Int((value * 100).rounded()))%" }

    private func linearGuideSwatch(_ color: Color, title: String) -> some View {
        HStack(spacing: 3) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(title)
                .font(.caption2)
        }
        .foregroundStyle(.secondary)
    }
}

/// The local-adjustment row mirrors the global value-entry contract while its binding remains
/// layer-scoped. Numeric entry and slider changes therefore share the exact persisted value, and
/// the reset action cannot accidentally clear a global stage.
private struct LocalAdjustmentValueRow: View {
    let control: LocalAdjustmentControl
    @Binding var value: Double
    let reset: () -> Void
    let beginInteraction: () -> Void
    let endInteraction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                ResettableAdjustmentLabel(
                    title: control.title,
                    reset: reset
                )
                Spacer()
                TextField(
                    control.title,
                    value: $value,
                    format: .number.precision(.fractionLength(0...2))
                )
                .textFieldStyle(.roundedBorder)
                .font(.system(.caption, design: .monospaced))
                .frame(width: 78)
                .multilineTextAlignment(.trailing)
                .accessibilityLabel(control.title)
                .accessibilityValue(control.readout(value))
                .accessibilitySortPriority(1)
            }

            Group {
                if control == .temperature {
                    TemperatureSlider(
                        value: $value,
                        in: control.range,
                        neutral: control.neutral,
                        trackStyle: control.trackStyle,
                        accessibilityTitle: control.title,
                        accessibilityReadout: control.readout(value),
                        onEditingChanged: { editing in
                            if editing { beginInteraction() } else { endInteraction() }
                        },
                        step: control.step
                    )
                } else {
                    NeutralOriginSlider(
                        value: $value,
                        in: control.range,
                        neutral: control.neutral,
                        step: control.step,
                        trackStyle: control.trackStyle,
                        accessibilityTitle: control.title,
                        accessibilityReadout: control.readout(value),
                        onEditingChanged: { editing in
                            if editing { beginInteraction() } else { endInteraction() }
                        }
                    )
                }
            }
            .accessibilityLabel(control.title)
            .accessibilityValue(control.readout(value))
            .accessibilitySortPriority(0)
            .accessibilityAction(named: Text("Reset to neutral"), reset)
        }
    }
}

fileprivate extension LocalAdjustmentControl {
    var trackStyle: SliderTrackStyle {
        switch self {
        case .temperature: return .temperature
        case .tint: return .tint
        case .saturation: return .saturation
        case .vibrance: return .vibrance
        case .exposure, .contrast, .highlights, .shadows, .whites, .blacks, .texture, .clarity,
             .dehaze:
            return .neutral
        }
    }
}

private struct MaskLayerRow: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject var maskingState: MaskInteractionState
    let layer: LocalAdjustmentLayer
    let index: Int
    let total: Int
    let isTransient: Bool

    var body: some View {
        HStack(spacing: 7) {
            Button {
                viewModel.selectMaskLayer(layer.id)
            } label: {
                Image(
                    systemName: maskingState.selectedLayerID == layer.id
                        ? "checkmark.circle.fill" : "circle"
                )
                .foregroundStyle(
                    maskingState.selectedLayerID == layer.id ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Select mask layer \(layer.name)")
            .accessibilityValue(
                maskingState.selectedLayerID == layer.id ? "Selected" : "Not selected")

            Circle()
                .fill(maskingState.overlayColor)
                .frame(width: 9, height: 9)
                .accessibilityHidden(true)

            TextField(
                "Mask name",
                text: Binding(
                    get: { layer.name },
                    set: { viewModel.renameMask(layer.id, name: $0) }
                )
            )
            .textFieldStyle(.plain)
            .font(.caption.weight(.medium))

            Text(layer.maskingSummary)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Toggle(
                "Enabled",
                isOn: Binding(
                    get: { layer.isEnabled },
                    set: { value in viewModel.updateMask(layer.id) { $0.isEnabled = value } }
                )
            )
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
            .accessibilityLabel("Enable \(layer.name)")
            .accessibilityValue(layer.isEnabled ? "On" : "Off")

            Menu {
                Button("Move up") { viewModel.moveMask(layer.id, by: -1) }
                    .disabled(isTransient || index == 0)
                Button("Move down") { viewModel.moveMask(layer.id, by: 1) }
                    .disabled(isTransient || index == total - 1)
                Divider()
                Button("Solo") { maskingState.toggleSolo(layerID: layer.id) }
                    .accessibilityLabel("Solo \(layer.name)")
                    .accessibilityValue(maskingState.soloLayerID == layer.id ? "On" : "Off")
                Button("Duplicate") { viewModel.duplicateMask(layer.id) }
                    .disabled(isTransient)
                Button("Reset") { viewModel.resetMask(layer.id) }
                Button("Delete", role: .destructive) {
                    if isTransient {
                        viewModel.cancelMaskGesture()
                    } else {
                        viewModel.deleteMask(layer.id)
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .accessibilityLabel("Actions for \(layer.name)")
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 5)
        .background(
            maskingState.selectedLayerID == layer.id ? Color.accentColor.opacity(0.12) : .clear,
            in: RoundedRectangle(cornerRadius: 6)
        )
        .accessibilityElement(children: .contain)
    }
}

extension MaskCreationKind {
    fileprivate var iconName: String {
        switch self {
        case .subject: return "person.crop.square"
        case .person: return "figure.stand"
        case .face: return "face.smiling"
        case .foreground: return "person.crop.square"
        case .background: return "photo"
        case .brush: return "paintbrush"
        case .erase: return "eraser"
        case .linear: return "line.diagonal"
        case .radial: return "oval"
        }
    }

    fileprivate var maskSource: MaskSource {
        switch self {
        case .subject: return .semantic(SemanticMaskDefinition(target: .subject))
        case .person: return .semantic(SemanticMaskDefinition(target: .person))
        case .face: return .semantic(SemanticMaskDefinition(target: .face))
        case .foreground: return .semantic(SemanticMaskDefinition(target: .foreground))
        case .background: return .semantic(SemanticMaskDefinition(target: .background))
        case .brush: return .brush(BrushMaskDefinition())
        case .erase: return .brush(BrushMaskDefinition())
        case .linear: return .linear(LinearGradientDefinition())
        case .radial: return .radial(RadialGradientDefinition())
        }
    }
}

/// Lightweight, presentation-only canvas guides for the saved component definition. The renderer
/// remains responsible for mask pixels; these guides give gradient/brush authors immediate handles
/// without putting pointer-frequency geometry into AppViewModel's published document.
struct MaskCanvasOverlay: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject var maskingState: MaskInteractionState
    let sourceSize: CGSize
    let crop: CropAdjustments
    let navigation: CanvasNavigation
    let backingScale: CGFloat

    @State private var isDrawing = false
    @State private var lastPanPoint: CGPoint?
    @State private var gestureStartViewportPoint: CGPoint?
    @State private var maskImage: CGImage?

    var body: some View {
        GeometryReader { geometry in
            let transform = CanvasMaskTransform(
                sourceSize: sourceSize, crop: crop, navigation: navigation,
                viewportSize: geometry.size, backingScale: backingScale
            )
            let targetSize = maskTargetSize(for: transform, viewportSize: geometry.size)
            // The cached overlay represents only completed work for brush strokes: the
            // active brush draft is drawn by the Metal presentation guide below, so a
            // 30-second stroke cannot invalidate and rerasterize the entire completed
            // history for every pointer sample. Linear/radial drafts are the opposite:
            // the single analytic definition *is* the mask, so the draft is folded into
            // the overlay layers. Without this the gradient wash never appears during a
            // drag (linear only looked alive because of its synthetic zone fills, and
            // radial showed just its ellipse tooling).
            let documentLayers = viewModel.document.localAdjustments
            let layers = overlayLayers(document: documentLayers, draft: gradientDraftForOverlay)
            // Brush drafts are presented as lightweight Canvas guides while the committed layer
            // remains the resolved wash. In particular an active subtractive brush must keep the
            // existing semantic/gradient coverage visible; inspecting the new brush component by
            // itself would make the base mask appear to vanish during an erase gesture.
            let overlayComponentID = brushDraftKeepsEffectiveOverlay
                ? nil : maskingState.selectedComponentID
            let style = overlayStyle
            let presentation = MaskOverlayPresentation(
                coverageOpacity: maskingState.overlayOpacity)
            let taskID = OverlayTaskID(
                layers: layers,
                selectedLayerID: maskingState.selectedLayerID,
                soloLayerID: maskingState.soloLayerID,
                selectedComponentID: overlayComponentID,
                soloComponentID: maskingState.soloComponentID,
                assetID: viewModel.maskingAssetID,
                sourceFingerprint: viewModel.maskingSource?.cacheFingerprint ?? "missing",
                requestRevision: viewModel.maskingSourceRevision,
                targetSize: targetSize,
                style: style,
                resolveEpoch: maskingState.maskResolveEpoch
            )
            ZStack {
                Canvas { context, _ in
                    draw(
                        layer: activeLayer, maskImage: maskImage, transform: transform,
                        presentation: presentation, in: &context
                    )
                }
                MaskPointerSurface(
                    isInteractive: maskingState.activeTool != .selection
                        && !viewModel.isCropToolActive
                ) { event in
                    handleNativePointer(event, transform: transform, viewportSize: geometry.size)
                }
            }
            .accessibilityLabel(canvasAccessibilityLabel)
            .accessibilityValue(canvasAccessibilityValue)
            .task(id: taskID) {
                let semanticTarget = selectedSemanticTarget(
                    in: layers,
                    selectedLayerID: maskingState.selectedLayerID,
                    selectedComponentID: overlayComponentID,
                    soloComponentID: maskingState.soloComponentID
                )
                if semanticTarget != nil {
                    maskingState.beginMaskResolution()
                }
                // Explicit person requests establish the provider gate signals first: cached
                // hits when warm, Vision-backed computation when cold. Without this a cold
                // store fails the gate permanently — the overlay has no analyze preflight.
                if semanticTarget == .person {
                    await viewModel.warmPersonSignals()
                }
                let resolved = await viewModel.renderMaskOverlay(
                    layers: layers,
                    selectedLayerID: maskingState.selectedLayerID,
                    soloLayerID: maskingState.soloLayerID,
                    targetSize: targetSize,
                    style: style,
                    selectedComponentID: overlayComponentID,
                    soloComponentID: maskingState.soloComponentID
                )
                guard !Task.isCancelled else { return }
                maskImage = resolved
                if semanticTarget != nil {
                    if resolved == nil {
                        maskingState.markMaskUnavailable(
                            "The selected semantic mask could not be resolved for this photo."
                        )
                    } else {
                        maskingState.markMaskResolved()
                    }
                } else {
                    maskingState.markMaskResolved()
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Mask canvas")
        .accessibilityHint("Drag to edit the selected brush, linear, or radial mask")
        .accessibilityAction(named: "Move mask left") {
            _ = viewModel.nudgeSelectedMask(dx: -1, dy: 0)
        }
        .accessibilityAction(named: "Move mask right") {
            _ = viewModel.nudgeSelectedMask(dx: 1, dy: 0)
        }
        .accessibilityAction(named: "Move mask up") {
            _ = viewModel.nudgeSelectedMask(dx: 0, dy: -1)
        }
        .accessibilityAction(named: "Move mask down") {
            _ = viewModel.nudgeSelectedMask(dx: 0, dy: 1)
        }
    }

    private func handleNativePointer(
        _ event: MaskNativePointerEvent, transform: CanvasMaskTransform,
        viewportSize: CGSize
    ) {
        func updateHover(_ sample: MaskNativePointerSample) {
            maskingState.updateHoverPoint(transform.sourceNormalizedPoint(forViewport: sample.point))
            maskingState.updateLinearHover(
                maskingState.activeTool == .linear
                    ? linearHandle(at: sample.point, transform: transform) : nil
            )
        }
        func pan(_ sample: MaskNativePointerSample) {
            guard let lastPanPoint else { self.lastPanPoint = sample.point; return }
            viewModel.panCanvas(
                by: CGSize(width: sample.point.x - lastPanPoint.x,
                           height: sample.point.y - lastPanPoint.y),
                viewportSize: viewportSize)
            self.lastPanPoint = sample.point
        }

        func sourceDelta(for sample: MaskNativePointerSample) -> CGPoint? {
            guard let start = gestureStartViewportPoint else { return nil }
            return transform.sourceNormalizedDelta(forViewportDelta: CGSize(
                width: sample.point.x - start.x,
                height: sample.point.y - start.y
            ))
        }

        switch event {
        case .moved(let samples):
            if let sample = samples.last { updateHover(sample) }
        case .began(let samples):
            guard let first = samples.first else { return }
            updateHover(first)
            if maskingState.isSpacePanning {
                lastPanPoint = first.point
                return
            }
            guard let point = transform.sourceNormalizedPoint(forViewport: first.point) else { return }
            isDrawing = true
            gestureStartViewportPoint = first.point
            let handle = linearHandle(at: first.point, transform: transform) ?? .creation
            let radial = radialHandle(at: first.point, transform: transform)
            viewModel.beginMaskGesture(
                at: point, linearHandle: handle, radialHandle: radial,
                sourceSize: transform.sourceSize, pressure: first.pressure,
                modifiers: NSEvent.modifierFlags)
            for sample in samples.dropFirst() {
                guard let point = transform.sourceNormalizedPoint(forViewport: sample.point) else { continue }
                viewModel.updateMaskGesture(
                    to: point, pressure: sample.pressure, modifiers: NSEvent.modifierFlags,
                    sourceDelta: sourceDelta(for: sample))
            }
        case .dragged(let samples):
            for sample in samples {
                updateHover(sample)
                if maskingState.isSpacePanning {
                    pan(sample)
                } else if let point = transform.sourceNormalizedPoint(forViewport: sample.point) {
                    viewModel.updateMaskGesture(
                        to: point, pressure: sample.pressure, modifiers: NSEvent.modifierFlags,
                        sourceDelta: sourceDelta(for: sample))
                }
            }
        case .ended(let sample):
            if let sample {
                updateHover(sample)
                if maskingState.isSpacePanning {
                    lastPanPoint = nil
                } else if let point = transform.sourceNormalizedPoint(forViewport: sample.point) {
                    viewModel.updateMaskGesture(
                        to: point, pressure: sample.pressure, modifiers: NSEvent.modifierFlags,
                        sourceDelta: sourceDelta(for: sample))
                }
            }
            if !maskingState.isSpacePanning, isDrawing {
                isDrawing = false
                gestureStartViewportPoint = nil
                viewModel.endMaskGesture()
            }
        }
    }

    private var activeLayer: LocalAdjustmentLayer? {
        guard let id = maskingState.selectedLayerID else { return nil }
        if let draft = maskingState.draftLayer, draft.id == id { return draft }
        return viewModel.document.localAdjustments.first(where: { $0.id == id })
    }

    private func selectedSemanticTarget(
        in layers: [LocalAdjustmentLayer], selectedLayerID: UUID?,
        selectedComponentID: UUID?, soloComponentID: UUID?
    ) -> SemanticTarget? {
        guard let selectedLayerID,
              let layer = layers.first(where: { $0.id == selectedLayerID }) else { return nil }
        let componentID = soloComponentID ?? selectedComponentID
        let component = componentID.flatMap { id in layer.components.first(where: { $0.id == id }) }
            ?? layer.components.first
        guard let component, case .semantic(let definition) = component.source else { return nil }
        return definition.target
    }

    private var brushDraftKeepsEffectiveOverlay: Bool {
        guard maskingState.hasDraft else { return false }
        return maskingState.activeTool == .brush || maskingState.activeTool == .erase
    }

    private var overlayStyle: MaskOverlayStyle {
        let color = NSColor(maskingState.overlayColor).usingColorSpace(.sRGB) ?? .orange
        var red: CGFloat = 1
        var green: CGFloat = 0.5
        var blue: CGFloat = 0
        var alpha: CGFloat = 1
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return MaskOverlayStyle(
            inspection: maskingState.overlayInspection == .grayscale ? .grayscale : .colorWash,
            red: red, green: green, blue: blue
        )
    }

    /// The in-progress draft, but only when it targets a gradient component. Brush drafts
    /// stay on the Metal fast path and must not join the rasterized overlay layers; gradient
    /// drafts are single analytic definitions whose wash (including feather falloff) should
    /// track the pointer live, during creation as well as handle drags and slider edits.
    private var gradientDraftForOverlay: LocalAdjustmentLayer? {
        guard let draft = maskingState.draftLayer,
              let index = draft.targetComponentIndex(
                selected: maskingState.selectedComponentID)
        else { return nil }
        switch draft.components[index].source {
        case .linear, .radial:
            return draft
        case .brush, .semantic:
            return nil
        }
    }

    private func overlayLayers(
        document: [LocalAdjustmentLayer], draft: LocalAdjustmentLayer?
    ) -> [LocalAdjustmentLayer] {
        guard let draft else { return document }
        var combined = document
        if let index = combined.firstIndex(where: { $0.id == draft.id }) {
            combined[index] = draft
        } else {
            combined.append(draft)
        }
        return combined
    }

    private func maskTargetSize(
        for transform: CanvasMaskTransform, viewportSize: CGSize
    ) -> PixelDimensions {
        let source = transform.sourceSize
        let maximumDimension = max(
            256,
            max(viewportSize.width, viewportSize.height) * max(backingScale, 1)
        )
        let scale = min(1, maximumDimension / max(source.width, source.height))
        return PixelDimensions(
            width: max(1, Int((source.width * scale).rounded())),
            height: max(1, Int((source.height * scale).rounded()))
        )
    }

    private struct OverlayTaskID: Equatable {
        let layers: [LocalAdjustmentLayer]
        let selectedLayerID: UUID?
        let soloLayerID: UUID?
        let selectedComponentID: UUID?
        let soloComponentID: UUID?
        let assetID: PhotoAssetID?
        let sourceFingerprint: String
        let requestRevision: UInt64
        let targetSize: PixelDimensions
        let style: MaskOverlayStyle
        let resolveEpoch: UInt64
    }

    private func draw(
        layer: LocalAdjustmentLayer?, maskImage: CGImage?, transform: CanvasMaskTransform,
        presentation: MaskOverlayPresentation, in context: inout GraphicsContext
    ) {
        if let maskImage,
            let imageRect = transform.viewportRect(
                forSourceNormalized: CGRect(x: 0, y: 0, width: 1, height: 1)
            ),
            let visibleRect = transform.viewportRect(forSourceNormalized: transform.cropRect) {
            var maskContext = context
            maskContext.opacity = presentation.coverageOpacity
            maskContext.clip(to: Path(visibleRect))
            maskContext.draw(
                Image(decorative: maskImage, scale: 1, orientation: .up), in: imageRect
            )
        }

        guard let layer,
            let index = layer.targetComponentIndex(selected: maskingState.selectedComponentID)
        else { return }
        let component = layer.components[index]
        let guideColor =
            maskingState.overlayInspection == .grayscale
            ? Color.white.opacity(presentation.toolingOpacity)
            : Color(
                red: overlayStyle.red, green: overlayStyle.green, blue: overlayStyle.blue
            ).opacity(presentation.toolingOpacity)

        func point(_ normalized: CGPoint) -> CGPoint? {
            transform.viewportPoint(forSourceNormalized: normalized)
        }

        switch component.source {
        case .semantic:
            let rect = CGRect(origin: .zero, size: transform.viewportSize).insetBy(dx: 10, dy: 10)
            context.stroke(
                Path(rect), with: .color(guideColor),
                style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
        case .brush(let definition):
            for stroke in definition.strokes {
                var path = Path()
                for (index, sample) in stroke.samples.enumerated() {
                    guard let viewportPoint = point(sample.point) else { continue }
                    if index == 0 {
                        path.move(to: viewportPoint)
                    } else {
                        path.addLine(to: viewportPoint)
                    }
                }
                let sourceRadius = stroke.radius
                    * Double(min(transform.sourceSize.width, transform.sourceSize.height))
                    / max(transform.sourceSize.width, 1)
                let center = stroke.samples.last?.point ?? .zero
                let viewportRadius: CGFloat
                if let centerPoint = point(center),
                   let edgePoint = point(CGPoint(
                       x: min(max(center.x + sourceRadius, 0), 1), y: center.y)) {
                    viewportRadius = max(1, abs(edgePoint.x - centerPoint.x))
                } else {
                    viewportRadius = 1
                }
                context.stroke(
                    path, with: .color(guideColor),
                    style: StrokeStyle(
                        lineWidth: viewportRadius * 2, lineCap: .round, lineJoin: .round))
            }
            if let hover = maskingState.hoverPoint,
               let center = point(hover),
               let activeStroke = definition.strokes.last,
               let edge = point(CGPoint(
                   x: hover.x + (maskingState.hasDraft
                       ? activeStroke.radius : maskingState.brushRadius)
                       * Double(min(transform.sourceSize.width, transform.sourceSize.height))
                       / max(transform.sourceSize.width, 1),
                   y: hover.y)) {
                let radius = max(5, abs(edge.x - center.x))
                context.stroke(
                    Path(ellipseIn: CGRect(
                        x: center.x - radius, y: center.y - radius,
                        width: radius * 2, height: radius * 2)),
                    with: .color(guideColor), style: StrokeStyle(lineWidth: 1.5))
                context.fill(
                    Path(ellipseIn: CGRect(x: center.x - 1, y: center.y - 1, width: 2, height: 2)),
                    with: .color(guideColor))
            }
        case .linear(let definition):
            guard let start = point(definition.zeroStrengthPoint),
                let end = point(definition.fullStrengthPoint)
            else { return }
            drawLinearGuide(
                start: start, end: end, transform: transform,
                in: &context
            )
        case .radial(let definition):
            guard let center = point(definition.center) else { return }
            let outer = radialGuidePoints(
                definition: definition, scale: 1, transform: transform)
            let inner = radialGuidePoints(
                definition: definition, scale: max(0, 1 - definition.feather), transform: transform)
            context.stroke(
                Path { path in
                    guard let first = outer.first else { return }
                    path.move(to: first)
                    for value in outer.dropFirst() { path.addLine(to: value) }
                }, with: .color(guideColor), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
            context.stroke(
                Path { path in
                    guard let first = inner.first else { return }
                    path.move(to: first)
                    for value in inner.dropFirst() { path.addLine(to: value) }
                }, with: .color(guideColor.opacity(0.75)), style: StrokeStyle(lineWidth: 1.5))

            drawHandle(at: center, in: &context, color: guideColor)
            for parameter in [0.0, .pi / 2, .pi, .pi * 1.5] {
                if let handle = radialGuidePoint(
                    definition: definition, parameter: parameter, scale: 1, transform: transform) {
                    drawHandle(at: handle, in: &context, color: guideColor)
                }
            }
            for parameter in [Double.pi / 4, Double.pi * 3 / 4,
                              Double.pi * 5 / 4, Double.pi * 7 / 4] {
                if let handle = radialGuidePoint(
                    definition: definition, parameter: parameter, scale: 1, transform: transform) {
                    drawHandle(at: handle, in: &context, color: guideColor)
                }
            }
            if let innerHandle = radialGuidePoint(
                definition: definition, parameter: 0, scale: max(0, 1 - definition.feather),
                transform: transform) {
                drawHandle(at: innerHandle, in: &context, color: guideColor.opacity(0.8))
            }
            let outerTop = radialGuidePoint(
                definition: definition, parameter: -.pi / 2, scale: 1, transform: transform)
            let rotationHandle: CGPoint
            if let outerTop {
                let dx = outerTop.x - center.x
                let dy = outerTop.y - center.y
                let length = max(hypot(dx, dy), 0.001)
                rotationHandle = CGPoint(
                    x: outerTop.x + dx / length * 30,
                    y: outerTop.y + dy / length * 30)
            } else {
                rotationHandle = CGPoint(x: center.x, y: center.y - 30)
            }
            context.stroke(
                Path { path in
                    path.move(to: center)
                    path.addLine(to: rotationHandle)
                }, with: .color(guideColor), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
            drawHandle(at: rotationHandle, in: &context, color: guideColor)
        }
    }

    private func drawHandle(at point: CGPoint, in context: inout GraphicsContext, color: Color) {
        context.fill(
            Path(ellipseIn: CGRect(x: point.x - 5, y: point.y - 5, width: 10, height: 10)),
            with: .color(color))
    }

    /// Draw the linear guide handles. The resolved overlay image above is the source of truth for
    /// coverage and already contains the renderer's smoothstep falloff. Constant-opacity zone
    /// fills here used to sit on top of that image and made the color wash read like a flat tint.
    private func drawLinearGuide(
        start: CGPoint, end: CGPoint, transform: CanvasMaskTransform,
        in context: inout GraphicsContext
    ) {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = max(hypot(dx, dy), 0.001)
        let direction = CGPoint(x: dx / length, y: dy / length)
        let normal = CGPoint(x: -direction.y, y: direction.x)
        let center = CGPoint(x: (start.x + end.x) * 0.5, y: (start.y + end.y) * 0.5)
        let halfBarLength = min(
            max(transform.viewportSize.width, transform.viewportSize.height) * 0.12, 64)
        let rotationHandle = CGPoint(
            x: center.x + normal.x * 34, y: center.y + normal.y * 34)
        let isToolActive = maskingState.activeTool == .linear
        let baseOpacity = isToolActive ? 1.0 : 0.55
        let handles: [(MaskInteractionState.LinearHandle, CGPoint, Color, Bool)] = [
            (.zeroStrength, start, Color.gray, false),
            (.center, center, Color.orange, true),
            (.fullStrength, end, Color.cyan, false),
            (.rotation, rotationHandle, Color.purple, false),
        ]

        for (handle, point, color, solid) in handles {
            let isActive = maskingState.activeLinearHandle == handle
            let isHovered = maskingState.hoveredLinearHandle == handle
            let lineWidth: CGFloat = isActive ? 4 : (isHovered ? 3 : (solid ? 2 : 1.5))
            let style = StrokeStyle(
                lineWidth: lineWidth, lineCap: .round, dash: solid ? [] : [5, 3])
            let barPath: Path
            if handle == .rotation {
                barPath = Path { path in
                    path.move(to: center)
                    path.addLine(to: point)
                }
            } else {
                let barStart = CGPoint(
                    x: point.x - normal.x * halfBarLength,
                    y: point.y - normal.y * halfBarLength)
                let barEnd = CGPoint(
                    x: point.x + normal.x * halfBarLength,
                    y: point.y + normal.y * halfBarLength)
                barPath = Path { path in
                    path.move(to: barStart)
                    path.addLine(to: barEnd)
                }
            }
            context.stroke(
                barPath, with: .color(Color.black.opacity(0.7 * baseOpacity)),
                style: StrokeStyle(
                    lineWidth: lineWidth + 3, lineCap: .round, dash: style.dash))
            context.stroke(
                barPath, with: .color(color.opacity(baseOpacity)), style: style)

            let radius: CGFloat = isActive ? 8 : (isHovered ? 7 : 6)
            context.fill(
                Path(ellipseIn: CGRect(
                    x: point.x - radius, y: point.y - radius,
                    width: radius * 2, height: radius * 2)),
                with: .color(Color.black.opacity(0.8)))
            context.fill(
                Path(ellipseIn: CGRect(
                    x: point.x - radius + 1.5, y: point.y - radius + 1.5,
                    width: (radius - 1.5) * 2, height: (radius - 1.5) * 2)),
                with: .color(color.opacity(baseOpacity)))
        }
    }

    private var canvasAccessibilityLabel: String {
        guard let layer = activeLayer,
            let index = layer.targetComponentIndex(selected: maskingState.selectedComponentID)
        else { return "Mask canvas" }
        if case .linear = layer.components[index].source {
            return "Linear gradient handles: zero-strength edge, center translation bar, "
            + "full-strength edge, and rotation handle"
        }
        if case .radial = layer.components[index].source {
            return "Radial gradient handles: center, horizontal and vertical radius, corner, "
                + "inner feather boundary, and rotation"
        }
        return "Mask canvas"
    }

    private var canvasAccessibilityValue: String {
        guard let layer = activeLayer,
            let index = layer.targetComponentIndex(selected: maskingState.selectedComponentID),
            let source = Optional(layer.components[index].source)
        else { return "" }
        switch source {
        case .linear(let definition):
            let angle = Int(definition.angleDegrees.rounded())
            let falloff = definition.falloff.formatted(
                .number.precision(.fractionLength(2)))
            let active = maskingState.activeLinearHandle.map {
                ", editing \($0.accessibilityTitle)"
            } ?? ""
            return "Zero-strength side to full-strength side, angle \(angle) degrees, "
                + "transition width \(falloff)\(active)"
        case .radial(let definition):
            let angle = Int((definition.rotation * 180 / .pi).rounded())
            return "Angle \(angle) degrees, horizontal radius "
                + definition.horizontalRadius.formatted(.number.precision(.fractionLength(2)))
                + ", vertical radius "
                + definition.verticalRadius.formatted(.number.precision(.fractionLength(2)))
                + ", feather \(Int((definition.feather * 100).rounded())) percent"
        default:
            return ""
        }
    }

    private func linearHandle(
        at viewportPoint: CGPoint, transform: CanvasMaskTransform
    ) -> MaskInteractionState.LinearHandle? {
        guard !maskingState.linearCreationPending else { return nil }
        guard let layer = activeLayer,
            let index = layer.targetComponentIndex(selected: maskingState.selectedComponentID),
            case .linear(let definition) = layer.components[index].source,
            let zero = transform.viewportPoint(forSourceNormalized: definition.zeroStrengthPoint),
            let full = transform.viewportPoint(forSourceNormalized: definition.fullStrengthPoint)
        else { return nil }

        let center = CGPoint(x: (zero.x + full.x) * 0.5, y: (zero.y + full.y) * 0.5)
        let dx = full.x - zero.x
        let dy = full.y - zero.y
        let length = max(hypot(dx, dy), 0.001)
        let normal = CGPoint(x: -dy / length, y: dx / length)
        let halfBarLength = min(
            max(transform.viewportSize.width, transform.viewportSize.height) * 0.12, 64)
        let rotation = CGPoint(x: center.x + normal.x * 34, y: center.y + normal.y * 34)
        let bars = [
            (MaskInteractionState.LinearHandle.zeroStrength, zero),
            (.center, center),
            (.fullStrength, full),
        ]

        if distance(viewportPoint, rotation) <= 16 { return .rotation }
        let hits = bars.compactMap { handle, bar -> (handle: MaskInteractionState.LinearHandle, distance: CGFloat)? in
            let first = CGPoint(x: bar.x - normal.x * halfBarLength,
                                y: bar.y - normal.y * halfBarLength)
            let second = CGPoint(x: bar.x + normal.x * halfBarLength,
                                 y: bar.y + normal.y * halfBarLength)
            let distance = distanceToSegment(viewportPoint, first, second)
            return distance <= 14 ? (handle, distance) : nil
        }
        return hits.min { $0.distance < $1.distance }?.handle
    }

    private func radialGuidePoints(
        definition: RadialGradientDefinition,
        scale: Double,
        transform: CanvasMaskTransform
    ) -> [CGPoint] {
        (0...64).compactMap { step in
            radialGuidePoint(
                definition: definition, parameter: Double(step) / 64 * 2 * .pi,
                scale: scale, transform: transform)
        }
    }

    private func radialGuidePoint(
        definition: RadialGradientDefinition,
        parameter: Double,
        scale: Double,
        transform: CanvasMaskTransform
    ) -> CGPoint? {
        let sourcePoint = RadialGradientMaskMath.point(
            parameter, horizontalRadius: definition.horizontalRadius * scale,
            verticalRadius: definition.verticalRadius * scale, center: definition.center,
            rotation: definition.rotation, sourceSize: transform.sourceSize)
        return transform.viewportPoint(forSourceNormalized: sourcePoint)
    }

    private func radialHandle(
        at viewportPoint: CGPoint, transform: CanvasMaskTransform
    ) -> MaskInteractionState.RadialHandle? {
        guard !maskingState.radialCreationPending,
              let layer = activeLayer,
              let index = layer.targetComponentIndex(selected: maskingState.selectedComponentID),
              case .radial(let definition) = layer.components[index].source,
              let center = transform.viewportPoint(forSourceNormalized: definition.center)
        else { return nil }

        func distance(_ lhs: CGPoint, _ rhs: CGPoint) -> CGFloat {
            hypot(lhs.x - rhs.x, lhs.y - rhs.y)
        }

        let top = radialGuidePoint(
            definition: definition, parameter: -.pi / 2, scale: 1, transform: transform)
        let rotation: CGPoint
        if let top {
            let dx = top.x - center.x
            let dy = top.y - center.y
            let length = max(hypot(dx, dy), 0.001)
            rotation = CGPoint(x: top.x + dx / length * 30, y: top.y + dy / length * 30)
        } else {
            rotation = CGPoint(x: center.x, y: center.y - 30)
        }
        if distance(viewportPoint, rotation) <= 16 { return .rotation }
        if distance(viewportPoint, center) <= 16 { return .center }

        let cardinals: [(MaskInteractionState.RadialHandle, Double)] = [
            (.horizontalRadius, 0), (.verticalRadius, .pi / 2),
            (.horizontalRadius, .pi), (.verticalRadius, .pi * 1.5)
        ]
        for (handle, parameter) in cardinals {
            if let candidate = radialGuidePoint(
                definition: definition, parameter: parameter, scale: 1, transform: transform),
                distance(viewportPoint, candidate) <= 14 {
                return handle
            }
        }

        for parameter in [Double.pi / 4, Double.pi * 3 / 4,
                          Double.pi * 5 / 4, Double.pi * 7 / 4] {
            if let candidate = radialGuidePoint(
                definition: definition, parameter: parameter, scale: 1, transform: transform),
                distance(viewportPoint, candidate) <= 14 {
                return .corner
            }
        }
        if definition.feather > 0,
            let inner = radialGuidePoint(
                definition: definition, parameter: 0,
                scale: max(0, 1 - definition.feather), transform: transform),
            distance(viewportPoint, inner) <= 14 {
            return .innerBoundary
        }
        return nil
    }

    private func distance(_ lhs: CGPoint, _ rhs: CGPoint) -> CGFloat {
        hypot(lhs.x - rhs.x, lhs.y - rhs.y)
    }

    private func distanceToSegment(_ point: CGPoint, _ start: CGPoint, _ end: CGPoint) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return distance(point, start) }
        let t = min(
            max(((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared, 0), 1)
        return distance(point, CGPoint(x: start.x + t * dx, y: start.y + t * dy))
    }
}

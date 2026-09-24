import AppKit
import SwiftUI

/// Persistent local-mask editor. The workspace is an inspector tab, so it stays beside the canvas
/// while the photographer changes masks, reopens saved recipes, or switches tools.
///
/// The panel reads top to bottom in task order: choose what a canvas drag does, choose (or add) a
/// mask, then shape it and set its adjustments. Overlay inspection is presentation-only, so its
/// settings sit collapsed at the bottom and only the show/hide switch stays in the header.
struct MaskingWorkspace: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject private var maskingState: MaskInteractionState

    @State private var adjustmentsExpanded = true
    @State private var maskShapeExpanded = true
    @State private var overlayExpanded = false

    init(viewModel: AppViewModel) {
        self.viewModel = viewModel
        _maskingState = ObservedObject(wrappedValue: viewModel.maskInteractionState)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header
                if viewModel.sourceImage == nil {
                    ContentUnavailableView(
                        "No photo", systemImage: "photo",
                        description: Text("Open a photo to edit masks."))
                } else {
                    toolPicker
                    creationPrompt
                    renderStatus
                    maskList
                    selectedInspector
                    Divider()
                    overlaySection
                }
            }
            .padding(16)
        }
        .frame(minWidth: 280, idealWidth: 320)
        .onAppear { viewModel.restoreMaskSelection() }
        .onChange(of: viewModel.document.localAdjustments) { _, _ in
            viewModel.restoreMaskSelection()
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            Text("Masking")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Toggle(isOn: $maskingState.showOverlay) {
                Image(systemName: maskingState.showOverlay ? "eye" : "eye.slash")
            }
            .toggleStyle(.button)
            .buttonStyle(.borderless)
            .help("Show or hide the mask overlay. Display only; the edit is unchanged.")
            .accessibilityLabel("Show overlay")
            .accessibilityValue(maskingState.showOverlay ? "On" : "Off")
            .accessibilityHint("Presentation only; does not change the saved mask or export")
            addMaskMenu
            Button("Done") { viewModel.closeMaskingWorkspace() }
                .buttonStyle(.borderless)
                .accessibilityLabel("Close masking workspace")
        }
    }

    private var addMaskMenu: some View {
        Menu {
            Section("Smart masks") {
                ForEach(MaskCreationKind.smartKinds, id: \.self) { kind in
                    Button {
                        create(kind)
                    } label: {
                        Label(kind.title, systemImage: kind.iconName)
                    }
                }
            }
            Section("Paint and gradients") {
                ForEach(MaskCreationKind.canvasKinds, id: \.self) { kind in
                    Button {
                        create(kind)
                    } label: {
                        Label(kind.title, systemImage: kind.iconName)
                    }
                }
            }
        } label: {
            Label("Add Mask", systemImage: "plus")
        }
        .fixedSize()
        .accessibilityLabel("Add mask layer")
        .help("Create a new mask")
    }

    /// Smart masks are preflighted by the analysis provider before they enter the document; the
    /// paint and gradient kinds are created directly.
    private func create(_ kind: MaskCreationKind) {
        if kind.isSmart {
            viewModel.createSmartMask(kind)
        } else {
            viewModel.createMask(kind)
        }
    }

    // MARK: Canvas tool

    private var toolPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker(
                "Canvas tool",
                selection: Binding(
                    get: { maskingState.activeTool },
                    set: { viewModel.setMaskTool($0) }
                )
            ) {
                ForEach(MaskInteractionState.Tool.allCases, id: \.self) { tool in
                    Label(tool.title, systemImage: tool.iconName)
                        .labelStyle(.iconOnly)
                        .accessibilityLabel("Mask tool \(tool.title)")
                        .help(tool.helpText)
                        .tag(tool)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityLabel("Canvas tool")
            .accessibilityValue(maskingState.activeTool.title)

            Text(toolGuidance)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if maskingState.activeTool == .brush || maskingState.activeTool == .erase {
                brushControls
            }
        }
    }

    /// One sentence describing what a canvas drag will do right now, so the tool, the selected
    /// mask, and the result are never left for the photographer to infer.
    private var toolGuidance: String {
        let selected = maskingState.selectedLayerID.flatMap(inspectorLayer(id:))
        switch maskingState.activeTool {
        case .selection:
            return selected == nil
                ? "Add a mask, or pick a tool to paint or draw one on the photo."
                : "Pick a tool to paint or draw on the photo."
        case .brush:
            return selected.map { "Paint on the photo to add to \($0.name)." }
                ?? "Select a mask below, or add a Brush mask, to start painting."
        case .erase:
            return selected.map { "Paint on the photo to remove from \($0.name)." }
                ?? "Select a mask below to erase from it."
        case .linear:
            return selectedGradientKind == .linear
                ? "Drag the bars to move, resize, or rotate. Drag elsewhere to redraw."
                : "Drag across the photo to draw a new linear gradient mask."
        case .radial:
            return selectedGradientKind == .radial
                ? "Drag the handles to move, resize, or rotate. Drag elsewhere to redraw."
                : "Drag on the photo to draw a new radial gradient mask."
        }
    }

    private var selectedGradientKind: MaskInteractionState.Tool? {
        guard let id = maskingState.selectedLayerID, let layer = inspectorLayer(id: id),
              let index = layer.targetComponentIndex(selected: maskingState.selectedComponentID)
        else { return nil }
        switch layer.components[index].source {
        case .linear: return .linear
        case .radial: return .radial
        case .brush, .semantic: return nil
        }
    }

    private var brushControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            brushSlider("Size", value: $maskingState.brushRadius, range: 0.001...0.5)
            brushSlider("Feather", value: $maskingState.brushFeather, range: 0...1)
            brushSlider("Flow", value: $maskingState.brushFlow, range: 0...1)
            brushSlider("Density", value: $maskingState.brushDensity, range: 0...1)
            Text("[ ] size · Shift-[ ] feather · Space pan")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(9)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Brush settings")
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
            statusBanner(
                title: "Mask analysis unavailable", message: message,
                retryTitle: "Retry mask analysis", retry: viewModel.retryMaskAnalysis)
        case .failed(let message):
            statusBanner(
                title: "Mask analysis failed", message: message,
                retryTitle: "Retry mask analysis", retry: viewModel.retryMaskAnalysis)
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
            statusBanner(
                title: "Preview unavailable", message: viewModel.statusMessage,
                retryTitle: "Retry preview", retry: viewModel.retryPreview)
                .accessibilityHint("Retry without discarding the saved mask definition")
        default:
            EmptyView()
        }
    }

    private func statusBanner(
        title: String, message: String, retryTitle: String, retry: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: "exclamationmark.triangle")
                .font(.caption.weight(.semibold))
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
            Button(retryTitle, action: retry)
                .buttonStyle(.borderless)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
    }

    // MARK: Masks

    @ViewBuilder
    private var maskList: some View {
        let layers = visibleLayers
        VStack(alignment: .leading, spacing: 4) {
            Text("Masks")
                .font(.subheadline.weight(.semibold))
                .accessibilityAddTraits(.isHeader)

            if layers.isEmpty {
                emptyMaskChooser
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

    /// With no masks yet, the choice of mask *is* the next step, so offer it directly rather than
    /// a generic create button that has to guess a kind.
    private var emptyMaskChooser: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Choose what to select. Each mask carries its own adjustments.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 116), spacing: 6)], alignment: .leading,
                spacing: 6
            ) {
                ForEach(MaskCreationKind.allAddable, id: \.self) { kind in
                    Button {
                        create(kind)
                    } label: {
                        Label(kind.title, systemImage: kind.iconName)
                            .font(.caption)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Add \(kind.title) mask")
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var visibleLayers: [LocalAdjustmentLayer] {
        var layers = viewModel.document.localAdjustments
        if let draft = maskingState.draftLayer,
           !layers.contains(where: { $0.id == draft.id }) {
            layers.append(draft)
        }
        return layers
    }

    // MARK: Selected mask

    @ViewBuilder
    private var selectedInspector: some View {
        if let id = maskingState.selectedLayerID,
            let layer = inspectorLayer(id: id)
        {
            VStack(alignment: .leading, spacing: 12) {
                Divider()
                HStack(alignment: .firstTextBaseline) {
                    Text(layer.name)
                        .font(.headline)
                        .lineLimit(1)
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    Button("Reset Mask") { viewModel.resetMask(id) }
                        .buttonStyle(.link)
                        .accessibilityHint("Restore this mask's saved controls to their defaults")
                }

                InspectorDisclosure("Adjustments", isExpanded: $adjustmentsExpanded) {
                    VStack(alignment: .leading, spacing: 10) {
                        maskSlider(
                            "Amount", value: layerBinding(id: id, keyPath: \.amount),
                            range: 0...1
                        )
                        .help("How strongly this mask's adjustments apply")
                        ForEach(LocalAdjustmentControl.inspectorGroups, id: \.title) { group in
                            Text(group.title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.top, 4)
                                .accessibilityAddTraits(.isHeader)
                            ForEach(group.controls, id: \.self) { control in
                                localAdjustmentRow(control, layerID: id)
                            }
                        }
                    }
                    .padding(.top, 10)
                }

                InspectorDisclosure("Mask", isExpanded: $maskShapeExpanded) {
                    maskShapeSection(layer)
                        .padding(.top, 10)
                }
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

    /// A mask with one source shows that source's controls directly. The part list, with its
    /// combine modes, solo, and ordering, only appears once a mask actually combines several
    /// sources — that is the only time those controls have anything to act on.
    private func maskShapeSection(_ layer: LocalAdjustmentLayer) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Invert mask", isOn: layerBinding(id: layer.id, keyPath: \.isInverted))
                .help("Apply the adjustments everywhere this mask does not select")

            if layer.components.count == 1, let component = layer.components.first {
                HStack(spacing: 6) {
                    Label(component.source.maskingTypeTitle, systemImage: component.source.iconName)
                        .font(.caption.weight(.semibold))
                    Spacer()
                }
                componentControls(component, layerID: layer.id, allowsInvert: false)
            } else {
                ForEach(Array(layer.components.enumerated()), id: \.element.id) {
                    index, component in
                    componentRow(component, index: index, layer: layer)
                }
            }

            addToMaskMenu(layer)
        }
    }

    private func addToMaskMenu(_ layer: LocalAdjustmentLayer) -> some View {
        Menu {
            ForEach([MaskCombineMode.add, .subtract, .intersect], id: \.self) { mode in
                Section(mode.summaryWord) {
                    ForEach(MaskCreationKind.allAddable, id: \.self) { kind in
                        Button(kind.title) {
                            if kind.isSmart {
                                viewModel.addSmartMaskComponent(
                                    to: layer.id, kind: kind, mode: mode)
                            } else {
                                viewModel.addMaskComponent(to: layer.id, kind: kind, mode: mode)
                            }
                        }
                    }
                }
            }
        } label: {
            Label("Add or Subtract…", systemImage: "plus.forwardslash.minus")
                .font(.caption)
        }
        .fixedSize()
        .accessibilityLabel("Add mask component")
        .help("Combine another selection with this mask")
    }

    private func componentRow(
        _ component: MaskComponent, index: Int, layer: LocalAdjustmentLayer
    ) -> some View {
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
            componentControls(component, layerID: layer.id, allowsInvert: true)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: component.source.iconName)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                TextField(
                    component.source.maskingTypeTitle,
                    text: Binding(
                        get: { component.displayName },
                        set: { viewModel.renameMaskComponent(component.id, in: layer.id, name: $0) }
                    )
                )
                .textFieldStyle(.plain)
                .font(.caption)
                // The first part defines the starting selection; only later parts combine.
                if index > 0 {
                    componentModeMenu(component, layerID: layer.id)
                }
                Spacer()
                Button {
                    maskingState.toggleSolo(componentID: component.id, layerID: layer.id)
                } label: {
                    Image(systemName: maskingState.soloComponentID == component.id
                        ? "eye.fill" : "eye")
                }
                .buttonStyle(.borderless)
                .help("Show only this part in the overlay")
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
                    Button("Move up") {
                        viewModel.moveMaskComponent(component.id, in: layer.id, by: -1)
                    }
                    .disabled(index == 0)
                    Button("Move down") {
                        viewModel.moveMaskComponent(component.id, in: layer.id, by: 1)
                    }
                    .disabled(index == layer.components.count - 1)
                    Divider()
                    Button("Delete", role: .destructive) {
                        viewModel.deleteMaskComponent(component.id, from: layer.id)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
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

    // MARK: Overlay

    private var overlaySection: some View {
        InspectorDisclosure("Overlay", isExpanded: $overlayExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                Picker("Inspection", selection: $maskingState.overlayInspection) {
                    ForEach(MaskInteractionState.OverlayInspection.allCases, id: \.self) {
                        Text($0.title).tag($0)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                HStack {
                    Text("Color")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    ColorPicker(
                        "Overlay color", selection: $maskingState.overlayColor,
                        supportsOpacity: false
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
                Text("Display only. The overlay never changes the edit or the export.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 10)
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

    /// - Parameter allowsInvert: A single-source mask is inverted by the mask-level toggle; a
    ///   per-part invert beside it would be a second switch with the same visible effect.
    @ViewBuilder
    private func componentControls(
        _ component: MaskComponent, layerID: UUID, allowsInvert: Bool
    ) -> some View {
        if allowsInvert || component.isInverted {
            Toggle(
                "Invert component",
                isOn: componentBinding(component.id, layerID: layerID, keyPath: \.isInverted)
            )
            .font(.caption)
        }
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
            if maskingState.activeTool != .brush, maskingState.activeTool != .erase {
                Button("Paint with Brush", systemImage: "paintbrush") {
                    viewModel.setMaskTool(.brush)
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
        case .linear(let definition):
            Text(
                "On the photo, the dashed line is where the effect starts and the outer solid "
                    + "line is where it reaches full strength. Drag the center to move it or the "
                    + "small knob to rotate it."
            )
            .font(.caption2)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel(
                "Linear gradient guide: zero strength, transition, and full strength")
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

extension LocalAdjustmentControl {
    /// The same Light / Color / Effects grouping the global inspectors use, so a mask's controls
    /// are found where the photographer already expects them.
    static let inspectorGroups: [(title: String, controls: [LocalAdjustmentControl])] = [
        ("Light", [.exposure, .contrast, .highlights, .shadows, .whites, .blacks]),
        ("Color", [.temperature, .tint, .saturation, .vibrance]),
        ("Effects", [.texture, .clarity, .dehaze]),
    ]
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

/// One mask in the list. The whole row selects the mask; the type icon, name, and summary say
/// what it selects, and the switch and menu hold the few per-mask actions.
private struct MaskLayerRow: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject var maskingState: MaskInteractionState
    let layer: LocalAdjustmentLayer
    let index: Int
    let total: Int
    let isTransient: Bool

    private var isSelected: Bool { maskingState.selectedLayerID == layer.id }

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: layer.components.first?.source.iconName ?? "rectangle.dashed")
                .frame(width: 16)
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                TextField(
                    "Mask name",
                    text: Binding(
                        get: { layer.name },
                        set: { viewModel.renameMask(layer.id, name: $0) }
                    )
                )
                .textFieldStyle(.plain)
                .font(.caption.weight(.medium))
                if layer.maskingSummary != layer.name {
                    Text(layer.maskingSummary)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            if maskingState.soloLayerID == layer.id {
                Image(systemName: "eye.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help("Overlay shows only this mask")
                    .accessibilityLabel("Solo overlay on")
            }

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
            .help("Turn this mask's adjustments on or off")
            .accessibilityLabel("Enable \(layer.name)")
            .accessibilityValue(layer.isEnabled ? "On" : "Off")

            Menu {
                Button("Move up") { viewModel.moveMask(layer.id, by: -1) }
                    .disabled(isTransient || index == 0)
                Button("Move down") { viewModel.moveMask(layer.id, by: 1) }
                    .disabled(isTransient || index == total - 1)
                Divider()
                Button(
                    maskingState.soloLayerID == layer.id ? "Show All in Overlay" : "Solo in Overlay"
                ) {
                    maskingState.toggleSolo(layerID: layer.id)
                }
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
            .fixedSize()
            .accessibilityLabel("Actions for \(layer.name)")
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 6)
        .background(
            isSelected ? Color.accentColor.opacity(0.14) : .clear,
            in: RoundedRectangle(cornerRadius: 6)
        )
        .contentShape(Rectangle())
        .onTapGesture { viewModel.selectMaskLayer(layer.id) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Mask \(layer.name)")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityAction(named: "Select mask layer \(layer.name)") {
            viewModel.selectMaskLayer(layer.id)
        }
    }
}

extension MaskSource {
    fileprivate var iconName: String {
        switch self {
        case .semantic(let definition):
            switch definition.target {
            case .subject, .foreground: return "person.crop.square"
            case .person: return "figure.stand"
            case .face: return "face.smiling"
            case .background: return "photo"
            }
        case .brush: return "paintbrush"
        case .linear: return "line.diagonal"
        case .radial: return "oval"
        }
    }
}

extension MaskCreationKind {
    /// The kinds drawn on the canvas. Erase is not a mask of its own: it is the Erase tool, which
    /// subtracts from whichever mask is selected.
    fileprivate static let canvasKinds: [MaskCreationKind] = [.brush, .linear, .radial]

    fileprivate static let allAddable: [MaskCreationKind] = smartKinds + canvasKinds

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

/// The brush stroke being painted (or just committed and awaiting the resolved overlay), and
/// whether it removes coverage.
private struct LiveBrushStroke: Equatable {
    let stroke: BrushStroke
    let subtracts: Bool
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
    /// The stroke that just finished, held on screen until the re-resolved overlay that
    /// contains it arrives. Without it the stroke would vanish at mouse-up and reappear a frame
    /// later when the renderer catches up.
    @State private var settlingStroke: LiveBrushStroke?

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
            // The overlay always shows the selected mask's effective coverage — what its
            // adjustments will actually touch. Selecting a part (for example the eraser part a
            // stroke just created) must not swap the wash for that part in isolation: an erase
            // would then read as a new colored stroke instead of coverage being removed. Only an
            // explicit solo isolates a part. The live brush stroke is composited into the same
            // wash by `draw`, so painting adds color and erasing visibly removes it.
            let overlayComponentID: UUID? = nil
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
                        && !viewModel.isCropToolActive,
                    cursor: maskingState.isSpacePanning ? .openHand : .crosshair
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
                settlingStroke = nil
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
            .onChange(of: maskingState.draftLayer) { previous, current in
                guard current == nil, let previous,
                      let stroke = liveStroke(in: previous),
                      strokeWasCommitted(stroke.stroke.id)
                else {
                    if current == nil { settlingStroke = nil }
                    return
                }
                settlingStroke = stroke
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
        case .exited:
            maskingState.updateHoverPoint(nil)
            maskingState.updateLinearHover(nil)
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

    /// The stroke being painted right now: each brush gesture appends exactly one stroke to the
    /// draft's target brush part, so it is that part's last stroke.
    private func liveStroke(in draft: LocalAdjustmentLayer?) -> LiveBrushStroke? {
        guard let draft,
              maskingState.activeTool == .brush || maskingState.activeTool == .erase,
              let index = draft.targetComponentIndex(selected: maskingState.selectedComponentID),
              case .brush(let definition) = draft.components[index].source,
              let stroke = definition.strokes.last
        else { return nil }
        return LiveBrushStroke(
            stroke: stroke, subtracts: draft.components[index].mode == .subtract)
    }

    private func strokeWasCommitted(_ strokeID: UUID) -> Bool {
        viewModel.document.localAdjustments.contains { layer in
            layer.components.contains { component in
                guard case .brush(let definition) = component.source else { return false }
                return definition.strokes.contains { $0.id == strokeID }
            }
        }
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

    /// Draws the inspection wash, the live brush stroke, and the tool guides.
    ///
    /// The wash and the live stroke share one transparency layer so a stroke reads as part of the
    /// mask rather than a second overlay: painting adds the same color at the same opacity, and
    /// erasing cuts coverage out of the wash (or darkens it in grayscale inspection). Guides use
    /// one neutral language — white lines with a soft shadow and round knobs — so they stay
    /// legible on any photo and never compete with the overlay color.
    private func draw(
        layer: LocalAdjustmentLayer?, maskImage: CGImage?, transform: CanvasMaskTransform,
        presentation: MaskOverlayPresentation, in context: inout GraphicsContext
    ) {
        let grayscale = maskingState.overlayInspection == .grayscale
        let live = liveStroke(in: maskingState.draftLayer) ?? settlingStroke
        if maskImage != nil || live != nil,
            let imageRect = transform.viewportRect(
                forSourceNormalized: CGRect(x: 0, y: 0, width: 1, height: 1)),
            let visibleRect = transform.viewportRect(forSourceNormalized: transform.cropRect)
        {
            var coverage = context
            coverage.opacity = presentation.coverageOpacity
            coverage.clip(to: Path(visibleRect))
            coverage.drawLayer { wash in
                if let maskImage {
                    wash.draw(
                        Image(decorative: maskImage, scale: 1, orientation: .up), in: imageRect)
                }
                if let live {
                    drawLiveStroke(live, transform: transform, grayscale: grayscale, in: &wash)
                }
            }
        }

        drawBrushCursor(live: live, transform: transform, in: &context)

        guard let layer,
            let index = layer.targetComponentIndex(selected: maskingState.selectedComponentID)
        else { return }
        switch layer.components[index].source {
        case .semantic, .brush:
            // The wash already shows these; a frame or stroke outline would only add noise.
            break
        case .linear(let definition):
            guard
                let start = transform.viewportPoint(
                    forSourceNormalized: definition.zeroStrengthPoint),
                let end = transform.viewportPoint(
                    forSourceNormalized: definition.fullStrengthPoint)
            else { return }
            drawLinearGuide(start: start, end: end, transform: transform, in: &context)
        case .radial(let definition):
            drawRadialGuide(definition, transform: transform, in: &context)
        }
    }

    /// An approximation of the renderer's stroke, shown only until the resolved overlay catches
    /// up: a round-capped path at the stroke's density whose soft edge follows its feather.
    private func drawLiveStroke(
        _ live: LiveBrushStroke, transform: CanvasMaskTransform, grayscale: Bool,
        in wash: inout GraphicsContext
    ) {
        let points = live.stroke.samples.compactMap {
            transform.viewportPoint(forSourceNormalized: $0.point)
        }
        guard let first = points.first, let anchor = live.stroke.samples.first?.point else {
            return
        }
        let radius = viewportBrushRadius(live.stroke.radius, at: anchor, transform: transform)
        let feather = CGFloat(live.stroke.feather)
        var path = Path()
        path.move(to: first)
        for point in points.dropFirst() { path.addLine(to: point) }
        // A click is a zero-length segment; its round caps draw the dab.
        if points.count == 1 { path.addLine(to: first) }

        let paint: Color
        var strokeContext = wash
        if grayscale {
            paint = live.subtracts ? .black : .white
        } else if live.subtracts {
            paint = .black
            strokeContext.blendMode = .destinationOut
        } else {
            paint = maskingState.overlayColor
        }
        strokeContext.opacity = live.stroke.density
        strokeContext.drawLayer { stroke in
            if feather > 0 {
                stroke.addFilter(.blur(radius: radius * feather * 0.5))
            }
            stroke.stroke(
                path, with: .color(paint),
                style: StrokeStyle(
                    lineWidth: max(1, radius * 2 * (1 - feather * 0.5)),
                    lineCap: .round, lineJoin: .round))
        }
    }

    /// The brush footprint under the pointer: the outer ring is the brush size and the faint
    /// inner ring is where feathering begins. Erase uses a dashed ring so the two tools are
    /// distinguishable at a glance without a badge on the photo.
    private func drawBrushCursor(
        live: LiveBrushStroke?, transform: CanvasMaskTransform, in context: inout GraphicsContext
    ) {
        let tool = maskingState.activeTool
        guard tool == .brush || tool == .erase, !maskingState.isSpacePanning,
            let hover = maskingState.hoverPoint,
            let center = transform.viewportPoint(forSourceNormalized: hover)
        else { return }
        let painting = maskingState.hasDraft ? live : nil
        let radius = max(
            4,
            viewportBrushRadius(
                painting?.stroke.radius ?? maskingState.brushRadius, at: hover,
                transform: transform))
        let feather = CGFloat(painting?.stroke.feather ?? maskingState.brushFeather)
        let dash: [CGFloat] = tool == .erase ? [4, 3] : []
        strokeGuide(
            Path(ellipseIn: circle(center, radius)), lineWidth: 1.25, dash: dash, in: &context)
        let inner = radius * (1 - feather)
        if feather > 0.02, inner > 2 {
            strokeGuide(
                Path(ellipseIn: circle(center, inner)), lineWidth: 1, dash: dash, opacity: 0.45,
                in: &context)
        }
    }

    /// Converts a stroke radius (a fraction of the source's shorter side) to viewport points.
    private func viewportBrushRadius(
        _ radius: Double, at point: CGPoint, transform: CanvasMaskTransform
    ) -> CGFloat {
        let size = transform.sourceSize
        let normalizedX = radius * Double(min(size.width, size.height)) / max(size.width, 1)
        let step = point.x < 0.5 ? 0.001 : -0.001
        guard let center = transform.viewportPoint(forSourceNormalized: point),
            let offset = transform.viewportPoint(
                forSourceNormalized: CGPoint(x: point.x + step, y: point.y))
        else { return 1 }
        let pointsPerUnit = hypot(offset.x - center.x, offset.y - center.y) / abs(step)
        return max(1, pointsPerUnit * CGFloat(normalizedX))
    }

    private func circle(_ center: CGPoint, _ radius: CGFloat) -> CGRect {
        CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
    }

    private func strokeGuide(
        _ path: Path, lineWidth: CGFloat = 1.5, dash: [CGFloat] = [], opacity: Double = 1,
        in context: inout GraphicsContext
    ) {
        context.stroke(
            path, with: .color(.black.opacity(0.35 * opacity)),
            style: StrokeStyle(
                lineWidth: lineWidth + 2, lineCap: .round, lineJoin: .round, dash: dash))
        context.stroke(
            path, with: .color(.white.opacity(0.95 * opacity)),
            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round, dash: dash))
    }

    /// A round handle. The one being dragged or hovered takes the accent color so the
    /// photographer can see which part of the guide they have hold of.
    private func drawKnob(
        at point: CGPoint, radius: CGFloat = 5, emphasized: Bool = false, opacity: Double = 1,
        in context: inout GraphicsContext
    ) {
        let knobRadius = emphasized ? radius + 1.5 : radius
        context.fill(
            Path(ellipseIn: circle(point, knobRadius + 1.5)),
            with: .color(.black.opacity(0.3 * opacity)))
        context.fill(
            Path(ellipseIn: circle(point, knobRadius)),
            with: .color((emphasized ? Color.accentColor : .white).opacity(opacity)))
        if emphasized {
            context.stroke(
                Path(ellipseIn: circle(point, knobRadius)), with: .color(.white.opacity(opacity)),
                lineWidth: 1.5)
        }
    }

    /// Linear guide: the dashed line is where the effect starts, the solid outer line where it
    /// reaches full strength, and the center line moves the whole gradient. The resolved wash
    /// already shows the falloff, so the guide adds only geometry and handles.
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
        let opacity = maskingState.activeTool == .linear ? 1.0 : 0.6

        func isEmphasized(_ handle: MaskInteractionState.LinearHandle) -> Bool {
            maskingState.activeLinearHandle == handle || maskingState.hoveredLinearHandle == handle
        }
        func bar(through point: CGPoint) -> Path {
            Path { path in
                path.move(to: CGPoint(
                    x: point.x - normal.x * halfBarLength, y: point.y - normal.y * halfBarLength))
                path.addLine(to: CGPoint(
                    x: point.x + normal.x * halfBarLength, y: point.y + normal.y * halfBarLength))
            }
        }

        let bars: [(MaskInteractionState.LinearHandle, CGPoint, [CGFloat])] = [
            (.zeroStrength, start, [5, 4]),
            (.center, center, []),
            (.fullStrength, end, []),
        ]
        for (handle, point, dash) in bars {
            strokeGuide(
                bar(through: point), lineWidth: isEmphasized(handle) ? 2.5 : 1.5, dash: dash,
                opacity: opacity, in: &context)
        }
        strokeGuide(
            Path { path in
                path.move(to: center)
                path.addLine(to: rotationHandle)
            }, lineWidth: 1, opacity: opacity * 0.8, in: &context)
        drawKnob(at: center, emphasized: isEmphasized(.center), opacity: opacity, in: &context)
        drawKnob(
            at: rotationHandle, radius: 4.5, emphasized: isEmphasized(.rotation),
            opacity: opacity, in: &context)
    }

    /// Radial guide: the solid ellipse is the gradient's edge, the dashed inner ellipse is where
    /// feathering begins, and knobs resize (sides and corners), move (center), or rotate.
    private func drawRadialGuide(
        _ definition: RadialGradientDefinition, transform: CanvasMaskTransform,
        in context: inout GraphicsContext
    ) {
        guard let center = transform.viewportPoint(forSourceNormalized: definition.center)
        else { return }
        let opacity = maskingState.activeTool == .radial ? 1.0 : 0.6
        let active = maskingState.activeRadialHandle

        func ellipse(scale: Double) -> Path {
            let points = radialGuidePoints(
                definition: definition, scale: scale, transform: transform)
            return Path { path in
                guard let first = points.first else { return }
                path.move(to: first)
                for point in points.dropFirst() { path.addLine(to: point) }
                path.closeSubpath()
            }
        }

        strokeGuide(ellipse(scale: 1), opacity: opacity, in: &context)
        let innerScale = max(0, 1 - definition.feather)
        if definition.feather > 0.01 {
            strokeGuide(
                ellipse(scale: innerScale), lineWidth: 1, dash: [5, 4], opacity: opacity * 0.8,
                in: &context)
        }

        let top = radialGuidePoint(
            definition: definition, parameter: -.pi / 2, scale: 1, transform: transform)
        let rotationHandle: CGPoint
        if let top {
            let dx = top.x - center.x
            let dy = top.y - center.y
            let length = max(hypot(dx, dy), 0.001)
            rotationHandle = CGPoint(x: top.x + dx / length * 30, y: top.y + dy / length * 30)
        } else {
            rotationHandle = CGPoint(x: center.x, y: center.y - 30)
        }
        strokeGuide(
            Path { path in
                path.move(to: top ?? center)
                path.addLine(to: rotationHandle)
            }, lineWidth: 1, opacity: opacity * 0.8, in: &context)

        let sides: [(Double, MaskInteractionState.RadialHandle)] = [
            (0, .horizontalRadius), (.pi / 2, .verticalRadius),
            (.pi, .horizontalRadius), (.pi * 1.5, .verticalRadius),
        ]
        for (parameter, handle) in sides {
            if let point = radialGuidePoint(
                definition: definition, parameter: parameter, scale: 1, transform: transform) {
                drawKnob(at: point, emphasized: active == handle, opacity: opacity, in: &context)
            }
        }
        for parameter in [Double.pi / 4, .pi * 3 / 4, .pi * 5 / 4, .pi * 7 / 4] {
            if let point = radialGuidePoint(
                definition: definition, parameter: parameter, scale: 1, transform: transform) {
                drawKnob(
                    at: point, radius: 3.5, emphasized: active == .corner, opacity: opacity,
                    in: &context)
            }
        }
        if definition.feather > 0,
            let inner = radialGuidePoint(
                definition: definition, parameter: 0, scale: innerScale, transform: transform) {
            drawKnob(
                at: inner, radius: 4, emphasized: active == .innerBoundary,
                opacity: opacity * 0.9, in: &context)
        }
        drawKnob(at: center, emphasized: active == .center, opacity: opacity, in: &context)
        drawKnob(
            at: rotationHandle, radius: 4.5, emphasized: active == .rotation, opacity: opacity,
            in: &context)
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

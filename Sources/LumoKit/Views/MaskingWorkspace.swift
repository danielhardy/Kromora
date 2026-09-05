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
                overlayControls
                renderStatus
                layerList
                selectedInspector
            }
            .padding(12)
        }
        .frame(minWidth: 280, idealWidth: 320)
        .background(LumoTheme.windowBackground)
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
                ForEach(MaskCreationKind.allCases, id: \.self) { kind in
                    Button {
                        viewModel.createMask(kind)
                    } label: {
                        Label(kind.title, systemImage: kind.iconName)
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
                Slider(value: $maskingState.overlayOpacity, in: 0...1)
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
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Layers")
                    .font(.headline)
                Spacer()
                Text("\(viewModel.document.localAdjustments.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if viewModel.sourceImage == nil {
                ContentUnavailableView(
                    "No photo", systemImage: "photo",
                    description: Text("Open a photo to edit masks."))
            } else if viewModel.document.localAdjustments.isEmpty {
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
                ForEach(Array(viewModel.document.localAdjustments.enumerated()), id: \.element.id) {
                    index, layer in
                    MaskLayerRow(
                        viewModel: viewModel,
                        maskingState: maskingState,
                        layer: layer,
                        index: index,
                        total: viewModel.document.localAdjustments.count
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var selectedInspector: some View {
        if let id = maskingState.selectedLayerID,
            let layer = viewModel.document.localAdjustments.first(where: { $0.id == id })
        {
            VStack(alignment: .leading, spacing: 10) {
                Divider()
                Text("Layer settings")
                    .font(.headline)
                HStack {
                    Text(layer.name)
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(layer.maskingTypeTitle)
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

    private func componentInspector(_ layer: LocalAdjustmentLayer) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("Components")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Menu {
                    ForEach(MaskCreationKind.allCases, id: \.self) { kind in
                        Button(kind.title) {
                            viewModel.addMaskComponent(to: layer.id, source: kind.maskSource)
                        }
                    }
                } label: {
                    Image(systemName: "plus.circle")
                }
                .accessibilityLabel("Add mask component")
            }

            ForEach(layer.components) { component in
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Button {
                            viewModel.selectMaskComponent(component.id, in: layer.id)
                        } label: {
                            Image(
                                systemName: maskingState.selectedComponentID == component.id
                                    ? "checkmark.circle.fill" : "circle")
                            Text(component.source.maskingTypeTitle)
                                .font(.caption)
                        }
                        .buttonStyle(.borderless)
                        Spacer()
                        componentModeMenu(component, layerID: layer.id)
                        Toggle(
                            "Enabled",
                            isOn: componentBinding(
                                component.id, layerID: layer.id, keyPath: \.isEnabled)
                        )
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        Button(role: .destructive) {
                            viewModel.deleteMaskComponent(component.id, from: layer.id)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Delete \(component.source.maskingTypeTitle) component")
                    }
                    if maskingState.selectedComponentID == component.id {
                        componentControls(component, layerID: layer.id)
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
                    viewModel.updateMaskComponent(component.id, in: layerID) { $0.mode = mode }
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
        case .linear(let definition):
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
        case .radial(let definition):
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
        }
    }

    private var localAdjustmentControls: some View {
        let layerID = maskingState.selectedLayerID
        return VStack(alignment: .leading, spacing: 7) {
            Text("Local adjustments")
                .font(.subheadline.weight(.semibold))
            if let layerID {
                adjustmentSlider(
                    "Exposure", keyPath: \.exposure, range: LocalAdjustments.exposureRange,
                    layerID: layerID)
                adjustmentSlider(
                    "Contrast", keyPath: \.contrast, range: LocalAdjustments.contrastRange,
                    layerID: layerID)
                adjustmentSlider(
                    "Highlights", keyPath: \.highlights, range: LocalAdjustments.highlightsRange,
                    layerID: layerID)
                adjustmentSlider(
                    "Shadows", keyPath: \.shadows, range: LocalAdjustments.shadowsRange,
                    layerID: layerID)
                adjustmentSlider(
                    "Whites", keyPath: \.whites, range: LocalAdjustments.whitesRange,
                    layerID: layerID)
                adjustmentSlider(
                    "Blacks", keyPath: \.blacks, range: LocalAdjustments.blacksRange,
                    layerID: layerID)
                adjustmentSlider(
                    "Temperature", keyPath: \.temperature, range: LocalAdjustments.temperatureRange,
                    layerID: layerID)
                adjustmentSlider(
                    "Tint", keyPath: \.tint, range: LocalAdjustments.tintRange, layerID: layerID)
                adjustmentSlider(
                    "Saturation", keyPath: \.saturation, range: LocalAdjustments.saturationRange,
                    layerID: layerID)
                adjustmentSlider(
                    "Vibrance", keyPath: \.vibrance, range: LocalAdjustments.vibranceRange,
                    layerID: layerID)
                adjustmentSlider(
                    "Texture", keyPath: \.texture, range: LocalAdjustments.textureRange,
                    layerID: layerID)
                adjustmentSlider(
                    "Clarity", keyPath: \.clarity, range: LocalAdjustments.clarityRange,
                    layerID: layerID)
                adjustmentSlider(
                    "Dehaze", keyPath: \.dehaze, range: LocalAdjustments.dehazeRange,
                    layerID: layerID)
            }
        }
    }

    private func adjustmentSlider(
        _ title: String, keyPath: WritableKeyPath<LocalAdjustments, Double>,
        range: ClosedRange<Double>, layerID: UUID
    ) -> some View {
        let binding = Binding<Double>(
            get: {
                viewModel.document.localAdjustments.first(where: { $0.id == layerID })?.adjustments[
                    keyPath: keyPath] ?? 0
            },
            set: { value in
                viewModel.updateMask(layerID, debounced: true) {
                    $0.adjustments[keyPath: keyPath] = value
                }
            }
        )
        return maskSlider(title, value: binding, range: range)
    }

    private func maskSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>)
        -> some View
    {
        HStack(spacing: 6) {
            Text(title)
                .font(.caption)
                .frame(width: 82, alignment: .leading)
            Slider(
                value: value, in: range,
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
        Binding(
            get: {
                viewModel.document.localAdjustments.first(where: { $0.id == id })?[keyPath: keyPath]
                    ?? viewModel.document.localAdjustments[0][keyPath: keyPath]
            },
            set: { value in viewModel.updateMask(id) { layer in layer[keyPath: keyPath] = value } }
        )
    }

    private func componentBinding(
        _ componentID: UUID, layerID: UUID, keyPath: WritableKeyPath<MaskComponent, Bool>
    ) -> Binding<Bool> {
        Binding(
            get: {
                viewModel.document.localAdjustments.first(where: { $0.id == layerID })?.components
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
                guard
                    let component = viewModel.document.localAdjustments.first(where: {
                        $0.id == layerID
                    })?.components.first(where: { $0.id == componentID })
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

private struct MaskLayerRow: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject var maskingState: MaskInteractionState
    let layer: LocalAdjustmentLayer
    let index: Int
    let total: Int

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

            Text(layer.maskingTypeTitle)
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
                    .disabled(index == 0)
                Button("Move down") { viewModel.moveMask(layer.id, by: 1) }
                    .disabled(index == total - 1)
                Divider()
                Button("Solo") { maskingState.toggleSolo(layerID: layer.id) }
                Button("Duplicate") { viewModel.duplicateMask(layer.id) }
                Button("Reset") { viewModel.resetMask(layer.id) }
                Button("Delete", role: .destructive) { viewModel.deleteMask(layer.id) }
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
        case .foreground: return "person.crop.square"
        case .background: return "photo"
        case .brush: return "paintbrush"
        case .linear: return "line.diagonal"
        case .radial: return "oval"
        }
    }

    fileprivate var maskSource: MaskSource {
        switch self {
        case .foreground: return .semantic(SemanticMaskDefinition(target: .foreground))
        case .background: return .semantic(SemanticMaskDefinition(target: .background))
        case .brush: return .brush(BrushMaskDefinition())
        case .linear: return .linear(LinearGradientDefinition())
        case .radial: return .radial(RadialGradientDefinition())
        }
    }
}

extension MaskCombineMode {
    fileprivate var title: String { rawValue.capitalized }
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

    var body: some View {
        GeometryReader { geometry in
            let transform = CanvasMaskTransform(
                sourceSize: sourceSize, crop: crop, navigation: navigation,
                viewportSize: geometry.size, backingScale: backingScale
            )
            Canvas { context, _ in
                draw(layer: activeLayer, transform: transform, in: &context)
            }
            .contentShape(Rectangle())
            .allowsHitTesting(maskingState.activeTool != .selection && !viewModel.isCropToolActive)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard
                            let point = transform.sourceNormalizedPoint(forViewport: value.location)
                        else { return }
                        if !isDrawing {
                            isDrawing = true
                            viewModel.beginMaskGesture(at: point)
                        } else {
                            viewModel.updateMaskGesture(to: point)
                        }
                    }
                    .onEnded { value in
                        if let point = transform.sourceNormalizedPoint(forViewport: value.location)
                        {
                            viewModel.updateMaskGesture(to: point)
                        }
                        isDrawing = false
                        viewModel.endMaskGesture()
                    }
            )
            .onContinuousHover(coordinateSpace: .local) { phase in
                switch phase {
                case .active(let point):
                    maskingState.updateHoverPoint(
                        transform.sourceNormalizedPoint(forViewport: point))
                case .ended:
                    maskingState.updateHoverPoint(nil)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Mask canvas")
        .accessibilityHint("Drag to edit the selected brush, linear, or radial mask")
    }

    private var activeLayer: LocalAdjustmentLayer? {
        guard let id = maskingState.selectedLayerID else { return nil }
        if let draft = maskingState.draftLayer, draft.id == id { return draft }
        return viewModel.document.localAdjustments.first(where: { $0.id == id })
    }

    private func draw(
        layer: LocalAdjustmentLayer?, transform: CanvasMaskTransform,
        in context: inout GraphicsContext
    ) {
        guard let component = layer?.components.first(where: { $0.isEnabled }) else { return }
        let guideColor =
            maskingState.overlayInspection == .grayscale
            ? Color.white.opacity(maskingState.overlayOpacity)
            : maskingState.overlayColor.opacity(maskingState.overlayOpacity)

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
                context.stroke(
                    path, with: .color(guideColor),
                    style: StrokeStyle(
                        lineWidth: max(2, stroke.radius * 80), lineCap: .round, lineJoin: .round))
            }
        case .linear(let definition):
            guard let start = point(definition.zeroStrengthPoint),
                let end = point(definition.fullStrengthPoint)
            else { return }
            let dx = end.x - start.x
            let dy = end.y - start.y
            let length = max(sqrt(dx * dx + dy * dy), 0.001)
            let normal = CGPoint(x: -dy / length * 12, y: dx / length * 12)
            for offset in [-1.0, 0, 1.0] {
                var path = Path()
                path.move(
                    to: CGPoint(x: start.x + normal.x * offset, y: start.y + normal.y * offset))
                path.addLine(
                    to: CGPoint(x: end.x + normal.x * offset, y: end.y + normal.y * offset))
                context.stroke(
                    path, with: .color(guideColor),
                    style: StrokeStyle(
                        lineWidth: offset == 0 ? 2 : 1, dash: offset == 0 ? [] : [4, 3]))
            }
            drawHandle(at: start, in: &context, color: guideColor)
            drawHandle(at: end, in: &context, color: guideColor)
        case .radial(let definition):
            guard let center = point(definition.center),
                let right = point(
                    CGPoint(
                        x: definition.center.x + definition.horizontalRadius, y: definition.center.y
                    )),
                let bottom = point(
                    CGPoint(
                        x: definition.center.x, y: definition.center.y + definition.verticalRadius))
            else { return }
            let rect = CGRect(
                x: center.x - abs(right.x - center.x), y: center.y - abs(bottom.y - center.y),
                width: abs(right.x - center.x) * 2, height: abs(bottom.y - center.y) * 2)
            context.stroke(
                Path(ellipseIn: rect), with: .color(guideColor),
                style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
            drawHandle(at: center, in: &context, color: guideColor)
        }
    }

    private func drawHandle(at point: CGPoint, in context: inout GraphicsContext, color: Color) {
        context.fill(
            Path(ellipseIn: CGRect(x: point.x - 5, y: point.y - 5, width: 10, height: 10)),
            with: .color(color))
    }
}

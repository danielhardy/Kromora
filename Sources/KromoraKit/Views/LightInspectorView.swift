import SwiftUI
import AppKit

/// The photographer-facing global Light inspector.
///
/// Sections use full-width disclosure rows so the full toolset stays in the docked inspector
/// without taking over the photo canvas. The view only talks to LightControl and AppViewModel value
/// bindings; Core Image never appears in the editing surface.
struct LightInspectorView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var toneSectionExpanded = true
    @State private var curveSectionExpanded = true

    var body: some View {
        ScrollViewReader { scrollProxy in
            InspectorScrollingContent {
                VStack(alignment: .leading, spacing: 12) {
                    header

                    InspectorDisclosure("Tone", isExpanded: $toneSectionExpanded) {
                        VStack(alignment: .leading, spacing: 14) {
                            ForEach(
                                Array(LightControl.allCases.enumerated()),
                                id: \.element
                            ) { offset, control in
                                controlRow(
                                    control,
                                    sortPriority: Double(LightControl.allCases.count - offset)
                                ).id(control)
                            }
                        }
                        .padding(.top, 10)
                    }

                    InspectorDisclosure("Tone Curve", isExpanded: $curveSectionExpanded) {
                        ToneCurveEditor(viewModel: viewModel)
                            .padding(.top, 10)
                    }
                }
                .padding(16)
            }
            .onChange(of: viewModel.exposureScrollRequest) { _, _ in
                scrollProxy.scrollTo(LightControl.exposure, anchor: .center)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Light adjustments")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Light").font(.headline)
                Spacer()
                Button("Reset Light") { viewModel.resetAllLight() }
                    .buttonStyle(.link)
                    .disabled(!viewModel.hasLightAdjustments)
                    .accessibilityHint("Reset all Light controls, including the tone curve")
            }
            Text("Auto replaces global Light and Color values; other edits stay unchanged.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func controlRow(_ control: LightControl, sortPriority: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                ResettableAdjustmentLabel(
                    title: control.title,
                    reset: { viewModel.resetLight(control) }
                )
                Spacer()
                Text(readout(for: control))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }

            NeutralOriginSlider(
                value: viewModel.lightBinding(for: control),
                in: control.range,
                neutral: control.neutral,
                accessibilityTitle: control.title,
                accessibilityReadout: readout(for: control),
                onEditingChanged: { editing in
                    if editing { viewModel.beginPreviewInteraction() }
                    else { viewModel.endPreviewInteraction() }
                }
            )
            .accessibilityLabel(control.title)
            .accessibilityValue(readout(for: control))
            .accessibilitySortPriority(sortPriority)
            .accessibilityAction(named: Text("Reset to neutral")) {
                viewModel.resetLight(control)
            }
            .help(control.explanation)
        }
    }

    private func readout(for control: LightControl) -> String {
        let value = viewModel.lightValue(for: control)
        switch control {
        case .exposure:
            return String(format: "%+.2f EV", value)
        case .contrast, .highlights, .shadows, .whites, .blacks:
            return String(format: "%+.0f", value)
        }
    }
}

/// A compact master RGB curve editor. Every control handle can be dragged and adjusted through
/// the keyboard/VoiceOver adjustable action.
private struct ToneCurveEditor: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var curveDrag: CurveDragState?
    @State private var channel: ToneCurveChannel = .master

    private enum CurveDragState: Equatable {
        case ignored
        case point(input: Double, moved: Bool)

        var isPoint: Bool {
            if case .point = self { return true }
            return false
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 8) {
                Picker("Channel", selection: $channel) {
                    ForEach(ToneCurveChannel.allCases) { item in Text(item.rawValue).tag(item) }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                HStack(spacing: 12) {
                    Button("Import…") { viewModel.importToneCurvePreset() }.buttonStyle(.link)
                    Button("Export…") { viewModel.exportToneCurvePreset() }.buttonStyle(.link)
                    Spacer(minLength: 0)
                    Button("Reset") { viewModel.resetToneCurve(channel) }
                        .buttonStyle(.link)
                        .disabled(viewModel.document.light.toneCurve(for: channel).isIdentity)
                }
            }

            GeometryReader { proxy in
                let size = proxy.size
                ZStack {
                    curveGraph(size: size)
                        .contentShape(Rectangle())
                    // Keep the handle view's identity tied to its slot, not its changing input.
                    // Re-keying by input while a drag is in flight can tear down the gesture as
                    // soon as the handle follows the pointer.
                    ForEach(Array(editablePoints.enumerated()), id: \.offset) { _, point in
                        pointHandle(point, size: size)
                    }
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                // A zero-distance graph gesture turns a press on the curve into both the add and
                // drag operation. Handle views only provide their double-click removal gesture;
                // selecting and moving every point therefore uses one graph coordinate space.
                .gesture(curveDragGesture(size: size))
                .accessibilityElement(children: .contain)
                .accessibilityLabel("\(channel.rawValue) tone curve")
            }
            // Keep the graph square while allowing it to shrink and grow with the inspector.
            // GeometryReader receives the resulting square size, so the normalized coordinate
            // mapping used by both the handles and drag gesture remains in one coordinate space.
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: .infinity, alignment: .center)
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in
                finishCurveDrag()
            }
            .onDisappear {
                finishCurveDrag()
            }

            HStack {
                Text("Shadows")
                Spacer()
                Text("Highlights")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)

            Text("Parametric regions").font(.caption).foregroundStyle(.secondary)
            ForEach(["Highlights", "Lights", "Darks", "Shadows"], id: \.self) { name in
                regionSlider(name, amount: true)
            }
            Text("Region splits").font(.caption).foregroundStyle(.secondary)
            ForEach(["Shadow split", "Dark split", "Light split", "Highlight split"], id: \.self) { name in
                regionSlider(name, amount: false)
            }
        }
    }

    private var editablePoints: [LightCurvePoint] {
        viewModel.document.light.toneCurve(for: channel).points
    }

    private func regionSlider(_ title: String, amount: Bool) -> some View {
        let keyPath: WritableKeyPath<ParametricToneCurve, Double>
        switch title {
        case "Highlights": keyPath = \.highlights
        case "Lights": keyPath = \.lights
        case "Darks": keyPath = \.darks
        case "Shadows": keyPath = \.shadows
        case "Shadow split": keyPath = \.shadowSplit
        case "Dark split": keyPath = \.darkSplit
        case "Light split": keyPath = \.lightSplit
        default: keyPath = \.highlightSplit
        }
        let value = viewModel.document.light.parametricCurve[keyPath: keyPath]
        let range = amount ? ParametricToneCurve.amountRange : 0...1
        return VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title)
                Spacer()
                Text(amount ? String(format: "%+.0f", value) : String(format: "%.2f", value))
                    .font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
            }
            NeutralOriginSlider(value: Binding(
                get: { viewModel.document.light.parametricCurve[keyPath: keyPath] },
                set: { next in
                    viewModel.updateDocument(debounced: true) {
                        var curve = $0.light.parametricCurve
                        let gap = 0.02
                        let bounded: Double
                        switch title {
                        case "Shadow split": bounded = min(max(next, 0.02), curve.darkSplit - gap)
                        case "Dark split": bounded = min(max(next, curve.shadowSplit + gap), curve.lightSplit - gap)
                        case "Light split": bounded = min(max(next, curve.darkSplit + gap), curve.highlightSplit - gap)
                        case "Highlight split": bounded = min(max(next, curve.lightSplit + gap), 0.98)
                        default: bounded = next
                        }
                        curve[keyPath: keyPath] = bounded
                        $0.light.parametricCurve = curve
                    }
                }
            ), in: range, neutral: amount ? 0 : 0,
               accessibilityTitle: title, accessibilityReadout: String(format: "%.2f", value))
        }
    }

    private func curveGraph(size: CGSize) -> some View {
        Canvas { context, canvasSize in
            let rect = CGRect(origin: .zero, size: canvasSize)
            // Tone-curve analysis is intentionally dark for consistent grid/curve contrast;
            // this fill is limited to the graph and is not an inspector-wide appearance choice.
            context.fill(Path(roundedRect: rect, cornerRadius: 5), with: .color(KromoraTheme.analysisBackground))

            var grid = Path()
            for fraction in stride(from: 0.25, through: 0.75, by: 0.25) {
                grid.move(to: CGPoint(x: fraction * canvasSize.width, y: 0))
                grid.addLine(to: CGPoint(x: fraction * canvasSize.width, y: canvasSize.height))
                grid.move(to: CGPoint(x: 0, y: (1 - fraction) * canvasSize.height))
                grid.addLine(to: CGPoint(x: canvasSize.width, y: (1 - fraction) * canvasSize.height))
            }
            context.stroke(grid, with: .color(KromoraTheme.analysisGrid), lineWidth: 1)

            var identity = Path()
            identity.move(to: CGPoint(x: 0, y: canvasSize.height))
            identity.addLine(to: CGPoint(x: canvasSize.width, y: 0))
            context.stroke(identity, with: .color(KromoraTheme.analysisReference), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))

            let curve = viewModel.document.light.toneCurve(for: channel)
            var path = Path()
            for index in 0...64 {
                let input = Double(index) / 64
                let point = CGPoint(
                    x: input * canvasSize.width,
                    y: (1 - curve.value(at: input)) * canvasSize.height
                )
                if index == 0 { path.move(to: point) }
                else { path.addLine(to: point) }
            }
            context.stroke(path, with: .color(KromoraTheme.primaryAccent), style: StrokeStyle(lineWidth: 2))
        }
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }

    private func pointHandle(_ point: LightCurvePoint, size: CGSize) -> some View {
        // This is deliberately not a `Button`: AppKit's button recognizer owns the mouse-down
        // until its primary action resolves on mouse-up. That can leave a handle drag dependent
        // on the release path instead of publishing its changing location immediately.
        Circle()
            .fill(KromoraTheme.primaryAccent)
            .overlay(Circle().stroke(.white, lineWidth: 1))
            .frame(width: 12, height: 12)
            .shadow(radius: 1)
            .contentShape(Circle())
            .position(position(for: point, in: size))
        .simultaneousGesture(
            SpatialTapGesture(count: 2)
                .onEnded { _ in removePoint(point) }
        )
        .focusable()
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Tone curve point")
        .accessibilityValue(String(format: "Input %.2f, output %.2f", point.input, point.output))
        .accessibilityHint("Drag or use adjustment keys to change this point")
        .accessibilityAdjustableAction { direction in
            let step = 0.01
            let output: Double
            switch direction {
            case .increment: output = min(point.output + step, 1)
            case .decrement: output = max(point.output - step, 0)
            @unknown default: return
            }
            viewModel.setToneCurvePoint(point, output: output, channel: channel)
        }
    }

    private func curveDragGesture(size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                updateCurveDrag(at: value.location, translation: value.translation, in: size)
            }
            .onEnded { _ in
                finishCurveDrag()
            }
    }

    private func updateCurveDrag(at location: CGPoint, translation: CGSize, in size: CGSize) {
        guard curveDrag == nil || curveDrag?.isPoint == true else { return }
        let coordinate = coordinate(for: location, in: size)
        let hasMoved = translation.width != 0 || translation.height != 0

        if curveDrag == nil {
            let curve = viewModel.document.light.toneCurve(for: channel)
            if let existing = curve.nearestPoint(toInput: coordinate.input) {
                viewModel.beginPreviewInteraction()
                curveDrag = .point(input: existing.input, moved: false)
            } else {
                // Match click-to-add: the press must be on the drawn transfer function, and the
                // new point initially samples that function. The first move below then applies
                // the pointer's exact output, so a click and a drag share one gesture.
                guard coordinate.input > 0.001, coordinate.input < 0.999,
                      abs(coordinate.output - curve.value(at: coordinate.input)) <= 0.06 else {
                    curveDrag = .ignored
                    return
                }
                viewModel.beginPreviewInteraction()
                viewModel.addToneCurvePoint(input: coordinate.input, channel: channel)
                curveDrag = .point(input: coordinate.input, moved: false)
            }
        }

        guard case .point(let sourceInput, _) = curveDrag else { return }
        // The first zero-distance update represents the press itself. Leave a click at the
        // sampled curve value; only a subsequent pointer movement should reposition the point.
        guard hasMoved else { return }
        let movedInput = viewModel.moveToneCurvePoint(
            fromInput: sourceInput,
            input: coordinate.input,
            output: coordinate.output,
            channel: channel
        )
        if let movedInput {
            curveDrag = .point(input: movedInput, moved: true)
        }
    }

    private func finishCurveDrag() {
        guard curveDrag != nil else { return }
        curveDrag = nil
        viewModel.endPreviewInteraction()
    }

    private func coordinate(for location: CGPoint, in size: CGSize) -> (input: Double, output: Double) {
        let width = max(size.width, 1)
        let height = max(size.height, 1)
        return (
            input: min(max(location.x / width, 0), 1),
            output: min(max(1 - location.y / height, 0), 1)
        )
    }

    private func position(for point: LightCurvePoint, in size: CGSize) -> CGPoint {
        CGPoint(x: point.input * size.width, y: (1 - point.output) * size.height)
    }

    private func removePoint(_ point: LightCurvePoint) {
        viewModel.beginPreviewInteraction()
        viewModel.removeToneCurvePoint(atInput: point.input, channel: channel)
        viewModel.endPreviewInteraction()
    }
}

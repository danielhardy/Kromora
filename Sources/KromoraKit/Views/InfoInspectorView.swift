import SwiftUI

/// Docked inspector pane: a pinned histogram above the selected editor surface.
/// Toggled from the toolbar (and ⌘I).
struct InfoInspectorView: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject var inspectorState: AppViewModel.InspectorState
    @Bindable private var canvasState: CanvasInteractionState

    init(viewModel: AppViewModel, inspectorState: AppViewModel.InspectorState) {
        self.viewModel = viewModel
        self.inspectorState = inspectorState
        _canvasState = Bindable(wrappedValue: viewModel.canvasState)
    }

    var body: some View {
        let _ = RenderDiagnostics.noteInspectorBody()
        return VStack(spacing: 0) {
            if canvasState.isCropToolActive {
                CropInspectorView(
                    aspectRatio: canvasState.cropAspectRatio,
                    orientation: canvasState.cropOrientation,
                    imageSize: viewModel.cropSourceSize,
                    straightenAngle: canvasState.cropStraightenAngle,
                    flipHorizontal: canvasState.cropFlipHorizontal,
                    flipVertical: canvasState.cropFlipVertical,
                    verticalPerspective: canvasState.cropVerticalPerspective,
                    horizontalPerspective: canvasState.cropHorizontalPerspective,
                    onRotateCounterClockwise: viewModel.rotateCounterClockwise,
                    onRotateClockwise: viewModel.rotateClockwise,
                    onBeginInteraction: viewModel.beginPreviewInteraction,
                    onEndInteraction: viewModel.endPreviewInteraction,
                    onStraightenChange: viewModel.setCropStraightenAngle,
                    onFlipHorizontal: { viewModel.toggleCropFlip(horizontal: true) },
                    onFlipVertical: { viewModel.toggleCropFlip(horizontal: false) },
                    onVerticalPerspectiveChange: viewModel.setCropVerticalPerspective,
                    onHorizontalPerspectiveChange: viewModel.setCropHorizontalPerspective,
                    onResetStraighten: { viewModel.setCropStraightenAngle(0) },
                    onResetVerticalPerspective: { viewModel.setCropVerticalPerspective(0) },
                    onResetHorizontalPerspective: { viewModel.setCropHorizontalPerspective(0) },
                    onAuto: viewModel.runCropAuto,
                    onAspectRatioChange: viewModel.selectCropAspectRatio,
                    onReset: viewModel.resetCrop,
                    onCancel: viewModel.cancelCrop,
                    onDone: viewModel.commitCrop
                )
                .transition(inspectorTransition(edge: .trailing))
            } else if viewModel.sourceImage == nil {
                // No image, no tabs. Both halves describe *a picture*: with nothing open, the switcher
                // offers a trip to Develop to be told "this image is already rendered" about an image
                // that does not exist. The empty state alone is the honest answer.
                emptyState
                    .transition(.opacity)
            } else {
                histogramSection

                tabSwitcher

                Divider()

                Group {
                    switch inspectorState.tab.content {
                    case .info:
                        infoContent
                    case .light:
                        LightInspectorView(viewModel: viewModel)
                    case .develop:
                        DevelopInspectorView(viewModel: viewModel)
                    case .color:
                        ColorInspectorView(viewModel: viewModel)
                    case .effects:
                        EffectsInspectorView(viewModel: viewModel)
                    case .look:
                        LookInspectorView(viewModel: viewModel)
                    case .masking:
                        MaskingWorkspace(viewModel: viewModel)
                    }
                }
                .frame(maxHeight: .infinity, alignment: .top)
                .transition(inspectorTransition(edge: .leading))
            }
        }
        .frame(minWidth: 240, idealWidth: 280)
        // Leave the pane transparent so the native inspector material shows around the chart.
        // The plot extends into the toolbar band. The window title bar is transparent there so
        // AppKit does not composite a second layer over the histogram.
        .animation(inspectorAnimation, value: canvasState.isCropToolActive)
    }

    private var inspectorAnimation: Animation? {
        accessibilityReduceMotion ? nil : .easeInOut(duration: 0.3)
    }

    private func inspectorTransition(edge: Edge) -> AnyTransition {
        accessibilityReduceMotion
            ? .opacity
            : .move(edge: edge).combined(with: .opacity)
    }

    private var tabSwitcher: some View {
        Picker("Inspector view", selection: Binding(
            get: { inspectorState.tab },
            set: { viewModel.inspectorTab = $0 }
        )) {
            ForEach(viewModel.availableInspectorTabs, id: \.self) { tab in
                Label(tab.title, systemImage: tab.iconName)
                    // Keep the full title in the semantic label while showing only the compact
                    // symbol in the segmented control.
                    .labelStyle(.iconOnly)
                    .accessibilityLabel(tab.title)
                    .accessibilityHint(tab.purpose)
                    .accessibilityValue(inspectorState.tab == tab ? "Selected" : "Not selected")
                    .help(tab.helpText)
                    .tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .controlSize(.large)
        .labelsHidden()
        .frame(minHeight: 32)
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    /// Photo identity and EXIF content. Only reached with an image open — the no-image case is
    /// handled one level up, before the tab switcher exists.
    private var infoContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                identitySection
                editHistorySection
                metadataSection
                if let assetID = viewModel.maskingAssetID,
                   let source = viewModel.maskingSource {
                    PhotoAnalysisInspectSection(
                        coordinator: viewModel.photoAnalysisCoordinator,
                        assetID: assetID,
                        source: source,
                        surface: viewModel.previewSurface,
                        sourceSize: viewModel.sourceSize,
                        crop: viewModel.document.crop,
                        histogram: viewModel.histogram,
                        isExpanded: $analysisExpanded,
                        onUseEditingMask: { kind, result, pixels in
                            viewModel.useInfoAnalysisMask(
                                kind, demonstrated: result, pixels: pixels)
                        }
                    )
                    .id(assetID)
                }
            }
            .padding(16)
        }
    }

    /// Do not persist this state: a newly opened photo must never trigger analysis unexpectedly.
    @State private var analysisExpanded = false
    @State private var snapshotName = ""

    private var editHistorySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Edit History").font(.headline)
                Spacer()
                Button { viewModel.refreshDurableEditHistory() } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .help("Refresh edit history")
            }
            if let source = viewModel.virtualCopySourceDescription {
                Label(source, systemImage: "square.on.square")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if viewModel.canCreateVirtualCopy {
                Button {
                    viewModel.createVirtualCopy()
                } label: {
                    Label("Create Virtual Copy", systemImage: "plus.square.on.square")
                }
                .buttonStyle(.plain)
                .help("Create an independent library copy with its own edits and history")
            }
            HStack(spacing: 6) {
                TextField("Snapshot name", text: $snapshotName)
                    .textFieldStyle(.roundedBorder)
                Button("Save") {
                    let name = snapshotName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !name.isEmpty else { return }
                    viewModel.saveEditSnapshot(named: name)
                    snapshotName = ""
                }
                .disabled(snapshotName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if viewModel.durableEditHistory.isEmpty {
                Text("No saved edits yet").font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.durableEditHistory.reversed(), id: \.revision) { entry in
                    Button {
                        viewModel.restoreEditRevision(entry.revision)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.snapshotName ?? "Edit \(entry.revision)")
                                    .lineLimit(1)
                                Text(entry.createdAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if entry.document == viewModel.document {
                                Image(systemName: "checkmark").foregroundStyle(.secondary)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Restore this edit state as a new history branch")
                }
            }
        }
    }

    // MARK: - Histogram

    private var histogramSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Histogram")
                    .font(.headline)
                Spacer()
                if let histogram = viewModel.histogram {
                    Label("\(histogram.clippedHighlights)", systemImage: "sun.max.fill")
                        .foregroundStyle(histogram.clippedHighlights > 0 ? .orange : .secondary)
                        .help("\(histogram.clippedHighlights) sampled highlight pixels")
                    Label("\(histogram.clippedShadows)", systemImage: "moon.fill")
                        .foregroundStyle(histogram.clippedShadows > 0 ? .cyan : .secondary)
                        .help("\(histogram.clippedShadows) sampled shadow pixels")
                    Button {
                        viewModel.showClippingAlerts.toggle()
                    } label: {
                        Image(systemName: viewModel.showClippingAlerts ? "viewfinder" : "viewfinder.circle")
                    }
                    .buttonStyle(.plain)
                    .help("Toggle clipping alerts on the photo")
                }
                Text(histogramSourceLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.08), in: Capsule())
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            histogramPlot
                .frame(height: 120)
                .frame(maxWidth: .infinity)
                // Full bleed to the photo and the window edge. The plot stays a local dark
                // surface; it does not define the inspector background.
                .background(KromoraTheme.analysisBackground)
                .overlay(Rectangle().stroke(KromoraTheme.analysisBorder, lineWidth: 1))

            Picker("Channel", selection: $channel) {
                Text("RGB").tag(HistogramChart.Mode.rgb)
                Text("Luma").tag(HistogramChart.Mode.luma)
                Text("R").tag(HistogramChart.Mode.red)
                Text("G").tag(HistogramChart.Mode.green)
                Text("B").tag(HistogramChart.Mode.blue)
                Text("Wave").tag(HistogramChart.Mode.waveform)
                Text("Parade").tag(HistogramChart.Mode.parade)
                Text("Vector").tag(HistogramChart.Mode.vectorscope)
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .padding(.horizontal, 12)

            HStack(spacing: 8) {
                if let readout = viewModel.pixelReadout {
                    if let before = viewModel.pixelReadoutBefore {
                        Text(String(format: "Pre RGB %03d %03d %03d", before.red, before.green, before.blue))
                        Text(String(format: "Lab %5.1f %+.1f %+.1f", before.lab.l, before.lab.a, before.lab.b))
                    }
                    Text(String(format: "Post RGB %03d %03d %03d", readout.red, readout.green, readout.blue))
                    Text(String(format: "Lab %5.1f %+.1f %+.1f", readout.lab.l, readout.lab.a, readout.lab.b))
                } else {
                    Text("Hover over photo for pixel readout")
                }
            }
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)

            if let histogram = viewModel.histogram {
                HStack(spacing: 7) {
                    Text("R \(histogram.clippedRed)").foregroundStyle(.red)
                    Text("G \(histogram.clippedGreen)").foregroundStyle(.green)
                    Text("B \(histogram.clippedBlue)").foregroundStyle(.blue)
                    Spacer(minLength: 2)
                    Button("Exposure") { viewModel.showExposureControl() }
                        .buttonStyle(.link)
                        .help("Show the Exposure control")
                }
                .font(.system(size: 10, design: .monospaced))
                .padding(.horizontal, 12)
            }
        }
    }

    @ViewBuilder
    private var histogramPlot: some View {
        if let histogram = viewModel.histogram {
            HistogramChart(data: histogram, channel: channel)
        } else if viewModel.isHistogramLoading {
            ProgressView().controlSize(.small)
        } else {
            Text(viewModel.histogramErrorMessage ?? "Histogram unavailable")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(12)
        }
    }

    @State private var channel: HistogramChart.Mode = .rgb

    private var histogramSourceLabel: String {
        if viewModel.isShowingOriginal { return "Original" }
        if viewModel.selectedLook != nil { return "Graded" }
        return viewModel.isComparisonAvailable ? "Edited" : "Original"
    }

    // MARK: - Metadata

    private var identitySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Photo")
                .font(.headline)
            metadataRow(ImageMetadata.Row(label: "Name", value: viewModel.currentPhotoName))
            metadataRow(ImageMetadata.Row(label: "File Type", value: viewModel.currentPhotoFileType))
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var metadataSection: some View {
        let sections = viewModel.metadata.sections
        if sections.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("Info")
                    .font(.headline)
                Text("No metadata available for this image.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(sections) { section in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(section.title)
                            .font(.subheadline.weight(.semibold))
                        ForEach(section.rows) { row in
                            metadataRow(row)
                        }
                    }
                }
            }
        }
    }

    private func metadataRow(_ row: ImageMetadata.Row) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(row.label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 92, alignment: .leading)
            Text(row.value)
                .font(.caption)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "info.circle")
                .font(.system(size: 28, weight: .thin))
                .foregroundStyle(.secondary.opacity(0.5))
            Text("Open an image to see its\nhistogram and EXIF data")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

// MARK: - Histogram chart

/// Canvas-drawn histogram. RGB mode overlays the three channels with additive
/// blending (overlaps brighten toward white, the classic look); single-channel
/// and luma modes draw one filled curve.
struct HistogramChart: View {
    enum Mode: Hashable {
        case rgb, luma, red, green, blue, waveform, parade, vectorscope
    }

    let data: HistogramData
    let channel: Mode

    var body: some View {
        Canvas { context, size in
            switch channel {
            case .rgb:
                fill(.red,   Color.red,   in: context, size: size, blend: .plusLighter)
                fill(.green, Color.green, in: context, size: size, blend: .plusLighter)
                fill(.blue,  Color.blue,  in: context, size: size, blend: .plusLighter)
            case .luma:
                fill(.luma, Color.white.opacity(0.85), in: context, size: size, blend: .normal)
            case .red:
                fill(.red, Color.red, in: context, size: size, blend: .normal)
            case .green:
                fill(.green, Color.green, in: context, size: size, blend: .normal)
            case .blue:
                fill(.blue, Color.blue, in: context, size: size, blend: .normal)
            case .waveform:
                drawWaveform(in: context, size: size, channels: [.white])
            case .parade:
                for (index, color) in [Color.red, .green, .blue].enumerated() {
                    var pane = context
                    pane.translateBy(x: CGFloat(index) * size.width / 3, y: 0)
                    drawWaveform(in: pane, size: CGSize(width: size.width / 3, height: size.height),
                                 channels: [color], channelIndex: index)
                }
            case .vectorscope:
                drawVectorscope(in: context, size: size)
            }
        }
    }

    private func drawWaveform(in context: GraphicsContext, size: CGSize, channels: [Color], channelIndex: Int? = nil) {
        guard data.sampleWidth > 0, data.sampleHeight > 0,
              data.samples.count >= data.sampleWidth * data.sampleHeight * 3 else { return }
        var points = Path()
        for y in 0..<data.sampleHeight {
            for x in 0..<data.sampleWidth {
                let offset = (y * data.sampleWidth + x) * 3
                let red = Int(data.samples[offset])
                let green = Int(data.samples[offset + 1])
                let blue = Int(data.samples[offset + 2])
                let channelValue: Int
                if let channelIndex {
                    channelValue = channelIndex == 0 ? red : (channelIndex == 1 ? green : blue)
                } else {
                    let weighted = 0.2126 * Double(red) + 0.7152 * Double(green) + 0.0722 * Double(blue)
                    channelValue = Int(weighted.rounded())
                }
                let level = Double(channelValue) / 255.0
                let px = CGFloat(x) / CGFloat(max(1, data.sampleWidth - 1)) * size.width
                let py = size.height * (1 - CGFloat(level))
                points.addEllipse(in: CGRect(x: px, y: py, width: 1.5, height: 1.5))
            }
        }
        context.fill(points, with: .color(channels[0].opacity(0.22)))
        if size.width > 30 {
            var grid = Path()
            for fraction in [0.25, 0.5, 0.75] {
                grid.move(to: CGPoint(x: 0, y: size.height * fraction))
                grid.addLine(to: CGPoint(x: size.width, y: size.height * fraction))
            }
            context.stroke(grid, with: .color(.white.opacity(0.12)), lineWidth: 0.5)
        }
    }

    private func drawVectorscope(in context: GraphicsContext, size: CGSize) {
        guard data.sampleWidth > 0, data.samples.count >= data.sampleWidth * data.sampleHeight * 3 else { return }
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = min(size.width, size.height) * 0.45
        var grid = Path()
        grid.addEllipse(in: CGRect(x: center.x-radius, y: center.y-radius, width: radius*2, height: radius*2))
        grid.move(to: CGPoint(x: center.x-radius, y: center.y)); grid.addLine(to: CGPoint(x: center.x+radius, y: center.y))
        grid.move(to: CGPoint(x: center.x, y: center.y-radius)); grid.addLine(to: CGPoint(x: center.x, y: center.y+radius))
        context.stroke(grid, with: .color(.white.opacity(0.22)), lineWidth: 0.6)
        var points = Path()
        for offset in stride(from: 0, to: data.sampleWidth * data.sampleHeight * 3, by: 3) {
            let r = Double(data.samples[offset]) / 255, g = Double(data.samples[offset+1]) / 255, b = Double(data.samples[offset+2]) / 255
            let u = (b - (0.299*r + 0.587*g + 0.114*b)) * 0.565
            let v = (r - (0.299*r + 0.587*g + 0.114*b)) * 0.713
            let p = CGPoint(x: center.x + CGFloat(u * 2) * radius, y: center.y - CGFloat(v * 2) * radius)
            points.addEllipse(in: CGRect(x: p.x, y: p.y, width: 2, height: 2))
        }
        context.fill(points, with: .color(.cyan.opacity(0.34)))
    }

    private func fill(
        _ ch: HistogramData.Channel,
        _ color: Color,
        in context: GraphicsContext,
        size: CGSize,
        blend: GraphicsContext.BlendMode
    ) {
        let norm = data.normalized(ch)
        guard norm.count > 1 else { return }
        let w = size.width
        let h = size.height
        let step = w / CGFloat(norm.count - 1)

        var path = Path()
        path.move(to: CGPoint(x: 0, y: h))
        for (i, v) in norm.enumerated() {
            let x = CGFloat(i) * step
            let y = h - v * h
            path.addLine(to: CGPoint(x: x, y: y))
        }
        path.addLine(to: CGPoint(x: w, y: h))
        path.closeSubpath()

        var ctx = context
        ctx.blendMode = blend
        ctx.fill(path, with: .color(color.opacity(channel == .rgb ? 0.75 : 0.9)))
    }
}

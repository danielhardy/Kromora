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
        return FitsProposedWidth {
            VStack(spacing: 0) {
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
                        onAspectRatioChange: viewModel.selectCropAspectRatio,
                        onReset: viewModel.resetCrop,
                        onCancel: viewModel.cancelCrop,
                        onDone: viewModel.commitCrop
                    )
                    .transition(inspectorTransition(edge: .trailing))
                } else if viewModel.sourceImage == nil && viewModel.histogram == nil {
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
                        case .retouch:
                            RetouchInspectorView(viewModel: viewModel)
                        }
                    }
                    .frame(maxHeight: .infinity, alignment: .top)
                    .transition(inspectorTransition(edge: .leading))
                    // A source switch briefly clears sourceImage while the replacement decodes.
                    // The retained histogram tells us this is a cutover, so keep the editor
                    // controls mounted and let their values settle onto the new document.
                    .environment(
                        \.sliderSourceAnimation,
                        SliderSourceAnimation(
                            assetID: viewModel.maskingAssetID,
                            isEnabled: !accessibilityReduceMotion
                        )
                    )
                    .animation(inspectorAnimation, value: viewModel.maskingAssetID)
                }
            }
        }
        .frame(minWidth: 240, idealWidth: 280, maxWidth: 360, alignment: .topLeading)
        // Light matches the toolbar. Dark stays the sidebar step. Follows the window
        // appearance, including Always dark mode.
        .background(KromoraTheme.inspectorChrome)
        .animation(inspectorAnimation, value: canvasState.isCropToolActive)
        .toolbar {
            // The toggle stays at the trailing edge while the column moves. The pin is not
            // cleared when closing starts: that jump would move the button. The photo
            // toolbar slides to it, and the pin drops only after that motion finishes.
            if !canvasState.isCropToolActive {
                if sidebarAnchoredToTrailingEdge {
                    ToolbarSpacer(.flexible)
                }
                ToolbarItem(placement: .primaryAction) {
                    EditorSidebarToolbarButton(
                        isPresented: inspectorState.isPresented,
                        isEnabled: viewModel.sourceImage != nil,
                        action: { viewModel.toggleInspector() }
                    )
                }
            }
        }
        .onChange(of: inspectorState.isPresented, initial: true) { _, presented in
            syncSidebarAnchor(presented: presented)
        }
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
        InspectorScrollingContent {
            VStack(alignment: .leading, spacing: InspectorStyle.sectionSpacing) {
                InspectorPanelHeading(title: "Info")
                identitySection
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
                editHistorySection
                metadataSection
            }
            .padding(InspectorStyle.contentInset)
        }
    }

    /// Do not persist this state: a newly opened photo must never trigger analysis unexpectedly.
    @State private var analysisExpanded = false
    @State private var editHistoryExpanded = false
    @State private var snapshotName = ""
    @State private var expandedMetadataSections: Set<String> = ["Camera & Lens", "Exposure"]
    /// True while the sidebar toggle should stay pinned to the window's trailing edge.
    /// Closing keeps this set until the column animation finishes.
    @State private var sidebarAnchoredToTrailingEdge = false
    @State private var sidebarAnchorGeneration = 0

    /// The system inspector column animates a bit longer than the pane's own content.
    private static let sidebarAnchorReleaseDelay: Duration = .milliseconds(450)

    private func syncSidebarAnchor(presented: Bool) {
        sidebarAnchorGeneration += 1
        let generation = sidebarAnchorGeneration
        if presented || accessibilityReduceMotion {
            sidebarAnchoredToTrailingEdge = presented
            return
        }
        Task { @MainActor in
            try? await Task.sleep(for: Self.sidebarAnchorReleaseDelay)
            guard generation == sidebarAnchorGeneration else { return }
            sidebarAnchoredToTrailingEdge = false
        }
    }

    private var editHistorySection: some View {
        InspectorDisclosure("Edit History", isExpanded: $editHistoryExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
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
                        let isCurrent = entry.revision == viewModel.durableCurrentEditRevision
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
                                if isCurrent {
                                    Text("Current")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.tint)
                                }
                            }
                            .contentShape(Rectangle())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .background(isCurrent ? Color.accentColor.opacity(0.12) : .clear)
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                        }
                        .buttonStyle(.plain)
                        .help(isCurrent ? "Current edit history position" : "Navigate to this edit state")
                    }
                }
            }
            .padding(.top, 8)
        }
    }

    // MARK: - Histogram

    private var histogramSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Histogram")
                    .font(InspectorStyle.sectionTitle)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if let histogram = viewModel.histogram {
                    Label("\(histogram.clippedHighlights)", systemImage: "sun.max.fill")
                        .foregroundStyle(histogram.clippedHighlights > 0 ? .orange : .secondary)
                        .help("\(histogram.clippedHighlights) sampled highlight pixels")
                    Label("\(histogram.clippedShadows)", systemImage: "moon.fill")
                        .foregroundStyle(histogram.clippedShadows > 0 ? .cyan : .secondary)
                        .help("\(histogram.clippedShadows) sampled shadow pixels")
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

            VStack(spacing: 0) {
                histogramPlot
                    .frame(height: 120)
                    .frame(maxWidth: .infinity)

                histogramModeSelector
            }
            // Keep the plot and its mode tabs on one edge-to-edge chart surface.
            .background(KromoraTheme.analysisBackground)
            .overlay(Rectangle().stroke(KromoraTheme.analysisBorder, lineWidth: 1))
        }
    }

    @ViewBuilder
    private var histogramPlot: some View {
        if let histogram = viewModel.histogram {
            HistogramChart(data: histogram, channel: channel)
                .animation(
                    accessibilityReduceMotion ? nil : .easeInOut(duration: 0.45),
                    value: histogram
                )
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

    private var histogramModeSelector: some View {
        HStack(spacing: 0) {
            ForEach(HistogramChart.Mode.allCases, id: \.self) { mode in
                let isSelected = channel == mode
                Button {
                    channel = mode
                } label: {
                    Text(mode.title)
                        .font(.system(.caption2, design: .monospaced))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                        .frame(maxWidth: .infinity, minHeight: 32)
                        .contentShape(Rectangle())
                        .background {
                            if isSelected {
                                Color.accentColor.opacity(0.2)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Histogram \(mode.accessibilityName)")
                .accessibilityValue(isSelected ? "Selected" : "Not selected")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .help("Show \(mode.accessibilityName) histogram")
                .overlay(alignment: .trailing) {
                    if mode != HistogramChart.Mode.allCases.last {
                        Rectangle()
                            .fill(KromoraTheme.analysisBorder)
                            .frame(width: 1)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Histogram mode")
        .overlay(alignment: .top) {
            Rectangle()
                .fill(KromoraTheme.analysisBorder)
                .frame(height: 1)
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
                .font(InspectorStyle.sectionTitle)
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
                Text("No metadata available for this image.")
                    .font(InspectorStyle.helperText)
                    .foregroundStyle(.secondary)
            }
        } else {
            VStack(alignment: .leading, spacing: InspectorStyle.sectionSpacing) {
                ForEach(sections) { section in
                    InspectorDisclosure(
                        section.title,
                        isExpanded: metadataExpansion(for: section.id)
                    ) {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(section.rows) { row in
                                metadataRow(row)
                            }
                        }
                        .padding(.top, InspectorStyle.sectionContentInset)
                    }
                }
            }
        }
    }

    private func metadataRow(_ row: ImageMetadata.Row) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(row.label)
                .font(InspectorStyle.fieldLabel)
                .foregroundStyle(.secondary)
                .frame(width: 92, alignment: .leading)
            Text(row.value)
                .font(InspectorStyle.fieldValue)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func metadataExpansion(for sectionID: String) -> Binding<Bool> {
        Binding(
            get: { expandedMetadataSections.contains(sectionID) },
            set: { isExpanded in
                if isExpanded {
                    expandedMetadataSections.insert(sectionID)
                } else {
                    expandedMetadataSections.remove(sectionID)
                }
            }
        )
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
struct HistogramChart: View, @MainActor Animatable {
    enum Mode: Hashable, CaseIterable {
        case rgb, luma, red, green, blue, waveform, parade, vectorscope

        var title: String {
            switch self {
            case .rgb: "RGB"
            case .luma: "Luma"
            case .red: "R"
            case .green: "G"
            case .blue: "B"
            case .waveform: "W"
            case .parade: "P"
            case .vectorscope: "V"
            }
        }

        var accessibilityName: String {
            switch self {
            case .rgb: "RGB"
            case .luma: "Luma"
            case .red: "Red"
            case .green: "Green"
            case .blue: "Blue"
            case .waveform: "Waveform"
            case .parade: "Parade"
            case .vectorscope: "Vectorscope"
            }
        }
    }

    let data: HistogramData
    let channel: Mode
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @State private var animatedValues: HistogramPlotValues?

    var animatableData: HistogramPlotValues {
        get { HistogramPlotValues(data: data) }
        set { animatedValues = newValue }
    }

    var body: some View {
        let values = animatedValues ?? HistogramPlotValues(data: data)
        Canvas { context, size in
            switch channel {
            case .rgb:
                fill(values.red, Color.red, in: context, size: size, blend: .plusLighter)
                fill(values.green, Color.green, in: context, size: size, blend: .plusLighter)
                fill(values.blue, Color.blue, in: context, size: size, blend: .plusLighter)
            case .luma:
                fill(values.luma, Color.white.opacity(0.85), in: context, size: size, blend: .normal)
            case .red:
                fill(values.red, Color.red, in: context, size: size, blend: .normal)
            case .green:
                fill(values.green, Color.green, in: context, size: size, blend: .normal)
            case .blue:
                fill(values.blue, Color.blue, in: context, size: size, blend: .normal)
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
        _ norm: [CGFloat],
        _ color: Color,
        in context: GraphicsContext,
        size: CGSize,
        blend: GraphicsContext.BlendMode
    ) {
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

/// Four fixed-size normalized channels form the chart's animatable value. Keeping the vector in
/// normalized display space makes each transition independent of the source photo's pixel count.
struct HistogramPlotValues: VectorArithmetic {
    private static let binsPerChannel = 256
    private var bins: [CGFloat]

    var red: [CGFloat] { Array(bins[0..<Self.binsPerChannel]) }
    var green: [CGFloat] { Array(bins[Self.binsPerChannel..<(2 * Self.binsPerChannel)]) }
    var blue: [CGFloat] { Array(bins[(2 * Self.binsPerChannel)..<(3 * Self.binsPerChannel)]) }
    var luma: [CGFloat] { Array(bins[(3 * Self.binsPerChannel)..<(4 * Self.binsPerChannel)]) }

    static var zero: HistogramPlotValues {
        HistogramPlotValues(bins: Array(repeating: 0, count: binsPerChannel * 4))
    }

    init(data: HistogramData) {
        bins = data.normalized(.red) + data.normalized(.green)
            + data.normalized(.blue) + data.normalized(.luma)
        guard bins.count == Self.binsPerChannel * 4 else {
            bins = Array(repeating: 0, count: Self.binsPerChannel * 4)
            return
        }
    }

    private init(bins: [CGFloat]) {
        self.bins = bins
    }

    static func + (lhs: HistogramPlotValues, rhs: HistogramPlotValues) -> HistogramPlotValues {
        HistogramPlotValues(bins: zip(lhs.bins, rhs.bins).map(+))
    }

    static func - (lhs: HistogramPlotValues, rhs: HistogramPlotValues) -> HistogramPlotValues {
        HistogramPlotValues(bins: zip(lhs.bins, rhs.bins).map(-))
    }

    mutating func scale(by rhs: Double) {
        bins = bins.map { $0 * CGFloat(rhs) }
    }

    var magnitudeSquared: Double {
        bins.reduce(0) { $0 + Double($1 * $1) }
    }
}

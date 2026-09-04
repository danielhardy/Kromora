import SwiftUI

/// Developer-only analysis inspection. Work starts from the sheet's task, so merely opening an
/// image has no analysis/mask cost when this panel is hidden.
@MainActor
final class AnalysisDebugPanelModel: ObservableObject {
    struct MaskEntry: Identifiable {
        let kind: SemanticMaskKind
        let mask: RegionMask?
        let pixels: NormalizedMask?
        let providerError: String?

        var id: SemanticMaskKind { kind }

        var normalModeReason: String {
            if let providerError { return "Unavailable: \(providerError)" }
            guard let mask else { return "Unavailable: no provider result" }
            return MaskPresentationPolicy.decision(for: mask).userMessage ?? "Available in normal mode"
        }

        var title: String {
            switch kind {
            case .subject: return "Subject"
            case .background: return "Background"
            case .person: return "Person"
            case .face: return "Face"
            case .faceInstance(let index): return "Face \(index + 1)"
            case .foregroundInstance(let index): return "Foreground \(index + 1)"
            case .unknown(let name): return name
            }
        }
    }

    @Published private(set) var analysis: PhotoAnalysis?
    @Published private(set) var masks: [MaskEntry] = []
    @Published var visibleKinds = Set<SemanticMaskKind>()
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let coordinator: PhotoAnalysisCoordinator
    private let assetID: PhotoAssetID
    private let source: ImageSource
    private var loadTask: Task<Void, Never>?

    init(coordinator: PhotoAnalysisCoordinator, assetID: PhotoAssetID, source: ImageSource) {
        self.coordinator = coordinator
        self.assetID = assetID
        self.source = source
    }

    deinit { loadTask?.cancel() }

    /// Inspect owns the lifetime of the request. Collapsing the section should release the
    /// demand-driven work instead of allowing an off-screen inspector to keep producing masks.
    func cancel() {
        loadTask?.cancel()
        loadTask = nil
        isLoading = false
    }

    func load() {
        loadTask?.cancel()
        isLoading = true
        errorMessage = nil
        loadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let analysis = try await coordinator.analyze(
                    assetID: assetID, source: source, level: .standard
                )
                let candidates: [SemanticMaskKind] = [
                    .subject, .background, .person, .face, .foregroundInstance(0)
                ]
                var entries: [MaskEntry] = []
                await withTaskGroup(of: MaskEntry?.self) { group in
                    for kind in candidates {
                        group.addTask { [coordinator, assetID, source] in
                            do {
                                let mask = try await coordinator.mask(
                                    assetID: assetID, source: source, kind: kind, quality: .analysis
                                )
                                let pixels = await coordinator.pixels(for: mask.reference)
                                return MaskEntry(kind: kind, mask: mask, pixels: pixels, providerError: nil)
                            } catch is CancellationError {
                                return nil
                            } catch {
                                return MaskEntry(
                                    kind: kind, mask: nil, pixels: nil,
                                    providerError: Self.errorDescription(error)
                                )
                            }
                        }
                    }
                    for await entry in group {
                        if let entry { entries.append(entry) }
                    }
                }
                guard !Task.isCancelled else { return }
                self.analysis = analysis
                self.masks = entries.sorted { $0.title < $1.title }
                self.visibleKinds = Set(entries.compactMap { $0.pixels == nil ? nil : $0.kind })
                self.isLoading = false
            } catch is CancellationError {
                return
            } catch {
                self.isLoading = false
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func isVisible(_ kind: SemanticMaskKind) -> Bool {
        visibleKinds.contains(kind)
    }

    func setVisible(_ kind: SemanticMaskKind, _ visible: Bool) {
        if visible { visibleKinds.insert(kind) }
        else { visibleKinds.remove(kind) }
    }

    private nonisolated static func errorDescription(_ error: Error) -> String {
        if let localized = error as? LocalizedError, let description = localized.errorDescription {
            return description
        }
        return String(describing: error)
    }
}

struct AnalysisDebugPanel: View {
    @StateObject private var model: AnalysisDebugPanelModel
    @ObservedObject private var surface: PreviewSurface
    let histogram: HistogramData?

    init(
        coordinator: PhotoAnalysisCoordinator,
        assetID: PhotoAssetID,
        source: ImageSource,
        surface: PreviewSurface,
        histogram: HistogramData? = nil
    ) {
        _model = StateObject(wrappedValue: AnalysisDebugPanelModel(
            coordinator: coordinator, assetID: assetID, source: source
        ))
        _surface = ObservedObject(wrappedValue: surface)
        self.histogram = histogram
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Photo Analysis (Debug)", systemImage: "ladybug")
                    .font(.title3.weight(.semibold))
                Spacer()
                if model.isLoading { ProgressView().controlSize(.small) }
            }

            if let analysis = model.analysis {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        overlaySection
                        factsSection(analysis)
                        if let histogram {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Global histogram").font(.headline)
                                HistogramChart(data: histogram, channel: .luma)
                                    .frame(height: 110)
                                    .background(LumoTheme.analysisBackground, in: RoundedRectangle(cornerRadius: 6))
                            }
                        }
                    }
                }
            } else if model.isLoading {
                ContentUnavailableView("Loading analysis", systemImage: "waveform.path.ecg")
            } else {
                ContentUnavailableView(
                    "Analysis unavailable",
                    systemImage: "exclamationmark.triangle",
                    description: Text(model.errorMessage ?? "No debug analysis is available for this photo.")
                )
            }
        }
        .padding(20)
        .frame(minWidth: 560, minHeight: 560)
        .task { model.load() }
    }

    private var overlaySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Mask overlays").font(.headline)
            ZStack {
                PreviewSurfaceView(surface: surface)
                    .allowsHitTesting(false)
                ForEach(model.masks.compactMap { entry -> (SemanticMaskKind, NormalizedMask)? in
                    guard model.isVisible(entry.kind), let pixels = entry.pixels else { return nil }
                    return (entry.kind, pixels)
                }, id: \.0) { _, pixels in
                    MaskGridView(mask: pixels)
                        .aspectRatio(
                            CGFloat(pixels.size.width) / CGFloat(pixels.size.height),
                            contentMode: .fit
                        )
                        .allowsHitTesting(false)
                }
            }
            .frame(minHeight: 180)
            .clipShape(RoundedRectangle(cornerRadius: 8))
                ForEach(model.masks) { entry in
                HStack(alignment: .firstTextBaseline) {
                    if entry.pixels != nil {
                        Toggle(entry.title, isOn: Binding(
                            get: { model.isVisible(entry.kind) },
                            set: { model.setVisible(entry.kind, $0) }
                        ))
                        .toggleStyle(.checkbox)
                    } else {
                        Text(entry.title)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let mask = entry.mask {
                        Text("confidence \(percentage(mask.confidence)) • coverage \(percentage(mask.coverage))")
                            .monospacedDigit()
                    }
                    Text(entry.normalModeReason)
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
            }
        }
    }

    private func factsSection(_ analysis: PhotoAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Facts").font(.headline)
            factRow("Tonal key", analysis.scene.tonalKey.rawValue.capitalized)
            factRow("Dynamic range", percentage(analysis.scene.dynamicRange))
            factRow("Subject prominence", percentage(analysis.scene.subjectProminence))
            factRow("Backlighting", percentage(analysis.scene.backlightingLikelihood))
            factRow("High key", percentage(analysis.scene.highKeyLikelihood))
            factRow("Low key", percentage(analysis.scene.lowKeyLikelihood))
            factRow("Primary subject confidence", percentage(analysis.primarySubject.confidence))
            factRow("Analysis confidence", percentage(analysis.quality.overallConfidence))
            factRow("Normal-mode mask threshold", "confidence ≥ \(percentage(MaskPresentationPolicy.minimumConfidence)), coverage ≥ \(percentage(MaskPresentationPolicy.minimumCoverage))")
            factRow("Analysis timings", format(analysis.timings.total))
        }
    }

    private func factRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospacedDigit()
        }
        .font(.caption)
    }

    private func percentage(_ value: Float) -> String { "\(Int(value * 100))%" }

    private func format(_ duration: Duration) -> String {
        let components = duration.components
        let milliseconds = Double(components.seconds) * 1_000
            + Double(components.attoseconds) / 1_000_000_000_000_000
        return String(format: "%.1f ms", milliseconds)
    }
}

/// On-demand analysis details embedded at the bottom of the Info inspector. This intentionally
/// shares the debug model's loading and mask policy, while keeping the normal inspector's layout
/// and presentation independent from the developer-only sheet.
struct PhotoAnalysisInspectSection: View {
    @StateObject private var model: AnalysisDebugPanelModel
    @ObservedObject private var surface: PreviewSurface
    let histogram: HistogramData?
    @Binding var isExpanded: Bool

    init(
        coordinator: PhotoAnalysisCoordinator,
        assetID: PhotoAssetID,
        source: ImageSource,
        surface: PreviewSurface,
        histogram: HistogramData?,
        isExpanded: Binding<Bool>
    ) {
        _model = StateObject(wrappedValue: AnalysisDebugPanelModel(
            coordinator: coordinator, assetID: assetID, source: source
        ))
        _surface = ObservedObject(wrappedValue: surface)
        self.histogram = histogram
        _isExpanded = isExpanded
    }

    var body: some View {
        InspectorDisclosure("Photo Analysis", isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 12) {
                if let analysis = model.analysis {
                    analysisContent(analysis)
                } else if model.isLoading {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Loading analysis and mask overlays…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                } else {
                    Label(
                        model.errorMessage ?? "Analysis is unavailable for this photo.",
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.top, 8)
        }
        .task(id: isExpanded) {
            if isExpanded { model.load() }
            else { model.cancel() }
        }
    }

    @ViewBuilder
    private func analysisContent(_ analysis: PhotoAnalysis) -> some View {
        compactFacts(analysis)

        if let histogram {
            VStack(alignment: .leading, spacing: 6) {
                Text("Histogram relationship").font(.subheadline.weight(.semibold))
                HistogramChart(data: histogram, channel: .luma)
                    .frame(height: 76)
                    .background(LumoTheme.analysisBackground, in: RoundedRectangle(cornerRadius: 6))
                Text("Global luminance distribution used by the analysis.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }

        if !model.masks.isEmpty { maskOverlays }
    }

    private func compactFacts(_ analysis: PhotoAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Facts and quality").font(.subheadline.weight(.semibold))
            factRow("Tonal key", analysis.scene.tonalKey.rawValue.capitalized)
            factRow("Dynamic range", percentage(analysis.scene.dynamicRange))
            factRow("Subject prominence", percentage(analysis.scene.subjectProminence))
            factRow("Backlighting", percentage(analysis.scene.backlightingLikelihood))
            factRow("Analysis confidence", percentage(analysis.quality.overallConfidence))
            factRow("Regions", "\(analysis.regions.count) available")
            factRow("Analysis time", format(analysis.timings.total))
        }
    }

    private var maskOverlays: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Mask overlays").font(.subheadline.weight(.semibold))
            ZStack {
                PreviewSurfaceView(surface: surface).allowsHitTesting(false)
                ForEach(model.masks.compactMap { entry -> (SemanticMaskKind, NormalizedMask)? in
                    guard model.isVisible(entry.kind), let pixels = entry.pixels else { return nil }
                    return (entry.kind, pixels)
                }, id: \.0) { _, pixels in
                    MaskGridView(mask: pixels)
                        .aspectRatio(
                            CGFloat(pixels.size.width) / CGFloat(pixels.size.height),
                            contentMode: .fit
                        )
                        .allowsHitTesting(false)
                }
            }
            .frame(height: 130)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            ForEach(model.masks) { entry in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if entry.pixels != nil {
                        Toggle(entry.title, isOn: Binding(
                            get: { model.isVisible(entry.kind) },
                            set: { model.setVisible(entry.kind, $0) }
                        ))
                        .toggleStyle(.checkbox)
                    } else {
                        Text(entry.title).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 4)
                    if let mask = entry.mask {
                        Text("\(percentage(mask.confidence)) / \(percentage(mask.coverage))")
                            .monospacedDigit()
                    }
                }
                .font(.caption)
            }
        }
    }

    private func factRow(_ label: String, _ value: String) -> some View {
        HStack(spacing: 6) {
            Text(label).foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Text(value).monospacedDigit()
        }
        .font(.caption)
    }

    private func percentage(_ value: Float) -> String { "\(Int(value * 100))%" }

    private func format(_ duration: Duration) -> String {
        let components = duration.components
        let milliseconds = Double(components.seconds) * 1_000
            + Double(components.attoseconds) / 1_000_000_000_000_000
        return String(format: "%.1f ms", milliseconds)
    }
}

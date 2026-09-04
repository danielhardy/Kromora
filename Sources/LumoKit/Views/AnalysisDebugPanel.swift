import SwiftUI

/// Developer-only analysis inspection. Work starts from the sheet's task, so merely opening an
/// image has no analysis/mask cost when this panel is hidden.
@MainActor
final class AnalysisDebugPanelModel: ObservableObject {
    struct MaskEntry: Identifiable {
        let kind: SemanticMaskKind
        let mask: RegionMask
        let pixels: NormalizedMask

        var id: SemanticMaskKind { kind }

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
                            guard let mask = try? await coordinator.mask(
                                assetID: assetID, source: source, kind: kind, quality: .analysis
                            ), let pixels = await coordinator.pixels(for: mask.reference) else {
                                return nil
                            }
                            return MaskEntry(kind: kind, mask: mask, pixels: pixels)
                        }
                    }
                    for await entry in group {
                        if let entry { entries.append(entry) }
                    }
                }
                guard !Task.isCancelled else { return }
                self.analysis = analysis
                self.masks = entries.sorted { $0.title < $1.title }
                self.visibleKinds = Set(entries.map(\.kind))
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
                ForEach(model.masks.filter { model.isVisible($0.kind) }) { entry in
                    MaskGridView(mask: entry.pixels)
                        .aspectRatio(
                            CGFloat(entry.pixels.size.width) / CGFloat(entry.pixels.size.height),
                            contentMode: .fit
                        )
                        .allowsHitTesting(false)
                }
            }
            .frame(minHeight: 180)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            ForEach(model.masks) { entry in
                Toggle(entry.title, isOn: Binding(
                    get: { model.isVisible(entry.kind) },
                    set: { model.setVisible(entry.kind, $0) }
                ))
                .toggleStyle(.checkbox)
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

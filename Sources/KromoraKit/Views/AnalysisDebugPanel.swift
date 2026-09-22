import SwiftUI

/// On-demand analysis details embedded at the bottom of the Info inspector. This intentionally
/// shares the debug model's loading and mask policy, while keeping the normal inspector's layout
/// and presentation independent from the developer-only sheet.
struct PhotoAnalysisInspectSection: View {
    @StateObject private var model: AnalysisDebugPanelModel
    @ObservedObject private var surface: PreviewSurface
    let histogram: HistogramData?
    @Binding var isExpanded: Bool
    let onUseEditingMask: (SemanticMaskKind, RegionMask, NormalizedMask) -> Void

    init(
        coordinator: PhotoAnalysisCoordinator,
        assetID: PhotoAssetID,
        source: ImageSource,
        surface: PreviewSurface,
        histogram: HistogramData?,
        isExpanded: Binding<Bool>,
        onUseEditingMask: @escaping (SemanticMaskKind, RegionMask, NormalizedMask) -> Void
    ) {
        _model = StateObject(wrappedValue: AnalysisDebugPanelModel(
            coordinator: coordinator, assetID: assetID, source: source
        ))
        _surface = ObservedObject(wrappedValue: surface)
        self.histogram = histogram
        _isExpanded = isExpanded
        self.onUseEditingMask = onUseEditingMask
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
                    Button("Retry analysis") { model.load() }
                        .buttonStyle(.borderless)
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
                    .background(KromoraTheme.analysisBackground, in: RoundedRectangle(cornerRadius: 6))
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

                if entry.kind.isInfoEditingMask {
                    infoEditingMaskAction(for: entry)
                }
            }
        }
    }

    @ViewBuilder
    private func infoEditingMaskAction(for entry: AnalysisDebugPanelModel.MaskEntry) -> some View {
        if model.isLoading {
            Label("Analyzing \(entry.title) editing mask…", systemImage: "hourglass")
                .font(.caption2)
                .foregroundStyle(.secondary)
        } else if let mask = entry.mask, let pixels = entry.pixels,
                  MaskPresentationPolicy.decision(for: mask) == .actionable {
            Button {
                onUseEditingMask(entry.kind, mask, pixels)
            } label: {
                Label("Use \(entry.title) as editing mask", systemImage: "wand.and.rays")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityLabel("Use \(entry.title) as editing mask")
            .accessibilityHint("Create or select the \(entry.title) mask in the Masking workflow")
        } else {
            Label(entry.editingMaskUnavailableMessage, systemImage: "slash.circle")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
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

private extension SemanticMaskKind {
    var isInfoEditingMask: Bool {
        switch self {
        case .subject, .person: return true
        default: return false
        }
    }
}

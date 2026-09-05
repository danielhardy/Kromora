import SwiftUI

/// Legacy semantic-result component retained for analysis diagnostics and compatibility tests.
/// It is not part of the editor workflow; `MaskingWorkspace` owns persistent layer selection and
/// all document mutations. It intentionally has no Vision or Core Image code:
/// every selection enters through PhotoAnalysisCoordinator and every combination uses
/// MaskOperations, so Auto and this UI share one mask representation and cache.
@MainActor
final class MaskingPanelModel: ObservableObject {
    struct Selection: Identifiable, Hashable {
        let kind: SemanticMaskKind

        var id: SemanticMaskKind { kind }

        var title: String {
            switch kind {
            case .subject: return "Subject"
            case .person: return "Person"
            case .background: return "Background"
            case .face: return "Face"
            case .faceInstance(let index): return "Face \(index + 1)"
            case .foregroundInstance(let index): return "Foreground \(index + 1)"
            case .unknown(let name): return name
            }
        }
    }

    @Published private(set) var availableSelections: [Selection] = []
    @Published private(set) var selectedKind: SemanticMaskKind?
    @Published private(set) var selectedMask: RegionMask?
    @Published private(set) var selectedPixels: NormalizedMask?
    @Published private(set) var appliedMask: RegionMask?
    @Published private(set) var isLoading = false
    @Published private(set) var isApplying = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var loadWarningMessage: String?
    @Published private(set) var unavailableTargetMessages: [String] = []
    @Published var isInverted = false {
        didSet {
            guard isInverted != oldValue else { return }
            appliedMask = nil
            refreshDisplayedPixels()
        }
    }

    private let coordinator: PhotoAnalysisCoordinator
    private let assetID: PhotoAssetID
    private let source: ImageSource
    /// Optional until the local-adjustment model can own a RegionMask. Keeping the hook explicit
    /// lets tests prove the full select/invert/apply handoff without shipping a button that only
    /// dismisses this sheet.
    private let onApply: (@MainActor (PhotoAssetID, RegionMask) -> Void)?
    private var masks: [SemanticMaskKind: RegionMask] = [:]
    private var pixels: [SemanticMaskKind: NormalizedMask] = [:]
    private var loadTask: Task<Void, Never>?

    init(
        coordinator: PhotoAnalysisCoordinator,
        assetID: PhotoAssetID,
        source: ImageSource,
        onApply: (@MainActor (PhotoAssetID, RegionMask) -> Void)? = nil
    ) {
        self.coordinator = coordinator
        self.assetID = assetID
        self.source = source
        self.onApply = onApply
    }

    deinit { loadTask?.cancel() }

    func load() {
        loadTask?.cancel()
        isLoading = true
        errorMessage = nil
        loadWarningMessage = nil
        unavailableTargetMessages = []
        appliedMask = nil
        loadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let candidates: [SemanticMaskKind] = [.subject, .person, .background, .face]
            var found: [SemanticMaskKind: RegionMask] = [:]
            var payloads: [SemanticMaskKind: NormalizedMask] = [:]
            var failures: [SemanticMaskKind: String] = [:]
            await withTaskGroup(of: (SemanticMaskKind, RegionMask?, NormalizedMask?, String?)?.self) { group in
                for kind in candidates {
                    group.addTask { [coordinator, assetID, source] in
                        do {
                            let mask = try await coordinator.mask(
                                assetID: assetID, source: source, kind: kind, quality: .preview
                            )
                            guard let pixels = await coordinator.pixels(for: mask.reference) else {
                                return (kind, mask, NormalizedMask?.none, "Mask pixels were unavailable")
                            }
                            return (kind, mask, pixels, nil)
                        } catch is CancellationError {
                            return nil
                        } catch {
                            return (kind, RegionMask?.none, NormalizedMask?.none,
                                    Self.errorDescription(error))
                        }
                    }
                }
                for await result in group {
                    guard let result else { continue }
                    if let mask = result.1, let pixels = result.2 {
                        found[result.0] = mask
                        payloads[result.0] = pixels
                    } else if let failure = result.3 {
                        failures[result.0] = failure
                    }
                }
            }
            guard !Task.isCancelled else { return }
            masks = found
            pixels = payloads
            let filtered = candidates.compactMap { kind -> (SemanticMaskKind, String)? in
                guard let mask = found[kind],
                      MaskPresentationPolicy.decision(for: mask) != .actionable else { return nil }
                let decision = MaskPresentationPolicy.decision(for: mask)
                return (kind, decision.userMessage ?? "This target is unavailable.")
            }
            unavailableTargetMessages = filtered.map { "\(Self.title(for: $0.0)): \($0.1)" }
            loadWarningMessage = failures.isEmpty && filtered.isEmpty
                ? nil : "Some mask targets were unavailable."
            availableSelections = candidates
                .filter {
                    guard let mask = found[$0] else { return false }
                    return MaskPresentationPolicy.decision(for: mask) == .actionable
                }
                .map(Selection.init(kind:))
            isLoading = false
            if selectedKind == nil, let first = availableSelections.first?.kind {
                select(first)
            } else {
                refreshDisplayedPixels()
            }
            if availableSelections.isEmpty {
                errorMessage = failures.isEmpty
                    ? (unavailableTargetMessages.isEmpty
                        ? "No semantic regions were available for this photo."
                        : "No usable regions were found for this photo.")
                    : "Mask generation failed for this photo. Retry to try again."
            }
        }
    }

    private static func title(for kind: SemanticMaskKind) -> String {
        Selection(kind: kind).title
    }

    func select(_ kind: SemanticMaskKind) {
        guard let mask = masks[kind] else { return }
        selectedKind = kind
        selectedMask = mask
        appliedMask = nil
        refreshDisplayedPixels()
    }

    var selectedMaskTitle: String? {
        guard let selectedKind else { return nil }
        let title = Selection(kind: selectedKind).title
        return isInverted ? "Inverted \(title)" : title
    }

    var canApplyMask: Bool {
        selectedMask != nil && onApply != nil && !isApplying
    }

    var applyHelp: String {
        guard selectedMask != nil else { return "Select an available mask first." }
        guard onApply != nil else {
            return "Local adjustments cannot own a mask yet, so applying is disabled."
        }
        return "Use \(selectedMaskTitle ?? "mask") in the active local adjustment."
    }

    /// Applies the selected RegionMask, or the RegionMask produced by the shared invert operation.
    /// The callback carries the asset ID as well as the mask so a future local-adjustment owner can
    /// reject a late result from another photo instead of accidentally attaching it to the current
    /// document.
    func apply() async {
        guard let selectedMask else { return }
        guard let onApply else {
            errorMessage = "Local adjustments cannot own a mask yet. Applying is disabled until an adjustment hook is available."
            return
        }

        isApplying = true
        defer { isApplying = false }
        do {
            let mask = isInverted
                ? try await coordinator.invertedMask(selectedMask)
                : selectedMask
            guard !Task.isCancelled else { return }
            onApply(assetID, mask)
            appliedMask = mask
        } catch is CancellationError {
            return
        } catch {
            errorMessage = "Could not prepare \(selectedMaskTitle ?? "the mask"). Try again."
        }
    }

    private nonisolated static func errorDescription(_ error: Error) -> String {
        if let localized = error as? LocalizedError, let description = localized.errorDescription {
            return description
        }
        return String(describing: error)
    }

    private func refreshDisplayedPixels() {
        guard let selectedKind, let sourcePixels = pixels[selectedKind] else {
            selectedPixels = nil
            return
        }
        selectedPixels = isInverted ? try? MaskOperations.invert(sourcePixels) : sourcePixels
    }
}

/// A reusable image-plus-mask preview. The image is presentation-only; the mask is drawn from the
/// same normalized upper-left coordinate system used by analysis and masking operations.
struct MaskOverlayView: View {
    let surface: PreviewSurface?
    let mask: NormalizedMask?

    var body: some View {
        ZStack {
            if let surface {
                PreviewSurfaceView(surface: surface)
                    .allowsHitTesting(false)
            } else {
                Color.black.opacity(0.18)
            }
            if let mask {
                MaskGridView(mask: mask)
                    .aspectRatio(CGFloat(mask.size.width) / CGFloat(mask.size.height), contentMode: .fit)
                    .allowsHitTesting(false)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.secondary.opacity(0.3)))
    }
}

struct MaskGridView: View {
    let mask: NormalizedMask

    var body: some View {
        Canvas { context, size in
            let stride = max(1, max(mask.size.width, mask.size.height) / 96)
            let cellWidth = size.width / CGFloat(mask.size.width)
            let cellHeight = size.height / CGFloat(mask.size.height)
            for y in Swift.stride(from: 0, to: mask.size.height, by: stride) {
                for x in Swift.stride(from: 0, to: mask.size.width, by: stride) {
                    let alpha = CGFloat(mask.values[y * mask.size.width + x]) * 0.55
                    guard alpha > 0.01 else { continue }
                    context.fill(
                        Path(CGRect(
                            x: CGFloat(x) * cellWidth,
                            y: CGFloat(y) * cellHeight,
                            width: cellWidth * CGFloat(stride),
                            height: cellHeight * CGFloat(stride)
                        )),
                        with: .color(.orange.opacity(alpha))
                    )
                }
            }
        }
    }
}

struct MaskingPanel: View {
    @StateObject private var model: MaskingPanelModel
    let surface: PreviewSurface?

    init(
        coordinator: PhotoAnalysisCoordinator,
        assetID: PhotoAssetID,
        source: ImageSource,
        surface: PreviewSurface? = nil
    ) {
        _model = StateObject(wrappedValue: MaskingPanelModel(
            coordinator: coordinator, assetID: assetID, source: source
        ))
        self.surface = surface
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Masking", systemImage: "wand.and.rays")
                    .font(.title3.weight(.semibold))
                Spacer()
                if model.isLoading { ProgressView().controlSize(.small) }
            }

            if model.availableSelections.isEmpty, !model.isLoading {
                VStack(spacing: 12) {
                    ContentUnavailableView(
                        "No masks available",
                        systemImage: "rectangle.dashed",
                        description: Text(model.errorMessage ?? "This photo has no selectable semantic regions.")
                    )
                    Button("Retry") { model.load() }
                        .buttonStyle(.bordered)
                        .accessibilityHint("Retry semantic mask generation for this photo")
                }
            } else {
                Picker("Mask target", selection: Binding(
                    get: { model.selectedKind ?? model.availableSelections.first?.kind },
                    set: { if let newValue = $0 { model.select(newValue) } }
                )) {
                    ForEach(model.availableSelections) { selection in
                        Text(selection.title).tag(Optional(selection.kind))
                    }
                }
                .pickerStyle(.segmented)

                MaskOverlayView(surface: surface, mask: model.selectedPixels)
                    .frame(minHeight: 220)

                HStack {
                    Toggle("Invert selection", isOn: $model.isInverted)
                    Spacer()
                    if let mask = model.selectedMask {
                        Text("Preview • \(Int(mask.coverage * 100))% coverage")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let warning = model.loadWarningMessage {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(warning, systemImage: "exclamationmark.triangle")
                        ForEach(model.unavailableTargetMessages, id: \.self) { message in
                            Text(message)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                if let selectedMaskTitle = model.selectedMaskTitle {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Selected target: \(selectedMaskTitle)")
                            .font(.subheadline.weight(.semibold))
                        if model.appliedMask != nil {
                            Label(
                                "Active target in local adjustment: \(selectedMaskTitle)",
                                systemImage: "checkmark.circle.fill"
                            )
                            .font(.caption)
                            .foregroundStyle(.green)
                        } else {
                            Text(model.applyHelp)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let errorMessage = model.errorMessage, !model.availableSelections.isEmpty {
                            Label(errorMessage, systemImage: "exclamationmark.triangle")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Selected target: \(selectedMaskTitle)")
                }

                HStack {
                    Spacer()
                    Button("Cancel") { dismiss() }
                    Button(model.isApplying ? "Applying…" : "Apply Mask") {
                        Task { await model.apply() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.canApplyMask)
                    .help(model.applyHelp)
                    .accessibilityHint(model.applyHelp)
                }
            }

            if model.availableSelections.isEmpty, !model.isLoading {
                HStack {
                    Spacer()
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .padding(20)
        .frame(minWidth: 520, minHeight: 390)
        .task { model.load() }
    }

    @Environment(\.dismiss) private var dismiss
}

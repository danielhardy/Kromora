import SwiftUI

/// The v1 masking panel is selection-only. It intentionally has no Vision or Core Image code:
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
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published var isInverted = false {
        didSet {
            guard isInverted != oldValue else { return }
            refreshDisplayedPixels()
        }
    }

    private let coordinator: PhotoAnalysisCoordinator
    private let assetID: PhotoAssetID
    private let source: ImageSource
    private var masks: [SemanticMaskKind: RegionMask] = [:]
    private var pixels: [SemanticMaskKind: NormalizedMask] = [:]
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
            let candidates: [SemanticMaskKind] = [.subject, .person, .background, .face]
            var found: [SemanticMaskKind: RegionMask] = [:]
            var payloads: [SemanticMaskKind: NormalizedMask] = [:]
            await withTaskGroup(of: (SemanticMaskKind, RegionMask, NormalizedMask)?.self) { group in
                for kind in candidates {
                    group.addTask { [coordinator, assetID, source] in
                        guard let mask = try? await coordinator.mask(
                            assetID: assetID, source: source, kind: kind, quality: .preview
                        ), let pixels = await coordinator.pixels(for: mask.reference) else {
                            return nil
                        }
                        return (kind, mask, pixels)
                    }
                }
                for await result in group {
                    guard let result else { continue }
                    found[result.0] = result.1
                    payloads[result.0] = result.2
                }
            }
            guard !Task.isCancelled else { return }
            masks = found
            pixels = payloads
            availableSelections = candidates
                .filter { found[$0] != nil }
                .map(Selection.init(kind:))
            isLoading = false
            if selectedKind == nil, let first = availableSelections.first?.kind {
                select(first)
            } else {
                refreshDisplayedPixels()
            }
            if availableSelections.isEmpty {
                errorMessage = "No semantic regions were available for this photo."
            }
        }
    }

    func select(_ kind: SemanticMaskKind) {
        guard let mask = masks[kind] else { return }
        selectedKind = kind
        selectedMask = mask
        refreshDisplayedPixels()
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
                ContentUnavailableView(
                    "No masks available",
                    systemImage: "rectangle.dashed",
                    description: Text(model.errorMessage ?? "This photo has no selectable semantic regions.")
                )
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
            }
        }
        .padding(20)
        .frame(minWidth: 520, minHeight: 390)
        .task { model.load() }
    }
}

import SwiftUI

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
        .onDisappear { model.cancel() }
    }

    @Environment(\.dismiss) private var dismiss
}

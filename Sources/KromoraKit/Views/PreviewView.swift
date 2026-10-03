import SwiftUI

/// Main image preview area. Supports side-by-side (original vs Look)
/// and single-image mode. Hold Space to flash original in single mode.
struct PreviewView: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @ObservedObject var viewModel: AppViewModel
    @Bindable var canvasState: CanvasInteractionState
    // The preview image is owned by a separate observation boundary. Keep observing it even while
    // the spinner is on screen; otherwise a completed replacement render can sit in the surface
    // until an unrelated AppViewModel change causes this view to rebuild.
    @ObservedObject private var previewSurface: PreviewSurface
    @ObservedObject private var originalPreviewSurface: PreviewSurface
    @State private var isDropTargeted = false
    @State private var isCaptureOverlayVisible = false
    @ObservedObject private var maskingState: MaskInteractionState
    @ObservedObject private var retouchState: RetouchInteractionState
    @ObservedObject private var settings: KromoraSettings

    init(viewModel: AppViewModel) {
        _viewModel = ObservedObject(wrappedValue: viewModel)
        _canvasState = Bindable(wrappedValue: viewModel.canvasState)
        _previewSurface = ObservedObject(wrappedValue: viewModel.previewSurface)
        _originalPreviewSurface = ObservedObject(wrappedValue: viewModel.originalPreviewSurface)
        _maskingState = ObservedObject(wrappedValue: viewModel.maskInteractionState)
        _retouchState = ObservedObject(wrappedValue: viewModel.retouchInteractionState)
        _settings = ObservedObject(wrappedValue: viewModel.settings)
    }

    private var maskOverlayBackingScale: CGFloat {
        NSScreen.main?.backingScaleFactor ?? 2
    }

    /// The editor canvas is deliberately distinct from the source browser's secondary chrome.
    /// The Metal surface resolves the same token for its letterbox; see `PreviewSurfaceView`.
    private var bgColor: Color { KromoraTheme.canvasBackground }

    private var isPreviewLoading: Bool {
        viewModel.isLoading || viewModel.previewState == .loading
    }

    var body: some View {
        ZStack {
            bgColor

            Group {
                if previewSurface.image != nil {
                    if canvasState.isCropToolActive {
                        singleView
                    } else if viewModel.isSideBySideVisible {
                        sideBySideView
                    } else {
                        singleView
                    }
                } else if isPreviewLoading {
                    ProgressView()
                        .scaleEffect(1.5)
                        .progressViewStyle(.circular)
                } else if viewModel.previewState == .failed {
                    failedState
                } else {
                    emptyState
                }
            }
            .allowsHitTesting(!isPreviewLoading)

            if previewSurface.image != nil && viewModel.isNavigationLoading {
                ProgressView()
                    .controlSize(.large)
                    .scaleEffect(1.35)
                    .padding(18)
                    .background(.regularMaterial, in: Circle())
                    .accessibilityLabel("Loading selected photo preview")
                    .allowsHitTesting(false)
            }

            if previewSurface.image != nil,
                !isPreviewLoading,
                !canvasState.isCropToolActive,
                viewModel.collection.selectedItem?.asset.flag == .reject
            {
                VStack {
                    Label("Rejected", systemImage: "xmark.circle.fill")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(.red.opacity(0.9), in: Capsule())
                        .padding(16)
                    Spacer()
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }

            if previewSurface.image != nil,
                !isPreviewLoading,
                !canvasState.isCropToolActive,
                isCaptureOverlayVisible,
                !viewModel.metadata.captureOverlayRows.isEmpty
            {
                VStack {
                    Spacer()
                    HStack {
                        CaptureMetadataOverlay(rows: viewModel.metadata.captureOverlayRows)
                        Spacer(minLength: 0)
                    }
                }
                .padding(20)
                .allowsHitTesting(false)
            }

            if previewSurface.image != nil, !isPreviewLoading, settings.showClippingAlerts,
               !canvasState.isCropToolActive, let histogram = viewModel.histogram,
               histogram.clippedHighlights + histogram.clippedShadows > 0 {
                VStack {
                    HStack(spacing: 8) {
                        Label("\(histogram.clippedHighlights) highlights", systemImage: "sun.max.fill")
                            .foregroundStyle(.orange)
                        Label("\(histogram.clippedShadows) shadows", systemImage: "moon.fill")
                            .foregroundStyle(.cyan)
                    }
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(.black.opacity(0.76), in: Capsule())
                    .overlay(Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 0.5))
                    .padding(.top, 14)
                    Spacer()
                }
                .allowsHitTesting(false)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Image clipping alerts")
            }
        }
        .onDrop(
            of: ImageDrop.acceptedTypes,
            delegate: ImageDropDelegate(viewModel: viewModel, isTargeted: $isDropTargeted)
        )
        .onReceive(NotificationCenter.default.publisher(for: .toggleCaptureMetadataOverlay)) { _ in
            isCaptureOverlayVisible.toggle()
        }
        .overlay(alignment: .bottomTrailing) {
            if previewSurface.image != nil && !canvasState.isCropToolActive {
                GuidedEditCards(viewModel: viewModel)
            }
        }
        .overlay(alignment: .bottom) {
            if viewModel.statusMessage.hasPrefix("Exported") {
                HStack(spacing: 12) {
                    Label("Export complete", systemImage: "checkmark.circle.fill")
                    Button("Export another…") { viewModel.shareDialog() }
                    Button("Back to Library") { _ = viewModel.navigate(to: .grid) }
                }
                .font(.caption)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(.regularMaterial, in: Capsule())
                .padding(.bottom, 14)
            }
        }
    }

    private var failedState: some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 28, weight: .thin))
                .foregroundStyle(.secondary.opacity(0.7))
            Text(viewModel.statusMessage)
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 24)
        }
    }

    // MARK: - Side-by-side

    private var sideBySideView: some View {
        GeometryReader { geo in
            HStack(spacing: 2) {
                // Original
                panelView(
                    surface: originalPreviewSurface,
                    label: "Original",
                    accessibilityLabel: "Original photo preview",
                    labelSide: .leading,
                    width: geo.size.width / 2,
                    showsMaskOverlay: false
                )

                // Divider
                Rectangle()
                    .fill(Color.primary.opacity(0.15))
                    .frame(width: 1)

                // Look applied
                panelView(
                    surface: previewSurface,
                    label: viewModel.selectedLook?.name ?? "Adjusted",
                    accessibilityLabel: viewModel.selectedLook.map {
                        "\($0.name) edited photo preview"
                    } ?? "Edited photo preview",
                    labelSide: .trailing,
                    width: geo.size.width / 2,
                    showsMaskOverlay: true
                )
            }
        }
        .padding(8)
    }

    private func panelView(
        surface: PreviewSurface, label: String, accessibilityLabel: String,
        labelSide: HorizontalAlignment, width: CGFloat, showsMaskOverlay: Bool
    ) -> some View {
        ZStack(alignment: labelSide == .leading ? .topLeading : .topTrailing) {
            bgColor

            if surface.image != nil {
                canvasSurface(surface, showsMaskOverlay: showsMaskOverlay)
            } else {
                ProgressView()
                    .scaleEffect(1.2)
                    .progressViewStyle(.circular)
                    .accessibilityLabel("Loading Original preview")
            }

            ComparisonBadge(text: label)
                .padding(12)
        }
        .frame(width: width)
        .clipped()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Presentation only; does not change edits or export")
    }

    // MARK: - Single image

    private var singleView: some View {
        GeometryReader { geometry in
            ZStack {
                    if previewSurface.image != nil {
                        canvasSurface(previewSurface, showsMaskOverlay: true)
                            .padding(8)
                    }

                    if canvasState.isCropToolActive, viewModel.sourceSize != .zero {
                        CropOverlayView(
                            normalizedRect: canvasState.cropDraft ?? CropAdjustments.unitRect,
                            imageSize: viewModel.cropSourceSize,
                            sourceImageSize: viewModel.sourceSize,
                            aspectRatio: canvasState.cropAspectRatio,
                            orientation: canvasState.cropOrientation,
                            straightenAngle: canvasState.cropStraightenAngle,
                            pixelAspectRatio: canvasState.cropPixelAspectRatio,
                            onChange: viewModel.updateCropDraft
                        )
                        .padding(8)
                    }

                    if previewSurface.image != nil, !canvasState.isCropToolActive {
                        // Comparison badge
                        if viewModel.isShowingOriginal && viewModel.isComparisonAvailable {
                            VStack {
                                HStack {
                                    ComparisonBadge(text: "Original")
                                    Spacer()
                                }
                                Spacer()
                            }
                            .padding(20)
                        }

                        // Look name badge
                        if !viewModel.isShowingOriginal, let look = viewModel.selectedLook {
                            VStack {
                                HStack {
                                    Spacer()
                                    ComparisonBadge(text: look.name)
                                }
                                Spacer()
                            }
                            .padding(20)
                        }
                    }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(singleViewAccessibilityLabel)
            .accessibilityHint("Presentation only; does not change edits or export")
            .frame(width: geometry.size.width, height: geometry.size.height)
            .animation(
                accessibilityReduceMotion ? nil : .easeInOut(duration: 0.3),
                value: canvasState.isCropToolActive
            )
            // The GPU preview request changes orientation at the same time as the draft frame is
            // remapped. Animating this narrow crop subtree keeps the frame/layout transition
            // readable without forcing a full-resolution render for intermediate angles.
            .animation(
                accessibilityReduceMotion ? nil : .snappy(duration: 0.3, extraBounce: 0.04),
                value: canvasState.cropRotation
            )
        }
    }

    private var singleViewAccessibilityLabel: String {
        if viewModel.isShowingOriginal && viewModel.isComparisonAvailable {
            return "Original photo preview"
        }
        if let look = viewModel.selectedLook {
            return "\(look.name) edited photo preview"
        }
        return viewModel.isComparisonAvailable ? "Edited photo preview" : "Photo preview"
    }

    /// A full-panel surface with presentation-only mouse and trackpad navigation. Pan, pinch, and
    /// double-click live on `PreviewMTKView` so a SwiftUI `DragGesture` cannot swallow the AppKit
    /// click path. The same navigation value is passed to both comparison panels.
    @ViewBuilder
    private func canvasSurface(
        _ surface: PreviewSurface, showsMaskOverlay: Bool = true
    ) -> some View {
        GeometryReader { geometry in
            let preview = PreviewSurfaceView(
                surface: surface,
                navigation: canvasState.navigation,
                onScrollZoom: { factor, point, viewportSize in
                    viewModel.zoomCanvas(by: factor, at: point, viewportSize: viewportSize)
                },
                onDoubleClick: { point, viewportSize in
                    viewModel.toggleCanvasZoom(at: point, viewportSize: viewportSize)
                },
                onCanvasInteractionBegan: { viewModel.beginCanvasInteraction() },
                onCanvasInteractionEnded: { viewModel.endCanvasInteraction() },
                onPan: { delta, viewportSize in
                    viewModel.panCanvas(by: delta, viewportSize: viewportSize)
                },
                onMagnify: { factor, point, viewportSize in
                    viewModel.zoomCanvas(by: factor, at: point, viewportSize: viewportSize)
                },
                isWhiteBalanceSampling: viewModel.isWhiteBalanceSampling && showsMaskOverlay,
                onWhiteBalanceSamplePoint: { point, viewportSize, commit in
                    viewModel.updateWhiteBalanceSample(
                        at: point, viewportSize: viewportSize, commit: commit)
                },
                onDrawableSizeChange: { size in viewModel.updatePreviewBackingSize(size) },
                onCanvasGeometryChange: showsMaskOverlay
                    ? { size in viewModel.updateCanvasBackingSize(size) }
                    : nil,
                viewSpaceRotationAngle: canvasState.isCropToolActive
                    ? canvasState.cropStraightenAngle : 0,
                ignoresHits: canvasState.isCropToolActive,
                reduceMotion: accessibilityReduceMotion
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            ZStack {
                if canvasState.isCropToolActive {
                    preview.allowsHitTesting(false)
                } else {
                    preview
                }

                if showsMaskOverlay, viewModel.isMaskingWorkspaceActive,
                    (maskingState.showOverlay || maskingState.overlayPreviewTarget != nil),
                    viewModel.sourceSize != .zero,
                    maskingState.selectedLayerID != nil || maskingState.hasDraft
                        || maskingState.activeTool == .linear || maskingState.activeTool == .radial
                        || maskingState.overlayPreviewTarget != nil
                {
                    MaskCanvasOverlay(
                        viewModel: viewModel,
                        maskingState: maskingState,
                        sourceSize: viewModel.sourceSize,
                        crop: viewModel.document.crop,
                        navigation: canvasState.navigation,
                        backingScale: maskOverlayBackingScale
                    )
                    // The guides remain visible for the selection tool, but they must not
                    // become a full-canvas hit-test shield. A drawing tool deliberately owns
                    // clicks in the masking workspace; selection leaves canvas navigation to
                    // the preview surface (including double-click zoom).
                    .allowsHitTesting(maskingState.activeTool != .selection)
                }

                if showsMaskOverlay, viewModel.isRetouchCanvasActive, viewModel.sourceSize != .zero {
                    RetouchCanvasOverlay(
                        viewModel: viewModel, state: retouchState, sourceSize: viewModel.sourceSize,
                        crop: viewModel.document.crop, rotation: viewModel.document.rotation,
                        navigation: canvasState.navigation, backingScale: maskOverlayBackingScale
                    )
                }

                if showsMaskOverlay, viewModel.isWhiteBalanceSampling,
                    let point = viewModel.whiteBalanceSamplerPoint,
                    let image = viewModel.whiteBalanceLoupeImage
                {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .interpolation(.none)
                        .frame(width: 132, height: 132)
                        .clipShape(Circle())
                        .overlay { Circle().strokeBorder(.white, lineWidth: 2) }
                        .overlay {
                            Image(systemName: "plus")
                                .font(.system(size: 18, weight: .regular))
                                .foregroundStyle(.white)
                                .shadow(color: .black.opacity(0.8), radius: 2)
                        }
                        .shadow(radius: 5)
                        .allowsHitTesting(false)
                        .position(
                            x: min(max(point.x + 78, 72), geometry.size.width - 72),
                            y: min(max(point.y - 78, 72), geometry.size.height - 72)
                        )
                        .accessibilityLabel("White balance sampling loupe")
                }
            }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 48, weight: .thin))
                .foregroundColor(.secondary.opacity(0.5))

            Text("Drop an image or folder here")
                .font(.title3)
                .foregroundColor(.secondary)

            Text("⌘O open  \u{2022}  ⌘⇧I import from Photos  \u{2022}  ⌘⌥I source folder")
                .font(.caption)
                .foregroundColor(Color(nsColor: .tertiaryLabelColor))

            HStack {
                Button("Import photos…") { viewModel.openImageDialog() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!viewModel.canImportIntoPortableLibrary)
                Button("Import from Photos…") { viewModel.importFromPhotos() }
                    .buttonStyle(.bordered)
                    .disabled(!viewModel.canImportIntoPortableLibrary)
            }
        }
    }

}

/// A quiet, film-contact-sheet-style readout that stays presentation-only over the canvas.
private struct CaptureMetadataOverlay: View {
    let rows: [ImageMetadata.Row]

    var body: some View {
        HStack(spacing: 11) {
            ForEach(rows) { row in
                if row.id != rows.first?.id {
                    Rectangle()
                        .fill(.white.opacity(0.28))
                        .frame(width: 1, height: 23)
                        .accessibilityHidden(true)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(row.label.uppercased())
                        .font(.system(size: 8, weight: .semibold, design: .monospaced))
                        .tracking(0.8)
                        .foregroundStyle(.white.opacity(0.68))
                    Text(row.value)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
        .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 5))
        .overlay {
            RoundedRectangle(cornerRadius: 5)
                .strokeBorder(.white.opacity(0.22), lineWidth: 0.75)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Capture information")
        .accessibilityValue(rows.map { "\($0.label) \($0.value)" }.joined(separator: ", "))
    }
}

struct ComparisonBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
            .foregroundColor(.primary)
    }
}

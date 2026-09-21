import SwiftUI

/// Main image preview area. Supports side-by-side (original vs Look)
/// and single-image mode. Hold Space to flash original in single mode.
struct PreviewView: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject var canvasState: CanvasInteractionState
    // The preview image is owned by a separate observation boundary. Keep observing it even while
    // the spinner is on screen; otherwise a completed replacement render can sit in the surface
    // until an unrelated AppViewModel change causes this view to rebuild.
    @ObservedObject private var previewSurface: PreviewSurface
    @ObservedObject private var originalPreviewSurface: PreviewSurface
    @State private var isDropTargeted = false
    @ObservedObject private var maskingState: MaskInteractionState

    init(viewModel: AppViewModel) {
        _viewModel = ObservedObject(wrappedValue: viewModel)
        _canvasState = ObservedObject(wrappedValue: viewModel.canvasState)
        _previewSurface = ObservedObject(wrappedValue: viewModel.previewSurface)
        _originalPreviewSurface = ObservedObject(wrappedValue: viewModel.originalPreviewSurface)
        _maskingState = ObservedObject(wrappedValue: viewModel.maskInteractionState)
    }

    private var maskOverlayBackingScale: CGFloat {
        NSScreen.main?.backingScaleFactor ?? 2
    }

    /// The editor canvas is deliberately distinct from the source browser's `.bar` material.
    /// The Metal surface resolves the same token for its letterbox; see `PreviewSurfaceView`.
    private var bgColor: Color { KromoraTheme.canvasBackground }

    var body: some View {
        ZStack {
            bgColor

            if previewSurface.image != nil {
                if canvasState.isCropToolActive {
                    singleView
                } else if viewModel.isSideBySideVisible {
                    sideBySideView
                } else {
                    singleView
                }
            } else if viewModel.isLoading || viewModel.previewState == .loading {
                ProgressView()
                    .scaleEffect(1.5)
                    .progressViewStyle(.circular)
            } else if viewModel.previewState == .failed {
                failedState
            } else {
                emptyState
            }

            if previewSurface.image != nil,
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
        }
        .onDrop(
            of: ImageDrop.acceptedTypes,
            delegate: ImageDropDelegate(viewModel: viewModel, isTargeted: $isDropTargeted)
        )
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
                    width: geo.size.width / 2
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
                    width: geo.size.width / 2
                )
            }
        }
        .padding(8)
    }

    private func panelView(
        surface: PreviewSurface, label: String, accessibilityLabel: String,
        labelSide: HorizontalAlignment, width: CGFloat
    ) -> some View {
        ZStack(alignment: labelSide == .leading ? .topLeading : .topTrailing) {
            bgColor

            if surface.image != nil {
                canvasSurface(surface)
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
                        canvasSurface(previewSurface)
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
            .animation(.easeInOut(duration: 0.2), value: canvasState.isCropToolActive)
            // The GPU preview request changes orientation at the same time as the draft frame is
            // remapped. Animating this narrow crop subtree keeps the frame/layout transition
            // readable without forcing a full-resolution render for intermediate angles.
            .animation(.snappy(duration: 0.3, extraBounce: 0.04), value: canvasState.cropRotation)
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
    private func canvasSurface(_ surface: PreviewSurface) -> some View {
        GeometryReader { _ in
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
                onDrawableSizeChange: { size in viewModel.updatePreviewBackingSize(size) },
                viewSpaceRotationAngle: canvasState.isCropToolActive
                    ? canvasState.cropStraightenAngle : 0,
                ignoresHits: canvasState.isCropToolActive
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            ZStack {
                if canvasState.isCropToolActive {
                    preview.allowsHitTesting(false)
                } else {
                    preview
                }

                if viewModel.isMaskingWorkspaceActive,
                    maskingState.showOverlay, viewModel.sourceSize != .zero,
                    maskingState.selectedLayerID != nil || maskingState.hasDraft
                        || maskingState.activeTool == .linear || maskingState.activeTool == .radial
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
        }
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

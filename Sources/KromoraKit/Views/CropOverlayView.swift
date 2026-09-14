import CoreGraphics
import SwiftUI

/// Crop Apply/Reset/Cancel chrome. Lives above the canvas in `PreviewView` so it reserves
/// height and cannot cover the top handles or steal their hits.
struct CropToolbarView: View {
    let aspectRatio: CropAspectRatio
    let orientation: CropAspectRatioOrientation
    let onAspectRatioChange: (CropAspectRatio, CropAspectRatioOrientation) -> Void
    let onApply: () -> Void
    let onReset: () -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text("Crop")
                .font(.headline)
            Menu {
                ForEach(CropAspectRatio.allCases, id: \.self) { ratio in
                    if ratio.supportsOrientationSelection {
                        Menu(ratio.label) {
                            ratioButton(ratio, orientation: .landscape)
                            ratioButton(ratio, orientation: .portrait)
                        }
                    } else {
                        Button {
                            onAspectRatioChange(ratio, .automatic)
                        } label: {
                            if ratio == aspectRatio && orientation == .automatic {
                                Label(ratio.label, systemImage: "checkmark")
                            } else {
                                Text(ratio.label)
                            }
                        }
                    }
                }
            } label: {
                Label(
                    aspectRatio.selectionLabel(for: orientation), systemImage: "aspectratio"
                )
            }
            .accessibilityLabel("Crop aspect ratio")
            .accessibilityHint(
                "Choose a square, freeform, landscape, or portrait crop ratio")
            Spacer()
            Button("Reset", action: onReset)
            Button("Cancel", action: onCancel)
            Button("Apply", action: onApply)
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Crop, \(aspectRatio.label)")
        .accessibilityHint(
            "Choose an aspect ratio, then drag the crop frame or handles within the image bounds"
        )
        .onExitCommand(perform: onCancel)
    }

    @ViewBuilder
    private func ratioButton(
        _ ratio: CropAspectRatio, orientation: CropAspectRatioOrientation
    ) -> some View {
        Button {
            onAspectRatioChange(ratio, orientation)
        } label: {
            if ratio == aspectRatio && self.orientation == orientation {
                Label(ratio.selectionLabel(for: orientation), systemImage: "checkmark")
            } else {
                Text(ratio.selectionLabel(for: orientation))
            }
        }
    }
}

/// Coordinates are converted to the normalized bottom-left model space before they reach
/// AppViewModel. Ratio geometry lives in `CropOverlayInteraction` so it is shared with model tests.
/// Crop chrome is `CropToolbarView` in `PreviewView`, not this overlay, so the top handles stay
/// reachable when the crop is the full image.
struct CropOverlayView: View {
    typealias Handle = CropHandle

    // Internal (not private) so CropOverlayViewTests can verify the hit-target geometry that
    // fixed KRMA-387 without a UI test harness.
    let handleHitTargetSize: CGFloat = CropOverlayInteraction.handleHitTargetSize

    let normalizedRect: CGRect
    let imageSize: CGSize
    let aspectRatio: CropAspectRatio
    let orientation: CropAspectRatioOrientation
    let onChange: (CGRect) -> Void

    @State private var dragSession: DragSession?

    var body: some View {
        GeometryReader { geometry in
            let bounds = CGRect(origin: .zero, size: geometry.size)
            let imageRect = fittedImageRect(in: geometry.size)
            let cropRect = screenRect(for: normalizedRect, in: imageRect)

            ZStack {
                dimmedOutside(cropRect: cropRect, in: geometry.size)

                cropGuides(cropRect: cropRect)
                    .accessibilityLabel("Crop frame")
                    .accessibilityHint("Drag to move the crop frame without changing its size")

                ForEach(Handle.allCases, id: \.self) { handle in
                    Circle()
                        .fill(Color.white)
                        .overlay(Circle().stroke(Color.accentColor, lineWidth: 2))
                        .frame(width: 18, height: 18)
                        .position(handlePosition(handle, in: cropRect))
                        .allowsHitTesting(false)
                        .accessibilityLabel("Crop \(handle.label) handle")
                        .accessibilityHint("Drag to resize the crop")
                }

                // One overlay-wide gesture classifies the press. Separate handle views using
                // `.position()` at the overlay origin do not reliably receive macOS hits, and the
                // interior move gesture then wins. For a full-image crop that move is clamped, so
                // the top-left handle appears dead.
                Rectangle()
                    .fill(Color.primary.opacity(0.001))
                    .contentShape(Rectangle())
                    .highPriorityGesture(
                        pointerGesture(
                            imageRect: imageRect, cropRect: cropRect, bounds: bounds)
                    )
                    .accessibilityHidden(true)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Crop overlay")
        }
    }

    private struct DragSession {
        var hit: CropOverlayHit
        var startRect: CGRect
    }

    private func pointerGesture(
        imageRect: CGRect, cropRect: CGRect, bounds: CGRect
    ) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let session: DragSession
                if let dragSession {
                    session = dragSession
                } else if let hit = CropOverlayInteraction.hit(
                    at: value.startLocation, cropRect: cropRect, bounds: bounds
                ) {
                    session = DragSession(hit: hit, startRect: normalizedRect)
                    dragSession = session
                } else {
                    return
                }

                switch session.hit {
                case .move:
                    onChange(
                        CropOverlayInteraction.translated(
                            session.startRect, delta: value.translation, imageRect: imageRect
                        ))
                case .resize(let handle):
                    onChange(
                        CropOverlayInteraction.resized(
                            session.startRect, handle: handle, delta: value.translation,
                            imageRect: imageRect, aspectRatio: aspectRatio,
                            orientation: orientation, imageSize: imageSize
                        ))
                }
            }
            .onEnded { _ in dragSession = nil }
    }

    private func fittedImageRect(in viewport: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0,
            viewport.width > 0, viewport.height > 0
        else { return .zero }
        let scale = min(viewport.width / imageSize.width, viewport.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: (viewport.width - size.width) / 2,
            y: (viewport.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
    }

    private func screenRect(for rect: CGRect, in imageRect: CGRect) -> CGRect {
        CGRect(
            x: imageRect.minX + rect.minX * imageRect.width,
            y: imageRect.minY + (1 - rect.maxY) * imageRect.height,
            width: rect.width * imageRect.width,
            height: rect.height * imageRect.height
        )
    }

    private func dimmedOutside(cropRect: CGRect, in size: CGSize) -> some View {
        Canvas { context, _ in
            var path = Path()
            path.addRect(CGRect(origin: .zero, size: size))
            path.addRect(cropRect)
            context.fill(path, with: .color(.black.opacity(0.5)), style: FillStyle(eoFill: true))
        }
        .allowsHitTesting(false)
    }

    private func cropGuides(cropRect: CGRect) -> some View {
        ZStack {
            Rectangle()
                .stroke(Color.white, lineWidth: 2)
            Path { path in
                path.move(to: CGPoint(x: cropRect.width / 3, y: 0))
                path.addLine(to: CGPoint(x: cropRect.width / 3, y: cropRect.height))
                path.move(to: CGPoint(x: cropRect.width * 2 / 3, y: 0))
                path.addLine(to: CGPoint(x: cropRect.width * 2 / 3, y: cropRect.height))
                path.move(to: CGPoint(x: 0, y: cropRect.height / 3))
                path.addLine(to: CGPoint(x: cropRect.width, y: cropRect.height / 3))
                path.move(to: CGPoint(x: 0, y: cropRect.height * 2 / 3))
                path.addLine(to: CGPoint(x: cropRect.width, y: cropRect.height * 2 / 3))
            }
            .stroke(Color.white.opacity(0.6), lineWidth: 1)
        }
        .frame(width: cropRect.width, height: cropRect.height)
        .position(x: cropRect.midX, y: cropRect.midY)
    }

    private func handlePosition(_ handle: Handle, in rect: CGRect) -> CGPoint {
        switch handle {
        case .topLeading: return CGPoint(x: rect.minX, y: rect.minY)
        case .topTrailing: return CGPoint(x: rect.maxX, y: rect.minY)
        case .bottomLeading: return CGPoint(x: rect.minX, y: rect.maxY)
        case .bottomTrailing: return CGPoint(x: rect.maxX, y: rect.maxY)
        }
    }

    // Internal (not private) so CropOverlayViewTests can verify the hit-target geometry that
    // fixed KRMA-387 without a UI test harness.
    func handleHitPosition(_ handle: Handle, in rect: CGRect) -> CGPoint {
        let inset = min(handleHitTargetSize / 2, min(rect.width, rect.height) / 2)
        switch handle {
        case .topLeading: return CGPoint(x: rect.minX + inset, y: rect.minY + inset)
        case .topTrailing: return CGPoint(x: rect.maxX - inset, y: rect.minY + inset)
        case .bottomLeading: return CGPoint(x: rect.minX + inset, y: rect.maxY - inset)
        case .bottomTrailing: return CGPoint(x: rect.maxX - inset, y: rect.maxY - inset)
        }
    }
}

extension CropHandle {
    fileprivate var label: String {
        switch self {
        case .topLeading: return "top left"
        case .topTrailing: return "top right"
        case .bottomLeading: return "bottom left"
        case .bottomTrailing: return "bottom right"
        }
    }
}

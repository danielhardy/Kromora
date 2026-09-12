import CoreGraphics
import SwiftUI

/// Coordinates are converted to the normalized bottom-left model space before they reach
/// AppViewModel. Ratio geometry lives in `CropOverlayInteraction` so it is shared with model tests.
struct CropOverlayView: View {
    typealias Handle = CropHandle

    private let handleHitTargetSize: CGFloat = 44

    let normalizedRect: CGRect
    let imageSize: CGSize
    let aspectRatio: CropAspectRatio
    let orientation: CropAspectRatioOrientation
    let onChange: (CGRect) -> Void
    let onAspectRatioChange: (CropAspectRatio, CropAspectRatioOrientation) -> Void
    let onApply: () -> Void
    let onReset: () -> Void
    let onCancel: () -> Void

    @State private var moveStart: CGRect?
    @State private var handleStarts: [Handle: CGRect] = [:]

    var body: some View {
        GeometryReader { geometry in
            let imageRect = fittedImageRect(in: geometry.size)
            let cropRect = screenRect(for: normalizedRect, in: imageRect)

            ZStack(alignment: .top) {
                dimmedOutside(cropRect: cropRect, in: geometry.size)

                Rectangle()
                    .fill(.clear)
                    .frame(width: cropRect.width, height: cropRect.height)
                    .position(x: cropRect.midX, y: cropRect.midY)
                    // Leave the handle hit zones out of the move surface so a corner drag is
                    // always owned by its handle, even when the frame is small.
                    .contentShape(Rectangle().inset(by: 14))
                    .gesture(moveGesture(imageRect: imageRect))
                    .accessibilityLabel("Crop frame")
                    .accessibilityHint("Drag to move the crop frame without changing its size")

                cropGuides(cropRect: cropRect)
                    .allowsHitTesting(false)

                ForEach(Handle.allCases, id: \.self) { handle in
                    Circle()
                        .fill(Color.white)
                        .overlay(Circle().stroke(Color.accentColor, lineWidth: 2))
                        .frame(width: 18, height: 18)
                        .position(handlePosition(handle, in: cropRect))
                        .allowsHitTesting(false)
                }

                // Keep the hit target inside the image when a crop corner is on the overlay
                // boundary. In particular, the top-left handle otherwise has most of its hit
                // area outside the GeometryReader and can also sit beneath the top controls.
                ForEach(Handle.allCases, id: \.self) { handle in
                    Rectangle()
                        .fill(.clear)
                        .frame(width: handleHitTargetSize, height: handleHitTargetSize)
                        .position(handleHitPosition(handle, in: cropRect))
                        .contentShape(Rectangle())
                        .gesture(handleGesture(handle, imageRect: imageRect))
                        .accessibilityLabel("Crop \(handle.label) handle")
                        .accessibilityHint("Drag to resize the crop")
                        .zIndex(1)
                }

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
                .padding(12)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Crop, \(aspectRatio.label)")
            .accessibilityHint(
                "Choose an aspect ratio, then drag the crop frame or handles within the image bounds"
            )
            .onExitCommand(perform: onCancel)
        }
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

    private func handleHitPosition(_ handle: Handle, in rect: CGRect) -> CGPoint {
        let inset = min(handleHitTargetSize / 2, min(rect.width, rect.height) / 2)
        switch handle {
        case .topLeading: return CGPoint(x: rect.minX + inset, y: rect.minY + inset)
        case .topTrailing: return CGPoint(x: rect.maxX - inset, y: rect.minY + inset)
        case .bottomLeading: return CGPoint(x: rect.minX + inset, y: rect.maxY - inset)
        case .bottomTrailing: return CGPoint(x: rect.maxX - inset, y: rect.maxY - inset)
        }
    }

    private func moveGesture(imageRect: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let start = moveStart ?? normalizedRect
                moveStart = start
                onChange(
                    CropOverlayInteraction.translated(
                        start, delta: value.translation, imageRect: imageRect
                    ))
            }
            .onEnded { _ in moveStart = nil }
    }

    private func handleGesture(_ handle: Handle, imageRect: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let start = handleStarts[handle] ?? normalizedRect
                handleStarts[handle] = start
                onChange(
                    CropOverlayInteraction.resized(
                        start, handle: handle, delta: value.translation, imageRect: imageRect,
                        aspectRatio: aspectRatio, orientation: orientation, imageSize: imageSize
                    ))
            }
            .onEnded { _ in handleStarts[handle] = nil }
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

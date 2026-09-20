import SwiftUI

/// The framing controls for the dedicated Crop workspace. Crop owns the inspector while it is
/// active, so none of the ordinary Edit tabs remain reachable behind the draft.
struct CropInspectorView: View {
    let aspectRatio: CropAspectRatio
    let orientation: CropAspectRatioOrientation
    let onRotateCounterClockwise: () -> Void
    let onRotateClockwise: () -> Void
    let onAspectRatioChange: (CropAspectRatio, CropAspectRatioOrientation) -> Void
    let onReset: () -> Void
    let onCancel: () -> Void
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Crop")
                .font(.title3.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    aspectSection
                    rotationSection

                    Divider()

                    Button("Reset", action: onReset)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityHint("Return the crop frame to the full image")
                }
                .padding(16)
            }

            Divider()

            HStack(spacing: 8) {
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Done", action: onDone)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(16)
        }
        .background(KromoraTheme.windowBackground)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Crop inspector")
        .onExitCommand(perform: onCancel)
    }

    private var aspectSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Aspect")
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
                    aspectRatio.selectionLabel(for: orientation),
                    systemImage: "aspectratio"
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityLabel("Crop aspect ratio")
            .accessibilityHint("Choose a square, freeform, landscape, or portrait crop ratio")
            .menuStyle(.borderlessButton)
        }
    }

    private var rotationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Rotate")
                .font(.headline)

            HStack(spacing: 8) {
                Button(action: onRotateCounterClockwise) {
                    Label("Rotate counterclockwise", systemImage: "rotate.left")
                        .labelStyle(.titleAndIcon)
                }
                .help("Rotate 90° counterclockwise")
                .accessibilityLabel("Rotate 90 degrees counterclockwise")

                Button(action: onRotateClockwise) {
                    Label("Rotate clockwise", systemImage: "rotate.right")
                        .labelStyle(.titleAndIcon)
                }
                .help("Rotate 90° clockwise")
                .accessibilityLabel("Rotate 90 degrees clockwise")
            }
        }
    }

    @ViewBuilder
    private func ratioButton(
        _ ratio: CropAspectRatio,
        orientation: CropAspectRatioOrientation
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

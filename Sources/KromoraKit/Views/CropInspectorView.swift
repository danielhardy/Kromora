import AppKit
import SwiftUI

/// The framing controls for the dedicated Crop workspace. Crop owns the inspector while it is
/// active, so none of the ordinary Edit tabs remain reachable behind the draft.
struct CropInspectorView: View {
    let aspectRatio: CropAspectRatio
    let orientation: CropAspectRatioOrientation
    let imageSize: CGSize
    let straightenAngle: Double
    let flipHorizontal: Bool
    let flipVertical: Bool
    let verticalPerspective: Double
    let horizontalPerspective: Double
    let onRotateCounterClockwise: () -> Void
    let onRotateClockwise: () -> Void
    let onBeginInteraction: () -> Void
    let onEndInteraction: () -> Void
    let onStraightenChange: (Double) -> Void
    let onFlipHorizontal: () -> Void
    let onFlipVertical: () -> Void
    let onVerticalPerspectiveChange: (Double) -> Void
    let onHorizontalPerspectiveChange: (Double) -> Void
    let onAuto: () -> Void
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
                    rotationAndFlipSection
                    straightenSection
                    perspectiveSection

                    Divider()

                    Button("Reset", action: onReset)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityHint("Return the crop frame to the full image")

                    Button(action: onAuto) {
                        Label("Auto", systemImage: "wand.and.stars")
                    }
                    .accessibilityHint(
                        "Suggest a horizon straighten when reliable evidence is available")
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
                ForEach(aspectOptions, id: \.self) { ratio in
                    Button {
                        selectAspect(ratio)
                    } label: {
                        if ratio == aspectRatio {
                            Label(ratio.label, systemImage: "checkmark")
                        } else {
                            Text(ratio.label)
                        }
                    }
                }
            } label: {
                Label(displayedAspectLabel, systemImage: "aspectratio")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .menuStyle(.borderlessButton)
            .accessibilityLabel("Crop aspect ratio")
            .accessibilityValue(displayedAspectLabel)
            .accessibilityHint("Choose the crop frame ratio")

            if aspectRatio.supportsOrientationSelection {
                HStack(spacing: 8) {
                    orientationButton(
                        "Landscape",
                        systemImage: landscapeOrientationSystemImage,
                        isSelected: effectiveOrientation == .landscape,
                        action: { onAspectRatioChange(aspectRatio, .landscape) }
                    )
                    orientationButton(
                        "Portrait",
                        systemImage: portraitOrientationSystemImage,
                        rotation: portraitOrientationSymbolRotation,
                        isSelected: effectiveOrientation == .portrait,
                        action: { onAspectRatioChange(aspectRatio, .portrait) }
                    )
                }
                .accessibilityLabel("Crop orientation")
                .accessibilityValue(effectiveOrientation == .landscape ? "Landscape" : "Portrait")
                .accessibilityHint("Choose the orientation of the crop frame")
            }
        }
    }

    /// The current selection's label, tracking the effective orientation so the shown ratio
    /// (e.g. "5:4" vs "4:5") always matches the frame that results — otherwise the header
    /// would keep showing the raw preset name regardless of which orientation is active.
    private var displayedAspectLabel: String {
        aspectRatio.supportsOrientationSelection
            ? aspectRatio.shapeLabel(for: effectiveOrientation)
            : aspectRatio.label
    }

    private var aspectOptions: [CropAspectRatio] {
        [
            .original, .freeform, .square, .sixteenToNine, .fourToThree, .threeToTwo,
            .fiveToSeven, .fourToFive, .threeToFive, .custom,
        ]
    }

    private func selectAspect(_ ratio: CropAspectRatio) {
        let nextOrientation =
            ratio.supportsOrientationSelection
            ? effectiveOrientation
            : .automatic
        onAspectRatioChange(ratio, nextOrientation)
    }

    private var landscapeOrientationSystemImage: String {
        Self.isSystemImageAvailable("rectangle.landscape") ? "rectangle.landscape" : "rectangle"
    }

    private var portraitOrientationSystemImage: String {
        Self.isSystemImageAvailable("rectangle.portrait") ? "rectangle.portrait" : "rectangle"
    }

    private var portraitOrientationSymbolRotation: Angle {
        Self.isSystemImageAvailable("rectangle.portrait") ? .zero : .degrees(90)
    }

    /// Legacy documents can use automatic orientation. Resolve that state for the control from
    /// the same normalized geometry used by the crop overlay so the icon matches the frame.
    private var effectiveOrientation: CropAspectRatioOrientation {
        guard orientation == .automatic else { return orientation }
        guard imageSize.width > 0, imageSize.height > 0,
            let normalized = aspectRatio.normalizedRatio(for: imageSize),
            normalized.isFinite
        else { return .landscape }
        let pixelRatio = normalized * imageSize.width / imageSize.height
        return pixelRatio >= 1 ? .landscape : .portrait
    }

    private var rotationAndFlipSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Rotate and Flip")
                .font(.headline)

            HStack(spacing: 8) {
                transformButton(
                    "Rotate 90 degrees counterclockwise",
                    systemImage: "rotate.left",
                    help: "Rotate 90 degrees counterclockwise",
                    action: onRotateCounterClockwise
                )
                transformButton(
                    "Rotate 90 degrees clockwise",
                    systemImage: "rotate.right",
                    help: "Rotate 90 degrees clockwise",
                    action: onRotateClockwise
                )
                flipButton(
                    "Flip horizontal",
                    systemImage: flipHorizontalSystemImage,
                    help: "Flip horizontally",
                    isOn: flipHorizontal,
                    action: onFlipHorizontal
                )
                flipButton(
                    "Flip vertical",
                    systemImage: flipVerticalSystemImage,
                    rotation: flipVerticalSymbolUsesRotation ? .degrees(90) : .zero,
                    help: "Flip vertically",
                    isOn: flipVertical,
                    action: onFlipVertical
                )
            }
        }
    }

    private var flipHorizontalSystemImage: String {
        Self.isSystemImageAvailable("flip.horizontal") ? "flip.horizontal" : "arrow.left.and.right"
    }

    private var flipVerticalSystemImage: String {
        Self.isSystemImageAvailable("flip.horizontal") ? "flip.horizontal" : "arrow.up.and.down"
    }

    private var flipVerticalSymbolUsesRotation: Bool {
        Self.isSystemImageAvailable("flip.horizontal")
    }

    private static func isSystemImageAvailable(_ name: String) -> Bool {
        NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil
    }

    private func orientationButton(
        _ title: String,
        systemImage: String,
        rotation: Angle = .zero,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .rotationEffect(rotation)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(.bordered)
        .frame(width: 32, height: 32)
        .contentShape(Rectangle())
        .help(title)
        .accessibilityLabel(title)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .tint(isSelected ? .accentColor : .secondary)
    }

    private var straightenSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Straighten")
                    .font(.headline)
                Spacer()
                Text("\(straightenAngle, specifier: "%.1f")°")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(
                value: Binding(
                    get: { straightenAngle },
                    set: { value in onStraightenChange(value) }
                ),
                in: -45...45,
                step: 0.1,
                onEditingChanged: { editing in
                    if editing { onBeginInteraction() } else { onEndInteraction() }
                }
            )
            .accessibilityLabel("Straighten angle")
            .accessibilityValue("\(straightenAngle, specifier: "%.1f") degrees")
        }
    }

    private var perspectiveSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Perspective")
                .font(.headline)
            perspectiveSlider(
                title: "Vertical",
                value: verticalPerspective,
                onChange: onVerticalPerspectiveChange,
                onBeginInteraction: onBeginInteraction,
                onEndInteraction: onEndInteraction
            )
            perspectiveSlider(
                title: "Horizontal",
                value: horizontalPerspective,
                onChange: onHorizontalPerspectiveChange,
                onBeginInteraction: onBeginInteraction,
                onEndInteraction: onEndInteraction
            )
        }
    }

    private func perspectiveSlider(
        title: String,
        value: Double,
        onChange: @escaping (Double) -> Void,
        onBeginInteraction: @escaping () -> Void,
        onEndInteraction: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text("\(value * 100, specifier: "%.0f")%")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(
                value: Binding(get: { value }, set: onChange),
                in: -CropAdjustments.maximumPerspective...CropAdjustments.maximumPerspective,
                step: 0.01,
                onEditingChanged: { editing in
                    if editing { onBeginInteraction() } else { onEndInteraction() }
                }
            )
            .accessibilityLabel("\(title) perspective")
            .accessibilityValue("\(value * 100, specifier: "%.0f") percent")
        }
    }

    private func flipButton(
        _ title: String,
        systemImage: String,
        rotation: Angle = .zero,
        help: String,
        isOn: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label {
                Text(title)
            } icon: {
                Image(systemName: systemImage)
                    .rotationEffect(rotation)
            }
        }
        .buttonStyle(.bordered)
        .labelStyle(.iconOnly)
        .frame(width: 32, height: 32)
        .contentShape(Rectangle())
        .help(help)
        .accessibilityLabel(title)
        .tint(isOn ? .accentColor : nil)
        .accessibilityValue(isOn ? "On" : "Off")
    }

    private func transformButton(
        _ title: String,
        systemImage: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
        }
        .buttonStyle(.bordered)
        .frame(width: 32, height: 32)
        .contentShape(Rectangle())
        .help(help)
        .accessibilityLabel(title)
    }

}

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
                    rotationSection
                    straightenSection
                    flipSection
                    perspectiveSection

                    Divider()

                    Button("Reset", action: onReset)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityHint("Return the crop frame to the full image")

                    Button(action: onAuto) {
                        Label("Auto", systemImage: "wand.and.stars")
                    }
                    .accessibilityHint("Suggest a horizon straighten when reliable evidence is available")
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

            Picker(selection: aspectSelection) {
                ForEach(aspectOptions, id: \.self) { ratio in
                    Text(ratio.label).tag(ratio)
                }
            } label: {
                Label(aspectRatio.label, systemImage: "aspectratio")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .pickerStyle(.menu)
            .accessibilityLabel("Crop aspect ratio")
            .accessibilityValue(aspectRatio.label)
            .accessibilityHint("Choose the crop frame ratio")

            if aspectRatio.supportsOrientationSelection {
                Picker("Crop orientation", selection: orientationSelection) {
                    Label("Landscape", systemImage: "rectangle.landscape")
                        .labelStyle(.iconOnly)
                        .accessibilityLabel("Landscape")
                        .tag(CropAspectRatioOrientation.landscape)
                    Label("Portrait", systemImage: "rectangle.portrait")
                        .labelStyle(.iconOnly)
                        .accessibilityLabel("Portrait")
                        .tag(CropAspectRatioOrientation.portrait)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
                .accessibilityLabel("Crop orientation")
                .accessibilityValue(effectiveOrientation == .landscape ? "Landscape" : "Portrait")
                .accessibilityHint("Choose the orientation of the crop frame")
            }
        }
    }

    private var aspectOptions: [CropAspectRatio] {
        [.original, .freeform, .square, .sixteenToNine, .fourToThree, .threeToTwo,
         .fiveToSeven, .fourToFive, .threeToFive, .custom]
    }

    private var aspectSelection: Binding<CropAspectRatio> {
        Binding(
            get: { aspectRatio },
            set: { ratio in
                let nextOrientation = ratio.supportsOrientationSelection
                    ? effectiveOrientation
                    : .automatic
                onAspectRatioChange(ratio, nextOrientation)
            }
        )
    }

    private var orientationSelection: Binding<CropAspectRatioOrientation> {
        Binding(
            get: { effectiveOrientation },
            set: { orientation in onAspectRatioChange(aspectRatio, orientation) }
        )
    }

    /// Legacy documents can use automatic orientation. Resolve that state for the control from
    /// the same normalized geometry used by the crop overlay so the icon matches the frame.
    private var effectiveOrientation: CropAspectRatioOrientation {
        guard orientation == .automatic else { return orientation }
        guard imageSize.width > 0, imageSize.height > 0,
              let normalized = aspectRatio.normalizedRatio(for: imageSize),
              normalized.isFinite else { return .landscape }
        let pixelRatio = normalized * imageSize.width / imageSize.height
        return pixelRatio >= 1 ? .landscape : .portrait
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
                step: 0.1
            )
            .accessibilityLabel("Straighten angle")
            .accessibilityValue("\(straightenAngle, specifier: "%.1f") degrees")
        }
    }

    private var flipSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Flip")
                .font(.headline)
            HStack(spacing: 8) {
                flipButton("Flip horizontal", systemImage: "arrow.left.and.right", isOn: flipHorizontal,
                           action: onFlipHorizontal)
                flipButton("Flip vertical", systemImage: "arrow.up.and.down", isOn: flipVertical,
                           action: onFlipVertical)
            }
        }
    }

    private var perspectiveSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Perspective")
                .font(.headline)
            perspectiveSlider(
                title: "Vertical",
                value: verticalPerspective,
                onChange: onVerticalPerspectiveChange
            )
            perspectiveSlider(
                title: "Horizontal",
                value: horizontalPerspective,
                onChange: onHorizontalPerspectiveChange
            )
        }
    }

    private func perspectiveSlider(
        title: String,
        value: Double,
        onChange: @escaping (Double) -> Void
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
                step: 0.01
            )
            .accessibilityLabel("\(title) perspective")
            .accessibilityValue("\(value * 100, specifier: "%.0f") percent")
        }
    }

    private func flipButton(
        _ title: String, systemImage: String, isOn: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.titleAndIcon)
        }
        .buttonStyle(.bordered)
        .tint(isOn ? .accentColor : nil)
        .accessibilityValue(isOn ? "On" : "Off")
    }

}

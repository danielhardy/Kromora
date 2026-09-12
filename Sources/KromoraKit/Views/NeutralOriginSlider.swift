import AppKit
import SwiftUI

/// A slider whose filled track starts at the control's neutral value rather than at the left edge.
///
/// `SwiftUI.Slider` on macOS always fills from the minimum, so a bipolar control sitting on its
/// neutral — Exposure 0 in −5…5, Contrast 0 in −100…100 — draws as half-adjusted while applying
/// nothing. There is no public `SliderStyle` to correct that with, and faking it by overlaying a
/// SwiftUI shape on a stock `Slider` means guessing at the knob inset and bar height. So this wraps
/// `NSSlider` and overrides the single cell method that draws the bar, where the geometry is
/// available rather than assumed (`knobRect(flipped:)`).
///
/// **Only the bar drawing is ours.** The knob, hit-testing and drag tracking, arrow- and page-key
/// handling, and the native slider accessibility element all stay AppKit's, which is what keeps the
/// interaction identical to the `Slider` this replaces.
///
/// Unipolar controls — a brush size, a Look intensity, a mask amount — pass `neutral:
/// range.lowerBound` and get the familiar left-origin fill out of the same code path. See
/// `SliderFill.span(value:neutral:in:)`.
struct NeutralOriginSlider: NSViewRepresentable {
    @Binding private var value: Double
    private let range: ClosedRange<Double>
    private let neutral: Double
    private let trackStyle: SliderTrackStyle
    private let accessibilityTitle: String?
    private let accessibilityReadout: String?
    private let onEditingChanged: (Bool) -> Void

    /// - Parameters:
    ///   - neutral: The value at which this control does nothing, **in slider space** — the same
    ///     space `value` and `range` are in. Pass `range.lowerBound` for a unipolar control.
    ///   - accessibilityTitle: Mirrored onto the `NSSlider` itself, alongside whatever
    ///     `.accessibilityLabel` the caller applies to this view. Belt and braces: a representable's
    ///     SwiftUI accessibility modifiers and the wrapped view's own attributes are two different
    ///     places to set the same thing, and which one VoiceOver reads is not ours to decide.
    init(
        value: Binding<Double>,
        in range: ClosedRange<Double>,
        neutral: Double,
        trackStyle: SliderTrackStyle = .neutral,
        accessibilityTitle: String? = nil,
        accessibilityReadout: String? = nil,
        onEditingChanged: @escaping (Bool) -> Void = { _ in }
    ) {
        self._value = value
        self.range = range
        self.neutral = neutral
        self.trackStyle = trackStyle
        self.accessibilityTitle = accessibilityTitle
        self.accessibilityReadout = accessibilityReadout
        self.onEditingChanged = onEditingChanged
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(value: $value, onEditingChanged: onEditingChanged)
    }

    func makeNSView(context: Context) -> NSSlider {
        let slider = NSSlider()
        let cell = NeutralOriginSliderCell()
        cell.sliderType = .linear
        cell.controlSize = .regular
        slider.cell = cell
        slider.isContinuous = true
        slider.target = context.coordinator
        slider.action = #selector(Coordinator.sliderMoved(_:))
        // NSSlider has no intrinsic width; without this it can win layout arguments against the
        // label and readout sharing its row.
        slider.setContentHuggingPriority(.defaultLow, for: .horizontal)
        slider.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        cell.trackingDidChange = { [weak coordinator = context.coordinator] isTracking in
            coordinator?.trackingChanged(isTracking)
        }
        apply(to: slider, coordinator: context.coordinator)
        return slider
    }

    func updateNSView(_ slider: NSSlider, context: Context) {
        context.coordinator.value = $value
        context.coordinator.onEditingChanged = onEditingChanged
        apply(to: slider, coordinator: context.coordinator)
    }

    private func apply(to slider: NSSlider, coordinator: Coordinator) {
        slider.minValue = range.lowerBound
        slider.maxValue = max(range.upperBound, range.lowerBound)
        (slider.cell as? NeutralOriginSliderCell)?.neutral = neutral
        (slider.cell as? NeutralOriginSliderCell)?.trackStyle = trackStyle

        // Never fight the drag: while the knob is being tracked the slider is the source of truth,
        // and the binding behind it is debounced, so writing back mid-gesture would stutter.
        if !coordinator.isTracking, slider.doubleValue != value {
            slider.doubleValue = value
        }

        if let accessibilityTitle { slider.setAccessibilityLabel(accessibilityTitle) }
        if let accessibilityReadout { slider.setAccessibilityValueDescription(accessibilityReadout) }
        slider.needsDisplay = true
    }

    @MainActor
    final class Coordinator: NSObject {
        var value: Binding<Double>
        var onEditingChanged: (Bool) -> Void
        private(set) var isTracking = false

        init(value: Binding<Double>, onEditingChanged: @escaping (Bool) -> Void) {
            self.value = value
            self.onEditingChanged = onEditingChanged
        }

        @objc func sliderMoved(_ sender: NSSlider) {
            value.wrappedValue = sender.doubleValue
        }

        /// Balanced, because `onEditingChanged(false)` ends a preview interaction: an unpaired end
        /// would drop the preview back to settled quality mid-drag.
        func trackingChanged(_ tracking: Bool) {
            guard tracking != isTracking else { return }
            isTracking = tracking
            onEditingChanged(tracking)
        }
    }
}

/// The colour vocabulary used by photographic slider tracks.
///
/// These are deliberately *descriptions of the adjustment*, rather than the colour of the current
/// image: a slider needs to explain its available direction before it has a pixel to sample. Every
/// ramp spans the entire knob travel and is muted outside the active `SliderFill` span; the neutral
/// marker therefore remains useful at zero/as-shot while either end still advertises its result.
///
/// - `temperature`: cool blue → daylight neutral → amber. This is used for both RAW and local
///   Kelvin controls as well as the standard-image, slider-mapped temperature control.
/// - `tint`: green → neutral → magenta.
/// - `saturation` and `vibrance`: restrained/chroma-reduced → neutral → increasingly vivid. They
///   are intentionally not photo previews; the ramp communicates chroma direction without
///   suggesting that any one hue will be added to an image.
/// - `hue`: the continuous colour wheel, appropriate only where the value itself is an absolute
///   hue. Controls whose effect has no honest colour direction stay `.neutral`.
enum SliderTrackStyle: Equatable, Sendable {
    case neutral
    case temperature
    case tint
    case saturation
    case vibrance
    case hue

    fileprivate var usesGradient: Bool { self != .neutral }

    fileprivate func gradient(neutralFraction: CGFloat) -> NSGradient? {
        func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> NSColor {
            NSColor(calibratedRed: red, green: green, blue: blue, alpha: 1)
        }
        let neutral = min(max(neutralFraction, 0), 1)
        func threePart(_ lower: NSColor, _ middle: NSColor, _ upper: NSColor) -> NSGradient {
            if neutral <= 0 {
                return NSGradient(colors: [middle, upper], atLocations: [0, 1], colorSpace: .deviceRGB)!
            }
            if neutral >= 1 {
                return NSGradient(colors: [lower, middle], atLocations: [0, 1], colorSpace: .deviceRGB)!
            }
            return NSGradient(
                colors: [lower, middle, upper], atLocations: [0, neutral, 1], colorSpace: .deviceRGB
            )!
        }
        func intensity(_ reduced: NSColor, _ middle: NSColor, _ vividFirst: NSColor, _ vividLast: NSColor) -> NSGradient {
            if neutral <= 0 {
                return NSGradient(colors: [middle, vividFirst, vividLast], atLocations: [0, 0.55, 1], colorSpace: .deviceRGB)!
            }
            if neutral >= 1 {
                return NSGradient(colors: [reduced, middle], atLocations: [0, 1], colorSpace: .deviceRGB)!
            }
            let vividStart = neutral + (1 - neutral) * 0.55
            return NSGradient(
                colors: [reduced, middle, vividFirst, vividLast],
                atLocations: [0, neutral, vividStart, 1], colorSpace: .deviceRGB
            )!
        }
        switch self {
        case .neutral:
            return nil
        case .temperature:
            return threePart(color(0.20, 0.48, 0.82), color(0.72, 0.78, 0.82), color(0.96, 0.67, 0.22))
        case .tint:
            return threePart(color(0.25, 0.66, 0.38), color(0.72, 0.76, 0.74), color(0.82, 0.29, 0.63))
        case .saturation:
            return intensity(
                color(0.43, 0.48, 0.52), color(0.55, 0.62, 0.66),
                color(0.17, 0.75, 0.73), color(0.92, 0.43, 0.32)
            )
        case .vibrance:
            return intensity(
                color(0.45, 0.47, 0.52), color(0.60, 0.63, 0.68),
                color(0.28, 0.62, 0.86), color(0.75, 0.35, 0.78)
            )
        case .hue:
            return NSGradient(
                colors: [.systemRed, .systemYellow, .systemGreen, .systemCyan, .systemBlue, .systemPurple, .systemRed],
                atLocations: [0, 1.0 / 6, 2.0 / 6, 3.0 / 6, 4.0 / 6, 5.0 / 6, 1], colorSpace: .deviceRGB
            )
        }
    }
}

/// The one piece of `NeutralOriginSlider` that draws.
///
/// `drawKnob` is deliberately not overridden — the knob stays the system's, so the control still
/// reads as a macOS slider and picks up focus rings and the accent colour for free.
final class NeutralOriginSliderCell: NSSliderCell {
    /// The value the fill is anchored at, in slider space.
    var neutral: Double = 0
    /// The visual explanation of this slider's effect. `.neutral` retains the ordinary adaptive
    /// AppKit treatment for controls where colour would imply a result we cannot honestly show.
    var trackStyle: SliderTrackStyle = .neutral

    /// Called with `true` when a drag starts and `false` when it ends. `NSCell`'s tracking pipeline
    /// rather than the action message, because the action also fires for keyboard changes, which
    /// are not a drag and must not open a preview interaction that nothing closes.
    var trackingDidChange: (@MainActor (Bool) -> Void)?

    /// The drawn bar's thickness. `drawBar(inside:)` is handed a rect taller than the groove for a
    /// regular-size slider; the system bar is a 4pt centred stripe, so ours is too.
    private static let barThickness: CGFloat = 4

    /// How many times AppKit has asked this cell to draw its bar.
    ///
    /// Only `NeutralOriginSliderTests` reads it, and it earns its keep: the whole control rests on
    /// this method still being the one a linear slider's bar goes through, and if a future SDK
    /// stopped calling it every slider would quietly revert to a left-origin fill with no other
    /// symptom.
    private(set) var barDrawCount = 0

    override func drawBar(inside rect: NSRect, flipped: Bool) {
        barDrawCount += 1
        let bar = Self.barRect(in: rect)
        let radius = bar.height / 2
        guard minValue < maxValue else { return }

        // Measure the travel from the knob rather than assuming an inset: the knob centre sits at
        // the bar's left edge plus half a knob at the minimum, and half a knob short of the right
        // edge at the maximum.
        let knobWidth = knobRect(flipped: flipped).width
        let travel = max(bar.width - knobWidth, 0)
        let origin = bar.minX + knobWidth / 2
        let range = minValue...maxValue
        let neutralFraction = CGFloat((neutral - minValue) / (maxValue - minValue))
        let trackRect = NSRect(x: origin, y: bar.minY, width: travel, height: bar.height)

        drawTrack(in: bar, travelRect: trackRect, radius: radius, neutralFraction: neutralFraction)

        let fill = SliderFill.span(value: doubleValue, neutral: neutral, in: range)
        guard !fill.isEmpty else {
            drawNeutralMarker(in: bar, at: origin + travel * neutralFraction)
            return
        }
        let fillRect = NSRect(
            x: origin + travel * fill.start,
            y: bar.minY,
            width: travel * (fill.end - fill.start),
            height: bar.height
        )
        drawActiveFill(in: fillRect, across: trackRect, radius: radius, neutralFraction: neutralFraction)
        drawNeutralMarker(in: bar, at: origin + travel * neutralFraction)
    }

    override func startTracking(at startPoint: NSPoint, in controlView: NSView) -> Bool {
        let started = super.startTracking(at: startPoint, in: controlView)
        if started { trackingDidChange?(true) }
        return started
    }

    override func stopTracking(
        last lastPoint: NSPoint, current stopPoint: NSPoint, in controlView: NSView,
        mouseIsUp flag: Bool
    ) {
        super.stopTracking(
            last: lastPoint, current: stopPoint, in: controlView, mouseIsUp: flag
        )
        trackingDidChange?(false)
    }

    private var fillColor: NSColor {
        isEnabled ? .controlAccentColor : .tertiaryLabelColor
    }

    private var emptyTrackColor: NSColor {
        isEnabled ? .tertiaryLabelColor : .quaternaryLabelColor
    }

    private func drawTrack(
        in bar: NSRect, travelRect: NSRect, radius: CGFloat, neutralFraction: CGFloat
    ) {
        let barPath = NSBezierPath(roundedRect: bar, xRadius: radius, yRadius: radius)
        emptyTrackColor.setFill()
        barPath.fill()
        guard isEnabled, trackStyle.usesGradient,
              let gradient = trackStyle.gradient(neutralFraction: neutralFraction), !travelRect.isEmpty
        else { return }

        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: travelRect, xRadius: radius, yRadius: radius).addClip()
        gradient.draw(from: NSPoint(x: travelRect.minX, y: travelRect.midY),
                      to: NSPoint(x: travelRect.maxX, y: travelRect.midY), options: [])
        // The full range remains visible, while an active span gets the unmuted ramp below.
        emptyTrackColor.withAlphaComponent(0.38).setFill()
        NSBezierPath(rect: travelRect).fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawActiveFill(
        in fillRect: NSRect, across travelRect: NSRect, radius: CGFloat, neutralFraction: CGFloat
    ) {
        guard trackStyle.usesGradient,
              let gradient = trackStyle.gradient(neutralFraction: neutralFraction)
        else {
            fillColor.setFill()
            NSBezierPath(roundedRect: fillRect, xRadius: radius, yRadius: radius).fill()
            return
        }

        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: fillRect, xRadius: radius, yRadius: radius).addClip()
        // Draw from the travel endpoints, not the fill endpoints: the colour at a value has to be
        // the same whether the user reaches it from negative or positive territory.
        gradient.draw(from: NSPoint(x: travelRect.minX, y: travelRect.midY),
                      to: NSPoint(x: travelRect.maxX, y: travelRect.midY), options: [])
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawNeutralMarker(in bar: NSRect, at position: CGFloat) {
        guard neutral > minValue, neutral < maxValue else { return }
        let marker = NSRect(x: position - 0.5, y: bar.minY - 1, width: 1, height: bar.height + 2)
        NSColor.labelColor.withAlphaComponent(isEnabled ? 0.72 : 0.35).setFill()
        NSBezierPath(roundedRect: marker, xRadius: 0.5, yRadius: 0.5).fill()
    }

    private static func barRect(in rect: NSRect) -> NSRect {
        guard rect.height > barThickness else { return rect }
        return NSRect(
            x: rect.minX, y: rect.midY - barThickness / 2,
            width: rect.width, height: barThickness
        )
    }
}

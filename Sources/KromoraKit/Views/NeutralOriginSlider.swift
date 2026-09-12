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
        accessibilityTitle: String? = nil,
        accessibilityReadout: String? = nil,
        onEditingChanged: @escaping (Bool) -> Void = { _ in }
    ) {
        self._value = value
        self.range = range
        self.neutral = neutral
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

/// The one piece of `NeutralOriginSlider` that draws.
///
/// `drawKnob` is deliberately not overridden — the knob stays the system's, so the control still
/// reads as a macOS slider and picks up focus rings and the accent colour for free.
final class NeutralOriginSliderCell: NSSliderCell {
    /// The value the fill is anchored at, in slider space.
    var neutral: Double = 0

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
        emptyTrackColor.setFill()
        NSBezierPath(roundedRect: bar, xRadius: radius, yRadius: radius).fill()

        guard minValue < maxValue else { return }
        let fill = SliderFill.span(
            value: doubleValue, neutral: neutral, in: minValue...maxValue
        )
        guard !fill.isEmpty else { return }

        // Measure the travel from the knob rather than assuming an inset: the knob centre sits at
        // the bar's left edge plus half a knob at the minimum, and half a knob short of the right
        // edge at the maximum.
        let knobWidth = knobRect(flipped: flipped).width
        let travel = max(bar.width - knobWidth, 0)
        let origin = bar.minX + knobWidth / 2
        let fillRect = NSRect(
            x: origin + travel * fill.start,
            y: bar.minY,
            width: travel * (fill.end - fill.start),
            height: bar.height
        )
        fillColor.setFill()
        NSBezierPath(roundedRect: fillRect, xRadius: radius, yRadius: radius).fill()
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

    private static func barRect(in rect: NSRect) -> NSRect {
        guard rect.height > barThickness else { return rect }
        return NSRect(
            x: rect.minX, y: rect.midY - barThickness / 2,
            width: rect.width, height: barThickness
        )
    }
}

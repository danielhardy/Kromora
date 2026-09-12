import XCTest
@testable import KromoraKit

/// The arithmetic behind KRMA-374: a bipolar slider must show *no* fill at its neutral, and fill
/// only the side between neutral and the thumb.
///
/// Pure and displayless — `SliderFill` exists as a separate type precisely so this can run in the
/// deterministic lane. `NeutralOriginSliderTests` covers the other half, that the numbers below
/// actually reach pixels.
final class SliderFillTests: XCTestCase {

    // MARK: - The three bipolar cases

    func testABipolarControlAtItsNeutralFillsNothing() {
        let fill = SliderFill.span(value: 0, neutral: 0, in: -100...100)
        XCTAssertTrue(fill.isEmpty)
        XCTAssertEqual(fill.start, fill.end)
        XCTAssertEqual(fill.start, 0.5, accuracy: 1e-12, "the baseline is mid-track for −100…100")
    }

    func testAPositiveValueFillsFromNeutralUpToTheThumb() {
        let fill = SliderFill.span(value: 50, neutral: 0, in: -100...100)
        XCTAssertEqual(fill.start, 0.5, accuracy: 1e-12)
        XCTAssertEqual(fill.end, 0.75, accuracy: 1e-12)
        XCTAssertFalse(fill.isEmpty)
    }

    func testANegativeValueFillsFromTheThumbUpToNeutral() {
        let fill = SliderFill.span(value: -50, neutral: 0, in: -100...100)
        XCTAssertEqual(fill.start, 0.25, accuracy: 1e-12)
        XCTAssertEqual(fill.end, 0.5, accuracy: 1e-12)
        XCTAssertFalse(fill.isEmpty)
    }

    /// The property the whole issue is about, stated once over the full travel: the fill never
    /// crosses the baseline, so it is on exactly one side of it at a time.
    func testTheFillNeverStraddlesTheNeutral() {
        for step in 0...200 {
            let value = -100 + Double(step)
            let fill = SliderFill.span(value: value, neutral: 0, in: -100...100)
            if value > 0 {
                XCTAssertEqual(fill.start, 0.5, accuracy: 1e-12, "value \(value)")
            } else if value < 0 {
                XCTAssertEqual(fill.end, 0.5, accuracy: 1e-12, "value \(value)")
            } else {
                XCTAssertTrue(fill.isEmpty, "value \(value)")
            }
        }
    }

    // MARK: - Unipolar controls keep the left-origin fill

    func testAUnipolarControlAtItsFloorFillsNothing() {
        let fill = SliderFill.span(value: 0, neutral: 0, in: 0...1)
        XCTAssertTrue(fill.isEmpty)
    }

    func testAUnipolarControlFillsFromTheLeftEdge() {
        for value in [0.25, 0.5, 0.75, 1.0] {
            let fill = SliderFill.span(value: value, neutral: 0, in: 0...1)
            XCTAssertEqual(fill.start, 0, accuracy: 1e-12, "amount \(value)")
            XCTAssertEqual(fill.end, value, accuracy: 1e-12, "amount \(value)")
        }
    }

    /// A brush size does not start at zero, and its floor is still its baseline.
    func testAUnipolarControlWithANonZeroFloorStillFillsFromTheLeftEdge() {
        let range = 0.001...0.5
        XCTAssertTrue(SliderFill.span(value: 0.001, neutral: 0.001, in: range).isEmpty)
        XCTAssertEqual(
            SliderFill.span(value: 0.25, neutral: 0.001, in: range).start, 0, accuracy: 1e-12
        )
    }

    // MARK: - The baseline is the control's neutral, not the range's midpoint or zero

    /// `AdjustmentControl.contrast` is neutral at 1 in 0…2 — mid-track, but only by coincidence —
    /// and `saturation` shares that shape. Reading the neutral off the model is what makes them
    /// agree; assuming zero would fill half the track on an untouched panel.
    func testAControlWhoseNeutralIsNotZeroAnchorsOnItsNeutral() {
        XCTAssertTrue(
            SliderFill.span(
                value: AdjustmentControl.contrast.neutral,
                neutral: AdjustmentControl.contrast.neutral,
                in: AdjustmentControl.contrast.range
            ).isEmpty
        )
        let reduced = SliderFill.span(
            value: 0.5, neutral: AdjustmentControl.contrast.neutral,
            in: AdjustmentControl.contrast.range
        )
        XCTAssertEqual(reduced.start, 0.25, accuracy: 1e-12)
        XCTAssertEqual(reduced.end, 0.5, accuracy: 1e-12)
    }

    /// `AdjustmentControl.highlights` is 0.3…1 with its identity at the **maximum**, so its fill
    /// only ever runs leftwards and never reaches the right-hand end.
    func testAControlWhoseNeutralIsItsMaximumFillsOnlyLeftwards() {
        let control = AdjustmentControl.highlights
        XCTAssertTrue(
            SliderFill.span(value: control.neutral, neutral: control.neutral, in: control.range)
                .isEmpty
        )
        let recovered = SliderFill.span(value: 0.3, neutral: control.neutral, in: control.range)
        XCTAssertEqual(recovered.start, 0, accuracy: 1e-12)
        XCTAssertEqual(recovered.end, 1, accuracy: 1e-12)
    }

    /// Temperature is reflected about D65 for the slider, so the baseline has to be read in slider
    /// space. It survives the round trip because D65 is the reflection's fixed point — a fact worth
    /// pinning rather than relying on.
    func testTheTemperatureBaselineSurvivesTheSliderReflection() {
        let control = AdjustmentControl.temperature
        XCTAssertEqual(control.sliderMapped(control.neutral), control.neutral)
        XCTAssertTrue(
            SliderFill.span(
                value: control.sliderMapped(control.neutral),
                neutral: control.sliderMapped(control.neutral),
                in: control.range
            ).isEmpty
        )
    }

    // MARK: - Degenerate input

    func testOutOfRangeValuesClampRatherThanOverflowTheTrack() {
        let high = SliderFill.span(value: 1000, neutral: 0, in: -100...100)
        XCTAssertEqual(high.end, 1, accuracy: 1e-12)
        let low = SliderFill.span(value: -1000, neutral: 0, in: -100...100)
        XCTAssertEqual(low.start, 0, accuracy: 1e-12)
    }

    /// A numeric field can hand a view model a NaN before anything clamps it. Drawing must not
    /// inherit that — `NSBezierPath` with a NaN width is a corrupted context, not a wrong picture.
    func testNonFiniteInputDrawsNothing() {
        XCTAssertTrue(SliderFill.span(value: .nan, neutral: 0, in: -100...100).isEmpty)
        XCTAssertTrue(SliderFill.span(value: 0, neutral: .infinity, in: -100...100).isEmpty)
    }

    func testADegenerateRangeDrawsNothing() {
        XCTAssertTrue(SliderFill.span(value: 5, neutral: 5, in: 5...5).isEmpty)
    }

    // MARK: - The neutrals the inspectors hand the slider

    /// Each of these baselines has to be the value its own Reset writes, or an untouched row draws
    /// with a fill and a reset row draws without one.
    func testEveryDeclaredNeutralIsTheValueItsModelDefaultsTo() {
        XCTAssertEqual(ColorGlobalControl.vibrance.neutral, ColorAdjustments.neutral.vibrance)
        XCTAssertEqual(ColorGlobalControl.saturation.neutral, ColorAdjustments.neutral.saturation)
        XCTAssertEqual(ColorMixerControl.hue.neutral, ColorMixerChannel.neutral.hue)
        XCTAssertEqual(ColorMixerControl.saturation.neutral, ColorMixerChannel.neutral.saturation)
        XCTAssertEqual(ColorMixerControl.luminance.neutral, ColorMixerChannel.neutral.luminance)
        XCTAssertEqual(ColorGradingControl.hue.neutral, ColorGradingWheel.neutral.hue)
        XCTAssertEqual(ColorGradingControl.saturation.neutral, ColorGradingWheel.neutral.saturation)
        XCTAssertEqual(
            ColorGradingGlobalControl.blending.neutral, ColorGradingAdjustments.neutral.blending
        )
        XCTAssertEqual(
            ColorGradingGlobalControl.balance.neutral, ColorGradingAdjustments.neutral.balance
        )
        for control in LightControl.allCases {
            XCTAssertEqual(control.neutral, control.value(in: .neutral), "\(control)")
        }
        for control in EffectsControl.allCases {
            XCTAssertEqual(control.neutral, control.value(in: .neutral), "\(control)")
        }
        for control in VignetteControl.allCases {
            XCTAssertEqual(control.neutral, control.value(in: .neutral), "\(control)")
        }
        for control in GrainControl.allCases {
            XCTAssertEqual(control.neutral, control.value(in: .neutral), "\(control)")
        }
    }

    /// **Blending's baseline is 50, not 0.** The one row in the app whose range is unsigned but
    /// whose default sits mid-track, and the reason `SliderFill` takes a neutral instead of a flag.
    func testTheBlendingRowIsCentredDespiteItsUnsignedRange() {
        let control = ColorGradingGlobalControl.blending
        let fill = SliderFill.span(
            value: control.neutral, neutral: control.neutral, in: control.range
        )
        XCTAssertTrue(fill.isEmpty)
        XCTAssertEqual(fill.start, 0.5, accuracy: 1e-12)
    }

    /// Every local-adjustment row reads its baseline off `LocalAdjustments.neutral`, which is why
    /// Temperature is centred on 6500 K rather than on the bottom of 2000…11000.
    func testLocalTemperatureIsCentredOnItsAsShotNeutral() {
        let fill = SliderFill.span(
            value: LocalAdjustments.neutral.temperature,
            neutral: LocalAdjustments.neutral.temperature,
            in: LocalAdjustments.temperatureRange
        )
        XCTAssertTrue(fill.isEmpty)
        XCTAssertEqual(fill.start, 0.5, accuracy: 1e-12)
        XCTAssertEqual(LocalAdjustments.neutral.exposure, 0)
    }
}

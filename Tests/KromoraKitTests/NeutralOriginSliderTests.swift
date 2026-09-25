import XCTest
import AppKit
import SwiftUI
@testable import KromoraKit

/// That the numbers `SliderFill` produces actually reach pixels, through the AppKit drawing path
/// the app really uses.
///
/// Worth its own suite rather than trusting the arithmetic: the whole approach rests on
/// `NSSliderCell.drawBar(inside:flipped:)` still being the method AppKit routes a linear slider's
/// bar through. If a future SDK stops calling it, `SliderFillTests` would keep passing while every
/// slider in the app silently reverted to a left-origin fill, which is the defect this issue was
/// filed about. `testTheCellsBarDrawingIsReachedWhenTheControlDraws` is the canary for that.
@MainActor
final class NeutralOriginSliderTests: XCTestCase {

    private let size = NSSize(width: 200, height: 24)

    // MARK: - Reachability

    func testTheCellsBarDrawingIsReachedWhenTheControlDraws() {
        let slider = makeSlider(range: -100...100, neutral: 0, value: 40)
        guard let cell = slider.cell as? NeutralOriginSliderCell else {
            return XCTFail("the slider is not using the neutral-origin cell")
        }
        XCTAssertEqual(cell.barDrawCount, 0)

        guard let rep = slider.bitmapImageRepForCachingDisplay(in: slider.bounds) else {
            return XCTFail("no bitmap for the slider's bounds")
        }
        slider.cacheDisplay(in: slider.bounds, to: rep)

        XCTAssertGreaterThan(
            cell.barDrawCount, 0,
            "AppKit no longer routes the bar through NSSliderCell.drawBar — the neutral-origin fill "
                + "is not being drawn, however correct SliderFill is"
        )
    }

    // MARK: - The three bipolar cases, in pixels

    func testABipolarSliderAtItsNeutralDrawsNoFill() {
        XCTAssertTrue(
            filledSpan(range: -100...100, neutral: 0, value: 0) == nil,
            "an untouched bipolar track must carry no accent fill at all"
        )
    }

    func testDraggingAboveNeutralFillsOnlyToTheRightOfTheBaseline() {
        let filled = filledSpan(range: -100...100, neutral: 0, value: 60)
        guard let filled else { return XCTFail("+60 drew no fill") }
        let baseline = baselinePoint(range: -100...100, neutral: 0)
        XCTAssertGreaterThanOrEqual(filled.lowerBound, baseline - tolerance)
        XCTAssertLessThanOrEqual(filled.upperBound, size.width)
    }

    func testDraggingBelowNeutralFillsOnlyToTheLeftOfTheBaseline() {
        let filled = filledSpan(range: -100...100, neutral: 0, value: -60)
        guard let filled else { return XCTFail("−60 drew no fill") }
        let baseline = baselinePoint(range: -100...100, neutral: 0)
        XCTAssertLessThanOrEqual(filled.upperBound, baseline + tolerance)
        XCTAssertGreaterThan(filled.lowerBound, 0)
    }

    /// Equal moves either way cover the same amount of track. The check that the baseline really is
    /// an origin rather than a place the fill happens to pass through.
    func testEqualAndOppositeValuesFillEqualAmountsOfTrack() {
        guard let up = filledSpan(range: -100...100, neutral: 0, value: 60),
              let down = filledSpan(range: -100...100, neutral: 0, value: -60)
        else { return XCTFail("±60 drew no fill") }
        XCTAssertEqual(up.upperBound - up.lowerBound, down.upperBound - down.lowerBound,
                       accuracy: tolerance)
    }

    // MARK: - Unipolar controls keep the left-origin fill

    func testAUnipolarSliderAtItsFloorDrawsNoFill() {
        XCTAssertNil(filledSpan(range: 0...1, neutral: 0, value: 0))
    }

    func testAUnipolarSliderFillsFromTheLeftEdge() {
        let filled = filledSpan(range: 0...1, neutral: 0, value: 0.5)
        guard let filled else { return XCTFail("an amount of 0.5 drew no fill") }
        XCTAssertLessThanOrEqual(
            filled.lowerBound, baselinePoint(range: 0...1, neutral: 0) + tolerance
        )
        XCTAssertEqual(
            filled.upperBound, baselinePoint(range: 0...1, neutral: 0.5), accuracy: tolerance
        )
    }

    /// The one control whose neutral is its maximum: the fill can only ever run leftwards, and at
    /// the bottom of the track it covers the whole travel.
    func testAControlNeutralAtItsMaximumFillsLeftwards() {
        let control = AdjustmentControl.highlights
        XCTAssertNil(
            filledSpan(range: control.range, neutral: control.neutral, value: control.neutral)
        )
        let recovered = filledSpan(range: control.range, neutral: control.neutral, value: 0.3)
        guard let recovered else { return XCTFail("recovering highlights drew no fill") }
        XCTAssertEqual(
            recovered.upperBound, baselinePoint(range: control.range, neutral: control.neutral),
            accuracy: tolerance
        )
        XCTAssertLessThanOrEqual(
            recovered.lowerBound, baselinePoint(range: control.range, neutral: 0.3) + tolerance
        )
    }

    // MARK: - Semantic colour-track snapshots

    /// A raster assertion rather than a palette-only unit test: it proves that the colours survive
    /// the actual AppKit bar drawing, including the inactive-track veil used at neutral.
    func testTemperatureTrackRunsFromCoolBlueToWarmAmber() {
        let cool = trackColor(style: .temperature, at: 0.2)
        let warm = trackColor(style: .temperature, at: 0.8)

        XCTAssertGreaterThan(cool.blueComponent, cool.redComponent, "the cool end should read blue")
        XCTAssertGreaterThan(warm.redComponent, warm.blueComponent, "the warm end should read amber")
        XCTAssertGreaterThan(warm.greenComponent, warm.blueComponent, "the warm end should not read magenta")
    }

    func testTintTrackRunsFromGreenToMagenta() {
        let green = trackColor(style: .tint, at: 0.2)
        let magenta = trackColor(style: .tint, at: 0.8)

        XCTAssertGreaterThan(green.greenComponent, green.redComponent, "the negative tint end should read green")
        XCTAssertGreaterThan(magenta.redComponent, magenta.greenComponent, "the positive tint end should read magenta")
        XCTAssertGreaterThan(magenta.blueComponent, magenta.greenComponent, "the positive tint end should retain blue")
    }

    func testChromaTracksRemainClearlyColouredWhenInactive() {
        for style in [SliderTrackStyle.saturation, .vibrance] {
            let sample = trackColor(style: style, at: 0.2)
            let components = [sample.redComponent, sample.greenComponent, sample.blueComponent]
            XCTAssertGreaterThan(
                components.max()! - components.min()!,
                0.06,
                "\(style) should not collapse into a grey inactive track"
            )
        }
    }

    func testSemanticTrackReachesBothEdgesOfTheBar() {
        let left = trackColor(style: .temperature, at: 0.02)
        let right = trackColor(style: .temperature, at: 0.98)

        XCTAssertGreaterThan(
            left.blueComponent, left.redComponent,
            "the colored track should reach the cool bar edge"
        )
        XCTAssertGreaterThan(
            right.redComponent, right.blueComponent,
            "the colored track should reach the warm bar edge"
        )
    }

    func testThumbGeometryIsCircularWithoutChangingNativeKnobGeometry() {
        let slider = makeSlider(range: -100...100, neutral: 0, value: 0)
        guard let cell = slider.cell as? NeutralOriginSliderCell else {
            return XCTFail("the slider is not using the neutral-origin cell")
        }

        let nativeKnob = cell.knobRect(flipped: false)
        let circle = NeutralOriginSliderCell.circularKnobRect(in: nativeKnob)
        XCTAssertEqual(circle.width, circle.height, accuracy: 0.001)
        XCTAssertEqual(circle.midX, nativeKnob.midX, accuracy: 0.001)
        XCTAssertEqual(circle.midY, nativeKnob.midY, accuracy: 0.001)
    }

    func testThumbVisualIsEightyPercentOfTheNativeKnobWhileHitGeometryStaysNative() {
        let slider = makeSlider(range: -100...100, neutral: 0, value: 0)
        guard let cell = slider.cell as? NeutralOriginSliderCell else {
            return XCTFail("the slider is not using the neutral-origin cell")
        }

        let nativeKnob = cell.knobRect(flipped: false)
        let circle = NeutralOriginSliderCell.circularKnobRect(in: nativeKnob)
        let nativeDiameter = min(nativeKnob.width, nativeKnob.height)

        XCTAssertEqual(
            circle.width,
            nativeDiameter * NeutralOriginSliderCell.knobVisualScale,
            accuracy: 0.001
        )
        XCTAssertEqual(circle.height, circle.width, accuracy: 0.001)
        XCTAssertEqual(cell.knobRect(flipped: false), nativeKnob)
    }

    /// The rendered picture, not the arithmetic: draws the whole control the way AppKit does and
    /// compares the vertical centre of the bar's rows with the thumb's rows. The bar is measured
    /// in a column well clear of the knob and the thumb in the knob's own column, so neither
    /// measurement is contaminated by the other.
    func testRenderedThumbIsVerticallyCenteredOnTheRenderedBar() {
        for controlSize in [NSControl.ControlSize.mini, .small, .regular] {
            let slider = makeSlider(range: -100...100, neutral: 0, value: 60)
            guard let cell = slider.cell as? NeutralOriginSliderCell else {
                return XCTFail("the slider is not using the neutral-origin cell")
            }
            cell.controlSize = controlSize
            guard let rep = slider.bitmapImageRepForCachingDisplay(in: slider.bounds) else {
                return XCTFail("could not build a bitmap for \(controlSize)")
            }
            slider.cacheDisplay(in: slider.bounds, to: rep)

            let scale = CGFloat(rep.pixelsWide) / slider.bounds.width
            let knob = cell.knobRect(flipped: slider.isFlipped)
            let thumbColumn = Int(knob.midX * scale)
            let barColumn = Int(slider.bounds.width * 0.15 * scale)

            func inkedRows(in column: Int) -> [Int] {
                (0..<rep.pixelsHigh).filter { y in
                    (rep.colorAt(x: column, y: y)?.alphaComponent ?? 0) > 0.05
                }
            }
            let barRows = inkedRows(in: barColumn)
            let thumbRows = inkedRows(in: thumbColumn)
            guard let barFirst = barRows.first, let barLast = barRows.last,
                  let thumbFirst = thumbRows.first, let thumbLast = thumbRows.last
            else {
                return XCTFail("no bar or thumb pixels rendered for \(controlSize)")
            }
            let barCentre = CGFloat(barFirst + barLast + 1) / 2
            let thumbCentre = CGFloat(thumbFirst + thumbLast + 1) / 2
            XCTAssertEqual(
                thumbCentre, barCentre, accuracy: 1.0 / scale + 0.001,
                "rendered thumb must be centred on the rendered bar for \(controlSize)"
            )
        }
    }

    func testThumbVisualCanCorrectAnOffsetNativeKnobRectWithoutChangingItsHorizontalGeometry() {
        let nativeKnob = NSRect(x: 40, y: 3, width: 20, height: 16)
        let circle = NeutralOriginSliderCell.circularKnobRect(in: nativeKnob, centeredOn: 12)

        XCTAssertEqual(circle.midX, nativeKnob.midX, accuracy: 0.001)
        XCTAssertEqual(circle.midY, 12, accuracy: 0.001)
        XCTAssertEqual(
            circle.width,
            min(nativeKnob.width, nativeKnob.height) * NeutralOriginSliderCell.knobVisualScale,
            accuracy: 0.001
        )
    }

    func testColorControlsUseDocumentedSemanticTracks() {
        XCTAssertEqual(ColorGlobalControl.saturation.trackStyle, .saturation)
        XCTAssertEqual(ColorGlobalControl.vibrance.trackStyle, .vibrance)
        XCTAssertEqual(ColorMixerControl.hue.trackStyle, .hue)
        XCTAssertEqual(ColorMixerControl.saturation.trackStyle, .saturation)
        XCTAssertEqual(ColorMixerControl.luminance.trackStyle, .neutral)
        XCTAssertEqual(ColorGradingControl.hue.trackStyle, .hue)
        XCTAssertEqual(ColorGradingControl.saturation.trackStyle, .saturation)
    }

    func testConfiguredStepSnapsSliderActionsBeforeUpdatingTheBinding() {
        var value = 0.0
        let binding = Binding<Double>(get: { value }, set: { value = $0 })
        let coordinator = NeutralOriginSlider.Coordinator(
            value: binding,
            step: 1,
            onEditingChanged: { _ in }
        )
        let slider = NSSlider()
        slider.minValue = -100
        slider.maxValue = 100
        slider.doubleValue = 37.4

        coordinator.sliderMoved(slider)

        XCTAssertEqual(value, 37)
        XCTAssertEqual(slider.doubleValue, 37)
    }

    // MARK: - Harness

    /// Rasterised geometry lands within a pixel or two of the arithmetic, and the fill's rounded
    /// caps antialias at each end. Which side of the baseline it falls on is not a rounding matter.
    private let tolerance: CGFloat = 2

    private func makeSlider(
        range: ClosedRange<Double>, neutral: Double, value: Double,
        trackStyle: SliderTrackStyle = .neutral
    ) -> NSSlider {
        let slider = NSSlider(frame: NSRect(origin: .zero, size: size))
        let cell = NeutralOriginSliderCell()
        cell.sliderType = .linear
        cell.controlSize = .regular
        slider.cell = cell
        slider.minValue = range.lowerBound
        slider.maxValue = range.upperBound
        slider.doubleValue = value
        cell.neutral = neutral
        cell.trackStyle = trackStyle
        return slider
    }

    private func trackColor(style: SliderTrackStyle, at fraction: CGFloat) -> NSColor {
        let slider = makeSlider(range: -100...100, neutral: 0, value: 0, trackStyle: style)
        guard let cell = slider.cell as? NeutralOriginSliderCell,
              let rep = slider.bitmapImageRepForCachingDisplay(in: slider.bounds),
              let context = NSGraphicsContext(bitmapImageRep: rep)
        else {
            XCTFail("could not build a drawing context for the colour-track snapshot")
            return .clear
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSColor.black.setFill()
        slider.bounds.fill()
        cell.drawBar(inside: slider.bounds, flipped: false)
        NSGraphicsContext.restoreGraphicsState()

        let point = slider.bounds.minX + slider.bounds.width * fraction
        let scale = CGFloat(rep.pixelsWide) / slider.bounds.width
        let x = min(max(Int(point * scale), 0), rep.pixelsWide - 1)
        let y = rep.pixelsHigh / 2
        guard let sampled = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else {
            XCTFail("could not sample the colour-track snapshot")
            return .clear
        }
        return sampled
    }

    /// The horizontal extent of the accent-coloured fill, in points, or `nil` when nothing is
    /// filled.
    ///
    /// Only the bar is drawn — `drawKnob` is skipped — so the knob cannot occlude the end of the
    /// fill at exactly the place these assertions measure. The fill is found by colour rather than
    /// by diffing two renders, so "no fill" is a positive statement about the picture rather than
    /// "indistinguishable from the render we are trying to validate".
    private func filledSpan(
        range: ClosedRange<Double>, neutral: Double, value: Double
    ) -> ClosedRange<CGFloat>? {
        let slider = makeSlider(range: range, neutral: neutral, value: value)
        guard let cell = slider.cell as? NeutralOriginSliderCell,
              let rep = slider.bitmapImageRepForCachingDisplay(in: slider.bounds),
              let context = NSGraphicsContext(bitmapImageRep: rep)
        else {
            XCTFail("could not build a drawing context for the slider")
            return nil
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSColor.black.setFill()
        slider.bounds.fill()
        cell.drawBar(inside: slider.bounds, flipped: false)
        NSGraphicsContext.restoreGraphicsState()

        guard let accent = KromoraTheme.primaryAccentNSColor.usingColorSpace(.deviceRGB) else {
            XCTFail("no device-RGB accent colour")
            return nil
        }
        let scale = CGFloat(rep.pixelsWide) / slider.bounds.width
        let y = rep.pixelsHigh / 2
        var columns: [Int] = []
        for x in 0..<rep.pixelsWide {
            guard let sampled = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else {
                continue
            }
            let distance = max(
                abs(sampled.redComponent - accent.redComponent),
                max(
                    abs(sampled.greenComponent - accent.greenComponent),
                    abs(sampled.blueComponent - accent.blueComponent)
                )
            )
            if distance < 0.02 { columns.append(x) }
        }
        guard let first = columns.first, let last = columns.last else { return nil }
        XCTAssertEqual(
            columns.count, last - first + 1,
            "the fill must be one contiguous run, not two"
        )
        return (CGFloat(first) / scale)...(CGFloat(last + 1) / scale)
    }

    /// The point the knob's centre sits at for `value` — where a fill anchored there has to begin.
    private func baselinePoint(range: ClosedRange<Double>, neutral: Double) -> CGFloat {
        let slider = makeSlider(range: range, neutral: neutral, value: neutral)
        guard let cell = slider.cell as? NeutralOriginSliderCell else { return 0 }
        let knob = cell.knobRect(flipped: false)
        let travel = slider.bounds.width - knob.width
        let fraction = (neutral - range.lowerBound) / (range.upperBound - range.lowerBound)
        return knob.width / 2 + travel * CGFloat(fraction)
    }
}

import SwiftUI

extension AppViewModel {
    func lightValue(for control: LightControl) -> Double {
        control.value(in: document.light)
    }

    func lightBinding(for control: LightControl) -> Binding<Double> {
        Binding(
            get: { self.lightValue(for: control) },
            set: { value in
                self.updateDocument(debounced: true) { document in
                    control.setting(value, in: &document.light)
                }
            }
        )
    }

    func resetLight(_ control: LightControl) {
        endUndoGrouping()
        updateDocument { document in
            control.setting(control.neutral, in: &document.light)
        }
    }

    func resetToneCurve() {
        endUndoGrouping()
        updateDocument { $0.light.toneCurve = .identity }
    }

    func resetAllLight() {
        endUndoGrouping()
        updateDocument { $0.light = .neutral }
    }

    var hasLightAdjustments: Bool { !document.light.isIdentity }

    /// Replace a curve point while keeping its slot ordered between adjacent controls.
    func setToneCurvePoint(_ point: LightCurvePoint, input: Double? = nil, output: Double? = nil) {
        var points = document.light.toneCurve.points
        if points.dropFirst().dropLast().isEmpty, abs(point.input - 0.5) < 0.001 {
            points.append(LightCurvePoint(input: input ?? point.input, output: output ?? point.output))
            updateDocument(debounced: true) {
                $0.light.toneCurve = LightToneCurve(points: points, preserveEndpointPositions: true)
            }
            return
        }
        guard let index = points.firstIndex(of: point) else { return }
        let lower = index == 0 ? 0 : points[index - 1].input + 0.001
        let upper = index == points.count - 1 ? 1 : points[index + 1].input - 0.001
        guard lower <= upper else { return }
        let constrainedInput = min(max(input ?? point.input, lower), upper)
        let monotonic = document.light.toneCurve.isMonotonic
        let constrainedOutput: Double
        if monotonic, index == 0 {
            constrainedOutput = min(output ?? point.output, points[index + 1].output)
        } else if monotonic, index == points.count - 1 {
            constrainedOutput = max(output ?? point.output, points[index - 1].output)
        } else if monotonic {
            constrainedOutput = min(max(output ?? point.output,
                                        points[index - 1].output), points[index + 1].output)
        } else {
            constrainedOutput = output ?? point.output
        }
        points[index] = LightCurvePoint(
            input: constrainedInput,
            output: constrainedOutput
        )
        updateDocument(debounced: true) {
            $0.light.toneCurve = LightToneCurve(points: points, preserveEndpointPositions: true)
        }
    }

    /// Remove an interior point. The model owns endpoint protection; this method is intentionally
    /// a no-op for an endpoint or for a miss outside the pointer hit tolerance.
    func removeToneCurvePoint(atInput input: Double) {
        let curve = document.light.toneCurve
        let updated = curve.removingPoint(at: input)
        guard updated != curve else { return }
        updateDocument(debounced: isToneCurvePreviewInteractionActive) {
            $0.light.toneCurve = updated
        }
    }

    @discardableResult
    func moveToneCurvePoint(fromInput: Double, input: Double, output: Double) -> Double? {
        let points = document.light.toneCurve.points
        guard let point = points.min(by: {
            abs($0.input - fromInput) < abs($1.input - fromInput)
        }) else {
            addToneCurvePoint(input: input, output: output)
            return min(max(input, 0.001), 0.999)
        }

        let index = points.firstIndex(of: point)!
        setToneCurvePoint(
            point,
            input: input,
            output: output
        )
        return document.light.toneCurve.points[index].input
    }

    /// Add a point to the master curve, keeping endpoint points and deterministic ordering intact.
    func addToneCurvePoint(input: Double, output: Double) {
        let curve = document.light.toneCurve
        guard input > 0.001, input < 0.999 else { return }
        guard !curve.points.contains(where: { abs($0.input - input) < 0.005 }) else { return }
        var points = curve.points
        points.append(LightCurvePoint(input: input, output: output))
        updateDocument(debounced: isToneCurvePreviewInteractionActive) {
            $0.light.toneCurve = LightToneCurve(points: points, preserveEndpointPositions: true)
        }
    }

    /// Add a point sampled from the current curve. Used by the click gesture so callers cannot
    /// accidentally create a point with a stale or guessed output value.
    func addToneCurvePoint(input: Double) {
        let curve = document.light.toneCurve
        let updated = curve.addingPoint(at: input)
        guard updated != curve else { return }
        updateDocument(debounced: isToneCurvePreviewInteractionActive) {
            $0.light.toneCurve = updated
        }
    }
}

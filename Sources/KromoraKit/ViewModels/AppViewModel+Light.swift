import SwiftUI
import AppKit
import UniformTypeIdentifiers

extension AppViewModel {
    func importToneCurvePreset() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let preset = try JSONDecoder().decode(ToneCurvePreset.self, from: Data(contentsOf: url))
            endUndoGrouping()
            updateDocument { preset.apply(to: &$0.light) }
        } catch {
            NSApp.presentError(error)
        }
    }

    func exportToneCurvePreset() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Tone Curves.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(ToneCurvePreset(light: document.light)).write(to: url, options: .atomic)
        } catch {
            NSApp.presentError(error)
        }
    }

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

    func resetToneCurve(_ channel: ToneCurveChannel = .master) {
        endUndoGrouping()
        updateDocument { $0.light.setToneCurve(.identity, for: channel) }
    }

    func resetAllLight() {
        endUndoGrouping()
        updateDocument { $0.light = .neutral }
    }

    var hasLightAdjustments: Bool { !document.light.isIdentity }

    /// Replace a curve point while keeping its slot ordered between adjacent controls.
    func setToneCurvePoint(_ point: LightCurvePoint, input: Double? = nil, output: Double? = nil,
                           channel: ToneCurveChannel = .master) {
        let curve = document.light.toneCurve(for: channel)
        var points = curve.points
        if points.dropFirst().dropLast().isEmpty, abs(point.input - 0.5) < 0.001 {
            points.append(LightCurvePoint(input: input ?? point.input, output: output ?? point.output))
            updateDocument(debounced: true) {
                $0.light.setToneCurve(LightToneCurve(points: points, preserveEndpointPositions: true), for: channel)
            }
            return
        }
        guard let index = points.firstIndex(of: point) else { return }
        let lower = index == 0 ? 0 : points[index - 1].input + 0.001
        let upper = index == points.count - 1 ? 1 : points[index + 1].input - 0.001
        guard lower <= upper else { return }
        let constrainedInput = min(max(input ?? point.input, lower), upper)
        let monotonic = curve.isMonotonic
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
            $0.light.setToneCurve(LightToneCurve(points: points, preserveEndpointPositions: true), for: channel)
        }
    }

    /// Remove an interior point. The model owns endpoint protection; this method is intentionally
    /// a no-op for an endpoint or for a miss outside the pointer hit tolerance.
    func removeToneCurvePoint(atInput input: Double, channel: ToneCurveChannel = .master) {
        let curve = document.light.toneCurve(for: channel)
        let updated = curve.removingPoint(at: input)
        guard updated != curve else { return }
        updateDocument(debounced: isToneCurvePreviewInteractionActive) {
            $0.light.setToneCurve(updated, for: channel)
        }
    }

    @discardableResult
    func moveToneCurvePoint(fromInput: Double, input: Double, output: Double,
                            channel: ToneCurveChannel = .master) -> Double? {
        let points = document.light.toneCurve(for: channel).points
        guard let point = points.min(by: {
            abs($0.input - fromInput) < abs($1.input - fromInput)
        }) else {
            addToneCurvePoint(input: input, output: output, channel: channel)
            return min(max(input, 0.001), 0.999)
        }

        let index = points.firstIndex(of: point)!
        setToneCurvePoint(
            point,
            input: input,
            output: output,
            channel: channel
        )
        return document.light.toneCurve(for: channel).points[index].input
    }

    /// Add a point to the master curve, keeping endpoint points and deterministic ordering intact.
    func addToneCurvePoint(input: Double, output: Double, channel: ToneCurveChannel = .master) {
        let curve = document.light.toneCurve(for: channel)
        guard input > 0.001, input < 0.999 else { return }
        guard !curve.points.contains(where: { abs($0.input - input) < 0.005 }) else { return }
        var points = curve.points
        points.append(LightCurvePoint(input: input, output: output))
        updateDocument(debounced: isToneCurvePreviewInteractionActive) {
            $0.light.setToneCurve(LightToneCurve(points: points, preserveEndpointPositions: true), for: channel)
        }
    }

    /// Add a point sampled from the current curve. Used by the click gesture so callers cannot
    /// accidentally create a point with a stale or guessed output value.
    func addToneCurvePoint(input: Double, channel: ToneCurveChannel = .master) {
        let curve = document.light.toneCurve(for: channel)
        let updated = curve.addingPoint(at: input)
        guard updated != curve else { return }
        updateDocument(debounced: isToneCurvePreviewInteractionActive) {
            $0.light.setToneCurve(updated, for: channel)
        }
    }
}

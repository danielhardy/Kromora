import Foundation

/// Photographer-facing name for the edit between two documents, shown in the Undo/Redo menu titles.
///
/// Derived from the document difference so every edit path (sliders, curves, masks, paste) is named
/// without per-call-site bookkeeping. One changed control names itself ("Exposure"); several
/// controls in one section name the section ("Light"); anything broader returns nil and the menu
/// shows plain "Undo"/"Redo".
enum EditActionName {
    static func make(from old: EditDocument, to new: EditDocument) -> String? {
        var changes: [(section: String, control: String)] = []
        func check<T: Equatable>(_ section: String, _ control: String, _ path: KeyPath<EditDocument, T>) {
            if old[keyPath: path] != new[keyPath: path] { changes.append((section, control)) }
        }

        check("Light", "Exposure", \.light.exposure)
        check("Light", "Contrast", \.light.contrast)
        check("Light", "Highlights", \.light.highlights)
        check("Light", "Shadows", \.light.shadows)
        check("Light", "Whites", \.light.whites)
        check("Light", "Blacks", \.light.blacks)
        check("Light", "Tone Curve", \.light.toneCurve)
        check("Light", "Tone Curve", \.light.redToneCurve)
        check("Light", "Tone Curve", \.light.greenToneCurve)
        check("Light", "Tone Curve", \.light.blueToneCurve)
        check("Light", "Tone Curve", \.light.parametricCurve)

        check("Color", "Vibrance", \.color.vibrance)
        check("Color", "Saturation", \.color.saturation)
        check("Color", "Color Mixer", \.color.mixer)
        check("Color", "Color Grading", \.color.grading)

        check("Effects", "Texture", \.effects.texture)
        check("Effects", "Clarity", \.effects.clarity)
        check("Effects", "Dehaze", \.effects.dehaze)
        check("Effects", "Vignette", \.effects.vignette)
        check("Effects", "Grain", \.effects.grain)
        check("Effects", "Detail", \.effects.detail)

        check("Develop", "RAW Develop", \.rawDevelop)
        check("Geometry", "Crop", \.crop)
        check("Geometry", "Rotation", \.rotation)
        check("Look", "Look", \.lut)
        check("Local", "Local Adjustment", \.localAdjustments)
        check("Retouch", "Retouch", \.retouch)
        check("Adjustments", "Adjustments", \.adjustments)

        let controls = Set(changes.map(\.control))
        if controls.count == 1 { return controls.first }
        let sections = Set(changes.map(\.section))
        return sections.count == 1 ? sections.first : nil
    }
}

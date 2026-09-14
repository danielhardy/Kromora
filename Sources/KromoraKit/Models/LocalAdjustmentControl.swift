import Foundation

/// The photographer-facing controls available on every local-adjustment layer.
///
/// The local recipe intentionally uses the same persisted units and ranges as the global stage
/// that renders each control: Light for tone, Color for chroma, the standard Adjust white-balance
/// pair, and Effects for detail. Keeping that mapping in one value type prevents the masking
/// inspector from drifting into a second set of slider rules while retaining layer scope.
enum LocalAdjustmentControl: String, CaseIterable, Hashable, Sendable {
    case exposure
    case contrast
    case highlights
    case shadows
    case whites
    case blacks
    case temperature
    case tint
    case saturation
    case vibrance
    case texture
    case clarity
    case dehaze

    var title: String {
        switch self {
        case .exposure: return "Exposure"
        case .contrast: return "Contrast"
        case .highlights: return "Highlights"
        case .shadows: return "Shadows"
        case .whites: return "Whites"
        case .blacks: return "Blacks"
        case .temperature: return "Temperature"
        case .tint: return "Tint"
        case .saturation: return "Saturation"
        case .vibrance: return "Vibrance"
        case .texture: return "Texture"
        case .clarity: return "Clarity"
        case .dehaze: return "Dehaze"
        }
    }

    var range: ClosedRange<Double> {
        switch self {
        case .exposure: return LightAdjustments.exposureRange
        case .contrast: return LightAdjustments.contrastRange
        case .highlights: return LightAdjustments.highlightsRange
        case .shadows: return LightAdjustments.shadowsRange
        case .whites: return LightAdjustments.whitesRange
        case .blacks: return LightAdjustments.blacksRange
        case .temperature: return AdjustmentControl.temperature.range
        case .tint: return AdjustmentControl.tint.range
        case .saturation: return ColorAdjustments.saturationRange
        case .vibrance: return ColorAdjustments.vibranceRange
        case .texture: return EffectsAdjustments.textureRange
        case .clarity: return EffectsAdjustments.clarityRange
        case .dehaze: return EffectsAdjustments.dehazeRange
        }
    }

    var neutral: Double {
        switch self {
        case .exposure, .contrast, .highlights, .shadows, .whites, .blacks, .tint, .saturation,
            .vibrance, .texture, .clarity, .dehaze:
            return 0
        case .temperature: return AdjustmentControl.temperature.neutral
        }
    }

    func value(in adjustments: LocalAdjustments) -> Double {
        switch self {
        case .exposure: return adjustments.exposure
        case .contrast: return adjustments.contrast
        case .highlights: return adjustments.highlights
        case .shadows: return adjustments.shadows
        case .whites: return adjustments.whites
        case .blacks: return adjustments.blacks
        case .temperature: return adjustments.temperature
        case .tint: return adjustments.tint
        case .saturation: return adjustments.saturation
        case .vibrance: return adjustments.vibrance
        case .texture: return adjustments.texture
        case .clarity: return adjustments.clarity
        case .dehaze: return adjustments.dehaze
        }
    }

    func setting(_ value: Double, in adjustments: inout LocalAdjustments) {
        switch self {
        case .exposure: adjustments.exposure = value
        case .contrast: adjustments.contrast = value
        case .highlights: adjustments.highlights = value
        case .shadows: adjustments.shadows = value
        case .whites: adjustments.whites = value
        case .blacks: adjustments.blacks = value
        case .temperature: adjustments.temperature = value
        case .tint: adjustments.tint = value
        case .saturation: adjustments.saturation = value
        case .vibrance: adjustments.vibrance = value
        case .texture: adjustments.texture = value
        case .clarity: adjustments.clarity = value
        case .dehaze: adjustments.dehaze = value
        }
    }

    /// The same display contract used by the global inspectors for the corresponding stage.
    func readout(_ value: Double) -> String {
        switch self {
        case .exposure:
            return String(format: "%+.2f EV", value)
        case .temperature:
            return ColorSettingFormatting.temperature(value)
        case .contrast, .highlights, .shadows, .whites, .blacks, .tint, .saturation, .vibrance,
            .texture, .clarity, .dehaze:
            return String(format: "%+.0f", value)
        }
    }
}

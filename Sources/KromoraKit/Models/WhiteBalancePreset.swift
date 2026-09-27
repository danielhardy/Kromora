import Foundation

/// Common photographic white-balance targets. Custom leaves the current editable values alone.
enum WhiteBalancePreset: String, CaseIterable, Identifiable, Sendable {
    case asShot = "As Shot"
    case auto = "Auto"
    case daylight = "Daylight"
    case cloudy = "Cloudy"
    case shade = "Shade"
    case tungsten = "Tungsten"
    case fluorescent = "Fluorescent"
    case flash = "Flash"
    case custom = "Custom"

    var id: Self { self }

    /// Conventional Kelvin targets used for standard images and as RAW decoder overrides.
    var temperature: Double? {
        switch self {
        case .daylight, .flash: 5500
        case .cloudy: 6500
        case .shade: 7500
        case .tungsten: 3200
        case .fluorescent: 4000
        case .asShot, .auto, .custom: nil
        }
    }
}

/// Converts a sampled sRGB patch into a practical white-balance correction.
/// The estimate uses the linear red/blue ratio for a bounded daylight-axis estimate and a
/// green/magenta offset around that axis. It is deliberately bounded by existing controls.
enum WhiteBalanceEstimator {
    static func correction(red: Double, green: Double, blue: Double) -> (temperature: Double, tint: Double) {
        let r = linear(red)
        let g = linear(green)
        let b = linear(blue)
        let cct = (6500 + 1800 * log(max(b, 0.0001) / max(r, 0.0001)))
            .clamped(to: 2000...11000, default: 6500)
        let temperature = cct
        let neutralGreen = (0.2126 * r + 0.7152 * g + 0.0722 * b)
        let greenDeviation = (g - (r + b) / 2) / max(neutralGreen, 0.0001)
        let tint = (greenDeviation * 120).clamped(to: -150...150, default: 0)
        return (temperature, tint)
    }

    private static func linear(_ value: Double) -> Double {
        let encoded = value.clamped(to: 0...1, default: 0)
        return encoded <= 0.04045 ? encoded / 12.92 : pow((encoded + 0.055) / 1.055, 2.4)
    }
}

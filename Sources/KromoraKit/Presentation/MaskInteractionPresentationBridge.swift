import AppKit
import SwiftUI

/// SwiftUI/AppKit projection for the platform-neutral mask overlay color.
///
/// Gesture state and durable mask recipes stay in `MaskInteractionState`; only this bridge knows
/// how a SwiftUI `Color` is represented and edited by the color picker.
extension MaskInteractionState {
    var overlayColor: Color {
        get { overlayColorValue.color }
        set {
            guard let value = MaskOverlayColor(newValue) else { return }
            overlayColorValue = value
        }
    }
}

extension MaskOverlayColor {
    var color: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }

    init?(_ color: Color) {
        guard let color = NSColor(color).usingColorSpace(.sRGB) else { return nil }
        self.init(
            red: Double(color.redComponent),
            green: Double(color.greenComponent),
            blue: Double(color.blueComponent),
            alpha: Double(color.alphaComponent)
        )
    }
}

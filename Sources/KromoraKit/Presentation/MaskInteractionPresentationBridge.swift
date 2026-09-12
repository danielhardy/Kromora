import AppKit
import SwiftUI

/// SwiftUI/AppKit projection for the platform-neutral mask overlay color.
///
/// Gesture state and durable mask recipes stay in `MaskInteractionState`; only this bridge knows
/// how a SwiftUI `Color` is represented and edited by the color picker.
extension MaskInteractionState {
    var overlayColor: Color {
        get {
            Color(
                .sRGB,
                red: overlayColorValue.red,
                green: overlayColorValue.green,
                blue: overlayColorValue.blue,
                opacity: overlayColorValue.alpha
            )
        }
        set {
            guard let color = NSColor(newValue).usingColorSpace(.sRGB) else { return }
            overlayColorValue = MaskOverlayColor(
                red: Double(color.redComponent),
                green: Double(color.greenComponent),
                blue: Double(color.blueComponent),
                alpha: Double(color.alphaComponent)
            )
        }
    }
}

import SwiftUI

/// The visible label for an adjustment row.
///
/// A double-click is deliberately the only pointer gesture installed here. A single click remains
/// passive, while the named accessibility action gives VoiceOver users (and keyboard users through
/// the accessibility action menu) the same reset operation without relying on a mouse gesture.
struct ResettableAdjustmentLabel: View {
    let title: String
    let reset: () -> Void
    var resetActionTitle: String = "Reset to neutral"
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Text(title)
            .font(.caption)
            .foregroundStyle(isEnabled ? KromoraTheme.adjustmentLabel : Color.secondary)
            .contentShape(Rectangle())
            .onTapGesture(count: 2, perform: reset)
            .accessibilityElement()
            .accessibilityLabel(title)
            .accessibilityHint("Double-click to \(resetActionTitle.lowercased()).")
            .accessibilityAction(named: Text(resetActionTitle), reset)
    }
}

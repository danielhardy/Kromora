import SwiftUI

/// Compact reset affordance shared by inspectors and settings.
struct ResetIconButton: View {
    let title: String
    var accessibilityLabel: String?
    var accessibilityHint: String?
    var disabled = false
    let action: () -> Void

    init(
        _ title: String,
        accessibilityLabel: String? = nil,
        accessibilityHint: String? = nil,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityHint = accessibilityHint
        self.disabled = disabled
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.counterclockwise")
                .font(.system(size: 11, weight: .medium))
                .frame(width: 24, height: 24)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .disabled(disabled)
        .help(title)
        .accessibilityLabel(accessibilityLabel ?? title)
        .accessibilityHint(accessibilityHint ?? "")
    }
}

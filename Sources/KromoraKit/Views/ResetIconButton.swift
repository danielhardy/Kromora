import SwiftUI

/// Compact reset affordance shared by inspectors and settings.
struct ResetIconButton: View {
    enum Appearance: Equatable {
        case icon
        case semanticLink
    }

    struct AccessibilityPresentation: Equatable {
        let label: String
        let hint: String
    }

    let title: String
    var accessibilityLabel: String?
    var accessibilityHint: String?
    var disabled = false
    var appearance: Appearance = .icon
    let action: () -> Void

    var accessibilityPresentation: AccessibilityPresentation {
        AccessibilityPresentation(label: accessibilityLabel ?? title, hint: accessibilityHint ?? "")
    }

    init(
        _ title: String,
        accessibilityLabel: String? = nil,
        accessibilityHint: String? = nil,
        disabled: Bool = false,
        appearance: Appearance = .icon,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityHint = accessibilityHint
        self.disabled = disabled
        self.appearance = appearance
        self.action = action
    }

    var body: some View {
        control
            .disabled(disabled)
            .help(title)
            .accessibilityLabel(accessibilityPresentation.label)
            .accessibilityHint(accessibilityPresentation.hint)
    }

    @ViewBuilder
    private var control: some View {
        switch appearance {
        case .icon:
            Button(action: action) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 11, weight: .medium))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(InspectorIconButtonStyle())
        case .semanticLink:
            Button(title, action: action)
                .font(.callout)
                .buttonStyle(SemanticLinkButtonStyle())
        }
    }
}

/// The shared look of the inspector's small icon buttons (reset, advanced controls): a quiet
/// secondary glyph that gains a soft circle and a brighter glyph under the pointer, and dims while
/// pressed. `isActive` is for a toggle that is on; it takes the primary accent, and its hover and
/// press states stay in that colour. A disabled button shows no hover at all.
struct InspectorIconButtonStyle: ButtonStyle {
    var isActive = false

    func makeBody(configuration: Configuration) -> some View {
        IconButtonBody(configuration: configuration, isActive: isActive)
    }

    private struct IconButtonBody: View {
        let configuration: ButtonStyleConfiguration
        let isActive: Bool
        @Environment(\.isEnabled) private var isEnabled
        @State private var isHovering = false

        private var hovered: Bool { isHovering && isEnabled }

        var body: some View {
            configuration.label
                .foregroundStyle(glyph)
                .background {
                    Circle().fill(circle)
                }
                .contentShape(Circle())
                .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.4)
                .onHover { isHovering = $0 }
                .animation(.easeOut(duration: 0.12), value: hovered)
        }

        private var glyph: AnyShapeStyle {
            if isActive { return AnyShapeStyle(KromoraTheme.primaryAccent) }
            return hovered ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary)
        }

        private var circle: Color {
            if isActive { return KromoraTheme.primaryAccent.opacity(hovered ? 0.32 : 0.2) }
            return Color.primary.opacity(hovered ? 0.12 : 0)
        }
    }
}

/// A compact, unfilled link in the primary accent. The system `.link` style takes its colour from
/// the system accent and ignores `.tint`, so the foreground is set explicitly here. Hover underlines
/// the title; press dims it.
struct SemanticLinkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        LinkBody(configuration: configuration)
    }

    private struct LinkBody: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isEnabled) private var isEnabled
        @State private var isHovering = false

        var body: some View {
            configuration.label
                .foregroundStyle(KromoraTheme.primaryAccent)
                .underline(isHovering && isEnabled)
                .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.4)
                .contentShape(Rectangle())
                .onHover { isHovering = $0 }
        }
    }
}

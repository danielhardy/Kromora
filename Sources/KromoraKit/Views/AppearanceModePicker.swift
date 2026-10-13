import AppKit
import SwiftUI

/// Three selectable miniature app shells: System, Light, and Dark. Previews are drawn from the
/// same `KromoraTheme` roles the app resolves under each appearance, so they stay accurate.
struct AppearanceModePicker: View {
    @Binding var selection: KromoraAppearanceMode

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            ForEach(KromoraAppearanceMode.allCases, id: \.self) { mode in
                AppearanceModeOption(mode: mode, isSelected: selection == mode) {
                    selection = mode
                }
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Appearance")
    }
}

private struct AppearanceModeOption: View {
    let mode: KromoraAppearanceMode
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                preview
                    .frame(width: 96, height: 62)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(
                                isSelected ? KromoraTheme.primaryAccent : Color.secondary.opacity(0.4),
                                lineWidth: isSelected ? 3 : 1)
                    }
                HStack(spacing: 4) {
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(KromoraTheme.primaryAccent)
                            .accessibilityHidden(true)
                    }
                    Text(mode.title)
                        .fontWeight(isSelected ? .semibold : .regular)
                }
                .font(.callout)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(mode.title)
        .accessibilityHint(
            mode == .system
                ? "Follow the macOS appearance" : "Always use the \(mode.title.lowercased()) appearance")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityIdentifier("appearance-\(mode.rawValue)")
    }

    @ViewBuilder
    private var preview: some View {
        switch mode {
        case .system:
            // Left half Light, right half Dark: the Mac decides.
            HStack(spacing: 0) {
                MiniShell(appearance: NSAppearance(named: .aqua))
                    .frame(width: 48, alignment: .leading)
                    .clipped()
                MiniShell(appearance: NSAppearance(named: .darkAqua))
                    .frame(width: 48, alignment: .trailing)
                    .clipped()
            }
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: "laptopcomputer")
                    .font(.caption2)
                    .padding(3)
                    .foregroundStyle(.white)
                    .accessibilityHidden(true)
            }
        case .light: MiniShell(appearance: NSAppearance(named: .aqua))
        case .dark: MiniShell(appearance: NSAppearance(named: .darkAqua))
        }
    }
}

/// A 96x62 miniature of the Edit shell: toolbar, sidebar, canvas with a photo block, inspector.
private struct MiniShell: View {
    let appearance: NSAppearance?

    private func color(_ resolve: (NSAppearance?) -> NSColor) -> Color {
        Color(nsColor: resolve(appearance))
    }

    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(color { KromoraTheme.resolvedToolbarChromeColor(for: $0) })
                .frame(height: 10)
            HStack(spacing: 0) {
                Rectangle().fill(color { KromoraTheme.resolvedSecondaryChromeColor(for: $0) })
                    .frame(width: 20)
                ZStack {
                    Rectangle().fill(color { KromoraTheme.resolvedCanvasBackgroundColor(for: $0) })
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color { KromoraTheme.resolvedPrimaryAccentColor(for: $0) }.opacity(0.85))
                        .frame(width: 30, height: 22)
                }
                Rectangle().fill(color { KromoraTheme.resolvedInspectorChromeColor(for: $0) })
                    .frame(width: 18)
            }
        }
        .frame(width: 96, height: 62)
    }
}

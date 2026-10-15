import AppKit
import SwiftUI

/// A slider's value readout that turns into a numeric field on click.
///
/// Return commits, Escape or clicking away cancels. Input is validated by `SliderValueEntry`,
/// which shares the slider's range and step, so an out-of-range number is rejected with a visible
/// message and never applied. A commit goes through the same binding and begin/end interaction
/// hooks as a slider drag, and typing the current value does nothing.
struct SliderValueField: View {
    let title: String
    @Binding var value: Double
    let entry: SliderValueEntry
    /// The text shown while not editing.
    let readout: String
    var width: CGFloat = 68
    var font: Font = .system(.caption, design: .monospaced)
    var onEditingChanged: (Bool) -> Void = { _ in }

    @State private var isEditing = false
    @State private var text = ""
    @State private var textAtStart = ""
    @State private var errorMessage: String?
    @FocusState private var isFocused: Bool

    var body: some View {
        Group {
            if isEditing {
                editor
            } else {
                Button(action: beginEditing) {
                    Text(readout)
                        .font(font)
                        .foregroundStyle(.secondary)
                        .frame(width: width, alignment: .trailing)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(title)
                .accessibilityValue(readout)
                .accessibilityHint("Type an exact value")
            }
        }
        .frame(width: width, alignment: .trailing)
    }

    private var editor: some View {
        TextField(title, text: $text)
            .textFieldStyle(.plain)
            .font(font)
            .multilineTextAlignment(.trailing)
            .frame(width: width, alignment: .trailing)
            .focused($isFocused)
            .overlay {
                RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(errorMessage == nil ? Color.accentColor : .red, lineWidth: 1.5)
                    .padding(-2)
            }
            .overlay(alignment: .bottomTrailing) {
                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .fixedSize()
                        .padding(.horizontal, 4)
                        .background(.background, in: RoundedRectangle(cornerRadius: 3))
                        .offset(y: 16)
                        .allowsHitTesting(false)
                }
            }
            .zIndex(1)
            .accessibilityLabel(title)
            .onSubmit(commit)
            .onExitCommand(perform: cancel)
            .onChange(of: text) { errorMessage = nil }
            .onChange(of: isFocused) { _, focused in
                if !focused { cancel() }
            }
    }

    private func beginEditing() {
        text = entry.editingText(for: value)
        textAtStart = text
        errorMessage = nil
        isEditing = true
        Task { @MainActor in
            isFocused = true
            await Task.yield()
            NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
        }
    }

    private func cancel() {
        guard isEditing else { return }
        isEditing = false
        errorMessage = nil
    }

    private func commit() {
        switch entry.parse(text) {
        case .failure(let failure):
            errorMessage = failure.message
            AccessibilityNotification.Announcement(failure.message).post()
        case .success(let newValue):
            let valueToAnnounce = text == textAtStart ? value : newValue
            if text != textAtStart, abs(newValue - value) > 1e-9 {
                onEditingChanged(true)
                value = newValue
                onEditingChanged(false)
            }
            AccessibilityNotification.Announcement(
                "\(title) \(entry.announcement(for: valueToAnnounce))"
            ).post()
            isEditing = false
            errorMessage = nil
        }
    }
}

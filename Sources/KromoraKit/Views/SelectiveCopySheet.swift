import SwiftUI

/// Compact category picker for the value-only edit clipboard.
struct SelectiveCopySheet: View {
    @Binding var categories: Set<EditClipboardPayload.Category>
    let sourceName: String
    let onCopy: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Copy Edits")
                    .font(.headline)
                Text("Choose which edits to copy from \(sourceName).")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(EditClipboardPayload.Category.allCases, id: \.self) { category in
                    Toggle(
                        category.title,
                        isOn: Binding(
                            get: { categories.contains(category) },
                            set: { isSelected in
                                if isSelected {
                                    categories.insert(category)
                                } else {
                                    categories.remove(category)
                                }
                            }
                        )
                    )
                }
            }

            HStack {
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Copy", action: onCopy)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(categories.isEmpty)
            }
        }
        .padding(22)
        .frame(width: 320)
    }
}

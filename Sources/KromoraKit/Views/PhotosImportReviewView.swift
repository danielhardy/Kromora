import Photos
import SwiftUI

/// Confirms a Photos picker selection before import, tagging items already in the library. The
/// grid mirrors `RemovableMediaSelectorView`: tagged items start unselected, a count and a Hide
/// toggle summarize them, and a tagged item can still be chosen explicitly.
struct PhotosImportReviewView: View {
    @Bindable var review: PhotosImportReviewCoordinator

    private static let cellWidth: CGFloat = 128

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Label("Import from Photos", systemImage: "photo.on.rectangle")
                    .font(.headline)
                Spacer()
                Text("\(review.selection.count) of \(review.items.count) selected")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            Divider()
            toolbar
            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: Self.cellWidth), spacing: 10)],
                    alignment: .leading, spacing: 10
                ) {
                    ForEach(review.visibleItems) { item in cell(for: item) }
                }
                .padding(16)
            }
            Divider()
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { review.cancel() }
                    .keyboardShortcut(.cancelAction)
                Button("Import \(review.selection.count) Selected") { review.confirm() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(review.selection.count == 0)
            }
            .padding(16)
        }
        .frame(minWidth: 640, minHeight: 480)
        .tint(KromoraTheme.primaryAccent)
    }

    private var toolbar: some View {
        HStack {
            Button("Select All") { review.selectAll() }
            Button("Select None") { review.selectNone() }
            if !review.inLibrary.isEmpty {
                Text("\(review.inLibrary.count) of \(review.items.count) already in library")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Toggle("Hide", isOn: $review.hidesInLibrary)
                    .toggleStyle(.checkbox)
                    .help("Hide photos that are already in the library")
                    .accessibilityLabel("Hide photos already in library")
            }
            if review.isChecking {
                ProgressView().controlSize(.small)
                Text("Checking library… \(review.checked)/\(review.items.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("Shift-click to select a range.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func cell(for item: PhotosImportReviewCoordinator.Item) -> some View {
        let isSelected = review.selection.contains(id: item.id)
        let isInLibrary = review.inLibrary.contains(item.id)
        return Button {
            if NSEvent.modifierFlags.contains(.shift) {
                review.selectRange(to: item)
            } else {
                review.toggle(item)
            }
        } label: {
            PhotosReviewThumbnail(localIdentifier: item.selection.localIdentifier)
                .overlay(alignment: .topTrailing) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, isSelected ? KromoraTheme.primaryAccent : Color.black.opacity(0.35))
                        .padding(6)
                }
                .overlay(alignment: .bottomLeading) {
                    if isInLibrary {
                        Label("In library", systemImage: "checkmark.seal")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.regularMaterial, in: Capsule())
                            .padding(6)
                            .accessibilityHidden(true)
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(isSelected ? KromoraTheme.primaryAccent : Color.clear, lineWidth: 3)
                }
        }
        .buttonStyle(.plain)
        .help(item.name)
        .accessibilityLabel(item.name)
        .accessibilityValue(
            (isInLibrary ? "Already in library, " : "") + (isSelected ? "Selected" : "Not selected")
        )
    }
}

private struct PhotosReviewThumbnail: View {
    let localIdentifier: String?
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                Rectangle()
                    .fill(Color.secondary.opacity(0.12))
                    .overlay { Image(systemName: "photo").foregroundStyle(.secondary) }
            }
        }
        .frame(width: 128, height: 96)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .task(id: localIdentifier) { image = await Self.load(localIdentifier) }
    }

    private static func load(_ identifier: String?) async -> NSImage? {
        guard let identifier,
              let asset = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil).firstObject
        else { return nil }
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = false
        return await withCheckedContinuation { continuation in
            PHImageManager.default().requestImage(
                for: asset, targetSize: CGSize(width: 256, height: 192),
                contentMode: .aspectFill, options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }
}

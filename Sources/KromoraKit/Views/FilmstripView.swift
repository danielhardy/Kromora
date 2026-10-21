import SwiftUI
import AppKit

/// Horizontal thumbnail strip for browsing imported images.
struct FilmstripView: View {
    @Bindable var collection: ImageCollection
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    let settings: KromoraSettings
    let viewModel: AppViewModel
    let onSelect: (Int, LibrarySelectionModel.Modifiers) -> Void

    var body: some View {
        let entries = collection.thumbnailEntries

        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 8) {
                    ForEach(entries) { entry in
                        if let resolved = collection.resolvedItem(for: entry) {
                            let item = resolved.item
                            Button {
                                let modifiers = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
                                var selectionModifiers: LibrarySelectionModel.Modifiers = []
                                if modifiers.contains(.command) { selectionModifiers.insert(.command) }
                                if modifiers.contains(.shift) { selectionModifiers.insert(.shift) }
                                onSelect(resolved.index, selectionModifiers)
                            } label: {
                                FilmstripThumbnail(
                                    item: item,
                                    settings: settings,
                                    isSelected: collection.selection.selectedIDs.contains(item.id)
                                )
                            }
                            .buttonStyle(.plain)
                            // Thumbnails stay VoiceOver buttons but never take keyboard focus: arrows
                            // belong to the app-level key surface (`KeyboardSurface`), and a focused
                            // NSButton would strand them on a control that cannot use them.
                            .focusable(false)
                            .overlay {
                                LibraryContextClickRetarget {
                                    viewModel.retargetLibrarySelection(toContext: item.id)
                                }
                                .accessibilityHidden(true)
                            }
                            .contextMenu { LibraryContextMenuItems(viewModel: viewModel, photoID: item.id) }
                            // Use the source ID for navigation scrolling; the collection keeps the
                            // reservation ID internally so this cell can be replaced in place.
                            .id(item.id)
                            .onAppear {
                                // Child appearance can precede the scroll view's callback, so opt into
                                // demand-driven work here as well as on the container.
                                collection.beginThumbnailDemand()
                                collection.requestThumbnail(
                                    for: item.id, priority: .adjacentFilmstrip
                                )
                            }
                            .onDisappear {
                                collection.releaseThumbnail(for: item.id)
                            }
                        }
                    }
                }
                .padding(.horizontal, FilmstripLayout.horizontalContentInset)
                // The native inspector resizes this viewport, so the existing 12 pt horizontal
                // content inset is the complete end gutter at the rightmost scroll position.
                .padding(.vertical, FilmstripLayout.stripVerticalPadding)
            }
            .background(KromoraTheme.canvasBackground)
            // The strip owns its settings observation so a caption toggle resizes it without
            // invalidating the root view model.
            .frame(height: FilmstripLayout.stripHeight(showPhotoNames: settings.showPhotoNames))
            .onAppear { collection.beginThumbnailDemand() }
            .onChange(of: collection.selectedIndex) { _, newIndex in
                guard collection.items.indices.contains(newIndex) else { return }
                withAnimation(
                    .easeInOut(duration: 0.2).respectingReduceMotion(accessibilityReduceMotion)
                ) {
                    proxy.scrollTo(collection.items[newIndex].id, anchor: .center)
                }
            }
        }
    }
}

/// Geometry for the Edit filmstrip. The strip height is derived from the cell and optional
/// caption so status badges do not reserve a second row below every thumbnail.
enum FilmstripLayout {
    static let thumbnailSize: CGFloat = 96
    static let horizontalContentInset: CGFloat = 12
    static let stripVerticalPadding: CGFloat = 3
    static let captionSpacing: CGFloat = 3
    static let captionHeight: CGFloat = 12

    static func stripHeight(showPhotoNames: Bool) -> CGFloat {
        thumbnailSize
            + (showPhotoNames ? captionSpacing + captionHeight : 0)
            + (stripVerticalPadding * 2)
            + 1
    }
}

struct FilmstripThumbnail: View {
    @Bindable var item: ImageCollection.Item
    let settings: KromoraSettings
    let isSelected: Bool

    var body: some View {
        VStack(spacing: FilmstripLayout.captionSpacing) {
            ZStack {
                if let thumbnail = item.thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        // The filmstrip is always square, regardless of which raster has arrived.
                        .aspectRatio(contentMode: .fill)
                        .frame(
                            width: FilmstripLayout.thumbnailSize,
                            height: FilmstripLayout.thumbnailSize
                        )
                        .clipped()
                } else {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.15))
                        .frame(
                            width: FilmstripLayout.thumbnailSize,
                            height: FilmstripLayout.thumbnailSize
                        )
                        .overlay {
                            ProgressView()
                                .scaleEffect(0.5)
                        }
                }

                if item.asset.flag != .none {
                    flagBadge
                        .frame(
                            maxWidth: .infinity,
                            maxHeight: .infinity,
                            alignment: .bottomLeading
                        )
                }

                if item.asset.rating > 0 {
                    ratingBadge
                        .frame(
                            maxWidth: .infinity,
                            maxHeight: .infinity,
                            alignment: .bottomTrailing
                        )
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? KromoraTheme.primaryAccent : Color.clear, lineWidth: 2.5)
            )

            if settings.showPhotoNames {
                Text(item.displayName)
                    .font(.system(size: 9))
                    .foregroundColor(isSelected ? .primary : .secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(
                        width: FilmstripLayout.thumbnailSize,
                        height: FilmstripLayout.captionHeight
                    )
                    .accessibilityLabel(item.displayName)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.displayName)
        .accessibilityValue(accessibilityValue)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var accessibilityValue: String {
        let selection = isSelected ? "Selected" : "Not selected"
        let flag = item.asset.flag == .none ? "unflagged" : item.asset.flag.rawValue
        return "\(selection), \(flag), \(item.asset.rating) stars"
    }

    private var flagBadge: some View {
        Image(systemName: item.asset.flag == .pick ? "checkmark.circle.fill" : "xmark.circle.fill")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(item.asset.flag == .pick ? .green : .red, .white)
            .padding(3)
            .background(.black.opacity(0.72), in: Circle())
            .padding(4)
    }

    private var ratingBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: "star.fill")
                .foregroundStyle(.yellow)
            Text("\(item.asset.rating)")
        }
        .font(.system(size: 9, weight: .semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
        .background(.black.opacity(0.72), in: Capsule())
        .padding(4)
    }
}

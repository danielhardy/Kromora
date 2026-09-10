import SwiftUI
import AppKit

/// Horizontal thumbnail strip for browsing imported images.
struct FilmstripView: View {
    @ObservedObject var collection: ImageCollection
    @ObservedObject var settings: KromoraSettings
    let onSelect: (Int, Bool) -> Void

    var body: some View {
        let entries = collection.thumbnailEntries
        let filteredIndices = collection.filteredIndices

        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 8) {
                    ForEach(entries) { entry in
                        if let resolved = collection.resolvedItem(for: entry) {
                            let item = resolved.item
                            Button {
                                let modifiers = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
                                onSelect(resolved.index, modifiers.contains(.command))
                            } label: {
                                FilmstripThumbnail(
                                    item: item,
                                    settings: settings,
                                    isSelected: collection.selection.selectedIDs.contains(item.id)
                                )
                            }
                            .buttonStyle(.plain)
                            .onKeyPress(keys: [.leftArrow, .rightArrow]) { press in
                                let direction: FilmstripNavigation.Direction =
                                    press.key == .leftArrow ? .previous : .next
                                guard let adjacentIndex = FilmstripNavigation.adjacentIndex(
                                    in: filteredIndices,
                                    selectedIndex: collection.selectedIndex,
                                    direction: direction
                                ) else {
                                    return .ignored
                                }
                                onSelect(adjacentIndex, false)
                                return .handled
                            }
                            // Use the source ID for navigation scrolling; the mosaic keeps the
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
                        } else if let slot = entry.placeholder {
                            FilmstripPlaceholder(slot: slot)
                                .id(entry.id)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .background(.bar)
            .onAppear { collection.beginThumbnailDemand() }
            .onChange(of: collection.selectedIndex) { _, newIndex in
                guard collection.items.indices.contains(newIndex) else { return }
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo(collection.items[newIndex].id, anchor: .center)
                }
            }
        }
    }
}

/// Computes filmstrip navigation in display order rather than underlying collection order. This
/// keeps keyboard stepping aligned with filtered thumbnails and gives the view a small, pure seam
/// for testing without synthesizing AppKit focus.
enum FilmstripNavigation {
    enum Direction {
        case previous
        case next
    }

    static func adjacentIndex(
        in filteredIndices: [Int],
        selectedIndex: Int,
        direction: Direction
    ) -> Int? {
        switch direction {
        case .previous:
            return filteredIndices.last { $0 < selectedIndex }
        case .next:
            return filteredIndices.first { $0 > selectedIndex }
        }
    }
}

struct FilmstripThumbnail: View {
    @ObservedObject var item: ImageCollection.Item
    @ObservedObject var settings: KromoraSettings
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                if let thumbnail = item.thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 72, height: 72)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.15))
                        .frame(width: 72, height: 72)
                        .overlay {
                            ProgressView()
                                .scaleEffect(0.5)
                        }
                }

                if item.asset.flag == .reject {
                    Color.black.opacity(0.58)
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.red, .white)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2.5)
            )

            if settings.showPhotoNames {
                Text(item.displayName)
                    .font(.system(size: 9))
                    .foregroundColor(isSelected ? .primary : .secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(width: 72)
                    .accessibilityLabel(item.displayName)
            }

            HStack(spacing: 3) {
                if item.asset.flag == .pick {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else if item.asset.flag == .reject {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.red)
                }
                if item.asset.rating > 0 {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.yellow)
                    Text("\(item.asset.rating)")
                }
            }
            .font(.system(size: 8, weight: .semibold))
            .frame(height: 10)
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
}

private struct FilmstripPlaceholder: View {
    let slot: ImageCollection.PendingImportSlot

    var body: some View {
        VStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.secondary.opacity(0.09))
                .frame(width: 72, height: 72)
                .overlay {
                    if slot.state == .pending {
                        ProgressView()
                            .scaleEffect(0.5)
                    } else {
                        Image(systemName: "photo.badge.exclamationmark")
                            .foregroundStyle(.secondary)
                    }
                }
            Text(slot.state == .pending ? "Importing" : "Unavailable")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 72)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(slot.state == .pending ? "Importing photo" : "Photo unavailable")
    }
}

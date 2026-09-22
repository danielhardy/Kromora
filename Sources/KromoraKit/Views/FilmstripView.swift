import SwiftUI
import AppKit

/// Horizontal thumbnail strip for browsing imported images.
struct FilmstripView: View {
    @Bindable var collection: ImageCollection
    @ObservedObject var settings: KromoraSettings
    let onSelect: (Int, LibrarySelectionModel.Modifiers) -> Void

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
                            // Thumbnails must remain VoiceOver buttons, but they must not take
                            // keyboard focus. A focused NSButton interprets leftover arrows as
                            // `noop:` and plays the system error beep even after `.onKeyPress`
                            // returns `.handled`.
                            .focusable(false)
                            // A focused thumbnail owns the arrow gesture. Consume every phase so
                            // AppKit's native button responder never sees a successful navigation,
                            // a boundary no-op, or the key-up after SwiftUI replaces the selected
                            // cell. The button's normal activation and accessibility behavior are
                            // otherwise left intact.
                            .onKeyPress(
                                keys: [.leftArrow, .rightArrow, .upArrow, .downArrow],
                                phases: .all
                            ) { press in
                                let result = FilmstripNavigation.keyPressResult(for: press.phase)
                                guard result == .handled else { return result }
                                guard press.phase != .up else { return result }
                                guard press.key == .leftArrow || press.key == .rightArrow else {
                                    return result
                                }
                                let direction: FilmstripNavigation.Direction =
                                    press.key == .leftArrow ? .previous : .next
                                guard let adjacentIndex = FilmstripNavigation.adjacentIndex(
                                    in: filteredIndices,
                                    selectedIndex: collection.selectedIndex,
                                    direction: direction
                                ) else {
                                    // Reaching either end is an intentional no-op, but the arrow
                                    // still belongs to the focused filmstrip control.
                                    return result
                                }
                                onSelect(adjacentIndex, [])
                                return result
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
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, FilmstripLayout.stripVerticalPadding)
            }
            .background(KromoraTheme.secondaryChrome)
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

/// Geometry for the Edit filmstrip. The strip height is derived from the cell and optional
/// caption so status badges do not reserve a second row below every thumbnail.
enum FilmstripLayout {
    static let thumbnailSize: CGFloat = 96
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

/// Computes filmstrip navigation in display order rather than underlying collection order. This
/// keeps keyboard stepping aligned with filtered thumbnails and gives the view a small, pure seam
/// for testing without synthesizing AppKit focus.
enum FilmstripNavigation {
    enum Direction {
        case previous
        case next
    }

    /// Arrow key events are handled at the focused SwiftUI button boundary. In particular, the
    /// key-up must be consumed even though it does not select another item: after a selection
    /// changes the old button can be replaced before AppKit dispatches that event.
    static func keyPressResult(for phase: KeyPress.Phases) -> KeyPress.Result {
        guard phase == .down || phase == .repeat || phase == .up else {
            return .ignored
        }
        return .handled
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
    @Bindable var item: ImageCollection.Item
    @ObservedObject var settings: KromoraSettings
    let isSelected: Bool

    var body: some View {
        VStack(spacing: FilmstripLayout.captionSpacing) {
            ZStack {
                if let thumbnail = item.thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
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
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2.5)
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

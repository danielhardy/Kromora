import AppKit
import SwiftUI

/// The grid-first browsing surface for a source collection.
///
/// `LazyVStack` is important here: the collection may contain thousands of `PhotoAsset` values, but
/// SwiftUI only hosts the rows around the viewport. Each hosted cell opts into thumbnail work from
/// `onAppear`, and releases in-flight work from `onDisappear`, so scrolling does not create a decode
/// task for the entire folder.
struct LibraryGridView: View {
    @ObservedObject var collection: ImageCollection
    @ObservedObject var viewModel: AppViewModel
    let onOpen: () -> Void

    private let layout = LibraryGridLayout()
    @State private var mosaicCache = LibraryMosaicLayoutCache()

    var body: some View {
        let entries = collection.thumbnailEntries

        VStack(spacing: 0) {
            HStack(spacing: 0) {
                CullingBarView(viewModel: viewModel)
                Divider()
                    .frame(height: 28)
                Button(role: .destructive) {
                    viewModel.requestDeleteSelectedLibraryItems()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .help("Remove the selected photo(s) from the Library (Delete)")
                .accessibilityHint(
                    "Move managed originals to the macOS Trash; keep referenced originals"
                )
                .disabled(collection.deletionCandidates.isEmpty)
                .padding(.horizontal, 12)
            }
            Divider()
            if collection.isPortableWindowed, let total = collection.portableTotalCount {
                Text("Showing \(collection.items.count) of \(total) — scroll for more")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 4)
                    .accessibilityLabel("Showing \(collection.items.count) of \(total) photos")
            }

            GeometryReader { geometry in
                if entries.isEmpty {
                    LibraryEmptyState(collection: collection)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        let itemIDs = entries.map(\.id)
                        let rows = mosaicCache.rows(
                            itemIDs: itemIDs,
                            width: max(1, geometry.size.width - 32),
                            cropGeneration: collection.cropGeneration,
                            layout: layout,
                            aspectRatioAt: { entries[$0].aspectRatio }
                        )
                        LazyVStack(alignment: .leading, spacing: CGFloat(layout.spacing)) {
                            ForEach(rows) { row in
                                LibraryMosaicRow(
                                    row: row,
                                    entries: entries,
                                    collection: collection,
                                    settings: viewModel.settings,
                                    spacing: layout.spacing,
                                    onSelect: select(index:),
                                    onOpen: onOpen,
                                    onAppearIndex: { viewModel.loadMorePortableIfNeeded(currentIndex: $0) }
                                )
                            }
                        }
                        .padding(16)
                        .frame(
                            maxWidth: .infinity,
                            minHeight: geometry.size.height,
                            alignment: .top
                        )
                    }
                    .background(KromoraTheme.windowBackground)
                }
            }
        }
        .background(KromoraTheme.windowBackground)
        .onAppear {
            collection.beginThumbnailDemand()
        }
        .overlay(alignment: .bottomLeading) {
            if collection.isScanning {
                Label("Scanning…", systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.regularMaterial, in: Capsule())
                    .padding(12)
            }
        }
    }

    private func select(index: Int) {
        let flags = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var modifiers: LibrarySelectionModel.Modifiers = []
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if collection.isPortableWindowed {
            // Single authority: the query controller owns portable selection; the collection
            // mirrors it so grid, filmstrip, keyboard, culling, and open stay coherent.
            viewModel.selectPortableItem(at: index, modifiers: modifiers)
            viewModel.loadMorePortableIfNeeded(currentIndex: index)
        } else {
            collection.select(at: index, modifiers: modifiers)
        }
    }
}

private struct LibraryMosaicRow: View {
    let row: LibraryGridLayout.MosaicRow
    let entries: [ImageCollection.ThumbnailEntry]
    @ObservedObject var collection: ImageCollection
    @ObservedObject var settings: KromoraSettings
    let spacing: Double
    let onSelect: (Int) -> Void
    let onOpen: () -> Void
    var onAppearIndex: ((Int) -> Void)? = nil

    private var cells: [LibraryMosaicCellLayout] {
        zip(row.itemIndices, row.itemWidths).compactMap { offset, width in
            guard entries.indices.contains(offset) else { return nil }
            return LibraryMosaicCellLayout(
                offset: offset,
                width: width,
                id: entries[offset].id
            )
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: CGFloat(spacing)) {
            ForEach(cells) { cell in
                let entry = entries[cell.offset]
                if let resolved = collection.resolvedItem(for: entry) {
                    let item = resolved.item
                    LibraryGridCell(
                        item: item,
                        settings: settings,
                        isSelected: collection.selection.selectedIDs.contains(item.id),
                        isActive: collection.selection.activeID == item.id,
                        imageWidth: cell.width,
                        imageHeight: row.imageHeight
                    )
                    .frame(width: CGFloat(cell.width))
                    .onAppear {
                        // Make the cell callback order-independent: SwiftUI may deliver a child's
                        // appearance before its row's appearance.
                        collection.beginThumbnailDemand()
                        collection.requestThumbnail(for: item.id)
                        onAppearIndex?(resolved.index)
                    }
                    .onDisappear {
                        collection.releaseThumbnail(for: item.id)
                    }
                    .onTapGesture {
                        onSelect(resolved.index)
                    }
                    .simultaneousGesture(
                        TapGesture(count: 2).onEnded {
                            onSelect(resolved.index)
                            onOpen()
                        }
                    )
                    .accessibilityAddTraits(
                        collection.selection.selectedIDs.contains(item.id) ? .isSelected : []
                    )
                    .accessibilityHint("Double-click to edit")
                } else if let slot = entry.placeholder {
                    LibraryGridPlaceholder(slot: slot)
                        .frame(width: CGFloat(cell.width), height: CGFloat(row.imageHeight))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct LibraryMosaicCellLayout: Identifiable {
    let offset: Int
    let width: Double
    let id: PhotoAssetID
}

private struct LibraryEmptyState: View {
    @ObservedObject var collection: ImageCollection

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: collection.items.isEmpty ? "photo.on.rectangle.angled" : "line.3.horizontal.decrease.circle")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text(collection.items.isEmpty ? "No photos in this library" : "No photos match these filters")
                .font(.headline)
            if collection.filter.isFiltered {
                Button("Clear filters") { collection.clearFilter() }
                    .buttonStyle(.bordered)
            }
        }
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }
}

private struct LibraryGridCell: View {
    @ObservedObject var item: ImageCollection.Item
    @ObservedObject var settings: KromoraSettings
    let isSelected: Bool
    let isActive: Bool
    let imageWidth: Double
    let imageHeight: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            thumbnail
                .frame(width: CGFloat(imageWidth), height: CGFloat(imageHeight))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .opacity(item.asset.flag == .reject ? 0.35 : 1)
                .overlay(alignment: .topLeading) {
                    if item.asset.flag == .reject {
                        Label("Rejected", systemImage: "xmark.circle.fill")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(.red.opacity(0.9), in: Capsule())
                            .padding(7)
                    }
                }
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        isActive ? Color.accentColor : (isSelected ? Color.accentColor.opacity(0.7) : .clear),
                        lineWidth: isActive ? 3 : 2
                    )
            }

            HStack(spacing: 5) {
                if settings.showPhotoNames {
                    Text(item.displayName)
                        .font(.caption)
                        .foregroundStyle(isActive ? .primary : .secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .accessibilityLabel(item.displayName)
                }
                Spacer(minLength: 0)
                stateBadges
            }
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let thumbnail = item.thumbnail {
            Image(nsImage: thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else if item.asset.thumbnailState == .failed {
            Rectangle()
                .fill(Color.secondary.opacity(0.12))
                .overlay {
                    Image(systemName: "photo.badge.exclamationmark")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
        } else {
            Rectangle()
                .fill(Color.secondary.opacity(0.12))
                .overlay {
                    if item.asset.thumbnailState == .loading {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "photo")
                            .font(.title2)
                            .foregroundStyle(.tertiary)
                    }
                }
        }
    }

    private var stateBadges: some View {
        HStack(spacing: 5) {
            if item.asset.rating > 0 {
                HStack(spacing: 2) {
                    Image(systemName: "star.fill")
                    Text("\(item.asset.rating)")
                }
                .foregroundStyle(.yellow)
                .accessibilityLabel("Rating \(item.asset.rating) of 5")
            }
            switch item.asset.flag {
            case .pick:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .reject:
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
            case .none:
                EmptyView()
            }
        }
        .font(.caption2.weight(.semibold))
        .frame(minWidth: 14)
    }
}

private struct LibraryGridPlaceholder: View {
    let slot: ImageCollection.PendingImportSlot

    var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.secondary.opacity(0.09))
            .overlay {
                VStack(spacing: 7) {
                    if slot.state == .pending {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "photo.badge.exclamationmark")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                    Text(slot.state == .pending ? "Importing" : "Unavailable")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(slot.state == .pending ? "Importing photo" : "Photo unavailable")
    }
}

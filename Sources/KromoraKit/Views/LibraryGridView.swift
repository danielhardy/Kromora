import AppKit
import SwiftUI

/// The grid-first browsing surface for a source collection.
///
/// `LazyVStack` is important here: the collection may contain thousands of `PhotoAsset` values, but
/// SwiftUI only hosts the rows around the viewport. Hosted cells still request a fast preview from
/// `onAppear`, and release in-flight work from `onDisappear`. That callback is not the admission
/// signal for the first screen — SwiftUI can leave visible cells unannounced until a click — so
/// the grid also admits every photo in the visible grid, originals first and edited renders
/// immediately after.
struct LibraryGridView: View {
    @Bindable var collection: ImageCollection
    let viewModel: AppViewModel
    let onOpen: () -> Void

    private let layout = LibraryGridLayout()
    private let contentPadding: Double = 16
    @State private var scrollOffset: Double = 0
    @State private var admittedThumbnailIDs: [PhotoAssetID] = []

    var body: some View {
        let _ = RenderDiagnostics.noteGridBody()
        let entries = collection.thumbnailEntries

        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                CullingBarView(viewModel: viewModel, collection: collection)
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
                // `deletionCandidates` copies asset names for the confirmation sheet. The
                // button only needs to know whether a selection exists.
                .disabled(collection.selection.selectedIDs.isEmpty && collection.selection.activeID == nil)
                .padding(.horizontal, 12)
            }
            .background(KromoraTheme.secondaryChrome)
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
                    LibraryEmptyState(collection: collection, viewModel: viewModel)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        let contentWidth = max(1, geometry.size.width - contentPadding * 2)
                        let metrics = layout.metrics(for: contentWidth)
                        let rowCount = layout.rowCount(
                            itemCount: entries.count, columns: metrics.columns
                        )
                        let visibleIDs = visibleThumbnailIDs(
                            entries: entries,
                            width: contentWidth,
                            viewportHeight: geometry.size.height
                        )
                        LazyVStack(alignment: .leading, spacing: CGFloat(layout.spacing)) {
                            ForEach(0..<rowCount, id: \.self) { row in
                                LibraryGridRow(
                                    indices: row * metrics.columns
                                        ..< min(entries.count, (row + 1) * metrics.columns),
                                    entries: entries,
                                    collection: collection,
                                    settings: viewModel.settings,
                                    cellEdge: metrics.cellEdge,
                                    spacing: layout.spacing,
                                    admittedThumbnailIDs: admittedThumbnailIDs,
                                    onSelect: select(index:),
                                    onOpen: onOpen,
                                    onAppearIndex: { viewModel.loadMorePortableIfNeeded(currentIndex: $0) }
                                )
                            }
                        }
                        .padding(CGFloat(contentPadding))
                        .background {
                            GeometryReader { proxy in
                                Color.clear.preference(
                                    key: LibraryGridScrollOffsetKey.self,
                                    value: proxy.frame(in: .named("libraryGrid")).minY
                                )
                            }
                        }
                        .frame(
                            maxWidth: .infinity,
                            minHeight: geometry.size.height,
                            alignment: .top
                        )
                        .onAppear { admitVisibleThumbnails(visibleIDs) }
                        .onChange(of: visibleIDs) { _, ids in
                            admitVisibleThumbnails(ids)
                        }
                    }
                    .coordinateSpace(name: "libraryGrid")
                    .onPreferenceChange(LibraryGridScrollOffsetKey.self) { minY in
                        let offset = max(0, -Double(minY))
                        guard abs(offset - scrollOffset) >= 24 else { return }
                        scrollOffset = offset
                    }
                    .background(KromoraTheme.windowBackground)
                }
            }
        }
        .background(KromoraTheme.windowBackground)
        .onAppear {
            RenderDiagnostics.noteGridMount()
            collection.beginThumbnailDemand()
        }
        .onDisappear { RenderDiagnostics.noteGridUnmount() }
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

    private func visibleThumbnailIDs(
        entries: [ImageCollection.ThumbnailEntry],
        width: Double,
        viewportHeight: Double
    ) -> [PhotoAssetID] {
        layout.visibleIndices(
            itemCount: entries.count,
            width: width,
            viewportHeight: viewportHeight,
            scrollOffset: scrollOffset,
            contentOrigin: contentPadding
        ).map { entries[$0].id }
    }

    private func admitVisibleThumbnails(_ ids: [PhotoAssetID]) {
        let previous = Set(admittedThumbnailIDs)
        let next = Set(ids)
        admittedThumbnailIDs = ids
        collection.beginThumbnailDemand()
        collection.requestVisibleThumbnails(for: ids)
        for id in previous.subtracting(next) {
            collection.releaseThumbnail(for: id)
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

private struct LibraryGridRow: View {
    let indices: Range<Int>
    let entries: [ImageCollection.ThumbnailEntry]
    @Bindable var collection: ImageCollection
    @ObservedObject var settings: KromoraSettings
    let cellEdge: Double
    let spacing: Double
    let admittedThumbnailIDs: [PhotoAssetID]
    let onSelect: (Int) -> Void
    let onOpen: () -> Void
    var onAppearIndex: ((Int) -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: CGFloat(spacing)) {
            ForEach(indices, id: \.self) { offset in
                let entry = entries[offset]
                if let resolved = collection.resolvedItem(for: entry) {
                    let item = resolved.item
                    LibraryGridCell(
                        item: item,
                        settings: settings,
                        isSelected: collection.selection.selectedIDs.contains(item.id),
                        isActive: collection.selection.activeID == item.id,
                        edge: cellEdge
                    )
                    .frame(width: CGFloat(cellEdge))
                    .onAppear {
                        item.markLibraryLayoutPresented()
                        // Make the cell callback order-independent: SwiftUI may deliver a child's
                        // appearance before its row's appearance. The fast preview starts here;
                        // edited renders are admitted for the whole viewport so a missing
                        // `onAppear` cannot leave a visible photo blank or unedited.
                        collection.beginThumbnailDemand()
                        collection.requestThumbnail(for: item.id, requestsEditedThumbnail: false)
                        onAppearIndex?(resolved.index)
                    }
                    .onDisappear {
                        guard !admittedThumbnailIDs.contains(item.id) else { return }
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
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct LibraryEmptyState: View {
    @Bindable var collection: ImageCollection
    @ObservedObject var viewModel: AppViewModel

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
            } else if collection.items.isEmpty {
                Text("Import photos to start a library, or try the bundled sample photos.")
                    .font(.callout)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
                HStack {
                    Button("Import photos…") { viewModel.openImageDialog() }
                        .buttonStyle(.borderedProminent)
                        .disabled(!viewModel.canImportIntoPortableLibrary)
                    Button("Try sample library") {
                        _ = viewModel.openImages(urls: StarterSampleLibrary.urls)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!viewModel.canImportIntoPortableLibrary)
                }
            }
        }
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }
}

private struct LibraryGridCell: View {
    @Bindable var item: ImageCollection.Item
    @ObservedObject var settings: KromoraSettings
    let isSelected: Bool
    let isActive: Bool
    let edge: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            thumbnail
                .frame(width: CGFloat(edge), height: CGFloat(edge))
                .clipShape(RoundedRectangle(cornerRadius: 6))
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
                if isActive || isSelected {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(
                            isActive ? KromoraTheme.primaryAccent : KromoraTheme.primaryAccent.opacity(0.7),
                            lineWidth: isActive ? 3 : 2
                        )
                }
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
                // Cells are uniform squares like the filmstrip's: every raster fills and clips,
                // so the arrival of original or edited pixels never changes the layout.
                .aspectRatio(contentMode: .fill)
                .frame(width: CGFloat(edge), height: CGFloat(edge))
                .clipped()
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

private struct LibraryGridScrollOffsetKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

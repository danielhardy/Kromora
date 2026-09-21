import SwiftUI

/// The always-visible culling surface shared by Library and Edit.
///
/// Keyboard shortcuts are fast once learned, but they are not the interface: every flag, rating,
/// and filter operation is available here with its current state visible at a glance.
struct CullingBarView: View {
    @ObservedObject var viewModel: AppViewModel
    var isCompact: Bool = false

    private var collection: ImageCollection { viewModel.collection }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: isCompact ? 6 : 10) {
                if let item = collection.selectedItem {
                    CullingSelectionControls(
                        item: item,
                        isCompact: isCompact,
                        onFlag: { flag in
                            viewModel.setFocusedFlag(flag, advance: true)
                        },
                        onRating: { rating in
                            viewModel.setFocusedRating(rating)
                        }
                    )
                } else {
                    Label("Select a photo to rate it", systemImage: "photo")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Divider()
                    .frame(height: isCompact ? 20 : 24)

                LibraryFilterControls(collection: collection, viewModel: viewModel, isCompact: isCompact)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, isCompact ? 4 : 7)
        }
        .background(KromoraTheme.secondaryChrome)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Photo culling controls")
    }
}

private struct CullingSelectionControls: View {
    @ObservedObject var item: ImageCollection.Item
    let isCompact: Bool
    let onFlag: (PhotoFlag) -> Void
    let onRating: (Int) -> Void

    var body: some View {
        HStack(spacing: isCompact ? 6 : 8) {
            Button {
                onFlag(item.asset.flag == .pick ? .none : .pick)
            } label: {
                Label(
                    "Pick",
                    systemImage: item.asset.flag == .pick ? "checkmark.circle.fill" : "checkmark.circle"
                )
            }
            .buttonStyle(.bordered)
            .controlSize(isCompact ? .small : .regular)
            .tint(item.asset.flag == .pick ? .green : .secondary)
            .help("Mark as Pick and advance (P)")
            .accessibilityValue(item.asset.flag == .pick ? "On" : "Off")

            Button {
                onFlag(item.asset.flag == .reject ? .none : .reject)
            } label: {
                Label(
                    "Reject",
                    systemImage: item.asset.flag == .reject ? "xmark.circle.fill" : "xmark.circle"
                )
            }
            .buttonStyle(.bordered)
            .controlSize(isCompact ? .small : .regular)
            .tint(item.asset.flag == .reject ? .red : .secondary)
            .help("Mark as Reject and advance (X)")
            .accessibilityValue(item.asset.flag == .reject ? "On" : "Off")

            HStack(spacing: 2) {
                ForEach(1...5, id: \.self) { rating in
                    Button {
                        onRating(rating == item.asset.rating ? 0 : rating)
                    } label: {
                        Image(systemName: rating <= item.asset.rating ? "star.fill" : "star")
                            .foregroundStyle(rating <= item.asset.rating ? .yellow : .secondary)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, isCompact ? 2 : 4)
                    .help(
                        rating == item.asset.rating
                            ? "Clear rating (0)"
                            : "Rate \(rating) stars (\(rating))"
                    )
                    .accessibilityLabel("\(rating) stars")
                    .accessibilityValue(rating == item.asset.rating ? "Selected" : "Not selected")
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Star rating, currently \(item.asset.rating) of 5")
        }
    }
}

struct LibraryFilterControls: View {
    @ObservedObject var collection: ImageCollection
    @ObservedObject var viewModel: AppViewModel
    let isCompact: Bool

    private var isPortableWindowed: Bool { collection.isPortableWindowed }

    private var currentFilter: LibraryFilter {
        isPortableWindowed ? viewModel.portableQuery.filter : collection.filter
    }

    private var countText: String {
        if let total = collection.portableTotalCount, isPortableWindowed {
            return "\(collection.items.count) of \(total)"
        }
        return "\(collection.filteredItemCount) of \(collection.items.count)"
    }

    private var isFiltered: Bool { currentFilter.isFiltered }

    var body: some View {
        HStack(spacing: isCompact ? 6 : 8) {
            Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
                .font(isCompact ? .caption2 : .caption)
                .foregroundStyle(.secondary)

            Picker("Flag filter", selection: flagBinding) {
                ForEach(LibraryFlagFilter.allCases, id: \.self) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .controlSize(isCompact ? .small : .regular)
            .focusable(false)
            .help("Filter by pick or reject status")

            Picker("Rating filter", selection: ratingBinding) {
                Text("Any rating").tag(LibraryRatingFilter.any)
                ForEach(1...5, id: \.self) { rating in
                    Text("\(rating)+ stars").tag(LibraryRatingFilter.minimum(rating))
                }
                Divider()
                ForEach(0...5, id: \.self) { rating in
                    Text("Exactly \(rating) stars").tag(LibraryRatingFilter.exact(rating))
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .controlSize(isCompact ? .small : .regular)
            .focusable(false)
            .help("Filter by star rating")

            Text(countText)
                .font(isCompact ? .caption2.monospacedDigit() : .caption.monospacedDigit())
                .foregroundStyle(.secondary)

            if isFiltered {
                Button("Clear") {
                    if isPortableWindowed {
                        viewModel.setPortableFilter(.all)
                    } else {
                        collection.clearFilter()
                    }
                }
                    .buttonStyle(.borderless)
                    .font(isCompact ? .caption2 : .caption)
                    .help("Clear culling filters")
            }
        }
    }

    private var flagBinding: Binding<LibraryFlagFilter> {
        Binding(
            get: { currentFilter.flag },
            set: { value in
                if isPortableWindowed {
                    var filter = viewModel.portableQuery.filter
                    filter.flag = value
                    viewModel.setPortableFilter(filter)
                } else {
                    var filter = collection.filter
                    filter.flag = value
                    collection.setFilter(filter)
                }
            }
        )
    }

    private var ratingBinding: Binding<LibraryRatingFilter> {
        Binding(
            get: { currentFilter.rating },
            set: { value in
                if isPortableWindowed {
                    var filter = viewModel.portableQuery.filter
                    filter.rating = value
                    viewModel.setPortableFilter(filter)
                } else {
                    var filter = collection.filter
                    filter.rating = value
                    collection.setFilter(filter)
                }
            }
        )
    }
}

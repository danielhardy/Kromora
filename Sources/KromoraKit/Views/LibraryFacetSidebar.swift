import SwiftUI

/// The optional advanced filter sidebar beside the Library grid.
///
/// Counts come from the index off the main actor and are recomputed whenever the query changes.
struct LibraryFacetSidebar: View {
    let viewModel: AppViewModel
    @State private var counts = LibraryFacetCounts()

    private var query: LibraryQuery { viewModel.portableQuery }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Filters").font(.headline)
                Spacer()
                Button("Reset") { viewModel.setPortableFacets(.none) }
                    .disabled(!query.facets.isActive)
                    .help("Clear all metadata filters")
            }
            .padding(12)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(LibraryFacet.allCases) { facet in
                        FacetSection(
                            facet: facet,
                            values: counts.counts(for: facet),
                            selected: query.facets.selected(in: facet),
                            onToggle: { value in
                                var facets = query.facets
                                facets.toggle(value, in: facet)
                                viewModel.setPortableFacets(facets)
                            }
                        )
                    }
                }
                .padding(12)
            }
        }
        .frame(width: 240)
        .background(KromoraTheme.secondaryChrome)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Metadata filters")
        .task(id: query) { counts = await viewModel.portableFacetCounts() ?? counts }
    }
}

private struct FacetSection: View {
    let facet: LibraryFacet
    let values: [LibraryFacetValueCount]
    let selected: Set<String>
    let onToggle: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(facet.title).font(.subheadline.weight(.semibold))
            if values.isEmpty {
                Text("No values").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(values) { entry in
                Toggle(isOn: Binding(
                    get: { selected.contains(entry.value) },
                    set: { _ in onToggle(entry.value) }
                )) {
                    HStack {
                        Text(entry.value).lineLimit(1).truncationMode(.middle)
                        Spacer(minLength: 4)
                        Text("\(entry.count)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.checkbox)
                .accessibilityLabel("\(entry.value), \(entry.count) photos")
            }
        }
    }
}

/// Toolbar toggle plus a one-action summary of every active Library query filter.
struct LibraryFacetToolbarControls: View {
    let viewModel: AppViewModel
    @Binding var isSidebarPresented: Bool

    var body: some View {
        HStack(spacing: 8) {
            let query = viewModel.portableQuery
            if query.hasActiveFilters {
                let parts = query.activeFilterDescriptions
                Text("\(parts.count) active filter\(parts.count == 1 ? "" : "s"): "
                    + parts.joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 260)
                    .accessibilityLabel("Active filters: " + parts.joined(separator: ", "))
                Button("Clear") { viewModel.clearPortableFilters() }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .help("Clear all filters and search")
                    .accessibilityLabel("Clear all filters")
            }
            Button {
                isSidebarPresented.toggle()
            } label: {
                Label("Filters", systemImage: isSidebarPresented
                    ? "line.3.horizontal.decrease.circle.fill"
                    : "line.3.horizontal.decrease.circle")
            }
            .buttonStyle(.bordered)
            .tint(isSidebarPresented ? KromoraTheme.primaryAccent : nil)
            .help("Show or hide the metadata filter sidebar")
            .accessibilityLabel(isSidebarPresented ? "Hide metadata filters" : "Show metadata filters")
        }
        .padding(.horizontal, 12)
    }
}

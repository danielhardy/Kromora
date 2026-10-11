import SwiftUI

/// The optional advanced filter sidebar beside the Library grid.
///
/// Counts come from the index off the main actor and are recomputed whenever the query changes.
struct LibraryFacetSidebar: View {
    let viewModel: AppViewModel
    @State private var counts = LibraryFacetCounts()

    private var query: LibraryQuery { viewModel.portableQuery }

    /// Observed bounds, widened to include an active selection so it can always be adjusted.
    private func rangeBounds(for facet: LibraryRangeFacet) -> ClosedRange<Double>? {
        let observed = counts.bounds(for: facet)
        let selected = query.facets.range(for: facet)
        guard observed != nil || selected != nil else { return nil }
        let low = min(observed?.lowerBound ?? .infinity, selected?.lower ?? .infinity)
        let high = max(observed?.upperBound ?? -.infinity, selected?.upper ?? -.infinity)
        return low...high
    }

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
                    ForEach(LibraryRangeFacet.allCases) { facet in
                        if let bounds = rangeBounds(for: facet) {
                            RangeFacetSection(
                                facet: facet,
                                bounds: bounds,
                                selection: query.facets.range(for: facet),
                                onCommit: { range in
                                    var facets = query.facets
                                    facets.setRange(range, for: facet)
                                    viewModel.setPortableFacets(facets)
                                }
                            )
                        }
                    }
                    if counts.unreadCaptureSettingsCount > 0 {
                        Text("Reading capture settings from \(counts.unreadCaptureSettingsCount) photos…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
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

/// Two sliders choosing an inclusive range. The query changes only when a drag ends, so the grid
/// does not re-filter on every tick. Photos without a value are excluded while a range is active.
private struct RangeFacetSection: View {
    let facet: LibraryRangeFacet
    let bounds: ClosedRange<Double>
    let selection: LibraryRangeSelection?
    let onCommit: (LibraryRangeSelection?) -> Void

    @State private var lower = 0.0
    @State private var upper = 0.0

    private var step: Double { facet == .aperture ? 0.1 : 1 }
    private var lowerBound: Double { bounds.lowerBound.rounded(.down) }
    private var upperBound: Double { bounds.upperBound.rounded(.up) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(facet.title).font(.subheadline.weight(.semibold))
                Spacer()
                if selection != nil {
                    Button("Clear") { onCommit(nil) }
                        .buttonStyle(.borderless)
                        .font(.caption)
                        .accessibilityLabel("Clear \(facet.title) filter")
                }
            }
            if facet == .captureDate {
                dateRangePickers
            } else if lowerBound < upperBound {
                HStack {
                    Text(facet.format(lower))
                    Spacer()
                    Text(facet.format(upper))
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                Slider(value: $lower, in: lowerBound...upperBound, step: step) { editing in
                    if !editing { commit() }
                }
                .accessibilityLabel("Minimum \(facet.title)")
                .accessibilityValue(facet.format(lower))
                Slider(value: $upper, in: lowerBound...upperBound, step: step) { editing in
                    if !editing { commit() }
                }
                .accessibilityLabel("Maximum \(facet.title)")
                .accessibilityValue(facet.format(upper))
            } else {
                Text(facet.format(lowerBound)).font(.caption).foregroundStyle(.secondary)
            }
        }
        .onAppear(perform: syncFromSelection)
        .onChange(of: selection) { syncFromSelection() }
        .onChange(of: bounds) { syncFromSelection() }
    }

    /// Day-granularity pickers clamped to the observed capture dates. Each change commits at once.
    @ViewBuilder private var dateRangePickers: some View {
        let low = LibraryRangeFacet.date(forDayNumber: lowerBound)
        let high = LibraryRangeFacet.date(forDayNumber: upperBound)
        let utc = Calendar.utcGregorian
        DatePicker(
            "From", selection: dateBinding(\.lower, fallback: lowerBound),
            in: low...high, displayedComponents: .date
        )
        .environment(\.calendar, utc).environment(\.timeZone, .gmt)
        DatePicker(
            "To", selection: dateBinding(\.upper, fallback: upperBound),
            in: low...high, displayedComponents: .date
        )
        .environment(\.calendar, utc).environment(\.timeZone, .gmt)
    }

    private func dateBinding(
        _ edge: WritableKeyPath<LibraryRangeSelection, Double>, fallback: Double
    ) -> Binding<Date> {
        Binding(
            get: { LibraryRangeFacet.date(forDayNumber: selection?[keyPath: edge] ?? fallback) },
            set: { newDate in
                let day = (newDate.timeIntervalSince1970 / 86_400).rounded(.down)
                var range = selection ?? LibraryRangeSelection(lower: lowerBound, upper: upperBound)
                range[keyPath: edge] = day
                range = LibraryRangeSelection(lower: range.lower, upper: range.upper)
                let isFull = range.lower <= lowerBound && range.upper >= upperBound
                onCommit(isFull ? nil : range)
            }
        )
    }

    private func syncFromSelection() {
        lower = selection?.lower ?? lowerBound
        upper = selection?.upper ?? upperBound
    }

    private func commit() {
        let range = LibraryRangeSelection(lower: lower, upper: upper)
        let isFull = range.lower <= lowerBound && range.upper >= upperBound
        onCommit(isFull ? nil : range)
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

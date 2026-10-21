import SwiftUI

/// The optional advanced filter sidebar beside the Library grid.
///
/// Counts come from the index off the main actor and are recomputed whenever the query changes.
struct LibraryFacetSidebar: View {
    let viewModel: AppViewModel
    @State private var counts = LibraryFacetCounts()

    private var query: LibraryQuery { viewModel.libraryPresentation.query }

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
                    .neutralActionButton()
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
        .frame(width: 280)
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
                RangeSlider(
                    lower: $lower, upper: $upper, bounds: lowerBound...upperBound, step: step,
                    lowerLabel: "Minimum \(facet.title)", upperLabel: "Maximum \(facet.title)",
                    format: facet.format, onCommit: commit
                )
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
            let query = viewModel.libraryPresentation.query
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

/// A slider with two thumbs choosing an inclusive range. `onCommit` fires when a drag ends or an
/// accessibility adjustment is made, so callers can defer expensive work until then.
private struct RangeSlider: View {
    @Binding var lower: Double
    @Binding var upper: Double
    let bounds: ClosedRange<Double>
    let step: Double
    let lowerLabel: String
    let upperLabel: String
    let format: (Double) -> String
    let onCommit: () -> Void

    /// The hit target and travel inset match AppKit's native knob, as in `NeutralOriginSlider`;
    /// the drawn disc is the same fraction of it, so this slider reads as the same control.
    private let thumbSize: CGFloat = {
        let width = (NSSlider().cell as? NSSliderCell)?.knobRect(flipped: false).width ?? 0
        return width > 0 ? width : 20
    }()
    private let trackHeight: CGFloat = 4

    private var visualThumbSize: CGFloat { thumbSize * NeutralOriginSliderCell.knobVisualScale }
    private var thumbRim: Color {
        Color(nsColor: KromoraTheme.primaryAccentNSColor
            .blended(withFraction: 0.45, of: .black) ?? KromoraTheme.primaryAccentNSColor)
    }

    var body: some View {
        GeometryReader { geometry in
            let travel = max(1, geometry.size.width - thumbSize)
            // State can lag the bounds or each other for a frame; never build an inverted range.
            let low = min(max(lower, bounds.lowerBound), bounds.upperBound)
            let high = min(max(upper, low), bounds.upperBound)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color(nsColor: .tertiaryLabelColor))
                    .frame(height: trackHeight)
                    .padding(.horizontal, thumbSize / 2)
                Capsule()
                    .fill(KromoraTheme.primaryAccent)
                    .frame(
                        width: max(0, position(high, travel) - position(low, travel)),
                        height: trackHeight
                    )
                    .offset(x: position(low, travel) + thumbSize / 2)
                thumb(value: $lower, shown: low, travel: travel, label: lowerLabel,
                      range: bounds.lowerBound...high)
                thumb(value: $upper, shown: high, travel: travel, label: upperLabel,
                      range: low...bounds.upperBound)
            }
            .frame(maxHeight: .infinity)
        }
        .frame(height: 22)
        .coordinateSpace(name: "rangeSlider")
    }

    private func position(_ value: Double, _ travel: CGFloat) -> CGFloat {
        let span = bounds.upperBound - bounds.lowerBound
        guard span > 0 else { return 0 }
        return CGFloat((value - bounds.lowerBound) / span) * travel
    }

    private func thumb(
        value: Binding<Double>, shown: Double, travel: CGFloat, label: String, range: ClosedRange<Double>
    ) -> some View {
        Circle()
            .fill(KromoraTheme.primaryAccent)
            .overlay(
                Circle().strokeBorder(thumbRim, lineWidth: max(0.75, visualThumbSize * 0.045))
            )
            .frame(width: visualThumbSize, height: visualThumbSize)
            .frame(width: thumbSize, height: thumbSize)
            .contentShape(Circle())
            .offset(x: position(shown, travel))
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named("rangeSlider"))
                    .onChanged { drag in
                        let fraction = Double((drag.location.x - thumbSize / 2) / travel)
                        let span = bounds.upperBound - bounds.lowerBound
                        let raw = bounds.lowerBound + min(max(fraction, 0), 1) * span
                        let snapped = (raw / step).rounded() * step
                        value.wrappedValue = min(max(snapped, range.lowerBound), range.upperBound)
                    }
                    .onEnded { _ in onCommit() }
            )
            .accessibilityElement()
            .accessibilityLabel(label)
            .accessibilityValue(format(shown))
            .accessibilityAdjustableAction { direction in
                let delta = direction == .increment ? step : -step
                value.wrappedValue = min(max(shown + delta, range.lowerBound), range.upperBound)
                onCommit()
            }
    }
}

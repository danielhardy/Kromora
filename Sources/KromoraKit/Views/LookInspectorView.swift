import SwiftUI

@MainActor
protocol LookPreviewProviding: AnyObject {
    var lookPreviewRevision: UInt64 { get }
    func lookPreview(for look: CubeLUT) async -> CGImage?
}

/// The empty browser has a small, explicit presentation matrix so its copy and icon stay aligned
/// across the initial, loading, unavailable-folder, and missing-reference states. Keeping this
/// decision outside the `ViewBuilder` also makes the view-level state matrix easy to exercise.
enum LookInspectorEmptyState: Equatable, Sendable {
    case scanning
    case folderUnavailable
    case missingReference
    case emptyFolder
    case firstLook
    case populated

    static func resolve(
        isScanning: Bool,
        lookCount: Int,
        folderConfigured: Bool,
        scanError: String?,
        hasMissingReference: Bool = false
    ) -> Self {
        if lookCount > 0 { return .populated }
        if isScanning { return .scanning }
        if scanError != nil { return .folderUnavailable }
        if hasMissingReference { return .missingReference }
        return folderConfigured ? .emptyFolder : .firstLook
    }

    var title: String {
        switch self {
        case .scanning: return "Scanning for Looks…"
        case .folderUnavailable: return "Look folder unavailable"
        case .missingReference: return "Look unavailable"
        case .emptyFolder: return "No Looks found"
        case .firstLook: return "Bring in your first Look"
        case .populated: return "Looks"
        }
    }

    var message: String {
        switch self {
        case .scanning:
            return "Kromora is checking the selected folder for external .cube and .look files."
        case .folderUnavailable:
            return "Choose another Look folder, or import a file from anywhere."
        case .missingReference:
            return "This photo references a Look that is no longer available. Clear the reference or import the file again."
        case .emptyFolder:
            return "Add .cube or .look files to the selected folder, or import one from anywhere."
        case .firstLook:
            return "Try a bundled starter library Look, import an external .cube or .look file, or choose a folder to browse your own Looks."
        case .populated:
            return "Browse and apply a Look."
        }
    }

    var iconName: String {
        switch self {
        case .scanning: return "arrow.triangle.2.circlepath"
        case .folderUnavailable, .missingReference: return "exclamationmark.triangle"
        case .emptyFolder: return "folder"
        case .firstLook, .populated: return "wand.and.stars"
        }
    }

    var accessibilityLabel: String { "Look inspector: \(title)" }
}

/// The one optional Look stage: a searchable, folder-aware browser for `.cube` looks and their
/// per-photo intensity. It is hosted in the editor inspector so Look is available without making
/// one a prerequisite for ordinary editing.
struct LookInspectorView: View {
    @ObservedObject var viewModel: AppViewModel
    /// Observed directly so scan/import/projection changes refresh the browser without
    /// invalidating the root `AppViewModel` observers.
    @ObservedObject private var library: LUTLibrary
    @State private var searchText = ""

    init(viewModel: AppViewModel) {
        self.viewModel = viewModel
        _library = ObservedObject(wrappedValue: viewModel.library)
    }

    private var hasLooks: Bool { !library.allLUTs.isEmpty }

    /// Keep the state exposed by the inspector's accessibility container in sync with the
    /// presentation matrix below. This is also useful to UI tests because it observes the real
    /// rendered view rather than calling the matrix in isolation.
    private var presentationState: LookInspectorEmptyState {
        LookInspectorEmptyState.resolve(
            isScanning: library.isScanning,
            lookCount: library.allLUTs.count,
            folderConfigured: library.folderURL != nil,
            scanError: library.scanError,
            hasMissingReference: viewModel.selectedLookID != nil && viewModel.selectedLook == nil
        )
    }

    private var filteredStarterLooks: [CubeLUT] {
        filteredStarterLookCategories.flatMap(\.luts)
    }

    private var filteredStarterLookCategories: [LUTLibrary.Category] {
        library.starterCategories.compactMap { category in
            let looks = filteredLooks(category.luts, collection: .starter)
            guard !looks.isEmpty else { return nil }
            return LUTLibrary.Category(
                id: category.id,
                name: category.name,
                luts: looks,
                source: category.source
            )
        }
    }

    private var filteredMyLooks: [CubeLUT] {
        filteredLooks(library.myLooks, collection: .my)
    }

    private func filteredLooks(
        _ looks: [CubeLUT], collection: LUTLibrary.LookCollectionID
    ) -> [CubeLUT] {
        guard !searchText.isEmpty else { return looks }
        let query = searchText.lowercased()
        guard !collection.title.lowercased().contains(query) else { return looks }

        // Category searches continue to surface the full matching set while category headings
        // remain visible as distinct, non-collapsible groups in the starter picker.
        let categoryLookIDs = Set(
            library.categories
                .filter { (collection.isReadOnly ? $0.source == .bundled : $0.source != .bundled)
                    && $0.name.lowercased().contains(query) }
                .flatMap(\.luts)
                .map(\.lutID)
        )
        return looks.filter {
            $0.name.lowercased().contains(query) || categoryLookIDs.contains($0.lutID)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if hasLooks {
                searchField
            }
            if let scanError = library.scanError {
                folderErrorBanner(scanError)
            }
            if let importError = library.importError {
                importErrorBanner(importError)
            }
            Divider()
            lookList
            unresolvedLookSection
            intensitySection
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Look adjustments")
        .accessibilityValue(presentationState.title)
    }

    private var header: some View {
        HStack(spacing: 8) {
            InspectorPanelHeading(title: "Looks")

            Spacer()

            Button {
                viewModel.chooseLookFile()
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Import a Look file")
            .accessibilityLabel("Import Look")

            Button {
                viewModel.refreshLooks()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Refresh Look files")

            Button {
                viewModel.presentRecipeExtractor()
            } label: {
                Image(systemName: "wand.and.stars")
            }
            .buttonStyle(.borderless)
            .help("Derive a look from a RAW and JPG")

            Button {
                viewModel.presentSaveLook()
            } label: {
                Image(systemName: "square.and.arrow.down")
            }
            .buttonStyle(.borderless)
            .disabled(viewModel.sourceImage == nil)
            .help("Save the active global edits as a Look/LUT")

            Button {
                viewModel.chooseLookFolder()
            } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(.borderless)
            .help("Choose Look folder")

            ResetIconButton(
                "Reset the Look stage",
                disabled: !viewModel.hasLookAdjustments,
                action: viewModel.resetLook
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("Search looks", text: $searchText)
                .textFieldStyle(.plain)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Clear search")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(KromoraTheme.controlBackground, in: RoundedRectangle(cornerRadius: 6))
        .onExitCommand { searchText = "" }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private var importLookButton: some View {
        Button {
            viewModel.chooseLookFile()
        } label: {
            Label(
                library.isImporting ? "Importing Look…" : "Import Look",
                systemImage: library.isImporting ? "hourglass" : "plus"
            )
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(library.isImporting)
        .help(library.isImporting ? "Importing Look…" : "Import an external .cube or .look file")
        .accessibilityLabel(library.isImporting ? "Importing Look" : "Import Look")
        .accessibilityHint(
            library.isImporting
                ? "Wait for the current Look import to finish"
                : "Choose an external cube or look file"
        )
    }

    private func folderErrorBanner(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
            .accessibilityLabel("Look folder warning: \(message)")
    }

    private func importErrorBanner(_ message: String) -> some View {
        Label(message, systemImage: "xmark.octagon")
            .font(.caption)
            .foregroundStyle(.red)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
            .accessibilityLabel("Look import error: \(message)")
    }

    private var lookList: some View {
        List(selection: selectedLookBinding) {
            Section {
                Button {
                    viewModel.selectLook(nil)
                } label: {
                    LookNoneRow(isSelected: viewModel.isLookNoneSelected)
                }
                .buttonStyle(.plain)
                .tag(nil as LUTID?)
                .listRowInsets(LookRowStyle.insets)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            } header: {
                HStack {
                    Text("Look")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(library.allLUTs.count)")
                        .font(.caption2)
                        .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                }
            }

            // The user's own Looks lead: they are the ones reached for most, and they must not sit
            // below the long starter catalogue. While searching, an empty group stays out of the way.
            if searchText.isEmpty || !filteredMyLooks.isEmpty {
            Section {
                if filteredMyLooks.isEmpty {
                    collectionEmptyRow(
                        collection: .my,
                        hasUnfilteredLooks: !library.myLooks.isEmpty
                    )
                } else {
                    lookRows(filteredMyLooks)
                }
            } header: {
                collectionHeader(.my, count: filteredMyLooks.count)
            }
            }

            if filteredStarterLookCategories.isEmpty {
                Section {
                    collectionEmptyRow(
                        collection: .starter,
                        hasUnfilteredLooks: !library.starterLooks.isEmpty
                    )
                } header: {
                    collectionHeader(.starter, count: filteredStarterLooks.count)
                }
            } else {
                ForEach(filteredStarterLookCategories) { category in
                    Section {
                        lookRows(category.luts)
                    } header: {
                        starterCategoryHeader(
                            category,
                            includesCollectionLabel: category.id == filteredStarterLookCategories.first?.id
                        )
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
    }

    @ViewBuilder
    private func lookRows(_ looks: [CubeLUT]) -> some View {
        ForEach(looks) { lut in
            Button {
                // Keep the click path ID-based. The library may replace the in-memory CubeLUT
                // during a rescan, while the document stores only this stable identity.
                viewModel.selectLook(id: lut.lutID)
            } label: {
                LookRow(
                    look: lut,
                    isSelected: viewModel.selectedLookID == lut.lutID,
                    previewProvider: viewModel
                )
            }
            .buttonStyle(.plain)
            .tag(Optional(lut.lutID))
            .listRowInsets(LookRowStyle.insets)
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        }
    }

    private func collectionHeader(
        _ collection: LUTLibrary.LookCollectionID,
        count: Int
    ) -> some View {
        HStack {
            InspectorHeading(title: collection.title, level: .section)
                .foregroundStyle(.secondary)
            if collection.isReadOnly {
                Text("Read-only")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(KromoraTheme.primaryAccent.opacity(0.12), in: Capsule())
                    .accessibilityLabel("Starter Looks, read-only")
            }
            Spacer()
            Text("\(count)")
                .font(.caption2)
                .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(collection.isReadOnly ? "Starter Looks, read-only" : "My Looks")
        .accessibilityValue("\(count) \(count == 1 ? "Look" : "Looks")")
    }

    private func starterCategoryHeader(
        _ category: LUTLibrary.Category,
        includesCollectionLabel: Bool
    ) -> some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                if includesCollectionLabel {
                    HStack(spacing: 5) {
                        InspectorHeading(title: "Starter Looks", level: .section)
                            .foregroundStyle(.secondary)
                        Text("Read-only")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(KromoraTheme.primaryAccent.opacity(0.12), in: Capsule())
                    }
                }
                InspectorHeading(title: category.name, level: .nested)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(category.luts.count)")
                .font(.caption2)
                .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            includesCollectionLabel
                ? "Starter Looks, read-only, \(category.name)"
                : "Starter Looks, \(category.name)"
        )
        .accessibilityValue("\(category.luts.count) \(category.luts.count == 1 ? "Look" : "Looks")")
    }

    @ViewBuilder
    private func collectionEmptyRow(
        collection: LUTLibrary.LookCollectionID,
        hasUnfilteredLooks: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if hasUnfilteredLooks {
                Label(
                    "No \(collection.title) match “\(searchText)”",
                    systemImage: "magnifyingglass"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            } else if collection == .my {
                Label(
                    library.isImporting ? "Importing a Look…" : "No Looks imported yet",
                    systemImage: library.isImporting ? "hourglass" : "plus"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

                Text("Import a .cube or .look file to keep it in My Looks.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                importLookButton
            } else {
                Label(
                    "No Starter Looks available",
                    systemImage: "wand.and.stars"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }

    private var selectedLookBinding: Binding<LUTID?> {
        Binding(
            get: { viewModel.selectedLookID },
            set: { viewModel.selectLook(id: $0) }
        )
    }

    private var intensitySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Intensity")
                    .font(InspectorStyle.sectionTitle)
                Spacer()
                Text("\(Int((viewModel.lookIntensity * 100).rounded()))%")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            NeutralOriginSlider(
                value: Binding(
                    get: { viewModel.lookIntensity },
                    set: { viewModel.setLookIntensity($0) }
                ),
                in: 0...1,
                // Unipolar: intensity is an amount, so 0 is both its neutral and its floor and the
                // fill runs from the left as it always did.
                neutral: 0,
                accessibilityTitle: "Look intensity",
                accessibilityReadout: "\(Int((viewModel.lookIntensity * 100).rounded())) percent",
                onEditingChanged: { editing in
                    if editing {
                        viewModel.beginPreviewInteraction()
                    } else {
                        viewModel.endPreviewInteraction()
                    }
                }
            )
            .accessibilityLabel("Look intensity")
            .accessibilityValue("\(Int((viewModel.lookIntensity * 100).rounded())) percent")
            .disabled(viewModel.selectedLook == nil)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.bar)
    }

    @ViewBuilder
    private var unresolvedLookSection: some View {
        if viewModel.selectedLookID != nil && viewModel.selectedLook == nil {
            VStack(alignment: .leading, spacing: InspectorStyle.sectionContentInset) {
                Label(
                    viewModel.lutResolutionStatus ?? "This Look is still resolving.",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

                Button("Clear Look Reference") {
                    viewModel.selectLook(nil)
                }
                .neutralActionButton()
                .controlSize(.small)
                .help("Remove the unavailable Look from this photo")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.orange.opacity(0.08))
        }
    }

}

/// Shared card chrome for Look rows: one rounded surface whose edge the thumbnail runs flush to,
/// with selection carried by the whole card (tint, hairline, checkmark) instead of a tiny marker.
private enum LookRowStyle {
    static let insets = EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0)
    static let cornerRadius: CGFloat = 8
    static let height: CGFloat = LookPreviewLayout.rowMinHeight
}

private struct LookRowCard<Leading: View>: View {
    let title: String
    let isSelected: Bool
    @ViewBuilder let leading: Leading
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 12) {
            leading
            Text(title)
                .font(.system(.body, design: .default).weight(isSelected ? .medium : .regular))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, KromoraTheme.primaryAccent)
                    .font(.system(size: 16))
                    .padding(.trailing, 12)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, minHeight: LookRowStyle.height, maxHeight: LookRowStyle.height, alignment: .leading)
        .background(
            isSelected
                ? KromoraTheme.primaryAccent.opacity(0.14)
                : Color.primary.opacity(isHovering ? 0.08 : 0.04)
        )
        .clipShape(RoundedRectangle(cornerRadius: LookRowStyle.cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: LookRowStyle.cornerRadius, style: .continuous)
                .strokeBorder(
                    isSelected ? KromoraTheme.primaryAccent.opacity(0.8) : Color.clear, lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: LookRowStyle.cornerRadius, style: .continuous))
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isSelected)
    }
}

private struct LookNoneRow: View {
    let isSelected: Bool

    var body: some View {
        LookRowCard(title: "None", isSelected: isSelected) {
            Image(systemName: "circle.slash")
                .font(.system(size: 18, weight: .light))
                .foregroundStyle(isSelected ? KromoraTheme.primaryAccent : .secondary)
                .frame(width: LookPreviewLayout.displaySize.width, height: LookRowStyle.height)
                .background(Color.primary.opacity(0.05))
        }
        .accessibilityLabel("None")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }
}

struct LookRow: View {
    let look: CubeLUT
    let isSelected: Bool
    let previewProvider: (any LookPreviewProviding)?

    init(
        look: CubeLUT,
        isSelected: Bool,
        previewProvider: (any LookPreviewProviding)? = nil
    ) {
        self.look = look
        self.isSelected = isSelected
        self.previewProvider = previewProvider
    }

    private var previewTaskID: String {
        "\(look.cacheFingerprint)-\(previewProvider?.lookPreviewRevision ?? 0)"
    }

    var body: some View {
        // The collection heading already says Starter or My Looks, so the row carries no source
        // badge; the accessibility label keeps the distinction for VoiceOver.
        LookRowCard(title: look.name, isSelected: isSelected) {
            LookPreviewThumbnail(
                look: look,
                previewProvider: previewProvider,
                taskID: previewTaskID
            )
        }
        .accessibilityLabel("\(look.name), \(look.source.accessibilityDescription)")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }
}

private struct LookPreviewThumbnail: View {
    let look: CubeLUT
    let previewProvider: (any LookPreviewProviding)?
    let taskID: String
    @State private var image: CGImage?

    private var colors: [Color] {
        look.previewSamples(count: 3).map { sample in
            Color(red: Double(sample.x), green: Double(sample.y), blue: Double(sample.z))
        }
    }

    var body: some View {
        // Full bleed: the row's rounded card clips the outer corners, so the image runs flush to the
        // leading, top, and bottom edges with no inner frame or stroke.
        Group {
            if let image {
                Image(decorative: image, scale: 1, orientation: .up)
                    .resizable()
                    .scaledToFill()
            } else {
                LookPreviewFallback(colors: colors)
            }
        }
        .frame(width: LookPreviewLayout.displaySize.width, height: LookRowStyle.height)
        .clipped()
        .accessibilityHidden(true)
        .task(id: taskID) {
            image = await previewProvider?.lookPreview(for: look)
        }
    }
}

private struct LookPreviewFallback: View {
    let colors: [Color]

    var body: some View {
        ZStack {
            LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: "photo")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
                .shadow(radius: 2)
        }
        .overlay(Color.black.opacity(0.16))
    }
}

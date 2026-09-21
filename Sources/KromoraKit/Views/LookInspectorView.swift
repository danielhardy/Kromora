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
    @State private var searchText = ""

    private var hasLooks: Bool { !viewModel.library.allLUTs.isEmpty }

    /// Keep the state exposed by the inspector's accessibility container in sync with the
    /// presentation matrix below. This is also useful to UI tests because it observes the real
    /// rendered view rather than calling the matrix in isolation.
    private var presentationState: LookInspectorEmptyState {
        LookInspectorEmptyState.resolve(
            isScanning: viewModel.library.isScanning,
            lookCount: viewModel.library.allLUTs.count,
            folderConfigured: viewModel.library.folderURL != nil,
            scanError: viewModel.library.scanError,
            hasMissingReference: viewModel.selectedLookID != nil && viewModel.selectedLook == nil
        )
    }

    private var filteredStarterLooks: [CubeLUT] {
        filteredStarterLookCategories.flatMap(\.luts)
    }

    private var filteredStarterLookCategories: [LUTLibrary.Category] {
        viewModel.library.starterCategories.compactMap { category in
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
        filteredLooks(viewModel.library.myLooks, collection: .my)
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
            viewModel.library.categories
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
            if let scanError = viewModel.library.scanError {
                folderErrorBanner(scanError)
            }
            if let importError = viewModel.library.importError {
                importErrorBanner(importError)
            }
            Divider()
            lookList
            if !viewModel.library.bundledAcknowledgement.isEmpty,
               !viewModel.library.starterLooks.isEmpty {
                starterAcknowledgement
            }
            unresolvedLookSection
            intensitySection
        }
        .frame(minWidth: 240, idealWidth: 280, maxWidth: 360)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Look adjustments")
        .accessibilityValue(presentationState.title)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Look")
                .font(.headline)
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)

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

            Button("Reset") {
                viewModel.resetLook()
            }
            .buttonStyle(.link)
            .disabled(!viewModel.hasLookAdjustments)
            .help("Reset the Look stage")
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
                viewModel.library.isImporting ? "Importing Look…" : "Import Look",
                systemImage: viewModel.library.isImporting ? "hourglass" : "plus"
            )
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(viewModel.library.isImporting)
        .help(viewModel.library.isImporting ? "Importing Look…" : "Import an external .cube or .look file")
        .accessibilityLabel(viewModel.library.isImporting ? "Importing Look" : "Import Look")
        .accessibilityHint(
            viewModel.library.isImporting
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
            } header: {
                HStack {
                    Text("Look")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(viewModel.library.allLUTs.count)")
                        .font(.caption2)
                        .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                }
            }

            if filteredStarterLookCategories.isEmpty {
                Section {
                    collectionEmptyRow(
                        collection: .starter,
                        hasUnfilteredLooks: !viewModel.library.starterLooks.isEmpty
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

            Section {
                if filteredMyLooks.isEmpty {
                    collectionEmptyRow(
                        collection: .my,
                        hasUnfilteredLooks: !viewModel.library.myLooks.isEmpty
                    )
                } else {
                    lookRows(filteredMyLooks)
                }
            } header: {
                collectionHeader(.my, count: filteredMyLooks.count)
            }
        }
        .listStyle(.sidebar)
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
        }
    }

    private func collectionHeader(
        _ collection: LUTLibrary.LookCollectionID,
        count: Int
    ) -> some View {
        HStack {
            Text(collection.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            if collection.isReadOnly {
                Text("Read-only")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.12), in: Capsule())
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
                        Text("Starter Looks")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text("Read-only")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.12), in: Capsule())
                    }
                }
                Text(category.name)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityAddTraits(.isHeader)
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
                    viewModel.library.isImporting ? "Importing a Look…" : "No Looks imported yet",
                    systemImage: viewModel.library.isImporting ? "hourglass" : "plus"
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
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

    private var starterAcknowledgement: some View {
        Text(viewModel.library.bundledAcknowledgement)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .accessibilityLabel("Starter Look acknowledgement: \(viewModel.library.bundledAcknowledgement)")
    }

    @ViewBuilder
    private var unresolvedLookSection: some View {
        if viewModel.selectedLookID != nil && viewModel.selectedLook == nil {
            VStack(alignment: .leading, spacing: 6) {
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
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Remove the unavailable Look from this photo")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.orange.opacity(0.08))
        }
    }

}

private struct LookNoneRow: View {
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 3)
                .fill(isSelected ? Color.accentColor : Color.secondary.opacity(0.3))
                .frame(width: 4, height: 20)
            Image(systemName: "circle.slash")
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
            Text("None")
                .font(.system(.body, design: .default))
            Spacer()
            if isSelected {
                Image(systemName: "checkmark")
                    .foregroundStyle(Color.accentColor)
                    .font(.caption.weight(.semibold))
            }
        }
        .contentShape(Rectangle())
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
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 3)
                .fill(isSelected ? Color.accentColor : Color.secondary.opacity(0.3))
                .frame(width: 4, height: 20)

            LookPreviewThumbnail(
                look: look,
                previewProvider: previewProvider,
                taskID: previewTaskID
            )

            Text(look.name)
                .font(.system(.body, design: .default))
                .lineLimit(1)

            Spacer()
            Text(look.source.displayName)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(Color.primary.opacity(0.08), in: Capsule())
                .accessibilityHidden(true)
            if isSelected {
                Image(systemName: "checkmark")
                    .foregroundStyle(Color.accentColor)
                    .font(.caption.weight(.semibold))
            }
        }
        .frame(minHeight: LookPreviewLayout.rowMinHeight)
        .contentShape(Rectangle())
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
        Group {
            if let image {
                Image(decorative: image, scale: 1, orientation: .up)
                    .resizable()
                    .scaledToFill()
            } else {
                LookPreviewFallback(colors: colors)
            }
        }
        .frame(width: LookPreviewLayout.displaySize.width, height: LookPreviewLayout.displaySize.height)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .overlay {
            RoundedRectangle(cornerRadius: 5)
                .stroke(.white.opacity(0.18), lineWidth: 0.5)
        }
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

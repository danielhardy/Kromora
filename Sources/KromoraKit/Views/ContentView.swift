import SwiftUI
import PhotosUI
import AppKit

/// Main window layout: sidebar + preview + toolbar.
///
/// One of two entry points KromoraKit exposes to the executable (the other is
/// `KromoraCommands`); everything else in the module stays internal.
public struct ContentView: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @StateObject private var viewModel: AppViewModel
    @Bindable private var photosImportCoordinator: PhotosImportCoordinator
    @ObservedObject private var inspectorState: AppViewModel.InspectorState
    @Bindable private var canvasState: CanvasInteractionState
    @Bindable private var collection: ImageCollection
    @Bindable private var exportCoordinator: ExportCoordinator
    @State private var photosSelection: [PhotosPickerItem] = []

    /// The window toolbar has a deliberately small crop-mode surface. Keep this as a named seam
    /// so the crop branch cannot accidentally grow the normal Edit chrome back into the workspace.
    static func toolbarMode(isCropToolActive: Bool) -> EditorToolbarMode {
        isCropToolActive ? .crop : .edit
    }

    public init() {
        let viewModel = AppViewModel(includeBundledLooks: true)
        _viewModel = StateObject(wrappedValue: viewModel)
        _photosImportCoordinator = Bindable(wrappedValue: viewModel.photosImportCoordinator)
        _inspectorState = ObservedObject(wrappedValue: viewModel.inspectorState)
        _canvasState = Bindable(wrappedValue: viewModel.canvasState)
        _collection = Bindable(wrappedValue: viewModel.collection)
        _exportCoordinator = Bindable(wrappedValue: viewModel.export)
    }

    /// Allows the application delegate to share the model that owns the persistence queue, so clean
    /// termination can flush the same edit catalog the window has been using.
    public init(viewModel: AppViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
        _photosImportCoordinator = Bindable(wrappedValue: viewModel.photosImportCoordinator)
        _inspectorState = ObservedObject(wrappedValue: viewModel.inspectorState)
        _canvasState = Bindable(wrappedValue: viewModel.canvasState)
        _collection = Bindable(wrappedValue: viewModel.collection)
        _exportCoordinator = Bindable(wrappedValue: viewModel.export)
    }

    public var body: some View {
        let _ = RenderDiagnostics.noteContentViewBody()
        return mainContent
            .navigationTitle("")
            .tint(KromoraTheme.primaryAccent)
            .toolbar {
                if #available(macOS 26.0, *) {
                    ToolbarItemGroup(placement: .primaryAction) {
                        toolbarContent
                    }
                    // The native toolbar owns the full-width surface. macOS 26 otherwise adds
                    // a separate shared glass plate behind this trailing action group.
                    .sharedBackgroundVisibility(.hidden)
                } else {
                    ToolbarItemGroup(placement: .primaryAction) {
                        toolbarContent
                    }
                }
            }
            // The inspector is a sibling column of the navigation content. Explicitly keep the
            // native window-toolbar material visible so SwiftUI paints one continuous chrome band
            // across that column too. Inspector roots stay transparent so their system material
            // starts below this band instead of owning a competing top edge.
            .toolbarBackground(.visible, for: .windowToolbar)
            .photosPicker(
                isPresented: $viewModel.isPhotosPickerPresented,
                selection: $photosSelection,
                maxSelectionCount: 50,
                matching: .images
            )
            .onChange(of: photosSelection) { _, newSelection in
                handlePhotosSelection(newSelection)
            }
            .onChange(of: photosImportCoordinator.progress) { _, newProgress in
                if newProgress == nil {
                    photosSelection = []
                }
            }
            .sheet(isPresented: Binding(
                get: { viewModel.derive.isSheetPresented },
                set: { viewModel.derive.isSheetPresented = $0 }
            )) {
                RecipeExtractorSheet(coordinator: viewModel.derive)
            }
            .sheet(isPresented: Binding(
                get: { viewModel.lookSave.isSheetPresented },
                set: { if !$0 { viewModel.dismissSaveLook() } }
            )) {
                LookSaveSheet(coordinator: viewModel.lookSave)
            }
            .sheet(isPresented: $viewModel.isRemovableMediaSelectorPresented) {
                RemovableMediaSelectorView(viewModel: viewModel)
            }
            .sheet(isPresented: $viewModel.isSelectiveCopyDialogPresented) {
                SelectiveCopySheet(
                    categories: $viewModel.selectiveCopyCategories,
                    sourceName: viewModel.sourceName,
                    onCopy: viewModel.confirmSelectiveCopy,
                    onCancel: viewModel.cancelSelectiveCopy
                )
            }
            .onAppear {
                viewModel.refreshRemovableMedia()
            }
            .modifier(KeyboardShortcuts(viewModel: viewModel))
            .modifier(MenuCommandReceivers(viewModel: viewModel))
            .alert(
                "Something went wrong",
                isPresented: Binding(
                    get: { viewModel.errorMessage != nil },
                    set: { if !$0 { viewModel.errorMessage = nil } }
                ),
                presenting: viewModel.errorMessage
            ) { _ in
                Button("OK", role: .cancel) { viewModel.errorMessage = nil }
            } message: { message in
                Text(message)
            }
            .confirmationDialog(
                viewModel.libraryDeletionConfirmation?.title
                    ?? "Remove selected photo(s) from Library?",
                isPresented: Binding(
                    get: { viewModel.libraryDeletionConfirmation != nil },
                    set: { if !$0 { viewModel.libraryDeletionConfirmation = nil } }
                ),
                titleVisibility: .visible
            ) {
                if let confirmation = viewModel.libraryDeletionConfirmation {
                    let actionTitle = confirmation.count == 1
                        ? "Delete Photo" : "Delete \(confirmation.count) Photos"
                    Button(
                        actionTitle,
                        role: .destructive
                    ) {
                        viewModel.confirmDeleteSelectedLibraryItems()
                    }
                }
                Button("Cancel", role: .cancel) {
                    viewModel.libraryDeletionConfirmation = nil
                }
            } message: {
                Text(viewModel.libraryDeletionConfirmation?.message ?? "")
            }
    }

    private func handlePhotosSelection(_ selection: [PhotosPickerItem]) {
        guard !selection.isEmpty else { return }
        photosImportCoordinator.start(
            selections: selection.enumerated().map {
                PhotosImportSelection(ordinal: $0.offset, localIdentifier: $0.element.itemIdentifier)
            },
            provider: PhotosPickerImportProvider(items: selection)
        )
    }

    private func cancelPhotosImport() {
        photosImportCoordinator.cancel()
    }

    private var mainContent: some View {
        NavigationStack {
            detailContent
        }
        .background(KromoraTheme.windowBackground)
        .inspector(isPresented: Binding(
            get: { canvasState.isCropToolActive || inspectorState.isPresented },
            set: { isPresented in
                // Crop owns the inspector for the duration of the mode.
                if !canvasState.isCropToolActive {
                    inspectorState.isPresented = isPresented
                }
            }
        )) {
            InfoInspectorView(viewModel: viewModel, inspectorState: inspectorState)
                .inspectorColumnWidth(min: 240, ideal: 280, max: 360)
        }
    }

    private var detailContent: some View {
        Group {
            if viewModel.navigation.isGrid && collection.isActive {
                VStack(spacing: 0) {
                    LibraryGridView(
                        collection: collection,
                        viewModel: viewModel,
                        onOpen: viewModel.openLibraryImageForEditing
                    )
                    StatusBar(viewModel: viewModel, photosImportCoordinator: photosImportCoordinator,
                              export: exportCoordinator, collection: collection,
                              onCancelImport: cancelPhotosImport,
                              onCancelExport: viewModel.cancelExport,
                              onCancelAuto: viewModel.cancelAutoAdjustment)
                }
            } else {
                HStack(spacing: 0) {
                    if !canvasState.isCropToolActive,
                        viewModel.isSourceBrowserPresented && !collection.items.isEmpty {
                        HStack(spacing: 0) {
                            SourceBrowserView(viewModel: viewModel)
                                .frame(width: 240)
                            Divider()
                        }
                        .transition(sourceBrowserTransition)
                    }

                    VStack(spacing: 0) {
                        PreviewView(viewModel: viewModel)

                        if collection.isActive && !canvasState.isCropToolActive {
                            VStack(spacing: 0) {
                                Divider()
                                CullingBarView(viewModel: viewModel, collection: collection, isCompact: true)
                                Divider()
                                FilmstripView(
                                    collection: collection,
                                    settings: viewModel.settings
                                ) { index, modifiers in
                                    viewModel.selectCollectionImage(at: index, modifiers: modifiers)
                                }
                                .frame(
                                    height: FilmstripLayout.stripHeight(
                                        showPhotoNames: viewModel.settings.showPhotoNames
                                    )
                                )
                            }
                            .transition(bottomChromeTransition)
                        }

                        StatusBar(
                            viewModel: viewModel,
                            photosImportCoordinator: photosImportCoordinator,
                            export: exportCoordinator,
                            collection: collection,
                            showsKeyHints: false,
                            onCancelImport: cancelPhotosImport,
                            onCancelExport: viewModel.cancelExport,
                            onCancelAuto: viewModel.cancelAutoAdjustment
                        )
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: collection.isActive)
        .animation(chromeAnimation, value: canvasState.isCropToolActive)
        .animation(chromeAnimation, value: viewModel.isSourceBrowserPresented)
        .animation(.easeInOut(duration: 0.2), value: viewModel.navigation.mode)
    }

    private var chromeAnimation: Animation? {
        accessibilityReduceMotion ? nil : .easeInOut(duration: 0.3)
    }

    private var bottomChromeTransition: AnyTransition {
        accessibilityReduceMotion
            ? .opacity
            : .move(edge: .bottom).combined(with: .opacity)
    }

    private var sourceBrowserTransition: AnyTransition {
        accessibilityReduceMotion
            ? .opacity
            : .move(edge: .leading).combined(with: .opacity)
    }

    private var toolbarContent: some View {
        Group {
            switch Self.toolbarMode(isCropToolActive: canvasState.isCropToolActive) {
            case .crop:
                CropToolbarControls(
                    viewModel: viewModel,
                    hasImage: viewModel.sourceImage != nil
                )
                .transition(.opacity)
            case .edit:
                Group {
                    Picker("Workspace", selection: Binding(
                        get: { viewModel.navigation.mode },
                        set: { viewModel.navigate(to: $0) }
                    )) {
                        ForEach(NavigationState.Mode.allCases) { mode in
                            Text(mode.title)
                                .tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 142)
                    .focusable(false)
                    .help("Library (G) or Edit (E)")

                    CanvasToolbarControls(
                        viewModel: viewModel,
                        canvasState: viewModel.canvasState,
                        hasImage: viewModel.sourceImage != nil
                    )

                    AutoToolbarButton(isInProgress: viewModel.isAutoAdjustmentInProgress) {
                        viewModel.runAutoAdjustment()
                    }
                    .accessibilityLabel("Auto photo adjustment")
                    .accessibilityHint("Analyze the source and replace global Light and Color controls; other edits remain unchanged")
                    .help(viewModel.autoAdjustmentHelp)
                    .disabled(!viewModel.canRunAutoAdjustment)

                    // Keep the comparison affordance in a stable toolbar position. The model still guards
                    // the action until a source is loaded; an untouched source is valid split-view input.
                    Button {
                        viewModel.toggleSideBySide()
                    } label: {
                        Label(
                            viewModel.isSideBySide ? "Single View" : "Side by Side",
                            systemImage: viewModel.isSideBySide ? "rectangle" : "rectangle.split.2x1"
                        )
                    }
                    .accessibilityLabel("Comparison view")
                    .accessibilityValue(viewModel.isSideBySide ? "Side by side" : "Single photo")
                    .accessibilityHint("Switch comparison view (V)")
                    .help("Switch between single-photo and side-by-side comparison (V). Hold ⌘\\ or Space to show original in single view.")
                    .disabled(!viewModel.isComparisonPresentationAvailable)

                    // Keep the editor controls on the trailing side of the toolbar. Source-folder browsing
                    // remains available from Import, while this button reveals the editor's inspector.
                    Button {
                        viewModel.toggleInspector()
                    } label: {
                        Label("Info", systemImage: "sidebar.right")
                    }
                    .accessibilityLabel("Editor sidebar")
                    .accessibilityValue(inspectorState.isPresented ? "Shown" : "Hidden")
                    .accessibilityHint("Show or hide the editor sidebar")
                    .help(inspectorState.isPresented ? "Hide the editor sidebar" : "Show the editor sidebar")
                    .disabled(viewModel.sourceImage == nil || canvasState.isCropToolActive)

                    // Keep reset scopes together and visible: the panel reset affects only the current stage,
                    // while Reset Photo clears every edit on the active source. The File menu retains the
                    // keyboard shortcut for the latter.
                    Menu {
                        Button(canvasState.isCropToolActive ? "Reset Crop" : "Reset " + inspectorState.tab.title) {
                            if canvasState.isCropToolActive {
                                viewModel.resetCrop()
                            } else {
                                viewModel.resetInspectorSection()
                            }
                        }
                        .disabled(!canvasState.isCropToolActive && inspectorState.tab == .info)

                        Divider()

                        Button("Reset Photo") {
                            viewModel.resetPhoto()
                        }
                    } label: {
                        Label("Reset", systemImage: "arrow.counterclockwise")
                    }
                    .help("Reset the current adjustment section or the whole photo")
                    .disabled(viewModel.sourceImage == nil)

                    // Import menu
                    Menu {
                        Button("Open Image...") {
                            viewModel.openImageDialog()
                        }
                        .disabled(!viewModel.canImportIntoPortableLibrary)
                        Divider()
                        Button("Import from Photos...") {
                            viewModel.importFromPhotos()
                        }
                        .disabled(!viewModel.canImportIntoPortableLibrary)
                        Button("Open Source Folder...") {
                            viewModel.chooseSourceFolder()
                        }
                        .disabled(!viewModel.canImportIntoPortableLibrary)
                        Menu("Removable Media") {
                            if viewModel.removableMediaVolumes.isEmpty {
                                Text("No supported media mounted")
                            } else {
                                ForEach(viewModel.removableMediaVolumes) { volume in
                                    Button(volume.menuLabel) {
                                        viewModel.openRemovableMedia(volume)
                                    }
                                    .disabled(!viewModel.canImportIntoPortableLibrary)
                                }
                            }
                            Divider()
                            Button("Refresh Removable Media") {
                                viewModel.refreshRemovableMedia()
                            }
                        }
                        .disabled(!viewModel.canImportIntoPortableLibrary)
                        if !collection.items.isEmpty {
                            Button("Refresh Source Folder") {
                                viewModel.refreshSource()
                            }
                        }
                        if photosImportCoordinator.progress != nil {
                            Divider()
                            Button("Cancel Photos Import") {
                                cancelPhotosImport()
                            }
                        }
                    } label: {
                        Label("Import", systemImage: "photo.on.rectangle")
                    }

                    // Export
                    Button {
                        viewModel.shareDialog()
                    } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                    // ⌘S is bound once, on the File ▸ Export menu item (KromoraApp.swift).
                    // Binding it here too gave the window two competing handlers.
                    .help("Export the graded image (⌘S)")
                    .disabled(viewModel.sourceImage == nil)
                }
                .transition(.opacity)
            }
        }
        .animation(chromeAnimation, value: canvasState.isCropToolActive)
    }
}

enum EditorToolbarMode: Equatable {
    case edit
    case crop
}

/// The Auto action changes its symbol and progress title while its work is running. Keep both
/// presentations in one layout so the widest state establishes the button footprint before the
/// state changes. The hidden presentation is still laid out, but is removed from accessibility
/// because the button supplies the stable action label and hint above.
struct AutoToolbarButton: View {
    let isInProgress: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Label("Auto…", systemImage: "hourglass")
                    .opacity(isInProgress ? 1 : 0)
                Label("Auto", systemImage: "wand.and.stars")
                    .opacity(isInProgress ? 0 : 1)
            }
            .fixedSize()
            .accessibilityHidden(true)
        }
    }
}

/// Toolbar controls backed by the narrow canvas publisher. A zoom or crop-handle update can
/// refresh this small control group without causing `ContentView`'s broad model observation to
/// participate in the interaction.
private struct CanvasToolbarControls: View {
    let viewModel: AppViewModel
    @Bindable var canvasState: CanvasInteractionState
    let hasImage: Bool

    var body: some View {
        // Crop is a committed edit, but its in-progress rectangle stays transient until Save.
        Button {
            viewModel.toggleCropTool()
        } label: {
            Label("Crop", systemImage: "crop")
        }
        .help("Crop the photo with a freeform or preset frame")
        .disabled(!hasImage)

        // Canvas navigation is presentation-only; these controls never touch the edit document.
        Menu {
            Button("Fit") { viewModel.fitCanvas() }
            Button("Fill") { viewModel.fillCanvas() }
            Divider()
            ForEach([0.25, 0.5, 1.0, 2.0, 4.0, 8.0], id: \.self) { zoom in
                Button("\(Int(zoom * 100))%") { viewModel.setCanvasZoom(CGFloat(zoom)) }
            }
            Divider()
            Button("Reset View") { viewModel.resetCanvas() }
        } label: {
            Label("\(canvasState.navigation.zoomPercent)%", systemImage: "magnifyingglass")
        }
        .help("Canvas zoom: fit, fill, or explicit zoom")
        .disabled(!hasImage)
    }
}

/// Crop owns the window toolbar while its draft is open. Undo and Redo use the normal document
/// history; applying a history state re-seeds the transient draft before a later Save.
private struct CropToolbarControls: View {
    let viewModel: AppViewModel
    let hasImage: Bool

    var body: some View {
        Button {
            viewModel.commitCrop()
        } label: {
            Label("Save", systemImage: "checkmark")
        }
        .buttonStyle(.borderedProminent)
        .accessibilityLabel("Save")
        .help("Apply the crop and return to Edit (Return)")
        .disabled(!hasImage)

        Button {
            viewModel.cancelCrop()
        } label: {
            Label("Cancel", systemImage: "xmark")
        }
        .accessibilityLabel("Cancel")
        .help("Cancel the current crop (Escape)")
        .disabled(!hasImage)

        Button {
            viewModel.undo()
        } label: {
            Label("Undo", systemImage: "arrow.uturn.backward")
        }
        .accessibilityLabel("Undo")
        .help("Undo the last committed edit")
        .disabled(!hasImage || !viewModel.canUndo)
    }
}

// The File menu, its notification names, and `MenuCommandReceivers` live in
// MenuCommands.swift.

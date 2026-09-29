import SwiftUI
import PhotosUI

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
    @AppStorage("hasSeenWelcome") private var hasSeenWelcome = false
    @State private var isWelcomePresented = false
    @State private var isTourPresented = false
    @State private var isShortcutReferencePresented = false
    @Namespace private var toolbarGlassNamespace

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
                if Self.toolbarMode(isCropToolActive: canvasState.isCropToolActive) == .edit {
                    ToolbarItem(placement: .navigation) {
                        workspaceModePicker
                    }
                    ToolbarSpacer(.fixed)
                    ToolbarItem(placement: .navigation) {
                        editToolbarPill
                    }
                    if inspectorState.isPresented {
                        ToolbarSpacer(.fixed)
                        ToolbarItem(placement: .navigation) {
                            transferToolbarPill
                        }
                    }
                }
                ToolbarSpacer(.flexible)
                if Self.toolbarMode(isCropToolActive: canvasState.isCropToolActive) == .crop {
                    ToolbarItem(placement: .primaryAction) {
                        cropToolbarPill
                    }
                } else {
                    ToolbarItem(placement: .primaryAction) {
                        viewToolbarPill
                    }
                    if !inspectorState.isPresented {
                        ToolbarSpacer(.fixed)
                        ToolbarItem(placement: .primaryAction) {
                            transferToolbarPill
                        }
                    }
                    ToolbarSpacer(.fixed)
                    ToolbarItem(placement: .primaryAction) {
                        inspectorToolbarButton
                    }
                }
            }
            .toolbarBackgroundVisibility(.visible, for: .windowToolbar)
            .toolbarBackground(.regularMaterial, for: .windowToolbar)
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
            .sheet(isPresented: $isWelcomePresented, onDismiss: { hasSeenWelcome = true }) {
                WelcomeView(
                    onImport: {
                        isWelcomePresented = false
                        Task { @MainActor in await Task.yield(); viewModel.openImageDialog() }
                    },
                    onPhotos: {
                        isWelcomePresented = false
                        Task { @MainActor in await Task.yield(); viewModel.importFromPhotos() }
                    },
                    onSamples: {
                        isWelcomePresented = false
                        _ = viewModel.openImages(urls: StarterSampleLibrary.urls)
                    },
                    onTour: {
                        isWelcomePresented = false
                        isTourPresented = true
                    },
                    onDismiss: { isWelcomePresented = false }
                )
            }
            .sheet(isPresented: $isTourPresented) {
                WorkflowTourView(onAction: { page in
                    switch page {
                    case .library: _ = viewModel.navigate(to: .grid)
                    case .edit: _ = viewModel.navigate(to: .edit)
                    case .export:
                        isTourPresented = false
                        Task { @MainActor in await Task.yield(); viewModel.shareDialog() }
                    }
                }, onDone: { isTourPresented = false })
            }
            .sheet(isPresented: $isShortcutReferencePresented) {
                KeyboardShortcutReferenceView()
            }
            .onReceive(NotificationCenter.default.publisher(for: .showKeyboardShortcuts)) { _ in
                isShortcutReferencePresented = true
            }
            .onAppear {
                viewModel.refreshRemovableMedia()
                if !hasSeenWelcome { isWelcomePresented = true }
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
            if viewModel.navigation.isGrid {
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
                        // This is a transient image browser beside the active editor, sharing
                        // selection with the filmstrip; it is not a navigation hierarchy for the
                        // Grid/Edit workspaces. Keep its independent toggle and crop-mode behavior.
                        // The window toolbar's native safe area docks it below the bar.
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
                                    settings: viewModel.settings,
                                    inspectorIsPresented: inspectorState.isPresented
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

    private var workspaceModePicker: some View {
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
    }

    private var editToolbarPill: some View {
        GlassEffectContainer(spacing: 10) {
            HStack {
                Button {
                    viewModel.toggleCropTool()
                } label: {
                    Label("Crop", systemImage: "crop")
                }
                .help("Crop the photo with a freeform or preset frame")
                .disabled(viewModel.sourceImage == nil)
                .glassEffectUnion(id: "edit", namespace: toolbarGlassNamespace)

                AutoToolbarButton(isInProgress: viewModel.isAutoAdjustmentInProgress) {
                    viewModel.runAutoAdjustment()
                }
                .accessibilityLabel("Auto photo adjustment")
                .accessibilityHint("Analyze the source and replace global Light and Color controls; other edits remain unchanged")
                .help(viewModel.autoAdjustmentHelp)
                .disabled(!viewModel.canRunAutoAdjustment)
                .glassEffectUnion(id: "edit", namespace: toolbarGlassNamespace)

                CanvasToolbarControls(
                    viewModel: viewModel,
                    canvasState: viewModel.canvasState,
                    hasImage: viewModel.sourceImage != nil
                )
                .glassEffectUnion(id: "edit", namespace: toolbarGlassNamespace)

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
                .glassEffectUnion(id: "edit", namespace: toolbarGlassNamespace)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.glass)
        }
        .transition(.opacity)
        .animation(chromeAnimation, value: canvasState.isCropToolActive)
    }

    private var viewToolbarPill: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
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
                .glassEffectUnion(id: "view", namespace: toolbarGlassNamespace)
            }
            .buttonStyle(.glass)
        }
    }

    private var inspectorToolbarButton: some View {
        Button {
            viewModel.toggleInspector()
        } label: {
            Label("Info", systemImage: "sidebar.right")
                .labelStyle(.iconOnly)
        }
        .accessibilityLabel("Editor sidebar")
        .accessibilityValue(inspectorState.isPresented ? "Shown" : "Hidden")
        .accessibilityHint("Show or hide the editor sidebar")
        .help(inspectorState.isPresented ? "Hide the editor sidebar" : "Show the editor sidebar")
        .disabled(viewModel.sourceImage == nil || canvasState.isCropToolActive)
        .buttonStyle(.glass)
    }

    private var transferToolbarPill: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
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
                .help("Import images from a file, Photos, folder, or removable media")
                .glassEffectUnion(id: "transfer", namespace: toolbarGlassNamespace)

                Button {
                    viewModel.shareDialog()
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .disabled(viewModel.sourceImage == nil)
                // ⌘S remains bound only to the File ▸ Export menu item.
                .help("Export the graded image (⌘S)")
                .glassEffectUnion(id: "transfer", namespace: toolbarGlassNamespace)
            }
            .buttonStyle(.glass)
        }
    }

    private var cropToolbarPill: some View {
        GlassEffectContainer(spacing: 10) {
            CropToolbarControls(
                viewModel: viewModel,
                hasImage: viewModel.sourceImage != nil,
                glassNamespace: toolbarGlassNamespace
            )
            .buttonStyle(.glass)
        }
        .transition(.opacity)
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
        .accessibilityLabel("Canvas zoom")
        .accessibilityValue("\(canvasState.navigation.zoomPercent)%")
        .disabled(!hasImage)
    }
}

/// Crop owns the window toolbar while its draft is open. Undo and Redo use the normal document
/// history; applying a history state re-seeds the transient draft before a later Save.
private struct CropToolbarControls: View {
    let viewModel: AppViewModel
    let hasImage: Bool
    let glassNamespace: Namespace.ID

    var body: some View {
        Button {
            viewModel.commitCrop()
        } label: {
            Label("Save", systemImage: "checkmark")
        }
        .buttonStyle(.glassProminent)
        .accessibilityLabel("Save")
        .help("Apply the crop and return to Edit (Return)")
        .disabled(!hasImage)
        .glassEffectUnion(id: "crop", namespace: glassNamespace)

        Button {
            viewModel.cancelCrop()
        } label: {
            Label("Cancel", systemImage: "xmark")
        }
        .accessibilityLabel("Cancel")
        .help("Cancel the current crop (Escape)")
        .disabled(!hasImage)
        .glassEffectUnion(id: "crop", namespace: glassNamespace)

        Button {
            viewModel.undo()
        } label: {
            Label("Undo", systemImage: "arrow.uturn.backward")
        }
        .accessibilityLabel("Undo")
        .help("Undo the last committed edit")
        .disabled(!hasImage || !viewModel.canUndo)
        .glassEffectUnion(id: "crop", namespace: glassNamespace)
    }
}

// The File menu, its notification names, and `MenuCommandReceivers` live in
// MenuCommands.swift.

import SwiftUI

/// Presents the derive, Look-save and removable-media sheets by observing those coordinators
/// directly, so their presentation and progress changes never invalidate `ContentView` or the
/// root `AppViewModel` observers. Ownership stays with `AppViewModel`; this only holds references.
struct FeatureSheetsModifier: ViewModifier {
    let viewModel: AppViewModel
    @Bindable var derive: DeriveCoordinator
    let lookSave: LookSaveCoordinator
    @Bindable var media: LibraryMediaWorkflowCoordinator

    init(viewModel: AppViewModel) {
        self.viewModel = viewModel
        derive = viewModel.derive
        lookSave = viewModel.lookSave
        media = viewModel.libraryMediaWorkflow
    }

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $derive.isSheetPresented) {
                RecipeExtractorSheet(coordinator: derive)
            }
            .sheet(isPresented: Binding(
                get: { lookSave.isSheetPresented },
                set: { if !$0 { viewModel.dismissSaveLook() } }
            )) {
                LookSaveSheet(coordinator: lookSave)
            }
            .sheet(isPresented: $media.isRemovableMediaSelectorPresented) {
                RemovableMediaSelectorView(viewModel: viewModel, media: media)
            }
    }
}

/// The Import ▸ Removable Media submenu, observing the media workflow directly.
struct RemovableMediaMenu: View {
    let viewModel: AppViewModel
    let media: LibraryMediaWorkflowCoordinator

    var body: some View {
        Menu("Removable Media") {
            if media.removableMediaVolumes.isEmpty {
                Text("No supported media mounted")
            } else {
                ForEach(media.removableMediaVolumes) { volume in
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
    }
}

/// Presents the selective-copy sheet by observing the edit clipboard directly, so dialog and
/// category changes never invalidate `ContentView` or the root `AppViewModel` observers.
struct SelectiveCopySheetModifier: ViewModifier {
    let viewModel: AppViewModel

    func body(content: Content) -> some View {
        @Bindable var clipboard = viewModel.editClipboardWorkflow
        return content.sheet(isPresented: $clipboard.isSelectiveCopyDialogPresented) {
            SelectiveCopySheet(
                categories: $clipboard.selectiveCopyCategories,
                sourceName: clipboard.selectiveCopySource?.name ?? viewModel.sourceName,
                onCopy: clipboard.confirmSelectiveCopy,
                onCancel: clipboard.cancelSelectiveCopy
            )
        }
    }
}

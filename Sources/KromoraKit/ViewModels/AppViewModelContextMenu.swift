import Foundation

private struct ContextMenuStoredEditsUnavailable: LocalizedError {
    let status: EditDocumentStore.Status

    var errorDescription: String? {
        switch status {
        case .ready, .relinked:
            nil
        case .opening:
            "The library is still opening."
        case .corrupt(let detail):
            "Could not read this photo's saved edits (\(detail))."
        case .packageFailure(let detail):
            "Could not read this photo's saved edits from the library (\(detail))."
        case .writeFailure(let detail):
            "Could not verify this photo's saved edits (\(detail))."
        }
    }
}

// KRMA-1080: the photo context menu's target resolution and action routing. Every action delegates
// to the existing library, edit-clipboard, export, virtual-copy, and deletion owners.
extension AppViewModel {
    /// Where the context menu was opened, which decides how selection is retargeted.
    private func contextTarget(for id: PhotoAssetID) -> LibraryContextTarget {
        .resolve(
            contextID: id, selectedIDs: collection.selection.selectedIDs,
            activeID: collection.selection.activeID)
    }

    /// Menu enablement for the photo under the pointer, as it will be once the pointer's photo has
    /// become the target.
    func libraryContextMenuState(for id: PhotoAssetID) -> LibraryContextMenuState {
        let item = collection.items.first { $0.id == id }
        var state = LibraryContextMenuState(target: contextTarget(for: id))
        state.isLibraryReady = canImportIntoPortableLibrary
        state.isGrid = navigation.isGrid
        state.isExportBusy = isExporting
        state.canPaste = canPasteEdits
        state.isPackagePhoto = portableLibrary != nil && item != nil
        state.isCreatingVirtualCopy = isCreatingVirtualCopy
        return state
    }

    /// A right-click on an unselected photo makes it the sole target; one inside the selection keeps
    /// the selection. Opening a menu never opens the photo from the Library.
    func retargetLibrarySelection(toContext id: PhotoAssetID) {
        guard contextTarget(for: id).replacesSelection,
              let index = collection.items.firstIndex(where: { $0.id == id }) else { return }
        if collection.isPortableWindowed {
            selectPortableItem(at: index)
        } else {
            collection.select(at: index)
        }
    }

    /// Runs a context-menu action on the photo it was opened for. The target is resolved here, at
    /// delivery time, so an action never lands on a different photo than the one the menu named.
    func performLibraryContextAction(_ action: LibraryContextAction, on id: PhotoAssetID) {
        guard let item = collection.items.first(where: { $0.id == id }) else {
            presentError("This photo is no longer in the Library view.")
            return
        }
        let state = libraryContextMenuState(for: id)
        if let reason = state.disabledReason(for: action) {
            statusMessage = reason
            return
        }
        retargetLibrarySelection(toContext: id)
        switch action {
        case .openInEdit:
            openLibraryImageForEditing(assetID: id)
        case .copyImage:
            exportWorkflow.copySelectedImages()
        case .copyEditSettings:
            editClipboardWorkflow.presentSelectiveCopyDialog(
                for: EditSourceReference(
                    assetID: id, portableIdentity: item.asset.source.portableIdentity, url: item.url),
                name: item.displayName)
        case .pasteEditSettings:
            pasteEdits()
        case .createVirtualCopy:
            createVirtualCopy(of: item)
        case .setFlag(let flag):
            _ = setFocusedFlag(flag)
        case .setRating(let rating):
            _ = setFocusedRating(rating)
        case .export:
            exportDialog()
        case .share:
            exportWorkflow.shareSelectedPhotos()
        case .deleteFromLibrary:
            requestDeleteSelectedLibraryItems()
        }
    }

    /// Duplicates the photo under the pointer. The open photo uses its live document; any other
    /// photo is copied from its durable edit, and the library is reloaded without opening the copy.
    private func createVirtualCopy(of item: ImageCollection.Item) {
        guard let portableLibrary else {
            statusMessage = "Virtual copies are available for photos in a Kromora library"
            return
        }
        let reference = EditSourceReference(
            assetID: item.id, portableIdentity: item.asset.source.portableIdentity, url: item.url)
        if reference == activeSourceReference {
            createVirtualCopy()
            return
        }
        editHistory.createVirtualCopy(
            of: reference,
            storedDocument: { [editStore] in
                let result = await editStore.load(for: reference)
                switch result.status {
                case .ready, .relinked:
                    return result.document
                default:
                    throw ContextMenuStoredEditsUnavailable(status: result.status)
                }
            },
            makeCopy: {
                let copy = try await portableLibrary.createVirtualCopy(of: reference.portableAssetID)
                return .init(
                    sourceReference: EditSourceReference(
                        portableIdentity: copy.identity,
                        assetID: PhotoAssetID(rawValue: "portable:\(copy.assetID.raw)")
                    ),
                    displayName: copy.displayName,
                    assetID: copy.assetID
                )
            },
            didCreate: { [weak self] copy in
                guard let self else { return }
                try self.libraryBrowsingCoordinator.reloadPortableCollection()
                self.statusMessage = "Created virtual copy ‘\(copy.displayName)’"
            }
        )
    }
}

import Foundation

/// Status-bar text and the hard-failure alert message. Split from `AppViewModel` so a status
/// update re-evaluates only the views that read `message`.
@MainActor
@Observable
final class StatusState {
    var message = "Open an image to get started"
    /// Non-nil when a hard failure should be surfaced as a dismissible alert in `ContentView`.
    var errorMessage: String?
}

/// Library browsing presentation: the portable filter/sort/search authority, package-import
/// progress, and the destructive-action confirmation. A query change never touches `StatusState`.
@MainActor
@Observable
final class LibraryPresentationState {
    var query = LibraryQuery.all
    private(set) var importProgress: PortablePackageImportProgress?
    /// The model owns the immutable target snapshot so a late selection change cannot redirect a
    /// destructive action.
    var deletionConfirmation: LibraryDeletionConfirmation?

    func setImportProgress(_ progress: PortablePackageImportProgress?) { importProgress = progress }
}

/// Picker and panel visibility owned by the window chrome.
@MainActor
@Observable
final class ChromePresentationState {
    var isPhotosPickerPresented = false
    /// Source-folder file browser panel visibility.
    var isSourceBrowserPresented = false
    /// Compatibility shim for callers that still mention the retired modal sheet.
    var isMaskingPanelPresented = false
}

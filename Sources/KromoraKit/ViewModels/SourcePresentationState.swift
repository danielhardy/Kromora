/// Presentation readiness for the selected photo's source-loading lifecycle.
///
/// The dimensions are deliberately independent: source preparation can finish while the first
/// frame is still pending, the inspector's stored document can lag source selection, and the
/// toolbar keeps its last settled availability while another photo loads. This value stores only
/// that readiness. The `ImageSource`, render surfaces, active `EditDocument` and generation
/// fences remain with their owners; callers check the current request before invoking a
/// transition. `AppViewModel` is the sole main-actor owner and exposes read-only projections.
///
/// After `shutDown()` every transition is a no-op, so a late completion cannot revive state.
struct SourcePresentationState: Equatable, Sendable {
    /// Source selection or preparation is in flight and no usable source exists yet.
    private(set) var isLoading = false
    /// Navigation waits only until the selected source has a usable frame on the surface.
    private(set) var isNavigationLoading = false
    private(set) var previewState: AppViewModel.PreviewState = .empty
    /// A cold photo-to-photo selection is waiting for its stored edit document.
    private(set) var isInspectorDocumentPending = false
    private(set) var toolbarActionsAvailable = false
    private(set) var isToolbarTransitioning = false
    private(set) var isShutDown = false

    /// A photo was selected (or its placeholder record is resolving): every stage restarts.
    mutating func beginSelection() {
        guard !isShutDown else { return }
        isToolbarTransitioning = true
        isLoading = true
        isNavigationLoading = true
        previewState = .loading
    }

    /// The toolbar holds its settled appearance until this photo publishes or fails.
    mutating func beginToolbarTransition() {
        guard !isShutDown else { return }
        isToolbarTransitioning = true
    }

    mutating func setInspectorDocumentPending(_ pending: Bool) {
        guard !isShutDown else { return }
        isInspectorDocumentPending = pending
    }

    /// The stored document was adopted or rejected; the inspector stops holding its values.
    mutating func inspectorDocumentSettled() {
        guard !isShutDown else { return }
        isInspectorDocumentPending = false
    }

    /// Source preparation was handed to the session; the old frame may still be on screen.
    mutating func beginSourcePreparation() {
        guard !isShutDown else { return }
        isLoading = true
        isNavigationLoading = true
    }

    /// A render of the retained source was requested; pixels are pending.
    mutating func markPreviewLoading() {
        guard !isShutDown else { return }
        previewState = .loading
    }

    /// Source preparation finished; the first rendered frame may still be pending.
    mutating func sourcePrepared() {
        guard !isShutDown else { return }
        previewState = .loading
        isLoading = false
    }

    /// A provisional or exact frame is on the surface, so navigation no longer waits.
    mutating func firstFramePresented() {
        guard !isShutDown else { return }
        isNavigationLoading = false
    }

    /// A rendered frame settled for the selected source.
    mutating func previewReady() {
        guard !isShutDown else { return }
        isNavigationLoading = false
        previewState = .ready
        toolbarActionsAvailable = true
        isToolbarTransitioning = false
    }

    /// A render failed. `hasSource` keeps toolbar actions available for a prepared source.
    mutating func previewFailed(hasSource: Bool) {
        guard !isShutDown else { return }
        isNavigationLoading = false
        previewState = .failed
        toolbarActionsAvailable = hasSource
        isToolbarTransitioning = false
    }

    /// Source preparation failed for the current request.
    mutating func sourceFailed(hasSource: Bool) {
        guard !isShutDown else { return }
        isLoading = false
        isInspectorDocumentPending = false
        previewFailed(hasSource: hasSource)
    }

    /// A direct open failed before any source request existed.
    mutating func openFailed() {
        guard !isShutDown else { return }
        isLoading = false
        previewState = .failed
    }

    /// A selection stopped without publishing a source (record resolution ended or failed). A
    /// non-nil `previewState` also settles the preview; nil leaves it for the failure path.
    mutating func endSelection(previewState settled: AppViewModel.PreviewState? = nil) {
        guard !isShutDown else { return }
        isToolbarTransitioning = false
        isLoading = false
        isNavigationLoading = false
        if let settled { previewState = settled }
    }

    /// The source was cleared (return to an empty editor, or the active photo was removed).
    mutating func clear() {
        guard !isShutDown else { return }
        self = SourcePresentationState()
    }

    mutating func shutDown() {
        isNavigationLoading = false
        isShutDown = true
    }
}

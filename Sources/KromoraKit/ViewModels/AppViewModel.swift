import AppKit
import Combine
import CoreImage
import Foundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

struct MediaVolumeImportProgress: Equatable, Sendable {
    let total: Int
    var processed: Int
    var imported: Int
    var skipped: Int
    var currentName: String?
    var cancelled: Bool

    var fraction: Double {
        guard total > 0 else { return 1 }
        return min(1, Double(processed) / Double(total))
    }
}

struct LibraryDeletionConfirmation: Identifiable, Equatable, Sendable {
    let id = UUID()
    let candidates: [ImageCollection.DeletionCandidate]

    var count: Int { candidates.count }
    var title: String {
        count == 1 ? "Remove photo from Library?" : "Remove \(count) photos from Library?"
    }
    var message: String {
        let names = candidates.map(\.displayName).joined(separator: ", ")
        let suffix =
            candidates.contains(where: { !$0.isManaged })
            ? " Original files outside Kromora's managed library will be kept."
            : " Managed originals will be moved to the macOS Trash."
        return "\(names).\(suffix)"
    }
}

struct LibraryDeletionResult: Equatable, Sendable {
    let deletedIDs: [PhotoAssetID]
    let failures: [String]

    var deletedCount: Int { deletedIDs.count }
    var succeeded: Bool { !deletedIDs.isEmpty && failures.isEmpty }
}

/// Lifecycle state for the source-statistics-driven Auto action.
enum AutoAdjustmentState: Equatable, Sendable {
    case unavailable(String)
    case ready
    case analyzing
    case renderingCandidates
    case validating
    case applying
    case cancelled
    case failed(String)

    var message: String {
        switch self {
        case .unavailable(let message), .failed(let message): return message
        case .ready:
            return
                "Analyze the source and replace global Light and Color with a conservative baseline."
        case .analyzing: return "Analyzing the source for Auto adjustments…"
        case .renderingCandidates: return "Rendering Auto candidates…"
        case .validating: return "Validating Auto candidates…"
        case .applying: return "Applying Auto adjustments…"
        case .cancelled: return "Auto cancelled; nothing was changed."
        }
    }
}

/// The outcome of attempting to make all queued edit snapshots durable.
public enum PersistenceFlushResult: Equatable, Sendable {
    case success
    case failure(String)
    case cancelled

    public var succeeded: Bool {
        if case .success = self { return true }
        return false
    }
}

/// Central state for the Kromora app.
@MainActor
public final class AppViewModel: ObservableObject, LookPreviewProviding, PhotosImportDestination {

    /// Inspector presentation state has its own observation boundary. The editor model still
    /// owns histogram scheduling and tab validity, but changing the inspector chrome does not
    /// need to publish through the model observed by the library and canvas shells.
    @MainActor
    final class InspectorState: ObservableObject {
        @Published var isPresented = false
        @Published var tab: InspectorTab = .info

        /// Masking is an inspector tab, not a second presentation mode. Keep the previous tab so
        /// Done/Escape can return to the edit control the user came from.
        private var tabBeforeMasking: InspectorTab = .info

        /// Compatibility access for masking commands and tests. `tab` remains the one source of
        /// truth for which inspector surface is active; changing this value only translates the
        /// old presentation vocabulary into a tab transition.
        var isMaskingWorkspacePresented: Bool {
            get { tab == .masking }
            set {
                if newValue {
                    if tab != .masking { tabBeforeMasking = tab }
                    tab = .masking
                } else if tab == .masking {
                    tab = tabBeforeMasking
                }
            }
        }

        func select(_ requestedTab: InspectorTab) {
            if requestedTab == .masking, tab != .masking {
                tabBeforeMasking = tab
            }
            tab = requestedTab
        }
    }

    // MARK: - Published state

    @Published var sourceImage: CIImage?
    @Published var sourceName: String = ""
    @Published var sourceSize: CGSize = .zero
    @Published var sourceURL: URL?

    /// Identity shown by Inspect. Resolve through the durable collection record so Photos names
    /// and the library/filmstrip naming convention remain consistent during source navigation.
    var currentPhotoName: String {
        if let activeAssetID,
            let item = collection.items.first(where: { $0.id == activeAssetID })
        {
            return item.asset.displayName
        }
        let value = sourceName.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty
            ? "Untitled" : URL(fileURLWithPath: value).deletingPathExtension().lastPathComponent
    }

    var currentPhotoFileType: String {
        if let activeAssetID,
            let item = collection.items.first(where: { $0.id == activeAssetID })
        {
            return item.asset.displayFileType
        }
        if let sourceURL, !sourceURL.pathExtension.isEmpty {
            return sourceURL.pathExtension.uppercased()
        }
        if case .data(let data) = imageSource?.backing,
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            let identifier = CGImageSourceGetType(source),
            let type = UTType(identifier as String),
            let preferredExtension = type.preferredFilenameExtension
        {
            return preferredExtension.uppercased()
        }
        return "Unknown"
    }

    /// **The look, as a value.** Phase 2's spine: everything the user has chosen lives here, and the
    /// preview is rebuilt from it rather than from a baked image (`docs/ENGINEERING_GUIDE.md`).
    ///
    /// Stored in a per-photo session keyed by stable source identity. Navigation restores the active
    /// photo's Light, other edits, and history without carrying them onto a different frame.
    @Published private(set) var document = EditDocument()

    /// The last copied value-state payload. It contains no image or rendered data, so it remains
    /// safe to apply to several destinations and keeps future selective-copy UI on one stable seam.
    /// Compatibility projection for the editor coordinator's value-only clipboard. The
    /// coordinator is the single owner; AppViewModel only exposes the historical API to views and
    /// commands.
    var editClipboard: EditClipboardPayload? { editorDocument.clipboard }

    var canPasteEdits: Bool { editorDocument.canPaste }

    /// The most recent persistence warning. A damaged edit catalog must not prevent the source
    /// image from opening, but it should remain visible to the user.
    @Published private(set) var editStoreStatus: String?

    /// Compatibility diagnostics for the application boundary. Persistence accounting is owned by
    /// `EditPersistenceCoordinator`; these accessors keep existing integrations and tests stable.
    var pendingPersistenceCount: Int { persistence.pendingCount }
    var peakPendingPersistenceCount: Int { persistence.peakPendingCount }

    /// How to reproduce the open image. Held instead of a decoded `CIImage` because a RAW has to be
    /// re-developed to honour `document.rawDevelop` (§4.2).
    private var imageSource: ImageSource?

    /// What the open image's RAW decoder can do, and where its own defaults sit. `nil` for a
    /// standard image, which has no develop stage at all — **and also `nil` while the probe is still
    /// running on a RAW**, which is why the panel switches on `developPanelState` rather than on
    /// this. See that property.
    ///
    /// Probed once per open rather than per render: the probe builds a `CIRAWFilter`, which measures
    /// ~25 ms on a 30 MB DNG. Not memoized across images — one entry would save that on returning to
    /// an image, at the cost of another cache whose invalidation nobody will remember.
    @Published private(set) var rawCapabilities: RAWCapabilities?

    /// Whether the capability answer belongs to the currently selected source. This is separate
    /// from `rawCapabilities == nil`: a RAW can still be probing, or its decoder can answer that it
    /// has no actionable develop controls.
    @Published private(set) var capabilitiesProbeCompleted = false

    /// What the develop panel should be showing right now. The probe state is distinct from a
    /// completed answer that offers no usable controls.
    ///
    /// `rawCapabilities` is nil while probing and can also be nil after a decoder answers that it
    /// has no actionable controls. `refreshCapabilities()` clears it synchronously on every open
    /// and refills it 25–170 ms later, so a RAW opened with the Develop tab already showing retains an
    /// honest loading state instead of briefly claiming "No develop stage". When a new source makes
    /// the active tab unavailable, navigation repairs the selection to Info.
    ///
    /// Deriving the state here rather than in the view is what makes it testable: this repo has no
    /// SwiftUI view tests, so a distinction that lives only in a `ViewBuilder` cannot be asserted.
    /// `DevelopInspectorView` is a `switch` over this value and nothing else.
    ///
    /// This — rather than a widened `imageSource` — is the whole of what the panel needs from the
    /// source: not the backing bytes, not the native extent, only whether a develop stage exists at
    /// all. See `sourceIsRAW` for the widening that does happen, and why it is a `Bool`.
    var developPanelState: DevelopPanelState {
        guard sourceImage != nil, sourceIsRAW else { return .noDevelopStage }
        return DevelopPanelState(
            sourceIsRAW: sourceIsRAW,
            capabilities: rawCapabilities,
            probeCompleted: capabilitiesProbeCompleted
        )
    }

    /// Whether the open image goes through the RAW decoder at all.
    ///
    /// **Widened from `private` deliberately, and narrowly.** `imageSource` itself stays `private`:
    /// the develop panel has no business with the backing bytes or the native extent, and the one
    /// fact it needs — is there a decode stage that could offer develop controls — is a `Bool`.
    /// Publishing the `Bool` instead of the struct keeps the reason for the widening legible and
    /// stops anything else reaching through it. It is also the input the state mapping is tested
    /// against directly.
    ///
    /// Not `@Published`: it only ever changes inside `load()`, which writes several `@Published`
    /// properties in the same main-actor turn (`sourceImage` among them), so any view observing this
    /// view model is already being invalidated when it moves.
    var sourceIsRAW: Bool { imageSource?.kind == .raw }

    /// The states of the develop panel. See `AppViewModel.developPanelState`.
    enum DevelopPanelState: Equatable, Sendable {
        /// Not a RAW (or nothing open): there is no develop stage to offer, and saying so is honest.
        case noDevelopStage
        /// A RAW whose capability probe has not landed yet. The controls are coming, so the panel
        /// must not claim there are none.
        case probing
        /// A RAW, probed. The panel draws `capabilities.availableControls`.
        case ready(RAWCapabilities)

        /// A RAW decoder answered, but did not offer anything this panel can edit.
        case noSupportedControls

        var offersDevelopTab: Bool {
            switch self {
            case .probing:
                return true
            case .ready(let capabilities):
                return !capabilities.availableControls.isEmpty
            case .noDevelopStage, .noSupportedControls:
                return false
            }
        }

        /// Preserve the original two-input mapping for callers that use it as a pure pre-probe
        /// state table. Production uses the overload below once it has an explicit completion bit.
        init(sourceIsRAW: Bool, capabilities: RAWCapabilities?) {
            if let capabilities {
                self = .ready(capabilities)
            } else {
                self = sourceIsRAW ? .probing : .noDevelopStage
            }
        }

        /// **The mapping, in one place, as a pure function.** A completed RAW answer of `nil` is
        /// not allowed to remain in `.probing`.
        init(sourceIsRAW: Bool, capabilities: RAWCapabilities?, probeCompleted: Bool) {
            if !sourceIsRAW {
                self = .noDevelopStage
                return
            }
            guard probeCompleted || capabilities != nil else {
                self = .probing
                return
            }
            guard let capabilities else {
                self = .noSupportedControls
                return
            }
            self =
                capabilities.availableControls.isEmpty
                ? .noSupportedControls
                : .ready(capabilities)
        }
    }

    /// Tabs for the current image. Develop remains visible during a RAW capability probe so the
    /// picker can honestly expose the loading state, but it disappears for standard images and for
    /// RAW decoders with no actionable controls.
    var availableInspectorTabs: [InspectorTab] {
        InspectorTab.availableTabs(
            hasImage: sourceImage != nil,
            developPanelState: developPanelState,
            hasMaskingTarget: maskingAssetID != nil
        )
    }

    private var activeAssetID: PhotoAssetID?
    private var activeSourceReference: EditSourceReference?
    /// Source generation prevents delayed work from a previous navigation selection from publishing
    /// into the new image, even if the source values happen to compare equal.
    var sourceRevision: UInt64 { sourceSession.sourceRevision }
    /// Document generation guards the primary visible render and histogram publications.
    private var documentRevision: UInt64 = 0
    /// Display generation guards histogram work against a newer request, including comparison
    /// mode and render-scale changes that do not change the edit document.
    var displayRevision: UInt64 { previewPresentation.displayRevision }
    /// Baseline generation changes when the source or a comparison-frame stage (develop/crop)
    /// changes. Look-stage edits and RAW white-balance Temperature/Tint must not invalidate an
    /// in-flight baseline that is still correct.
    var comparisonRevision: UInt64 { previewPresentation.comparisonRevision }
    /// Presentation-only snapshot of the before image. `EditDocument.originalForComparison` is a
    /// useful value projection, but it is derived from the live document; RAW Temperature/Tint are
    /// part of `rawDevelop` and would therefore mutate that projection during a slider gesture.
    /// Keeping the snapshot outside the persisted edit document lets ordinary Temperature/Tint edits
    /// remain undoable without moving the comparison reference.
    private var comparisonBaselineDocument = EditDocument().comparisonBaseline
    /// The baseline revision already queued or published for the Original surface. A visible
    /// adjusted render can follow every Temperature/Tint tick, but it must not enqueue the same
    /// Original request again when the baseline revision is unchanged.
    private var comparisonPreviewScheduledRevision: UInt64?
    /// A failed Original render gets one retry after the scheduler has retired the failed attempt.
    /// The revision key prevents a persistent renderer failure from spinning the editor lane.
    private var comparisonPreviewRetriedRevision: UInt64?
    private var comparisonPreviewRetryTask: Task<Void, Never>?
    /// The last settled request confirmed by the presentation surface. Supporting work is never
    /// admitted before this lifecycle boundary.
    private var lastPresentedVisibleRequest: RenderRequest?
    /// The completed image belonging to `lastPresentedVisibleRequest`. Keeping the value alongside
    /// the request lets a later Info-tab open use the frame that was actually presented without
    /// asking the renderer to reconstruct it.
    private var lastPresentedVisibleImage: CIImage?
    /// The newest settled request accepted by the preview surface. Mode entry may use this current
    /// candidate before drawable confirmation, but it must never fall back to an older document.
    private var lastPublishedVisibleRequest: RenderRequest?
    private var isPreviewInteractionActive = false

    /// Whether any call since the last fired render changed a comparison-frame stage.
    ///
    /// A coalesced burst of edits accumulates this flag while the preview coordinator keeps only the
    /// newest visible request. A baseline is released after that settled visible request, so an
    /// earlier develop/crop edit in the burst is not lost when a later tick supersedes its value.
    private var pendingDevelopChange = false

    /// LUTs a document can reference that no folder scan produces — a freshly derived LUT, and the
    /// file it becomes once saved. See `DerivedLUTRegistry`; this is the Step 9 replacement for the
    /// single `scratchLUT` slot that stood here.
    private var derivedRegistry = DerivedLUTRegistry()

    /// The selected Look resolved from the active photo's persisted `LUTID`. Resolution is
    /// deliberately fresh: a library rescan may replace the in-memory `CubeLUT`, but it must not
    /// change the document's reference (§4.3).
    var selectedLook: CubeLUT? { resolvedLUT(document.lut.lutID) }

    /// The active photo's persisted Look strength.
    var lookIntensity: Double { document.lut.intensity }

    /// Compatibility seam for render and test callers that still use the model's historical LUT
    /// name. The user-facing editor is routed through `selectedLook`.
    var selectedLUT: CubeLUT? { selectedLook }

    /// Compatibility seam for callers that still use the model's historical LUT name.
    var lutIntensity: Double { lookIntensity }

    /// The document-level identity used by the Look inspector's selection binding. This remains
    /// separate from `selectedLUT`: an unresolved reference must not look like the explicit None
    /// choice in the browser.
    var selectedLookID: LUTID? { document.lut.lutID }

    /// True only for the explicit no-look state. A missing file keeps its stored ID and therefore
    /// stays visibly distinct from None until the user chooses to clear it.
    var isLookNoneSelected: Bool { document.lut.lutID == nil }

    /// Whether the Look stage has state worth resetting, including an unresolved stored reference
    /// and an intensity changed while no LUT was selected.
    var hasLookAdjustments: Bool { document.lut != .none }

    /// A missing LUT never prevents the source image from rendering. Keep the warning separate from
    /// the transient image status so the stored `LUTID` remains visible to callers and recoverable.
    @Published private(set) var lutResolutionStatus: String?

    /// Whether the transient A/B comparison — especially the Space-hold — has a meaningful
    /// before/after to show. Side-by-side presentation has a separate source-availability gate
    /// because an identity document still renders valid source pixels into both panes.
    /// The document owns the exact visible-stage rule and the matching `comparisonBaseline`, so
    /// Light, Color, Effects, adjustment nodes, and LUT intensity cannot drift apart at this gate.
    ///
    var isComparisonAvailable: Bool { document.hasVisibleLookEdits }

    @Published var isShowingOriginal: Bool = false
    /// The user's preferred comparison presentation. This is a display preference rather than
    /// per-photo edit state, so changing photos does not reset it and a new view model can restore
    /// it from `UserDefaults`.
    @Published var isSideBySide: Bool = false {
        didSet {
            guard isSideBySide != oldValue else { return }
            preferences.set(isSideBySide, forKey: Self.comparisonModeKey)
        }
    }
    /// Side-by-side is a retained presentation preference. An identity document still has valid
    /// source pixels, so it can populate both panes even though there is no meaningful before/after
    /// for the transient Space comparison.
    var isSideBySideVisible: Bool { isSideBySide && sourceImage != nil }

    /// The explicit comparison affordance is available for every loaded source when either a
    /// meaningful before/after exists or the user has retained the side-by-side presentation.
    /// Keeping this separate from `isComparisonAvailable` prevents the toolbar and status hints
    /// from disappearing merely because the current document is back at identity.
    var isComparisonPresentationAvailable: Bool {
        sourceImage != nil && (isComparisonAvailable || isSideBySide)
    }

    /// The visible render is owned by these surfaces, not published image values on this model.
    let previewSurface = PreviewSurface()
    let originalPreviewSurface = PreviewSurface()

    /// High-frequency canvas and transient crop state live outside the broad application
    /// publisher. Only the views that observe `canvasState` reevaluate for pointer interaction.
    let canvasState = CanvasInteractionState()
    let maskInteractionState = MaskInteractionState()

    /// Inspector chrome has a separate observation boundary for the same reason. The view model
    /// keeps compatibility accessors below so existing commands and tests retain their API while
    /// SwiftUI views can observe the narrow state object directly.
    let inspectorState = InspectorState()

    var canvasNavigation: CanvasNavigation { canvasState.navigation }
    var isCropToolActive: Bool { canvasState.isCropToolActive }
    var cropDraft: CGRect? { canvasState.cropDraft }
    var cropAspectRatio: CropAspectRatio { canvasState.cropAspectRatio }
    var cropOrientation: CropAspectRatioOrientation { canvasState.cropOrientation }

    var isInspectorPresented: Bool {
        get { inspectorState.isPresented }
        set { inspectorState.isPresented = newValue }
    }

    var inspectorTab: InspectorTab {
        get { inspectorState.tab }
        set { selectInspectorTab(newValue) }
    }

    /// Whether the masking presentation belongs on the editor canvas right now. Mask selection,
    /// drafts, and the overlay preference are persistent/transient masking state; this is only the
    /// workspace gate that decides whether the presentation subtree should exist at all.
    var isMaskingWorkspaceActive: Bool {
        inspectorState.isPresented
            && inspectorState.tab == .masking
            && navigation.isEdit
            && sourceImage != nil
            && maskingAssetID != nil
    }

    /// Route every inspector-tab selection through the shared workspace transition. Masking keeps
    /// its persistent editor and selection semantics; the other tabs remain ordinary inspector
    /// navigation and implicitly return from Masking when selected.
    func selectInspectorTab(_ requestedTab: InspectorTab) {
        if requestedTab == .masking {
            openMaskingWorkspace()
        } else {
            inspectorState.select(requestedTab)
        }
    }

    var hasCropAdjustments: Bool { !document.crop.isIdentity }

    /// Inspector visibility. Computing the histogram is gated on this — plus on the Info tab being
    /// the one on screen — so we don't tally pixels for a panel nobody's looking at.
    enum InspectorTab: String, CaseIterable, Sendable {
        case info, light, develop, adjust
        case effects, look, masking

        /// The view surface selected by this tab. Keep `.adjust` as the stored compatibility case;
        /// its photographer-facing name is Color.
        enum Content: Equatable, Sendable {
            case info, light, develop, color, effects, look, masking
        }

        var content: Content {
            switch self {
            case .info: return .info
            case .light: return .light
            case .develop: return .develop
            case .adjust: return .color
            case .effects: return .effects
            case .look: return .look
            case .masking: return .masking
            }
        }

        var iconName: String {
            switch self {
            case .info: return "info.circle"
            case .light: return "sun.max"
            case .develop: return "camera.aperture"
            case .adjust: return "paintpalette"
            case .effects: return "sparkles"
            case .look: return "wand.and.stars"
            case .masking: return "wand.and.rays"
            }
        }

        var title: String {
            switch self {
            case .info: return "Info"
            case .light: return "Light"
            case .develop: return "Develop"
            case .adjust: return "Color"
            case .effects: return "Effects"
            case .look: return "Look"
            case .masking: return "Masking"
            }
        }

        /// Describes the panel's purpose for compact icon-only navigation controls.
        var purpose: String {
            switch self {
            case .info: return "Histogram and photo metadata"
            case .light: return "Tone and RGB curve adjustments"
            case .develop: return "RAW decoder controls"
            case .adjust: return "Color adjustments"
            case .effects: return "Texture, clarity, and dehaze effects"
            case .look: return "Browse and apply a Look"
            case .masking: return "Create and edit local masks"
            }
        }

        var helpText: String { "\(title): \(purpose)" }

        static func availableTabs(
            hasImage: Bool,
            developPanelState: DevelopPanelState,
            hasMaskingTarget: Bool = true
        ) -> [InspectorTab] {
            guard hasImage else { return [] }
            return allCases.filter { tab in
                switch tab {
                case .develop:
                    return developPanelState.offersDevelopTab
                case .masking:
                    return hasMaskingTarget
                default:
                    return true
                }
            }
        }
    }
    /// Source-folder file browser panel visibility.
    @Published var isSourceBrowserPresented: Bool = false
    /// The visible workspace. Library selection, the active edit document, and render surfaces
    /// remain owned by their existing collaborators; this value only composes those surfaces.
    @Published private(set) var navigation = NavigationState()

    /// EXIF/TIFF/GPS metadata of the loaded image, read at load time.
    @Published var metadata: ImageMetadata = ImageMetadata()
    /// Histogram of the currently displayed image (graded result, or original
    /// while comparing). `nil` until computed / when no image is loaded.
    @Published var histogram: HistogramData?
    /// A nil histogram is otherwise ambiguous: it can mean loading, cancellation, an
    /// unsupported source, or a failed calculation. Keep the terminal UI state explicit.
    @Published private(set) var isHistogramLoading = false
    @Published private(set) var histogramErrorMessage: String?
    private var histogramTaskRevision: UInt64?
    private var histogramTaskRequest: RenderRequest?
    /// The asset identity is checked separately from the source value. Two library items can
    /// legitimately carry equal-valued source data, and an old histogram must never become the
    /// current item's result just because its `ImageSource` compares equal.
    private var histogramTaskAssetID: PhotoAssetID?

    /// Auto has its own analysis lifecycle rather than borrowing the Info histogram's loading flag:
    /// an Auto request must not make the histogram spinner appear to be waiting on unrelated work.
    @Published private(set) var autoAdjustmentState: AutoAdjustmentState = .unavailable(
        "Open a supported photo to enable Auto."
    )
    /// Determinate progress for the Auto lifecycle. `nil` means Auto is settled; unlike the Info
    /// histogram flag, this value belongs only to the active Auto invocation.
    @Published private(set) var autoAdjustmentProgress: Double?
    private var autoAdjustmentTask: Task<Void, Never>?
    /// A second Auto invocation, a manual edit, or navigation invalidates the previous invocation
    /// even when the source and document values happen to compare equal. This closes the late
    /// completion window left by a renderer that can only observe cancellation cooperatively.
    private var autoInvocationRevision: UInt64 = 0
    /// Smart-mask creation performs provider work before inserting the durable recipe. This keeps
    /// unsupported sources and failed analysis from leaving an inert component in the document.
    var smartMaskCreationTask: Task<Void, Never>?
    var smartMaskRetryContext: SmartMaskRetryContext?

    @Published var isLoading: Bool = false
    enum PreviewState: Equatable, Sendable {
        case empty
        case loading
        case ready
        case failed
    }
    /// Source preparation and preview presentation are separate async stages. This state keeps
    /// the transparent source marker from making a not-yet-presented canvas look like a black one.
    @Published private(set) var previewState: PreviewState = .empty
    @Published var statusMessage: String = "Open an image to get started"

    /// Non-nil when a hard failure should be surfaced as a dismissible alert.
    /// Bound to an `.alert` in ContentView; cleared when the user dismisses it.
    @Published var errorMessage: String?
    /// The Library owns the confirmation presentation, while the model owns the immutable target
    /// snapshot so a late selection change cannot redirect a destructive action.
    @Published var libraryDeletionConfirmation: LibraryDeletionConfirmation?
    /// Compatibility shim for callers that still mention the retired modal sheet.
    @Published var isMaskingPanelPresented = false

    @Published var isPhotosPickerPresented: Bool = false
    /// Compatibility projection for the import coordinator's operation state. The coordinator is
    /// the single owner so the picker and status bar cannot observe competing progress values.
    var photosImportProgress: PhotosImportProgress? { photosImportCoordinator.progress }
    /// Presentation is a property of the import operation, not of each item. This prevents a
    /// later streamed arrival (or a second load triggered by metadata work) from reopening or
    /// retargeting the inspector after the first accepted item has established the active photo.
    private var didPresentInspectorForPhotosImport = false
    /// Portable Photos imports commit each item's package transaction immediately, but defer the
    /// disposable index/collection refresh until the streamed batch finishes.
    private var isPortablePhotosImportActive = false
    private var portablePhotosImportNeedsRefresh = false
    private var portablePhotosImportWasEmpty = false
    private var portablePhotosImportFirstAssetID: PortablePhotoAssetID?
    private var droppedPromiseTask: Task<Void, Never>?

    /// Removable volumes are discovered independently of the selector so the Import menu can name
    /// mounted volumes that contain supported images, or offer a permission-recovery path when
    /// the sandbox cannot inspect a volume until the user selects it.
    var removableMediaVolumes: [MediaVolume] { libraryMediaWorkflow.removableMediaVolumes }
    var isRemovableMediaSelectorPresented: Bool {
        get { libraryMediaWorkflow.isRemovableMediaSelectorPresented }
        set { libraryMediaWorkflow.isRemovableMediaSelectorPresented = newValue }
    }
    var removableMediaVolume: MediaVolume? { libraryMediaWorkflow.removableMediaVolume }
    var removableMediaFiles: [MediaVolumeFile] { libraryMediaWorkflow.removableMediaFiles }
    var removableMediaWarnings: [String] { libraryMediaWorkflow.removableMediaWarnings }
    var isRemovableMediaScanning: Bool { libraryMediaWorkflow.isRemovableMediaScanning }
    var removableMediaSelection: MediaVolumeSelectionModel {
        libraryMediaWorkflow.removableMediaSelection
    }
    var removableMediaImportProgress: MediaVolumeImportProgress? {
        libraryMediaWorkflow.removableMediaImportProgress
    }

    // MARK: - Owned state

    public let settings: KromoraSettings
    let library: LUTLibrary
    let workScheduler: ImageWorkScheduler
    /// Edited thumbnails share the collection's bounded thumbnail lane. A stable job per asset
    /// lets filmstrip and grid demand one render rather than producing duplicate work.
    private var editedThumbnailGenerations: [PhotoAssetID: UInt64] = [:]
    private var editedThumbnailDebounceTasks: [PhotoAssetID: Task<Void, Never>] = [:]
    private var pendingEditedThumbnailAssetID: PhotoAssetID?
    private let editedThumbnailJobPrefix = "edited-thumbnail-"
    let lookPreviewCoordinator: LookPreviewCoordinator
    let collection: ImageCollection
    let editStore: EditDocumentStore
    /// Value-only editor sessions, history, and clipboard. The published document remains owned by
    /// AppViewModel so render scheduling has one presentation-state owner.
    let editorDocument: EditorDocumentCoordinator
    /// Provider interaction and progress belong to the application composition root, while this
    /// model remains the narrow destination for durable collection admission and source loading.
    let photosImportCoordinator: PhotosImportCoordinator
    /// Coalesced durable edit snapshots. The application model routes persistence policy here;
    /// file I/O remains inside `EditDocumentStore`.
    let persistence: EditPersistenceCoordinator
    /// The production library boundary. When present, package membership and originals are
    /// canonical; the legacy ImageCollection remains only as a bounded presentation bridge.
    let portableLibrary: PortableLibrarySession?
    /// Background compaction shares the scheduler with editor work but uses its detached
    /// package-I/O lane, so a foreground edit can take the admission window back immediately.
    /// Writing images to disk — the single export, the batch run, and naming. Production exports
    /// use an isolated RenderEngine lane while preserving the same render request funnel.
    let export: ExportCoordinator
    /// The "Derive Look from JPG" flow and its scratch-until-saved result.
    let derive = DeriveCoordinator()
    /// The active-document global Look export flow. It snapshots edits and never mutates them while
    /// the user reviews omissions or chooses a destination.
    let lookSave = LookSaveCoordinator()
    let libraryMediaWorkflow: LibraryMediaWorkflowCoordinator
    private let libraryDeletionCoordinator: LibraryDeletionCoordinator
    private let applicationShell: ApplicationShellCoordinator
    /// Compatibility façade for diagnostics and package-maintenance tests. Lifecycle ownership
    /// remains in `ApplicationShellCoordinator`.
    var portablePackageMaintenance: PortablePackageMaintenance { applicationShell.maintenance }

    /// The persistent edit database location, when the store has an on-disk backing file.
    ///
    /// This keeps the persistence actor internal while allowing the app boundary to expose the
    /// one value needed by Settings for support and backup workflows.
    public var editDatabaseURL: URL? {
        get async { await editStore.onDiskFileURL }
    }

    // Convenience passthroughs so views and the menu don't have to know which
    // collaborator owns a given piece of state.
    var isExporting: Bool { export.isExporting }
    var isBatchExporting: Bool { export.isExporting && export.batchTotal > 0 }
    var batchProgress: Double { export.batchProgress }
    var batchCompleted: Int { export.batchCompleted }
    var batchTotal: Int { export.batchTotal }
    var batchCurrentItem: String? { export.batchCurrentItem }

    func cancelExport() {
        export.cancelBatchExport()
    }

    /// The renderer. An `any RenderEngining` rather than the concrete actor so a test can drive the
    /// preview flow without a GPU — the reason Step 4 introduced the protocol.
    private let engine: any RenderEngining

    /// Narrow presentation-only accessors for the masking canvas. The backing source and renderer
    /// remain owned by the view model; callers receive only the values needed for an overlay task.
    var maskOverlaySource: ImageSource? { isShuttingDown ? nil : imageSource }
    var maskOverlayEngine: any RenderEngining { engine }
    /// Shared photo-understanding coordinator. Auto consumes its scalar result; it never reaches
    /// through to Vision, Core Image, or mask pixels.
    let photoAnalysisCoordinator: PhotoAnalysisCoordinator

    var maskingAssetID: PhotoAssetID? { isShuttingDown ? nil : activeAssetID }
    var maskingSourceRevision: UInt64 { sourceRevision }
    var maskingSource: ImageSource? { isShuttingDown ? nil : imageSource }
    private let preferences: UserDefaults
    private let previewCoordinator: PreviewCoordinator
    private let previewPresentation: PreviewPresentationCoordinator
    private var pendingPreviewCacheLookup:
        (
            request: RenderRequest, assetID: PhotoAssetID?, sourceRevision: UInt64,
            displayRevision: UInt64
        )?
    private struct AdjacentPreviewCandidate: Sendable {
        let source: ImageSource
        let inMemoryDocument: EditDocument?
        let reference: EditSourceReference
    }
    private struct IdlePreviewCandidate: Sendable {
        let index: Int
        let source: ImageSource
        let inMemoryDocument: EditDocument?
        let reference: EditSourceReference
    }
    private struct IdlePreviewWorkItem: Sendable {
        let cursor: Int
        let request: RenderRequest?
    }
    /// One non-cancellable source preparation is allowed to run. New navigation replaces this one
    /// pending value, so a burst cannot build a queue of obsolete RAW decoder operations.
    /// Idle preview building is deliberately separate from adjacent prefetch. The neighbour wave
    /// warms the renderer's in-memory sources; this slower wave owns cache-fill cancellation and
    /// must never cancel or be cancelled by that existing two-item prefetch.
    private let idlePreviewBuildJobID = ImageWorkScheduler.JobID("idle-preview-build")
    private var idleBuildTask: Task<Void, Never>?
    private var idleBuildGeneration: UInt64 = 0
    private var idleBuildCursor: Int?
    private static let maxItemsPerIdleSession = 20
    /// Tracks whether a preview was already admitted after source chrome appeared. A user edit
    /// can arrive while stored edits are still loading; adopting the store result must not submit
    /// a duplicate preview in that case.
    private var previewScheduledSourceRevision: UInt64?
    /// The first preview may be speculative while persistence is still loading. Supporting work
    /// such as histogram and edited-thumbnail generation is admitted only after this source's
    /// stored document has been reconciled.
    private var storedEditsResolvedSourceRevision: UInt64?
    private let adjacentPreviewPrefetchJobID = ImageWorkScheduler.JobID("adjacent-preview-prefetch")
    private let comparisonPreviewJobID = ImageWorkScheduler.JobID("comparison-preview")
    private let histogramJobID = ImageWorkScheduler.JobID("histogram")
    /// The embedded camera JPEG is a presentation-only first frame. It never enters the render
    /// coordinator or any supporting-work path, and is cancelled when navigation selects another
    /// source.
    private let fileDialog: any FileDialogProviding
    private var prefetchDelayTask: Task<Void, Never>?
    private var previewDebounceTask: Task<Void, Never>?
    private var previewDebounceGeneration: UInt64 = 0
    private var sourceFolderOpenTask: Task<Void, Never>?
    private let sourceSession: SourceSessionCoordinator
    // Internal so the masking extension can register its retry warm-up with lifecycle shutdown.
    var personSignalWarmingTask: Task<Void, Never>?
    private var lutCacheInvalidationTask: Task<Void, Never>?
    private var semanticCoordinatorInstallTask: Task<Void, Never>?
    private var isShuttingDown = false
    private var cancellables: [AnyCancellable] = []
    private let portableLibraryOpenError: String?

    /// Changes whenever a Look thumbnail's source or edit recipe can change. Look rows use this as
    /// their task identity so a source switch or restored per-photo document refreshes thumbnails
    /// even when the library itself did not change.
    var lookPreviewRevision: UInt64 { sourceRevision &* 31 &+ documentRevision }

    func lookPreview(for look: CubeLUT) async -> CGImage? {
        await lookPreviewCoordinator.image(source: imageSource, document: document, look: look)
    }

    // MARK: - Init

    public convenience init() {
        let packageURL = KromoraStorage.defaultPortableLibraryPackageURL
        self.init(
            engine: RenderEngine.shared,
            editStore: EditDocumentStore.makeInMemoryProjectionStore(),
            includeBundledLooks: false,
            portablePackageURL: packageURL
        )
    }

    /// Production entry points opt into the packaged starter library. The plain initializer stays
    /// bundle-free for headless/test clients that intentionally provide their own Look folder.
    public convenience init(includeBundledLooks: Bool) {
        let packageURL = KromoraStorage.defaultPortableLibraryPackageURL
        self.init(
            engine: RenderEngine.shared,
            editStore: EditDocumentStore.makeInMemoryProjectionStore(),
            includeBundledLooks: includeBundledLooks,
            portablePackageURL: packageURL
        )
    }

    init(
        engine: any RenderEngining = RenderEngine.shared,
        editStore: EditDocumentStore? = nil,
        preferences: UserDefaults = .standard,
        mediaVolumeProvider: any MediaVolumeProviding = MountedMediaVolumeProvider(),
        mediaVolumeNotificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        applicationNotificationCenter: NotificationCenter = .default,
        includeBundledLooks: Bool = false,
        libraryFolderURL: URL? = nil,
        userLookFolderURL: URL? = nil,
        photoAnalysisCoordinator: PhotoAnalysisCoordinator? = nil,
        previewDiskCacheDirectory: URL? = nil,
        previewDiskCacheCapBytes: Int64 = PreviewDiskCache.defaultCapBytes,
        portablePackageURL: URL? = nil,
        portableMaintenanceIdleDelay: Duration = .seconds(2),
        embeddedFirstFrameProvider: @escaping @Sendable (URL) async -> NSImage? = { url in
            Thumbnails.generate(from: url, maxPixelSize: Thumbnails.firstFrameMaxPixelSize)
        },
        fileDialog: any FileDialogProviding = AppKitFileDialog(),
        fileDropActionPolicy: FileDropActionPolicy = FileDropActionPolicy()
    ) {
        var interval = KromoraSignpostInterval(.launch, context: .unknown)
        defer { interval.end() }

        self.engine = engine
        let analysisCoordinator =
            photoAnalysisCoordinator ?? PhotoAnalysisCoordinator(engine: engine)
        self.photoAnalysisCoordinator = analysisCoordinator
        self.preferences = preferences
        let normalizedPortablePackageURL = portablePackageURL?.standardizedFileURL
        let openedPortableLibrary: PortableLibrarySession?
        let portableOpenError: String?
        let effectiveEditStore: EditDocumentStore
        if let normalizedPortablePackageURL {
            do {
                let session = try PortableLibrarySession(at: normalizedPortablePackageURL)
                openedPortableLibrary = session
                portableOpenError = nil
                // The package owns the edit sidecars. SwiftData is constructed as a disposable
                // projection and is never allowed to become a fallback authority.
                effectiveEditStore = EditDocumentStore(
                    package: session.package, lease: session.lease
                )
            } catch {
                openedPortableLibrary = nil
                portableOpenError =
                    "Kromora could not open its library package at \(normalizedPortablePackageURL.path): "
                    + error.localizedDescription
                // A package-mode failure is an actionable empty state, not permission to open
                // the old standalone edit database. Keep the composition root fail-closed and
                // use only an in-memory projection until the user repairs the package.
                effectiveEditStore = editStore ?? EditDocumentStore.makeInMemoryProjectionStore()
            }
        } else {
            openedPortableLibrary = nil
            portableOpenError = nil
            effectiveEditStore = editStore ?? EditDocumentStore.makeDefaultStore()
        }
        let effectiveLibraryFolderURL: URL
        if let openedPortableLibrary {
            effectiveLibraryFolderURL = openedPortableLibrary.rootURL
        } else if let libraryFolderURL {
            effectiveLibraryFolderURL = libraryFolderURL
        } else if let normalizedPortablePackageURL {
            // Keep package-mode failures isolated from the legacy folder-backed library. This
            // URL is never scanned because the error state returns before restoration below.
            effectiveLibraryFolderURL = normalizedPortablePackageURL
        } else {
            effectiveLibraryFolderURL = ImageCollection.defaultLibraryFolderURL
        }
        self.portableLibrary = openedPortableLibrary
        self.portableLibraryOpenError = portableOpenError
        self.editStore = effectiveEditStore
        self.editorDocument = EditorDocumentCoordinator()
        self.photosImportCoordinator = PhotosImportCoordinator()
        self.settings = KromoraSettings(
            preferences: preferences,
            userLookFolderURL: userLookFolderURL
        )
        self.workScheduler = ImageWorkScheduler()
        self.persistence = EditPersistenceCoordinator(store: effectiveEditStore)
        // Look thumbnails have a bounded, independent thumbnail lane. Sharing the editor's lane
        // would let a burst of filmstrip/grid work evict a row's continuation before it can return.
        self.lookPreviewCoordinator = LookPreviewCoordinator(
            engine: engine, scheduler: ImageWorkScheduler()
        )
        self.collection = ImageCollection(
            scheduler: workScheduler, defaults: preferences,
            libraryFolderURL: effectiveLibraryFolderURL,
            persistsLegacyLibraryState: openedPortableLibrary == nil
        )
        self.library = LUTLibrary(
            preferences: preferences,
            userLookFolderURL: settings.ensureUserLookFolder(),
            includeBundled: includeBundledLooks
        )
        self.export = ExportCoordinator(
            engine: engine,
            maskResolver: CoordinatorLocalMaskResolver(coordinator: analysisCoordinator),
            editStore: effectiveEditStore
        )
        self.previewCoordinator = PreviewCoordinator(engine: engine, scheduler: workScheduler)
        let previewCache = PreviewDiskCache(
            directory: previewDiskCacheDirectory
                ?? (openedPortableLibrary.map { PreviewDiskCache.packageDirectory(for: $0.rootURL) }
                    ?? PreviewDiskCache.defaultDirectory()),
            capBytes: previewDiskCacheCapBytes
        )
        self.previewPresentation = PreviewPresentationCoordinator(cache: previewCache)
        self.sourceSession = SourceSessionCoordinator(
            engine: engine, editStore: effectiveEditStore,
            embeddedFirstFrameProvider: embeddedFirstFrameProvider
        )
        self.fileDialog = fileDialog
        self.libraryMediaWorkflow = LibraryMediaWorkflowCoordinator(
            provider: mediaVolumeProvider, fileDialog: fileDialog,
            fileDropActionPolicy: fileDropActionPolicy
        )
        self.applicationShell = ApplicationShellCoordinator(
            mediaNotificationCenter: mediaVolumeNotificationCenter,
            applicationNotificationCenter: applicationNotificationCenter,
            scheduler: workScheduler,
            maintenance: PortablePackageMaintenance(scheduler: workScheduler),
            packageURL: normalizedPortablePackageURL,
            packageLease: openedPortableLibrary?.lease,
            idleDelay: portableMaintenanceIdleDelay
        )
        let deletionCollection = self.collection
        self.libraryDeletionCoordinator = LibraryDeletionCoordinator(
            collection: self.collection,
            persistence: self.persistence,
            editStore: self.editStore,
            photoAnalysis: self.photoAnalysisCoordinator,
            portableLibrary: self.portableLibrary,
            persistenceIdentity: { item in
                guard deletionCollection.sourceKind(for: item) == .managed else { return nil }
                return item.asset.source.portableIdentity
            }
        )
        self.photosImportCoordinator.destination = self
        self.photosImportCoordinator.onStatus = { [weak self] message in
            self?.statusMessage = message
        }

        collection.onThumbnailDemand = { [weak self] assetID, priority in
            self?.requestEditedThumbnail(for: assetID, priority: priority)
        }

        if let renderEngine = engine as? RenderEngine {
            semanticCoordinatorInstallTask = Task {
                await renderEngine.installSemanticMaskCoordinator(analysisCoordinator)
            }
        }

        persistence.onStatusChange = { [weak self] status in
            self?.editStoreStatus = status
        }
        persistence.onFailure = { [weak self] message in
            self?.statusMessage = message
        }

        libraryMediaWorkflow.onStatus = { [weak self] message in
            self?.statusMessage = message
        }
        libraryMediaWorkflow.onError = { [weak self] message in
            self?.presentError(message)
        }
        libraryMediaWorkflow.onSourceFolder = { [weak self] url in
            self?.openSourceFolder(url: url)
        }
        libraryMediaWorkflow.onImageURL = { [weak self] url in
            self?.openImage(url: url)
        }
        libraryMediaWorkflow.onImageURLs = { [weak self] urls in
            self?.openImages(urls: urls)
        }
        libraryMediaWorkflow.onImportRequest = { [weak self] request in
            self?.importRemovableMedia(request)
        }
        applicationShell.onMediaChanged = { [weak self] in
            self?.libraryMediaWorkflow.refreshRemovableMedia()
        }
        applicationShell.start()

        // A missing value is the first-launch state: single-photo editing is the primary surface.
        // Read this after all stored properties are initialized because the published property's
        // observer persists later user changes through `preferences`.
        if let storedMode = preferences.object(forKey: Self.comparisonModeKey) as? Bool {
            self.isSideBySide = storedMode
        }

        // A Core Image graph is lazy: a publication can be accepted while its drawable command
        // buffer is still able to fail. Keep the previous surface image in that case and surface a
        // useful status instead of leaving the user with a permanent black canvas.
        previewSurface.onPresentationFailure = { [weak self] in
            guard let self, !self.isShuttingDown, self.sourceImage != nil else { return }
            self.previewState = .failed
            self.publishAutoAdjustmentState(
                .unavailable("Auto is unavailable because the photo preview failed."))
            self.statusMessage =
                "Could not display \(self.sourceName). Try Fit or reload the photo."
        }
        originalPreviewSurface.onPresentationFailure = { [weak self] in
            guard let self, !self.isShuttingDown, self.sourceImage != nil else { return }
            self.statusMessage =
                "Could not display the comparison preview. Try Fit or reload the photo."
        }

        sourceSession.onPreparation = { [weak self] publication in
            guard let self, !self.isShuttingDown else { return }
            self.install(preparation: publication.preparation, request: publication.request)
            if self.previewScheduledSourceRevision != self.sourceRevision {
                self.schedulePreview()
            }
        }
        sourceSession.onStoredDocument = { [weak self] publication in
            guard let self, !self.isShuttingDown else { return }
            self.adoptStoredEdits(publication.result, for: publication.request)
        }
        sourceSession.onMetadata = { [weak self] publication in
            guard let self, !self.isShuttingDown,
                publication.request.sourceRevision == self.sourceRevision,
                publication.request.assetID == self.activeAssetID else { return }
            self.metadata = publication.metadata
        }
        sourceSession.onCapabilities = { [weak self] publication in
            guard let self, !self.isShuttingDown,
                publication.request.sourceRevision == self.sourceRevision,
                publication.request.assetID == self.activeAssetID else { return }
            self.rawCapabilities = publication.capabilities
            self.capabilitiesProbeCompleted = true
            self.keepInspectorTabValid()
        }
        sourceSession.onFirstFrame = { [weak self] publication in
            guard let self, !self.isShuttingDown else { return }
            self.presentEmbeddedFirstFrame(publication)
        }
        sourceSession.onFailure = { [weak self] request, message in
            guard let self, !self.isShuttingDown,
                request.sourceRevision == self.sourceRevision,
                request.assetID == self.activeAssetID else { return }
            self.isLoading = false
            self.previewState = .failed
            self.presentError(message)
        }

        // Forward nested ObservableObject changes so SwiftUI views update.
        for child in [
            settings.objectWillChange.eraseToAnyPublisher(),
            library.objectWillChange.eraseToAnyPublisher(),
            collection.objectWillChange.eraseToAnyPublisher(),
            libraryMediaWorkflow.objectWillChange.eraseToAnyPublisher(),
            editorDocument.objectWillChange.eraseToAnyPublisher(),
            photosImportCoordinator.objectWillChange.eraseToAnyPublisher(),
            export.objectWillChange.eraseToAnyPublisher(),
            derive.objectWillChange.eraseToAnyPublisher(),
            lookSave.objectWillChange.eraseToAnyPublisher(),
        ] {
            cancellables.append(
                child.sink { [weak self] _ in
                    Task { @MainActor [weak self] in
                        guard let self, !self.isShuttingDown else { return }
                        self.objectWillChange.send()
                    }
                })
        }

        // Inspector chrome is observed by its own view subtree. Histogram work still belongs to
        // this model, so react after the published state has been assigned without forwarding the
        // inspector publisher through AppViewModel's broad objectWillChange stream.
        cancellables.append(
            inspectorState.objectWillChange.sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, !self.isShuttingDown else { return }
                    if self.inspectorState.isPresented, self.inspectorState.tab == .info {
                        self.updateHistogram()
                    } else {
                        self.cancelHistogram(clear: true)
                    }
                }
            })

        previewCoordinator.onPublication = { [weak self] publication in
            self?.publishPreview(publication)
        }
        previewCoordinator.onFailure = { [weak self] request in
            guard request.quality == .preview else { return }
            guard let self, request.source == self.imageSource else { return }
            self.previewState = .failed
            self.publishAutoAdjustmentState(
                .unavailable("Auto is unavailable because the photo preview failed."))
            if let message = self.semanticMaskFailureMessage(for: request.document) {
                self.maskInteractionState.markMaskFailed(message)
                self.statusMessage = message
            } else {
                self.statusMessage = "Could not render \(self.sourceName)"
            }
        }

        wireCoordinators()
        library.restoreFolder()

        if let portableLibrary {
            do {
                collection.loadPortableAssets(try portableLibrary.materializedAssets())
                navigation.move(to: .grid)
                collection.beginThumbnailDemand()
            } catch {
                presentError(
                    "Kromora could not read the library package: \(error.localizedDescription)"
                )
            }
            configureEmbeddedLooks()
            return
        }

        if let portableLibraryOpenError {
            // A failed package open is an actionable empty state. In particular, do not restore a
            // source folder or the old Application Support managed folder as a hidden second
            // library.
            presentError(portableLibraryOpenError)
            return
        }

        // Restore a previously-chosen source folder and open its first image.
        // Both the LUT scan above and this one run asynchronously, so the
        // window paints immediately and fills in as the scans land.
        if collection.restoreSourceFolder() {
            isSourceBrowserPresented = true
            navigation.move(to: .grid)
            collection.beginThumbnailDemand()
            openFirstImageWhenScanned()
        } else if collection.hasPersistedSourceFolderBookmark {
            presentError(
                "Kromora could not restore the source folder. "
                    + "Choose Open Source Folder… to select it again."
            )
        } else if collection.restoreLibrary() {
            navigation.move(to: .grid)
            collection.beginThumbnailDemand()
        }
    }

    private static let comparisonModeKey = "Kromora.editor.comparisonMode.sideBySide"

    /// Point the coordinators' status/error output at this view model, which
    /// owns the status bar and the alert. They report *what* happened; deciding
    /// how to show it stays here.
    private func wireCoordinators() {
        // Export resolves each selected asset's durable document on demand. The LUT table is not
        // part of that Codable record, so resolve its stable ID against the current Look library
        // only after the store has supplied the per-photo document.
        export.lutResolver = { [weak self] id in self?.resolvedLUT(id) }

        // A rescan can mean the bytes behind an unchanged `LUTID` have changed — a path is the
        // identity, so a `.cube` replaced in place keeps it. Drop the engine's cube filters rather
        // than go on serving the old cube. Wired here, before `restoreFolder()` runs below, so the
        // launch scan is covered too.
        library.onScanned = { [weak self] in
            guard let self, !self.isShuttingDown else { return }
            self.refreshLUTResolutionStatus()
            self.lutCacheInvalidationTask?.cancel()
            let engine = self.engine
            guard self.sourceImage != nil else {
                self.lutCacheInvalidationTask = Task { [weak self, engine] in
                    await engine.invalidateLUTCache()
                    guard let self, !self.isShuttingDown else { return }
                    self.refreshMaterializedEditedThumbnails()
                }
                return
            }
            // A render submitted before the asynchronous scan may have been safely ungraded. Flush
            // first, then submit again, so an old cached cube cannot win the race with publication.
            lutCacheInvalidationTask = Task { [weak self] in
                await engine.invalidateLUTCache()
                guard let self, !self.isShuttingDown, self.sourceImage != nil else { return }
                self.schedulePreview()
                self.refreshMaterializedEditedThumbnails()
            }
        }

        library.onImported = { [weak self] lut in
            self?.configureEmbeddedLooks()
            // Importing is also an audition action when an image is open. With no active image the
            // file still appears in the browser, but must not become a document default that could
            // accidentally leak into a later per-photo session.
            guard let self, self.sourceImage != nil else { return }
            self.selectLook(lut)
        }
        library.onImportError = { [weak self] message in
            self?.presentError(message)
        }

        export.onStatus = { [weak self] in self?.statusMessage = $0 }
        export.onError = { [weak self] in self?.presentError($0) }
        export.defaultFolderURL = { [weak self] in self?.settings.ensureDefaultExportFolder() }

        derive.onStatus = { [weak self] in self?.statusMessage = $0 }
        derive.onError = { [weak self] in self?.presentError($0) }
        derive.onDerived = { [weak self] lut in
            // Preview the new look immediately, if there's something to see.
            guard let self, self.sourceImage != nil else { return }
            self.selectLook(lut)
        }
        derive.libraryFolder = { [weak self] in
            self?.library.folderURL
        }
        derive.canonicalLibraryFolder = { [weak self] in self?.settings.userLookFolderURL }
        derive.onSaved = { [weak self] destination in
            guard let self else { return }
            self.adoptSavedLUT(at: destination)
            // Re-scan so the new entry appears in the sidebar.
            if let folder = self.library.folderURL {
                self.library.scan(folder)
            } else {
                // A clean profile saves into the canonical user Look folder before any external
                // folder is selected. Importing here keeps that saved user Look discoverable.
                self.library.importLUT(from: destination, audition: false)
            }
        }

        lookSave.onStatus = { [weak self] in self?.statusMessage = $0 }
        lookSave.onError = { [weak self] in self?.presentError($0) }
        lookSave.libraryFolder = { [weak self] in
            self?.library.folderURL
        }
        lookSave.canonicalLibraryFolder = { [weak self] in self?.settings.userLookFolderURL }
        lookSave.onSaved = { [weak self] destination in
            // Registration is intentionally non-auditioning. Saving a Look must not add a new
            // edit or undo entry to the photo whose document was exported.
            self?.library.importLUT(from: destination, audition: false)
        }

        configureEmbeddedLooks()
    }

    /// Snapshot the bytes of every currently-resolvable Look for the package edit boundary. The
    /// package sidecar remains self-contained even if a user later removes or relocates the
    /// external browser file.
    private func configureEmbeddedLooks() {
        guard portableLibrary != nil else { return }
        let values = library.allLUTs.reduce(into: [String: Data]()) { result, look in
            if let data = try? Data(contentsOf: look.url) {
                result[look.lutID.raw] = data
            }
        }
        let store = editStore
        Task {
            await store.setEmbeddedLookBytes(values)
        }
    }

    /// Follow a derived LUT from memory onto disk.
    ///
    /// Saving is the moment a derived LUT becomes durable, so it is the moment its reference should
    /// become durable too. A `derived://` ID resolves only through the registry and cannot survive a
    /// relaunch; the path the user just chose is what a fresh launch would resolve and what the next
    /// library scan will hold. So the document is re-pointed at it.
    ///
    /// **The saved LUT is re-parsed from the file rather than aliased from memory.** `cubeFileContents`
    /// writes `%.6f`, so what landed on disk is a rounded copy of the in-memory table. Aliasing the
    /// full-precision cube to the saved path would leave the app rendering something a fresh launch
    /// could not reproduce from that same file — a divergence of exactly the kind this migration
    /// exists to close. The file is authoritative because the file is what persists.
    ///
    /// It is registered as well as re-pointed, because `onSaved` only triggers a rescan when the
    /// destination is inside the configured LUT folder. Saving anywhere else would otherwise re-point
    /// the document at something nothing can resolve.
    ///
    /// Only the LUT that was *just saved* moves. The user can derive, pick something else from the
    /// sidebar, and then save the derive from the still-open sheet; that must not steal the selection.
    private func adoptSavedLUT(at destination: URL) {
        guard let saved = try? CubeLUT(url: destination, category: "Derived") else { return }
        derivedRegistry.register(saved)

        guard let current = document.lut.lutID, current == derive.derivedLUT?.lutID else { return }
        endUndoGrouping()
        updateDocument { $0.lut.lutID = saved.lutID }
    }

    /// Open the first image of the source folder once its scan completes.
    private func openFirstImageWhenScanned() {
        let scanToken = collection.scanToken
        sourceFolderOpenTask = Task { [weak self] in
            guard let self else { return }
            await collection.scanCompletion()
            guard !Task.isCancelled, !self.isShuttingDown,
                collection.scanToken == scanToken
            else { return }
            guard let first = collection.items.first, let fileURL = first.url else { return }
            // Folder open starts in Library even though the first image is also loaded so the
            // editor is ready for an immediate Enter/double-click handoff.
            self.load(
                name: first.displayName, url: fileURL, data: nil, assetID: first.id,
                portableIdentity: persistencePortableIdentity(for: first)
            )
        }
    }

    // MARK: - Error presentation

    /// Surface a user-facing error both as a dismissible alert and in the
    /// status bar. Used for hard failures (load / export / derive / save);
    /// transient preview hiccups stay status-bar-only to avoid alert spam.
    private func presentError(_ message: String) {
        statusMessage = message
        errorMessage = message
    }

    // MARK: - Auto adjustment

    /// Whether the one-click action has a ready source to analyze. The transparent source marker
    /// installed during preparation is deliberately not enough: Auto becomes available only after
    /// a real frame has made it through the presentation lifecycle. Optional metadata, histogram
    /// work, and photo-intelligence availability are not prerequisites; the action has a histogram
    /// fallback for those cases.
    var canRunAutoAdjustment: Bool {
        sourceImage != nil && imageSource != nil && previewState == .ready
            && !isAutoAdjustmentInProgress
    }

    var isAutoAdjustmentInProgress: Bool {
        switch autoAdjustmentState {
        case .analyzing, .renderingCandidates, .validating, .applying:
            return true
        case .unavailable, .ready, .cancelled, .failed:
            return false
        }
    }

    var autoAdjustmentHelp: String {
        if canRunAutoAdjustment || isAutoAdjustmentInProgress {
            return autoAdjustmentState.message
        }
        if previewState == .failed {
            return
                "Auto is unavailable because the photo preview failed. Reload the photo to try again."
        }
        if sourceImage == nil || imageSource == nil {
            return "Open a supported photo to enable Auto."
        }
        return "Auto is available when the photo preview is ready."
    }

    private func publishAutoAdjustmentState(
        _ state: AutoAdjustmentState, progress: Double? = nil
    ) {
        autoAdjustmentState = state
        autoAdjustmentProgress = progress.map { min(max($0, 0), 1) }
    }

    private func setAutoAdjustmentProgress(
        _ phase: AutoEnhancementPhase, invocationRevision: UInt64
    ) {
        guard self.autoInvocationRevision == invocationRevision else { return }
        switch phase {
        case .analyzing:
            publishAutoAdjustmentState(.analyzing, progress: 0)
            statusMessage = "Analyzing \(sourceName) for Auto adjustments…"
        case .renderingCandidates:
            publishAutoAdjustmentState(.renderingCandidates, progress: 0.5)
            statusMessage = "Rendering Auto candidates…"
        case .validating:
            publishAutoAdjustmentState(.validating, progress: 0.75)
            statusMessage = "Validating Auto candidates…"
        }
    }

    /// Analyze the current source, then atomically replace the accepted document. The result
    /// enters `updateDocument`, so it receives normal per-photo persistence and one undo
    /// operation. RAW/develop, legacy nodes, Looks, Effects, crop, mixer, and grading are retained.
    func runAutoAdjustment() {
        guard sourceImage != nil, previewState == .ready, let imageSource else { return }
        endUndoGrouping()

        // The toolbar is disabled while work is active, but this method is also an action seam
        // used by keyboard commands and tests. A direct second invocation supersedes the first.
        autoAdjustmentTask?.cancel()
        autoInvocationRevision &+= 1
        let invocationRevision = self.autoInvocationRevision

        let sourceRevision = self.sourceRevision
        let documentRevision = self.documentRevision
        let assetID = self.activeAssetID
        let currentDocument = document
        let currentLUT = resolvedLUT(document.lut.lutID)
        var analysisDocument = document
        analysisDocument.light = .neutral
        analysisDocument.color.vibrance = 0
        analysisDocument.color.saturation = 0
        // Do not compensate for an existing Look. Auto is a source baseline; applying it also
        // preserves the active Look on the document below.
        analysisDocument.lut = .none
        let engine = self.engine
        let photoAnalysisCoordinator = self.photoAnalysisCoordinator

        if let fingerprint = currentDocument.lastAutoRunFingerprint,
            fingerprint.matches(source: imageSource, document: currentDocument)
        {
            publishAutoAdjustmentState(.ready)
            statusMessage = "No further improvement found"
            autoAdjustmentTask = nil
            return
        }

        publishAutoAdjustmentState(.analyzing, progress: 0)
        statusMessage = "Analyzing \(sourceName) for Auto adjustments…"
        let onProgress: @MainActor @Sendable (AutoEnhancementPhase) -> Void = {
            [weak self] phase in
            self?.setAutoAdjustmentProgress(phase, invocationRevision: invocationRevision)
        }
        autoAdjustmentTask = Task { @MainActor [weak self, engine] in
            // The content-aware path is capability-gated only by the sampling seam. Engines that
            // expose only histogram rendering continue through the established global-only
            // fallback below; a missing optional semantic signal never blocks that fallback.
            if let assetID,
                let contentEngine = engine as? any RenderEngining & CurrentEditSampling,
                contentEngine is RenderEngine
            {
                let maskStore = photoAnalysisCoordinator.maskStore
                let result = await ContentAwareAutoEngine(
                    engine: contentEngine,
                    analysisCoordinator: photoAnalysisCoordinator,
                    maskStore: maskStore
                ).run(
                    source: imageSource,
                    assetID: assetID,
                    current: currentDocument,
                    lut: currentLUT,
                    onProgress: onProgress
                )
                guard !Task.isCancelled, let self,
                    self.autoInvocationRevision == invocationRevision
                else { return }
                let isSamePhoto =
                    self.activeAssetID == assetID
                    && self.sourceRevision == sourceRevision
                    && self.imageSource == imageSource
                guard isSamePhoto, self.documentRevision == documentRevision else {
                    if isSamePhoto { self.publishAutoAdjustmentState(.ready) }
                    return
                }
                switch result.status {
                case .improved:
                    let applied = EditDocument.applyingAutoResult(result, to: self.document)
                    self.publishAutoAdjustmentState(.applying, progress: 0.9)
                    self.statusMessage = "Applying Auto adjustments…"
                    self.updateDocument(preservingAutoResult: true) { document in
                        document = applied
                    }
                    self.publishAutoAdjustmentState(.ready)
                    let count = result.changedControls.count
                    self.statusMessage =
                        "Auto applied — \(count) coordinated control\(count == 1 ? "" : "s") (undo to restore previous edits)"
                case .unchanged:
                    self.publishAutoAdjustmentState(.ready)
                    self.statusMessage = "No further improvement found"
                case .noCandidate:
                    let message = result.reasons.first ?? "Auto found no acceptable improvement."
                    self.publishAutoAdjustmentState(.failed(message))
                    self.statusMessage = message
                case .cancelled:
                    self.publishAutoAdjustmentState(.ready)
                    self.statusMessage = "Auto cancelled; nothing was changed."
                case .staleRevision:
                    self.publishAutoAdjustmentState(.ready)
                    self.statusMessage = "Auto was superseded; nothing was changed."
                case .renderUnavailable:
                    // A renderer failure is recoverable and must not mutate the document. Keep
                    // the action available so a later retry can use a healthy render surface.
                    self.publishAutoAdjustmentState(
                        .failed(result.reasons.first ?? "Auto could not render the current edit."))
                    self.statusMessage = self.autoAdjustmentState.message
                }
                return
            }

            let photoAnalysis: PhotoAnalysis?
            if let assetID {
                photoAnalysis = try? await photoAnalysisCoordinator.analyze(
                    assetID: assetID, source: imageSource, level: .standard
                )
            } else {
                photoAnalysis = nil
            }

            guard !Task.isCancelled, let self,
                self.autoInvocationRevision == invocationRevision
            else { return }
            let isSamePhoto =
                self.activeAssetID == assetID
                && self.sourceRevision == sourceRevision
                && self.imageSource == imageSource
            guard isSamePhoto, self.documentRevision == documentRevision else {
                // A user edit can supersede an Auto request without changing the photo. Clear
                // only that photo's in-progress state; a navigation completion must not make the
                // newly selected photo look ready before its own preview is presented.
                if isSamePhoto { self.publishAutoAdjustmentState(.ready) }
                return
            }

            if let photoAnalysis,
                photoAnalysis.quality.globalToneAvailable,
                photoAnalysis.quality.overallConfidence
                    >= AutoLightConfiguration.default.confidenceFloor
            {
                let result = AutoLightEngine.evaluate(
                    analysis: photoAnalysis,
                    currentEdits: analysisDocument,
                    configuration: .default
                )
                var proposed = self.document
                proposed.light = result.light
                proposed.color.vibrance = result.color.vibrance
                proposed.color.saturation = result.color.saturation
                guard proposed.renderingHash != self.document.renderingHash else {
                    self.publishAutoAdjustmentState(.ready)
                    self.statusMessage = "No further improvement found"
                    return
                }
                let autoResult = AutoEnhancementResult(
                    proposedDocument: proposed,
                    fingerprint: AutoRunFingerprint.make(source: imageSource, document: proposed)
                )
                let applied = EditDocument.applyingAutoResult(autoResult, to: self.document)
                self.publishAutoAdjustmentState(.applying, progress: 0.9)
                self.statusMessage = "Applying Auto adjustments…"
                self.updateDocument(preservingAutoResult: true) { document in
                    document = applied
                }
                self.publishAutoAdjustmentState(.ready)
                self.statusMessage =
                    "Auto applied — subject-aware Light baseline (undo to restore previous edits)"
                return
            }

            self.setAutoAdjustmentProgress(
                .renderingCandidates, invocationRevision: invocationRevision)
            let histogram = await engine.histogram(
                source: imageSource,
                document: analysisDocument,
                lut: nil,
                scale: .preview(maxSize: CGSize(width: 1600, height: 1200)),
                space: .current,
                maxDimension: AutoAdjustmentSettings.default.histogramMaxDimension
            )

            guard !Task.isCancelled,
                self.autoInvocationRevision == invocationRevision
            else { return }
            let isSamePhotoAfterAnalysis =
                self.activeAssetID == assetID
                && self.sourceRevision == sourceRevision
                && self.imageSource == imageSource
            guard isSamePhotoAfterAnalysis, self.documentRevision == documentRevision else {
                if isSamePhotoAfterAnalysis { self.publishAutoAdjustmentState(.ready) }
                return
            }
            guard let histogram,
                let result = AutoAdjustmentAnalyzer.analyze(histogram: histogram)
            else {
                let message = "Auto could not analyze \(self.sourceName). Try reloading the photo."
                self.publishAutoAdjustmentState(.failed(message))
                self.statusMessage = message
                return
            }

            self.setAutoAdjustmentProgress(.validating, invocationRevision: invocationRevision)
            var proposed = self.document
            proposed.light = result.light
            proposed.color.vibrance = result.color.vibrance
            proposed.color.saturation = result.color.saturation
            guard proposed.renderingHash != self.document.renderingHash else {
                self.publishAutoAdjustmentState(.ready)
                self.statusMessage = "No further improvement found"
                return
            }
            let autoResult = AutoEnhancementResult(
                proposedDocument: proposed,
                fingerprint: AutoRunFingerprint.make(source: imageSource, document: proposed)
            )
            let applied = EditDocument.applyingAutoResult(autoResult, to: self.document)
            self.publishAutoAdjustmentState(.applying, progress: 0.9)
            self.statusMessage = "Applying Auto adjustments…"
            self.updateDocument(preservingAutoResult: true) { document in
                document = applied
            }
            self.publishAutoAdjustmentState(.ready)
            self.statusMessage =
                "Auto applied — Light and Color baseline (undo to restore previous edits)"
        }
    }

    /// Cancel the active Auto operation without giving a late renderer result a chance to commit.
    /// The cancelled state remains visible until the next settled preview or Auto attempt.
    func cancelAutoAdjustment() {
        guard isAutoAdjustmentInProgress else { return }
        autoInvocationRevision &+= 1
        autoAdjustmentTask?.cancel()
        autoAdjustmentTask = nil
        publishAutoAdjustmentState(.cancelled)
        statusMessage = "Auto cancelled; nothing was changed."
    }

    /// Await the active Auto task in tests and lifecycle owners without polling published state.
    /// The task is retained after completion until the next invocation so a caller can join a
    /// completion that already crossed its final renderer milestone.
    func waitForAutoAdjustmentCompletion() async {
        await autoAdjustmentTask?.value
    }

    private func resetAutoAdjustmentForLifecycle() {
        autoInvocationRevision &+= 1
        autoAdjustmentTask?.cancel()
        autoAdjustmentTask = nil
        publishAutoAdjustmentState(
            .unavailable("Auto is available when the photo preview is ready."))
    }

    // MARK: - Image loading

    private var portableLibraryFailureIsActive: Bool {
        portableLibrary != nil || portableLibraryOpenError != nil
    }

    private func reloadPortableCollection() throws {
        guard let portableLibrary else { return }
        collection.loadPortableAssets(try portableLibrary.materializedAssets())
        navigation.move(to: .grid)
        collection.beginThumbnailDemand()
    }

    private func openPortableAsset(_ assetID: PortablePhotoAssetID) {
        guard let item = collection.items.first(where: {
            $0.asset.source.portableIdentity.assetID == assetID
        }), let url = item.url else {
            statusMessage = "The imported photo is not available in the package index."
            return
        }
        openImage(url: url, assetID: item.id)
    }

    func openImage(url: URL) {
        cancelPendingPreviewDebounce()
        if let portableLibrary {
            do {
                let result = try portableLibrary.importURLs([url])
                let assetID = result.imported.first?.assetID
                    ?? result.duplicates.first?.existingAssetID
                try reloadPortableCollection()
                if let assetID { openPortableAsset(assetID) }
            } catch {
                presentError("Kromora could not import \(url.lastPathComponent): \(error.localizedDescription)")
            }
            return
        }
        guard !portableLibraryFailureIsActive else { return }
        let ids = collection.addFromURLs([url])
        navigation.move(to: .edit)
        guard let assetID = ids.first,
            collection.items.contains(where: { $0.id == assetID })
        else {
            // Keep the editor's actionable failure state for a missing/unsupported URL even
            // though there is no durable library item to adopt.
            load(name: url.lastPathComponent, url: url, data: nil)
            return
        }
        selectCollectionItem(id: assetID)
        let item = collection.items.first(where: { $0.id == assetID })
        let durableURL = item?.url
        // Keep the one-off editor's source label compatible with the URL picker and with
        // source-folder opens; the collection item itself uses the extension-free display name.
        load(
            name: url.lastPathComponent, url: durableURL ?? url, data: nil, assetID: assetID,
            portableIdentity: item.flatMap { persistencePortableIdentity(for: $0) }
        )
    }

    private func openImage(url: URL, assetID: PhotoAssetID) {
        cancelPendingPreviewDebounce()
        navigation.move(to: .edit)
        focusCollectionItem(id: assetID)
        let item = collection.items.first(where: { $0.id == assetID })
        let itemName = item?.displayName
        let name =
            itemName.map { displayName in
                guard !url.pathExtension.isEmpty,
                    !displayName.lowercased().hasSuffix(".\(url.pathExtension.lowercased())")
                else {
                    return displayName
                }
                return "\(displayName).\(url.pathExtension)"
            } ?? url.lastPathComponent
        load(
            name: name, url: url, data: nil, assetID: assetID,
            portableIdentity: item.flatMap { persistencePortableIdentity(for: $0) }
        )
    }

    /// Referenced-folder files keep their file-backed legacy identity so two distinct files with
    /// identical bytes cannot alias one another's edit record. Managed imports carry the opaque
    /// UUID assigned when they entered the library and remain relocation-safe.
    private func persistencePortableIdentity(for item: ImageCollection.Item)
        -> PortablePhotoIdentity?
    {
        guard collection.sourceKind(for: item) == .managed else { return nil }
        return item.asset.source.portableIdentity
    }

    private func selectCollectionItem(id: PhotoAssetID) {
        guard let index = collection.items.firstIndex(where: { $0.id == id }) else { return }
        collection.select(at: index)
    }

    private func focusCollectionItem(id: PhotoAssetID) {
        collection.focus(id: id)
    }

    private func cancelPendingPreviewDebounce() {
        previewDebounceGeneration &+= 1
        previewDebounceTask?.cancel()
        previewDebounceTask = nil
        previewPresentation.cancelCacheLookup()
        pendingPreviewCacheLookup = nil
        previewCoordinator.cancel()
    }

    /// Invalidate an edited-thumbnail operation without removing a bitmap that has already been
    /// published for the item. Cancellation is cooperative — a renderer may still be returning
    /// from a framework call — so the generation bump is the durable fence for that late result.
    private func invalidateEditedThumbnailWork(for assetID: PhotoAssetID?) {
        guard let assetID else { return }
        editedThumbnailGenerations[assetID] = (editedThumbnailGenerations[assetID] ?? 0) &+ 1
        editedThumbnailDebounceTasks[assetID]?.cancel()
        editedThumbnailDebounceTasks[assetID] = nil
        workScheduler.cancel(
            id: ImageWorkScheduler.JobID(editedThumbnailJobPrefix + assetID.raw), pump: false
        )
    }

    /// Stop cache-only work before any user-visible operation gets a chance to enter the editor
    /// lane. The scheduler's background job may already be inside one Core Image call; cancellation
    /// bounds that unavoidable tail to the current item and the generation guards the result.
    private func cancelIdlePreviewBuild(resetCursor: Bool = false) {
        idleBuildGeneration &+= 1
        idleBuildTask?.cancel()
        idleBuildTask = nil
        workScheduler.cancel(id: idlePreviewBuildJobID, pump: false)
        if resetCursor { idleBuildCursor = nil }
    }

    /// Prepare a source without decoding pixels, then publish it and render the previews. RAW
    /// demosaicing remains renderer-owned and happens at the requested preview scale. The worker
    /// below deliberately has one active preparation and one replaceable pending request.
    private func load(
        name: String, url: URL?, data: Data?, assetID: PhotoAssetID? = nil,
        traceQuality: String = "open", dataFingerprint: String? = nil,
        portableIdentity: PortablePhotoIdentity? = nil
    ) {
        guard !isShuttingDown else { return }
        // A real open always wins over cache-only work. Keep this adjacent to the existing
        // prefetch cancellation: the two jobs have separate identities and separate lifecycles.
        cancelIdlePreviewBuild(resetCursor: true)
        let importPlan = SourceImportPlan(
            name: name, url: url, data: data, assetID: assetID,
            portableIdentity: portableIdentity, dataFingerprint: dataFingerprint,
            traceQuality: traceQuality
        )
        let assetID = importPlan.assetID
        endUndoGrouping()
        resetAutoAdjustmentForLifecycle()
        smartMaskCreationTask?.cancel()
        smartMaskCreationTask = nil
        smartMaskRetryContext = nil
        // Discrete edits are queued normally; switching sources is a durability boundary for them.
        // Do not rewrite an unchanged document merely because navigation occurred.
        requestPersistenceFlush()
        let previousActiveAssetID = activeAssetID
        activeAssetID = assetID
        let sourceReference = importPlan.sourceReference
        activeSourceReference = sourceReference
        let session = editorDocument.session(for: assetID)
        document = session?.document ?? EditDocument()
        comparisonBaselineDocument = document.comparisonBaseline
        editorDocument.activate(session: session)
        lastReportedMissingLUT = nil
        lutResolutionStatus = nil
        refreshLUTResolutionStatus()

        previewPresentation.resetForSource()
        storedEditsResolvedSourceRevision = nil
        cancelHistogram(clear: true, pump: false)
        previewCoordinator.cancel()
        invalidateEditedThumbnailWork(for: previousActiveAssetID)
        pendingEditedThumbnailAssetID = nil
        previewSurface.clear()
        originalPreviewSurface.clear()
        canvasState.resetForSource()
        maskInteractionState.resetForSource()
        restoreMaskSelection()
        resetResolutionPlanners()
        // Do not let the previous surface briefly show the photo we are leaving while the new
        // source is being decoded.
        sourceImage = nil
        previewState = .loading
        // The old source must not describe the empty/loading state or gate the new image's
        // inspector while its pixels are being decoded.
        imageSource = nil
        lastPresentedVisibleRequest = nil
        lastPresentedVisibleImage = nil
        lastPublishedVisibleRequest = nil
        sourceURL = nil
        sourceSize = .zero
        isPreviewInteractionActive = false
        // Space comparison is transient and belongs to the source being left. The user's
        // single-vs-side-by-side preference intentionally remains intact across photo switches.
        isShowingOriginal = false
        metadata = ImageMetadata()
        cancelComparisonPreview(pump: false)
        comparisonPreviewRetryTask?.cancel()
        comparisonPreviewRetryTask = nil
        comparisonPreviewScheduledRevision = nil
        workScheduler.cancel(id: adjacentPreviewPrefetchJobID, pump: false)
        prefetchDelayTask?.cancel()
        prefetchDelayTask = nil
        cancelPendingPreviewDebounce()
        rawCapabilities = nil
        capabilitiesProbeCompleted = false
        // A pending develop flag describes the image being left; it must not survive onto whatever
        // opens next, or an unrelated first edit on the new image would render a comparison baseline
        // for develop settings that were never actually touched on it.
        pendingDevelopChange = false
        // Keep the tab during the transient no-source interval. The new source publication below
        // validates it once its actual capabilities are known; resetting here would make an import
        // change an unrelated inspector preference merely because source preparation is async.

        isLoading = true
        statusMessage = "Loading \(name)..."

        sourceSession.begin(
            plan: importPlan,
            editSessionRevision: editorDocument.revision(for: assetID),
            hadInMemorySession: session != nil
        )
    }

    private func install(
        preparation: ImageSourcePreparation, request: SourceSessionCoordinator.Request
    ) {
        imageSource = preparation.source
        previewScheduledSourceRevision = nil
        if case .url(let url) = request.plan.source.backing {
            sourceURL = url
        } else {
            sourceURL = nil
        }
        sourceName = request.plan.name
        sourceSize = preparation.nativeExtent
        // This marker is availability state only. It is never sent to RenderEngine, histogram, or
        // detail assessment; the authoritative color-managed pixels come from the edited render.
        sourceImage = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0)).cropped(
            to: CGRect(origin: .zero, size: preparation.nativeExtent)
        )
        previewState = .loading
        if request.plan.source.kind != .raw {
            statusMessage =
                "\(request.plan.name)  \(Int(preparation.nativeExtent.width))\u{00D7}\(Int(preparation.nativeExtent.height))"
        }
        isLoading = false
        keepInspectorTabValid()
        scheduleAdjacentPreviewPrefetch()
    }

    /// Present the source-session's optional camera JPEG while the RAW render is loading. The
    /// provisional frame is deliberately not a `PreviewCoordinator` publication and therefore
    /// cannot admit histogram, comparison, or cache work.
    private func presentEmbeddedFirstFrame(
        _ publication: SourceSessionCoordinator.FirstFramePublication
    ) {
        guard publication.request.sourceRevision == sourceRevision,
            publication.request.assetID == activeAssetID,
            previewState == .loading,
            lastPublishedVisibleRequest == nil,
            let cgImage = publication.image.cgImage(
                forProposedRect: nil, context: nil, hints: nil
            ) else { return }

            // The camera JPEG is a stand-in for the whole photo. Do not rasterize it at
            // native RAW size — that is a 24–60MP GPU upload on every filmstrip click and
            // stalls the develop that should replace it. Keep the JPEG's own pixels and tell
            // the surface to stretch them across the native Fit/Fill frame. If the preview
            // is still sensor-landscape while native display size is portrait, rotate first
            // so the stretch cannot look like a 90° error.
            let native = publication.preparation.nativeExtent
            let provisional = Self.alignedEmbeddedFirstFrame(
                CIImage(cgImage: cgImage), to: native
            )

            // The settled preview is submitted through the coordinator and always publishes at a
            // newer surface revision. The guards above keep a late provisional JPEG from ever
            // replacing that settled frame, so no explicit clear is needed here.
            previewSurface.present(
                provisional, space: .current,
                revision: displayRevision,
                source: publication.preparation.source,
                quality: .preview,
                presentationImageExtent: CGRect(origin: .zero, size: native),
                coversPresentationExtent: true,
                onPresented: nil
            )
    }

    /// Camera previews are often still sensor-landscape when the RAW's display size is portrait.
    /// Stretching that JPEG onto the native frame looks like a 90° rotation; one quarter-turn
    /// that matches native aspect is enough, and a matching pair of axes is a no-op.
    static func alignedEmbeddedFirstFrame(_ image: CIImage, to native: CGSize) -> CIImage {
        let src = image.extent.size
        guard src.width > 1, src.height > 1, native.width > 1, native.height > 1,
            src.width.isFinite, src.height.isFinite,
            native.width.isFinite, native.height.isFinite
        else {
            return image
        }
        let srcLandscape = src.width >= src.height
        let nativeLandscape = native.width >= native.height
        guard srcLandscape != nativeLandscape else { return image }
        let nativeAspect = native.width / native.height
        func aspectMismatch(_ candidate: CIImage) -> CGFloat {
            let size = candidate.extent.size
            guard size.height > 0 else { return .greatestFiniteMagnitude }
            return abs(size.width / size.height - nativeAspect)
        }
        let right = image.oriented(.right)
        let left = image.oriented(.left)
        return aspectMismatch(right) <= aspectMismatch(left) ? right : left
    }

    private func adoptStoredEdits(
        _ stored: EditDocumentLoadResult, for request: SourceSessionCoordinator.Request
    ) {
        // A pre-existing session or a mutation made while preparation was in flight owns the
        // current document. Only a still-pristine, never-seen session may adopt disk state.
        let changedInMemory =
            editorDocument.revision(for: request.assetID) != request.editSessionRevision
        let shouldAdopt = !request.hadInMemorySession && !changedInMemory
        var documentChanged = false
        if shouldAdopt {
            documentChanged = document != stored.document
            document = stored.document
            sourceSize = document.rotation.orientedExtent(imageSource?.nativeExtent ?? sourceSize)
            comparisonBaselineDocument = document.comparisonBaseline
            editorDocument.adoptStoredDocument(document, for: request.assetID)
            restoreMaskSelection()
            refreshLUTResolutionStatus()
            if documentChanged {
                documentRevision &+= 1
                previewPresentation.advanceComparisonRevision()
                scheduleAdjacentPreviewPrefetch()
            }
        }
        storedEditsResolvedSourceRevision = sourceRevision
        // A cold open already rendered the identity document speculatively. Only an adopted disk
        // document that differs from that first request needs a corrective render. In-memory
        // sessions and edits made while loading remain authoritative and must not be replaced.
        // The corrective queues behind the speculation instead of cancelling it, so the first
        // request still reaches the engine (LUMO-317).
        if shouldAdopt, documentChanged {
            scheduleCorrectivePreview()
        } else if let lastPresentedVisibleRequest,
            lastPresentedVisibleRequest.source == imageSource,
            lastPresentedVisibleRequest.document == displayRequest.document
        {
            // If the speculative frame already reached the drawable, it was intentionally not
            // allowed to start histogram work. Re-admit that final request now that persistence
            // has confirmed it is the document on screen.
            updateHistogram(
                for: lastPresentedVisibleRequest, presentedImage: lastPresentedVisibleImage)
        }
        scheduleEditedThumbnailAfterSettle(for: request.assetID, priority: .activeEditor)
        applyStoredLoadStatus(stored.status)
    }

    private func applyStoredLoadStatus(_ status: EditDocumentStore.Status) {
        // Load banners are scoped to the active photo. A relink notice is useful for the photo
        // just opened, a corrupt-record warning belongs only to that record, and a load-time
        // write failure belongs only to that attempt. None should leak from photo A to photo B;
        // the store's separate worstActionableStatus owns any deliberately sticky diagnostic.
        editStoreStatus = status.isActionable ? status.message : nil
    }

    /// Warm at most the two nearest filtered neighbours after the active render has had an idle
    /// window. The request is cancellable at the orchestration layer and the snapshot is value-only;
    /// an obsolete prefetch may finish in the renderer, but it cannot publish or start source-load
    /// work for a photo the user has already left.
    private func scheduleAdjacentPreviewPrefetch() {
        workScheduler.cancel(id: adjacentPreviewPrefetchJobID)
        prefetchDelayTask?.cancel()
        prefetchDelayTask = nil
        guard collection.isActive else { return }

        let selected = collection.selectedIndex
        let candidates = collection.filteredIndices
            .filter { $0 != selected && abs($0 - selected) <= 2 }
            .sorted { abs($0 - selected) < abs($1 - selected) }
            .prefix(2)
            .compactMap { index -> AdjacentPreviewCandidate? in
                let item = collection.items[index]
                guard let dimensions = item.asset.dimensions,
                    dimensions.width > 0, dimensions.height > 0
                else { return nil }
                let extent = CGSize(width: dimensions.width, height: dimensions.height)
                let source: ImageSource
                if let url = item.url {
                    source = ImageSource(
                        url: url, nativeExtent: extent,
                        portableIdentity: item.asset.source.portableIdentity
                    )
                } else if let data = item.imageData {
                    source = ImageSource(
                        data: data, nativeExtent: extent, dataFingerprint: item.dataFingerprint,
                        portableIdentity: item.asset.source.portableIdentity
                    )
                } else {
                    return nil
                }
                return AdjacentPreviewCandidate(
                    source: source,
                    inMemoryDocument: editorDocument.session(for: item.id)?.document,
                    reference: EditSourceReference(
                        assetID: item.id, portableIdentity: persistencePortableIdentity(for: item),
                        url: item.url
                    )
                )
            }
        guard !candidates.isEmpty else { return }

        let revision = sourceRevision
        let assetID = activeAssetID
        let engine = self.engine
        let editStore = self.editStore
        prefetchDelayTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled, let self,
                self.activeAssetID == assetID,
                self.sourceRevision == revision
            else { return }

            // Resolve all cold neighbors before admitting the scheduler job. The editor lane is
            // reserved for renderer work, and a corrupt/unavailable record must not be converted
            // into a guessed identity document that is immediately discarded on open.
            let coldCandidates = candidates.filter { $0.inMemoryDocument == nil }
            let storedResults = await editStore.load(for: coldCandidates.map(\.reference))
            guard !Task.isCancelled,
                self.activeAssetID == assetID,
                self.sourceRevision == revision
            else { return }

            var storedResultIndex = 0
            var requests: [RenderRequest] = []
            requests.reserveCapacity(candidates.count)
            for candidate in candidates {
                let document: EditDocument
                if let inMemory = candidate.inMemoryDocument {
                    document = inMemory
                } else {
                    let stored = storedResults[storedResultIndex]
                    storedResultIndex += 1
                    guard stored.isUsableForPrefetch else { continue }
                    document = stored.document
                }
                requests.append(
                    self.makeSettledPreviewRequest(
                        source: candidate.source,
                        assetID: candidate.reference.assetID,
                        document: document,
                        lut: self.resolvedLUT(document.lut.lutID),
                        plan: self.adjacentPreviewPlan(
                            for: document, nativeExtent: candidate.source.nativeExtent
                        )
                    )
                )
            }
            guard !requests.isEmpty,
                !Task.isCancelled,
                self.activeAssetID == assetID,
                self.sourceRevision == revision
            else { return }

            self.workScheduler.enqueue(
                id: self.adjacentPreviewPrefetchJobID, lane: .editor, priority: .background
            ) { [weak self, engine] in
                guard !Task.isCancelled, let self,
                    self.activeAssetID == assetID,
                    self.sourceRevision == revision
                else { return }
                for request in requests {
                    guard !Task.isCancelled,
                        self.activeAssetID == assetID,
                        self.sourceRevision == revision
                    else { return }
                    _ = await engine.makeCIImage(request)
                }
            }
        }
    }

    /// Start the slower, folder-wide cache-fill wave after a settled frame. The sleep is the idle
    /// admission window; every guard is repeated after it because source preparation, edits, and
    /// interaction can all make the original quiet period obsolete.
    private func scheduleIdlePreviewBuild() {
        guard idleBuildTask == nil else { return }
        cancelIdlePreviewBuild()
        guard collection.isActive,
            !collection.isScanning,
            !sourceSession.isBusy,
            previewDebounceTask == nil,
            !isPreviewInteractionActive,
            !sourceSession.isBusy,
            NSApplication.shared.isActive
        else { return }

        let candidates = collection.filteredIndices
            .filter { $0 != collection.selectedIndex }
            .sorted { abs($0 - collection.selectedIndex) < abs($1 - collection.selectedIndex) }
            .compactMap { index -> IdlePreviewCandidate? in
                let item = collection.items[index]
                guard let dimensions = item.asset.dimensions,
                    dimensions.width > 0, dimensions.height > 0
                else { return nil }
                let extent = CGSize(width: dimensions.width, height: dimensions.height)
                let source: ImageSource
                if let url = item.url {
                    source = ImageSource(
                        url: url, nativeExtent: extent,
                        portableIdentity: item.asset.source.portableIdentity
                    )
                } else if let data = item.imageData {
                    source = ImageSource(
                        data: data, nativeExtent: extent, dataFingerprint: item.dataFingerprint,
                        portableIdentity: item.asset.source.portableIdentity
                    )
                } else {
                    return nil
                }
                return IdlePreviewCandidate(
                    index: index, source: source,
                    inMemoryDocument: editorDocument.session(for: item.id)?.document,
                    reference: EditSourceReference(
                        assetID: item.id, portableIdentity: persistencePortableIdentity(for: item),
                        url: item.url
                    )
                )
            }
        guard !candidates.isEmpty else { return }

        let generation = idleBuildGeneration
        let revision = sourceRevision
        let selectedAssetID = activeAssetID
        idleBuildTask = Task { [weak self, candidates, generation, revision, selectedAssetID] in
            try? await Task.sleep(for: .milliseconds(1500))
            guard !Task.isCancelled, let self,
                !self.isShuttingDown,
                self.idleBuildGeneration == generation,
                self.sourceRevision == revision,
                self.activeAssetID == selectedAssetID,
                self.collection.isActive,
                !self.collection.isScanning,
                !self.sourceSession.isBusy,
                self.previewDebounceTask == nil,
                !self.isPreviewInteractionActive,
                !self.sourceSession.isBusy,
                NSApplication.shared.isActive
            else {
                if let self, self.idleBuildGeneration == generation {
                    self.idleBuildTask = nil
                }
                return
            }
            await self.runIdlePreviewBuild(
                candidates: candidates, generation: generation, sourceRevision: revision,
                selectedAssetID: selectedAssetID
            )
            if self.idleBuildGeneration == generation {
                self.idleBuildTask = nil
            }
        }
    }

    /// Fill only the disk cache. No publication path is reachable from here: this job never calls
    /// `previewSurface`, `PreviewCoordinator`, `previewState`, histogram work, or selection APIs.
    /// The background priority and single editor lane mean the worst-case added latency to a user
    /// open is one in-flight background develop, and only if it started before cancellation landed.
    private func runIdlePreviewBuild(
        candidates: [IdlePreviewCandidate], generation: UInt64, sourceRevision: UInt64,
        selectedAssetID: PhotoAssetID?
    ) async {
        let start = min(idleBuildCursor ?? 0, candidates.count)
        guard start < candidates.count else { return }
        let sessionCandidates = Array(
            candidates[start..<candidates.count].prefix(Self.maxItemsPerIdleSession)
        )
        let coldCandidates = sessionCandidates.filter { $0.inMemoryDocument == nil }
        let storedResults = await editStore.load(for: coldCandidates.map(\.reference))
        guard !Task.isCancelled,
            idleBuildGeneration == generation,
            self.sourceRevision == sourceRevision,
            activeAssetID == selectedAssetID,
            !collection.isScanning,
            NSApplication.shared.isActive
        else { return }

        var storedResultIndex = 0
        var workItems: [IdlePreviewWorkItem] = []
        workItems.reserveCapacity(sessionCandidates.count)
        for (offset, candidate) in sessionCandidates.enumerated() {
            let cursor = start + offset
            let document: EditDocument
            if let inMemory = candidate.inMemoryDocument {
                document = inMemory
            } else {
                guard storedResults.indices.contains(storedResultIndex) else {
                    workItems.append(IdlePreviewWorkItem(cursor: cursor, request: nil))
                    storedResultIndex += 1
                    continue
                }
                let stored = storedResults[storedResultIndex]
                storedResultIndex += 1
                guard stored.isUsableForPrefetch else {
                    workItems.append(IdlePreviewWorkItem(cursor: cursor, request: nil))
                    continue
                }
                document = stored.document
            }

            let plan = canonicalPreviewPlan(
                for: document, nativeExtent: candidate.source.nativeExtent
            )
            let request = makeSettledPreviewRequest(
                source: candidate.source, assetID: candidate.reference.assetID,
                document: document, lut: resolvedLUT(document.lut.lutID), plan: plan,
                canonical: true
            )
            // This is metadata/stat work only. Do not decode pixels merely to decide whether to
            // render; an exact key hit is enough to skip the candidate.
            workItems.append(
                IdlePreviewWorkItem(
                    cursor: cursor,
                    request: previewPresentation.cache.contains(previewDiskCacheKey(for: request))
                        ? nil : request
                )
            )
        }

        guard !workItems.isEmpty, !Task.isCancelled else { return }
        let engine = self.engine
        let cache = self.previewPresentation.cache
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            workScheduler.enqueue(
                id: idlePreviewBuildJobID, lane: .editor, priority: .background,
                onTerminal: { _ in continuation.resume() }
            ) {
                [weak self, engine, cache, workItems, generation, sourceRevision, selectedAssetID]
                in
                guard let self else { return }
                for item in workItems {
                    guard !Task.isCancelled,
                        self.idleBuildGeneration == generation,
                        self.sourceRevision == sourceRevision,
                        self.activeAssetID == selectedAssetID,
                        !self.collection.isScanning,
                        NSApplication.shared.isActive
                    else { return }

                    guard let request = item.request else {
                        self.idleBuildCursor = item.cursor + 1
                        continue
                    }
                    let key = self.previewPresentation.cacheKey(for: request)
                    guard !cache.contains(key) else {
                        self.idleBuildCursor = item.cursor + 1
                        continue
                    }
                    let image = await engine.makeCIImage(request)
                    guard !Task.isCancelled,
                        self.idleBuildGeneration == generation,
                        self.sourceRevision == sourceRevision,
                        self.activeAssetID == selectedAssetID
                    else { return }
                    if let image { self.previewPresentation.writeCanonical(image, for: request) }
                    self.idleBuildCursor = item.cursor + 1
                }
            }
        }
    }

    func openImageDialog() {
        guard let urls = fileDialog.chooseImages(startingAt: settings.defaultSourceFolderURL) else {
            return
        }
        openImages(urls: urls)
    }

    /// Replace the one-off library with the selected files and open the first item. Keeping this
    /// separate from the AppKit panel makes the selection behavior deterministic to test and
    /// ensures an empty/cancelled result does not disturb the current edit.
    func openImages(urls: [URL]) {
        guard !urls.isEmpty else { return }
        if let portableLibrary {
            do {
                let result = try portableLibrary.importURLs(urls)
                try reloadPortableCollection()
                if let assetID = result.imported.first?.assetID
                    ?? result.duplicates.first?.existingAssetID
                { openPortableAsset(assetID) }
                if !result.failures.isEmpty {
                    statusMessage = "Imported \(result.imported.count) photo\(result.imported.count == 1 ? "" : "s"); "
                        + "skipped \(result.failures.count): "
                        + result.failures.map { $0.source.name }.joined(separator: ", ")
                }
            } catch {
                presentError("Kromora could not import the selected photos: \(error.localizedDescription)")
            }
            return
        }
        guard !portableLibraryFailureIsActive else { return }
        let ids = collection.addFromURLs(urls)
        guard let firstID = ids.first,
            let firstItem = collection.items.first(where: { $0.id == firstID }),
            let url = firstItem.url
        else { return }
        openImage(url: url, assetID: firstID)
    }

    // MARK: - Photo import

    func openImage(data: Data, name: String) {
        if let portableLibrary {
            do {
                let result = try portableLibrary.importData(data, name: name)
                try reloadPortableCollection()
                if let assetID = result.imported.first?.assetID
                    ?? result.duplicates.first?.existingAssetID
                { openPortableAsset(assetID) }
            } catch {
                presentError("Kromora could not import \(name): \(error.localizedDescription)")
            }
            return
        }
        guard !portableLibraryFailureIsActive else { return }
        let ids = collection.addFromData([(name: name, data: data)])
        navigation.move(to: .edit)
        guard let assetID = ids.first,
            let item = collection.items.first(where: { $0.id == assetID })
        else {
            load(name: name, url: nil, data: data)
            return
        }
        selectCollectionItem(id: assetID)
        load(
            name: item.displayName, url: item.url,
            data: item.url == nil ? data : nil, assetID: assetID,
            dataFingerprint: item.dataFingerprint,
            portableIdentity: item.asset.source.portableIdentity
        )
    }

    func importFromPhotos() {
        isPhotosPickerPresented = true
    }

    func beginPhotosImport(totalCount: Int) {
        photosImportCoordinator.begin(totalCount: totalCount)
    }

    func updatePhotosImportPhase(_ phase: PhotosImportProgress.Phase, name: String) {
        photosImportCoordinator.updatePhase(phase, name: name)
    }

    /// Append one transferred item and open the first successful item immediately. The payload is
    /// moved into the collection's source record; no batch array is retained by this method.
    func appendPhotosImport(
        _ item: ImageCollection.PhotoImportItem, ordinal: Int
    ) {
        photosImportCoordinator.append(item, ordinal: ordinal)
    }

    func preparePhotosImport(totalCount: Int) {
        cancelIdlePreviewBuild(resetCursor: true)
        didPresentInspectorForPhotosImport = false
        if portableLibrary != nil {
            isPortablePhotosImportActive = true
            portablePhotosImportNeedsRefresh = false
            portablePhotosImportWasEmpty = collection.items.isEmpty
            portablePhotosImportFirstAssetID = nil
            return
        }
        collection.beginDataImport(reservedCount: max(0, totalCount))
    }

    func insertPhotosImport(_ item: ImageCollection.PhotoImportItem, ordinal: Int) {
        if let portableLibrary {
            do {
                let result = try portableLibrary.importData(
                    item.data,
                    name: item.name,
                    rebuildIndex: !isPortablePhotosImportActive
                )
                let assetID = result.imported.first?.assetID
                    ?? result.duplicates.first?.existingAssetID
                if isPortablePhotosImportActive {
                    if let assetID, portablePhotosImportFirstAssetID == nil {
                        portablePhotosImportFirstAssetID = assetID
                    }
                    portablePhotosImportNeedsRefresh =
                        portablePhotosImportNeedsRefresh || !result.imported.isEmpty
                } else {
                    try reloadPortableCollection()
                    if collection.items.count == 1, let assetID {
                        openPortableAsset(assetID)
                        presentInspectorForFirstPhotosImportItem()
                    }
                }
            } catch {
                recordPhotosImportFailureDestination(
                    name: item.name, ordinal: ordinal
                )
            }
            return
        }
        let assetID = collection.appendDataImport(item, ordinal: ordinal)
        if collection.currentDataImportCount == 1 {
            selectCollectionItem(id: assetID)
            let durableURL = collection.items.first(where: { $0.id == assetID })?.url
            load(
                name: item.name, url: durableURL, data: durableURL == nil ? item.data : nil,
                assetID: assetID, traceQuality: "photosImport", dataFingerprint: item.contentDigest
            )
            presentInspectorForFirstPhotosImportItem()
        }
    }

    /// Present the existing inspector exactly once for the first accepted Photos payload. The
    /// selected tab belongs to the user's inspector preferences, so opening the panel must not
    /// force Info or disturb it; `load()` has already cleared metadata and histogram state for the
    /// new active source before this presentation change is published.
    private func presentInspectorForFirstPhotosImportItem() {
        guard !didPresentInspectorForPhotosImport else { return }
        didPresentInspectorForPhotosImport = true
        guard !inspectorState.isPresented else { return }
        inspectorState.isPresented = true
    }

    func recordPhotosImportFailure(name: String, ordinal: Int? = nil) {
        photosImportCoordinator.recordFailure(
            name: name, ordinal: ordinal, reason: "Photos returned no transferable data.")
    }

    func finishPhotosImport(cancelled: Bool) {
        photosImportCoordinator.finish(cancelled: cancelled)
    }

    func recordPhotosImportFailureDestination(name: String, ordinal: Int?) {
        if let ordinal {
            collection.recordDataImportFailure(ordinal: ordinal, name: name)
        } else {
            collection.recordDataImportFailure(name: name)
        }
    }

    func finishPhotosImportDestination(cancelled: Bool) {
        if let portableLibrary {
            guard isPortablePhotosImportActive else { return }
            defer {
                portableLibrary.finishImportBatch()
                isPortablePhotosImportActive = false
                portablePhotosImportNeedsRefresh = false
                portablePhotosImportWasEmpty = false
                portablePhotosImportFirstAssetID = nil
            }
            guard portablePhotosImportNeedsRefresh else { return }
            do {
                try portableLibrary.refreshIndex()
                try reloadPortableCollection()
                if portablePhotosImportWasEmpty,
                   let assetID = portablePhotosImportFirstAssetID
                {
                    openPortableAsset(assetID)
                    presentInspectorForFirstPhotosImportItem()
                }
            } catch {
                presentError(
                    "Kromora could not refresh the library after Photos import: "
                        + error.localizedDescription
                )
            }
            return
        }
        collection.finishDataImport()
    }

    func importPhotosData(_ items: [(name: String, data: Data)]) {
        if let portableLibrary {
            do {
                var firstAssetID: PortablePhotoAssetID?
                for item in items {
                    let result = try portableLibrary.importData(item.data, name: item.name)
                    firstAssetID = firstAssetID ?? result.imported.first?.assetID
                        ?? result.duplicates.first?.existingAssetID
                }
                try reloadPortableCollection()
                if let firstAssetID { openPortableAsset(firstAssetID) }
            } catch {
                presentError("Kromora could not import Photos data: \(error.localizedDescription)")
            }
            return
        }
        let ids = collection.addFromData(items)
        if let first = items.first, let firstID = ids.first,
            let firstItem = collection.items.first(where: { $0.id == firstID })
        {
            selectCollectionItem(id: firstID)
            load(
                name: first.name, url: firstItem.url,
                data: firstItem.url == nil ? first.data : nil, assetID: firstItem.id,
                dataFingerprint: firstItem.dataFingerprint
            )
        }
    }

    // MARK: - Removable media import

    var selectedRemovableMediaFiles: [MediaVolumeFile] {
        libraryMediaWorkflow.selectedRemovableMediaFiles
    }

    func refreshRemovableMedia() {
        libraryMediaWorkflow.refreshRemovableMedia()
    }

    func importFromRemovableMedia() {
        libraryMediaWorkflow.importFromRemovableMedia()
    }

    func openRemovableMedia(_ volume: MediaVolume) {
        libraryMediaWorkflow.openRemovableMedia(volume)
    }

    func toggleRemovableMediaSelection(_ file: MediaVolumeFile) {
        libraryMediaWorkflow.toggleRemovableMediaSelection(file)
    }

    func selectAllRemovableMedia() {
        libraryMediaWorkflow.selectAllRemovableMedia()
    }

    func selectNoRemovableMedia() {
        libraryMediaWorkflow.selectNoRemovableMedia()
    }

    func cancelRemovableMediaImport() {
        libraryMediaWorkflow.cancelRemovableMediaImport()
    }

    func importSelectedRemovableMedia() {
        libraryMediaWorkflow.importSelectedRemovableMedia()
    }


    private func importRemovableMedia(_ request: RemovableMediaImportRequest) {
        let volume = request.volume
        let files = request.files
        if let portableLibrary {
            do {
                let result = try portableLibrary.importURLs(files.map(\.url))
                try reloadPortableCollection()
                if let assetID = result.imported.first?.assetID
                    ?? result.duplicates.first?.existingAssetID
                { openPortableAsset(assetID) }
                libraryMediaWorkflow.finishImport(
                    imported: result.imported.count, skipped: 0, cancelled: false,
                    total: files.count
                )
            } catch {
                presentError(
                    "Kromora could not import removable-media photos: \(error.localizedDescription)"
                )
            }
            isRemovableMediaSelectorPresented = false
            return
        }

        guard !portableLibraryFailureIsActive else { return }
        let ids = collection.addFromMediaVolume(volume, files: files)
        if let first = files.first, let firstID = ids.first {
            isSourceBrowserPresented = false
            navigation.move(to: .grid)
            load(
                name: first.filename, url: first.url, data: nil, assetID: firstID,
                traceQuality: "removableMediaImport",
                portableIdentity: collection.items.first(where: { $0.id == firstID })?
                    .asset.source.portableIdentity
            )
        }
        libraryMediaWorkflow.finishImport(
            imported: ids.count, skipped: files.count - ids.count, cancelled: false,
            total: files.count
        )
        isRemovableMediaSelectorPresented = false
    }

    /// Choose a folder to use as the persistent image source, scan it (incl.
    /// subfolders), reveal the file browser, and open the first image.
    func chooseSourceFolder() {
        libraryMediaWorkflow.chooseSourceFolder(startingAt: settings.defaultSourceFolderURL)
    }

    /// Classify a dropped URL at the application boundary, then dispatch through the existing
    /// value-based open seams. Invalid or cancelled drops leave the current edit untouched.
    func handleDroppedURL(_ url: URL) {
        libraryMediaWorkflow.handleDroppedURL(url)
    }

    func handleDrop(_ payload: ImageDrop.Payload) {
        switch payload {
        case .urls(let urls):
            libraryMediaWorkflow.handleDroppedURLs(urls)
        case .image(let data, let name):
            openImage(data: data, name: name)
        case .promises(let receivers):
            droppedPromiseTask?.cancel()
            droppedPromiseTask = Task { @MainActor [weak self] in
                guard let self, !self.isShuttingDown else { return }
                ImageDrop.purgeDropDirectories()
                let directory: URL
                do {
                    directory = try ImageDrop.makeDropDirectory()
                } catch {
                    self.presentError(
                        "Kromora could not prepare the Photos drop: \(error.localizedDescription)"
                    )
                    return
                }
                defer { ImageDrop.purgeDropDirectories() }

                let result = await ImageDrop.receive(receivers, into: directory)
                if !result.urls.isEmpty {
                    // Promise URLs are already known to be files. Use the same durable multi-file
                    // path as other library imports rather than opening a Photos derivative URL.
                    self.openImages(urls: result.urls)
                }
                if !result.failures.isEmpty {
                    let prefix = result.urls.isEmpty ? "No Photos files imported" :
                        "Imported \(result.urls.count) Photos file\(result.urls.count == 1 ? "" : "s")"
                    self.statusMessage = "\(prefix); skipped \(result.failures.count): "
                        + result.failures.joined(separator: "; ")
                } else if result.urls.isEmpty {
                    self.statusMessage = "No Photos files could be redeemed."
                }
                self.droppedPromiseTask = nil
            }
        }
    }

    /// Adopt `url` as the source folder (persisted), reveal the browser, and
    /// open its first image. Shared by the menu/toolbar action and folder drops.
    func openSourceFolder(url: URL) {
        cancelIdlePreviewBuild(resetCursor: true)
        if let portableLibrary {
            let files = supportedImageURLs(in: url)
            guard !files.isEmpty else {
                statusMessage = "No supported images were found in \(url.lastPathComponent)."
                return
            }
            do {
                let result = try portableLibrary.importURLs(files)
                try reloadPortableCollection()
                if let assetID = result.imported.first?.assetID
                    ?? result.duplicates.first?.existingAssetID
                { openPortableAsset(assetID) }
            } catch {
                presentError("Kromora could not import the folder: \(error.localizedDescription)")
            }
            return
        }
        guard !portableLibraryFailureIsActive else { return }
        let didPersistBookmark = collection.setSourceFolder(url)
        if !didPersistBookmark {
            presentError(
                "Kromora could not save the source folder. "
                    + "It will not be restored on next launch."
            )
        }
        isSourceBrowserPresented = true
        navigation.move(to: .grid)
        collection.beginThumbnailDemand()
        openFirstImageWhenScanned()
    }

    private func supportedImageURLs(in folder: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: folder, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]
        ) else { return [] }
        return enumerator.compactMap { value in
            guard let url = value as? URL,
                  (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
                  ImageDecoder.supportedExtensions.contains(url.pathExtension.lowercased()),
                  FileManager.default.isReadableFile(atPath: url.path) else { return nil }
            return url
        }.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    func toggleSourceBrowser() {
        if navigation.isGrid, !navigate(to: .edit) { return }
        isSourceBrowserPresented.toggle()
    }

    func toggleLibraryGrid() {
        navigate(to: navigation.isGrid ? .edit : .grid)
    }

    /// Move between the two top-level workspaces. Entering Edit always uses the collection's active
    /// item, so a grid selection is handed off deterministically and never relies on a stale source
    /// image. The first folder scan is allowed to establish the initial Grid state asynchronously;
    /// user-triggered transitions require an actual active item.
    @discardableResult
    func navigate(to mode: NavigationState.Mode) -> Bool {
        switch mode {
        case .grid:
            guard collection.isActive else { return false }
            navigation.move(to: .grid)
            collection.beginThumbnailDemand()
            return true

        case .edit:
            guard collection.isActive, collection.selectedItem != nil else {
                return sourceImage != nil && setEditMode()
            }
            navigation.move(to: .edit)
            openActiveCollectionImage(loadMode: false)
            return true
        }
    }

    private func setEditMode() -> Bool {
        navigation.move(to: .edit)
        return true
    }

    /// Re-scan the current source folder for added/removed files.
    func refreshSource() {
        cancelIdlePreviewBuild(resetCursor: true)
        collection.refresh()
    }

    /// Capture the current Library selection for a destructive confirmation. The focused item is
    /// included by `ImageCollection` even for a keyboard/menu invocation with no explicit set.
    func requestDeleteSelectedLibraryItems() {
        guard navigation.isGrid else { return }
        let candidates = collection.deletionCandidates
        guard !candidates.isEmpty else {
            statusMessage = "Select at least one photo to remove"
            return
        }
        libraryDeletionConfirmation = LibraryDeletionConfirmation(candidates: candidates)
    }

    /// Confirm the previously captured target set. The actual work is asynchronous because edit
    /// records and analysis/mask caches are actor-isolated.
    func confirmDeleteSelectedLibraryItems() {
        guard let confirmation = libraryDeletionConfirmation else { return }
        libraryDeletionConfirmation = nil
        Task { @MainActor [weak self] in
            _ = await self?.deleteLibraryItems(confirmation.candidates)
        }
    }

    /// Delete the supplied Library targets. This is also the testable seam behind the confirmation
    /// UI: flush pending edits, clear durable derived data, move managed files to Trash, remove
    /// edit records, then commit the collection state. A per-item failure leaves that item alone.
    @discardableResult
    func deleteSelectedLibraryItems() async -> LibraryDeletionResult {
        await deleteLibraryItems(collection.deletionCandidates)
    }

    @discardableResult
    private func deleteLibraryItems(
        _ candidates: [ImageCollection.DeletionCandidate]
    ) async -> LibraryDeletionResult {
        let result = await libraryDeletionCoordinator.delete(candidates)
        guard !result.deletedIDs.isEmpty else {
            if let message = result.failures.first { presentError(message) }
            return result
        }

        let deletedSet = Set(result.deletedIDs)
        for id in deletedSet {
            editedThumbnailDebounceTasks[id]?.cancel()
            editedThumbnailDebounceTasks.removeValue(forKey: id)
            editedThumbnailGenerations.removeValue(forKey: id)
            editorDocument.removeSession(for: id)
            workScheduler.cancel(
                id: ImageWorkScheduler.JobID(editedThumbnailJobPrefix + id.raw), pump: false
            )
        }
        if let pendingEditedThumbnailAssetID, deletedSet.contains(pendingEditedThumbnailAssetID) {
            self.pendingEditedThumbnailAssetID = nil
        }
        _ = collection.removeItems(with: deletedSet)
        previewPresentation.cache.invalidateAll()
        Thumbnails.invalidateCache()
        await engine.invalidateRenderCaches()

        if let activeAssetID, deletedSet.contains(activeAssetID) {
            if collection.selectedItem != nil {
                openActiveCollectionImage(loadMode: false)
            } else {
                clearActiveSourceAfterLibraryDeletion()
            }
        }

        if !result.failures.isEmpty {
            presentError(
                "Removed \(result.deletedIDs.count) photo(s), but some photos could not be removed: "
                    + result.failures.joined(separator: " ")
            )
        } else {
            statusMessage = result.deletedIDs.count == 1
                ? "Photo removed from Library"
                : "Removed \(result.deletedIDs.count) photos from Library"
        }
        return result
    }


    private func clearActiveSourceAfterLibraryDeletion() {
        sourceSession.cancel()
        documentRevision &+= 1
        previewPresentation.advanceDisplayRevision()
        cancelPendingPreviewDebounce()
        previewCoordinator.cancel()
        sourceImage = nil
        imageSource = nil
        sourceURL = nil
        sourceName = ""
        sourceSize = .zero
        activeAssetID = nil
        activeSourceReference = nil
        editorDocument.clearActiveHistory()
        document = EditDocument()
        metadata = ImageMetadata()
        histogram = nil
        isLoading = false
        previewState = .empty
        previewSurface.clear()
        originalPreviewSurface.clear()
        inspectorState.isPresented = false
        statusMessage = "Open an image to get started"
        resetAutoAdjustmentForLifecycle()
    }

    func selectCollectionImage(at index: Int, additive: Bool = false) {
        guard collection.items.indices.contains(index) else { return }
        cancelIdlePreviewBuild(resetCursor: true)
        collection.select(at: index, modifiers: additive ? [.command] : [])
        let item = collection.items[index]
        requestEditedThumbnail(for: item.id, priority: .activeEditor)

        if let url = item.url {
            openImage(url: url, assetID: item.id)
        } else if let data = item.imageData {
            load(
                name: item.displayName, url: nil, data: data, assetID: item.id,
                dataFingerprint: item.dataFingerprint,
                portableIdentity: item.asset.source.portableIdentity
            )
        }
    }

    // MARK: - Edit-aware thumbnails

    /// Request one bounded edited-thumbnail render for a photo. The original thumbnail is already
    /// visible while this work runs, so a slow RAW or LUT render never blocks the editor or blanks a
    /// browsing cell. The job identity is per photo; the document hash and resolved Look fingerprint
    /// are the effective pixel revision applied at publication time.
    private func requestEditedThumbnail(
        for assetID: PhotoAssetID,
        priority: ImageWorkScheduler.Priority,
        force: Bool = false
    ) {
        guard !isShuttingDown,
            let item = collection.items.first(where: { $0.id == assetID })
        else { return }

        // A demand callback can arrive while the preview debounce is already pending (or after a
        // cell reappears during a gesture). Keep the active photo's request as value state and let
        // the settle path admit it; no thumbnail should enter the shared render actor in either
        // interval.
        if isPreviewInteractionActive || previewDebounceTask != nil {
            if assetID == activeAssetID {
                pendingEditedThumbnailAssetID = assetID
                editedThumbnailDebounceTasks[assetID]?.cancel()
                editedThumbnailDebounceTasks[assetID] = nil
                workScheduler.cancel(
                    id: ImageWorkScheduler.JobID(editedThumbnailJobPrefix + assetID.raw),
                    pump: false
                )
            }
            return
        }

        let jobID = ImageWorkScheduler.JobID(editedThumbnailJobPrefix + assetID.raw)
        if workScheduler.contains(jobID) {
            if force {
                workScheduler.cancel(id: jobID, pump: false)
            } else {
                workScheduler.updatePriority(for: jobID, to: priority)
                return
            }
        }

        // A completed result is shared by both surfaces. Repeated SwiftUI appearance callbacks
        // should not re-render it; a force request is reserved for explicit edit/look changes.
        if !force, item.editedThumbnailRevision != nil { return }

        let generation = (editedThumbnailGenerations[assetID] ?? 0) &+ 1
        editedThumbnailGenerations[assetID] = generation
        collection.invalidateEditedThumbnail(for: assetID)

        let source: ImageSource?
        if let url = item.url {
            source = ImageSource(
                url: url, nativeExtent: item.thumbnailNativeExtent,
                portableIdentity: item.asset.source.portableIdentity
            )
        } else if let data = item.imageData {
            source = ImageSource(
                data: data, nativeExtent: item.thumbnailNativeExtent,
                dataFingerprint: item.dataFingerprint,
                portableIdentity: item.asset.source.portableIdentity
            )
        } else {
            source = nil
        }
        guard let source else { return }

        let inMemoryDocument = editorDocument.session(for: assetID)?.document
        if let inMemoryDocument, inMemoryDocument.isIdentity {
            let revision = editedThumbnailRevision(document: inMemoryDocument, lut: nil)
            collection.applyEditedThumbnail(nil, for: assetID, revision: revision)
            return
        }
        let sourceReference = EditSourceReference(
            assetID: assetID, portableIdentity: persistencePortableIdentity(for: item),
            url: item.url
        )
        // Active thumbnails need a navigation fence as well as the per-asset generation: A → B → A
        // can otherwise let a cancelled A request publish into the second A session. Non-active
        // thumbnails remain useful across navigation, so their session revision is the document
        // fence and they are not tied to the active source generation.
        let thumbnailSourceRevision: UInt64? = assetID == activeAssetID ? self.sourceRevision : nil
        let thumbnailDocumentRevision =
            assetID == activeAssetID
            ? self.documentRevision : editorDocument.revision(for: assetID)
        let thumbnailSourceIdentity = source.cacheIdentity
        let engine = self.engine
        let editStore = self.editStore
        workScheduler.enqueue(
            id: jobID, lane: .thumbnail, priority: priority
        ) {
            [
                weak self, engine, editStore, source, sourceReference, assetID, generation,
                thumbnailSourceRevision, thumbnailDocumentRevision, thumbnailSourceIdentity
            ] in
            guard let self, !self.isShuttingDown,
                self.isCurrentEditedThumbnailRequest(
                    assetID: assetID, generation: generation,
                    sourceRevision: thumbnailSourceRevision,
                    documentRevision: thumbnailDocumentRevision,
                    sourceIdentity: thumbnailSourceIdentity
                )
            else { return }

            let document: EditDocument
            if let inMemoryDocument {
                document = inMemoryDocument
            } else {
                document = await editStore.load(for: sourceReference).document
            }
            guard !Task.isCancelled, !self.isShuttingDown,
                self.isCurrentEditedThumbnailRequest(
                    assetID: assetID, generation: generation,
                    sourceRevision: thumbnailSourceRevision,
                    documentRevision: thumbnailDocumentRevision,
                    sourceIdentity: thumbnailSourceIdentity
                )
            else { return }

            let lut = self.resolvedLUT(document.lut.lutID)
            let revision = self.editedThumbnailRevision(document: document, lut: lut)
            guard !document.isIdentity else {
                self.collection.applyEditedThumbnail(nil, for: assetID, revision: revision)
                return
            }

            // Metadata normally supplies the extent before a cell appears. Preparing the source
            // here is the safe fallback for a just-discovered cell and keeps the thumbnail render
            // at preview scale instead of accidentally rasterizing a full-resolution image.
            let renderSource = await engine.prepareSource(source)?.source ?? source
            let request = RenderRequest(
                source: renderSource,
                assetID: assetID,
                document: document,
                lut: lut,
                targetSize: CGSize(
                    width: Thumbnails.defaultMaxPixelSize,
                    height: Thumbnails.defaultMaxPixelSize),
                quality: .thumbnail,
                output: .raster, space: .current
            )
            let image: NSImage?
            if let cgImage = await engine.makeThumbnailCGImage(request) {
                image = NSImage(
                    cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            } else {
                image = nil
            }
            guard !Task.isCancelled, !self.isShuttingDown,
                self.isCurrentEditedThumbnailRequest(
                    assetID: assetID, generation: generation,
                    sourceRevision: thumbnailSourceRevision,
                    documentRevision: thumbnailDocumentRevision,
                    sourceIdentity: thumbnailSourceIdentity
                )
            else { return }
            self.collection.applyEditedThumbnail(image, for: assetID, revision: revision)
        }
    }

    /// Validate every value that can make an edited thumbnail stale. The collection item is checked
    /// again because a file-backed source can be replaced in place while a thumbnail is rendering.
    private func isCurrentEditedThumbnailRequest(
        assetID: PhotoAssetID,
        generation: UInt64,
        sourceRevision: UInt64?,
        documentRevision: UInt64,
        sourceIdentity: PortablePhotoIdentity
    ) -> Bool {
        guard !isShuttingDown,
            editedThumbnailGenerations[assetID] == generation,
            let item = collection.items.first(where: { $0.id == assetID })
        else { return false }

        let currentSource: ImageSource?
        if let url = item.url {
            currentSource = ImageSource(
                url: url, nativeExtent: item.thumbnailNativeExtent,
                portableIdentity: item.asset.source.portableIdentity
            )
        } else if let data = item.imageData {
            currentSource = ImageSource(
                data: data, nativeExtent: item.thumbnailNativeExtent,
                dataFingerprint: item.dataFingerprint,
                portableIdentity: item.asset.source.portableIdentity
            )
        } else {
            currentSource = nil
        }
        guard currentSource?.cacheIdentity == sourceIdentity else { return false }

        if let sourceRevision {
            guard activeAssetID == assetID,
                self.sourceRevision == sourceRevision,
                self.documentRevision == documentRevision
            else { return false }
        } else {
            guard editorDocument.revision(for: assetID) == documentRevision else { return false }
        }
        return true
    }

    private func editedThumbnailRevision(document: EditDocument, lut: CubeLUT?) -> String {
        document.editHash + ":" + (lut?.cacheFingerprint ?? "unresolved")
    }

    /// Keep the active photo's badge out of the shared renderer while a preview burst is active.
    /// One task survives the quiet period, so a slider drag can invalidate and replace a queued
    /// thumbnail without submitting one thumbnail per document tick.
    private func scheduleEditedThumbnailAfterSettle(
        for assetID: PhotoAssetID, priority: ImageWorkScheduler.Priority
    ) {
        guard !isShuttingDown, assetID == activeAssetID else { return }
        pendingEditedThumbnailAssetID = assetID
        editedThumbnailDebounceTasks[assetID]?.cancel()
        editedThumbnailDebounceTasks[assetID] = nil
        guard !isPreviewInteractionActive, previewDebounceTask == nil else { return }

        let sourceRevision = self.sourceRevision
        editedThumbnailDebounceTasks[assetID] = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled, let self,
                !self.isShuttingDown,
                self.sourceRevision == sourceRevision,
                self.activeAssetID == assetID,
                !self.isPreviewInteractionActive,
                self.previewDebounceTask == nil
            else { return }
            self.editedThumbnailDebounceTasks[assetID] = nil
            self.pendingEditedThumbnailAssetID = nil
            self.requestEditedThumbnail(for: assetID, priority: priority, force: true)
        }
    }

    private func cancelEditedThumbnailDebounce(for assetID: PhotoAssetID?) {
        guard let assetID else { return }
        editedThumbnailDebounceTasks[assetID]?.cancel()
        editedThumbnailDebounceTasks[assetID] = nil
    }

    /// A LUT scan can resolve or replace a file-backed Look without changing the edit document.
    /// Only items that already produced an edited thumbnail are revisited; demand admission still
    /// keeps the work bounded and avoids a full-library render after every Look-folder scan.
    private func refreshMaterializedEditedThumbnails() {
        for item in collection.items where item.editedThumbnailRevision != nil {
            let priority: ImageWorkScheduler.Priority =
                item.id == activeAssetID
                ? .activeEditor : .visibleGrid
            requestEditedThumbnail(for: item.id, priority: priority, force: true)
        }
    }

    // MARK: - Copy and paste

    /// Copy the active photo's value-state edits. RAW decoder defaults are represented by neutral
    /// optional settings, so copying never transfers a source photo's as-shot seed accidentally.
    func copyAllEdits() {
        guard activeAssetID != nil, sourceImage != nil else {
            statusMessage = "Open an image first"
            return
        }
        editorDocument.copy(document: document)
        statusMessage = "Copied all edits from \(sourceName)"
    }

    /// Paste to the active photo, or to every selected photo. Non-active destinations receive their
    /// own history entry and disk snapshot; they do not need to be opened first.
    func pasteEdits() {
        guard let clipboard = editClipboard else {
            statusMessage = "Copy edits first"
            return
        }

        let selected = collection.selectedItems
        if selected.isEmpty {
            guard activeAssetID != nil, let source = imageSource else {
                statusMessage = "Open an image first"
                return
            }
            endUndoGrouping()
            let updated = clipboard.applying(
                to: document, destinationIsRAW: source.kind == .raw
            )
            updateDocument { $0 = updated }
            statusMessage = "Pasted edits"
            return
        }

        endUndoGrouping()
        var pastedCount = 0
        for item in selected {
            let assetID = item.id
            let destinationIsRAW: Bool
            if let url = item.url {
                destinationIsRAW = ImageSource.kind(forExtension: url.pathExtension) == .raw
            } else if let data = item.imageData {
                destinationIsRAW = ImageSource.kind(forData: data) == .raw
            } else {
                destinationIsRAW = false
            }

            if assetID == activeAssetID {
                let updated = clipboard.applying(
                    to: document, destinationIsRAW: destinationIsRAW
                )
                updateDocument { $0 = updated }
            } else {
                let updated = clipboard.applying(
                    to: editorDocument.session(for: assetID)?.document ?? EditDocument(),
                    destinationIsRAW: destinationIsRAW
                )
                guard editorDocument.apply(updated, to: assetID) else { continue }
                requestEditedThumbnail(for: assetID, priority: .visibleGrid, force: true)
                queuePersistence(
                    updated,
                    for: EditSourceReference(
                        assetID: assetID, portableIdentity: persistencePortableIdentity(for: item),
                        url: item.url
                    ),
                    reportsStatus: false,
                    force: true
                )
            }
            pastedCount += 1
        }

        statusMessage =
            pastedCount == 1
            ? "Pasted edits to 1 photo"
            : pastedCount > 1 ? "Pasted edits to \(pastedCount) photos" : "Pasted edits"
        requestPersistenceFlush()
    }

    /// Select a grid cell without leaving the grid. This is what makes a multi-selection useful:
    /// Command-click and Shift-click change the batch while the active photo remains explicit.
    func selectLibraryItem(
        at index: Int,
        modifiers: LibrarySelectionModel.Modifiers = []
    ) {
        cancelIdlePreviewBuild(resetCursor: true)
        collection.select(at: index, modifiers: modifiers)
    }

    /// Apply a culling flag to the focused library asset. Pick/reject use the rapid-cull workflow
    /// and move to the next visible asset; rating changes stay on the current photo.
    @discardableResult
    func setFocusedFlag(_ flag: PhotoFlag, advance: Bool = false) -> Bool {
        let name = collection.selectedItem?.displayName
        let previousIndex = collection.selectedIndex
        let changed = collection.setFlag(flag, advance: advance)
        if changed { persistPortableLibraryStateIfNeeded() }
        if changed, let name {
            statusMessage =
                "\(name): \(flag == .pick ? "Picked" : flag == .reject ? "Rejected" : "Flag cleared")"
        }
        // `ImageCollection` owns browsing focus, but Edit also has a prepared/rendered source.
        // Keep them in lockstep after the rapid-cull advance so the filmstrip never highlights a
        // different photo from the one shown on the canvas.
        if advance, !navigation.isGrid, collection.selectedIndex != previousIndex {
            selectCollectionImage(at: collection.selectedIndex)
        }
        return changed
    }

    @discardableResult
    func setFocusedRating(_ rating: Int) -> Bool {
        let changed = collection.setRating(rating)
        if changed { persistPortableLibraryStateIfNeeded() }
        if changed, let item = collection.selectedItem {
            statusMessage =
                "\(item.displayName): \(rating == 0 ? "Rating cleared" : "Rated \(rating) stars")"
        }
        return changed
    }

    @discardableResult
    func undoCullingChange() -> Bool {
        let changed = collection.undoLastCullingChange()
        if changed { persistPortableLibraryStateIfNeeded() }
        return changed
    }

    private func persistPortableLibraryStateIfNeeded() {
        guard let portableLibrary, let assetID = collection.lastCullingAssetID,
              let item = collection.items.first(where: { $0.id == assetID }) else { return }
        do {
            try portableLibrary.updateLibraryState(
                for: item.asset.source.portableIdentity.assetID,
                rating: item.asset.rating,
                flag: item.asset.flag
            )
        } catch {
            presentError("Kromora could not update the library catalog: \(error.localizedDescription)")
        }
    }

    /// Enter the editor for the grid's active photo. Thumbnail availability is not a prerequisite;
    /// `openImage` starts the existing asynchronous RAW load immediately.
    func openActiveCollectionImage() {
        openActiveCollectionImage(loadMode: true)
    }

    /// Enter Edit from a Library double-click with the editor chrome in its expected presentation
    /// state. The source browser is an explicit Edit control, so it must not leak into this
    /// transition from the source-folder session; the inspector is the actionable editor surface
    /// for the newly opened photo.
    func openLibraryImageForEditing() {
        guard collection.selectedItem != nil else { return }
        isSourceBrowserPresented = false
        inspectorState.isPresented = true
        openActiveCollectionImage()
    }

    private func openActiveCollectionImage(loadMode: Bool) {
        guard let item = collection.selectedItem else { return }
        if loadMode { navigation.move(to: .edit) }

        // The library selection is the source of truth for the edit handoff. When returning from
        // the grid, the active item is often already prepared because the editor was left visible
        // behind the library. Reusing that source avoids clearing a valid preview (and the canvas
        // presentation state) just to revisit the same photo. If the surface was recreated or a
        // preview is still pending, explicitly request the visible render again.
        if activeAssetID == item.id {
            if imageSource != nil, sourceImage != nil {
                if previewSurface.image == nil {
                    previewState = .loading
                    schedulePreview()
                }
                return
            }
            // A source preparation can be non-cancellable. Let the in-flight, revision-checked
            // request finish instead of enqueueing a duplicate while the user is navigating.
            if sourceSession.isBusy { return }
        }

        if let url = item.url {
            openImage(url: url, assetID: item.id)
        } else if let data = item.imageData {
            if loadMode { navigation.move(to: .edit) }
            load(
                name: item.displayName, url: nil, data: data, assetID: item.id,
                dataFingerprint: item.dataFingerprint,
                portableIdentity: item.asset.source.portableIdentity
            )
        }
    }

    func selectPreviousImage() {
        guard collection.isActive else { return }
        let prev = collection.selectedIndex
        collection.selectPrevious()
        if collection.selectedIndex != prev {
            selectCollectionImage(at: collection.selectedIndex)
        }
    }

    func selectNextImage() {
        guard collection.isActive else { return }
        let prev = collection.selectedIndex
        collection.selectNext()
        if collection.selectedIndex != prev {
            selectCollectionImage(at: collection.selectedIndex)
        }
    }

    // MARK: - Look selection

    func selectLook(_ look: CubeLUT?) {
        // A derived LUT is in no library, so nothing but the registry can resolve it later. Remember
        // it rather than replacing the last one: a document made now must still resolve after the
        // user derives again.
        if let look, look.lutID.isDerived { derivedRegistry.register(look) }
        endUndoGrouping()
        updateDocument { $0.lut.lutID = look?.lutID }
        refreshLUTResolutionStatus()
    }

    /// Select a Look by its stable document ID. The browser binds to IDs rather than resolved LUT
    /// values so the explicit None row and a missing file remain distinct selections.
    func selectLook(id: LUTID?) {
        guard let id else {
            selectLook(nil)
            return
        }
        guard let look = resolvedLUT(id) else {
            if library.isScanning {
                statusMessage =
                    "Look is still loading. Try selecting it again when scanning finishes."
            } else {
                // Keep an unresolved persisted ID intact, but make an attempted selection
                // observable and recoverable through the inspector's clear action.
                refreshLUTResolutionStatus()
            }
            return
        }
        selectLook(look)
    }

    /// Historical model-name compatibility for existing integrations and persisted-workflow
    /// tests. New editor code should use the Look-named actions above.
    func selectLUT(_ lut: CubeLUT?) { selectLook(lut) }

    func selectLUT(id: LUTID?) { selectLook(id: id) }

    /// Mutate the document and re-render.
    ///
    /// The only way to reach `rawDevelop` and `adjustments` today. The inspector that will drive them
    /// from the UI is Step 10; until it exists this is the seam those fields are tested through, and
    /// it is what the inspector will call. Keeping `document` `private(set)` behind it means every
    /// mutation goes through one place that knows to re-render.
    func updateDocument(_ transform: (inout EditDocument) -> Void) {
        updateDocument(
            debounced: false, invalidatesComparisonBaseline: false, preservingAutoResult: false,
            transform)
    }

    /// Mutate the document and re-render, optionally coalescing a burst of edits into one render.
    ///
    /// **`debounced: true` is for continuous controls only** — a slider drag, where the user
    /// produces tens of values per second and only the one they settle on matters. `PHASE2_SPEC.md`
    /// §6 is explicit that open and filmstrip navigation must stay immediate, and discrete controls
    /// (toggles, resets) should too: a checkbox that lagged 60 ms would feel broken.
    ///
    /// The document itself is updated **immediately** either way. Only the render is deferred, so
    /// the control stays glued to the pointer and `document` is always the truth. Deferring the
    /// document as well would mean a read-back mid-drag saw a stale value.
    ///
    /// Worth the machinery because a comparison-frame develop change costs *two* renders —
    /// `scheduleOriginalPreview` as well as `schedulePreview`. White-balance Temperature/Tint are
    /// the exception: they are evaluated against, rather than incorporated into, the comparison
    /// frame.
    func updateDocument(debounced: Bool, _ transform: (inout EditDocument) -> Void) {
        updateDocument(
            debounced: debounced, invalidatesComparisonBaseline: false, preservingAutoResult: false,
            transform)
    }

    /// Apply a completed content-aware Auto value without interpreting its generated layer
    /// replacement as a manual edit. This is the only production call site that may preserve
    /// Auto ownership; every inspector mutation takes the normal ownership-transition path.
    func updateDocument(preservingAutoResult: Bool, _ transform: (inout EditDocument) -> Void) {
        updateDocument(
            debounced: false, invalidatesComparisonBaseline: false,
            preservingAutoResult: preservingAutoResult, transform
        )
    }

    func updateDocument(
        debounced: Bool,
        invalidatesComparisonBaseline: Bool,
        preservingAutoResult: Bool = false,
        _ transform: (inout EditDocument) -> Void
    ) {
        if !preservingAutoResult, isAutoAdjustmentInProgress {
            // Manual edits supersede Auto immediately. The revision check below is still needed
            // because a renderer may finish one non-cancellable operation after cancellation.
            cancelAutoAdjustment()
        }
        var updated = document
        transform(&updated)
        if !preservingAutoResult {
            updated = EditDocument.markingManualEdits(from: document, to: updated)
        }
        guard updated != document else { return }

        let comparisonChanged = ComparisonFramePolicy.changesBaseline(
            from: document, to: updated, explicitlyInvalidated: invalidatesComparisonBaseline
        )
        let rotationChanged = updated.rotation != document.rotation
        previewPresentation.advanceDisplayRevision()
        cancelHistogram(clear: false, pump: false)
        editorDocument.recordChange(from: document, to: updated)
        document = updated
        if rotationChanged {
            sourceSize = document.rotation.orientedExtent(imageSource?.nativeExtent ?? sourceSize)
        }
        if !document.hasVisibleLookEdits { isShowingOriginal = false }
        refreshLUTResolutionStatus()
        saveActiveDocument()
        documentRevision &+= 1
        // Look edits and RAW Temperature/Tint leave the baseline unchanged, so an in-flight
        // baseline remains useful. Other RAW develop edits change the explicit before-image and
        // must invalidate that work; it will be queued again after the new visible result publishes.
        if comparisonChanged {
            comparisonBaselineDocument = updated.comparisonBaseline
            previewPresentation.advanceComparisonRevision()
            comparisonPreviewScheduledRevision = nil
            cancelComparisonPreview(pump: false)
            originalPreviewSurface.clear()
        }
        // OR'd in rather than assigned: a call earlier in a coalesced burst may have changed a
        // comparison-frame stage even though this call did not, and only the last call's task
        // survives to fire (see `pendingDevelopChange`'s doc comment).
        pendingDevelopChange = pendingDevelopChange || comparisonChanged

        guard debounced else {
            previewDebounceTask?.cancel()
            previewDebounceTask = nil
            schedulePreview()
            if let activeAssetID {
                scheduleEditedThumbnailAfterSettle(for: activeAssetID, priority: .activeEditor)
            }
            return
        }

        if isPreviewInteractionActive {
            scheduleInteractivePreview()
        } else {
            scheduleSettledPreviewAfterDebounce()
        }
        if let activeAssetID {
            scheduleEditedThumbnailAfterSettle(for: activeAssetID, priority: .activeEditor)
        }
    }

    /// Resolve a document's LUT reference: prefer the latest library scan, then the in-memory
    /// registry. The library must win for file-backed IDs: the registry retains saved derived LUTs
    /// so they work outside the library folder, but must not mask a replacement found by a scan.
    private func resolvedLUT(_ id: LUTID?) -> CubeLUT? {
        guard let id else { return nil }
        if let scanned = library.allLUTs.first(matching: id) { return scanned }
        return derivedRegistry.lut(for: id)
    }

    /// Report one missing-reference transition at a time. Waiting for scan completion avoids a false
    /// warning while the library is still assembling, while the document retains the unresolved ID.
    private var lastReportedMissingLUT: LUTID?

    private func refreshLUTResolutionStatus() {
        guard let id = document.lut.lutID else {
            lastReportedMissingLUT = nil
            lutResolutionStatus = nil
            return
        }
        guard !library.isScanning else { return }
        guard resolvedLUT(id) == nil else {
            lastReportedMissingLUT = nil
            lutResolutionStatus = nil
            return
        }
        guard lastReportedMissingLUT != id else { return }

        let name = id.isDerived ? "derived look" : URL(fileURLWithPath: id.raw).lastPathComponent
        let message = "Look “\(name)” is unavailable; the stored reference was kept."
        lastReportedMissingLUT = id
        lutResolutionStatus = message
        statusMessage = message
    }

    func selectPreviousLook() {
        applyLookNavigation(.previous)
    }

    func selectNextLook() {
        applyLookNavigation(.next)
    }

    /// Audition the adjacent Look, treating the inspector's explicit None row as the slot before
    /// the first library Look so Up from the first Look can clear the grade.
    private func applyLookNavigation(_ direction: LookNavigation.Direction) {
        let looks = library.allLUTs
        let currentIndex = selectedLook.flatMap { current in looks.firstIndex(of: current) }
        let nextIndex = LookNavigation.adjacentIndex(
            currentIndex: currentIndex,
            count: looks.count,
            direction: direction
        )
        if let nextIndex {
            selectLook(looks[nextIndex])
        } else if selectedLookID != nil {
            selectLook(nil)
        }
    }

    func selectPreviousLUT() { selectPreviousLook() }

    func selectNextLUT() { selectNextLook() }

    /// Reset only the Look stage. Other inspector panels remain untouched, and the operation is one
    /// reversible history entry for the active photo.
    func resetLook() {
        endUndoGrouping()
        updateDocument { $0.lut = .none }
    }

    // MARK: - LUT application

    private func applyLUT() {
        schedulePreview()
    }

    /// Retry the currently active preview without touching the durable document. This is also the
    /// recovery action exposed by the masking workspace when a source or mask render fails.
    func retryPreview() {
        guard imageSource != nil, sourceImage != nil else { return }
        previewState = .loading
        statusMessage = "Retrying preview…"
        schedulePreview()
    }

    /// Set the LUT strength (0...1) and re-render the preview. Safe to call on
    /// every slider tick: the re-render is debounced and the previous one is
    /// cancelled, so a full-travel drag costs a handful of renders, not one per
    /// pixel of travel.
    func setLookIntensity(_ value: Double) {
        let clamped = max(0, min(1, value))
        guard clamped != document.lut.intensity else { return }
        let oldDocument = document
        previewPresentation.advanceDisplayRevision()
        cancelHistogram(clear: false, pump: false)
        document.lut.intensity = clamped
        if !document.hasVisibleLookEdits {
            isShowingOriginal = false
        }
        editorDocument.recordChange(from: oldDocument, to: document)
        saveActiveDocument()
        documentRevision &+= 1
        if isPreviewInteractionActive {
            scheduleInteractivePreview()
        } else {
            scheduleSettledPreviewAfterDebounce()
        }
        if let activeAssetID {
            scheduleEditedThumbnailAfterSettle(for: activeAssetID, priority: .activeEditor)
        }
    }

    func setLUTIntensity(_ value: Double) { setLookIntensity(value) }

    // MARK: - Preview

    /// Backing pixels of the visible canvas. PreviewView updates this from its live geometry;
    /// the fallback is only used before the first layout pass.
    private var previewBackingSize = CGSize(width: 1600, height: 1200)
    private static let intensityDebounceMs = 60

    /// Build the same fit-state plan that a newly selected source receives after navigation resets
    /// the canvas. Keeping the ROI and presentation extent with the warm request is important:
    /// RenderEngine's preview cache includes the ROI, so a prefetch that only matches the pyramid
    /// level still forces the selected photo through the graph a second time.
    private func adjacentPreviewPlan(
        for document: EditDocument,
        nativeExtent: CGSize
    ) -> ResolutionPlan {
        var planner = ResolutionPlanner()
        return planner.plan(
            nativeExtent: document.rotation.orientedExtent(nativeExtent),
            crop: document.crop,
            viewportSize: previewBackingSize,
            // `openImage` resets presentation navigation for the next source before it plans
            // that source's preview. Match that fit-state input instead of borrowing the current
            // photo's zoom/pan.
            navigation: CanvasNavigation()
        )
    }

    /// Plan source detail for one logical rendering surface.
    ///
    /// This stays an internal value seam so tests can exercise the same surface routing without
    /// depending on asynchronous image preparation or a real drawable size. Production render
    /// requests use the returned plan's source size, ROI, and presentation extent together.
    func resolutionPlan(
        for document: EditDocument,
        nativeExtent: CGSize,
        viewportSize: CGSize,
        surface: ResolutionPlannerSurface
    ) -> ResolutionPlan {
        return previewPresentation.plan(
            for: document, nativeExtent: nativeExtent, viewportSize: viewportSize,
            surface: surface, navigation: canvasState.navigation
        )
    }

    private func resetResolutionPlanners() {
        previewPresentation.resetPlanners()
    }

    /// What the main preview panel should currently show, as a render request.
    ///
    /// While Space is held that is the **comparison baseline** — the same document with the look
    /// removed and develop kept (§8.5). Both sides therefore share a `rawDevelop`, so the swap reuses
    /// the engine's developed source instead of re-developing the RAW.
    ///
    /// One accessor rather than the same ternary at each call site: the histogram is supposed to
    /// describe the pixels on screen, and it stopped doing so precisely because it derived its image
    /// separately. Reading the request from one place is what makes that structural.
    private var displayRequest: (document: EditDocument, lut: CubeLUT?) {
        var requested = isShowingOriginal ? comparisonBaselineDocument : document

        // Crop is a composition stage. While the tool is open the overlay is expressed in the
        // full, oriented source coordinate space, so the pixels underneath it must be the same
        // adjusted stage before crop. This preserves the developed-source cache (including RAW
        // reuse) while making the saved rectangle line up with recognizable content. Vignette and
        // grain consequently describe this temporary full-source frame; the committed request
        // below restores their existing post-crop semantics.
        if canvasState.isCropToolActive {
            requested.crop = .neutral
        }

        return isShowingOriginal ? (requested, nil) : (requested, selectedLook)
    }

    /// Render the document for display.
    ///
    /// **This is the Step 5 cutover.** The preview no longer grades a baked `CIImage` on the main
    /// actor and rasterizes it through the old `ImageProcessor`; it hands the whole document to
    /// `PreviewCoordinator`, which selects the interactive or settled quality and asks
    /// `RenderEngine` to evaluate the graph inside its actor.
    private func schedulePreview() {
        cancelIdlePreviewBuild()
        submitSettledPreview(preemptsPredecessor: true)
    }

    /// The stored-edit corrective render for a speculative open (see `adoptStoredEdits`). Unlike
    /// every other settled submission, this queues behind the speculative request instead of
    /// cancelling it, so both renders reach the engine in order.
    private func scheduleCorrectivePreview() {
        cancelIdlePreviewBuild()
        submitSettledPreview(preemptsPredecessor: false)
    }

    /// Construct the request used by both the visible settled path and the idle cache builder.
    /// Idle work uses a fit plan with the cache's canonical long edge and no ROI, so its raster is
    /// always a complete photo rather than a viewport fragment.
    private func makeSettledPreviewRequest(
        source: ImageSource, assetID: PhotoAssetID?, document: EditDocument, lut: CubeLUT?,
        plan: ResolutionPlan, canonical: Bool = false, cropInteractionActive: Bool = false,
        requestRevision: UInt64 = 0
    ) -> RenderRequest {
        RenderRequest(
            source: source, assetID: assetID, document: document, lut: lut,
            targetSize: plan.sourceSize,
            sourceROI: canonical || cropInteractionActive
                ? nil
                : plan.previewSourceROI(
                    nativeExtent: document.rotation.orientedExtent(source.nativeExtent)
                ),
            presentationImageExtent: plan.presentationImageExtent,
            quality: .preview,
            output: .raster, space: .current, requestRevision: requestRevision
        )
    }

    private func canonicalPreviewPlan(
        for document: EditDocument, nativeExtent: CGSize
    ) -> ResolutionPlan {
        var planner = ResolutionPlanner()
        return planner.plan(
            nativeExtent: document.rotation.orientedExtent(nativeExtent),
            crop: document.crop,
            viewportSize: CGSize(
                width: CGFloat(PreviewDiskCache.canonicalLongEdge),
                height: CGFloat(PreviewDiskCache.canonicalLongEdge)
            ),
            navigation: CanvasNavigation()
        )
    }

    private func submitSettledPreview(preemptsPredecessor: Bool) {
        cancelIdlePreviewBuild()
        guard !isShuttingDown, let imageSource else {
            previewSurface.clear()
            return
        }

        let supersededLookup = pendingPreviewCacheLookup
        previewPresentation.advanceDisplayRevision()
        cancelHistogram(clear: false, pump: false)

        let (requested, look) = displayRequest
        let plan = resolutionPlan(
            for: requested,
            nativeExtent: imageSource.nativeExtent,
            viewportSize: previewBackingSize,
            surface: .mainPreview
        )
        previewScheduledSourceRevision = sourceRevision
        let request = makeSettledPreviewRequest(
            source: imageSource, assetID: activeAssetID, document: requested, lut: look,
            plan: plan, cropInteractionActive: canvasState.isCropToolActive,
            requestRevision: displayRevision
        )
        let cacheKey = previewPresentation.cacheKey(for: request)
        let assetID = activeAssetID
        let sourceRevision = self.sourceRevision
        let displayRevision = self.displayRevision
        if !preemptsPredecessor,
            let supersededLookup,
            supersededLookup.sourceRevision == sourceRevision,
            supersededLookup.assetID == assetID
        {
            // Stored-edit adoption intentionally preserves the speculative-first-frame contract.
            // If the miss lookup has not returned before the corrective request arrives, admit the
            // same speculative request now, then queue the corrective lookup behind it.
            previewPresentation.cancelCacheLookup()
            previewCoordinator.submit(
                supersededLookup.request, phase: .settled,
                assetID: supersededLookup.assetID,
                sourceRevision: supersededLookup.sourceRevision,
                displayRevision: supersededLookup.displayRevision
            )
        }
        // A cached entry is always a complete canonical photo, because the disk key deliberately
        // omits viewport state and `didPresentVisibleFrame` only writes a frame whose `sourceROI`
        // is nil. A zoomed or panned request asks for an ROI, so adopting that canonical raster
        // for it would publish the whole photo through ROI geometry — wrong scale, wrong origin —
        // and the retained frame would then refuse the correct render that follows. Reads have to
        // refuse the asymmetric case for exactly the reason writes already do.
        if request.sourceROI != nil {
            previewPresentation.cancelCacheLookup()
            pendingPreviewCacheLookup = nil
            if preemptsPredecessor {
                previewCoordinator.submit(
                    request, phase: .settled, assetID: assetID,
                    sourceRevision: sourceRevision, displayRevision: displayRevision
                )
            } else {
                previewCoordinator.submitCorrective(
                    request, assetID: assetID,
                    sourceRevision: sourceRevision, displayRevision: displayRevision
                )
            }
            return
        }
        previewPresentation.lookupCache(for: cacheKey) { [weak self] cached in
            guard let self, !self.isShuttingDown,
                self.sourceRevision == sourceRevision,
                self.displayRevision == displayRevision,
                self.activeAssetID == assetID,
                self.imageSource == request.source,
                self.displayRequest.document == request.document
            else { return }

            self.pendingPreviewCacheLookup = nil
            if let cached {
                // A hit has no coordinator publication, so explicitly retire any speculative
                // predecessor before using the same settled presentation gate as a render.
                self.previewCoordinator.cancel()
                self.presentSettledRaster(
                    CIImage(cgImage: cached), request: request, assetID: assetID,
                    sourceRevision: sourceRevision, displayRevision: displayRevision
                )
            } else if preemptsPredecessor {
                self.previewCoordinator.submit(
                    request, phase: .settled, assetID: assetID,
                    sourceRevision: sourceRevision, displayRevision: displayRevision
                )
            } else {
                self.previewCoordinator.submitCorrective(
                    request, assetID: assetID,
                    sourceRevision: sourceRevision, displayRevision: displayRevision
                )
            }
        }
        pendingPreviewCacheLookup = (
            request: request, assetID: assetID, sourceRevision: sourceRevision,
            displayRevision: displayRevision
        )
    }

    private func previewDiskCacheKey(for request: RenderRequest) -> PreviewDiskCache.Key {
        previewPresentation.cacheKey(for: request)
    }

    /// A viewport-sized interactive render. `PreviewCoordinator` drops superseded values and
    /// promotes the last value to a normal `.preview` render after the quiet period.
    private func scheduleInteractivePreview() {
        cancelIdlePreviewBuild()
        guard let imageSource else { return }
        previewPresentation.advanceDisplayRevision()
        cancelHistogram(clear: false, pump: false)
        let (requested, lut) = displayRequest
        let plan = resolutionPlan(
            for: requested,
            nativeExtent: imageSource.nativeExtent,
            viewportSize: previewBackingSize,
            surface: .mainPreview
        )
        previewCoordinator.submit(
            RenderRequest(
                source: imageSource, assetID: activeAssetID, document: requested, lut: lut,
                targetSize: plan.sourceSize,
                sourceROI: canvasState.isCropToolActive
                    ? nil
                    : plan.previewSourceROI(
                        nativeExtent: requested.rotation.orientedExtent(imageSource.nativeExtent)
                    ),
                presentationImageExtent: plan.presentationImageExtent,
                quality: .interactive,
                output: .raster, space: .current, requestRevision: displayRevision
            ), phase: .interactive, assetID: activeAssetID, sourceRevision: sourceRevision,
            displayRevision: displayRevision)
    }

    /// Called by the persistent preview surface after layout. Keeping this as value state avoids
    /// publishing a new image merely because the window changed size.
    func updatePreviewBackingSize(_ size: CGSize) {
        let width = size.width.rounded(.down)
        let height = size.height.rounded(.down)
        guard width >= 1, height >= 1,
            width.isFinite, height.isFinite,
            abs(width - previewBackingSize.width) > 1 || abs(height - previewBackingSize.height) > 1
        else { return }
        previewBackingSize = CGSize(width: width, height: height)
        guard imageSource != nil else { return }
        if isPreviewInteractionActive {
            scheduleInteractivePreview()
        } else {
            schedulePreview()
        }
    }

    private func scheduleSettledPreviewAfterDebounce() {
        cancelIdlePreviewBuild()
        previewDebounceTask?.cancel()
        previewDebounceGeneration &+= 1
        let generation = previewDebounceGeneration
        let revision = sourceRevision
        previewDebounceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(Self.intensityDebounceMs))
            guard !Task.isCancelled, let self,
                self.previewDebounceGeneration == generation,
                self.sourceRevision == revision
            else { return }
            // The handle represents pending work, not the completed task. Clear it before
            // scheduling the trailing thumbnail so scheduleEditedThumbnailAfterSettle can admit
            // exactly one render for the settled document.
            self.previewDebounceTask = nil
            self.schedulePreview()
            if let assetID = self.pendingEditedThumbnailAssetID {
                self.scheduleEditedThumbnailAfterSettle(for: assetID, priority: .activeEditor)
            }
        }
    }

    func beginPreviewInteraction() {
        cancelIdlePreviewBuild()
        beginUndoGrouping()
        cancelEditedThumbnailDebounce(for: activeAssetID)
        if let activeAssetID {
            workScheduler.cancel(
                id: ImageWorkScheduler.JobID(editedThumbnailJobPrefix + activeAssetID.raw),
                pump: false
            )
        }
        isPreviewInteractionActive = true
        previewCoordinator.beginInteraction()
    }

    func endPreviewInteraction() {
        isPreviewInteractionActive = false
        previewDebounceTask?.cancel()
        previewDebounceTask = nil
        previewCoordinator.endInteraction()
        endUndoGrouping()
        if let assetID = pendingEditedThumbnailAssetID {
            scheduleEditedThumbnailAfterSettle(for: assetID, priority: .activeEditor)
        }
    }

    // MARK: - Crop

    /// Enter the crop tool. The first draft is the committed crop, or the full image when this is a
    /// new crop. Crop interaction uses a fit canvas so screen coordinates map directly to the
    /// oriented source image and are not confused with presentation zoom/pan.
    func beginCrop() {
        guard sourceImage != nil else {
            statusMessage = "Open an image first"
            return
        }
        guard !canvasState.isCropToolActive else { return }
        endUndoGrouping()
        isShowingOriginal = false
        canvasState.beginCrop(using: document.crop)
        statusMessage = "Adjust crop, then Apply"
        // The committed preview may already be cropped. Ask for the same adjusted stage without
        // the composition crop so the full-source overlay has actual pixels underneath it.
        schedulePreview()
    }

    func toggleCropTool() {
        if isCropToolActive { cancelCrop() } else { beginCrop() }
    }

    /// Update only the transient framing rectangle. The model clamps it to image bounds and rejects
    /// invalid/degenerate values, so every pointer update remains safe to display.
    func updateCropDraft(_ normalizedRect: CGRect) {
        canvasState.updateCropDraft(normalizedRect)
    }

    /// Select a crop ratio in the transient tool state. The current crop center and approximate
    /// area are preserved, while the resulting frame is clamped to the source image bounds.
    func selectCropAspectRatio(
        _ aspectRatio: CropAspectRatio,
        orientation: CropAspectRatioOrientation = .automatic
    ) {
        guard sourceSize != .zero else { return }
        canvasState.selectCropAspectRatio(
            aspectRatio, orientation: orientation, imageSize: sourceSize
        )
    }

    /// Commit the current draft as one ordinary document mutation, giving it persistence, undo,
    /// copy/paste, cache invalidation, and preview/export parity automatically.
    func commitCrop() {
        guard canvasState.isCropToolActive else { return }
        let committed = canvasState.cropDraft ?? CropAdjustments.unitRect
        let aspectRatio = canvasState.cropAspectRatio
        let orientation = canvasState.cropOrientation
        canvasState.finishCrop()
        let previousDocument = document
        updateDocument {
            $0.crop = CropAdjustments(
                normalizedRect: committed, aspectRatio: aspectRatio, orientation: orientation
            )
        }
        canvasState.fit()
        // Applying an unchanged draft is still a composition transition: updateDocument quite
        // correctly records no history entry, but the temporary uncropped preview must be replaced
        // by the committed framing.
        if document == previousDocument {
            schedulePreview()
        }
        statusMessage = "Crop applied"
    }

    /// Abandon the draft and restore the committed framing without adding an undo entry.
    func cancelCrop() {
        guard canvasState.isCropToolActive else { return }
        canvasState.finishCrop()
        canvasState.fit()
        // Restore the committed framing without touching history or persistence.
        schedulePreview()
        statusMessage = hasCropAdjustments ? "Crop unchanged" : "Crop cancelled"
    }

    /// While editing, Reset returns the draft to the full image. Outside the tool it clears the
    /// committed crop through the normal history/persistence path.
    func resetCrop() {
        if canvasState.isCropToolActive {
            canvasState.resetCropDraft()
            statusMessage = "Crop reset"
        } else {
            endUndoGrouping()
            updateDocument { $0.crop = .neutral }
            canvasState.fit()
        }
    }

    // MARK: - Rotation

    /// Rotate the active image one quarter-turn clockwise. The edit is value state, so it is
    /// persisted with the photo and participates in the ordinary document history.
    func rotateClockwise() {
        rotateImage(clockwise: true)
    }

    /// Rotate the active image one quarter-turn counterclockwise.
    func rotateCounterClockwise() {
        rotateImage(clockwise: false)
    }

    /// Compatibility spelling for callers that expose rotation as a selected-image action.
    func rotateSelectedImage(clockwise: Bool) {
        rotateImage(clockwise: clockwise)
    }

    /// Clear only the rotation while preserving crop, tone, colour, and other spatial edits.
    func resetRotation() {
        guard sourceImage != nil else {
            statusMessage = "Open an image first"
            return
        }
        endUndoGrouping()
        updateDocument { document in
            let turnsToUndo = document.rotation.rawValue / 90
            document.crop = document.crop.rotated(byClockwiseQuarterTurns: -turnsToUndo)
            document.rotation = .zero
        }
        canvasState.fit()
        statusMessage = "Rotation reset"
    }

    private func rotateImage(clockwise: Bool) {
        guard sourceImage != nil else {
            statusMessage = "Open an image first"
            return
        }
        // A draft crop is expressed in the current image coordinates. Finish that transient tool
        // before changing the coordinate system so an unapplied rectangle cannot be committed
        // against the wrong orientation later.
        if canvasState.isCropToolActive { cancelCrop() }
        endUndoGrouping()
        updateDocument { document in
            document.rotation = document.rotation.addingClockwiseQuarterTurns(clockwise ? 1 : -1)
            document.crop = document.crop.rotated(byClockwiseQuarterTurns: clockwise ? 1 : -1)
        }
        canvasState.fit()
        statusMessage = "Rotated \(clockwise ? "clockwise" : "counterclockwise")"
    }

    // MARK: - Canvas navigation

    func fitCanvas() {
        canvasState.fit()
        schedulePreview()
    }

    func fillCanvas() {
        canvasState.fill()
        schedulePreview()
    }

    func resetCanvas() {
        canvasState.reset()
        schedulePreview()
    }

    func toggleCanvasZoom() {
        canvasState.toggleFitAndRememberedZoom()
        schedulePreview()
    }

    func setCanvasZoom(_ value: CGFloat) {
        let oldValue = canvasState.navigation.zoom
        canvasState.setZoom(value)
        guard canvasState.navigation.zoom != oldValue else { return }
        previewPresentation.advanceDisplayRevision()
        cancelHistogram(clear: false, pump: false)
        if isPreviewInteractionActive {
            scheduleInteractivePreview()
        } else {
            scheduleSettledPreviewAfterDebounce()
        }
    }

    func zoomCanvas(by factor: CGFloat) {
        guard factor.isFinite, factor > 0 else { return }
        setCanvasZoom(canvasState.navigation.zoom * factor)
    }

    /// Pinch-zoom is presentation-only, unlike a slider drag, so this deliberately does not call
    /// `beginPreviewInteraction`/`endPreviewInteraction`: those also open an undo grouping and
    /// queue a document save, which would flash a "saving" status and grow the undo stack for a
    /// gesture that never touches `document`.
    func beginCanvasInteraction() {
        isPreviewInteractionActive = true
        previewCoordinator.beginInteraction()
    }

    func endCanvasInteraction() {
        isPreviewInteractionActive = false
        previewCoordinator.endInteraction()
    }

    /// Pan is a presentation-only operation. The caller supplies a viewport-space pointer delta,
    /// so the image follows that delta on both axes. It updates the Metal transform immediately
    /// and does not wait for a new render; zoom is the operation that asks the coordinator for more
    /// detail.
    func panCanvas(by delta: CGSize, viewportSize: CGSize) {
        guard let imageSource else { return }
        let oriented = document.rotation.orientedExtent(imageSource.nativeExtent)
        let crop = document.crop.normalizedRect ?? CropAdjustments.unitRect
        canvasState.pan(
            by: delta,
            imageExtent: CGRect(
                origin: .zero,
                size: CGSize(
                    width: oriented.width * crop.width, height: oriented.height * crop.height)
            ),
            viewportSize: viewportSize
        )
    }

    /// Read-only seam for controls implemented in extensions. Keeping the stored interaction flag
    /// private preserves ownership of the lifecycle while allowing curve mutations to choose the
    /// same immediate-vs-interactive render policy as the built-in sliders.
    var isToneCurvePreviewInteractionActive: Bool { isPreviewInteractionActive }

    // MARK: - Undo and reset

    /// Start one history entry for a continuous slider gesture.
    func beginUndoGrouping() {
        editorDocument.beginGrouping(document: document)
    }

    /// Finish a continuous gesture. A gesture that did not change the document is not recorded.
    func endUndoGrouping() {
        let wasGrouping = editorDocument.endGrouping(document: document)
        if wasGrouping { saveActiveDocument(force: true) }
    }

    var canUndo: Bool { editorDocument.canUndo }
    var canRedo: Bool { editorDocument.canRedo }
    var undoDepth: Int { editorDocument.undoDepth }

    func undo() {
        cancelAutoAdjustment()
        endUndoGrouping()
        guard let restored = editorDocument.undo(current: document) else { return }
        applyHistoryDocument(restored)
    }

    func redo() {
        cancelAutoAdjustment()
        endUndoGrouping()
        guard let restored = editorDocument.redo(current: document) else { return }
        applyHistoryDocument(restored)
    }

    /// Return every edit on the current photo to its neutral state as one reversible operation.
    func resetPhoto() {
        cancelAutoAdjustment()
        endUndoGrouping()
        let previousDocument = document
        updateDocument { $0 = EditDocument() }
        guard document != previousDocument else { return }
        // Reset Photo is an explicit comparison-baseline invalidation even when the previous
        // document differed only by RAW Temperature, which is intentionally ignored by the normal
        // develop-frame comparison check.
        comparisonBaselineDocument = document.comparisonBaseline
        previewPresentation.advanceComparisonRevision()
        comparisonPreviewScheduledRevision = nil
        comparisonPreviewRetryTask?.cancel()
        comparisonPreviewRetryTask = nil
        cancelComparisonPreview(pump: false)
        originalPreviewSurface.clear()
        pendingDevelopChange = true
    }

    /// Reset the currently visible inspector stage without crossing into another stage. The
    /// toolbar uses this alongside each panel's local reset links so the scope is explicit before
    /// the action is taken; every branch still records through the stage's existing undo path.
    func resetInspectorSection() {
        if inspectorState.isMaskingWorkspacePresented {
            resetSelectedMask()
            return
        }
        switch inspectorTab {
        case .info:
            statusMessage = "Info has no adjustments to reset"
        case .light:
            resetAllLight()
        case .develop:
            resetAllDevelop()
        case .adjust:
            resetAllAdjustments()
        case .effects:
            resetAllEffects()
        case .look:
            resetLook()
        case .masking:
            resetSelectedMask()
        }
    }

    private func applyHistoryDocument(_ restored: EditDocument) {
        let comparisonChanged = ComparisonFramePolicy.changesBaseline(
            from: document, to: restored
        )
        previewPresentation.advanceDisplayRevision()
        cancelHistogram(clear: false, pump: false)
        document = restored
        sourceSize = restored.rotation.orientedExtent(imageSource?.nativeExtent ?? sourceSize)
        if !document.hasVisibleLookEdits {
            // Space is a transient single-view state. Undoing/redoing to identity must not leave
            // it armed when the before/after surface no longer exists.
            isShowingOriginal = false
        }
        if comparisonChanged {
            comparisonBaselineDocument = restored.comparisonBaseline
            comparisonPreviewScheduledRevision = nil
        }
        refreshLUTResolutionStatus()
        saveActiveDocument(force: true)
        documentRevision &+= 1
        if let activeAssetID {
            scheduleEditedThumbnailAfterSettle(for: activeAssetID, priority: .activeEditor)
        }
        if comparisonChanged {
            previewPresentation.advanceComparisonRevision()
            comparisonPreviewScheduledRevision = nil
            cancelComparisonPreview(pump: false)
            originalPreviewSurface.clear()
        }
        pendingDevelopChange = comparisonChanged
        restoreMaskSelection()
        schedulePreview()
    }

    private func publishPreview(_ publication: PreviewCoordinator.Publication) {
        guard !isShuttingDown,
            publication.assetID == activeAssetID,
            publication.sourceRevision == sourceRevision,
            publication.displayRevision == displayRevision,
            publication.request.source == imageSource
        else { return }
        let request = publication.request
        let detailIdentity = PreviewFrameIdentity(
            sourceToken: request.source.traceToken,
            documentHash: request.document.editHash,
            space: request.space
        )
        let detailFactor = request.renderScale.factor(for: request.source.nativeExtent)
        let presentedImage = publication.gpuImage ?? publication.image.map(CIImage.init)
        if publication.phase == .settled, let presentedImage {
            presentSettledRaster(
                presentedImage, request: request, assetID: publication.assetID,
                sourceRevision: publication.sourceRevision,
                displayRevision: publication.displayRevision,
                surfaceRevision: publication.revision
            )
        } else if let gpuImage = publication.gpuImage {
            previewSurface.present(
                gpuImage, space: request.space,
                revision: publication.revision,
                telemetry: previewCoordinator.telemetry,
                source: request.source,
                quality: request.quality,
                detailIdentity: detailIdentity,
                detailFactor: detailFactor,
                presentationImageExtent: request.presentationImageExtent,
                coversPresentationExtent: request.coversPresentationExtent,
                layoutImageExtent: request.presentationLayoutExtent,
                onPresented: nil)
        } else if let cgImage = publication.image {
            // Non-GPU conformers retain a raster compatibility seam, but it terminates at the
            // same persistent surface. Production RenderEngine publishes `gpuImage`, so this does
            // not allocate or publish an NSImage on the normal preview path.
            previewSurface.present(
                CIImage(cgImage: cgImage), space: request.space,
                revision: publication.revision,
                telemetry: previewCoordinator.telemetry,
                source: request.source,
                quality: request.quality,
                detailIdentity: detailIdentity,
                detailFactor: detailFactor,
                presentationImageExtent: request.presentationImageExtent,
                coversPresentationExtent: request.coversPresentationExtent,
                layoutImageExtent: request.presentationLayoutExtent,
                onPresented: nil)
        }
        guard publication.gpuImage != nil || publication.image != nil else {
            if publication.phase == .settled {
                previewState = .failed
                publishAutoAdjustmentState(
                    .unavailable("Auto is unavailable because the photo preview failed."))
                statusMessage = "Could not render \(sourceName)"
            }
            return
        }
        if publication.phase == .settled {
            lastPublishedVisibleRequest = request
            // A thumbnail switch can publish the new Adjusted candidate before its MTKView has a
            // drawable (for example while SwiftUI is replacing the selected filmstrip cell). Do
            // not make the new Original pane depend on that later confirmation; both requests are
            // already fenced to this source and display revision.
            if isSideBySideVisible {
                scheduleOriginalPreview(allowBeforePresentationConfirmation: true)
            }
        }

    }

    /// The one settled-raster presentation funnel. Rendered frames and disk-cache hits both use
    /// this path so drawable confirmation, histogram admission, Auto readiness, and thumbnail
    /// gating cannot diverge between a cold and warm open.
    @discardableResult
    private func presentSettledRaster(
        _ image: CIImage, request: RenderRequest, assetID: PhotoAssetID?,
        sourceRevision: UInt64, displayRevision: UInt64, surfaceRevision: UInt64? = nil
    ) -> Bool {
        let detailIdentity = PreviewFrameIdentity(
            sourceToken: request.source.traceToken,
            documentHash: request.document.editHash,
            space: request.space
        )
        let detailFactor = request.renderScale.factor(for: request.source.nativeExtent)
        let presented = previewSurface.present(
            image, space: request.space,
            revision: surfaceRevision ?? displayRevision,
            telemetry: previewCoordinator.telemetry,
            source: request.source,
            quality: request.quality,
            detailIdentity: detailIdentity,
            detailFactor: detailFactor,
            presentationImageExtent: request.presentationImageExtent,
            coversPresentationExtent: request.coversPresentationExtent,
            layoutImageExtent: request.presentationLayoutExtent,
            onPresented: { [weak self] in
                self?.didPresentVisibleFrame(
                    request, assetID: assetID, sourceRevision: sourceRevision,
                    displayRevision: displayRevision, presentedImage: image
                )
            }
        )
        if presented {
            lastPublishedVisibleRequest = request
        }
        return presented
    }

    /// Supporting work starts only after the persistent presentation surface confirms that the
    /// visible frame made it through its drawable lifecycle. This keeps a completed renderer result
    /// from being mistaken for pixels the user has actually received.
    private func didPresentVisibleFrame(
        _ request: RenderRequest, assetID: PhotoAssetID?, sourceRevision: UInt64,
        displayRevision: UInt64, presentedImage: CIImage?
    ) {
        guard assetID == activeAssetID,
            sourceRevision == self.sourceRevision,
            displayRevision == self.displayRevision,
            request.source == imageSource,
            request.document == displayRequest.document
        else { return }
        previewState = .ready
        if request.source.kind == .raw,
            statusMessage == "Loading \(sourceName)..."
        {
            statusMessage =
                "\(sourceName)  \(Int(request.source.nativeExtent.width))\u{00D7}\(Int(request.source.nativeExtent.height))"
        }
        if !isAutoAdjustmentInProgress { publishAutoAdjustmentState(.ready) }
        lastPresentedVisibleRequest = request
        lastPresentedVisibleImage = presentedImage
        let needsComparisonRefresh = pendingDevelopChange
        pendingDevelopChange = false
        if isSideBySideVisible || needsComparisonRefresh {
            scheduleOriginalPreview(allowHiddenPreparation: needsComparisonRefresh)
        } else {
            cancelComparisonPreview()
        }
        if storedEditsResolvedSourceRevision == sourceRevision {
            updateHistogram(for: request, presentedImage: presentedImage)
        }

        // The builder is admitted by a settled presentation, even when this particular frame is
        // an ROI and therefore cannot itself be written to the canonical disk cache.
        scheduleIdlePreviewBuild()

        // A zoomed request may contain only an ROI. Since the disk key intentionally omits viewport
        // state, only a complete settled frame is eligible; otherwise a pan could persist a partial
        // raster that a later fit-open would incorrectly treat as the whole photo.
        guard request.quality == .preview,
            request.sourceROI == nil,
            let presentedImage
        else { return }
        previewPresentation.writeCanonical(presentedImage, for: request)
    }

    /// Rasterize the comparison baseline for the side-by-side left panel. Only needs to re-run when
    /// the image or the develop settings change — not when the look does. A mode-entry request may
    /// start from the current preview candidate before its drawable confirmation arrives; normal
    /// supporting work remains gated on that confirmation below.
    private func scheduleOriginalPreview(
        allowHiddenPreparation: Bool = false,
        allowBeforePresentationConfirmation: Bool = false
    ) {
        let hasCurrentPreviewCandidate =
            allowBeforePresentationConfirmation
            && previewSurface.image != nil
            && lastPublishedVisibleRequest?.source == imageSource
            && lastPublishedVisibleRequest?.document == document
        guard lastPresentedVisibleRequest != nil || hasCurrentPreviewCandidate,
            isSideBySideVisible || allowHiddenPreparation,
            let imageSource
        else {
            comparisonPreviewScheduledRevision = nil
            cancelComparisonPreview()
            originalPreviewSurface.clear()
            return
        }
        guard comparisonPreviewScheduledRevision != comparisonRevision else { return }
        let baseline = comparisonBaselineDocument
        let plan = resolutionPlan(
            for: baseline,
            nativeExtent: imageSource.nativeExtent,
            viewportSize: previewBackingSize,
            surface: .comparisonBaseline
        )
        let sourceRevision = self.sourceRevision
        let comparisonRevision = self.comparisonRevision
        let assetID = self.activeAssetID
        let sourceReference = self.activeSourceReference
        comparisonPreviewScheduledRevision = comparisonRevision

        let accepted = workScheduler.enqueue(
            id: comparisonPreviewJobID, lane: .editor, priority: .comparison,
            onTerminal: { [weak self] outcome in
                guard outcome != .completed,
                    let self,
                    assetID == self.activeAssetID,
                    sourceReference == self.activeSourceReference,
                    sourceRevision == self.sourceRevision,
                    comparisonRevision == self.comparisonRevision,
                    self.comparisonPreviewScheduledRevision == comparisonRevision
                else { return }
                // A queued comparison can be evicted by a newer active-editor render. Leave the
                // revision retryable so the next settled publication can re-admit it; otherwise a
                // valid selected image could keep the Original pane blank forever.
                self.comparisonPreviewScheduledRevision = nil
            },
            operation: { [weak self, engine] in
                guard !Task.isCancelled, let self else { return }
                // Cancellation can arrive after this job has been admitted to the scheduler but
                // before the renderer call begins. Check the same source/revision fence before asking
                // the engine, otherwise an obsolete baseline still consumes a render and looks like a
                // cross-photo comparison request even though its eventual publication is discarded.
                guard assetID == self.activeAssetID,
                    sourceReference == self.activeSourceReference,
                    sourceRevision == self.sourceRevision,
                    comparisonRevision == self.comparisonRevision,
                    self.imageSource == imageSource
                else { return }
                let request = self.makeSettledPreviewRequest(
                    source: imageSource,
                    assetID: assetID,
                    document: baseline,
                    lut: nil,
                    plan: plan
                )
                let gpuImage = await engine.makeCIImage(request)
                if let gpuImage {
                    guard !Task.isCancelled,
                        assetID == self.activeAssetID,
                        sourceReference == self.activeSourceReference,
                        sourceRevision == self.sourceRevision,
                        comparisonRevision == self.comparisonRevision,
                        self.imageSource == imageSource
                    else { return }
                    let hadValidOriginal = self.originalPreviewSurface.image != nil
                    guard
                        self.originalPreviewSurface.present(
                            gpuImage,
                            space: request.space,
                            presentationImageExtent: request.presentationImageExtent,
                            coversPresentationExtent: request.coversPresentationExtent,
                            layoutImageExtent: request.presentationLayoutExtent
                        ) || hadValidOriginal
                    else {
                        self.comparisonPreviewDidFail(
                            sourceReference: sourceReference,
                            sourceRevision: sourceRevision, comparisonRevision: comparisonRevision
                        )
                        return
                    }
                    return
                }
                let cgImage = await engine.makeCGImage(request)
                guard !Task.isCancelled,
                    assetID == self.activeAssetID,
                    sourceReference == self.activeSourceReference,
                    sourceRevision == self.sourceRevision,
                    comparisonRevision == self.comparisonRevision,
                    self.imageSource == imageSource,
                    let cgImage
                else { return }
                let hadValidOriginal = self.originalPreviewSurface.image != nil
                guard
                    self.originalPreviewSurface.present(
                        CIImage(cgImage: cgImage),
                        space: request.space,
                        presentationImageExtent: request.presentationImageExtent,
                        coversPresentationExtent: request.coversPresentationExtent,
                        layoutImageExtent: request.presentationLayoutExtent
                    ) || hadValidOriginal
                else {
                    self.comparisonPreviewDidFail(
                        sourceReference: sourceReference,
                        sourceRevision: sourceRevision, comparisonRevision: comparisonRevision
                    )
                    return
                }
            }
        )
        if !accepted, comparisonPreviewScheduledRevision == comparisonRevision {
            comparisonPreviewScheduledRevision = nil
        }
    }

    private func comparisonPreviewDidFail(
        sourceReference: EditSourceReference?,
        sourceRevision: UInt64, comparisonRevision: UInt64
    ) {
        guard activeAssetID != nil,
            sourceReference == activeSourceReference,
            sourceRevision == self.sourceRevision,
            comparisonRevision == self.comparisonRevision,
            isSideBySideVisible,
            comparisonPreviewScheduledRevision == comparisonRevision
        else { return }
        comparisonPreviewScheduledRevision = nil
        originalPreviewSurface.clear()
        statusMessage = "Could not display the comparison preview. Retrying…"
        guard comparisonPreviewRetriedRevision != comparisonRevision else { return }
        comparisonPreviewRetriedRevision = comparisonRevision
        comparisonPreviewRetryTask?.cancel()
        comparisonPreviewRetryTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(25))
            guard !Task.isCancelled, let self,
                sourceReference == self.activeSourceReference,
                sourceRevision == self.sourceRevision,
                comparisonRevision == self.comparisonRevision,
                self.isSideBySideVisible,
                self.comparisonPreviewScheduledRevision != comparisonRevision
            else { return }
            self.comparisonPreviewRetryTask = nil
            self.scheduleOriginalPreview(allowBeforePresentationConfirmation: true)
        }
    }

    private func cancelComparisonPreview(pump: Bool = true) {
        workScheduler.cancel(id: comparisonPreviewJobID, pump: pump)
    }

    /// Toggle between original and LUT preview (for Space-hold comparison).
    @discardableResult
    func showOriginal(_ show: Bool) -> Bool {
        // The always-both model already exposes Original in the left pane. Space is deliberately
        // single-image-only so it cannot replace the adjusted surface underneath side-by-side.
        guard !isSideBySide, !show || isComparisonAvailable else {
            if isShowingOriginal {
                isShowingOriginal = false
                schedulePreview()
            }
            return false
        }
        guard show != isShowingOriginal else { return true }
        isShowingOriginal = show
        previewPresentation.advanceDisplayRevision()
        cancelHistogram(clear: false, pump: false)
        schedulePreview()
        return true
    }

    @discardableResult
    func toggleSideBySide() -> Bool {
        // An active retained side-by-side preference must remain dismissible after Reset Photo or
        // when navigation lands on an identity document. Enabling it from single view still uses
        // the meaningful-edit gate, preserving the existing affordance semantics for untouched
        // photos.
        guard isComparisonAvailable || isSideBySideVisible else { return false }
        isSideBySide.toggle()
        if isSideBySide {
            if isShowingOriginal {
                isShowingOriginal = false
                previewPresentation.advanceDisplayRevision()
                cancelHistogram(clear: false, pump: false)
                schedulePreview()
            }
            scheduleOriginalPreview(allowBeforePresentationConfirmation: true)
        } else {
            cancelComparisonPreview()
            comparisonPreviewScheduledRevision = nil
            originalPreviewSurface.clear()
        }
        return true
    }

    // MARK: - Info inspector (EXIF + histogram)

    func toggleInspector() {
        guard sourceImage != nil else {
            statusMessage = "Open an image first"
            return
        }
        isInspectorPresented.toggle()
    }

    /// Recompute the histogram for the currently displayed image. No-op unless the Info tab of an
    /// open inspector is on screen. Cancellable, so dragging the intensity slider stays smooth.
    ///
    /// The histogram consumes the completed image from the settled presentation. This keeps it
    /// aligned with the pixels the user received and avoids evaluating the preview graph again.
    /// The source/document overload remains available for standalone engine analysis, but it is
    /// intentionally not used for the visible Info inspector path.
    private func updateHistogram(
        for displayedRequest: RenderRequest? = nil,
        presentedImage: CIImage? = nil
    ) {
        // Both halves of the gate: an inspector parked on Develop shows no histogram, so tallying
        // one on every settled render of a slider drag is pure waste.
        guard isInspectorPresented, inspectorTab == .info else {
            cancelHistogram(clear: true)
            return
        }
        guard let imageSource else {
            cancelHistogram(clear: true)
            return
        }
        guard let lastPresentedVisibleRequest else { return }
        let request: RenderRequest
        if let displayedRequest {
            request = displayedRequest
        } else {
            // Opening Info between a document edit and its settled presentation must describe the
            // last frame the user actually received, not a newly assembled request for the edit
            // that is still rendering.
            request = lastPresentedVisibleRequest
        }
        guard request.source == imageSource else {
            cancelHistogram(clear: true)
            return
        }
        let image = presentedImage ?? lastPresentedVisibleImage
        guard let image else { return }

        let sourceRevision = self.sourceRevision
        let displayRevision = self.displayRevision
        let assetID = self.activeAssetID

        // Opening the Info tab can race the settled publication that is already on its way. Do not
        // tally the same displayed request twice just because both paths noticed it.
        if workScheduler.contains(histogramJobID),
            histogramTaskAssetID == assetID,
            histogramTaskRevision == displayRevision,
            histogramTaskRequest == request
        {
            return
        }
        cancelHistogram(clear: false)
        histogramTaskRevision = displayRevision
        histogramTaskRequest = request
        histogramTaskAssetID = assetID
        isHistogramLoading = true
        histogramErrorMessage = nil
        workScheduler.enqueue(id: histogramJobID, lane: .editor, priority: .histogram) {
            [weak self, engine] in
            guard !Task.isCancelled, let self, !self.isShuttingDown else { return }
            // The settled publication already contains the completed preview texture. Tally that
            // value after drawable confirmation so Info describes pixels the user received and does
            // not trigger a second evaluation of the render graph.
            let result = await engine.histogram(
                presentedImage: image, space: request.space, maxDimension: 512
            )
            guard !Task.isCancelled, !self.isShuttingDown,
                self.isInspectorPresented,
                self.inspectorTab == .info,
                assetID == self.activeAssetID,
                sourceRevision == self.sourceRevision,
                displayRevision == self.displayRevision,
                self.imageSource == request.source
            else { return }
            self.histogram = result
            self.isHistogramLoading = false
            if result == nil {
                let message = "Histogram unavailable for \(self.sourceName)."
                self.histogramErrorMessage = message
                self.statusMessage = message
            } else {
                self.histogramErrorMessage = nil
            }
        }
    }

    /// Cancel pending or in-flight histogram work. The revision check in the task remains necessary:
    /// a renderer may be finishing a non-cancellable Core Image operation after its task is canceled.
    private func cancelHistogram(clear: Bool, pump: Bool = true) {
        workScheduler.cancel(id: histogramJobID, pump: pump)
        histogramTaskRevision = nil
        histogramTaskRequest = nil
        histogramTaskAssetID = nil
        if isHistogramLoading { isHistogramLoading = false }
        if histogramErrorMessage != nil { histogramErrorMessage = nil }
        if clear { histogram = nil }
    }

    /// Keep the Picker selection valid as source publication and capability probing change which
    /// tabs exist. The base Info tab is always available for a loaded image.
    private func keepInspectorTabValid() {
        let tabs = availableInspectorTabs
        guard let fallback = tabs.first else {
            if inspectorTab != .info { inspectorTab = .info }
            return
        }
        if !tabs.contains(inspectorTab) {
            inspectorTab = fallback
        }
    }

    // MARK: - Export

    /// Export the open image at full resolution.
    ///
    /// **The Step 6 cutover.** What goes to disk is now the same `EditDocument` the screen is
    /// rendering, at `.full` instead of `.preview` — one argument apart, through one funnel. Before,
    /// this handed over a baked `CIImage` that carried the LUT and nothing else, so develop and
    /// adjustments reached the preview and silently did not reach the file.
    ///
    /// Note it exports `document`, not `displayRequest` — holding Space to compare should not change
    /// what ⌘S writes.
    func exportDialog() {
        guard let request = exportRequest else {
            statusMessage = "Open an image first"
            return
        }
        export.exportDialog(
            source: request.source,
            assetID: activeAssetID,
            document: request.document,
            lut: request.lut,
            suggestedBaseName: request.baseName
        )
    }

    /// What ⌘S would export, without running a panel.
    ///
    /// Internal rather than private because `NSSavePanel` cannot run headless, so this is the only
    /// way to assert the part of `exportDialog` that has content — *which* document goes to disk. The
    /// wrapper around it is the two lines the panel makes untestable, which is the same trade
    /// `docs/ENGINEERING_GUIDE.md` already records for every other panel in the app.
    var exportRequest:
        (source: ImageSource, document: EditDocument, lut: CubeLUT?, baseName: String)?
    {
        guard let imageSource else { return nil }
        // `sourceURL` is the managed copy for one-off opens and may carry Kromora's internal
        // de-duplication prefix. The user-facing name is retained separately in `sourceName`.
        let base =
            sourceName.isEmpty
            ? (sourceURL?.deletingPathExtension().lastPathComponent ?? "image")
            : URL(fileURLWithPath: sourceName).deletingPathExtension().lastPathComponent
        return (
            source: imageSource,
            document: document,
            lut: selectedLook,
            baseName: ExportCoordinator.exportBaseName(source: base, lut: selectedLook)
        )
    }

    /// Apply the current look to every imported image and export them all to a
    /// chosen folder.
    ///
    /// Cut over with the single export, and for the same reason: `performBatchExport` used to load
    /// and grade each file itself, so fixing only the single path would have left Export All writing
    /// the old, develop-less render.
    func batchExportDialog() {
        let request = batchExportRequest
        export.batchExportDialog(items: request.items, document: request.document, lut: request.lut)
    }

    /// Export exactly the library selection. The active photo is not implicitly added when the
    /// user has selected other cells; selection and edit focus are separate in the grid model.
    func exportSelectedDialog() {
        let request = selectedBatchExportRequest
        guard !request.items.isEmpty else {
            statusMessage = "Select at least one photo to export"
            return
        }
        export.batchExportDialog(items: request.items, document: request.document, lut: request.lut)
    }

    /// What Export All would write, without running a panel. Internal for the same reason
    /// `exportRequest` is.
    var batchExportRequest:
        (items: [ExportCoordinator.BatchItem], document: EditDocument, lut: CubeLUT?)
    {
        makeBatchExportRequest(from: collection.items)
    }

    /// The panel-free request used by Export Selected. Unlike the historical `batchExportRequest`
    /// compatibility seam, this list is never widened to the whole collection.
    var selectedBatchExportRequest:
        (items: [ExportCoordinator.BatchItem], document: EditDocument, lut: CubeLUT?)
    {
        makeBatchExportRequest(from: collection.selectedItems)
    }

    /// Alternate spelling for callers that use the product-facing command name.
    var selectedExportRequest:
        (items: [ExportCoordinator.BatchItem], document: EditDocument, lut: CubeLUT?)
    {
        selectedBatchExportRequest
    }

    private func makeBatchExportRequest(
        from sourceItems: [ImageCollection.Item]
    ) -> (items: [ExportCoordinator.BatchItem], document: EditDocument, lut: CubeLUT?) {
        // Snapshot only Sendable source/edit values — never carry NSImage thumbnails into export.
        // A missing session document is intentional: ExportCoordinator asks EditDocumentStore for
        // the durable record, so unopened selected photos still export their own saved edits.
        let items = sourceItems.map { item in
            let itemDocument: EditDocument?
            if item.id == activeAssetID {
                itemDocument = document
            } else {
                itemDocument = editorDocument.session(for: item.id)?.document
            }
            let itemLUT = itemDocument.flatMap { resolvedLUT($0.lut.lutID) }
            return ExportCoordinator.BatchItem(
                url: item.url,
                data: item.imageData,
                name: item.displayName,
                assetID: item.id,
                portableIdentity: persistencePortableIdentity(for: item),
                bookmarkData: item.asset.bookmarkData,
                document: itemDocument,
                lut: itemLUT
            )
        }
        return (items: items, document: document, lut: selectedLook)
    }

    // MARK: - Recipe extractor

    func presentRecipeExtractor() {
        derive.present()
    }

    func dismissRecipeExtractor() {
        derive.dismiss()
    }

    func deriveRecipe(rawURL: URL, jpgURL: URL) {
        derive.derive(rawURL: rawURL, jpgURL: jpgURL)
    }

    func saveDerivedLUT() {
        derive.saveDialog()
    }

    /// Present the support-matrix confirmation for the active photo's LUT-compatible edits.
    func presentSaveLook() {
        guard sourceImage != nil else {
            statusMessage = "Open an image first"
            return
        }
        let suggested: String
        if let sourceURL {
            suggested = sourceURL.deletingPathExtension().lastPathComponent + " Look"
        } else {
            suggested = "Look"
        }
        lookSave.present(document: document, lut: selectedLook, suggestedName: suggested)
    }

    func dismissSaveLook() {
        lookSave.dismiss()
    }

    func saveLook() {
        lookSave.saveDialog()
    }

    // MARK: - Look folder

    func chooseLookFolder() {
        let panel = NSOpenPanel()
        panel.title = "Select Look Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            library.setFolder(url)
        }
    }

    /// Import one or more external `.cube`/text-based `.look` files from ordinary Finder locations.
    /// The library owns parsing, security-scoped access, and persistence; this method only owns the
    /// AppKit panel and the user-facing entry point.
    func chooseLookFile() {
        let panel = NSOpenPanel()
        panel.title = "Import Look"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [
            UTType(filenameExtension: "cube"),
            UTType(filenameExtension: "look"),
        ].compactMap { $0 }

        if panel.runModal() == .OK {
            for url in panel.urls {
                library.importLUT(from: url)
            }
        }
    }

    /// Testable/non-panel seam for importing a file selected by another UI surface.
    func importLook(from url: URL) {
        library.importLUT(from: url)
    }

    /// Re-read configured and imported Look files. This is also the explicit user action for an
    /// external editor that replaced a file in place.
    func refreshLooks() {
        library.refresh()
    }

    func chooseLUTFolder() { chooseLookFolder() }

    private func saveActiveDocument(force: Bool = false) {
        guard let activeAssetID, let activeSourceReference else { return }
        editorDocument.commit(document: document, for: activeAssetID)

        queuePersistence(document, for: activeSourceReference, reportsStatus: true, force: force)
    }

    /// Serialize disk snapshots in edit order. This is shared with multi-photo paste because a
    /// destination that was never opened does not pass through `saveActiveDocument` before quit.
    private func queuePersistence(
        _ document: EditDocument,
        for reference: EditSourceReference,
        reportsStatus: Bool,
        force: Bool = false
    ) {
        persistence.enqueue(
            document,
            for: reference,
            reportsStatus: reportsStatus,
            force: force
        )
    }

    private func requestPersistenceFlush() {
        persistence.requestFlush()
    }

    /// Wait for queued snapshots before clean application termination.
    public func flushPendingWrites() async -> PersistenceFlushResult {
        await persistence.flush()
    }

    /// Explicitly abandon snapshots that could not be written. This is only used after the user
    /// has chosen Quit Without Saving; ordinary edits and failed flushes leave snapshots dirty.
    public func discardPendingWrites() async {
        await persistence.discard()
    }

    /// Cancel all work owned by this testable application model and wait until its collaborators
    /// have released their source/store accesses. This is deliberately explicit rather than a
    /// `deinit` hook: `deinit` is nonisolated in Swift 6 and cannot safely perform actor cleanup.
    /// Production launch behavior is unchanged; the app's normal termination path still flushes
    /// pending edits before quitting.
    func shutdown() async {
        guard !isShuttingDown else { return }
        isShuttingDown = true

        // Invalidate every generation before awaiting anything. A renderer or framework call may
        // only observe cancellation when it returns, but it can no longer publish into this model.
        sourceSession.cancel()
        documentRevision &+= 1
        previewPresentation.resetForSource()
        autoInvocationRevision &+= 1
        previewDebounceGeneration &+= 1
        comparisonPreviewRetryTask?.cancel()
        comparisonPreviewRetryTask = nil

        // Disconnect callbacks first so a child that finishes while shutdown is re-entrant cannot
        // schedule new work or publish into the model.
        previewCoordinator.onPublication = nil
        previewCoordinator.onFailure = nil
        library.onScanned = nil
        library.onImported = nil
        library.onImportError = nil
        export.onStatus = nil
        export.onError = nil
        derive.onStatus = nil
        derive.onError = nil
        derive.onDerived = nil
        derive.onSaved = nil
        lookSave.onStatus = nil
        lookSave.onError = nil
        lookSave.onSaved = nil
        persistence.onStatusChange = nil
        persistence.onFailure = nil
        photosImportCoordinator.onStatus = nil
        photosImportCoordinator.destination = nil
        libraryMediaWorkflow.onStatus = nil
        libraryMediaWorkflow.onError = nil
        libraryMediaWorkflow.onSourceFolder = nil
        libraryMediaWorkflow.onImageURL = nil
        libraryMediaWorkflow.onImageURLs = nil
        libraryMediaWorkflow.onImportRequest = nil
        applicationShell.onMediaChanged = nil
        applicationShell.onApplicationActivated = nil
        cancellables.removeAll()
        await applicationShell.shutdown()

        // Collection shutdown ends its discovery stream before awaiting the consumer. This also
        // prevents a late scan batch from admitting another thumbnail job.
        await collection.shutdown()

        let thumbnailDebounceTasks = editedThumbnailDebounceTasks.values.map(Optional.init)
        let idleBuild = idleBuildTask
        cancelIdlePreviewBuild(resetCursor: true)
        let tasks: [Task<Void, Never>?] =
            [
                autoAdjustmentTask, smartMaskCreationTask, prefetchDelayTask, previewDebounceTask, sourceFolderOpenTask,
                idleBuild, personSignalWarmingTask, lutCacheInvalidationTask,
                semanticCoordinatorInstallTask,
                droppedPromiseTask,
            ] + thumbnailDebounceTasks
        for task in tasks { task?.cancel() }
        autoAdjustmentTask = nil
        smartMaskCreationTask = nil
        prefetchDelayTask = nil
        previewDebounceTask = nil
        idleBuildTask = nil
        editedThumbnailDebounceTasks.removeAll()
        pendingEditedThumbnailAssetID = nil
        sourceFolderOpenTask = nil
        personSignalWarmingTask = nil
        lutCacheInvalidationTask = nil
        semanticCoordinatorInstallTask = nil
        droppedPromiseTask = nil
        await libraryMediaWorkflow.shutdown()
        await sourceSession.shutdown()

        await library.shutdown()
        await export.shutdown()
        await photosImportCoordinator.shutdown()
        await derive.shutdown()
        await lookSave.shutdown()
        await photoAnalysisCoordinator.shutdown()
        previewPresentation.shutdown()
        await previewCoordinator.shutdown()
        await lookPreviewCoordinator.shutdown()
        await workScheduler.cancelAllAndWait()
        for task in tasks {
            if let task { await task.value }
        }
        await persistence.discard()
    }
}

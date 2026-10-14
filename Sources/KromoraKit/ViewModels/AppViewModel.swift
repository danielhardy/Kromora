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
    var duplicates: Int = 0
    var skipped: Int
    var failed: Int = 0
    var failureReasons: [String] = []
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

    var succeeded: Bool { !deletedIDs.isEmpty && failures.isEmpty }
}

struct FrameStoreFlushOperations: Sendable {
    let flushThumbnails: @MainActor @Sendable () async throws -> Void
    let flushPreviews: @MainActor @Sendable () async throws -> Void

    @MainActor
    func flush() async {
        async let thumbnails: Void = flushBestEffort(flushThumbnails)
        async let previews: Void = flushBestEffort(flushPreviews)
        await thumbnails
        await previews
    }

    private func flushBestEffort(
        _ operation: @MainActor @Sendable () async throws -> Void
    ) async {
        do { try await operation() } catch { }
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
public final class AppViewModel: ObservableObject, LookPreviewProviding, PhotosImportDestination,
    AsyncPhotosImportDestination, PhotosImportBatchDestination, MaskingWorkflowDestination,
    RetouchWorkflowDestination, EditedThumbnailDestination
{

    var packageImportDoesNotNeedDigest: Bool { true }

    /// Inspector presentation state has its own observation boundary. The editor model still
    /// owns histogram scheduling and tab validity, but changing the inspector chrome does not
    /// need to publish through the model observed by the library and canvas shells.
    @MainActor
    final class InspectorState: ObservableObject {
        /// Inspector visibility drives the histogram gate synchronously after assignment.
        var onPresentationChange: (() -> Void)?

        @Published var isPresented = false {
            didSet { onPresentationChange?() }
        }
        @Published var tab: InspectorTab = .light

        /// Masking is an inspector tab, not a second presentation mode. Keep the previous tab so
        /// Done/Escape can return to the edit control the user came from.
        private var tabBeforeMasking: InspectorTab = .light

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
    @Published var isWhiteBalanceSampling = false
    @Published var whiteBalanceSamplerPoint: CGPoint?
    @Published var whiteBalanceLoupeImage: CGImage?

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
    /// True while a cold photo-to-photo selection is waiting for its stored edit document. The
    /// inspector holds its current slider presentation during this short interval; the published
    /// document itself continues to belong to the newly selected photo.
    var isInspectorSourceDocumentPending: Bool { presentation.isInspectorDocumentPending }
    /// Toolbar photo actions retain their last settled availability while another selected photo
    /// loads. Their action methods still validate the active source before doing any work.
    var toolbarPhotoActionsAvailable: Bool { presentation.toolbarActionsAvailable }
    var isToolbarPhotoTransitioning: Bool { presentation.isToolbarTransitioning }
    var durableEditHistory: [PortablePackageEditRevision] { editHistory.history }
    var durableCurrentEditRevision: UInt64 { editHistory.currentRevision }

    /// Compatibility projection for the copy/paste coordinator's value-only clipboard.
    /// The payload contains no images; the root exposes it to existing views and commands.
    var editClipboard: EditClipboardPayload? { editClipboardWorkflow.clipboard }

    var editClipboardCategories: Set<EditClipboardPayload.Category> {
        editClipboardWorkflow.clipboardCategories
    }

    var canPasteEdits: Bool { editClipboardWorkflow.canPaste }

    /// The most recent persistence warning. A damaged edit catalog must not prevent the source
    /// image from opening, but it should remain visible to the user.
    @Published private(set) var editStoreStatus: String?

    /// The status-bar text last published by a failed edit write. A later successful write clears
    /// the bar only when that text is still showing, so an unrelated status is left alone.
    private var persistenceFailureMessage: String?

    /// Compatibility diagnostics for the application boundary. Persistence accounting is owned by
    /// `EditPersistenceCoordinator`; these accessors keep existing integrations and tests stable.
    var pendingPersistenceCount: Int { persistence.pendingCount }

    /// How to reproduce the open image. Held instead of a decoded `CIImage` because a RAW has to be
    /// re-developed to honour `document.rawDevelop` (§4.2).
    private var imageSource: ImageSource? {
        didSet { if oldValue?.cacheFingerprint != imageSource?.cacheFingerprint { retouchWorkflow.activeSourceDidChange() } }
    }

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

    /// Tabs for the current image. Develop stays out of the icon bar until that row fits the
    /// column; the develop stage itself is unchanged.
    var availableInspectorTabs: [InspectorTab] {
        guard !isCropToolActive else { return [] }
        return InspectorTab.availableTabs(
            // Retain the visible tab set across a photo cutover. The histogram remains published
            // until the new source's histogram is ready, so it marks this brief loading interval.
            hasImage: sourceImage != nil || histogram != nil,
            developPanelState: developPanelState,
            hasMaskingTarget: maskingAssetID != nil
        )
    }

    private var activeAssetID: PhotoAssetID?
    private var activeSourceReference: EditSourceReference? {
        didSet { virtualCopyMetadata?.activeAssetChanged(to: activeSourceReference?.portableAssetID) }
    }
    /// Cached copy-relationship snapshot for the inspector; nil without a portable library.
    private var virtualCopyMetadata: VirtualCopyMetadataCoordinator?
    /// Source generation prevents delayed work from a previous navigation selection from publishing
    /// into the new image, even if the source values happen to compare equal.
    var sourceRevision: UInt64 { sourceSession.sourceRevision }
    /// Document generation guards the primary visible render and histogram publications.
    private var documentRevision: UInt64 = 0
    /// Owns the stored-edit adoption rules and per-source reconciliation state (KRMA-755, KRMA-885).
    private let storedEditAdoption = StoredEditAdoptionCoordinator()
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
    private lazy var previewPublicationCoordinator = PreviewPublicationCoordinator(
        destination: self
    )
    var isPreviewInteractionActive: Bool {
        get { previewAdmissionCoordinator.isPreviewInteractionActive }
        set { previewAdmissionCoordinator.isPreviewInteractionActive = newValue }
    }
    /// Owns Look resolution (library scan, then derived registry), the missing-reference report,
    /// and selection/audition decisions. The document stays here; see `LookSelectionCoordinator`.
    private lazy var lookSelection = LookSelectionCoordinator(library: library)
    /// Package-backed edit history, named snapshots, and virtual-copy I/O for the active photo.
    private lazy var editHistory = EditHistoryCoordinator(
        store: editStore,
        environment: .init(
            activeSourceReference: { [weak self] in self?.activeSourceReference },
            currentDocument: { [weak self] in self?.document ?? EditDocument() },
            endUndoGrouping: { [weak self] in self?.endUndoGrouping() },
            flushPersistence: { [weak self] in
                guard let persistence = self?.persistence else { return false }
                return await persistence.flush() == .success
            },
            adoptRestoredRevision: { [weak self] restored, priorDocuments in
                self?.adoptRestoredEditRevision(restored, priorDocuments: priorDocuments)
            },
            reportStatus: { [weak self] in self?.statusMessage = $0 }
        ),
        willChange: { [weak self] in self?.objectWillChange.send() }
    )

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

    /// The split/single presentation affordance is available for every loaded source. This is
    /// intentionally broader than `isComparisonAvailable`: an identity document still has valid
    /// pixels, so both panes can show the same source image until a visible edit exists to compare.
    var isComparisonPresentationAvailable: Bool { sourceImage != nil }

    /// The visible render is owned by these surfaces, not published image values on this model.
    let previewSurface = PreviewSurface()
    let originalPreviewSurface = PreviewSurface()

    /// High-frequency canvas and transient crop state live outside the broad application
    /// publisher. Only the views that observe `canvasState` reevaluate for pointer interaction.
    private lazy var canvasWorkflow: CanvasWorkflowCoordinator = {
        let coordinator = CanvasWorkflowCoordinator(destination: self)
        return coordinator
    }()
    var canvasState: CanvasInteractionState { canvasWorkflow.interactionState }
    /// Selection, transient creation, and smart-mask analysis state for the masking workspace,
    /// owned by `MaskingWorkflowCoordinator`. AppViewModel remains the document/undo/preview owner
    /// that coordinator's commands commit through.
    var maskInteractionState: MaskInteractionState { maskingWorkflow.interactionState }
    var retouchInteractionState: RetouchInteractionState { retouchWorkflow.interactionState }

    /// Inspector chrome has a separate observation boundary for the same reason. The view model
    /// keeps compatibility accessors below so existing commands and tests retain their API while
    /// SwiftUI views can observe the narrow state object directly.
    let inspectorState = InspectorState()

    var canvasNavigation: CanvasNavigation { canvasState.navigation }
    var isCropToolActive: Bool { canvasState.isCropToolActive }
    var cropDraft: CGRect? { canvasState.cropDraft }
    var cropAspectRatio: CropAspectRatio { canvasState.cropAspectRatio }
    var cropOrientation: CropAspectRatioOrientation { canvasState.cropOrientation }
    var cropRotation: ImageRotation { canvasState.cropRotation }
    var cropStraightenAngle: Double { canvasState.cropStraightenAngle }
    var cropFlipHorizontal: Bool { canvasState.cropFlipHorizontal }
    var cropFlipVertical: Bool { canvasState.cropFlipVertical }
    var cropVerticalPerspective: Double { canvasState.cropVerticalPerspective }
    var cropHorizontalPerspective: Double { canvasState.cropHorizontalPerspective }
    var cropSourceSize: CGSize { canvasWorkflow.cropSourceSize }

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

    var isRetouchCanvasActive: Bool {
        retouchInteractionState.isArmed && inspectorState.isPresented
            && inspectorState.tab == .retouch && navigation.isEdit && sourceImage != nil
    }

    /// Route every inspector-tab selection through the shared workspace transition. Masking keeps
    /// its persistent editor and selection semantics; the other tabs remain ordinary inspector
    /// navigation and implicitly return from Masking when selected.
    func selectInspectorTab(_ requestedTab: InspectorTab) {
        if isCropToolActive {
            guard requestedTab == .retouch || requestedTab == .masking else { return }
            cancelCrop()
        }
        if requestedTab == .masking {
            retouchWorkflow.setArmed(false)
            openMaskingWorkspace()
        } else {
            if requestedTab == .retouch, inspectorState.isMaskingWorkspacePresented {
                closeMaskingWorkspace()
            }
            if requestedTab == .retouch {
                retouchInteractionState.mode = .heal
            }
            inspectorState.select(requestedTab)
            retouchWorkflow.setArmed(requestedTab == .retouch)
        }
    }

    var hasCropAdjustments: Bool { !document.crop.isIdentity }

    /// Inspector visibility. Computing the histogram is gated on this so we don't tally pixels
    /// for a panel nobody's looking at.
    enum InspectorTab: String, CaseIterable, Sendable {
        // Case order is the visible inspector order. Develop remains hidden by its capability
        // gate, so keep it last without changing the order users see.
        case light, adjust, effects, masking, retouch, look, info, develop

        /// The view surface selected by this tab. Keep `.adjust` as the stored compatibility case;
        /// its photographer-facing name is Color.
        enum Content: Equatable, Sendable {
            case info, light, develop, color, effects, look, masking, retouch
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
            case .retouch: return .retouch
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
            case .retouch: return "bandage"
            }
        }

        var title: String {
            switch self {
            case .info: return "Info"
            case .light: return "Light"
            case .develop: return "Develop"
            case .adjust: return "Color"
            case .effects: return "Effects"
            case .look: return "Looks"
            case .masking: return "Masks"
            case .retouch: return "Heal"
            }
        }

        /// Describes the panel's purpose for compact icon-only navigation controls.
        var purpose: String {
            switch self {
            case .info: return "Photo name, file type, and metadata"
            case .light: return "Tone and RGB curve adjustments"
            case .develop: return "RAW decoder controls"
            case .adjust: return "Color adjustments"
            case .effects: return "Texture, clarity, and dehaze effects"
            case .look: return "Browse and apply a Look"
            case .masking: return "Create and edit local masks"
            case .retouch: return "Heal or clone spots and correct red-eye"
            }
        }

        var helpText: String { "\(title): \(purpose)" }

        /// Develop is a real inspector stage, but its icon makes the tab bar wider than the
        /// column. Keep the case and the capability gate; withhold the tab until the bar fits.
        static let showsDevelopTab = false

        static func availableTabs(
            hasImage: Bool,
            developPanelState: DevelopPanelState,
            hasMaskingTarget: Bool = true
        ) -> [InspectorTab] {
            guard hasImage else { return [] }
            return allCases.filter { tab in
                switch tab {
                case .develop:
                    return showsDevelopTab && developPanelState.offersDevelopTab
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
    var isSelectiveCopyDialogPresented: Bool {
        get { editClipboardWorkflow.isSelectiveCopyDialogPresented }
        set { editClipboardWorkflow.isSelectiveCopyDialogPresented = newValue }
    }
    var selectiveCopyCategories: Set<EditClipboardPayload.Category> {
        get { editClipboardWorkflow.selectiveCopyCategories }
        set { editClipboardWorkflow.selectiveCopyCategories = newValue }
    }
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

    /// Auto has its own analysis lifecycle rather than borrowing the Info histogram's loading flag:
    /// an Auto request must not make the histogram spinner appear to be waiting on unrelated work.
    @Published private(set) var autoAdjustmentState: AutoAdjustmentState = .unavailable(
        "Open a supported photo to enable Auto."
    )
    /// Determinate progress for the Auto lifecycle. `nil` means Auto is settled; unlike the Info
    /// histogram flag, this value belongs only to the active Auto invocation.
    @Published private(set) var autoAdjustmentProgress: Double?
    private let autoWorkflowCoordinator = AutoWorkflowCoordinator()

    /// Single owner of the source-loading presentation flags (KRMA-910). The façade properties
    /// below are read-only projections; every write goes through a named transition.
    @Published private(set) var presentation = SourcePresentationState()
    var isLoading: Bool { presentation.isLoading }
    /// Navigation waits only until the selected source has a usable frame on the surface. Full
    /// preview readiness remains separate because RAW development and other render work can
    /// continue after its embedded camera preview has already been presented.
    var isNavigationLoading: Bool { presentation.isNavigationLoading }
    enum PreviewState: Equatable, Sendable {
        case empty
        case loading
        case ready
        case failed
    }
    /// Source preparation and preview presentation are separate async stages. This state keeps
    /// the transparent source marker from making a not-yet-presented canvas look like a black one.
    var previewState: PreviewState { presentation.previewState }
    @Published var statusMessage: String = "Open an image to get started"
    private var pendingImportOutcome: (summary: ImportOutcomeSummary, prefix: String)?

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
    /// Bridges streamed Photos package results to one deferred collection refresh and source
    /// handoff. Package writes and collection/document ownership remain with their coordinators.
    private let photosImportBatchCoordinator = PhotosImportBatchCoordinator()
    private var bestEffortFrameStoreFlushTask: Task<Void, Never>?
    /// Replaces cache flush work in lifecycle tests so they can hold each store independently.
    var frameStoreFlushOperationsForTesting: FrameStoreFlushOperations?
    /// Every asynchronous import handoff captures this token. A late provider result can never
    /// publish into a newer import operation.
    @Published private(set) var portableImportProgress: PortablePackageImportProgress?

    /// Removable volumes are discovered independently of the selector so the Import menu can name
    /// mounted volumes that contain supported images, or offer a permission-recovery path when
    /// the sandbox cannot inspect a volume until the user selects it.
    var removableMediaVolumes: [MediaVolume] { libraryMediaWorkflow.removableMediaVolumes }
    var isRemovableMediaSelectorPresented: Bool {
        get { libraryMediaWorkflow.isRemovableMediaSelectorPresented }
        set { libraryMediaWorkflow.isRemovableMediaSelectorPresented = newValue }
    }
    var removableMediaVolume: MediaVolume? { libraryMediaWorkflow.removableMediaVolume }
    var mediaImportSource: MediaImportSource { libraryMediaWorkflow.importSource }
    var removableMediaFiles: [MediaVolumeFile] { libraryMediaWorkflow.removableMediaFiles }
    var removableMediaWarnings: [String] { libraryMediaWorkflow.removableMediaWarnings }
    var removableMediaInLibrary: Set<String> { libraryMediaWorkflow.removableMediaInLibrary }
    var removableMediaLibraryChecked: Int { libraryMediaWorkflow.removableMediaLibraryChecked }
    var isCheckingRemovableMediaLibrary: Bool { libraryMediaWorkflow.isCheckingRemovableMediaLibrary }
    var visibleRemovableMediaFiles: [MediaVolumeFile] { libraryMediaWorkflow.visibleRemovableMediaFiles }
    var hidesInLibraryRemovableMedia: Bool {
        get { libraryMediaWorkflow.hidesInLibraryRemovableMedia }
        set { libraryMediaWorkflow.hidesInLibraryRemovableMedia = newValue }
    }
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
    /// Edit-aware collection thumbnail scheduling and cache publication.
    private lazy var editedThumbnailCoordinator = EditedThumbnailCoordinator(
        workScheduler: workScheduler, engine: engine, editStore: editStore,
        frameStore: thumbnailFrameStore, frameLookupLedger: frameLookupLedger, destination: self
    )
    /// Persisted original and latest-edited thumbnails in `Derived/Thumbnails`. Rebuildable cache:
    /// losing it costs a decode or render, never an edit.
    let thumbnailFrameStore: ThumbnailFrameStore
    let frameLookupLedger: FrameLookupLedger
    let lookPreviewCoordinator: LookPreviewCoordinator
    let collection: ImageCollection
    let editStore: EditDocumentStore
    /// Value-only editor sessions and history. The published document remains owned by
    /// AppViewModel so render scheduling has one presentation-state owner.
    let editorDocument: EditorDocumentCoordinator
    let editClipboardWorkflow: EditClipboardCoordinator
    /// Provider interaction and progress belong to the application composition root, while this
    /// model remains the narrow destination for durable collection admission and source loading.
    let photosImportCoordinator: PhotosImportCoordinator
    let photosImportReview = PhotosImportReviewCoordinator()
    /// Shared package-write generation, cancellation, and progress owner for every import source.
    private lazy var libraryImportCoordinator = LibraryImportCoordinator(
        package: portableLibrary,
        isShuttingDown: { [weak self] in self?.isShuttingDown ?? true },
        publishProgress: { [weak self] progress in self?.portableImportProgress = progress },
        publishStatus: { [weak self] status in self?.statusMessage = status }
    )
    /// Folder, removable-media and Photos-drop import orchestration over the shared coordinator.
    private lazy var packageSourceImports = PackageSourceImportCoordinator(
        imports: libraryImportCoordinator, destination: self
    )
    /// Coalesced durable edit snapshots. The application model routes persistence policy here;
    /// file I/O remains inside `EditDocumentStore`.
    let persistence: EditPersistenceCoordinator
    /// The production library boundary. Package membership and originals are canonical; the
    /// collection is only the bounded presentation bridge.
    private(set) var portableLibrary: PortableLibrarySession?
    /// The single portable filter/sort/search authority (KRMA-519 scope item 3). The collection is
    /// only a bounded presentation bridge; filtering runs in the query controller.
    @Published var portableQuery = LibraryQuery.all
    /// Background compaction shares the scheduler with editor work but uses its detached
    /// package-I/O lane, so a foreground edit can take the admission window back immediately.
    /// Writing images to disk — the single export, the batch run, and naming. Production exports
    /// use an isolated RenderEngine lane while preserving the same render request funnel.
    let export: ExportCoordinator
    /// Export entry points, Share, external-editor handoff, and bundle export.
    let exportWorkflow: ExportWorkflowCoordinator
    /// The "Derive Look from JPG" flow and its scratch-until-saved result.
    let derive = DeriveCoordinator()
    /// The active-document global Look export flow. It snapshots edits and never mutates them while
    /// the user reviews omissions or chooses a destination.
    let lookSave = LookSaveCoordinator()
    let libraryMediaWorkflow: LibraryMediaWorkflowCoordinator
    private let libraryDeletionCoordinator: LibraryDeletionCoordinator
    private lazy var libraryBrowsingCoordinator = LibraryBrowsingCoordinator(
        collection: collection, library: portableLibrary, destination: self,
        scheduler: workScheduler, frameStore: thumbnailFrameStore,
        hintsStore: LaunchHintsStore(url: KromoraStorage.launchHintsURL())
    )
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

    /// Long-running work that quitting would cancel.
    var terminationGuard: TerminationGuard {
        TerminationGuard(
            batchExportTotal: isBatchExporting ? export.batchTotal : nil,
            photosImportTotal: photosImportProgress?.total,
            packageImportTotal: portableImportProgress.flatMap { $0.phase == .finished ? nil : $0.total }
        )
    }
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
    /// Owns masking workspace selection, transient creation, and smart-mask analysis lifecycle.
    let maskingWorkflow: MaskingWorkflowCoordinator
    let retouchWorkflow: RetouchWorkflowCoordinator

    var maskingAssetID: PhotoAssetID? { isShuttingDown ? nil : activeAssetID }
    var maskingSourceRevision: UInt64 { sourceRevision }
    var maskingSource: ImageSource? { isShuttingDown ? nil : imageSource }
    var hasOpenSource: Bool { sourceImage != nil }

    var activeEditedThumbnailAssetID: PhotoAssetID? { activeAssetID }
    var editedThumbnailSourceRevision: UInt64 { sourceRevision }
    var editedThumbnailDocumentRevision: UInt64 { documentRevision }
    var isEditedThumbnailShuttingDown: Bool { isShuttingDown }
    var isEditedThumbnailInteractionActive: Bool { isPreviewInteractionActive }
    var isEditedThumbnailPreviewDebouncing: Bool { previewAdmissionCoordinator.isPreviewDebouncing }
    var editedThumbnailItems: [ImageCollection.Item] { collection.items }
    var visibleEditedThumbnailAssetIDs: Set<PhotoAssetID> {
        collection.visibleEditedThumbnailAssetIDs
    }
    func editedThumbnailItem(for assetID: PhotoAssetID) -> ImageCollection.Item? {
        collection.items.first { $0.id == assetID }
    }
    func editedThumbnailDocument(for assetID: PhotoAssetID) -> EditDocument? {
        editorDocument.session(for: assetID)?.document
    }
    func editedThumbnailDocumentRevision(for assetID: PhotoAssetID) -> UInt64 {
        editorDocument.revision(for: assetID)
    }
    func resolvedEditedThumbnailLUT(_ id: LUTID?) -> CubeLUT? { resolvedLUT(id) }
    func markEditedThumbnailStale(for assetID: PhotoAssetID) {
        editedThumbnailItem(for: assetID)?.markEditedThumbnailStale()
    }
    func applyEditedThumbnail(_ image: NSImage?, for assetID: PhotoAssetID, revision: String) {
        collection.applyEditedThumbnail(image, for: assetID, revision: revision)
    }
    func applyStoredEditedThumbnail(
        _ image: NSImage, metadata: PresentationFrameMetadata, for assetID: PhotoAssetID
    ) {
        collection.applyStoredEditedThumbnail(image, metadata: metadata, for: assetID)
    }
    func confirmStoredEditedThumbnail(
        revision: String, metadata: PresentationFrameMetadata, for assetID: PhotoAssetID
    ) -> Bool {
        collection.confirmStoredEditedThumbnail(
            revision: revision, metadata: metadata, for: assetID
        )
    }
    func setEditedThumbnailPresentedCrop(
        _ crop: CropAdjustments, rotation: ImageRotation, for assetID: PhotoAssetID
    ) {
        collection.setPresentedCrop(crop, rotation: rotation, for: assetID)
    }

    func setMaskingStatusMessage(_ message: String) { statusMessage = message }

    func presentMaskingWorkspace() {
        inspectorState.select(.masking)
        inspectorState.isPresented = true
        isMaskingPanelPresented = false
    }

    func dismissMaskingWorkspace() {
        inspectorState.isMaskingWorkspacePresented = false
    }

    func setRetouchCanvasActive(_ active: Bool) {
        guard active else { return }
        if isCropToolActive { cancelCrop() }
        if inspectorState.isMaskingWorkspacePresented { closeMaskingWorkspace() }
        inspectorState.select(.retouch)
        inspectorState.isPresented = true
    }
    private let preferences: UserDefaults
    /// An injected edit store is a non-production composition boundary. It may be used while a
    /// second model is inspecting the same package, so source navigation can fall back to the
    /// caller-owned URL if the package writer lease is already held by the first model.
    private let usesInjectedEditStore: Bool
    private let previewCoordinator: PreviewCoordinator
    private let previewPresentation: PreviewPresentationCoordinator
    private let firstFrames: FirstFramePresentationCoordinator
    private var loadRequestGeneration: UInt64 = 0
    /// In-flight browsing-placeholder resolutions keyed by their request generation.
    private var placeholderMaterializationTasks: [UInt64: Task<Void, Never>] = [:]

    /// Value-only counters used by the opt-in Release presentation qualification harness.
    var presentationSessionForDiagnostics: PreviewPresentationCoordinator.PresentationSession? {
        previewPresentation.presentationSession
    }
    var previewRenderAdmissionCountForDiagnostics: Int {
        previewCoordinator.renderAdmissionCount
    }
    var canonicalWriteAdmissionCountForDiagnostics: Int {
        previewPresentation.canonicalWriteAdmissionCount
    }
    func waitForCanonicalWriteForDiagnostics(for identity: PortablePhotoIdentity) async {
        await previewPresentation.waitForCanonicalWriteForDiagnostics(for: identity)
    }
    private lazy var previewAdmissionCoordinator = PreviewAdmissionCoordinator(
        workScheduler: workScheduler, engine: engine, destination: self
    )
    private lazy var idleFrameWarmerCoordinator = IdleFrameWarmerCoordinator(
        scheduler: workScheduler, engine: engine, editStore: editStore,
        thumbnailStore: thumbnailFrameStore, previewPresentation: previewPresentation,
        destination: self
    )
    var idleFrameWarmerProgressForDiagnostics: IdleFrameWarmerProgress {
        idleFrameWarmerCoordinator.progress
    }
    /// The adopted revision's own Look identity, from its content-addressed reference. It lets a
    /// stored frame be judged exact before the Look browser has scanned the Look.
    private var storedEditLook: LookSignature?
    private struct PendingStoredFrameConfirmation {
        let image: CIImage
        let request: RenderRequest
        let assetID: PhotoAssetID?
        let sourceRevision: UInt64
        let displayRevision: UInt64
    }
    private var pendingStoredFrameConfirmation: PendingStoredFrameConfirmation?
    /// The embedded camera JPEG is a presentation-only first frame. It never enters the render
    /// coordinator or any supporting-work path, and is cancelled when navigation selects another
    /// source.
    private let fileDialog: any FileDialogProviding
    private let lookSheets: LookLibrarySheets
    private let sourceSession: SourceSessionCoordinator
    private var lutCacheInvalidationTask: Task<Void, Never>?
    private var semanticCoordinatorInstallTask: Task<Void, Never>?
    private var pendingPersistenceFlush: Task<PersistenceFlushResult, Never>?
    private(set) var isShuttingDown = false
    private var cancellables: [AnyCancellable] = []
    /// The reason the package is unavailable, once its open has failed.
    var portableLibraryOpenError: String? {
        if case .failed(let message) = libraryOpen.state { message } else { nil }
    }
    let portablePackageURL: URL
    let libraryOpen: LibraryOpenCoordinator

    var canImportIntoPortableLibrary: Bool { portableLibrary != nil }

    private var portableLibraryUnavailableMessage: String {
        if libraryOpen.state == .opening {
            return "Kromora is still opening the library. Try again in a moment."
        }
        let reason = portableLibraryOpenError ?? "The library package is unavailable."
        return "\(reason) Resolve the library issue and relaunch Kromora before importing."
    }

    func reportPortableLibraryUnavailable() {
        // A command attempted mid-open is not a failure; the status line is enough.
        if libraryOpen.state == .opening {
            statusMessage = portableLibraryUnavailableMessage
        } else {
            presentError(portableLibraryUnavailableMessage)
        }
    }

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
            includeBundledLooks: false,
            portablePackageURL: packageURL,
            asynchronousPortableLibraryIndexLoading: true
        )
    }

    /// Production entry points opt into the packaged starter library. The plain initializer stays
    /// bundle-free for headless/test clients that intentionally provide their own Look folder.
    public convenience init(includeBundledLooks: Bool) {
        let packageURL = KromoraStorage.defaultPortableLibraryPackageURL
        self.init(
            engine: RenderEngine.shared,
            includeBundledLooks: includeBundledLooks,
            portablePackageURL: packageURL,
            asynchronousPortableLibraryIndexLoading: true
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
        userLookFolderURL: URL? = nil,
        photoAnalysisCoordinator: PhotoAnalysisCoordinator? = nil,
        previewFrameStoreDirectory: URL? = nil,
        previewFrameStoreCapBytes: Int64 = LatestPreviewFrameStore.defaultCapBytes,
        previewFrameReader: @escaping PreviewPresentationCoordinator.StoredFrameReader = PreviewPresentationCoordinator.readStoredFrame,
        thumbnailFrameStoreDirectory: URL? = nil,
        portablePackageURL: URL,
        portableMaintenanceIdleDelay: Duration = .seconds(2),
        frameLookupLedger: FrameLookupLedger = .shared,
        originalThumbnailProvider: @escaping ImageCollection.OriginalThumbnailProvider = { url, data, fingerprint, identity, store, ledger, surface in
            await OriginalThumbnailLoader.load(
                url: url, data: data, dataFingerprint: fingerprint,
                identity: identity, store: store, ledger: ledger, surface: surface
            )
        },
        embeddedFirstFrameProvider: @escaping @Sendable (URL) async -> NSImage? = { url in
            Thumbnails.generate(from: url, maxPixelSize: Thumbnails.firstFrameMaxPixelSize)
        },
        fileDialog: any FileDialogProviding = AppKitFileDialog(),
        sheets: any SheetPresenting = AppKitSheetPresenter(),
        fileDropActionPolicy: FileDropActionPolicy = FileDropActionPolicy(),
        leaseRecoveryConfirmer: (any PortablePackageLeaseRecoveryConfirming)? = nil,
        settings injectedSettings: KromoraSettings? = nil,
        portableLibrarySession injectedPortableLibrarySession: PortableLibrarySession? = nil,
        asynchronousPortableLibraryIndexLoading: Bool = false,
        defersLibraryOpen: Bool = false,
        packageOpener: any PackageOpening = PortablePackageOpener()
    ) {
        var interval = KromoraSignpostInterval(.launch, context: .unknown)
        defer { interval.end() }

        self.engine = engine
        self.frameLookupLedger = frameLookupLedger
        let analysisCoordinator =
            photoAnalysisCoordinator ?? PhotoAnalysisCoordinator(engine: engine)
        self.photoAnalysisCoordinator = analysisCoordinator
        self.preferences = preferences
        self.usesInjectedEditStore = editStore != nil
        let normalizedPortablePackageURL = portablePackageURL.standardizedFileURL
        self.portablePackageURL = normalizedPortablePackageURL
        // Create the shared package-I/O scheduler before opening the session so its lease
        // heartbeat is admitted on the same lane as imports and maintenance.
        let packageIOScheduler = ImageWorkScheduler()
        let openedPortableLibrary: PortableLibrarySession?
        let portableOpenError: String?
        let effectiveEditStore: EditDocumentStore
        var recoveredPreviousWriter = false
        if defersLibraryOpen, injectedPortableLibrarySession == nil {
            // Late-bound: `openLibrary(confirmer:)` opens the package and binds it later. Until
            // then the store reports `.opening` and nothing is written under the package URL.
            openedPortableLibrary = nil
            portableOpenError = nil
            effectiveEditStore = editStore ?? EditDocumentStore.makeUnboundStore()
        } else {
          do {
            let session: PortableLibrarySession
            if let injectedPortableLibrarySession {
                session = injectedPortableLibrarySession
            } else {
                let opened = try PortablePackageOpener.openBlocking(
                    at: normalizedPortablePackageURL,
                    asynchronousIndexLoading: asynchronousPortableLibraryIndexLoading
                ) { info in
                    leaseRecoveryConfirmer?.confirmBreakExpiredWriterLease(
                        packageURL: normalizedPortablePackageURL, info: info) == true
                }
                session = try PortableLibrarySession(
                    opened: opened, scheduler: packageIOScheduler,
                    asynchronousIndexLoading: asynchronousPortableLibraryIndexLoading)
                recoveredPreviousWriter = opened.recoveredPreviousWriter
            }
            openedPortableLibrary = session
            portableOpenError = nil
            // An explicitly supplied store is an integration boundary for headless clients and
            // tests. Preserve it even when the library package opens successfully; otherwise the
            // composition root silently discards the caller's persistence authority and relaunch
            // checks observe a different store. Production initializers omit this argument and
            // therefore use the package's canonical edit sidecars.
            effectiveEditStore =
                editStore
                ?? EditDocumentStore(
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
        }
        self.libraryOpen = LibraryOpenCoordinator(
            opener: packageOpener,
            state: openedPortableLibrary != nil ? .ready
                : portableOpenError.map { .failed($0) } ?? .idle
        )
        self.editStore = effectiveEditStore
        self.editorDocument = EditorDocumentCoordinator()
        self.photosImportCoordinator = PhotosImportCoordinator()
        self.maskingWorkflow = MaskingWorkflowCoordinator(analysis: analysisCoordinator)
        self.retouchWorkflow = RetouchWorkflowCoordinator()
        self.settings = injectedSettings ?? KromoraSettings(
            preferences: preferences,
            userLookFolderURL: userLookFolderURL
        )
        self.editClipboardWorkflow = EditClipboardCoordinator(
            editor: self.editorDocument, settings: self.settings
        )
        self.workScheduler = packageIOScheduler
        self.persistence = EditPersistenceCoordinator(store: effectiveEditStore)
        // Look thumbnails have a bounded, independent thumbnail lane. Sharing the editor's lane
        // would let a burst of filmstrip/grid work evict a row's continuation before it can return.
        self.lookPreviewCoordinator = LookPreviewCoordinator(
            engine: engine, scheduler: ImageWorkScheduler()
        )
        self.collection = ImageCollection(
            scheduler: workScheduler,
            frameLookupLedger: frameLookupLedger,
            originalThumbnailProvider: originalThumbnailProvider
        )
        self.library = LUTLibrary(
            preferences: preferences,
            userLookFolderURL: settings.ensureUserLookFolder(),
            includeBundled: includeBundledLooks
        )
        self.lookSheets = LookLibrarySheets(sheets: sheets, library: self.library)
        self.export = ExportCoordinator(
            engine: engine,
            maskResolver: CoordinatorLocalMaskResolver(coordinator: analysisCoordinator),
            editStore: effectiveEditStore
        )
        self.exportWorkflow = ExportWorkflowCoordinator(export: self.export)
        self.previewCoordinator = PreviewCoordinator(engine: engine, scheduler: workScheduler)
        let previewFrameStore = LatestPreviewFrameStore(
            directory: previewFrameStoreDirectory
                ?? LatestPreviewFrameStore.packageDirectory(for: normalizedPortablePackageURL),
            capBytes: previewFrameStoreCapBytes,
            workScheduler: workScheduler
        )
        self.previewPresentation = PreviewPresentationCoordinator(
            store: previewFrameStore, engine: engine, frameLookupLedger: frameLookupLedger,
            storedFrameReader: previewFrameReader)
        self.firstFrames = FirstFramePresentationCoordinator(presentation: previewPresentation)
        self.thumbnailFrameStore = ThumbnailFrameStore(
            directory: thumbnailFrameStoreDirectory
                ?? ThumbnailFrameStore.packageDirectory(for: normalizedPortablePackageURL),
            workScheduler: workScheduler
        )
        collection.thumbnailFrameStore = thumbnailFrameStore
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
            packageLease: nil,
            idleDelay: portableMaintenanceIdleDelay
        )
        let deletionCollection = self.collection
        self.libraryDeletionCoordinator = LibraryDeletionCoordinator(
            collection: self.collection,
            persistence: self.persistence,
            editStore: self.editStore,
            photoAnalysis: self.photoAnalysisCoordinator,
            portableLibrary: nil,
            persistenceIdentity: { item in
                guard deletionCollection.sourceKind(for: item) == .managed else { return nil }
                return item.asset.source.portableIdentity
            },
            allowsUnregisteredSourceDeletion: self.usesInjectedEditStore
        )
        self.libraryDeletionCoordinator.destination = self
        self.photosImportCoordinator.destination = self
        self.photosImportReview.onImport = { [weak self] selections, provider in
            self?.photosImportCoordinator.start(selections: selections, provider: provider)
        }
        self.photosImportBatchCoordinator.destination = self
        self.photosImportCoordinator.onStatus = { [weak self] message in
            self?.statusMessage = message
        }
        self.editClipboardWorkflow.destination = self
        self.exportWorkflow.destination = self
        self.maskingWorkflow.destination = self
        self.retouchWorkflow.destination = self

        collection.onThumbnailDemand = { [weak self] assetID, priority in
            self?.requestEditedThumbnail(for: assetID, priority: priority)
        }
        libraryBrowsingCoordinator.onViewportPublished = { [weak self] ids in
            guard let self else { return }
            self.cancelIdlePreviewBuild()
            self.updatePinnedFrameAssets(visible: ids)
            self.scheduleIdlePreviewBuild()
        }
        if let renderEngine = engine as? RenderEngine {
            semanticCoordinatorInstallTask = Task {
                await renderEngine.installSemanticMaskCoordinator(analysisCoordinator)
            }
        }

        persistence.onStatusChange = { [weak self] status in
            guard let self else { return }
            self.editStoreStatus = status
            if status == nil, let failure = self.persistenceFailureMessage,
               self.statusMessage == failure {
                self.persistenceFailureMessage = nil
                self.statusMessage = ""
            }
        }
        persistence.onFailure = { [weak self] message in
            self?.persistenceFailureMessage = message
            self?.statusMessage = message
        }
        persistence.onDurableWrite = { [weak self] reference in
            guard self?.activeSourceReference == reference else { return }
            self?.refreshDurableEditHistory()
        }

        libraryMediaWorkflow.onStatus = { [weak self] message in
            self?.statusMessage = message
        }
        libraryMediaWorkflow.onError = { [weak self] message in
            self?.presentError(message)
        }
        libraryMediaWorkflow.onImageURL = { [weak self] url, access in
            self?.openImage(url: url, access: access)
        }
        libraryMediaWorkflow.onImageURLs = { [weak self] urls, accesses in
            self?.openImages(urls: urls, access: accesses)
        }
        libraryMediaWorkflow.onImportRequest = { [weak self] request in
            self?.importRemovableMedia(request)
        }
        applicationShell.onMediaChanged = { [weak self] in
            self?.libraryMediaWorkflow.refreshRemovableMedia()
        }
        applicationShell.onApplicationActivated = { [weak self] in
            self?.portableLibrary?.renewAfterWake()
            self?.scheduleIdlePreviewBuild()
        }
        applicationShell.onApplicationDeactivated = { [weak self] in
            self?.cancelIdlePreviewBuild()
            self?.requestBestEffortFrameStoreFlush()
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
            self.publishPreviewFailure()
            self.publishAutoAdjustmentState(
                .unavailable("Auto is unavailable because the photo preview failed."))
            self.statusMessage =
                "Could not display \(self.sourceName). Try Fit or reload the photo."
            self.presentPendingImportOutcome()
        }
        previewSurface.onPresentationHistogramSampleChange = { [weak self] sample in
            self?.previewAdmissionCoordinator.presentationHistogramSampleDidChange(sample)
        }
        originalPreviewSurface.onPresentationFailure = { [weak self] in
            guard let self, !self.isShuttingDown, self.sourceImage != nil else { return }
            self.statusMessage =
                "Could not display the comparison preview. Try Fit or reload the photo."
        }

        sourceSession.onPreparation = { [weak self] publication in
            guard let self, !self.isShuttingDown,
                publication.request.sourceRevision == self.sourceRevision,
                publication.request.assetID == self.activeAssetID else { return }
            let switchUptime = self.previewPresentation.presentationSession?.selectionUptime
            KromoraObservability.photoSwitchPhase("sourcePrepared", since: switchUptime)
            self.install(preparation: publication.preparation, request: publication.request)
            KromoraObservability.photoSwitchPhase("sourceInstalled", since: switchUptime)
            if self.previewAdmissionCoordinator.scheduledSourceRevision != self.sourceRevision {
                self.schedulePreview()
            }
            KromoraObservability.photoSwitchPhase("previewScheduled", since: switchUptime)
        }
        sourceSession.onStoredDocumentLoaded = { [weak self] publication in
            guard let self, !self.isShuttingDown,
                publication.request.sourceRevision == self.sourceRevision,
                publication.request.assetID == self.activeAssetID else { return }
            KromoraObservability.photoSwitchPhase(
                "storedDocumentLoaded", since: self.previewPresentation.presentationSession?.selectionUptime
            )
            self.adoptStoredDocumentValues(publication.result, for: publication.request)
        }
        sourceSession.onStoredDocument = { [weak self] publication in
            guard let self, !self.isShuttingDown else { return }
            self.adoptStoredEdits(publication.result, for: publication.request)
        }
        sourceSession.onMetadata = { [weak self] publication in
            guard let self, !self.isShuttingDown,
                publication.request.sourceRevision == self.sourceRevision,
                publication.request.assetID == self.activeAssetID
            else { return }
            self.metadata = publication.metadata
            KromoraObservability.photoSwitchPhase(
                "metadataPublished", since: self.previewPresentation.presentationSession?.selectionUptime
            )
        }
        sourceSession.onCapabilities = { [weak self] publication in
            guard let self, !self.isShuttingDown,
                publication.request.sourceRevision == self.sourceRevision,
                publication.request.assetID == self.activeAssetID
            else { return }
            self.rawCapabilities = publication.capabilities
            self.capabilitiesProbeCompleted = true
            self.keepInspectorTabValid()
            KromoraObservability.photoSwitchPhase(
                "capabilitiesPublished", since: self.previewPresentation.presentationSession?.selectionUptime
            )
        }
        sourceSession.onFirstFrame = { [weak self] publication in
            guard let self, !self.isShuttingDown else { return }
            self.presentEmbeddedFirstFrame(publication)
        }
        sourceSession.onFailure = { [weak self] request, message in
            guard let self, !self.isShuttingDown,
                request.sourceRevision == self.sourceRevision,
                request.assetID == self.activeAssetID
            else { return }
            self.presentation.sourceFailed(hasSource: self.sourceImage != nil)
            self.previewSurface.discardDepartingFrame()
            self.presentError(message)
            self.presentPendingImportOutcome()
        }

        // KRMA-521: High-frequency children (collection/items, import, export, canvas) are
        // @Observable and observed directly by their views through `@Bindable`. They are
        // intentionally absent from the forwarding list below: thumbnail streaming, metadata,
        // scan ticks, canvas pointer updates, and import/export progress must not reevaluate
        // unrelated inspector or toolbar views. A Task per child notification also had incorrect
        // will-change timing, so no forwarding path here may spawn a Task.
        //
        // Derive, look-save and the removable-media workflow are observed directly by
        // `FeatureSheetsModifier`, `RemovableMediaMenu` and `RemovableMediaSelectorView`, so they
        // are also absent below. Settings and the Look library are observed directly by
        // `LookInspectorView`, `FilmstripView`, the grid cells, `PreviewView`, `KromoraCommands`
        // and the settings view. Remaining ObservableObject children (editor document, edit
        // clipboard) are still consumed via `viewModel.*` (clipboard/undo read
        // `editClipboardWorkflow`/`editorDocument`). Forward synchronously:
        // `send()` in the same turn preserves will-change timing until views hold children directly
        // and the corresponding entry can be removed. Delete this loop only when every entry
        // is gone; removing an entry before its views observe the child directly makes that
        // surface stale (sheets stop presenting, library scans stop refreshing).
        for child in [
            editorDocument.objectWillChange.eraseToAnyPublisher(),
            editClipboardWorkflow.objectWillChange.eraseToAnyPublisher(),
        ] {
            cancellables.append(
                child.sink { [weak self] _ in
                    guard let self, !self.isShuttingDown else { return }
                    self.objectWillChange.send()
                })
        }

        // Inspector chrome is observed by its own view subtree. Histogram work still belongs to
        // this model. Use InspectorState's post-assignment callback so the gate sees the new
        // value synchronously; @Published emits from willSet and would otherwise read stale state.
        inspectorState.onPresentationChange = { [weak self] in
            self?.refreshHistogramGate()
        }

        // The overlay's look is a Settings preference; the masking canvas reads it from its own
        // interaction state. @Published delivers the stored value immediately, then each change.
        cancellables.append(
            settings.$maskOverlayAppearance.sink { [weak self] appearance in
                self?.maskInteractionState.apply(appearance)
            })

        previewCoordinator.onPublication = { [weak self] publication in
            self?.previewPublicationCoordinator.publish(publication)
        }
        previewCoordinator.onFailure = { [weak self] request in
            guard request.quality == .preview else { return }
            guard let self, request.source == self.imageSource else { return }
            self.publishPreviewFailure()
            self.publishAutoAdjustmentState(
                .unavailable("Auto is unavailable because the photo preview failed."))
            if let message = self.semanticMaskFailureMessage(for: request.document) {
                self.maskInteractionState.markMaskFailed(message)
                self.statusMessage = message
            } else {
                self.statusMessage = "Could not render \(self.sourceName)"
            }
            self.presentPendingImportOutcome()
        }

        wireCoordinators()
        libraryOpen.onStateChange = { [weak self] state in self?.libraryOpenStateDidChange(state) }
        if let openedPortableLibrary {
            bindPortableLibrary(openedPortableLibrary, recoveredPreviousWriter: recoveredPreviousWriter)
        } else if !defersLibraryOpen {
            reportPortableLibraryUnavailable()
        }
        configureEmbeddedLooks()
    }

    /// The single place that threads an opened session into the model and its coordinators.
    func bindPortableLibrary(
        _ session: PortableLibrarySession, recoveredPreviousWriter: Bool
    ) {
        objectWillChange.send()
        portableLibrary = session
        virtualCopyMetadata = VirtualCopyMetadataCoordinator(
            reader: VirtualCopyMetadataCoordinator.packageReader(session.package),
            willChange: { [weak self] in self?.objectWillChange.send() }
        )
        libraryImportCoordinator.bind(package: session)
        libraryBrowsingCoordinator.bind(library: session)
        libraryDeletionCoordinator.bind(portableLibrary: session)
        applicationShell.bind(packageLease: session.lease)
        let store = editStore
        Task { [weak session] in await session?.mirrorCommittedMemberships(from: store) }
        let loader = LibraryMembershipMatcher.loader(for: session.package)
        libraryMediaWorkflow.libraryMatcherLoader = loader
        photosImportReview.libraryMatcherLoader = loader

        session.onIndexWriteFailure = { [weak self] message in
            guard let self, !self.isShuttingDown else { return }
            self.statusMessage = "Could not save the library index: \(message)"
        }
        session.onPresentedAspectRatioUpdates = { [weak self] updates in
            self?.libraryBrowsingCoordinator.applyPresentedAspectRatioUpdates(updates)
        }
        libraryBrowsingCoordinator.prepareLaunchHints()
        if session.isLoadingIndex {
            statusMessage = "Opening library index…"
        }
        session.onIndexLoadingStateChange = { [weak self] state in self?.handlePortableIndexLoadingState(state) }
        if let state = session.indexLoadingState {
            session.onIndexLoadingStateChange?(state)
        }
        if session.didRepairIndexOnOpen, !session.isLoadingIndex {
            statusMessage = "Rebuilt the library index from package membership."
        }
        if recoveredPreviousWriter {
            statusMessage = "Recovered interrupted writes from the previous library session."
        }
        // Launch paints the first query page from index summaries only; further pages fault in on
        // scroll/selection with stable identity.
        do {
            try reloadPortableWindow(pageIndex: 0)
            if collection.isActive { navigation.move(to: .grid) }
            collection.beginThumbnailDemand()
        } catch {
            presentError("Kromora could not read the library package: \(error.localizedDescription)")
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
        // identity, so a `.cube` replaced in place keeps it. The library reports which IDs now
        // resolve differently, and only work that referenced one of them is redone. Wired here,
        // before `restoreFolder()` runs below, so the launch scan is covered too.
        library.onScanned = { [weak self] delta in
            guard let self, !self.isShuttingDown else { return }
            self.refreshLUTResolutionStatus()
            self.applyLookLibraryDelta(delta)
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
        export.onActivityChanged = { [weak self] isActive in
            guard let self else { return }
            if isActive {
                self.cancelIdlePreviewBuild()
            } else {
                self.scheduleIdlePreviewBuild()
            }
        }
        export.onError = { [weak self] message in
            self?.exportWorkflow.exportFailed()
            self?.presentError(message)
        }
        export.onExportCompleted = { [weak self] url in
            self?.exportWorkflow.exportCompleted(at: url)
        }
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
        let sources = library.allLUTs.map { EmbeddedLookSource(id: $0.lutID.raw, url: $0.url) }
        let accesses = library.retainedAccesses
        let store = editStore
        Task { await store.loadEmbeddedLooks(sources, retaining: accesses) }
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
        lookSelection.register(saved)

        guard let current = document.lut.lutID, current == derive.derivedLUT?.lutID else { return }
        endUndoGrouping()
        updateDocument { $0.lut.lutID = saved.lutID }
    }

    // MARK: - Error presentation

    /// Surface a user-facing error both as a dismissible alert and in the
    /// status bar. Used for hard failures (load / export / derive / save);
    /// transient preview hiccups stay status-bar-only to avoid alert spam.
    func presentError(_ message: String) {
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
        sourceImage != nil && imageSource != nil && previewState == .ready && !isLoading
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

    /// Start Auto and apply its value-only result through the normal document commit path.
    func runAutoAdjustment() {
        guard sourceImage != nil, previewState == .ready, !isLoading, let imageSource else {
            return
        }
        endUndoGrouping()
        let sourceRevision = self.sourceRevision
        let documentRevision = self.documentRevision
        let assetID = self.activeAssetID
        let currentDocument = document
        let request = AutoWorkflowRequest(
            source: imageSource, assetID: assetID, document: currentDocument,
            lut: resolvedLUT(document.lut.lutID)
        )
        let runner = ProductionAutoWorkflow(engine: engine, analysis: photoAnalysisCoordinator)
        _ = autoWorkflowCoordinator.start(
            request: request, previewReady: previewState == .ready, runner: runner,
            isFenceCurrent: { [weak self] in
                guard let self else { return false }
                return self.activeAssetID == assetID && self.sourceRevision == sourceRevision
                    && self.imageSource == imageSource && self.documentRevision == documentRevision
            },
            onState: { [weak self] state, progress in
                self?.publishAutoAdjustmentState(state, progress: progress)
                if state == .analyzing {
                    self?.statusMessage =
                        "Analyzing \(self?.sourceName ?? "photo") for Auto adjustments…"
                }
                if state == .renderingCandidates {
                    self?.statusMessage = "Rendering Auto candidates…"
                }
                if state == .validating { self?.statusMessage = "Validating Auto candidates…" }
            },
            completion: { [weak self] invocationRevision, outcome in
                guard let self, self.autoWorkflowCoordinator.isCurrent(invocationRevision) else {
                    return
                }
                let samePhoto =
                    self.activeAssetID == assetID
                    && self.sourceRevision == sourceRevision && self.imageSource == imageSource
                guard samePhoto, self.documentRevision == documentRevision else {
                    if samePhoto { self.publishAutoAdjustmentState(.ready) }
                    return
                }
                switch outcome.result.status {
                case .improved:
                    let applied = EditDocument.applyingAutoResult(outcome.result, to: self.document)
                    self.publishAutoAdjustmentState(.applying, progress: 0.9)
                    self.statusMessage = "Applying Auto adjustments…"
                    self.updateDocument(preservingAutoResult: true) { $0 = applied }
                    self.publishAutoAdjustmentState(.ready)
                    self.statusMessage = outcome.message
                case .unchanged:
                    self.publishAutoAdjustmentState(.ready)
                    self.statusMessage = outcome.message
                case .noCandidate, .renderUnavailable:
                    let message = outcome.message
                    self.publishAutoAdjustmentState(.failed(message))
                    self.statusMessage = message
                case .cancelled:
                    self.publishAutoAdjustmentState(.ready)
                    self.statusMessage = "Auto cancelled; nothing was changed."
                case .staleRevision:
                    self.publishAutoAdjustmentState(.ready)
                    self.statusMessage = "Auto was superseded; nothing was changed."
                }
            }
        )
    }

    /// Cancel the active Auto operation without allowing a late result to commit.
    func cancelAutoAdjustment() {
        guard isAutoAdjustmentInProgress else { return }
        autoWorkflowCoordinator.cancel { [weak self] state, progress in
            self?.publishAutoAdjustmentState(state, progress: progress)
        }
        statusMessage = "Auto cancelled; nothing was changed."
    }

    func waitForAutoAdjustmentCompletion() async {
        await autoWorkflowCoordinator.waitForCompletion()
    }

    private func resetAutoAdjustmentForLifecycle() {
        autoWorkflowCoordinator.invalidate { [weak self] state, progress in
            self?.publishAutoAdjustmentState(state, progress: progress)
        }
    }

    // MARK: - Image loading

    private func beginImportOperation() -> UUID {
        libraryImportCoordinator.beginOperation()
    }

    private func isCurrentImport(_ id: UUID) -> Bool {
        libraryImportCoordinator.isCurrent(id)
    }

    private func presentImportOutcome(_ summary: ImportOutcomeSummary, prefix: String) {
        // Opening an imported photo immediately enters the source-loading state. Keep terminal
        // import outcomes until its first preview settles so partial failures remain visible.
        guard previewState != .loading, !statusMessage.hasPrefix("Loading ") else {
            pendingImportOutcome = (summary, prefix)
            return
        }
        pendingImportOutcome = nil
        statusMessage = summary.status(prefix: prefix)
    }

    private func presentPendingImportOutcome() {
        guard previewState != .loading,
            !statusMessage.hasPrefix("Loading "),
            let pendingImportOutcome
        else { return }
        self.pendingImportOutcome = nil
        statusMessage = pendingImportOutcome.summary.status(prefix: pendingImportOutcome.prefix)
    }

    private func failOpenImage(_ url: URL, reason: String) {
        // A failed replacement import must not blank an already displayed photo. For a fresh
        // open, however, the import boundary is the source-loading boundary, so publish the same
        // terminal state the source session uses and let callers stop waiting on published state.
        guard sourceImage == nil else {
            presentImportOutcome(
                .failure(total: 1, reason: "\(url.lastPathComponent): \(reason)"),
                prefix: "Photo import"
            )
            return
        }
        presentation.openFailed()
        previewSurface.discardDepartingFrame()
        presentError("Could not open \(url.lastPathComponent): \(reason)")
    }

    /// Cancels the running package import. Photos committed so far stay in the Library.
    func cancelLibraryImport() {
        guard portableImportProgress != nil else { return }
        libraryImportCoordinator.cancelCurrent()
        statusMessage = "Cancelling import…"
    }

    private func reloadPortableCollection() throws {
        previewAdmissionCoordinator.cancelAdjacentPreviewPrefetch()
        try libraryBrowsingCoordinator.reloadPortableCollection()
        logFrameLookupSummaries([.gridOriginal, .gridEdited, .filmstrip, .launchHint])
    }

    /// Publish one query page as the visible window (KRMA-519 scope items 2-3). Membership,
    /// ordering, filtering, and selection come from the query controller; the collection holds
    /// only the window's Items as a presentation adapter.
    func reloadPortableWindow(pageIndex: Int = 0) throws {
        previewAdmissionCoordinator.cancelAdjacentPreviewPrefetch()
        try libraryBrowsingCoordinator.reloadPortableWindow(pageIndex: pageIndex)
        logFrameLookupSummaries([.gridOriginal, .gridEdited, .filmstrip, .launchHint])
    }

    /// Fault the next page when the visible window approaches its tail. Grid/filmstrip call this
    /// from `onAppear` of trailing cells so scrolling never materializes the full library.
    func loadMorePortableIfNeeded(currentIndex: Int) {
        libraryBrowsingCoordinator.loadMorePortableIfNeeded(currentIndex: currentIndex)
    }

    /// Portable filtering/sorting preserve user-visible behavior without materializing the full
    /// collection: the query controller re-pages from summaries and the window reloads page 0.
    func setPortableFilter(_ filter: LibraryFilter) {
        previewAdmissionCoordinator.cancelAdjacentPreviewPrefetch()
        libraryBrowsingCoordinator.setPortableFilter(filter)
    }

    func setPortableFacets(_ facets: LibraryFacetSelection) {
        previewAdmissionCoordinator.cancelAdjacentPreviewPrefetch()
        libraryBrowsingCoordinator.setPortableFacets(facets)
    }

    func clearPortableFilters() {
        previewAdmissionCoordinator.cancelAdjacentPreviewPrefetch()
        libraryBrowsingCoordinator.clearPortableFilters()
    }

    func portableFacetCounts() async -> LibraryFacetCounts? {
        await libraryBrowsingCoordinator.portableFacetCounts()
    }

    func setPortableSort(_ sort: LibraryQuerySort) {
        previewAdmissionCoordinator.cancelAdjacentPreviewPrefetch()
        libraryBrowsingCoordinator.setPortableSort(sort)
    }

    func setPortableSearch(_ text: String?) {
        previewAdmissionCoordinator.cancelAdjacentPreviewPrefetch()
        libraryBrowsingCoordinator.setPortableSearch(text)
    }

    /// Route a presentation selection through the query-controller authority, then mirror back.
    /// Ordinary click replaces, Command toggles, Shift is approximated as additive here because
    /// range extension needs the ordered window IDs owned by the collection.
    func selectPortableItem(at index: Int, modifiers: LibrarySelectionModel.Modifiers = []) {
        libraryBrowsingCoordinator.selectPortableItem(at: index, modifiers: modifiers)
    }

    /// Grid keyboard stepping under the single portable authority. Unlike the editor
    /// steppers, moving in the grid changes selection without opening the asset; at the
    /// window tail with more pages, the next page faults in first so keyboard traversal
    /// covers the full query without materializing it.
    func selectNextPortableInGrid() {
        libraryBrowsingCoordinator.selectNextPortableInGrid()
    }

    func selectPreviousPortableInGrid() {
        libraryBrowsingCoordinator.selectPreviousPortableInGrid()
    }

    /// Down/Up in the grid move by one row of the current column count.
    func selectPortableRowBelowInGrid() {
        libraryBrowsingCoordinator.selectPortableRowBelowInGrid()
    }

    func selectPortableRowAboveInGrid() {
        libraryBrowsingCoordinator.selectPortableRowAboveInGrid()
    }

    private func openPortableAsset(_ assetID: PortablePhotoAssetID) {
        libraryBrowsingCoordinator.openPortableAsset(assetID)
    }

    func openImage(
        url: URL,
        operationID: UUID? = nil,
        access: SecurityScopedResourceAccess? = nil
    ) {
        var transferredAccess = false
        defer {
            if !transferredAccess { access?.release() }
        }
        // A browsed collection already owns a stable source identity. Re-importing the URL here
        // would route it through package duplicate detection, which intentionally hashes bytes and
        // can therefore collapse two distinct files with identical contents onto one edit record.
        // Keep navigation on the collection item's identity instead.
        if let item = collection.items.first(where: { item in
            guard let itemURL = item.url else { return false }
            let sameURL =
                itemURL.standardizedFileURL.resolvingSymlinksInPath()
                == url.standardizedFileURL.resolvingSymlinksInPath()
            return sameURL || (usesInjectedEditStore && item.displayName == url.lastPathComponent)
        }) {
            let sameURL =
                item.url?.standardizedFileURL.resolvingSymlinksInPath()
                == url.standardizedFileURL.resolvingSymlinksInPath()
            // A package-backed item may have an embedded URL while an injected store is reopening
            // the original fixture path. Keep the caller's URL as the relink locator in that case.
            openImage(url: sameURL ? (item.url ?? url) : url, assetID: item.id)
            return
        }

        let operationID = operationID ?? beginImportOperation()
        cancelPendingPreviewDebounce()
        guard portableLibrary != nil else {
            if usesInjectedEditStore {
                load(name: url.lastPathComponent, url: url, data: nil)
                return
            }
            reportPortableLibraryUnavailable()
            return
        }
        do {
            // A direct URL open is a request to keep this source addressable. The collection-aware
            // path above handles reopening an already admitted source, while a new URL must remain
            // distinct even when its bytes match another referenced photo.
            let handle = try libraryImportCoordinator.startImportURLs(
                [url], duplicatePolicy: .importAnyway, access: access.map { [$0] } ?? []
            )
            transferredAccess = access != nil
            packageSourceImports.observe(
                handle, operationID: operationID, total: 1, prefix: "Photo import",
                onSuccess: { [weak self] result in
                    guard let self else { return }
                    guard
                        let assetID = result.imported.first?.assetID
                            ?? result.duplicates.first?.existingAssetID
                    else {
                        self.failOpenImage(
                            url,
                            reason: result.failures.first?.reason ?? "The import produced no asset."
                        )
                        return
                    }
                    do {
                        try self.reloadPortableCollection()
                        // Injected stores may be used by a second model while the first model still
                        // owns the package lease. Preserve the caller's URL as the edit locator in
                        // that mode; production remains copy-on-import and opens the embedded
                        // package original through openPortableAsset.
                        if self.usesInjectedEditStore {
                            if let item = self.collection.items.first(where: {
                                $0.asset.source.portableIdentity.assetID == assetID
                            }) {
                                self.openImage(url: url, assetID: item.id)
                            } else {
                                self.load(
                                    name: url.lastPathComponent, url: url, data: nil,
                                    assetID: PhotoAssetID(rawValue: "portable:" + assetID.raw)
                                )
                            }
                        } else {
                            self.openPortableAsset(assetID)
                        }
                        self.presentImportOutcome(
                            ImportOutcomeSummary(result: result, total: 1),
                            prefix: "Photo import"
                        )
                    } catch { self.presentError(error.localizedDescription) }
                },
                onFailure: { [weak self] error in
                    guard let self, self.isCurrentImport(operationID) else { return }
                    self.failOpenImage(url, reason: error.localizedDescription)
                }
            )
        } catch {
            guard isCurrentImport(operationID) else { return }
            failOpenImage(url, reason: error.localizedDescription)
        }
    }

    private func openImage(
        url: URL, assetID: PhotoAssetID, selectionUptime: UInt64? = nil,
        collectionAlreadySelected: Bool = false
    ) {
        guard !isShuttingDown else { return }
        previewAdmissionCoordinator.cancelAdjacentPreviewPrefetch()
        cancelPendingPreviewDebounce()
        // Assign the value so @Published sends immediately. This open path can now suspend while
        // resolving a browsing record, before `load` publishes its normal loading-state changes.
        navigation = NavigationState(mode: .edit)
        if !collectionAlreadySelected { focusCollectionItem(id: assetID) }
        let item = collection.items.first(where: { $0.id == assetID })
        if let item,
            item.asset.source.portableIdentity.sourceFingerprint.isBrowsingPlaceholder,
            let portableLibrary
        {
            // Record I/O and the bounded file signature lookup belong off the main actor. Fence
            // late opens against a newer selection before publishing the durable source identity.
            loadRequestGeneration &+= 1
            let resolutionGeneration = loadRequestGeneration
            let portableAssetID = item.asset.source.portableIdentity.assetID
            let previousStatusMessage = statusMessage
            presentation.beginSelection()
            // Fence the canvas before suspending, exactly as `load` does: the previous photo's
            // pixels must never remain on screen while the selected photo's record resolves.
            imageSource = nil
            sourceImage = nil
            previewPresentation.resetForSource()
            previewSurface.clearForSourceSwitch()
            originalPreviewSurface.clear()
            statusMessage = "Loading \(item.displayName)..."
            // The root owns the task so shutdown can drain it before the package lease is released.
            // A superseded request stays registered until it returns; dropping the handle would
            // neither cancel nor await it.
            placeholderMaterializationTasks[resolutionGeneration] = Task { @MainActor [weak self] in
                guard let self else { return }
                defer { self.placeholderMaterializationTasks[resolutionGeneration] = nil }
                await Task.yield()
                do {
                    guard !self.isShuttingDown else { return }
                    let resolved = try await portableLibrary.materializedAsset(for: portableAssetID)
                    guard !self.isShuttingDown, self.loadRequestGeneration == resolutionGeneration,
                        let current = self.collection.items.first(where: { $0.id == assetID })
                    else { return }
                    // Keep the actual identity on the collection item so later ImageSource values
                    // (thumbnails, previews, and persistence) reuse its hash for an unchanged file.
                    current.asset = resolved
                    guard self.navigation.isEdit else {
                        self.presentation.endSelection(
                            previewState: self.sourceImage == nil ? .empty : .ready)
                        self.statusMessage = self.sourceImage == nil
                            ? "Open an image to get started" : previousStatusMessage
                        self.presentPendingImportOutcome()
                        return
                    }
                    self.openImage(
                        url: url, assetID: assetID, selectionUptime: selectionUptime,
                        collectionAlreadySelected: true
                    )
                } catch {
                    guard !self.isShuttingDown, self.loadRequestGeneration == resolutionGeneration
                    else { return }
                    self.presentation.endSelection()
                    self.failOpenImage(url, reason: error.localizedDescription)
                }
            }
            return
        }
        let itemName = item?.displayName
        let name =
            itemName.map { displayName in
                let ext = url.pathExtension
                guard !ext.isEmpty else { return displayName }
                let dotted = ".\(ext.lowercased())"
                let lowercased = displayName.lowercased()
                if lowercased.hasSuffix(dotted) || lowercased.contains(dotted) {
                    return displayName
                }
                return "\(displayName).\(ext)"
            } ?? url.lastPathComponent
        load(
            name: name, url: url, data: nil, assetID: assetID,
            portableIdentity: item.flatMap { persistencePortableIdentity(for: $0) },
            fileChangeSignature: item?.asset.source.fingerprint,
            presentationSelectionUptime: selectionUptime
        )
    }

    /// Package assets carry the opaque UUID assigned when they entered the library and remain
    /// relocation-safe.
    private func persistencePortableIdentity(for item: ImageCollection.Item)
        -> PortablePhotoIdentity?
    {
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
        previewAdmissionCoordinator.cancelPendingPreviewWork()
    }

    private func invalidateEditedThumbnailWork(for assetID: PhotoAssetID?) {
        editedThumbnailCoordinator.invalidateWork(for: assetID)
    }

    private func cancelIdlePreviewBuild(resetCursor: Bool = false) {
        previewAdmissionCoordinator.cancelIdlePreviewBuild(resetCursor: resetCursor)
    }

    private func scheduleAdjacentPreviewPrefetch() {
        previewAdmissionCoordinator.scheduleAdjacentPreviewPrefetch()
    }

    private func scheduleIdlePreviewBuild() {
        previewAdmissionCoordinator.scheduleIdlePreviewBuild()
    }

    private func updatePinnedFrameAssets(visible: [PhotoAssetID]) {
        var pinned = Set(visible.map(PortablePhotoAssetID.compatibility(from:)))
        if let active = portableLibrary?.portableActiveID { pinned.insert(active) }
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.previewPresentation.setPinnedFrameAssets(pinned)
        }
    }

    /// Stop cache-only work before any user-visible operation gets a chance to enter the editor
    /// lane. The scheduler's background job may already be inside one Core Image call; cancellation
    /// bounds that unavoidable tail to the current item and the generation guards the result.
    /// Prepare a source without decoding pixels, then publish it and render the previews. RAW
    /// demosaicing remains renderer-owned and happens at the requested preview scale. The worker
    /// below deliberately has one active preparation and one replaceable pending request.
    private func load(
        name: String, url: URL?, data: Data?, assetID: PhotoAssetID? = nil,
        traceQuality: String = "open", dataFingerprint: String? = nil,
        portableIdentity: PortablePhotoIdentity? = nil,
        fileChangeSignature: PhotoSourceFingerprint? = nil,
        presentationSelectionUptime: UInt64? = nil
    ) {
        guard !isShuttingDown else { return }
        let loadClock = ContinuousClock()
        var loadMark = loadClock.now
        func lap(_ name: String) -> String {
            let now = loadClock.now
            defer { loadMark = now }
            let parts = (now - loadMark).components
            return "\(name)=\(Int(parts.seconds * 1000 + parts.attoseconds / 1_000_000_000_000_000))"
        }
        var laps: [String] = []
        cancelIdlePreviewBuild(resetCursor: true)
        laps.append(lap("cancelIdlePreviewBuildMs"))
        let importPlan = SourceImportDraft(
            name: name, url: url, data: data, assetID: assetID,
            portableIdentity: portableIdentity, fileChangeSignature: fileChangeSignature,
            dataFingerprint: dataFingerprint,
            traceQuality: traceQuality
        )
        loadRequestGeneration &+= 1
        let requestGeneration = loadRequestGeneration
        let previousActiveAssetID = activeAssetID
        // A file-backed draft without a supplied identity publishes it once resolved off-main.
        presentation.setInspectorDocumentPending(
            previousActiveAssetID != nil
                && previousActiveAssetID != importPlan.assetID
                && importPlan.assetID.map { editorDocument.session(for: $0) == nil } ?? true)

        // Make the source switch observable and invalidate old pixels immediately. Package state,
        // editor cleanup, and candidate materialization continue after the selection event yields.
        activeAssetID = importPlan.assetID
        laps.append(lap("planMs"))
        updatePinnedFrameAssets(visible: Array(collection.visibleEditedThumbnailAssetIDs))
        laps.append(lap("pinnedFramesMs"))
        presentation.beginSelection()
        imageSource = nil
        sourceImage = nil
        statusMessage = "Loading \(importPlan.name)..."
        laps.append(lap("publishedStateMs"))
        previewPresentation.resetForSource()
        laps.append(lap("presentationResetMs"))
        previewSurface.clearForSourceSwitch()
        laps.append(lap("clearSurfaceMs"))
        originalPreviewSurface.clear()
        laps.append(lap("clearOriginalSurfaceMs"))
        KromoraObservability.photoSwitchPhase(
            "loadSyncPrefix", since: presentationSelectionUptime, detail: laps.joined(separator: " ")
        )

        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, !self.isShuttingDown,
                self.loadRequestGeneration == requestGeneration else { return }
            KromoraObservability.photoSwitchPhase("beginLoadScheduled", since: presentationSelectionUptime)
            // The file's identity resolves off the main actor; a newer selection supersedes it.
            let resolvedPlan = await importPlan.resolved()
            guard !self.isShuttingDown, self.loadRequestGeneration == requestGeneration else { return }
            self.beginLoad(
                resolvedPlan, previousActiveAssetID: previousActiveAssetID,
                presentationSelectionUptime: presentationSelectionUptime
            )
        }
    }

    private func beginLoad(
        _ importPlan: SourceImportPlan, previousActiveAssetID: PhotoAssetID?,
        presentationSelectionUptime: UInt64?
    ) {
        guard !isShuttingDown else { return }
        // A real open always wins over cache-only work. Keep this adjacent to the existing
        // prefetch cancellation: the two jobs have separate identities and separate lifecycles.
        cancelIdlePreviewBuild(resetCursor: true)
        previewCoordinator.cancel()
        cancelPendingPreviewDebounce()
        let assetID = importPlan.assetID
        endUndoGrouping()
        resetAutoAdjustmentForLifecycle()
        maskingWorkflow.cancelInFlightSmartMask()
        // Discrete edits are queued normally; switching sources is a durability boundary for them.
        // Do not rewrite an unchanged document merely because navigation occurred.
        let persistenceBarrier = requestPersistenceFlush()
        KromoraObservability.photoSwitchPhase("persistenceFlushRequested", since: presentationSelectionUptime)
        // `sourceImage` is cleared below to fence edit operations while decoding. Keep the
        // toolbar's settled enabled appearance until this selected photo publishes or fails.
        presentation.beginToolbarTransition()
        activeAssetID = assetID
        let sourceReference = importPlan.sourceReference
        activeSourceReference = sourceReference
        let session = editorDocument.session(for: assetID)
        document = session?.document ?? EditDocument()
        comparisonBaselineDocument = document.comparisonBaseline
        editorDocument.activate(session: session)
        if let session {
            collection.setPresentedCrop(
                session.document.crop, rotation: session.document.rotation, for: assetID)
        }
        KromoraObservability.photoSwitchPhase("documentActivated", since: presentationSelectionUptime)
        refreshDurableEditHistory()
        KromoraObservability.photoSwitchPhase("editHistoryRefreshed", since: presentationSelectionUptime)
        lookSelection.resetReportedStatus()
        lutResolutionStatus = nil
        refreshLUTResolutionStatus()
        KromoraObservability.photoSwitchPhase("lutStatusRefreshed", since: presentationSelectionUptime)

        previewPresentation.resetForSource()
        let presentationGeneration = sourceSession.sourceRevision &+ 1
        let presentationIdentity = importPlan.source.portableIdentity
        previewPresentation.beginPresentationSession(
            assetID: assetID, identity: presentationIdentity,
            generation: presentationGeneration,
            allowsSourceGeometry: session.map {
                $0.document.crop.isIdentity && $0.document.rotation == .zero
            } ?? false,
            selectionUptime: presentationSelectionUptime ?? DispatchTime.now().uptimeNanoseconds
        )
        storedEditAdoption.reset()
        storedEditLook = nil
        firstFrames.resetForSource()
        pendingStoredFrameConfirmation = nil
        // Keep the last published chart visible while the newly selected source prepares and
        // renders. Histogram admission still checks the active asset and source revision before
        // publishing, so only the current photo can replace it.
        cancelHistogram(clear: false, pump: false)
        invalidateEditedThumbnailWork(for: previousActiveAssetID)
        editedThumbnailCoordinator.clearPendingRequest()
        // Fence the old asset synchronously. Only already-materialized pixels owned by the new
        // selection may fill the canvas while preparation and rendering suspend.
        var stagedThumbnail: FirstFramePresentationCoordinator.DeferredThumbnail?
        if let item = collection.items.first(where: { $0.id == assetID }),
            item.asset.source.portableIdentity == presentationIdentity
        {
            if let edited = item.editedThumbnailForPresentation,
                let cgImage = Self.cgImage(from: edited)
            {
                stagedThumbnail = FirstFramePresentationCoordinator.DeferredThumbnail(
                    image: CIImage(cgImage: cgImage), source: .editedThumbnail,
                    assetID: assetID, identity: presentationIdentity,
                    generation: presentationGeneration,
                    nativeExtent: CGSize(width: cgImage.width, height: cgImage.height)
                )
            } else if let original = item.originalThumbnailForPresentation,
                let cgImage = Self.cgImage(from: original)
            {
                stagedThumbnail = FirstFramePresentationCoordinator.DeferredThumbnail(
                    image: CIImage(cgImage: cgImage), source: .originalThumbnail,
                    assetID: assetID, identity: presentationIdentity,
                    generation: presentationGeneration, nativeExtent: item.thumbnailNativeExtent
                )
            }
        }
        firstFrames.stage(thumbnail: stagedThumbnail)
        KromoraObservability.photoSwitchPhase(
            "thumbnailCandidateBuilt", since: presentationSelectionUptime,
            detail: "candidate=\(stagedThumbnail.map { "\($0.source)" } ?? "none")"
        )
        previewAdmissionCoordinator.resetDeferredSettledPreview()
        // The latest persisted frame is read while the source prepares. It needs only the
        // identity the collection already holds, so it can paint before any decode.
        previewPresentation.beginStoredFrameLookup(
            assetID: assetID, identity: presentationIdentity, generation: presentationGeneration
        ) { [weak self] candidate in
            guard let self, !self.isShuttingDown else { return }
            let release = self.firstFrames.storedFrameLookupFinished(
                generation: presentationGeneration, hit: candidate != nil
            )
            if let candidate {
                self.presentProvisionalCandidate(
                    CIImage(cgImage: candidate.image), source: .storedFrame,
                    assetID: assetID, identity: presentationIdentity,
                    generation: presentationGeneration,
                    perceptualDigest: candidate.metadata.perceptualDigest,
                    nativeExtent: CGSize(
                        width: candidate.metadata.pixelWidth,
                        height: candidate.metadata.pixelHeight
                    )
                )
            } else {
                self.present(release)
            }
            self.previewAdmissionCoordinator.resumeDeferredSettledPreview()
        }
        firstFrames.armFallback(generation: presentationGeneration) { [weak self] release in
            guard let self, !self.isShuttingDown else { return }
            self.present(release)
        }
        if canvasState.isCropToolActive {
            canvasWorkflow.discardCropForSourceChange()
        }
        canvasWorkflow.resetForSource()
        maskInteractionState.resetForSource()
        restoreMaskSelection()
        resetResolutionPlanners()
        cancelWhiteBalanceSampling()
        // No source pixels are available to editing tools during the transition. PreviewView may
        // still display the last confirmed frame with a loading indicator over it.
        sourceImage = nil
        presentation.markPreviewLoading()
        // The old source must not describe the empty/loading state or gate the new image's
        // inspector while its pixels are being decoded.
        imageSource = nil
        previewPublicationCoordinator.resetForSource()
        sourceURL = nil
        sourceSize = .zero
        isPreviewInteractionActive = false
        // Space comparison is transient and belongs to the source being left. The user's
        // single-vs-side-by-side preference intentionally remains intact across photo switches.
        isShowingOriginal = false
        metadata = ImageMetadata()
        cancelComparisonPreview(pump: false)
        previewAdmissionCoordinator.resetComparisonPreviewAdmission()
        previewAdmissionCoordinator.cancelAdjacentPreviewPrefetch()
        cancelPendingPreviewDebounce()
        rawCapabilities = nil
        capabilitiesProbeCompleted = false
        // Keep the tab during the transient no-source interval. The new source publication below
        // validates it once its actual capabilities are known; resetting here would make an import
        // change an unrelated inspector preference merely because source preparation is async.

        presentation.beginSourcePreparation()
        statusMessage = "Loading \(importPlan.name)..."

        KromoraObservability.photoSwitchPhase("beginLoadSyncEnd", since: presentationSelectionUptime)
        sourceSession.begin(
            plan: importPlan,
            editSessionRevision: editorDocument.revision(for: assetID),
            hadInMemorySession: session != nil,
            persistenceBarrier: persistenceBarrier
        )
    }

    private func presentProvisionalCandidate(
        _ image: CIImage, source: PreviewPresentationCoordinator.CandidateSource,
        assetID: PhotoAssetID, identity: PortablePhotoIdentity, generation: UInt64,
        perceptualDigest: PerceptualDigest? = nil,
        nativeExtent: CGSize
    ) {
        guard previewPresentation.presentProvisional(
            source, assetID: assetID, identity: identity, generation: generation
        ) else { return }
        firstFrames.candidateAdmitted(source)
        let extent = nativeExtent.width > 0 && nativeExtent.height > 0
            ? CGRect(origin: .zero, size: nativeExtent) : image.extent
        let rasterSource: PresentationRasterSource
        switch source {
        case .storedFrame: rasterSource = .stored
        case .editedThumbnail, .originalThumbnail: rasterSource = .thumbnail
        case .embeddedJPEG: rasterSource = .embedded
        case .rendered: rasterSource = .settled
        }
        _ = previewSurface.present(
            image, space: .current,
            revision: UInt64.max - generation,
            quality: .preview,
            presentationImageExtent: extent,
            coversPresentationExtent: true,
            perceptualDigest: perceptualDigest,
            presentationAssetID: assetID,
            rasterSource: rasterSource,
            materializesPresentationTexture: engine.materializesPresentationTextures,
            onPresented: { [weak self] in
                guard let self,
                    self.previewPresentation.presentationSession?.generation == generation,
                    self.previewPresentation.presentationSession?.assetID == assetID else { return }
                self.previewPresentation.confirmProvisionalPresentation(
                    source, assetID: assetID, identity: identity, generation: generation
                )
                if source == .storedFrame {
                    self.completePendingStoredFrameConfirmation(generation: generation)
                    self.previewAdmissionCoordinator.admitExactStoredFrameHistogramIfAvailable()
                }
                self.presentation.firstFramePresented()
            }
        )
    }

    /// Paints released first-frame candidates. The thumbnail goes first: once admitted it
    /// suppresses the embedded frame, which is then re-evaluated against the new session state.
    private func present(_ release: FirstFramePresentationCoordinator.Release) {
        if let thumbnail = release.thumbnail {
            presentProvisionalCandidate(
                thumbnail.image, source: thumbnail.source,
                assetID: thumbnail.assetID, identity: thumbnail.identity,
                generation: thumbnail.generation, nativeExtent: thumbnail.nativeExtent
            )
        }
        if let embedded = release.embedded {
            presentEmbeddedFirstFrame(embedded)
        }
    }

    private func completePendingStoredFrameConfirmation(generation: UInt64) {
        guard let pending = pendingStoredFrameConfirmation,
            pending.sourceRevision == generation,
            previewPresentation.hasPresentedStoredFrame(generation: generation)
        else { return }
        guard pending.displayRevision == displayRevision,
            pending.request.source == imageSource,
            pending.request.document == displayRequest.document
        else {
            pendingStoredFrameConfirmation = nil
            return
        }
        pendingStoredFrameConfirmation = nil
        _ = previewPublicationCoordinator.confirmExistingStoredFrame(
            pending.image, request: pending.request, assetID: pending.assetID,
            sourceRevision: pending.sourceRevision, displayRevision: pending.displayRevision
        )
    }

    private static func cgImage(from image: NSImage) -> CGImage? {
        image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }

    private func install(
        preparation: ImageSourcePreparation, request: SourceSessionCoordinator.Request
    ) {
        imageSource = preparation.source
        previewAdmissionCoordinator.resetScheduledSourceRevision()
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
        if request.plan.source.kind != .raw {
            statusMessage =
                "\(request.plan.name)  \(Int(preparation.nativeExtent.width))\u{00D7}\(Int(preparation.nativeExtent.height))"
        }
        presentation.sourcePrepared()
        keepInspectorTabValid()
        scheduleAdjacentPreviewPrefetch()
    }

    /// Present the source-session's optional camera JPEG while the RAW render is loading. The
    /// provisional frame is deliberately not a `PreviewCoordinator` publication and therefore
    /// cannot admit histogram, comparison, or cache work.
    private func presentEmbeddedFirstFrame(
        _ publication: SourceSessionCoordinator.FirstFramePublication
    ) {
        guard firstFrames.evaluateEmbedded(
            publication,
            context: .init(
                sourceRevision: sourceRevision, activeAssetID: activeAssetID,
                isSourceDocumentResolved: storedEditAdoption.isResolved(for: sourceRevision),
                isPreviewLoading: previewState == .loading,
                hasPublishedFrame: previewPublicationCoordinator.hasPublishedFrame
            )
        ) == .present,
            let cgImage = publication.image.cgImage(
                forProposedRect: nil, context: nil, hints: nil
            )
        else { return }

        // The camera JPEG is a stand-in for the whole photo. Do not rasterize it at
        // native RAW size — that is a 24–60MP GPU upload on every filmstrip click and
        // stalls the develop that should replace it. Keep the JPEG's own pixels and tell
        // the surface to stretch them across the native Fit/Fill frame. If the preview
        // is still sensor-landscape while native display size is portrait, rotate first
        // so the stretch cannot look like a 90° error.
        let native = publication.preparation.nativeExtent
        let provisional = PreviewSurface.alignedEmbeddedFirstFrame(
            CIImage(cgImage: cgImage), to: native
        )

        guard previewPresentation.presentProvisional(
            .embeddedJPEG, assetID: publication.request.assetID,
            identity: publication.preparation.source.portableIdentity,
            generation: publication.request.sourceRevision
        ) else { return }
        previewSurface.present(
            provisional, space: .current,
            // Presentation-only revision: the embedded JPEG is not renderer telemetry, but
            // it still participates in the drawable confirmation lifecycle.
            revision: UInt64.max - displayRevision,
            source: publication.preparation.source,
            quality: .preview,
            presentationImageExtent: CGRect(origin: .zero, size: native),
            coversPresentationExtent: true,
            presentationAssetID: publication.request.assetID,
            rasterSource: .embedded,
            materializesPresentationTexture: engine.materializesPresentationTextures,
            onPresented: { [weak self] in
                guard let self, !self.isShuttingDown,
                    publication.request.sourceRevision == self.sourceRevision,
                    publication.request.assetID == self.activeAssetID,
                    self.previewState == .loading
                else { return }
                self.previewPresentation.confirmProvisionalPresentation(
                    .embeddedJPEG, assetID: publication.request.assetID,
                    identity: publication.preparation.source.portableIdentity,
                    generation: publication.request.sourceRevision
                )
                self.presentation.firstFramePresented()
            }
        )
    }

    /// Stage one of stored-edit adoption: everything the Edit panel binds to, which needs no
    /// prepared source. It runs as soon as the small edit read completes, so the panel and the
    /// stored frame agree long before the (serialized, much slower) source preparation finishes.
    /// The source-dependent reconciliation stays in `adoptStoredEdits`.
    private func adoptStoredDocumentValues(
        _ stored: EditDocumentLoadResult, for request: SourceSessionCoordinator.Request
    ) {
        defer { presentation.inspectorDocumentSettled() }
        let context = storedAdoptionContext(stored, for: request)
        guard storedEditAdoption.decideEarlyAdoption(context) == .adopt else { return }
        document = stored.document
        comparisonBaselineDocument = document.comparisonBaseline
        editorDocument.adoptStoredDocument(document, for: request.assetID)
        collection.setPresentedCrop(document.crop, rotation: document.rotation, for: request.assetID)
        storedEditLook = stored.lookSignature
        resolveProvisionalSourceGeometry(for: request.sourceRevision)
        previewAdmissionCoordinator.admitExactStoredFrameHistogramIfAvailable()
    }

    private func storedAdoptionContext(
        _ stored: EditDocumentLoadResult, for request: SourceSessionCoordinator.Request
    ) -> StoredEditAdoptionCoordinator.Context {
        .init(
            requestSourceRevision: request.sourceRevision,
            currentSourceRevision: sourceRevision,
            hadInMemorySession: request.hadInMemorySession,
            changedInMemory: editorDocument.revision(for: request.assetID)
                != request.editSessionRevision,
            storedDocumentDiffers: document != stored.document,
            speculativeRenderScheduled:
                previewAdmissionCoordinator.scheduledSourceRevision == sourceRevision)
    }

    private func adoptStoredEdits(
        _ stored: EditDocumentLoadResult, for request: SourceSessionCoordinator.Request
    ) {
        defer { presentation.inspectorDocumentSettled() }
        let outcome = storedEditAdoption.decideLateAdoption(
            storedAdoptionContext(stored, for: request),
            hasDeferredSettledPreview: previewAdmissionCoordinator.hasDeferredSettledPreview)
        if outcome.shouldAdopt {
            if !outcome.adoptedEarly {
                document = stored.document
                comparisonBaselineDocument = document.comparisonBaseline
                editorDocument.adoptStoredDocument(document, for: request.assetID)
                collection.setPresentedCrop(
                    document.crop, rotation: document.rotation, for: request.assetID)
            }
            sourceSize = document.rotation.orientedExtent(imageSource?.nativeExtent ?? sourceSize)
            restoreMaskSelection()
            refreshLUTResolutionStatus()
            if outcome.documentChanged {
                documentRevision &+= 1
                previewPresentation.advanceComparisonRevision()
                scheduleAdjacentPreviewPrefetch()
            }
        }
        storedEditLook = stored.lookSignature
        resolveProvisionalSourceGeometry(for: request.sourceRevision)
        previewAdmissionCoordinator.admitExactStoredFrameHistogramIfAvailable()
        // A cold open already rendered the identity document speculatively; the corrective
        // queues behind it instead of cancelling it, so the first request still reaches the
        // engine (LUMO-317).
        switch outcome.followUp {
        case .correctivePreview:
            scheduleCorrectivePreview()
        case .resumeDeferredSettledPreview:
            previewAdmissionCoordinator.resumeDeferredSettledPreview()
        case .reconcilePresentedFrame:
            if let lastPresentedVisibleRequest =
                previewPublicationCoordinator.lastPresentedVisibleRequest,
                lastPresentedVisibleRequest.source == imageSource,
                lastPresentedVisibleRequest.document == displayRequest.document
            {
                // If the speculative frame already reached the drawable, it was intentionally not
                // allowed to start histogram work. Re-admit that final request now that
                // persistence has confirmed it is the document on screen.
                updateHistogram(
                    for: lastPresentedVisibleRequest,
                    presentedImage: previewPublicationCoordinator.lastPresentedVisibleImage)
                if publicationMayPersistFrame,
                    let image = previewPublicationCoordinator.lastPresentedVisibleImage
                {
                    writeCanonicalPreview(image, request: lastPresentedVisibleRequest)
                }
            }
        }
        scheduleEditedThumbnailAfterSettle(for: request.assetID, priority: .activeEditor)
        applyStoredLoadStatus(stored.status)
    }

    private func resolveProvisionalSourceGeometry(for generation: UInt64) {
        present(firstFrames.sourceGeometryResolved(document: document, generation: generation))
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
    @discardableResult
    func openImageDialog() -> Task<Void, Never> {
        Task { [weak self] in
            guard let self else { return }
            guard self.portableLibrary != nil else {
                self.reportPortableLibraryUnavailable()
                return
            }
            guard let urls = await self.fileDialog.chooseImages(
                startingAt: self.settings.defaultSourceFolderURL
            ) else { return }
            self.openImages(
                urls: urls,
                access: urls.map { .systemGranted(for: $0) }
            )
        }
    }

    /// Import the selected files through the worker-backed package path and open the first item.
    /// Returns immediately; package I/O runs off the main actor and security-scoped `access` is
    /// owned by that operation until it reaches a terminal state. `completion` receives the
    /// terminal summary exactly once for a current operation. It is not called when a newer import
    /// or shutdown supersedes this one, and gets `nil` for empty input or an unavailable package.
    /// Empty input is a no-op that does not cancel unrelated work or disturb the current edit.
    func openImages(
        urls: [URL],
        operationID: UUID? = nil,
        access: [SecurityScopedResourceAccess] = [],
        completion: (@MainActor (ImportOutcomeSummary?) -> Void)? = nil
    ) {
        guard !urls.isEmpty else {
            access.forEach { $0.release() }
            completion?(nil)
            return
        }
        let operationID = operationID ?? beginImportOperation()
        guard portableLibrary != nil else {
            access.forEach { $0.release() }
            reportPortableLibraryUnavailable()
            completion?(nil)
            return
        }
        let prefix = "Photo import"
        do {
            let handle = try libraryImportCoordinator.startImportURLs(urls, access: access)
            packageSourceImports.observe(
                handle, operationID: operationID, total: urls.count, prefix: prefix,
                onSuccess: { [weak self] result in
                    guard let self else { return }
                    do {
                        try self.reloadPortableCollection()
                        self.applyDialogNames(from: result)
                        // Import results retain input order, while the browsing projection is
                        // sorted by display name. Open the first displayed item so selection
                        // agrees with what the user sees.
                        if let firstItem = self.collection.items.first {
                            self.openPortableAsset(firstItem.asset.source.portableIdentity.assetID)
                        }
                        let summary = ImportOutcomeSummary(result: result, total: urls.count)
                        self.presentImportOutcome(summary, prefix: prefix)
                        completion?(summary)
                    } catch {
                        let summary = ImportOutcomeSummary.failure(
                            total: urls.count, reason: error.localizedDescription)
                        self.presentImportOutcome(summary, prefix: prefix)
                        completion?(summary)
                    }
                },
                onFailure: { [weak self] error in
                    guard let self, self.isCurrentImport(operationID) else { return }
                    let summary = ImportOutcomeSummary.failure(
                        total: urls.count, reason: error.localizedDescription)
                    self.presentImportOutcome(summary, prefix: prefix)
                    completion?(summary)
                }
            )
        } catch {
            guard isCurrentImport(operationID) else { return }
            let summary = ImportOutcomeSummary.failure(
                total: urls.count, reason: error.localizedDescription)
            presentImportOutcome(summary, prefix: prefix)
            completion?(summary)
        }
    }

    /// The package keeps each original filename (with extension) so the embedded source stays
    /// self-describing; Open Image… presents stems, so apply that only to assets this import named.
    private func applyDialogNames(from result: PortablePackageImportResult) {
        var names: [PortablePhotoAssetID: String] = [:]
        func stem(_ name: String) -> String {
            URL(fileURLWithPath: name).deletingPathExtension().lastPathComponent
        }
        for imported in result.imported { names[imported.assetID] = stem(imported.source.name) }
        for duplicate in result.duplicates {
            names[duplicate.existingAssetID] = stem(duplicate.source.name)
        }
        for item in collection.items {
            item.setDisplayNameOverride(names[item.asset.source.portableIdentity.assetID])
        }
    }

    // MARK: - Photo import

    func openImage(data: Data, name: String) {
        let operationID = beginImportOperation()
        guard portableLibrary != nil else {
            reportPortableLibraryUnavailable()
            return
        }
        do {
            let handle = try libraryImportCoordinator.startImportData(data, name: name)
            packageSourceImports.observe(
                handle, operationID: operationID, total: 1, prefix: "Photo import",
                onSuccess: { [weak self] result in
                    guard let self else { return }
                    do {
                        try self.reloadPortableCollection()
                        if let assetID = result.imported.first?.assetID
                            ?? result.duplicates.first?.existingAssetID
                        {
                            self.openPortableAsset(assetID)
                        }
                        self.presentImportOutcome(
                            ImportOutcomeSummary(result: result, total: 1),
                            prefix: "Photo import"
                        )
                    } catch { self.presentError(error.localizedDescription) }
                },
                onFailure: { [weak self] error in
                    guard let self, self.isCurrentImport(operationID) else { return }
                    self.presentImportOutcome(
                        .failure(total: 1, reason: "\(name): \(error.localizedDescription)"),
                        prefix: "Photo import"
                    )
                }
            )
        } catch {
            guard isCurrentImport(operationID) else { return }
            presentImportOutcome(
                .failure(total: 1, reason: "\(name): \(error.localizedDescription)"),
                prefix: "Photo import"
            )
        }
    }

    func importFromPhotos() {
        guard portableLibrary != nil else {
            reportPortableLibraryUnavailable()
            return
        }
        isPhotosPickerPresented = true
    }

    func preparePhotosImport(totalCount: Int) {
        let operationID = beginImportOperation()
        cancelIdlePreviewBuild(resetCursor: true)
        photosImportBatchCoordinator.begin(
            operationID: operationID,
            totalCount: totalCount,
            packageWasEmpty: collection.items.isEmpty,
            packageAvailable: portableLibrary != nil
        )
        guard portableLibrary != nil else {
            reportPortableLibraryUnavailable()
            return
        }
    }

    func insertPhotosImport(
        _ item: ImageCollection.PhotoImportItem, ordinal: Int
    ) -> PhotosImportInsertionOutcome {
        photosImportBatchCoordinator.insert(item, ordinal: ordinal)
    }

    /// Package Photos imports await the detached package worker before updating the presentation
    /// bridge. This keeps temp-file creation, copying, hashing, fsync, and commit off the main
    /// actor for every Photos import.
    func insertPhotosImportAsync(
        _ item: ImageCollection.PhotoImportItem, ordinal: Int
    ) async -> PhotosImportInsertionOutcome {
        await photosImportBatchCoordinator.insertAsync(item, ordinal: ordinal)
    }

    func isCurrentPhotosImportBatch(_ operationID: UUID) -> Bool {
        isCurrentImport(operationID)
    }

    func writePhotosImportItem(
        _ item: ImageCollection.PhotoImportItem, rebuildIndex: Bool
    ) throws -> PortablePackageImportResult {
        try libraryImportCoordinator.importData(
            item.data, name: item.name, rebuildIndex: rebuildIndex
        )
    }

    func writePhotosImportItemAsync(
        _ item: ImageCollection.PhotoImportItem, rebuildIndex: Bool
    ) async throws -> PortablePackageImportResult {
        let handle = try libraryImportCoordinator.startImportData(
            item.data, name: item.name, rebuildIndex: rebuildIndex
        )
        return try await handle.value()
    }

    func refreshPhotosImportCollection() throws {
        // Commit the coalesced package membership delta before the presentation bridge snapshots
        // the index generation.
        libraryImportCoordinator.finishImportBatch()
        try reloadPortableCollection()
    }

    func openPhotosImportAsset(_ assetID: PortablePhotoAssetID) {
        openPortableAsset(assetID)
    }

    func presentPhotosImportInspector() {
        // Keep the user's selected inspector tab unchanged.
        inspectorState.isPresented = true
    }

    func reportPhotosImportBatchError(_ message: String) {
        presentError(message)
    }

    func recordPhotosImportFailureDestination(name: String, ordinal: Int?, reason: String) {
        // Package failures are already represented by the coordinator's outcome summary.
        _ = (name, ordinal, reason)
    }

    func finishPhotosImportDestination(summary: ImportOutcomeSummary) {
        _ = summary
        photosImportBatchCoordinator.finish()
    }

    // MARK: - Removable media import

    var selectedRemovableMediaFiles: [MediaVolumeFile] {
        libraryMediaWorkflow.selectedRemovableMediaFiles
    }

    func refreshRemovableMedia() {
        libraryMediaWorkflow.refreshRemovableMedia()
    }

    func importFromRemovableMedia() {
        guard portableLibrary != nil else {
            reportPortableLibraryUnavailable()
            return
        }
        libraryMediaWorkflow.importFromRemovableMedia()
    }

    func openRemovableMedia(_ volume: MediaVolume) {
        guard portableLibrary != nil else {
            reportPortableLibraryUnavailable()
            return
        }
        libraryMediaWorkflow.openRemovableMedia(volume)
    }

    func toggleRemovableMediaSelection(_ file: MediaVolumeFile) {
        libraryMediaWorkflow.toggleRemovableMediaSelection(file)
    }

    func selectRemovableMediaRange(to file: MediaVolumeFile) {
        libraryMediaWorkflow.selectRemovableMediaRange(to: file)
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
        guard portableLibrary != nil else {
            reportPortableLibraryUnavailable()
            return
        }
        libraryMediaWorkflow.importSelectedRemovableMedia()
    }

    private func importRemovableMedia(_ request: RemovableMediaImportRequest) {
        packageSourceImports.importRemovableMedia(request)
        isRemovableMediaSelectorPresented = false
    }

    /// Choose a folder to import into the portable library, reveal the library browser, and open
    /// the first imported image.
    @discardableResult
    func chooseSourceFolder() -> Task<Void, Never> {
        Task { [weak self] in
            guard let self else { return }
            guard self.portableLibrary != nil else {
                self.reportPortableLibraryUnavailable()
                return
            }
            await self.libraryMediaWorkflow.chooseSourceFolder(
                startingAt: self.settings.defaultSourceFolderURL
            )
        }
    }

    /// Classify a dropped URL at the application boundary, then dispatch through the existing
    /// value-based open seams. Invalid or cancelled drops leave the current edit untouched.
    func handleDroppedURL(_ url: URL) {
        libraryMediaWorkflow.handleDroppedURL(url)
    }

    func handleDrop(_ payload: ImageDrop.Payload) {
        guard portableLibrary != nil else {
            reportPortableLibraryUnavailable()
            return
        }
        switch payload {
        case .urls(let urls):
            libraryMediaWorkflow.handleDroppedURLs(urls)
        case .image(let data, let name):
            openImage(data: data, name: name)
        case .promises(let receivers):
            packageSourceImports.importDroppedPromises(receivers)
        }
    }

    /// Import supported images from `url` into the package and open the first imported image.
    /// Shared by the menu/toolbar action and folder drops; the source folder is never persisted.
    @discardableResult
    func openSourceFolder(
        url: URL,
        access: SecurityScopedResourceAccess? = nil
    ) -> ImportOutcomeSummary? {
        cancelIdlePreviewBuild(resetCursor: true)
        return packageSourceImports.openSourceFolder(url: url, access: access)
    }

    /// Move between the two top-level workspaces. Entering Edit uses the collection's active
    /// item, so a grid selection is handed off deterministically and never relies on a stale source
    /// image. With no selection, Edit opens the first photo only when that Library setting is on.
    @discardableResult
    func navigate(to mode: NavigationState.Mode) -> Bool {
        cancelIdlePreviewBuild()
        switch mode {
        case .grid:
            if isCropToolActive { cancelCrop() }
            guard collection.isActive else { return false }
            previewAdmissionCoordinator.cancelAdjacentPreviewPrefetch()
            // Release the editor inspector before composing the Library viewport. If it closes
            // after the workspace changes, SwiftUI first lays the grid out beside the inspector
            // and then animates its width, rebuilding the grid rows during the return.
            inspectorState.isPresented = false
            navigation.move(to: .grid)
            collection.beginThumbnailDemand()
            scheduleIdlePreviewBuild()
            return true

        case .edit:
            if collection.isActive, collection.selectedItem == nil,
                settings.openFirstPhotoWhenEnteringEdit, !collection.items.isEmpty
            {
                selectCollectionImage(at: 0)
                openLibraryImageForEditing()
                return collection.selectedItem != nil
            }
            guard collection.isActive, collection.selectedItem != nil else {
                return sourceImage != nil && setEditMode()
            }
            navigation.move(to: .edit)
            openActiveCollectionImage(loadMode: false)
            scheduleIdlePreviewBuild()
            return true
        }
    }

    private func setEditMode() -> Bool {
        navigation.move(to: .edit)
        scheduleIdlePreviewBuild()
        return true
    }

    /// Refresh the package-backed library query after an external package change. The package is
    /// canonical, so this rebuilds the disposable index from membership first; it is also the
    /// manual recovery for a grid that disagrees with the package.
    func refreshSource() {
        previewAdmissionCoordinator.cancelAdjacentPreviewPrefetch()
        cancelIdlePreviewBuild(resetCursor: true)
        do {
            try libraryBrowsingCoordinator.rebuildPortableIndex()
            logFrameLookupSummaries([.gridOriginal, .gridEdited, .filmstrip, .launchHint])
        } catch {
            presentLibraryError("The library index could not be refreshed: \(error.localizedDescription)")
        }
    }

    /// Capture the current Library selection for a destructive confirmation. The focused item is
    /// included by `ImageCollection` even for a keyboard/menu invocation with no explicit set.
    func requestDeleteSelectedLibraryItems() {
        libraryBrowsingCoordinator.requestDeleteSelectedLibraryItems()
    }

    /// Confirm the previously captured target set. The actual work is asynchronous because edit
    /// records and analysis/mask caches are actor-isolated.
    func confirmDeleteSelectedLibraryItems() {
        libraryBrowsingCoordinator.confirmDeleteSelectedLibraryItems()
    }

    /// Delete the supplied Library targets. This is also the testable seam behind the confirmation
    /// UI: flush pending edits, clear durable derived data, move managed files to Trash, remove
    /// edit records, then commit the collection state. A per-item failure leaves that item alone.
    @discardableResult
    func deleteSelectedLibraryItems() async -> LibraryDeletionResult {
        await deleteLibraryItems(collection.deletionCandidates)
    }

    @discardableResult
    func deleteLibraryItems(
        _ candidates: [ImageCollection.DeletionCandidate]
    ) async -> LibraryDeletionResult {
        let outcome = await libraryDeletionCoordinator.deleteAndCleanUp(candidates)
        switch outcome.activePhoto {
        case .none: break
        case .openSelection: openActiveCollectionImage(loadMode: false)
        case .clearSource: clearActiveSourceAfterLibraryDeletion()
        }
        switch outcome.message {
        case .none: break
        case .status(let message): statusMessage = message
        case .error(let message): presentError(message)
        }
        return outcome.result
    }

    private func clearActiveSourceAfterLibraryDeletion() {
        loadRequestGeneration &+= 1
        sourceSession.cancel()
        previewAdmissionCoordinator.cancelAdjacentPreviewPrefetch()
        autoWorkflowCoordinator.invalidate { [weak self] state, progress in
            self?.publishAutoAdjustmentState(state, progress: progress)
        }
        documentRevision &+= 1
        previewPresentation.advanceDisplayRevision()
        cancelPendingPreviewDebounce()
        previewCoordinator.cancel()
        cancelWhiteBalanceSampling()
        sourceImage = nil
        imageSource = nil
        sourceURL = nil
        sourceName = ""
        sourceSize = .zero
        activeAssetID = nil
        activeSourceReference = nil
        previewPublicationCoordinator.resetForSource()
        editorDocument.clearActiveHistory()
        document = EditDocument()
        metadata = ImageMetadata()
        histogram = nil
        presentation.clear()
        previewSurface.clear()
        originalPreviewSurface.clear()
        inspectorState.isPresented = false
        statusMessage = "Open an image to get started"
        resetAutoAdjustmentForLifecycle()
    }

    func selectCollectionImage(
        at index: Int,
        modifiers: LibrarySelectionModel.Modifiers = []
    ) {
        guard collection.items.indices.contains(index) else { return }
        let selectionUptime = DispatchTime.now().uptimeNanoseconds
        if isCropToolActive { cancelCrop() }
        selectPortableItem(at: index, modifiers: modifiers)
        KromoraObservability.photoSwitchPhase("selectPortableItem", since: selectionUptime)
        let item = collection.items[index]

        if let url = item.url {
            // `selectPortableItem` is a no-op without an open package or a portable ID, so only
            // skip the focus step when it actually made this item the active selection.
            openImage(
                url: url, assetID: item.id, selectionUptime: selectionUptime,
                collectionAlreadySelected: collection.selection.activeID == item.id
            )
        } else if let data = item.imageData {
            load(
                name: item.displayName, url: nil, data: data, assetID: item.id,
                dataFingerprint: item.dataFingerprint,
                portableIdentity: item.asset.source.portableIdentity,
                presentationSelectionUptime: selectionUptime
            )
        }
        KromoraObservability.photoSwitchPhase("selectionSyncReturned", since: selectionUptime)
        // The active editor should receive this request, but constructing its persistence and
        // Look snapshot can be expensive. It is supporting work, so let the photo switch enqueue
        // source preparation first and admit the thumbnail after the selection event returns.
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, !self.isShuttingDown, self.activeAssetID == item.id else { return }
            self.requestEditedThumbnail(for: item.id, priority: .activeEditor)
        }
    }

    /// Compatibility entry point for callers that only need Command-click semantics.
    func selectCollectionImage(at index: Int, additive: Bool) {
        selectCollectionImage(at: index, modifiers: additive ? [.command] : [])
    }

    // MARK: - Edit-aware thumbnails

    private func requestEditedThumbnail(
        for assetID: PhotoAssetID,
        priority: ImageWorkScheduler.Priority,
        force: Bool = false
    ) {
        editedThumbnailCoordinator.request(
            for: assetID, priority: priority, force: force,
            surface: priority == .adjacentFilmstrip ? .filmstrip : .gridEdited
        )
    }

    private func scheduleEditedThumbnailAfterSettle(
        for assetID: PhotoAssetID, priority: ImageWorkScheduler.Priority
    ) {
        editedThumbnailCoordinator.scheduleAfterSettle(for: assetID, priority: priority)
    }

    private func cancelEditedThumbnailDebounce(for assetID: PhotoAssetID?) {
        editedThumbnailCoordinator.cancelDebounce(for: assetID)
    }

    // MARK: - Copy and paste

    func presentSelectiveCopyDialog() { editClipboardWorkflow.presentSelectiveCopyDialog() }
    func confirmSelectiveCopy() { editClipboardWorkflow.confirmSelectiveCopy() }
    func cancelSelectiveCopy() { editClipboardWorkflow.cancelSelectiveCopy() }
    func copyAllEdits() { editClipboardWorkflow.copyAllEdits() }
    func pasteEdits() { editClipboardWorkflow.pasteEdits() }

    /// Select a grid cell without leaving the grid. This is what makes a multi-selection useful:
    /// Command-click and Shift-click change the batch while the active photo remains explicit.
    func selectLibraryItem(
        at index: Int,
        modifiers: LibrarySelectionModel.Modifiers = []
    ) {
        cancelIdlePreviewBuild(resetCursor: true)
        libraryBrowsingCoordinator.selectLibraryItem(at: index, modifiers: modifiers)
        updatePinnedFrameAssets(visible: Array(collection.visibleEditedThumbnailAssetIDs))
        scheduleIdlePreviewBuild()
    }

    /// Apply a culling flag to the focused library asset. Pick/reject use the rapid-cull workflow
    /// and move to the next visible asset; rating changes stay on the current photo.
    @discardableResult
    func setFocusedFlag(_ flag: PhotoFlag, advance: Bool = false) -> Bool {
        libraryBrowsingCoordinator.setFocusedFlag(flag, advance: advance)
    }

    @discardableResult
    func setFocusedRating(_ rating: Int) -> Bool {
        libraryBrowsingCoordinator.setFocusedRating(rating)
    }

    /// Apply a culling key to every selected photo, in the grid or the Edit filmstrip, or to the
    /// active photo when nothing else is selected. Marking never moves the selection: the arrow
    /// keys stay free for navigating, and a multi-selection stays selected for the next key.
    @discardableResult
    func perform(_ command: LibraryCullingCommand) -> Bool {
        switch command {
        case .pick: setFocusedFlag(.pick)
        case .reject: setFocusedFlag(.reject)
        case .clearFlag: setFocusedFlag(.none)
        case .clearRating: setFocusedRating(0)
        case .rating(let rating): setFocusedRating(rating)
        }
    }

    @discardableResult
    func undoCullingChange() -> Bool {
        libraryBrowsingCoordinator.undoCullingChange()
    }

    /// Enter the editor for the grid's active photo. Thumbnail availability is not a prerequisite;
    /// `openImage` starts the existing asynchronous RAW load immediately.
    func openActiveCollectionImage() {
        openActiveCollectionImage(loadMode: true)
    }

    /// Enter Edit from a Library double-click with the editor chrome in its expected presentation
    /// state. The source browser is an explicit Edit control, so it must not leak into this
    /// transition from the library browser; the inspector is the actionable editor surface
    /// for the newly opened photo.
    func openLibraryImageForEditing() {
        guard collection.selectedItem != nil else {
            presentError("Select a photo to open in Edit.")
            return
        }
        isSourceBrowserPresented = false
        inspectorState.isPresented = true
        openActiveCollectionImage()
    }

    /// A pointer open targets the clicked asset, even if selection changed during an import or
    /// the first click toggled it out of a Command-click batch.
    func openLibraryImageForEditing(assetID: PhotoAssetID) {
        guard let index = collection.items.firstIndex(where: { $0.id == assetID }),
            collection.filter.matches(
                flag: collection.items[index].asset.flag, rating: collection.items[index].asset.rating
            )
        else {
            presentError("This photo is no longer in the Library view. Select it again to open it.")
            return
        }
        if collection.isPortableWindowed {
            selectPortableItem(at: index)
        }
        if collection.selection.activeID != assetID {
            collection.select(at: index)
        }
        openLibraryImageForEditing()
    }

    private func openActiveCollectionImage(loadMode: Bool) {
        guard let item = collection.selectedItem else {
            presentError("Select a photo to open in Edit.")
            return
        }
        if loadMode { navigation.move(to: .edit) }

        // The library selection is the source of truth for the edit handoff. When returning from
        // the grid, the active item is often already prepared because the editor was left visible
        // behind the library. Reusing that source avoids clearing a valid preview (and the canvas
        // presentation state) just to revisit the same photo. If the surface was recreated or a
        // preview is still pending, explicitly request the visible render again.
        if activeAssetID == item.id {
            if imageSource != nil, sourceImage != nil {
                if previewSurface.image == nil {
                    presentation.markPreviewLoading()
                    schedulePreview()
                } else if inspectorState.isPresented, !isCropToolActive {
                    // Library selection can settle and present this frame while the inspector
                    // is hidden. Re-admit that retained frame after the explicit Library → Edit
                    // transition, since its original presentation callback correctly skipped
                    // histogram work while the inspector was closed.
                    updateHistogram(
                        for: previewPublicationCoordinator.lastPublishedVisibleRequest,
                        presentedImage: previewSurface.image
                    )
                }
                return
            }
            // A source preparation can be non-cancellable. Let the in-flight, revision-checked
            // request finish instead of enqueueing a duplicate while the user is navigating.
            if sourceSession.isBusy {
                presentation.markPreviewLoading()
                statusMessage = "Loading \(item.displayName)..."
                return
            }
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
        } else if let portableLibrary {
            do {
                let url = try portableLibrary.resolveEmbeddedSourceURL(
                    for: item.asset.source.portableIdentity.assetID
                )
                openImage(url: url, assetID: item.id)
            } catch {
                presentError("Could not open \(item.displayName): \(error.localizedDescription)")
            }
        } else {
            presentError("Could not open \(item.displayName): the original photo is unavailable.")
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
        if collection.portableHasMorePages,
            collection.selectedIndex >= collection.items.count - 1
        {
            loadMorePortableIfNeeded(currentIndex: collection.items.count - 1)
        }
        let prev = collection.selectedIndex
        collection.selectNext()
        if collection.selectedIndex != prev {
            selectCollectionImage(at: collection.selectedIndex)
        }
    }

    // MARK: - Look selection

    func selectLook(_ look: CubeLUT?) {
        if let look, look.lutID.isDerived { lookSelection.register(look) }
        endUndoGrouping()
        updateDocument { $0.lut.lutID = look?.lutID }
        refreshLUTResolutionStatus()
    }

    /// Select a Look by its stable document ID. The browser binds to IDs rather than resolved LUT
    /// values so the explicit None row and a missing file remain distinct selections.
    func selectLook(id: LUTID?) {
        switch lookSelection.selection(for: id) {
        case .clear:
            selectLook(nil)
        case .select(let look):
            selectLook(look)
        case .loading(let message):
            statusMessage = message
        case .unresolved:
            // Keep an unresolved persisted ID intact, but make an attempted selection
            // observable and recoverable through the inspector's clear action.
            refreshLUTResolutionStatus()
        }
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

    /// Persist a deterministic automatic source choice only if the spot and open source still match
    /// the request. A manual source always wins over a late picker result.
    func pickRetouchSource(spotID: UUID, rank: Int = 0) async {
        guard let source = imageSource,
              let spot = document.retouch.spots.first(where: { $0.id == spotID }) else { return }
        if case .manual? = spot.source { return }
        let sourceFingerprint = source.cacheFingerprint
        let originalRegion = spot.region
        let settings = document.retouch
        guard let picked = await engine.pickRetouchSource(
            source: source, settings: settings, spotID: spotID, rank: rank
        ), imageSource?.cacheFingerprint == sourceFingerprint,
           let current = document.retouch.spots.first(where: { $0.id == spotID }),
           current.region == originalRegion,
           current.source == nil || isAutomaticRetouchSource(current.source) else { return }
        updateDocument { document in
            guard let index = document.retouch.spots.firstIndex(where: { $0.id == spotID }),
                  document.retouch.spots[index].region == originalRegion,
                  document.retouch.spots[index].source == nil || isAutomaticRetouchSource(document.retouch.spots[index].source) else { return }
            document.retouch.spots[index].source = picked
        }
    }

    func toggleRetouchVisualization() { retouchWorkflow.toggleVisualization() }
    func setRetouchVisualizationThreshold(_ threshold: Double) { retouchWorkflow.setVisualizationThreshold(threshold) }
    func detectRetouchDust() { retouchWorkflow.detectDust() }

    var retouchAnalysisSource: ImageSource? { imageSource }
    func retouchAnalysisProxy(source: ImageSource) async -> RetouchAnalysisProxy? {
        await engine.retouchAnalysisProxy(source: source)
    }
    func publishRetouchStatus(_ message: String) { statusMessage = message }

    private func isAutomaticRetouchSource(_ source: RetouchSource?) -> Bool {
        if case .auto? = source { return true }
        return false
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
        if !isPreviewInteractionActive {
            previewPresentation.advanceDisplayRevision()
        }
        cancelHistogram(clear: false, pump: false)
        editorDocument.recordChange(from: document, to: updated)
        document = updated
        if let activeAssetID {
            collection.setPresentedCrop(document.crop, rotation: document.rotation, for: activeAssetID)
        }
        if rotationChanged {
            sourceSize = document.rotation.orientedExtent(imageSource?.nativeExtent ?? sourceSize)
        }
        if !document.hasVisibleLookEdits { isShowingOriginal = false }
        refreshLUTResolutionStatus()
        saveActiveDocument()
        documentRevision &+= 1
        // Fence any thumbnail already admitted for the active photo immediately. The trailing
        // replacement request is intentionally debounced, but an older renderer may finish during
        // that quiet period and must not publish its captured document.
        invalidateEditedThumbnailWork(for: activeAssetID)
        // Look edits and RAW Temperature/Tint leave the baseline unchanged, so an in-flight
        // baseline remains useful. Other RAW develop edits change the explicit before-image and
        // must invalidate that work; it will be queued again after the new visible result publishes.
        if comparisonChanged {
            comparisonBaselineDocument = updated.comparisonBaseline
            previewPresentation.advanceComparisonRevision()
            previewAdmissionCoordinator.resetComparisonPreviewAdmission()
            cancelComparisonPreview(pump: false)
            originalPreviewSurface.clear()
        }
        // OR'd in rather than assigned: a call earlier in a coalesced burst may have changed a
        // comparison-frame stage even though this call did not, and only the last call's task
        // survives to fire (see the publication coordinator's pending develop-change flag).
        previewPublicationCoordinator.noteDevelopChange(comparisonChanged)

        guard debounced else {
            previewAdmissionCoordinator.cancelPreviewDebounce()
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

    /// Redo only the work whose Look resolution a scan changed.
    ///
    /// Preview and thumbnail identities carry the Look's content (`LookSignature`), so a stale
    /// result can never be served for changed bytes. What a scan owes is *replacement*: the pixels
    /// already on screen were made with a Look that is now different, missing, or newly resolvable.
    /// That is limited to the active document's Look and Looks a published edited thumbnail
    /// references. A byte-identical rescan, or a change to a Look nothing references, updates the
    /// browser (already done by the library) and does no engine or image work.
    private func applyLookLibraryDelta(_ delta: LookLibraryDelta) {
        guard !delta.isEmpty else { return }
        let activeLookID = sourceImage != nil ? document.lut.lutID : nil
        var referenced = editedThumbnailCoordinator.referencedLookIDs
        if let activeLookID { referenced.insert(activeLookID) }
        let affected = delta.affected.intersection(referenced)
        guard !affected.isEmpty else { return }

        let refreshesCanvas = activeLookID.map(affected.contains) ?? false
        let engine = self.engine
        lutCacheInvalidationTask = Task { [weak self, engine] in
            await engine.invalidateLUTCache(ids: affected)
            guard let self, !self.isShuttingDown else { return }
            if refreshesCanvas, self.sourceImage != nil { self.schedulePreview() }
            self.editedThumbnailCoordinator.refreshMaterializedThumbnails(affecting: affected)
        }
    }

    private func resolvedLUT(_ id: LUTID?) -> CubeLUT? { lookSelection.resolve(id) }

    private func refreshLUTResolutionStatus() {
        switch lookSelection.refreshStatus(for: document.lut.lutID) {
        case .unchanged:
            break
        case .cleared:
            lutResolutionStatus = nil
        case .missing(let message):
            lutResolutionStatus = message
            statusMessage = message
        }
    }

    func selectPreviousLook() {
        applyLookNavigation(.previous)
    }

    func selectNextLook() {
        applyLookNavigation(.next)
    }

    private func applyLookNavigation(_ direction: LookNavigation.Direction) {
        switch lookSelection.navigate(direction, from: selectedLook, currentID: selectedLookID) {
        case .select(let look): selectLook(look)
        case .clear: selectLook(nil)
        case .none: break
        }
    }

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
        presentation.markPreviewLoading()
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
        if !isPreviewInteractionActive {
            previewPresentation.advanceDisplayRevision()
        }
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

    // MARK: - Preview admission façade

    /// Shared request seam retained for the render-planning tests. Admission policy lives in
    /// `PreviewAdmissionCoordinator`; resolution hysteresis and cache identity remain in presentation.
    func resolutionPlan(
        for document: EditDocument,
        nativeExtent: CGSize,
        viewportSize: CGSize,
        surface: ResolutionPlannerSurface
    ) -> ResolutionPlan {
        previewPresentation.plan(
            for: document, nativeExtent: nativeExtent, viewportSize: viewportSize,
            surface: surface, navigation: canvasState.navigation
        )
    }

    private func resetResolutionPlanners() { previewPresentation.resetPlanners() }

    private var displayRequest: (document: EditDocument, lut: CubeLUT?) {
        previewAdmissionCoordinator.displayRequest
    }

    private func schedulePreview() { previewAdmissionCoordinator.schedulePreview() }
    private func scheduleCropEntryPreview() { previewAdmissionCoordinator.scheduleCropEntryPreview() }
    private func scheduleCorrectivePreview() { previewAdmissionCoordinator.scheduleCorrectivePreview() }
    private func scheduleInteractivePreview() { previewAdmissionCoordinator.scheduleInteractivePreview() }
    func updateCanvasBackingSize(_ size: CGSize) -> CanvasNavigation {
        previewAdmissionCoordinator.updateViewportBackingSize(size)
        canvasWorkflow.updateCanvasBackingSize(size)
        return canvasState.navigation
    }
    func updatePreviewBackingSize(_ size: CGSize) {
        previewAdmissionCoordinator.updatePreviewBackingSize(size)
    }
    private func scheduleSettledPreviewAfterDebounce() {
        previewAdmissionCoordinator.scheduleSettledPreviewAfterDebounce()
        logFrameLookupSummaries([.editPreview])
    }

    private func logFrameLookupSummaries(_ surfaces: [FrameLookupSurface]) {
        let ledger = frameLookupLedger
        Task {
            for surface in surfaces { await ledger.logSummary(for: surface) }
        }
    }

    func beginPreviewInteraction() {
        cancelIdlePreviewBuild()
        beginUndoGrouping()
        editedThumbnailCoordinator.cancelActiveRequest(for: activeAssetID)
        previewAdmissionCoordinator.beginInteraction()
    }

    func endPreviewInteraction() {
        previewAdmissionCoordinator.endInteraction()
        endUndoGrouping()
        editedThumbnailCoordinator.admitDeferredDemands()
        if let assetID = editedThumbnailCoordinator.pendingAssetID {
            scheduleEditedThumbnailAfterSettle(for: assetID, priority: .activeEditor)
        }
    }

    // MARK: - Crop and rotation workflow façade

    func beginCrop() { retouchWorkflow.setArmed(false); canvasWorkflow.beginCrop() }
    func toggleCropTool() { retouchWorkflow.setArmed(false); canvasWorkflow.toggleCropTool() }
    func updateCropDraft(_ normalizedRect: CGRect) {
        canvasWorkflow.updateCropDraft(normalizedRect)
    }

    func selectCropAspectRatio(
        _ aspectRatio: CropAspectRatio,
        orientation: CropAspectRatioOrientation = .automatic
    ) {
        canvasWorkflow.selectCropAspectRatio(aspectRatio, orientation: orientation)
    }

    func setCropStraightenAngle(_ angle: Double) { canvasWorkflow.setCropStraightenAngle(angle) }
    func setCropVerticalPerspective(_ value: Double) {
        canvasWorkflow.setCropVerticalPerspective(value)
    }
    func setCropHorizontalPerspective(_ value: Double) {
        canvasWorkflow.setCropHorizontalPerspective(value)
    }
    func toggleCropFlip(horizontal: Bool) { canvasWorkflow.toggleCropFlip(horizontal: horizontal) }
    func commitCrop() { canvasWorkflow.commitCrop() }
    func cancelCrop() { canvasWorkflow.cancelCrop() }
    func resetCrop() { canvasWorkflow.resetCrop() }
    func rotateClockwise() { canvasWorkflow.rotateClockwise() }
    func rotateCounterClockwise() { canvasWorkflow.rotateCounterClockwise() }
    func resetRotation() { canvasWorkflow.resetRotation() }

    // MARK: - Canvas navigation façade

    func fitCanvas() { canvasWorkflow.fitCanvas() }
    func fillCanvas() { canvasWorkflow.fillCanvas() }
    func resetCanvas() { canvasWorkflow.resetCanvas() }
    func toggleCanvasZoom() { canvasWorkflow.toggleCanvasZoom() }
    func toggleCanvasZoom(at viewportPoint: CGPoint, viewportSize: CGSize) {
        canvasWorkflow.toggleCanvasZoom(at: viewportPoint, viewportSize: viewportSize)
    }
    func setCanvasZoom(_ value: CGFloat) { canvasWorkflow.setCanvasZoom(value) }
    func zoomCanvas(by factor: CGFloat) { canvasWorkflow.zoomCanvas(by: factor) }
    func zoomCanvas(by factor: CGFloat, at viewportPoint: CGPoint, viewportSize: CGSize) {
        canvasWorkflow.zoomCanvas(by: factor, at: viewportPoint, viewportSize: viewportSize)
    }

    /// Pinch-zoom is presentation-only, unlike a slider drag, so this deliberately does not call
    /// `beginPreviewInteraction`/`endPreviewInteraction`: those also open an undo grouping and
    /// queue a document save, which would flash a "saving" status and grow the undo stack for a
    /// gesture that never touches `document`.
    func beginCanvasInteraction() {
        previewPresentation.advanceDisplayRevision()
        isPreviewInteractionActive = true
        previewCoordinator.beginInteraction()
    }

    func endCanvasInteraction() {
        isPreviewInteractionActive = false
        previewCoordinator.endInteraction()
        editedThumbnailCoordinator.admitDeferredDemands()
    }

    /// Pan is presentation-only and is coordinated with the current rendered image extent.
    func panCanvas(by delta: CGSize, viewportSize: CGSize) {
        canvasWorkflow.panCanvas(by: delta, viewportSize: viewportSize)
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

    func refreshDurableEditHistory() { editHistory.refresh() }

    /// Navigate to a durable edit state without creating a new revision.
    func restoreEditRevision(_ revision: UInt64) { editHistory.restore(revision) }

    func saveEditSnapshot(named name: String) { editHistory.saveSnapshot(named: name) }

    private func adoptRestoredEditRevision(_ restored: EditDocument, priorDocuments: [EditDocument]) {
        if let activeAssetID {
            editorDocument.adoptHistoryPosition(restored, priorDocuments: priorDocuments, for: activeAssetID)
            editorDocument.activate(session: editorDocument.session(for: activeAssetID))
        }
        applyHistoryDocument(restored, persist: false)
    }

    var virtualCopySourceDescription: String? { virtualCopyMetadata?.sourceDescription }

    var canCreateVirtualCopy: Bool { virtualCopyMetadata?.canCreate ?? false }

    var isCreatingVirtualCopy: Bool { editHistory.isCreatingVirtualCopy }

    func createVirtualCopy() {
        guard let portableLibrary, let reference = activeSourceReference,
              (try? portableLibrary.package.readAssetRecord(for: reference.portableAssetID)) != nil else {
            statusMessage = "Virtual copies are available for photos in a Kromora library"
            return
        }
        editHistory.createVirtualCopy(
            of: reference,
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
                self.openPortableAsset(copy.assetID)
            }
        )
    }

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
        if isCropToolActive { cancelCrop() }
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
        previewAdmissionCoordinator.resetComparisonPreviewAdmission()
        cancelComparisonPreview(pump: false)
        originalPreviewSurface.clear()
        previewPublicationCoordinator.noteDevelopChange()
    }

    /// Reset the currently visible inspector stage without crossing into another stage. The
    /// toolbar uses this alongside each panel's local reset links so the scope is explicit before
    /// the action is taken; every branch still records through the stage's existing undo path.
    func resetInspectorSection() {
        if isCropToolActive {
            resetCrop()
            return
        }
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
        case .retouch:
            updateDocument { $0.retouch = .neutral }
        }
    }

    private func applyHistoryDocument(_ restored: EditDocument, persist: Bool = true) {
        let comparisonChanged = ComparisonFramePolicy.changesBaseline(
            from: document, to: restored
        )
        previewPresentation.advanceDisplayRevision()
        cancelHistogram(clear: false, pump: false)
        document = restored
        if let activeAssetID {
            collection.setPresentedCrop(document.crop, rotation: document.rotation, for: activeAssetID)
        }
        sourceSize = restored.rotation.orientedExtent(imageSource?.nativeExtent ?? sourceSize)
        let cropToolRemainsActive = canvasState.isCropToolActive
        if cropToolRemainsActive {
            canvasWorkflow.reseedCrop(using: restored.crop, sourceSize: sourceSize)
        }
        if !document.hasVisibleLookEdits {
            // Space is a transient single-view state. Undoing/redoing to identity must not leave
            // it armed when the before/after surface no longer exists.
            isShowingOriginal = false
        }
        if comparisonChanged {
            comparisonBaselineDocument = restored.comparisonBaseline
            previewAdmissionCoordinator.resetComparisonPreviewAdmission()
        }
        refreshLUTResolutionStatus()
        if persist { saveActiveDocument(force: true) }
        documentRevision &+= 1
        if let activeAssetID {
            scheduleEditedThumbnailAfterSettle(for: activeAssetID, priority: .activeEditor)
        }
        if comparisonChanged {
            previewPresentation.advanceComparisonRevision()
            previewAdmissionCoordinator.resetComparisonPreviewAdmission()
            cancelComparisonPreview(pump: false)
            originalPreviewSurface.clear()
        }
        previewPublicationCoordinator.noteDevelopChange(comparisonChanged)
        restoreMaskSelection()
        if cropToolRemainsActive {
            scheduleCropEntryPreview()
        } else {
            schedulePreview()
        }
    }

    /// Rasterize the comparison baseline for the side-by-side left panel. Only needs to re-run when
    /// the image or the develop settings change — not when the look does. A mode-entry request may
    /// start from the current preview candidate before its drawable confirmation arrives; normal
    /// supporting work remains gated on that confirmation below.
    private func scheduleOriginalPreview(
        allowHiddenPreparation: Bool = false,
        allowBeforePresentationConfirmation: Bool = false
    ) {
        previewAdmissionCoordinator.scheduleOriginalPreview(
            allowHiddenPreparation: allowHiddenPreparation,
            allowBeforePresentationConfirmation: allowBeforePresentationConfirmation
        )
    }

    private func comparisonPreviewDidFail(
        sourceReference: EditSourceReference?, sourceRevision: UInt64,
        comparisonRevision: UInt64
    ) {
        previewAdmissionCoordinator.comparisonPreviewDidFail(
            sourceReference: sourceReference, sourceRevision: sourceRevision,
            comparisonRevision: comparisonRevision
        )
    }

    private func cancelComparisonPreview(pump: Bool = true) {
        previewAdmissionCoordinator.cancelComparisonPreview(pump: pump)
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
        // Split view is a presentation choice, not an edit-state affordance. An identity document
        // still has valid source pixels, so entering it should render that same source into both
        // panes; an edited document continues through the baseline comparison path below.
        guard sourceImage != nil else { return false }
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
            previewAdmissionCoordinator.resetComparisonPreviewAdmission()
            originalPreviewSurface.clear()
        }
        return true
    }

    // MARK: - Inspector histogram

    func toggleInspector() {
        guard sourceImage != nil else {
            statusMessage = "Open an image first"
            return
        }
        guard !isCropToolActive else { return }
        isInspectorPresented.toggle()
    }

    /// Recompute the histogram for the currently displayed image. No-op unless the inspector is
    /// open. Cancellable, so dragging the intensity slider stays smooth.
    ///
    /// The histogram consumes the completed image from the settled presentation. This keeps it
    /// aligned with the pixels the user received and avoids evaluating the preview graph again.
    /// The source/document overload remains available for standalone engine analysis, but it is
    /// intentionally not used for the visible inspector path.
    private func updateHistogram(
        for displayedRequest: RenderRequest? = nil,
        presentedImage: CIImage? = nil
    ) {
        previewAdmissionCoordinator.updateHistogram(
            for: displayedRequest, presentedImage: presentedImage
        )
    }

    /// Cancel pending or in-flight histogram work. The revision check in the task remains necessary:
    /// a renderer may be finishing a non-cancellable Core Image operation after its task is canceled.
    private func cancelHistogram(clear: Bool, pump: Bool = true) {
        previewAdmissionCoordinator.cancelHistogram(clear: clear, pump: pump)
    }

    /// Inspector-presentation gate for histogram work (KRMA-521). Called synchronously when
    /// inspector visibility changes so no Task is spawned per presentation change and the
    /// broad AppViewModel publisher is never involved.
    private func refreshHistogramGate() {
        guard !isShuttingDown else { return }
        if inspectorState.isPresented, !isCropToolActive {
            updateHistogram()
        } else {
            cancelHistogram(clear: true)
        }
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

    typealias ShareDialogMode = ExportWorkflowCoordinator.ShareDialogMode

    static func shareDialogMode(for selectionCount: Int) -> ShareDialogMode {
        ExportWorkflowCoordinator.shareDialogMode(for: selectionCount)
    }

    func shareDialog() { exportWorkflow.shareDialog() }
    func exportDialog() { exportWorkflow.exportDialog() }
    func editInExternalEditor() { exportWorkflow.editInExternalEditor() }
    func exportOriginalWithSettings() { exportWorkflow.exportOriginalWithSettings() }
    func batchExportDialog() { exportWorkflow.batchExportDialog() }
    func exportSelectedDialog() { exportWorkflow.exportSelectedDialog() }

    /// What ⌘S would export, without running a panel. Internal for headless assertions.
    var exportRequest: ExportWorkflowCoordinator.SingleRequest? { exportSingleRequest }

    /// What Export All would write, without running a panel.
    var batchExportRequest: ExportWorkflowCoordinator.BatchRequest {
        makeBatchExportRequest(from: collection.items)
    }

    /// The panel-free request used by Export Originals; never widened to the whole collection.
    var selectedBatchExportRequest: ExportWorkflowCoordinator.BatchRequest {
        makeBatchExportRequest(from: collection.selectedItems)
    }

    var selectedExportRequest: ExportWorkflowCoordinator.BatchRequest { selectedBatchExportRequest }

    var exportSingleRequest: ExportSingleRequest? {
        guard let imageSource else { return nil }
        // `sourceURL` is the managed copy for one-off opens and may carry Kromora's internal
        // de-duplication prefix. The user-facing name is retained separately in `sourceName`.
        let base =
            sourceName.isEmpty
            ? (sourceURL?.deletingPathExtension().lastPathComponent ?? "image")
            : URL(fileURLWithPath: sourceName).deletingPathExtension().lastPathComponent
        return ExportWorkflowCoordinator.SingleRequest(
            source: imageSource,
            document: document,
            lut: selectedLook,
            baseName: ExportCoordinator.exportBaseName(source: base, lut: selectedLook)
        )
    }

    private func makeBatchExportRequest(
        from sourceItems: [ImageCollection.Item]
    ) -> ExportWorkflowCoordinator.BatchRequest {
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
        return ExportWorkflowCoordinator.BatchRequest(items: items, document: document, lut: selectedLook)
    }

    // MARK: - Recipe extractor

    func presentRecipeExtractor() {
        derive.present()
    }

    func deriveRecipe(rawURL: URL, jpgURL: URL) {
        derive.derive(rawURL: rawURL, jpgURL: jpgURL)
    }

    @discardableResult
    func saveDerivedLUT() -> Task<Void, Never> {
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

    @discardableResult
    func saveLook() -> Task<Void, Never> {
        lookSave.saveDialog()
    }

    // MARK: - Look folder

    @discardableResult
    func chooseLookFolder() -> Task<Void, Never> { lookSheets.chooseFolder() }

    /// Import external `.cube`/`.look` files; the library owns parsing, access, and persistence.
    @discardableResult
    func chooseLookFile() -> Task<Void, Never> { lookSheets.chooseFiles() }

    /// Testable/non-panel seam for importing a file selected by another UI surface.
    func importLook(from url: URL) {
        library.importLUT(from: url)
    }

    /// Re-read configured and imported Look files. This is also the explicit user action for an
    /// external editor that replaced a file in place.
    func refreshLooks() {
        library.refresh()
    }

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

    @discardableResult
    private func requestPersistenceFlush() -> Task<PersistenceFlushResult, Never> {
        let previous = pendingPersistenceFlush
        let barrier = Task { [persistence] in
            _ = await previous?.value
            return await persistence.flush()
        }
        pendingPersistenceFlush = barrier
        return barrier
    }

    /// Wait for queued edit snapshots and settled presentation-frame writes before clean exit.
    public func flushPendingWrites() async -> PersistenceFlushResult {
        async let edits = persistence.flush()
        async let frameStores: Void = flushPendingFrameStores()
        let result = await edits
        await frameStores
        await portableLibrary?.flushPendingLibraryState()
        return result
    }

    /// Flush both rebuildable frame stores concurrently. Their own write failures are best effort
    /// and never change the result used by the edit-save prompt.
    private func flushPendingFrameStores() async {
        await frameStoreFlushOperations.flush()
    }

    private var frameStoreFlushOperations: FrameStoreFlushOperations {
        frameStoreFlushOperationsForTesting ?? FrameStoreFlushOperations(
            flushThumbnails: { [thumbnailFrameStore] in
                await thumbnailFrameStore.flush()
            },
            flushPreviews: { [previewPresentation] in
                await previewPresentation.flushPendingWrites()
            }
        )
    }

    /// A resign-active notification is only an opportunity to reduce the loss window. Keep it
    /// asynchronous so foreground editing never waits for disposable cache I/O.
    private func requestBestEffortFrameStoreFlush() {
        guard !isShuttingDown, bestEffortFrameStoreFlushTask == nil else { return }
        let operations = frameStoreFlushOperations
        bestEffortFrameStoreFlushTask = Task { @MainActor [weak self] in
            await operations.flush()
            self?.bestEffortFrameStoreFlushTask = nil
        }
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
    public func shutdown() async {
        guard !isShuttingDown else { return }
        isShuttingDown = true
        // Before anything else: an open still in flight must finish unwinding (binding is refused
        // once `isShuttingDown` is set, so it releases its lease) before the lease owner is torn down.
        await libraryOpen.cancelAndWait()
        presentation.shutDown()

        // Invalidate every generation before awaiting anything. A renderer or framework call may
        // only observe cancellation when it returns, but it can no longer publish into this model.
        sourceSession.cancel()
        editHistory.beginShutdown()
        loadRequestGeneration &+= 1
        let materializationTasks = Array(placeholderMaterializationTasks.values)
        for task in materializationTasks { task.cancel() }
        let shutdownStore = editStore
        let embeddedLookTask = await shutdownStore.cancelEmbeddedLookLoading()
        await embeddedLookTask?.value
        await virtualCopyMetadata?.shutdown()
        await retouchWorkflow.shutdown()
        previewAdmissionCoordinator.cancelAdjacentPreviewPrefetch()
        autoWorkflowCoordinator.invalidate { [weak self] state, progress in
            self?.publishAutoAdjustmentState(state, progress: progress)
        }
        documentRevision &+= 1
        previewPresentation.resetForSource()
        previewAdmissionCoordinator.cancelPreviewDebounce()
        previewAdmissionCoordinator.cancelComparisonRetry()

        // Disconnect callbacks first so a child that finishes while shutdown is re-entrant cannot
        // schedule new work or publish into the model.
        previewCoordinator.onPublication = nil
        previewCoordinator.onFailure = nil
        library.onScanned = nil
        library.onImported = nil
        library.onImportError = nil
        export.onStatus = nil
        export.onError = nil
        export.onExportCompleted = nil
        export.onActivityChanged = nil
        derive.onStatus = nil
        derive.onError = nil
        derive.onDerived = nil
        derive.onSaved = nil
        lookSave.onStatus = nil
        lookSave.onError = nil
        lookSave.onSaved = nil
        persistence.onStatusChange = nil
        persistence.onFailure = nil
        persistence.onDurableWrite = nil
        photosImportReview.shutdown()
        photosImportCoordinator.onStatus = nil
        photosImportCoordinator.destination = nil
        libraryMediaWorkflow.onStatus = nil
        libraryMediaWorkflow.onError = nil
        libraryMediaWorkflow.onImageURL = nil
        libraryMediaWorkflow.onImageURLs = nil
        libraryMediaWorkflow.onImportRequest = nil
        applicationShell.onMediaChanged = nil
        applicationShell.onApplicationActivated = nil
        applicationShell.onApplicationDeactivated = nil
        cancellables.removeAll()
        await applicationShell.shutdown()

        await libraryBrowsingCoordinator.shutdown()

        // Collection shutdown ends its discovery stream before awaiting the consumer. This also
        // prevents a late scan batch from admitting another thumbnail job.
        await collection.shutdown()

        await editedThumbnailCoordinator.shutdown()
        await idleFrameWarmerCoordinator.shutdown()
        await thumbnailFrameStore.shutdown()
        previewAdmissionCoordinator.shutdown()
        cancelIdlePreviewBuild(resetCursor: true)
        let tasks: [Task<Void, Never>?] =
            [
                lutCacheInvalidationTask,
                semanticCoordinatorInstallTask,
            ]
        for task in tasks { task?.cancel() }
        lutCacheInvalidationTask = nil
        semanticCoordinatorInstallTask = nil
        let frameStoreFlushTask = bestEffortFrameStoreFlushTask
        bestEffortFrameStoreFlushTask = nil
        await frameStoreFlushTask?.value
        await maskingWorkflow.shutdown()
        await libraryMediaWorkflow.shutdown()
        packageSourceImports.shutdown()
        await libraryImportCoordinator.shutdown()
        await sourceSession.shutdown()
        // Drain placeholder resolution (cancellation-oblivious worker I/O included) before the
        // package scheduler and writer lease are torn down.
        for task in materializationTasks { await task.value }
        // Accepted snapshot/restore/copy writes settle while persistence and the lease are live.
        await editHistory.shutdown()

        await library.shutdown()
        await export.shutdown()
        canvasWorkflow.shutdown()
        await photosImportCoordinator.shutdown()
        photosImportBatchCoordinator.shutdown()
        await derive.shutdown()
        await lookSave.shutdown()
        await photoAnalysisCoordinator.shutdown()
        await previewPresentation.shutdown()
        await previewCoordinator.shutdown()
        await lookPreviewCoordinator.shutdown()
        await workScheduler.cancelAllAndWait()
        // The scheduler barrier comes before the session releases its writer lease. This keeps a
        // queued import/maintenance operation from starting against a newly opened package.
        await portableLibrary?.shutdown()
        for task in tasks {
            if let task { await task.value }
        }
        await persistence.discard()
    }
}

extension AppViewModel: CanvasWorkflowDestination {
    var canvasWorkflowHasSource: Bool { sourceImage != nil }
    var canvasWorkflowDocument: EditDocument { document }
    var canvasWorkflowSourceSize: CGSize { sourceSize }
    var canvasWorkflowHasCropAdjustments: Bool { hasCropAdjustments }

    var canvasWorkflowImageExtent: CGRect? {
        guard let imageSource else { return nil }
        let oriented = RenderPipeline.geometryExtent(
            of: document.rotation.orientedExtent(imageSource.nativeExtent), for: document.crop
        )
        let crop = document.crop.normalizedRect ?? CropAdjustments.unitRect
        let size = CGSize(width: oriented.width * crop.width, height: oriented.height * crop.height)
        guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else {
            return nil
        }
        return CGRect(origin: .zero, size: size)
    }

    func updateCanvasWorkflowDocument(_ transform: (inout EditDocument) -> Void) {
        updateDocument(transform)
    }

    func endCanvasWorkflowUndoGrouping() { endUndoGrouping() }
    func setCanvasWorkflowStatus(_ message: String) { statusMessage = message }

    func captureCropWorkflowPresentation() -> CropWorkflowPresentation {
        CropWorkflowPresentation(
            isInspectorPresented: inspectorState.isPresented,
            inspectorTab: inspectorState.tab.rawValue,
            isSourceBrowserPresented: isSourceBrowserPresented
        )
    }

    func prepareCropWorkflowPresentation() {
        isSourceBrowserPresented = false
        inspectorState.isPresented = true
    }

    func restoreCropWorkflowPresentation(_ presentation: CropWorkflowPresentation) {
        isSourceBrowserPresented = presentation.isSourceBrowserPresented
        if let tab = InspectorTab(rawValue: presentation.inspectorTab) {
            inspectorState.tab = tab
        }
        inspectorState.isPresented = presentation.isInspectorPresented
    }

    func scheduleCanvasWorkflowPreview() { schedulePreview() }
    func scheduleCanvasWorkflowCropEntryPreview() { scheduleCropEntryPreview() }
    func scheduleCanvasWorkflowInteractivePreview() { scheduleInteractivePreview() }

    func canvasNavigationDidChange(_ change: CanvasNavigationChange) {
        switch change {
        case .zoom:
            if !isPreviewInteractionActive { previewPresentation.advanceDisplayRevision() }
            if isPreviewInteractionActive {
                scheduleInteractivePreview()
            } else {
                scheduleSettledPreviewAfterDebounce()
            }
        case .pan:
            scheduleInteractivePreview()
        }
    }

    func setCanvasWorkflowOriginalVisible(_ visible: Bool) {
        isShowingOriginal = visible
    }
}

extension AppViewModel: PreviewPublicationDestination {
    var publicationIsShuttingDown: Bool { isShuttingDown }
    var publicationActiveAssetID: PhotoAssetID? { activeAssetID }
    var publicationImageSource: ImageSource? { imageSource }
    var publicationSourceRevision: UInt64 { sourceRevision }
    var publicationDisplayRevision: UInt64 { displayRevision }
    var publicationDisplayDocument: EditDocument { displayRequest.document }
    var publicationSourceName: String { sourceName }
    var publicationIsAutoAdjustmentInProgress: Bool { isAutoAdjustmentInProgress }
    var publicationIsSideBySideVisible: Bool { isSideBySideVisible }
    var publicationStoredEditsResolvedSourceRevision: UInt64? {
        storedEditAdoption.resolvedSourceRevision
    }
    func publicationAcceptsFrame(
        assetID: PhotoAssetID?, identity: PortablePhotoIdentity, generation: UInt64
    ) -> Bool {
        generation == sourceRevision && previewPresentation.admitsPublication(
            assetID: assetID, identity: identity, generation: generation
        )
    }
    func confirmPresentationFrame(
        assetID: PhotoAssetID?, identity: PortablePhotoIdentity, generation: UInt64,
        source: PreviewPresentationCoordinator.CandidateSource
    ) {
        previewPresentation.confirmRenderedFrame(
            assetID: assetID, identity: identity, generation: generation, as: source
        )
    }

    func publishPreviewReady() {
        presentation.previewReady()
        presentPendingImportOutcome()
    }
    func publishPreviewFailure() {
        presentation.previewFailed(hasSource: sourceImage != nil)
        previewSurface.discardDepartingFrame()
        presentPendingImportOutcome()
    }
    func publishAutoAdjustmentReady() {
        publishAutoAdjustmentState(.ready)
    }
    func publishAutoAdjustmentFailure() {
        publishAutoAdjustmentState(
            .unavailable("Auto is unavailable because the photo preview failed.")
        )
    }
    func publishStatusMessage(_ message: String) { statusMessage = message }
    func publishStatusMessageIfLoading(_ expected: String, replacement: String) {
        if statusMessage == expected { statusMessage = replacement }
    }
    func presentAdjustedFrame(
        _ image: CIImage, request: RenderRequest, revision: UInt64,
        onPresented: (@MainActor () -> Void)?
    ) -> Bool {
        let detailIdentity = PreviewFrameIdentity(
            sourceToken: request.source.traceToken,
            documentHash: request.document.editHash,
            space: request.space
        )
        let rasterSource: PresentationRasterSource = request.quality == .interactive
            || previewSurface.hasPresentedDigest ? .refinement : .settled
        let publish: (PerceptualDigest?) -> Bool = { digest in
            self.previewSurface.present(
            image, space: request.space,
            revision: revision,
            telemetry: self.previewCoordinator.telemetry,
            source: request.source,
            quality: request.quality,
            detailIdentity: detailIdentity,
            detailFactor: request.renderScale.factor(for: request.source.nativeExtent),
            presentationImageExtent: request.presentationImageExtent,
            coversPresentationExtent: request.coversPresentationExtent,
            layoutImageExtent: request.presentationLayoutExtent,
            presentationNavigation: request.presentationNavigation,
            perceptualDigest: digest,
            presentationAssetID: request.assetID,
            rasterSource: rasterSource,
            materializesPresentationTexture: self.engine.materializesPresentationTextures,
            onPresented: onPresented
            )
        }
        guard previewSurface.hasPresentedDigest,
            request.quality == .preview, request.sourceROI == nil,
            request.coversPresentationExtent
        else { return publish(nil) }

        let expectedSurfaceRevision = previewSurface.revision
        let engine = self.engine
        Task { @MainActor [weak self] in
            let digest = await engine.makePerceptualDigest(image, space: request.space)
            guard let self, self.previewSurface.revision == expectedSurfaceRevision else { return }
            _ = publish(digest)
        }
        return true
    }
    func publicationScheduleOriginalPreview(
        allowHiddenPreparation: Bool, allowBeforePresentationConfirmation: Bool
    ) {
        scheduleOriginalPreview(
            allowHiddenPreparation: allowHiddenPreparation,
            allowBeforePresentationConfirmation: allowBeforePresentationConfirmation
        )
    }
    func publicationCancelComparisonPreview() { cancelComparisonPreview() }
    func publicationUpdateHistogram(for request: RenderRequest, presentedImage: CIImage?) {
        updateHistogram(for: request, presentedImage: presentedImage)
    }
    func publicationScheduleIdlePreviewBuild() { scheduleIdlePreviewBuild() }
    func writeCanonicalPreview(_ image: CIImage, request: RenderRequest) {
        previewPresentation.writeCanonical(image, for: request)
    }
    var publicationMayPersistFrame: Bool { !isShowingOriginal && !canvasState.isCropToolActive }
    var publicationVisiblePreview: CIImage? { previewSurface.image }
}

extension AppViewModel: PreviewAdmissionDestination {
    var admissionIsShuttingDown: Bool { isShuttingDown }
    var admissionImageSource: ImageSource? { imageSource }
    var admissionSourceRevision: UInt64 { sourceRevision }
    var admissionDisplayRevision: UInt64 { displayRevision }
    var admissionDisplayDocument: EditDocument { displayRequest.document }
    var admissionDisplayLUT: CubeLUT? { displayRequest.lut }
    var admissionActiveAssetID: PhotoAssetID? { activeAssetID }
    var admissionLastPresentedRequest: RenderRequest? {
        previewPublicationCoordinator.lastPresentedVisibleRequest
    }
    var admissionLastPresentedImage: CIImage? {
        previewPublicationCoordinator.lastPresentedVisibleImage
    }
    var admissionInspectorPresented: Bool { isInspectorPresented }
    var admissionHistogramLoading: Bool { isHistogramLoading }
    var admissionHistogram: HistogramData? { histogram }
    var admissionPresentationHistogramSample: HistogramData.PresentationSample? {
        previewSurface.presentationHistogramSample
    }
    var admissionPresentationSurfaceRevision: UInt64? { previewSurface.revision }
    func admissionRetryPresentationHistogramSample(surfaceRevision: UInt64) -> Bool {
        previewSurface.retryPresentationHistogramSample(surfaceRevision: surfaceRevision)
    }
    var admissionOriginalPreviewImage: CIImage? { originalPreviewSurface.image }
    var admissionHistogramErrorMessage: String? { histogramErrorMessage }
    var admissionSourceName: String { sourceName }
    var admissionCollection: ImageCollection { collection }
    var admissionEditStore: EditDocumentStore { editStore }
    var admissionCanWarmAdjacentDocuments: Bool {
        navigation.isEdit && previewState == .ready && !sourceSession.isBusy
            && !previewAdmissionCoordinator.isPreviewDebouncing
            && !isPreviewInteractionActive && workScheduler.runningEditorCount == 0
    }
    var admissionNavigationIsEdit: Bool { navigation.isEdit }
    func admissionResolveBrowsingAsset(for assetID: PortablePhotoAssetID) async throws -> PhotoAsset
    {
        guard let portableLibrary else { throw CocoaError(.fileNoSuchFile) }
        return try await portableLibrary.materializedAsset(for: assetID)
    }
    var admissionPresentation: PreviewPresentationCoordinator { previewPresentation }
    var admissionSourceSessionIsBusy: Bool { sourceSession.isBusy }
    var admissionPreviewDebouncing: Bool { previewAdmissionCoordinator.isPreviewDebouncing }
    var admissionPreviewInteractionActive: Bool { isPreviewInteractionActive }
    var admissionPreviewBackingSize: CGSize { previewAdmissionCoordinator.planningViewportSize }
    var admissionDocument: EditDocument { document }
    var admissionComparisonBaselineDocument: EditDocument { comparisonBaselineDocument }
    var admissionComparisonRevision: UInt64 { comparisonRevision }
    var admissionActiveSourceReference: EditSourceReference? { activeSourceReference }
    var admissionIsShowingOriginal: Bool { isShowingOriginal }
    var admissionIsSideBySideVisible: Bool { isSideBySideVisible }
    var admissionHasOriginalPreview: Bool { originalPreviewSurface.image != nil }
    func admissionScheduleOriginalPreview() {
        scheduleOriginalPreview(allowBeforePresentationConfirmation: true)
    }
    var admissionHasComparisonPreviewCandidate: Bool {
        previewSurface.image != nil
            && previewPublicationCoordinator.lastPublishedVisibleRequest?.source == imageSource
            && previewPublicationCoordinator.lastPublishedVisibleRequest?.document == document
    }
    var admissionSelectedLook: CubeLUT? { selectedLook }
    var admissionCropToolActive: Bool { canvasState.isCropToolActive }
    var admissionCanvasNavigation: CanvasNavigation { canvasState.navigation }
    var admissionCropRotation: ImageRotation { canvasState.cropRotation }
    var admissionCropFlipHorizontal: Bool { canvasState.cropFlipHorizontal }
    var admissionCropFlipVertical: Bool { canvasState.cropFlipVertical }
    var admissionCropVerticalPerspective: Double { canvasState.cropVerticalPerspective }
    var admissionCropHorizontalPerspective: Double { canvasState.cropHorizontalPerspective }
    var admissionPreviewCoordinator: PreviewCoordinator { previewCoordinator }
    var pendingEditedThumbnailAssetID: PhotoAssetID? { editedThumbnailCoordinator.pendingAssetID }
    func admitSettledEditedThumbnail(_ assetID: PhotoAssetID) {
        editedThumbnailCoordinator.admitDeferredDemands()
        scheduleEditedThumbnailAfterSettle(for: assetID, priority: .activeEditor)
    }
    func admitDeferredEditedThumbnails() {
        editedThumbnailCoordinator.admitDeferredDemands()
    }
    var admissionStoredEditsResolved: Bool { storedEditAdoption.isResolved(for: sourceRevision) }
    func admissionStoredLookSignature(for lutID: LUTID?) -> LookSignature? {
        guard let lutID, let stored = storedEditLook, stored.lutID == lutID else { return nil }
        return stored
    }
    func admissionClearPreview() { previewSurface.clear() }
    func admissionPrepareStaleRefinement(using digest: PerceptualDigest) {
        previewSurface.prepareStaleRefinement(using: digest)
    }
    func admissionPresentCacheRaster(
        _ image: CIImage, request: RenderRequest, assetID: PhotoAssetID?,
        sourceRevision: UInt64, displayRevision: UInt64
    ) {
        _ = previewPublicationCoordinator.presentSettledRaster(
            image, request: request, assetID: assetID,
            sourceRevision: sourceRevision, displayRevision: displayRevision,
            persistsFrame: false,
            confirmationSource: .storedFrame
        )
    }
    func admissionConfirmExistingStoredFrame(
        _ image: CIImage, request: RenderRequest, assetID: PhotoAssetID?,
        sourceRevision: UInt64, displayRevision: UInt64
    ) -> Bool {
        guard previewPresentation.hasStoredFrameCandidate(generation: sourceRevision) else {
            return false
        }
        pendingStoredFrameConfirmation = PendingStoredFrameConfirmation(
            image: image, request: request, assetID: assetID,
            sourceRevision: sourceRevision, displayRevision: displayRevision
        )
        completePendingStoredFrameConfirmation(generation: sourceRevision)
        return true
    }

    func admissionDocument(for assetID: PhotoAssetID) -> EditDocument? {
        editorDocument.session(for: assetID)?.document
    }
    func admissionSourceReference(for item: ImageCollection.Item) -> EditSourceReference {
        EditSourceReference(
            assetID: item.id, portableIdentity: persistencePortableIdentity(for: item), url: item.url
        )
    }
    func admissionResolvedLUT(_ id: LUTID?) -> CubeLUT? { resolvedLUT(id) }
    func admissionAdjacentPlan(for document: EditDocument, nativeExtent: CGSize) -> ResolutionPlan {
        var planner = ResolutionPlanner()
        return planner.plan(
            nativeExtent: document.rotation.orientedExtent(nativeExtent), crop: document.crop,
            viewportSize: previewAdmissionCoordinator.previewBackingSize,
            navigation: CanvasNavigation()
        )
    }
    func admissionCanonicalPlan(for document: EditDocument, nativeExtent: CGSize) -> ResolutionPlan {
        var planner = ResolutionPlanner()
        return planner.plan(
            nativeExtent: document.rotation.orientedExtent(nativeExtent), crop: document.crop,
            viewportSize: CGSize(
                width: CGFloat(LatestPreviewFrameStore.canonicalLongEdge),
                height: CGFloat(LatestPreviewFrameStore.canonicalLongEdge)
            ), navigation: CanvasNavigation()
        )
    }
    func admissionSettledRequest(
        source: ImageSource, assetID: PhotoAssetID?, document: EditDocument, lut: CubeLUT?,
        plan: ResolutionPlan, canonical: Bool
    ) -> RenderRequest {
        RenderRequest(
            source: source, assetID: assetID, document: document, lut: lut,
            targetSize: plan.sourceSize,
            sourceROI: canonical ? nil : plan.previewSourceROI(
                nativeExtent: document.rotation.orientedExtent(source.nativeExtent)
            ),
            presentationROI: canonical ? nil : plan.visiblePresentationRect,
            presentationImageExtent: plan.presentationImageExtent,
            presentationNavigation: canvasState.navigation,
            quality: .preview, output: .raster, space: .current
        )
    }

    func publishAdmissionHistogram(_ histogram: HistogramData?) { self.histogram = histogram }
    func publishAdmissionHistogramLoading(_ isLoading: Bool) { isHistogramLoading = isLoading }
    func publishAdmissionHistogramError(_ message: String?) { histogramErrorMessage = message }
    func publishAdmissionStatus(_ message: String) { statusMessage = message }
    func admissionPresentOriginalPreview(_ image: CIImage, request: RenderRequest) -> Bool {
        let hadValidOriginal = originalPreviewSurface.image != nil
        return originalPreviewSurface.present(
            image,
            space: request.space,
            presentationImageExtent: request.presentationImageExtent,
            coversPresentationExtent: request.coversPresentationExtent,
            layoutImageExtent: request.presentationLayoutExtent,
            presentationNavigation: request.presentationNavigation
        ) || hadValidOriginal
    }
    func admissionClearOriginalPreview() { originalPreviewSurface.clear() }
    func admissionScheduleIdleFrameWarmup() { idleFrameWarmerCoordinator.schedule() }
    func admissionCancelIdleFrameWarmup(resetProgress: Bool) {
        idleFrameWarmerCoordinator.cancel(resetProgress: resetProgress)
    }
}

extension AppViewModel: LibraryDeletionCleanupDestination {
    var activeDeletionAssetID: PhotoAssetID? { activeAssetID }

    func removeEditedThumbnails(for assetIDs: Set<PhotoAssetID>) {
        editedThumbnailCoordinator.removeAssets(assetIDs)
    }

    func removeThumbnailFrames(for assetIDs: Set<PortablePhotoAssetID>) {
        Task { [thumbnailFrameStore] in
            await thumbnailFrameStore.remove(assetIDs: assetIDs)
        }
    }

    func removeEditorSessions(for assetIDs: Set<PhotoAssetID>) {
        editorDocument.removeSessions(for: assetIDs)
    }

    func syncPortableSelectionAfterDeletion() {
        libraryBrowsingCoordinator.syncPortableSelection()
    }

    func invalidatePreviewIdentities(_ identities: Set<PortablePhotoIdentity>) async {
        await previewPresentation.store.invalidate(identities: identities)
    }

    func invalidateRenderCaches() async {
        Thumbnails.invalidateCache()
        await engine.invalidateRenderCaches()
    }
}

extension AppViewModel: LibraryBrowsingDestination {
    var isLibraryGridShowing: Bool { navigation.isGrid }

    func showLibraryGridIfActive() {
        // Launch chooses the Library on its own. A collection reload must not change workspace:
        // leaving Edit also makes the workspace picker reopen the selected photo.
    }

    func openPortableLibraryAsset(url: URL, assetID: PhotoAssetID) {
        openImage(url: url, assetID: assetID)
    }

    func selectCollectionImage(at index: Int) {
        selectCollectionImage(at: index, modifiers: [])
    }

    func setLibraryStatusMessage(_ message: String) { statusMessage = message }

    func presentLibraryError(_ message: String) { presentError(message) }
}

extension AppViewModel: IdleFrameWarmerDestination {
    var idleFrameWarmerIsReady: Bool {
        guard portableLibrary != nil else { return false }
        return libraryBrowsingCoordinator.hasPublishedFirstIndexPage
            && libraryBrowsingCoordinator.hasPublishedVisibleWindow
    }

    var idleFrameWarmerIsBlocked: Bool {
        isShuttingDown || !collection.isActive || collection.isScanning
            || sourceSession.isBusy || isLoading || isNavigationLoading
            || previewAdmissionCoordinator.isPreviewDebouncing || isPreviewInteractionActive
            || isExporting || (!navigation.isGrid && !navigation.isEdit)
    }

    var idleFrameWarmerConditions: IdleFrameWarmerConditions {
        let thermal = ProcessInfo.processInfo.thermalState
        return IdleFrameWarmerConditions(
            isLowPowerModeEnabled: ProcessInfo.processInfo.isLowPowerModeEnabled,
            isThermalStateSeriousOrWorse: thermal == .serious || thermal == .critical,
            isApplicationActive: NSApplication.shared.isActive
        )
    }

    func idleFrameWarmerPlanInput() -> IdleFrameWarmPlanInput? {
        guard let portableLibrary, idleFrameWarmerIsReady else { return nil }
        var anchorIDs = idleFrameWarmerVisiblePortableAssetIDs
        if let active = portableLibrary.portableActiveID { anchorIDs.insert(active) }
        return IdleFrameWarmPlanInput(
            controller: portableLibrary.queryController, anchorIDs: anchorIDs,
            fallbackSelection: collection.selectedIndex,
            recencyOrder: libraryBrowsingCoordinator.launchHintRecencyOrder,
            generation: portableLibrary.indexGeneration
        )
    }

    func idleFrameWarmerPlanIsCurrent(generation: UInt64) -> Bool {
        portableLibrary?.indexGeneration == generation
    }

    func idleFrameWarmerCandidates(for entries: [IdleFrameWarmPlanEntry]) async -> [IdleFrameWarmCandidate] {
        guard let portableLibrary,
              let assets = try? portableLibrary.browsingAssets(forIDs: entries.map(\.assetID))
        else { return [] }
        let byID = Dictionary(
            assets.map { ($0.source.portableIdentity.assetID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        // Gather value inputs on the main actor, then resolve each file's identity off it.
        var pending: [(entry: IdleFrameWarmPlanEntry, asset: PhotoAsset, url: URL,
                       identity: PortablePhotoIdentity, extent: CGSize)] = []
        for entry in entries {
            guard let asset = byID[entry.assetID],
                  let dimensions = asset.dimensions,
                  dimensions.width > 0, dimensions.height > 0,
                  let url = asset.url else { continue }
            let identity = asset.source.portableIdentity
            guard !identity.sourceFingerprint.isBrowsingPlaceholder else { continue }
            pending.append((
                entry, asset, url, identity,
                CGSize(width: dimensions.width, height: dimensions.height)
            ))
        }
        var candidates: [IdleFrameWarmCandidate] = []
        candidates.reserveCapacity(pending.count)
        for item in pending {
            let source = await ImageSource.resolve(
                url: item.url, nativeExtent: item.extent, portableIdentity: item.identity,
                existingFileChangeSignature: item.asset.source.fingerprint
            )
            candidates.append(IdleFrameWarmCandidate(
                index: item.entry.index, assetID: item.asset.id, source: source,
                reference: EditSourceReference(
                    assetID: item.asset.id, portableIdentity: item.identity, url: item.url
                ),
                inMemoryDocument: editorDocument.session(for: item.asset.id)?.document,
                inMemoryLookSignature: idleFrameWarmerSavedLookSignature(for: item.asset.id),
                distanceFromViewport: item.entry.distanceFromViewport,
                launchHintRecencyRank: item.entry.launchHintRecencyRank
            ))
        }
        return candidates
    }

    var idleFrameWarmerActivePortableAssetID: PortablePhotoAssetID? {
        portableLibrary?.portableActiveID
    }

    var idleFrameWarmerVisiblePortableAssetIDs: Set<PortablePhotoAssetID> {
        Set(collection.visibleEditedThumbnailAssetIDs.map(PortablePhotoAssetID.compatibility(from:)))
    }

    func idleFrameWarmerSavedLookSignature(for assetID: PhotoAssetID) -> LookSignature? {
        guard assetID == activeAssetID else { return nil }
        return admissionStoredLookSignature(for: editorDocument.session(for: assetID)?.document.lut.lutID)
    }

    func idleFrameWarmerResolvedLUT(_ id: LUTID?) -> CubeLUT? { resolvedLUT(id) }

    func idleFrameWarmerCanonicalRequest(
        source: ImageSource, assetID: PhotoAssetID, document: EditDocument, lut: CubeLUT?
    ) -> RenderRequest {
        let plan = admissionCanonicalPlan(for: document, nativeExtent: source.nativeExtent)
        return admissionSettledRequest(
            source: source, assetID: assetID, document: document, lut: lut,
            plan: plan, canonical: true
        )
    }
}

extension AppViewModel: EditClipboardDestination {
    var clipboardHasCopySource: Bool { activeAssetID != nil && sourceImage != nil }
    var clipboardSourceName: String { sourceName }
    var clipboardDocument: EditDocument { document }
    var clipboardActiveSourceReference: EditSourceReference? { activeSourceReference }
    var clipboardActiveDestinationIsRAW: Bool? {
        guard activeAssetID != nil, let imageSource else { return nil }
        return imageSource.kind == .raw
    }
    var clipboardSelectedTargets: [EditClipboardTarget] {
        collection.selectedItems.map { item in
            let isRAW: Bool
            if let url = item.url {
                isRAW = ImageSource.kind(forExtension: url.pathExtension) == .raw
            } else if let data = item.imageData {
                isRAW = ImageSource.kind(forData: data) == .raw
            } else {
                isRAW = false
            }
            return EditClipboardTarget(
                sourceReference: EditSourceReference(
                    assetID: item.id, portableIdentity: persistencePortableIdentity(for: item),
                    url: item.url
                ),
                isRAW: isRAW
            )
        }
    }

    func activateClipboardAsset(_ assetID: PhotoAssetID) { activeAssetID = assetID }
    func setClipboardStatus(_ message: String) { statusMessage = message }
    func persistInactiveClipboardDocument(_ document: EditDocument, for reference: EditSourceReference) {
        requestEditedThumbnail(for: reference.assetID, priority: .visibleGrid, force: true)
        queuePersistence(document, for: reference, reportsStatus: false, force: true)
    }
    func flushClipboardPersistence() { requestPersistenceFlush() }
}

extension AppViewModel: ExportWorkflowDestination {
    var exportSelectionCount: Int { collection.selectedItems.count }
    var exportActiveAssetID: PhotoAssetID? { activeAssetID }
    var exportSourceName: String { sourceName }

    func exportBatchRequest(selectedOnly: Bool) -> ExportBatchRequest {
        selectedOnly ? selectedBatchExportRequest : batchExportRequest
    }

    func setExportStatus(_ message: String) { statusMessage = message }
    func presentExportError(_ message: String) { presentError(message) }
}

extension AppViewModel: PackageSourceImportDestination {
    var isPackageAvailable: Bool { portableLibrary != nil }

    func reportPackageUnavailable() { reportPortableLibraryUnavailable() }

    func mergeCommittedImports() { try? libraryBrowsingCoordinator.mergeCommittedImports() }

    func reloadCollection() throws { try reloadPortableCollection() }

    func openAsset(_ assetID: PortablePhotoAssetID) { openPortableAsset(assetID) }

    func presentOutcome(_ summary: ImportOutcomeSummary, prefix: String) {
        presentImportOutcome(summary, prefix: prefix)
    }

    func presentStatus(_ message: String) { statusMessage = message }

    func openImages(
        urls: [URL], operationID: UUID,
        completion: @escaping @MainActor (ImportOutcomeSummary?) -> Void
    ) {
        openImages(urls: urls, operationID: operationID, access: [], completion: completion)
    }

    func finishMediaImport(_ summary: ImportOutcomeSummary, operationID: UUID) {
        libraryMediaWorkflow.finishImport(summary: summary, operationID: operationID)
    }

    func cancelMediaImport() { libraryMediaWorkflow.cancelRemovableMediaImport() }
}

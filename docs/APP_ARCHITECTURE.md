# Application ownership boundaries

Product intent and explicit scope boundaries are in [`PRODUCT_SCOPE.md`](PRODUCT_SCOPE.md). This
guide describes current code ownership; the package library is the only production library mode.

## Library product boundary (KRMA-520)

The library product is package-backed. Referenced-folder browsing has no product future and is not
restored, persisted, or maintained as a second mode. A folder chooser, folder drop, Photos import,
or removable-volume selection is an import source: accepted assets are copied into the open
`.kromoralibrary` package and then presented through the package query/window model.

This is a deliberate migration boundary, not an on-disk cleanup. Existing `EditStore*.store`
files are left untouched for backup/recovery and are not read as a library fallback. Future
referenced assets, if product requirements return, will be represented as package `.referenced`
records rather than by reintroducing a source bookmark or folder-backed collection mode.

The cleanup removed scan/discovery, bookmark recovery, legacy reservations, and UserDefaults culling
state from `ImageCollection`, which no longer has a folder-backed mode.

`AppViewModel` is the application composition root and a façade for the main window. It wires
collaborators, owns published cross-feature presentation state, and sequences source/revision
fences. Feature workflows do not reach into one another's private state.

`AppViewModel.swift` is a size-guarded file: `PackageSettingsTests.testAppViewModelDoesNotRegrow` holds
the line ceiling as a trend guard (the test owns the number; this page does not copy it). Extract new
workflows into coordinators rather than raising the ceiling. A dated measurement: 5,033 lines on
2026-10-14.

## Boundaries

| Workflow | Owner | Values crossing the boundary |
| --- | --- | --- |
| Source and library | `ImageCollection`, `SourceImportPlan`, `SourceSessionCoordinator`, `StoredEditAdoptionCoordinator`, `LibraryMediaWorkflowCoordinator`, `LibraryImportCoordinator`, `PackageSourceImportCoordinator`, `PhotosImportCoordinator`, and `LUTLibrary` | source plans, prepared source publications, media/import requests, stored-document results, metadata/capability values, collection items, import progress |
| Library browsing | `LibraryBrowsingCoordinator` owns portable query-window paging, mirrored selection, culling-state persistence, and deletion confirmation; `AppViewModel` owns source loading, deletion cleanup, and the edit handoff | query values, page summaries/assets, selection IDs, deletion candidates/results, and open/status callbacks |
| Editor document and history | `AppViewModel` owns the published active `EditDocument`; `EditorDocumentCoordinator` owns per-photo sessions and bounded undo/redo (whole-session retention policy: [`EDITOR_SESSION_RETENTION.md`](EDITOR_SESSION_RETENTION.md)); `EditHistoryCoordinator` owns the published durable revision list/current revision and the history, restore, snapshot, and virtual-copy store I/O (stale-reference fenced, flush-before-write; it owns every operation task, `beginShutdown()` runs early in `AppViewModel.shutdown` to reject new work and fence publication, and its `shutdown()` barrier drains accepted writes before the package lease is released; it takes closures and a narrow store protocol, never `AppViewModel`); package sidecars own durable commit history, named snapshots, and virtual-copy identity | `EditDocument`, `PhotoEditSession`, immutable revision numbers |
| Copy and paste edits | `EditClipboardCoordinator` owns clipboard values, selective-copy state/preferences, and single/batch paste routing; `EditorDocumentCoordinator` owns destination sessions/history; `AppViewModel` commits the active document and adapts persistence/thumbnail effects | `EditClipboardPayload`, category sets, `EditClipboardTarget`, source references, document commit/status callbacks |
| Edited thumbnails | `EditedThumbnailCoordinator` owns per-asset request generations, debounce handles, and scheduler job IDs; `AppViewModel` owns documents and the collection projection | source/document revisions, cache identity, bounded raster thumbnail and edit/LUT revision |
| Idle frame warming | `IdleFrameWarmerCoordinator` owns sequential background fills for original/edited thumbnails and canonical previews; `LibraryBrowsingCoordinator` supplies paged package candidates and launch-hint order; `AppViewModel` supplies readiness, activity, and system conditions | portable identities, source references, edit/look values, viewport distances, and progress |
| Preview and comparison | `PreviewAdmissionCoordinator` owns preview, histogram, adjacent-prefetch, debounce, and comparison-retry admission; `PreviewPublicationCoordinator` owns settled/interactive publication and presented-frame state; `PreviewPresentationCoordinator` owns display/comparison generations, resolution planners, cache identity/access, and canonical cache writes; `PreviewCoordinator` owns render submission; `FirstFramePresentationCoordinator` owns deferred thumbnail/camera-JPEG first-paint candidates, the stored-frame fallback timer, and generation-fenced release decisions (returning value outcomes; no surface or `AppViewModel` reference); `AppViewModel` owns the published document and presentation surfaces and paints released candidates; `ComparisonFramePolicy` owns pure baseline rules | `RenderRequest`, `PreviewCoordinator.Publication`, source/document/display revisions |
| Crop, rotation, and canvas navigation | `CanvasWorkflowCoordinator` owns crop-session commands and presentation snapshot, crop/rotation commands, and fit/fill/zoom/pan navigation; `CanvasInteractionState` owns observable draft and viewport values; `AppViewModel` owns document history, persistence, and render scheduling | crop presentation snapshot, `EditDocument` mutation closures, source size, image extent, and render/navigation callbacks |
| Analysis, Auto, and masking | `PhotoAnalysisCoordinator` owns analysis/cache work; `AutoWorkflowCoordinator` owns Auto invocation state and cancellation, and the pure `AutoEnhancementCoordinator` scores bounded candidates through the renderer; `MaskingWorkflowCoordinator` owns masking-workspace selection, transient creation, and smart-mask analysis lifecycle | analysis value results, mask recipes, asset/source revisions |
| Export and Looks | `ExportWorkflowCoordinator`, `ExportCoordinator`, `DeriveCoordinator`, `LookSaveCoordinator`, `LookSelectionCoordinator`, `LookPreviewCoordinator`, and `LUTLibrary` | render requests, export items, LUT IDs/values, status/error callbacks |
| Lifecycle and shutdown | `ApplicationShellCoordinator` owns process observers and package-maintenance admission; `AppViewModel` remains the shutdown composition root; each collaborator owns cancellation and resource release within its boundary | explicit `shutdown()`/flush calls; observer tokens, maintenance triggers, and provider tasks do not escape their owner |

The active `EditDocument` is intentionally still published by `AppViewModel`: preview, histogram,
comparison, persistence, and the existing view façade all consume that one value. The editor and
clipboard coordinators own the value-state companion data, so history and clipboard changes do not
create a second document store or hidden mutation channel.

## Copy/paste ownership

`EditClipboardCoordinator` owns the value-only clipboard, chosen category mask, selective-copy
sheet state, remembered settings, status text, and active/batch routing. Its weak
`EditClipboardDestination` exposes source/document values, selected `EditClipboardTarget` snapshots,
and focused commit/persistence callbacks; it never retains `AppViewModel`. Source classification and
portable persistence identity are projected at the root's library adapter.

Active pastes commit through `updateDocument`. During a filmstrip load, matching the displayed
source reference restores the matching asset/history before that commit. Non-active pastes use
`EditorDocumentCoordinator.apply` to record per-photo history and revisions, skip unchanged
sessions, then request forced thumbnail/persistence updates and a batch flush. The root retains
thin command and presentation forwards. Derive, Look-save, and removable-media state are observed
directly by `FeatureSheetsModifier` and `RemovableMediaMenu` (not forwarded through the root);
settings and the Look library are observed directly by `LookInspectorView`, `FilmstripView`, the grid cells, `PreviewView`, and `KromoraCommands`. The edit clipboard is observed directly by `SelectiveCopySheetModifier` (sheet and categories) and `KeyboardSurface` (paste availability). No child notification forwards through the root. `EditorDocumentCoordinator` is a plain value-state owner with no publisher: undo/redo availability refreshes through root document publications, and `endUndoGrouping` publishes explicitly when closing a gesture group.
`EditClipboardCoordinatorTests` cover source validation, remembered selection/cancel, selective
active commits, RAW/raster batch behavior, selection transitions, per-photo undo, and no-op writes
without constructing `AppViewModel`.

## Source-session ownership

`SourceSessionCoordinator` is constructed from a renderer, edit store, and first-frame provider.
It owns the replaceable source-preparation worker, source generation, stored-edit lookup, metadata
and RAW capability tasks, and embedded first-frame lifetime. It publishes only tagged
`PreparationPublication`, `StoredDocumentPublication`, `MetadataPublication`,
`CapabilitiesPublication`, and `FirstFramePublication` values. The root decides how those values
update the published document, source marker, inspector, and surfaces. Cancellation invalidates
the generation before any asynchronous result can call back; shutdown awaits the worker and its
child tasks.

Open Image (`AppViewModel.openImages`) uses the same scheduler-backed `startImportURLs` path and
`LibraryImportCoordinator` operation as folder imports. It returns immediately, transfers
security-scoped access to the worker (released on every terminal path), and reports its terminal
`ImportOutcomeSummary` through an optional completion that never fires for a superseded or
shut-down operation.

## Stored-edit adoption ownership

`StoredEditAdoptionCoordinator` owns the rules for adopting a photo's stored edits while it loads,
and the per-source state they need: the reconciled source revision and the early-adoption record
(KRMA-755). It takes a value `Context` (request and current source revisions, `hadInMemorySession`,
whether the in-memory edit revision moved, whether the stored document differs, whether a
speculative render is already scheduled) and returns outcomes: stage one (`decideEarlyAdoption`)
says adopt or skip; stage two (`decideLateAdoption`) returns whether to adopt, whether the document
changed, and one preview follow-up (corrective preview, resume the deferred settled preview, or
reconcile the already-presented frame). It holds no reference to `AppViewModel`, which applies the
outcomes to the document, collection crop, preview admission, and thumbnails and stays the sole
publisher of the `EditDocument`; the LUMO-317 rule that the corrective preview queues behind the
speculative render is preserved there. `StoredEditAdoptionCoordinatorTests` cover the early-versus-late
race and the in-memory-session-wins cases without constructing `AppViewModel`.

## Preview-presentation ownership

`PreviewAdmissionCoordinator` owns request admission, debounce handles, histogram jobs,
adjacent prefetch, and comparison-preview admission, including its scheduled and retried revision
state and retry task. `IdleFrameWarmerCoordinator` handles all-photo package warming separately:
it waits for the first index page and viewport, then ranks the whole library once per index
generation off the main actor (`IdleFrameWarmPlanner`, a value snapshot of `LibraryQueryController`
ordered by viewport distance, launch-hint recency, then index position). It keeps only lightweight
ranked IDs, asks `AppViewModel` to materialize bounded pages of candidates, and abandons and
replans (a bounded number of times) if the index generation changes. It admits one `.background`
editor operation per photo. It asks the frame stores for
metadata before opening a source, skips exact tiers, and writes only original/edited thumbnail
records and complete canonical preview frames. It never publishes to a canvas or histogram
surface. `AppViewModel` cancels it for selection, navigation, visible interaction, export, library
activity, app deactivation, shutdown, Low Power Mode, or serious thermal pressure; low-water
admission leaves room below the preview-store cap while the normal pin-aware LRU protects the
active and visible photos. Progress reports completed and remaining photos. `PreviewPublicationCoordinator` owns the settled and
interactive publication funnel, presented-frame state, and latest-wins publication fences;
`PreviewPresentationCoordinator` owns display/comparison generations, per-surface
resolution-planner hysteresis, the selection-time stored-frame lookup and its classification, and
canonical complete-frame writes to `LatestPreviewFrameStore` (an actor in `Derived/Previews`). `ThumbnailFrameStore` (an actor over the packed store in `Derived/Thumbnails`) is owned by `AppViewModel` and read by `ImageCollection` and `EditedThumbnailCoordinator` for cell pixels; `LibraryBrowsingCoordinator` owns `LaunchHints` (read at launch, written coalesced) and package-photo identity resolution for `AppViewModel.openImage`, which fences the canvas before resolving a browsing record.
`PreviewAdmissionCoordinator` holds a settled submission back while a stored frame can still make it
unnecessary, and presents an exact hit instead of rendering. `PreviewCoordinator` remains the only render-submission owner. The root supplies
value-only document/source/navigation inputs and retains the `PreviewSurface` instances, so there
is no second document store or surface reference in these collaborators.

## Source-presentation state ownership (KRMA-910)

`SourcePresentationState` (`ViewModels/SourcePresentationState.swift`) is the single owner of the
source-loading presentation flags: `isLoading`, `isNavigationLoading`, `previewState`,
inspector-document-pending, and toolbar availability/transition. `AppViewModel` stores it once as
`presentation` and exposes the historical names (`isLoading`, `previewState`, …) as read-only
projections. The dimensions stay independent on purpose; the value records presentation readiness
only and never holds the `ImageSource`, render surfaces, active `EditDocument`, or generations.
Call sites keep their existing source/request-generation and `isShuttingDown` guards and then
invoke one named transition. After `shutDown()` every transition is a no-op.

| Event | Transition | loading | nav loading | preview | toolbar |
| --- | --- | --- | --- | --- | --- |
| Placeholder record resolving; new selection | `beginSelection` | on | on | loading | transitioning |
| Cached/ stored first frame or provisional frame confirmed | `firstFramePresented` | – | off | – | – |
| Source preparation handed to session | `beginSourcePreparation` | on | on | – | – |
| Source prepared (marker installed) | `sourcePrepared` | off | – | loading | – |
| Stored document adopted/rejected | `inspectorDocumentSettled` | – | – | – | – (pending off) |
| Renderer frame settled | `previewReady` | – | off | ready | available, settled |
| Render failure | `previewFailed` | – | off | failed | available iff a source exists |
| Source preparation failure | `sourceFailed` | off | off | failed | as `previewFailed`; pending off |
| Direct open failure | `openFailed` | off | – | failed | – |
| Placeholder resolution ended (Library, error) | `endSelection` | off | off | optional | settled |
| Source clear / active deletion | `clear` | off | off | empty | unavailable |
| Shutdown | `shutDown` | – | off | – | frozen |

## Canvas workflow ownership

`CanvasWorkflowCoordinator` owns crop entry, commit, cancel, reset, transient straighten/flip/
perspective updates, quarter-turn behavior, and viewport fit/fill/zoom/pan commands. Its
`CanvasInteractionState` owns the observable crop draft and viewport navigation values so
pointer-frequency changes continue to invalidate only the canvas. Crop presentation restoration
crosses the `CanvasWorkflowDestination` seam as a value snapshot; the coordinator has no inspector
or source-browser references. The destination provides the active document/source geometry and
callbacks for ordinary document updates, undo-group completion, status, and preview scheduling.

`AppViewModel` remains the sole owner of `EditDocument`, history, persistence, preview/revision
fences, and compatibility entry points. Canvas navigation never enters document history. The
coordinator has no asynchronous work or retained external resources; `shutdown()` clears a draft
and its presentation snapshot, and source replacement resets the interaction state. Fake-only
`CanvasWorkflowCoordinatorTests` cover crop cancellation and commit, document rotation, and
presentation-only navigation without constructing `AppViewModel`.

## Library browsing ownership

`LibraryBrowsingCoordinator` sequences portable query pages into `ImageCollection`, mirrors the
query controller's selection for the visible window, and owns grid selection, keyboard paging,
portable asset page-faulting, culling persistence, and deletion confirmation. Its
`LibraryBrowsingDestination` is limited to presentation values and callbacks for status/errors,
selection-to-edit, source opening, and deletion. `AppViewModel` remains responsible for opening and
preparing the active photo and `clearActiveSourceAfterLibraryDeletion`; the coordinator never
stores the application model. `LibraryDeletionCoordinator` owns the post-deletion cleanup sequence
through `LibraryDeletionCleanupDestination` and returns a `LibraryDeletionOutcome` (active-photo
action plus status/error message) that the root applies.
`LibraryBrowsingCoordinatorTests` exercise paging, query no-op behavior, off-window opens, culling
persistence, and the grid-only confirmation rule with a fake query provider and destination.

## Library/media and application-shell ownership

`LibraryMediaWorkflowCoordinator` owns mounted-volume discovery, debounced scan replacement,
selection state, security-scoped validation, source-folder dialog/drop classification, and the
cancelable media-import validation task. It publishes narrow state and a
`RemovableMediaImportRequest` value to the composition root. The root remains responsible for the
final package or managed-copy transaction, then reports the result back through `finishImport`; no
workflow creates a second authoritative library.

The in-app import selector tags files already in the open library. It serves removable volumes and
folders (a folder is scanned as a source just like a volume; `MediaImportSource` only changes
wording and the status prefix). `LibraryMembershipMatcher` compares each file's SHA-256 with the
package import catalog's content hashes (the same rule `PortablePackageImporter` uses for
duplicates), hashing lazily and cancellably on a detached task as scan batches arrive; the catalog
load is cancelled with the selector. Tagged files are left out of default selection and Select All
unless the user clicked them, a count and Hide toggle summarize them, and the library is the only
authority, so other libraries and deleted assets are not remembered.

The system Photos picker cannot show tags, so `PhotosImportReviewCoordinator` reviews its result
before import. The package does not record Photos local identifiers, so each picked item is
transferred and hashed with the same content digest, one at a time off the main actor, and the
import then transfers only the confirmed items.

`ApplicationShellCoordinator` owns workspace mount/unmount observers, app-activation observers,
debounce tasks, portable-package maintenance admission, and observer/maintenance teardown. Its
callbacks are refresh signals only. `AppViewModel` retains the compatibility façade and orders
shutdown by disconnecting callbacks, stopping the shell and media workflow, stopping collection and
provider work, awaiting editor/render collaborators, cancelling the shared scheduler, and then
discarding only explicitly abandoned persistence snapshots. Browsing-placeholder resolution in
`openImage` is a root-owned task keyed by its request generation: shutdown bumps the generation and
cancels, every post-suspension step checks `isShuttingDown` and the generation, and shutdown awaits
all registered tasks (including superseded ones) before the scheduler and writer lease are released.

`LibraryImportCoordinator` is the shared package-write boundary for URL and in-memory imports from
Open, folders, Photos, and removable media. It owns the replaceable import generation, active
worker handle, progress observation task, and progress publication; starting or adopting a newer
operation cancels the previous worker and fences its late callbacks. Its command surface is limited
to the package session's import and batch-finish entry points. `PhotosImportBatchCoordinator` owns
only the streamed Photos batch snapshot, insertion-result mapping, first accepted asset, and the
once-per-batch refresh/source/inspector decision. It calls back through the narrow
`PhotosImportBatchDestination` protocol; it stores neither the app model nor a package session or
import worker. `AppViewModel` adapts that protocol to the existing library import and
collection/editor presentation boundaries. Worker cancellation is cooperative and shutdown cancels
and awaits the library progress observer; the package session's shared scheduler continues to bound
actual I/O admission.

`PackageSourceImportCoordinator` owns the folder, removable-media, and Photos-drop import shape on top of it: start, observe, reload, open the first imported or duplicate asset, and report an `ImportOutcomeSummary` through the narrow `PackageSourceImportDestination` (the root conforms; the coordinator never holds `AppViewModel`). It also owns the drop-promise task and security-scoped access release on no-files paths.

Multi-photo imports stream into the Library grid while they run. The worker appends each committed
source's index entry to a lock-backed `PortablePackageCommitBuffer`; the progress observer drains it
through `PortablePackageImportHandle.publishCommitted()` at most every 250 ms, which applies an
idempotent index delta, and then asks `LibraryBrowsingCoordinator.mergeCommittedImports()` to fold
the new assets into the loaded window. The merge reuses existing cells (thumbnails, demand,
selection, scroll position), inserts new ones in query order with a loading thumbnail state, and
leaves unloaded pages to the normal scroll path. Cancellation or failure drains what was already
committed, so those photos stay in the index and grid. Photos' deferred-catalog batches keep their
single end-of-batch index publication. `MediaVolumeProviding.scanBatches` streams the removable-media
scan in the same way; `LibraryMediaWorkflowCoordinator` merges batches into the selector in final
display order and keeps selection and the shift-click anchor keyed by file id.

## Masking-workflow ownership

`MaskingWorkflowCoordinator` owns the masking workspace: layer/component selection and transient
creation state (`MaskInteractionState`, an `@Observable` class this coordinator constructs and
exposes), plus smart-mask analysis invocation, cancellation, retry context, and the person-signal
warm-up task. `AppViewModel` remains the owner of the published `EditDocument`, undo grouping,
preview scheduling, and inspector chrome; the coordinator reaches into that state only through
`MaskingWorkflowDestination`, a narrow `@MainActor` protocol (`document`/`updateDocument`, status
message, undo grouping, preview interaction begin/end, retry-preview, and masking-workspace
present/dismiss). `PhotoAnalysisCoordinator` is injected behind `MaskAnalysisProviding` — a
three-method async boundary (`analyze`, `mask`, `preparePersonSignals`) — so smart-mask creation,
cancellation, and supersession are covered by fake-runner tests
(`MaskingWorkflowCoordinatorTests`) without a renderer, Vision, or an `AppViewModel`.

A masking command commits through `MaskingWorkflowDestination.updateDocument`, which gives it the
normal persistence/undo/copy-paste path automatically — the coordinator never becomes a second
document store. `AppViewModel` keeps every masking entry point (`createMask`, `createSmartMask`,
`beginMaskGesture`, …) as a one-line forwarder in `AppViewModel+Masking.swift` so existing View and
`KeyboardShortcuts` call sites are unaffected. Smart-mask and person-signal-warming tasks are owned
and cancelled by the coordinator's own `shutdown()`, called once from `AppViewModel.shutdown`,
rather than living in `AppViewModel`'s task-cancellation array.

## Retouch-workflow ownership

`RetouchWorkflowCoordinator` owns canvas-only selection, hover/handle state, brush drafts, and
shift-click chaining. `RetouchInteractionState` is transient and never enters `EditDocument`. The
preview canvas routes native pointer samples through `GeometryPointMapping` into oriented-source
coordinates; the coordinator commits each finished brush or handle gesture through
`AppViewModel.updateDocument` once. `AppViewModel` remains the recipe, undo, and render owner.
Entering Retouch closes crop and masking so only one canvas tool captures pointer input.

The coordinator also owns the dust-analysis lifecycle (Detect Dust and the visualization overlay).
Each request captures the source fingerprint, a monotonically bumped generation, and the threshold;
after its suspension it publishes only if the owner is live, the generation is current, the source is
unchanged (and, for visualization, still enabled). Generations are bumped before anything is awaited
because cancellation alone does not stop a proxy provider that ignores it. `AppViewModel` calls
`activeSourceDidChange()` when `imageSource` changes, which clears suggestions, candidates, and
gesture selection (thresholds and overlay policy persist), and `shutdown()` before releasing
renderer resources. Accept and Accept All verify the suggestions' owning source still matches the
open photo.

CPU work runs in `RetouchDustAnalysisWorker`, an actor, never on the main actor. Each lane (Detect Dust,
overlay) runs one request and keeps one replaceable pending request, so a slider burst collapses to
the active request plus the latest threshold. The worker retains the threshold-independent blur and
difference-of-Gaussians products for the current photo; threshold changes redo only peak selection.
Source change and shutdown invalidate the lanes, and shutdown awaits the owned loops.

## Edited-thumbnail ownership

`EditedThumbnailCoordinator` owns edited-thumbnail demand admission, per-asset generations,
trailing debounce tasks, scheduler job IDs, and cancellation during source replacement, item
deletion, and shutdown. It reuses the collection's bounded `.thumbnail` scheduler lane and submits
only `.thumbnail` raster requests through `EditedThumbnailRendering`; source preparation supplies
the extent fallback, and full-resolution preview work remains outside this workflow. Debounced
active-asset edits wait 500 ms after preview settles and coalesce repeated changes into one forced
request.

`AppViewModel` remains the sole owner of the active `EditDocument`, editor sessions, edit store,
source/document revisions, LUT resolution, and collection. The coordinator reaches these through
`EditedThumbnailDestination`, a narrow `@MainActor` protocol, and publishes only thumbnail values,
crop presentation, and revision strings. Every completion checks the per-asset generation, current
collection item and source cache identity, and the appropriate active-source/document or stored
document revision before publishing. Identity documents publish a nil edited thumbnail without
rendering. Fake-only `EditedThumbnailCoordinatorTests` cover debounce coalescing, shutdown and
source-identity late-result rejection, revision composition, and identity-document behavior.

## AppViewModel root inventory

`AppViewModel` is the composition root, the main-window command façade, and the sole publisher of
the active `EditDocument`. The inventory below reflects the current `AppViewModel.swift` MARKs
after the ownership stages. Line counts are intentionally not recorded here; they drift (see the dated
measurement above).

| MARK / remaining workflow | Owner and root responsibility |
| --- | --- |
| Published state | `AppViewModel` owns the active document and cross-feature chrome: source/loading and preview state, navigation, inspector presentation, comparison mode, metadata, histogram result, status/error, and import/Auto presentation. Collaborators own their workflow state and report values through narrow destinations or callbacks. |
| Owned state | Composition references and application-wide seams remain at the root: collection, editor sessions, edit store/persistence, source identity, revision fences, preview surfaces, schedulers, and collaborator instances. Extracted per-workflow state and task handles live with their owners. |
| Init and wiring | `init` constructs the one shared render and package-I/O graph and wires destinations/callbacks. `wireCoordinators` connects export/Look status and resolution behavior. Neither is a second workflow owner. |
| Error presentation | The root maps hard failures to its status bar and alert; collaborators report outcomes. |
| Auto adjustment | `AutoWorkflowCoordinator` owns invocation state and cancellation. `runAutoAdjustment` snapshots source/document identity, fences completion, presents status, and commits a successful value through `updateDocument`. |
| Image loading and source changes | `load` is the root sequencer: it closes undo, flushes the previous edit, activates the session, invalidates old source/display work, clears surfaces, then starts `SourceSessionCoordinator`. Root installation and stored-edit adoption publish the active document and schedule the corrective render. Stored-edit adoption has two stages: `SourceSessionCoordinator.begin` starts the edit read at selection and `onStoredDocumentLoaded` lets `adoptStoredDocumentValues` put the document on the panel as soon as it is read, independent of the serialized source preparation; the source-dependent reconciliation (`adoptStoredEdits`) still runs after preparation, and queues a corrective render only if a render with a different document was already scheduled. `SourceSessionCoordinator` owns replaceable source preparation and its worker tasks. |
| Import and library commands | `LibraryImportCoordinator`, `PackageSourceImportCoordinator`, `PhotosImportCoordinator`, `PhotosImportBatchCoordinator`, `LibraryMediaWorkflowCoordinator`, and `LibraryBrowsingCoordinator` own their worker, provider, batch bridge, validation, query-window, and selection state. The root keeps view-compatible entry points, final package/import publication, source-to-edit handoff, and cross-feature deletion cleanup. |
| Launch hints | `LibraryBrowsingCoordinator` coalesces device-local viewport/active-ID hints, reads at most two hinted packed-frame windows below current viewport priority, and cancels remaining speculative reads when the grid publishes its real viewport. Hints never alter selection, scroll position, or package truth. |
| Edited thumbnails | `EditedThumbnailCoordinator` owns request state. Root demand, refresh, debounce, and invalidation hooks are forwards; collection/document publication remains at the root boundary. |
| Look browser previews | `LookPreviewCoordinator` owns the browser's lazy 168×112 thumbnails and their bounded cache (24 entries, 8 MB). It renders through the shared `RenderEngine` so RAW development, the Look, global edits, and crop ordering match the canvas (each candidate shares only the developed source, never a graded prefix), and it never changes the document or history. The root forwards `lookPreview(for:)` and keys invalidation on source and document revision. |
| Copy/paste and Looks | `EditClipboardCoordinator` owns clipboard values, selective-copy presentation/preferences, and paste sequencing through a narrow destination. `EditorDocumentCoordinator` owns per-photo sessions/history. `LookSelectionCoordinator` owns Look resolution against `LUTLibrary`/`DerivedLUTRegistry`, the one-shot missing-reference report, and selection/audition decisions; it returns outcomes and never mutates the document. Root commands apply those outcomes through `updateDocument` and preserve multi-photo persistence semantics. |
| Document commit and history | `updateDocument` is the sole ordinary edit commit path: it records history, updates the published document and crop, queues persistence, advances revisions, and admits preview/thumbnail work. `applyHistoryDocument` is the restore sequencer for undo/redo and reset, using the same published document, persistence, revision, and render boundaries. |
| Preview, canvas, and inspector | Preview admission, publication, and presentation collaborators own scheduling, publication fences, cache/planner state, histogram work, and comparison retry. `PreviewCoordinator` remains the render submitter. Canvas workflow owns crop/viewport commands; the root retains surfaces and presentation state. Inspector chrome and displayed histogram values remain root-published. |
| Export, derive, and Look dialogs | `ExportWorkflowCoordinator` owns export entry points (save/folder panels, Share, external-editor handoff, original + settings bundle) and the pending share/handoff URLs through `ExportWorkflowDestination`. `ExportCoordinator`, `DeriveCoordinator`, `LookSaveCoordinator`, and `LUTLibrary` own execution and file/model work. `AppViewModel` keeps thin forwarders and snapshots each export request from the active document or selected assets. |
| Persistence and shutdown | `EditPersistenceCoordinator` owns queued writes. The root serializes source-switch flush barriers and composes shutdown across collaborators and the package lease. |

The narrow one-line façades remain where existing views and integrations call the root:

- Edited-thumbnail request, settle, materialized-refresh, and debounce-cancel methods forward to
  `EditedThumbnailCoordinator`.
- Preview scheduling and comparison-retry helpers forward to `PreviewAdmissionCoordinator`; the
  resolution-plan seam forwards to `PreviewPresentationCoordinator`.
- Crop/rotation and canvas navigation commands forward to `CanvasWorkflowCoordinator`. The root's
  preview-interaction methods remain sequencers because they also bracket undo grouping and
  thumbnail admission; canvas gesture methods update the root's display revision and render policy.
- Masking commands in `AppViewModel+Masking.swift` forward to `MaskingWorkflowCoordinator`.
- Library query/window selection commands forward to `LibraryBrowsingCoordinator`; source opening
  and deletion cleanup remain root-owned handoffs.

The remaining stored root task handles are bounded to root-only setup, platform, or sequencing
work:

| Handle | Why it remains on the root |
| --- | --- |
| `semanticCoordinatorInstallTask` | Installs the photo-analysis coordinator into the shared `RenderEngine` during composition; the root cancels and awaits it at shutdown. |
| `lutCacheInvalidationTask` | Bridges a `LUTLibrary` scan to shared-engine cache invalidation and then re-admits preview/thumbnail work; the root cancels and awaits the current bridge. |
| `droppedPromiseTask` | Owns the AppKit file-promise receipt tied to the root's import and source handoff; a newer drop replaces it, and shutdown cancels and awaits it. |
| `pendingPersistenceFlush` | Chains source-switch flush barriers so an older snapshot finishes before the next one; it is passed into source preparation and is not a second persistence queue. |

Shutdown first closes admission: it marks the root as shutting down, cancels source work, invalidates
Auto/document generations, resets presentation revisions, and cancels preview debounce/retry. It
then disconnects callbacks and Combine subscriptions, shuts down the application shell, and stops the
collection before awaiting edited-thumbnail and preview-admission teardown. It cancels the three
retained cancellable setup/platform tasks, then shuts down masking, media/import, source, library,
export, canvas, Photos, derive/Look-save, analysis, preview-presentation, preview-render, and Look
preview owners. The shared image scheduler barrier runs before the portable package releases its
writer lease; cancelled root tasks are awaited, then explicitly abandoned persistence snapshots
are discarded. Each collaborator cancels its own work within this order.

### Lifecycle transitions (KRMA-1065 audit)

Who owns what at each cross-feature transition, and the test that pins it. `AppViewModel` stays the
only published active-document owner; each row is sequencing the root already performs.

| Transition | Document owner | Generation invalidation | Accepted task owner | Drain barrier | Package lease |
| --- | --- | --- | --- | --- | --- |
| Source switch (`load`/`beginLoad`) | Root publishes the incoming session's document; the outgoing session stays in `EditorDocumentCoordinator` | `load()` advances `loadRequestGeneration` and clears the visible source synchronously. After the import plan resolves, `beginLoad()` calls `sourceSession.begin()`, which advances `sourceRevision` | Pending edit writes: `EditPersistenceCoordinator`; source preparation: `SourceSessionCoordinator` | `requestPersistenceFlush()` chains behind the previous barrier and gates the stored-edit read; source preparation can proceed while it flushes | Held |
| Failed save then switch/retry | The failed photo's session stays resident and dirty (`isDirty` pins it against eviction) | None needed; the snapshot is keyed by asset and reference, not by the active photo | `EditPersistenceCoordinator` keeps the snapshot queued | A forced `flushPendingWrites()` retries; failure is reported, never approved | Held |
| Quit (`applicationShouldTerminate`) | Unchanged until the flush succeeds or the user discards | `shutdown()` sets `isShuttingDown` first, then awaits `libraryOpen.cancelAndWait()` before invalidating source/load generations and closing coordinator-specific admission; callbacks are disconnected before the remaining drains | Edit writes: persistence. Accepted history/snapshot/copy writes: `EditHistoryCoordinator`. Export jobs: `ExportCoordinator` | `flushPendingWrites()`, then `shutdown()`: `editHistory.shutdown()` drains accepted writes; `export.shutdown()` cancels and awaits jobs; `workScheduler.cancelAllAndWait()` | Released by `portableLibrary.shutdown()` after the scheduler barrier, then `persistence.discard()` |
| Library relaunch (`flushAndReleaseLibrary`) | Same as quit | Same as quit (`shutdown()`) | Same as quit | `LibraryReleaseFlow`: flush; on failure Retry loops, Cancel returns `.declined` without shutdown, Discard shuts down as `.releasedWithoutSaving` | Released only on `.released` / `.releasedWithoutSaving`; the replacement launches only after `.released` |

Test map:

- Edit A, delayed/failed save, switch to B, late A completion:
  `EditPersistenceIntegrationTests.testFailedSaveOfPhotoAIsRetainedAcrossSwitchToBAndRetrySavesOnlyA`
  (B shows the default document, A's session remains resident, and the forced flush makes only A durable);
  `testForcedFlushWaitsForAnInFlightSlowWrite` and `testRacedFlushReportsSuccessAfterReplacementDrainsQueue`
  (slow and raced writes); `testLateEditStoreResultCannotOverwriteAnInMemoryEdit` and
  `StoredEditAdoptionTests.testSlowMaterializationCannotReopenSupersededPhoto` /
  `testASupersededSelectionNeverPublishesTheOldPhotosStoredValues` (late results);
  `EditorSessionEvictionTests.testFailedSaveKeepsSessionResidentOverBudgetUntilRetrySucceeds`.
- Quit with accepted history writes plus an export: `EditHistoryCoordinatorTests.testShutdownDrainsAcceptedSnapshotWithoutPublishing`,
  `testShutdownDoesNotCancelAcceptedSnapshotWhileItWaitsForFlush`, `testShutdownDuringVirtualCopySuppressesDidCreate`
  (accepted writes complete, nothing publishes, new work is rejected);
  `ExportJobOwnershipTests.testShutdownCancelsAndAwaitsEveryRegisteredJob` and
  `testViewModelTerminationGuardSeesRegisteredJobs` (jobs are cancelled and awaited, and the quit guard lists them);
  `EditPersistenceIntegrationTests.testFailedTerminationFlushCannotApproveQuitSilently`.
  The ordering between the two drains is fixed by the sequence in `shutdown()` (history before the
  scheduler barrier and lease), so no further combined test mirrors it.
- Failed library-release flush with cancel/retry: `ActiveLibrarySelectionTests.testReleaseFlowRetriesUntilFlushSucceedsThenShutsDownOnce`,
  `testReleaseFlowCancelAfterFailureNeverShutsDownOrDiscards`, `testFailedFlushQuitWithoutSavingDoesNotLaunch`,
  `testReleaseWithoutSavingDoesNotLaunch`, `testDeclinedReleaseDoesNotLaunch`,
  `testRelaunchRequestsLaunchOnlyAfterLibraryReleased`, `testLaunchRequestFindsPackageLeaseReleased`.

Disposition: the audit found no ownership defect. The sequencing lives in `load`/`shutdown()` by
design, is covered per owner as above, and no further pre-release extraction is justified.

Source, document, and display revisions remain distinct. `load` and source-session publications
fence source identity; `updateDocument` advances the document revision and advances display revision
outside an active preview interaction, while `applyHistoryDocument` advances both for history
restoration. Preview publication checks the corresponding source, document, and display snapshot
before touching root-owned surfaces. No extraction adds another document store, renderer, or
scheduler.

## Boundary rules

- Rendered pixels cross only through `RenderRequest` and `RenderEngine`; source, document, and
  revision fences remain application-owned.
- Collaborators exchange `Sendable` value contracts or narrow protocols. They do not mutate another
  collaborator's published properties through an untyped backchannel.
- Native panels and Photos/PhotoKit objects stay at their platform adapters. Tests use plans,
  provider protocols, fakes, and value results instead of constructing the full application model.
- Persistence, export, comparison, undo/redo, and navigation retain their existing semantics; a
  coordinator extraction is complete only when the old AppViewModel façade still routes the same
  operation.

## Active library selection

`ActiveLibrarySelection` (Models) owns which `.kromoralibrary` package a launch opens. Settings >
Choose Library… runs `ActiveLibraryChooser`, which picks a folder through `FileDialogProviding`,
validates it with `PortableLibraryPackage.open(at:)`, stores a security-scoped bookmark and offers
Relaunch / Later. There is no runtime swap. `AppLaunch.open()` resolves the bookmark (else the
default), holds the security scope for the session, and passes the URL to the view model. A stale,
unresolvable or missing choice falls back to the default with a one-time notice and clears only the
bookmark; the old path is never touched. "Use Default Library" clears the bookmark.

## Launch sequence (KRMA-944)

1. **Process start.** The SwiftPM or Xcode launcher creates `KromoraAppDelegate`.
2. **Delegate init (no I/O).** It sets window-tabbing and activation policy and creates
   `AppLaunch()` with `KromoraSettings`. No package, lease, recovery or `AppViewModel` work runs in
   the delegate, `KromoraScene` or `AppLaunch.init`. (Activation policy there is KRMA-945's scope.)
3. **First window with the library shell.** `KromoraRootView` shows a progress shell while
   `AppLaunch.viewModel` is nil; its `.task` calls `AppLaunch.open()`. Settings also calls it.
4. **Open starts.** `open()` resolves the active library (see above), builds `AppViewModel` through
   `makeViewModel` (the only `AppViewModel(` construction in Presentation) with `defersLibraryOpen`,
   and starts `beginOpeningLibrary`. `LibraryOpenState` becomes `.opening` ("Opening library…") and
   library commands are gated.
5. **Lease-recovery prompt (when needed).** `PortablePackageLeaseRecoveryPrompt` asks through the
   sheet seam; a stale-bookmark notice is shown first. Declining leaves the library closed with one
   error.
6. **Async package open.** `LibraryOpenCoordinator` calls `PortablePackageOpener` through the
   `PackageOpening` protocol. Package open and recovery run off the main actor.
7. **Bind.** The returned `OpenedPackage` is bound on the main actor and `PortableLibrarySession`
   is built.
8. **Collection/index load.** Binding publishes the collection, then the packed index loads
   asynchronously (KRMA-557).
9. **Ready.** `LibraryOpenState` becomes `.ready` and commands enable.

An open failure sets `LibraryOpenState.failed` and publishes one error message.
`ApplicationShellCoordinator` (process observers, maintenance admission) is owned by the model and
starts when it is built.

**Shutdown during open.** `AppViewModel.shutdown()` cancels the open first; an unbound lease is
released rather than bound. `applicationShouldTerminate` returns `.terminateNow` only when
`AppLaunch.viewModel` is still nil, which happens when the user quits before the first frame's
`.task` has run: nothing was opened, so there is nothing to flush or release. Otherwise it goes
through the termination guard, flush and `shutdown()`.

## Library open (KRMA-984)

`AppLaunch.open()` builds `AppViewModel` immediately with `defersLibraryOpen`, then
`beginOpeningLibrary` starts `LibraryOpenCoordinator`. The coordinator asks the lease-takeover
question (if needed), runs a `PackageOpening` implementation off the main actor, and binds the
resulting `OpenedPackage` (a `Sendable` package + lease) on the main actor, where the session is
built. State is `.idle → .opening → .ready | .failed`; library-dependent commands stay disabled
until `.ready`. `AppViewModel.shutdown()` cancels the open first: a cancelled open releases its
unbound lease instead of binding (the blocking filesystem work itself cannot be interrupted).

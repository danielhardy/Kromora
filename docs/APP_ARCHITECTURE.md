# Application ownership boundaries

## Library product boundary (KRMA-520)

The library product is package-backed. Referenced-folder browsing has no product future and is not
restored, persisted, or maintained as a second mode. A folder chooser, folder drop, Photos import,
or removable-volume selection is an import source: accepted assets are copied into the open
`.kromoralibrary` package and then presented through the package query/window model.

This is a deliberate migration boundary, not an on-disk cleanup. Existing `EditStore*.store`
files are left untouched for backup/recovery and are not read as a library fallback. Future
referenced assets, if product requirements return, will be represented as package `.referenced`
records rather than by reintroducing a source bookmark or folder-backed collection mode.

The cleanup is intentionally measurable: `ImageCollection.swift` is now 653 lines, down from
2,010 lines at the pre-cleanup baseline, because scan/discovery, bookmark recovery, legacy
reservations, and UserDefaults culling state no longer have a product owner.

`AppViewModel` is the application composition root and a façade for the main window. It wires
collaborators, owns published cross-feature presentation state, and sequences source/revision
fences. Feature workflows do not reach into one another's private state.

## Boundaries

| Workflow | Owner | Values crossing the boundary |
| --- | --- | --- |
| Source and library | `ImageCollection`, `SourceImportPlan`, `SourceSessionCoordinator`, `LibraryMediaWorkflowCoordinator`, `PhotosImportCoordinator`, and `LUTLibrary` | source plans, prepared source publications, media/import requests, stored-document results, metadata/capability values, collection items, import progress |
| Editor document and history | `AppViewModel` owns the published active `EditDocument`; `EditorDocumentCoordinator` owns per-photo sessions, undo/redo, revisions, and clipboard | `EditDocument`, `PhotoEditSession`, `EditClipboardPayload`, revision numbers |
| Preview and comparison | `PreviewPresentationCoordinator` owns display/comparison generations, resolution planners, cache identity/access, and canonical cache writes; `PreviewCoordinator` owns render admission; `AppViewModel` owns the published document and presentation surfaces; `ComparisonFramePolicy` owns pure baseline rules | `RenderRequest`, `PreviewCoordinator.Publication`, source/document/display revisions |
| Analysis and masking | `PhotoAnalysisCoordinator` owns analysis/cache work; `MaskingWorkflowCoordinator` owns masking-workspace selection, transient creation, and smart-mask analysis lifecycle | analysis value results, mask recipes, asset/source revisions |
| Export and Looks | `ExportCoordinator`, `DeriveCoordinator`, `LookSaveCoordinator`, and `LUTLibrary` | render requests, export items, LUT IDs/values, status/error callbacks |
| Lifecycle and shutdown | `ApplicationShellCoordinator` owns process observers and package-maintenance admission; `AppViewModel` remains the shutdown composition root; each collaborator owns cancellation and resource release within its boundary | explicit `shutdown()`/flush calls; observer tokens, maintenance triggers, and provider tasks do not escape their owner |

The active `EditDocument` is intentionally still published by `AppViewModel`: preview, histogram,
comparison, persistence, and the existing view façade all consume that one value. The editor
coordinator owns the value-state companion data, so history and clipboard changes do not create a
second document store or hidden mutation channel.

## Source-session ownership

`SourceSessionCoordinator` is constructed from a renderer, edit store, and first-frame provider.
It owns the replaceable source-preparation worker, source generation, stored-edit lookup, metadata
and RAW capability tasks, and embedded first-frame lifetime. It publishes only tagged
`PreparationPublication`, `StoredDocumentPublication`, `MetadataPublication`,
`CapabilitiesPublication`, and `FirstFramePublication` values. The root decides how those values
update the published document, source marker, inspector, and surfaces. Cancellation invalidates
the generation before any asynchronous result can call back; shutdown awaits the worker and its
child tasks.

## Preview-presentation ownership

`PreviewPresentationCoordinator` owns the display and comparison generations, per-surface
resolution-planner hysteresis, preview cache keys/access, and canonical complete-frame cache
writes. `PreviewCoordinator` remains the only render-admission owner. The root supplies the
value-only document/source/navigation inputs and retains the compatibility methods plus the
`PreviewSurface` instances, so there is no second document store or broad root reference in either
collaborator.

## Library/media and application-shell ownership

`LibraryMediaWorkflowCoordinator` owns mounted-volume discovery, debounced scan replacement,
selection state, security-scoped validation, source-folder dialog/drop classification, and the
cancelable media-import validation task. It publishes narrow state and a
`RemovableMediaImportRequest` value to the composition root. The root remains responsible for the
final package or managed-copy transaction, then reports the result back through `finishImport`; no
workflow creates a second authoritative library.

`ApplicationShellCoordinator` owns workspace mount/unmount observers, app-activation observers,
debounce tasks, portable-package maintenance admission, and observer/maintenance teardown. Its
callbacks are refresh signals only. `AppViewModel` retains the compatibility façade and orders
shutdown by disconnecting callbacks, stopping the shell and media workflow, stopping collection and
provider work, awaiting editor/render collaborators, cancelling the shared scheduler, and then
discarding only explicitly abandoned persistence snapshots.

## Masking-workflow ownership

`MaskingWorkflowCoordinator` owns the masking workspace: layer/component selection and transient
creation state (`MaskInteractionState`, an `ObservableObject` this coordinator constructs and
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

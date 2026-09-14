# Application ownership boundaries

`AppViewModel` is the application composition root and a façade for the main window. It wires
collaborators, owns published cross-feature presentation state, and sequences source/revision
fences. Feature workflows do not reach into one another's private state.

## Boundaries

| Workflow | Owner | Values crossing the boundary |
| --- | --- | --- |
| Source and library | `ImageCollection`, `SourceImportPlan`, `SourceSessionCoordinator`, `LibraryMediaWorkflowCoordinator`, `PhotosImportCoordinator`, and `LUTLibrary` | source plans, prepared source publications, media/import requests, stored-document results, metadata/capability values, collection items, import progress |
| Editor document and history | `AppViewModel` owns the published active `EditDocument`; `EditorDocumentCoordinator` owns per-photo sessions, undo/redo, revisions, and clipboard | `EditDocument`, `PhotoEditSession`, `EditClipboardPayload`, revision numbers |
| Preview and comparison | `PreviewPresentationCoordinator` owns display/comparison generations, resolution planners, cache identity/access, and canonical cache writes; `PreviewCoordinator` owns render admission; `AppViewModel` owns the published document and presentation surfaces; `ComparisonFramePolicy` owns pure baseline rules | `RenderRequest`, `PreviewCoordinator.Publication`, source/document/display revisions |
| Analysis and masking | `PhotoAnalysisCoordinator` owns analysis/cache work; masking state and presentation remain in the masking boundary | analysis value results, mask recipes, asset/source revisions |
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

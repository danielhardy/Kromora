# Application ownership boundaries

`AppViewModel` is the application composition root and a façade for the main window. It wires
collaborators, owns published cross-feature presentation state, and sequences source/revision
fences. Feature workflows do not reach into one another's private state.

## Boundaries

| Workflow | Owner | Values crossing the boundary |
| --- | --- | --- |
| Source and library | `ImageCollection`, `SourceImportPlan`, `PhotosImportCoordinator`, and `LUTLibrary` | source plans, `ImageSource`, `PhotoAssetID`, collection items, import progress |
| Editor document and history | `AppViewModel` owns the published active `EditDocument`; `EditorDocumentCoordinator` owns per-photo sessions, undo/redo, revisions, and clipboard | `EditDocument`, `PhotoEditSession`, `EditClipboardPayload`, revision numbers |
| Preview and comparison | `PreviewCoordinator` owns render admission; `AppViewModel` owns source/display fences and presentation surfaces; `ComparisonFramePolicy` owns pure baseline rules | `RenderRequest`, `PreviewCoordinator.Publication`, source/document/display revisions |
| Analysis and masking | `PhotoAnalysisCoordinator` owns analysis/cache work; masking state and presentation remain in the masking boundary | analysis value results, mask recipes, asset/source revisions |
| Export and Looks | `ExportCoordinator`, `DeriveCoordinator`, `LookSaveCoordinator`, and `LUTLibrary` | render requests, export items, LUT IDs/values, status/error callbacks |
| Lifecycle and shutdown | `AppViewModel` owns the shutdown order as composition root; each collaborator owns cancellation and resource release within its boundary | explicit `shutdown()`/flush calls; no implicit cross-owner cancellation |

The active `EditDocument` is intentionally still published by `AppViewModel`: preview, histogram,
comparison, persistence, and the existing view façade all consume that one value. The editor
coordinator owns the value-state companion data, so history and clipboard changes do not create a
second document store or hidden mutation channel.

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

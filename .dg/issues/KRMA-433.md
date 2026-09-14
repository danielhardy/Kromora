---
id: KRMA-433
title: Extract library-media and lifecycle orchestration from AppViewModel
type: task
status: ready
priority: high
agent: codex
model: gpt-5.6-luna
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - architecture
  - maintainability
  - library
  - lifecycle
created: 2026-09-14T03:08:00.703Z
updated: 2026-09-14T03:54:25.702Z
depends_on:
  - KRMA-432
  - KRMA-431
order: y
board: product
---

## Objective

Finish the remaining `AppViewModel` decomposition after KRMA-382 and KRMA-432 by extracting library/media workflows, native dialog routing, export/Look request assembly where appropriate, application observers, and shutdown coordination behind narrow boundaries.

## Context

The root still owns folder and removable-media discovery, library navigation/deletion, edited-thumbnail orchestration, Photos/removable import sequencing, native dialog entry points, export and Look request assembly, application/media observers, portable maintenance triggering, persistence shutdown ordering, and lifecycle cleanup. Extensions improve navigation but remain the same large object and do not provide independent ownership.

Relevant code:

- `Sources/KromoraKit/ViewModels/AppViewModel.swift`
- `Sources/KromoraKit/ViewModels/AppViewModel+Masking.swift`
- `Sources/KromoraKit/ViewModels/PhotosImportCoordinator.swift`
- `Sources/KromoraKit/ViewModels/ExportCoordinator.swift`
- `Sources/KromoraKit/ViewModels/DeriveCoordinator.swift`
- `Sources/KromoraKit/ViewModels/LookSaveCoordinator.swift`
- `Sources/KromoraKit/Models/ImageCollection.swift`
- `Sources/KromoraKit/Models/MediaVolume.swift`
- `Sources/KromoraKit/Presentation/AppKitFileDialogAdapter.swift`
- `docs/APP_ARCHITECTURE.md`
- `docs/REPOSITORY_IMPROVEMENT_PLAN.md`

## Acceptance criteria

- [ ] Define independent library/media workflow ownership for scanning, paging/selection handoff, folder and removable-media discovery, managed import, deletion, navigation, and edited-thumbnail demand.
- [ ] Define an application-shell boundary for native dialogs, workspace/media notifications, portable-library maintenance triggers, termination flushing, observer registration, and shutdown.
- [ ] Keep `AppViewModel` as the composition root and compatibility façade; collaborators publish value results or narrow state and do not mutate unrelated root state through hidden callbacks.
- [ ] Preserve managed-versus-referenced deletion semantics, security-scoped access, Photos/removable import cancellation, selection identity, thumbnail fencing, export/Look behavior, and termination persistence guarantees.
- [ ] Keep package/library storage ownership aligned with KRMA-430 and KRMA-431; no workflow may reintroduce a second authoritative Application Support library.
- [ ] Add collaborator-level tests using fake file dialogs, workspace/media providers, collections, package stores, schedulers, and render engines.
- [ ] Add integration tests for navigation during scan/import, deletion confirmation/failure, removable-volume appearance/disappearance, dialog cancellation, app activation maintenance, termination flush, and shutdown races.
- [ ] Remove obsolete extension-only organization and record the final ownership boundaries in `docs/APP_ARCHITECTURE.md`.
- [ ] Demonstrate that the root's mutable state, task handles, and lifecycle responsibilities are materially reduced rather than simply renamed.
- [ ] Run focused tests, `swift build -c release`, `scripts/ci-tests.sh fast`, `scripts/ci-tests.sh serial`, `dg validate`, and `git diff --check`.

## Constraints

Do not change render quality, package transaction safety, deletion policy, or public command behavior as part of the extraction. Preserve façade methods until all views and menu commands use the new boundaries.

---
id: KRMA-460
title: "Continue AppViewModel decomposition: ownership first, file splits second"
type: task
status: backlog
priority: medium
creation_provenance:
  runner: cursor
  model: unknown
  actor: cursor
labels:
  - architecture
  - maintainability
created: 2026-09-19T15:31:38.265Z
updated: 2026-09-24T01:13:35.039Z
depends_on:
  - KRMA-465
  - KRMA-466
  - KRMA-467
  - KRMA-468
  - KRMA-469
blockers: []
order: f
board: product
---

## Current disposition (reviewed 2026-09-23)

This remains a **backlog tracking parent**. Do not claim it, do not `dg issue prepare` it, and do not implement several stages in one session.

`AppViewModel.swift` is **5,561 lines** as of this review. Later tickets already finished part of the plan below. A follow-on agent should execute only the open children:

| Child | Original stage | Disposition |
| --- | --- | --- |
| KRMA-461, KRMA-462, KRMA-463 | Unrelated UI bugs filed beside this plan | Already `done`. Ignore. |
| KRMA-464 | Stage 0, optional façade file moves | **Withdrawn.** Crop/canvas forwarders already exist (KRMA-552). The “Look folder” MARK also contains `shutdown()`. A file split here does not change ownership. |
| KRMA-465 | Stage 1, Auto invocation | **Superseded by KRMA-528.** `AutoWorkflowCoordinator` owns invocation, progress, and cancellation. The remaining Auto MARK (`runAutoAdjustment`, about lines 1441–1571) is the apply façade and stays on the root. |
| KRMA-466 | Stage 2, edited thumbnails | **Still open.** This is the next implementation ticket. |
| KRMA-467 | Stage 3, preview and histogram scheduling | **Still open.** Start only after KRMA-466. The preview MARK is still about 365 lines, and idle/prefetch/histogram admission is still on the root. |
| KRMA-468 | Stage 4, masking workspace | **Superseded by KRMA-529.** `MaskingWorkflowCoordinator` owns the workspace. `AppViewModel+Masking.swift` is 172 lines of forwarders. |
| KRMA-469 | Stage 5, re-inventory and docs | **Still open, last.** Start only after KRMA-466 and KRMA-467. `docs/APP_ARCHITECTURE.md` already documents source session, preview presentation, canvas, library import, and masking. |

The inventory table and stage write-ups under “Remaining inventory (2026-09-19)” are the original plan. Where they disagree with the table above, follow the table above.

## Objective

Record a staged plan for shrinking `AppViewModel` without treating “split the 5k-line file” as the goal. Keep the type as the composition root and published-document façade. Extract remaining workflow ownership first; only then move thin façade methods into `AppViewModel+*.swift` files for navigation.

**This is a parent/plan ticket.** Keep it in `backlog`. Do not claim it as one implementation sweep. Each stage below is one PR (or one child ticket). Line count is a trend metric, not a pass/fail target.

## Why a mechanical file split is not enough

`AppViewModel.swift` is **5,173 lines** today. The same type already has six extensions (**2,230 lines**), so the object is about **7,400 lines** even after the previous coordinator work.

KRMA-382, KRMA-432, and KRMA-433 already extracted real collaborators (`EditorDocumentCoordinator`, `SourceSessionCoordinator`, `PreviewPresentationCoordinator`, `LibraryMediaWorkflowCoordinator`, `LibraryDeletionCoordinator`, `ApplicationShellCoordinator`, plus the older export/Look/Photos/analysis owners). Those tickets explicitly rejected “split into extensions to reduce file length” as a substitute for ownership.

`AppViewModel+Color.swift` / `+Light.swift` / `+Effects.swift` / `+Adjust.swift` / `+Develop.swift` are already the right shape for inspector bindings: they mutate the one published `EditDocument` through `updateDocument`. Do not turn those into coordinators.

`AppViewModel+Masking.swift` (**1,310 lines**) is the counter-example: it is a feature boundary candidate still living as an extension of the root.

## What should stay on AppViewModel

- Composition: `init`, collaborator wiring, `shutdown()`, persistence flush/discard.
- One published active `EditDocument`, source chrome, navigation policy, status/error presentation.
- Cross-feature sequencing in `load()` / `updateDocument()` / `applyHistoryDocument()` — these are the fences, not leftover clutter.
- Compatibility façade methods until views and menu commands are migrated.

Do not introduce a second writable document store, a generic event bus, a second renderer, or a broad `AppViewModel` back-reference from new collaborators. Swift 6: no `@unchecked Sendable`, `nonisolated(unsafe)`, or `@preconcurrency`.

## Remaining inventory (2026-09-19)

| Block | Approx. lines | Current owner | Next move |
| --- | --- | --- | --- |
| Published + owned state | 690 | Root | Keep. Shrink only by extracting fields that travel with a new collaborator. |
| Init / wiring | 555 | Root | Keep. |
| Auto adjustment | 310 | Root (`runAutoAdjustment`); `AutoEnhancementCoordinator` / `ContentAwareAutoEngine` already exist as engines | Extract invocation, progress, cancellation, and apply-via-`updateDocument`. |
| Image loading / install / stored-edit adopt / idle+prefetch | 714 | Root sequences `SourceSessionCoordinator` | Keep `load()` as sequencer; extract idle/prefetch + cache-fill worker. |
| Photos import façade | 196 | Mostly `PhotosImportCoordinator` | Optional façade file after ownership review. |
| Removable media + library selection | 349 | Mix of `LibraryMediaWorkflowCoordinator` façade and remaining import transaction | Keep package/copy transaction at root until it has a value-request owner; façade the rest. |
| Edited thumbnails | 252 | Root (`editedThumbnailGenerations`, debounce tasks) | New `EditedThumbnailCoordinator`. |
| Copy/paste + collection navigation | 213 | Root + `EditorDocumentCoordinator` | Keep commit path; façade the rest. |
| Look / LUT selection | 264 | Root façade over `LUTLibrary` | Optional façade file. |
| Preview scheduling leftover | 331 | Root still owns debounce, interactive/settled submit, comparison retry; `PreviewPresentationCoordinator` owns planners/cache/generations | Move remaining admission/scheduling into that coordinator or a sibling. |
| Crop / rotation / canvas | 219 | `CanvasInteractionState` already owns drafts | Optional façade file. |
| Undo / reset / history apply | 480 | Root sequences `EditorDocumentCoordinator` | Keep one document commit path; do not extract `applyHistoryDocument` away from preview/thumbnail/histogram side effects. |
| Histogram / Info | 121 | Root | Fold into preview-presentation owner. |
| Export / recipe / Look folder / shutdown | ~345 | Mostly façades; `shutdown()` is composition | Façade files for export/Look; keep `shutdown()`. |
| Masking extension | 1,310 | Same type | Extract masking workspace owner (drafts vs committed recipes). |

## Recommended PR sequence

### Stage 0 — Optional navigation-only façade files (S, no behavior change)

Move **already-thin** MARK sections into extensions. Allowed now because they are passthroughs, not hidden state machines:

- Photo import façade
- Export façade
- Look folder / Look file import panels (route new panels through `FileDialogProviding`; do not add more raw `NSOpenPanel` in the root)
- Crop / rotation / canvas passthroughs
- Error presentation helpers

**Not allowed in Stage 0:** Auto, `load()`, preview scheduling, edited thumbnails, histogram, undo/history apply, masking, shutdown. Putting those in extensions first makes later extraction harder and repeats the KRMA-382 anti-pattern.

Acceptance for Stage 0: public APIs unchanged; `git diff` is moves plus file headers; focused + fast tests still pass.

### Stage 1 — Auto invocation owner (M)

Extract the 310-line Auto MARK into a collaborator that:

- Owns `autoAdjustmentTask`, invocation revision, progress publication, and cancellation.
- Calls existing `PhotoAnalysisCoordinator` / `ContentAwareAutoEngine` / histogram fallback.
- Returns a value `AutoEnhancementResult` (or equivalent) that the root applies through the existing `updateDocument` / undo / persistence path.
- Cancels on `load()`, undo/redo, and `shutdown()`.

Do not move Auto policy/scoring out of the existing engines.

### Stage 2 — Edited-thumbnail owner (M)

Extract per-asset generations, debounce tasks, job IDs, and cache-identity hashing. Reuse `ImageWorkScheduler` lanes and cancellation IDs. Root keeps demand hooks (`collection` / filmstrip / grid) and the published collection items.

### Stage 3 — Remaining preview + histogram scheduling (M)

KRMA-432 moved planners, display/comparison generations, and cache I/O. The root still owns interactive/settled submit, debounce, adjacent prefetch, idle cache-fill (`KRMA-328` policy), comparison retry, and histogram admission.

Move that remaining scheduling into `PreviewPresentationCoordinator` or a sibling that still does **not** own `PreviewSurface` or the published document. `PreviewCoordinator` remains the only render-admission owner. Preserve latest-wins source/document/display fences and the idle-vs-prefetch job-ID split.

### Stage 4 — Masking workspace owner (L)

Replace `AppViewModel+Masking.swift` with a collaborator that owns gesture drafts, smart-mask tasks/retry context, and overlay request identity. Committed recipes still enter the document through the root’s one `updateDocument` path. Keep `MaskInteractionState` / overlay renderer contracts. Tests must construct the collaborator with fakes (no full `AppViewModel`, no GPU required for non-render cases).

### Stage 5 — Re-inventory the root

After stages 1–4, list remaining root methods. Expected leftover: `init`/wiring, `load()` sequencer, `updateDocument`/`applyHistoryDocument`, published chrome, `shutdown()`. If a leftover MARK is now a thin façade, file a Stage-0-style move. Update `docs/APP_ARCHITECTURE.md` (and the R5 paragraph in `docs/REPOSITORY_IMPROVEMENT_PLAN.md` if it still describes pre-extraction locations).

## Constraints (every stage)

- Preserve public `AppViewModel` initialization and command façade until callers migrate.
- Collaborators exchange `Sendable` values or narrow protocols. No untyped backchannel into root `@Published` state.
- Persistence, export, comparison, undo/redo, navigation, managed-vs-referenced deletion, and package storage stay semantically unchanged.
- New collaborator tests use fakes; keep existing AppViewModel integration tests for navigation-during-load, Auto, undo grouping, comparison, persistence failure, and shutdown.
- Swift 6 language mode, macOS 14+, zero third-party dependencies.

## Acceptance criteria (parent)

- [ ] This ticket remains a plan/parent; implementation lands as one stage per PR (or as child tickets spawned from the stages above).
- [ ] Stage 0, if done, moves only thin façades and does not relocate Auto/load/preview/thumbnail/histogram/undo/masking/shutdown.
- [ ] Each ownership stage states: state owned, admitted commands, published values, revision checks, task handles, shutdown behavior, and resource limits.
- [ ] AppViewModel remains the sole published active-document owner; no second store or generic event bus.
- [ ] RenderRequest/RenderEngine funnel and source/document/display fences are unchanged.
- [ ] Collaborators are testable without constructing the full AppViewModel, real preferences, NSWorkspace, or GPU setup where the old coordinator tests already follow that pattern.
- [ ] `docs/APP_ARCHITECTURE.md` matches the post-stage ownership table.
- [ ] Line count of `AppViewModel.swift` trends down because mutable state and task handles left the type, not because methods were renamed into extensions.
- [ ] Per-stage verification: focused tests, `swift build`, relevant `scripts/ci-tests.sh` lane, `dg validate`, `git diff --check`.

## Out of scope

- Rewriting the render pipeline or changing image-quality behavior.
- Portable-library package work (`docs/LIBRARY_PACKAGE_PLAN.md` / KRMA-384).
- Broad SwiftUI invalidation / Look-projection work (R6 in `docs/REPOSITORY_IMPROVEMENT_PLAN.md`).
- Splitting `AppViewModelTests.swift` unless a new collaborator needs its own test file.

## Context

- `Sources/KromoraKit/ViewModels/AppViewModel.swift` (5,173 lines; MARK inventory above)
- `Sources/KromoraKit/ViewModels/AppViewModel+Masking.swift` (1,310 lines)
- `Sources/KromoraKit/ViewModels/PreviewPresentationCoordinator.swift`
- `Sources/KromoraKit/ViewModels/SourceSessionCoordinator.swift`
- `Sources/KromoraKit/ViewModels/EditorDocumentCoordinator.swift`
- `docs/APP_ARCHITECTURE.md`
- `docs/ENGINEERING_GUIDE.md`
- `docs/REPOSITORY_IMPROVEMENT_PLAN.md` (R5 — still directionally right, line numbers stale)
- Prior extractions: KRMA-382, KRMA-432, KRMA-433


### Comment — codex @ 2026-09-19T16:28:35.439Z

Plan decomposition recorded: KRMA-464 is the optional Stage 0 façade-only cleanup; KRMA-465 through KRMA-468 are the ownership extractions for Auto, edited thumbnails, preview/histogram scheduling, and masking; KRMA-469 is the final root re-inventory/documentation stage. KRMA-460 depends on the required ownership/re-inventory children and remains a backlog tracking parent.


### Comment — cursor @ 2026-09-24T01:13:35.038Z

Triage 2026-09-23: parent stays backlog. KRMA-464 withdrawn. KRMA-465 superseded by KRMA-528. KRMA-468 superseded by KRMA-529. Remaining execution is KRMA-466, then KRMA-467, then KRMA-469.

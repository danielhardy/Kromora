---
id: KRMA-292
title: Debounce and coalesce edited-thumbnail renders, skip during interaction
type: feature
status: done
priority: urgent
verification_agent: pi
verification_model: openrouter/meta/muse-spark-1.3-contributor
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: A 10-tick slider burst submits previews per policy and at most one trailing thumbnail render
      result: pass
      notes: Covered by new testDebouncedEditBurstCoalescesToOneTrailingThumbnail; 9/9 ThumbnailSwitchLifecycleTests pass
    - criterion: Discrete edits still refresh the badge promptly after settle
      result: pass
      notes: Non-debounced updateDocument path schedules preview plus trailing thumbnail immediately; existing shared-surface test passes
    - criterion: ThumbnailSwitchLifecycleTests extended to cover burst coalescing and interaction skip
      result: pass
      notes: Two new tests added in 42655f2, both pass; interaction test asserts zero thumbnail submissions during begin/endPreviewInteraction window
  checks_run:
    - git diff --check (clean)
    - swift test --filter ThumbnailSwitchLifecycleTests (9 passed)
    - scripts/ci-tests.sh fast (645 passed, exit 0)
    - dg validate (OK with pre-existing low-context/model warnings)
  findings:
    - Stored-document identity check still performs the cheap editStore.load before skipping the render inside the job; in-memory identity skips enqueue entirely. Engine work is skipped in both paths, so the RenderEngine-contention objective holds; non-blocking, no ticket filed.
  fixes: []
  verification_commits: []
  actor: pi
  resolved_model: openrouter/meta/muse-spark-1.3-contributor
  completed_at: 2026-09-09T00:43:23.455Z
  session: 01MTTD43SI0PECY3SS
labels:
  - performance
  - preview
  - thumbnails
created: 2026-09-08T23:48:28.943Z
updated: 2026-09-10T12:53:54.076Z
order: a0
board: product
---

## Objective

Edited-thumbnail renders stop contending with interactive and settled previews on the shared RenderEngine actor.

## Context

Parent: KRMA-289. updateDocument, applyHistoryDocument, and adoptStoredEdits call requestEditedThumbnail(force:true) on every tick, including debounced slider-drag ticks (Sources/LumoKit/ViewModels/AppViewModel.swift). Each thumbnail is a full pipeline run (prepareSource + graph + masks + PNG encode, then NSImage(data:) on the MainActor) serialized against previews on the single actor. Regression from b6df9a3.

## Plan

- Coalesce thumbnail demand: trailing debounce (~500-750ms), one render per pause, superseding queued-but-unstarted work via the existing generation counter.
- Skip entirely while isPreviewInteractionActive or a preview debounce is pending; schedule the trailing thumbnail on settle (endPreviewInteraction / debounce fire / discrete edit).
- Skip the job without touching the store when the resolved document isIdentity (keep the early-out, move it before the store await).
- Tests drive PreviewCoordinator/FakeRenderEngine submission counts, not wall time.

## Acceptance

- A 10-tick slider burst submits previews per policy and at most one trailing thumbnail render.
- Discrete edits still refresh the badge promptly after settle.
- ThumbnailSwitchLifecycleTests extended to cover burst coalescing and interaction skip.


### Comment — codex @ 2026-09-09T00:30:29.270Z

Implemented in 42655f2. Preview debounce handles now clear before trailing thumbnail scheduling; active thumbnail demand callbacks are suppressed during preview interaction/debounce and queued work is canceled; ThumbnailSwitchLifecycleTests cover ten-tick burst coalescing and interaction skip. Verification: git diff --check, swift build -c release, swift test --filter ThumbnailSwitchLifecycleTests (9 passed), scripts/ci-tests.sh fast (645 required tests passed), dg validate (OK with pre-existing low-context/model warnings).


### Comment — pi @ 2026-09-09T00:43:20.041Z

## Verification report — PASS

Scope checked: correctness, maintainability, security, performance; independent re-run of declared checks. Commit verified: 42655f2.

What the change does (Sources/LumoKit/ViewModels/AppViewModel.swift):
- requestEditedThumbnail now returns early while isPreviewInteractionActive or a preview debounce is pending; the active photo's demand is kept as value state (pendingEditedThumbnailAssetID) and queued scheduler work is canceled — no thumbnail enters the shared render actor during interaction/debounce.
- The preview-debounce task handle is cleared (previewDebounceTask = nil) before schedulePreview + trailing-thumbnail scheduling, so scheduleEditedThumbnailAfterSettle can admit exactly one render for the settled document.
- Trailing 500ms debounce in scheduleEditedThumbnailAfterSettle coalesces a slider burst to one render; discrete edits still call schedulePreview + scheduleEditedThumbnailAfterSettle immediately.

Acceptance:
- 10-tick burst -> one trailing thumbnail: PASS (new testDebouncedEditBurstCoalescesToOneTrailingThumbnail).
- Interaction skip + exactly one render after endPreviewInteraction: PASS (new testEditedThumbnailSkipsPreviewInteractionAndRunsOnceAfterItEnds).
- Discrete-edit prompt refresh preserved via the non-debounced updateDocument path plus existing testEditedThumbnailUsesCurrentDocumentAndIsSharedByBrowsingSurfaces.

Note (non-blocking, no ticket): the isIdentity early-out for documents without an in-memory session still performs the cheap editStore.load before skipping the render inside the job; identity is unknowable without loading in that case, and the expensive engine work (prepareSource/render) is skipped in both paths, so the objective holds.

Checks: git diff --check (clean), swift test --filter ThumbnailSwitchLifecycleTests (9/9 pass), scripts/ci-tests.sh fast (645 pass, exit 0), dg validate (OK; only pre-existing low-context/model warnings).

No source changes made during verification; no child tickets filed.

## Agent log

- 2026-09-09T00:43:23.456Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] A 10-tick slider burst submits previews per policy and at most one trailing thumbnail render (pass) — Covered by new testDebouncedEditBurstCoalescesToOneTrailingThumbnail; 9/9 ThumbnailSwitchLifecycleTests pass
- [x] Discrete edits still refresh the badge promptly after settle (pass) — Non-debounced updateDocument path schedules preview plus trailing thumbnail immediately; existing shared-surface test passes
- [x] ThumbnailSwitchLifecycleTests extended to cover burst coalescing and interaction skip (pass) — Two new tests added in 42655f2, both pass; interaction test asserts zero thumbnail submissions during begin/endPreviewInteraction window
Checks run:
- git diff --check (clean)
- swift test --filter ThumbnailSwitchLifecycleTests (9 passed)
- scripts/ci-tests.sh fast (645 passed, exit 0)
- dg validate (OK with pre-existing low-context/model warnings)
Findings:
- Stored-document identity check still performs the cheap editStore.load before skipping the render inside the job; in-memory identity skips enqueue entirely. Engine work is skipped in both paths, so the RenderEngine-contention objective holds; non-blocking, no ticket filed.
Fixes:
- None
Verification commits:
- None
Actor: pi
Resolved model: openrouter/meta/muse-spark-1.3-contributor
Pickup session: 01MTTD43SI0PECY3SS

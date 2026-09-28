---
id: KRMA-690
title: Prevent edited thumbnails flickering when selected in Edit mode
type: bug
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Reproduce the flicker while switching between images in Edit mode and record whether the thumbnail is in the filmstrip, grid, or another selection surface, plus the conditions that trigger it.
      result: pass
      notes: "Implementer confirmed the path in the shared Edit filmstrip/Library grid item (ImageCollection.Item is shared by both surfaces): repeated selection demand cleared an already-published edited thumbnail before the re-render completed."
    - criterion: Compare edited and unedited images and trace any visible intermediate state to thumbnail generation, cache invalidation, selection updates, or another responsible stage.
      result: pass
      notes: Root cause traced to EditedThumbnailCoordinator.request unconditionally calling destination.invalidateEditedThumbnail(for:) on every demand, even when the demand resolved to the same already-published revision; unedited images were unaffected because they never populate a non-fallback edited thumbnail.
    - criterion: Keep the selected image thumbnail visually stable and consistent with the applicable edited/original display policy; do not briefly show a stale or incorrect image state.
      result: pass
      notes: EditedThumbnailCoordinator now only invalidates on force or a genuinely different revision; ImageCollection.applyEditedThumbnail was updated in lockstep to still allow a same-revision fallback-to-real upgrade. Verified by reading both diffs together and by the new regression test.
    - criterion: Preserve timely thumbnail updates when edits or image selection genuinely change, and do not introduce regressions for unedited images.
      result: pass
      notes: Existing coverage for forced refresh, LUT/edit changes, and navigation fencing (testVisibleDemandReplacesAnOlderMaterializedRevisionWithoutInteraction, testSourceIdentityChangeRejectsLateResult, etc.) still passes; unedited (identity-document) path is untouched by the guard change.
    - criterion: Add regression coverage for the triggering edited-image selection/update sequence and record verification commands and results.
      result: pass
      notes: testMatchingEditedThumbnailStaysVisibleDuringRepeatedDemand added; asserts the same NSImage instance (===) stays displayed across a held re-render of a matching revision.
  checks_run:
    - swift test --filter 'EditedThumbnailCoordinatorTests|ThumbnailSwitchLifecycleTests' (29 passed)
    - git diff --check (clean)
    - ./scripts/ci-tests.sh fast, full run (passed on rerun after one earlier run had an unrelated intermittent failure)
  findings:
    - "[test-flake, PLAUSIBLE] ThumbnailSwitchLifecycleTests.testFilmstripAndGridPublishCropAwareSettledThumbnails (Tests/KromoraKitTests/ThumbnailSwitchLifecycleTests.swift) failed once under 'swift test --parallel' with a pixel-buffer mismatch, but passed in isolation and on a full fast-lane rerun. The file is untouched by ba24b36, so this looks like pre-existing flakiness surfaced by parallel scheduling rather than a regression from this change. Non-blocking; filed as KRMA-692 (verification-labeled, parent KRMA-690). Outcome: skipped (out of scope for a localized fix)."
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-28T21:07:08.197Z
  session: 01MULQE7XAO2R2KBMJ
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - bug
  - rendering
created: 2026-09-28T20:50:55.241Z
updated: 2026-09-28T21:07:08.199Z
blockers: []
order: a0
board: product
---

## Objective

Stop thumbnails from visibly flickering when the user changes image selection in Edit mode, especially for images that already have edits.

## User report

The thumbnail for the newly selected image frequently flickers when changing images in Edit mode. The user observes that unedited images do not show the effect. They suspect the thumbnail may render the original first and then render the edited version; this is a hypothesis to verify during investigation.

## Acceptance criteria

- [ ] Reproduce the flicker while switching between images in Edit mode and record whether the thumbnail is in the filmstrip, grid, or another selection surface, plus the conditions that trigger it.
- [ ] Compare edited and unedited images and trace any visible intermediate state to thumbnail generation, cache invalidation, selection updates, or another responsible stage.
- [ ] Keep the selected image thumbnail visually stable and consistent with the applicable edited/original display policy; do not briefly show a stale or incorrect image state.
- [ ] Preserve timely thumbnail updates when edits or image selection genuinely change, and do not introduce regressions for unedited images.
- [ ] Add regression coverage for the triggering edited-image selection/update sequence and record verification commands and results.

## Investigation notes

Check whether selection causes sequential original and edited thumbnail renders, whether cached originals are briefly displayed before revised thumbnails arrive, and whether asynchronous results can overwrite the current selection. Validate any root cause against both edited and unedited images.


### Comment — codex @ 2026-09-28T20:59:53.940Z

Confirmed the flicker path in the shared Edit filmstrip/Library grid item: repeated selection demand could clear an already-published edited thumbnail before rendering completed, exposing the original. Matching edit revisions now remain visible during repeated demand; changed/forced revisions still invalidate, and same-revision failed renders can retry. Added a delayed-render regression test. Verification: swift test --filter 'EditedThumbnailCoordinatorTests|ThumbnailSwitchLifecycleTests' (29 passed); git diff --check passed. Commit: ba24b36.


### Comment — claude @ 2026-09-28T21:06:37.675Z

Verification: reviewed ba24b36 (ImageCollection.applyEditedThumbnail + EditedThumbnailCoordinator.request). Fix is localized and correct: a repeated demand for an already-published edit revision no longer invalidates the visible bitmap before re-render (invalidate now only on force or a genuinely different revision), and applyEditedThumbnail now also permits re-applying the same revision when the current thumbnail is still a fallback, so an upgraded real render isn't skipped. Re-ran 'swift test --filter EditedThumbnailCoordinatorTests|ThumbnailSwitchLifecycleTests' (29/29 passed) and the full './scripts/ci-tests.sh fast' lane (passed on rerun; one earlier run had an unrelated intermittent failure in ThumbnailSwitchLifecycleTests.testFilmstripAndGridPublishCropAwareSettledThumbnails, a file untouched by this fix, reproducible neither in isolation nor on a second full-lane run — filed as KRMA-692, verification-labeled, non-blocking). git diff --check clean. No blocking findings; no additional fixes needed.

## Agent log

- 2026-09-28T21:07:08.197Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Reproduce the flicker while switching between images in Edit mode and record whether the thumbnail is in the filmstrip, grid, or another selection surface, plus the conditions that trigger it. (pass) — Implementer confirmed the path in the shared Edit filmstrip/Library grid item (ImageCollection.Item is shared by both surfaces): repeated selection demand cleared an already-published edited thumbnail before the re-render completed.
- [x] Compare edited and unedited images and trace any visible intermediate state to thumbnail generation, cache invalidation, selection updates, or another responsible stage. (pass) — Root cause traced to EditedThumbnailCoordinator.request unconditionally calling destination.invalidateEditedThumbnail(for:) on every demand, even when the demand resolved to the same already-published revision; unedited images were unaffected because they never populate a non-fallback edited thumbnail.
- [x] Keep the selected image thumbnail visually stable and consistent with the applicable edited/original display policy; do not briefly show a stale or incorrect image state. (pass) — EditedThumbnailCoordinator now only invalidates on force or a genuinely different revision; ImageCollection.applyEditedThumbnail was updated in lockstep to still allow a same-revision fallback-to-real upgrade. Verified by reading both diffs together and by the new regression test.
- [x] Preserve timely thumbnail updates when edits or image selection genuinely change, and do not introduce regressions for unedited images. (pass) — Existing coverage for forced refresh, LUT/edit changes, and navigation fencing (testVisibleDemandReplacesAnOlderMaterializedRevisionWithoutInteraction, testSourceIdentityChangeRejectsLateResult, etc.) still passes; unedited (identity-document) path is untouched by the guard change.
- [x] Add regression coverage for the triggering edited-image selection/update sequence and record verification commands and results. (pass) — testMatchingEditedThumbnailStaysVisibleDuringRepeatedDemand added; asserts the same NSImage instance (===) stays displayed across a held re-render of a matching revision.
Checks run:
- swift test --filter 'EditedThumbnailCoordinatorTests|ThumbnailSwitchLifecycleTests' (29 passed)
- git diff --check (clean)
- ./scripts/ci-tests.sh fast, full run (passed on rerun after one earlier run had an unrelated intermittent failure)
Findings:
- [test-flake, PLAUSIBLE] ThumbnailSwitchLifecycleTests.testFilmstripAndGridPublishCropAwareSettledThumbnails (Tests/KromoraKitTests/ThumbnailSwitchLifecycleTests.swift) failed once under 'swift test --parallel' with a pixel-buffer mismatch, but passed in isolation and on a full fast-lane rerun. The file is untouched by ba24b36, so this looks like pre-existing flakiness surfaced by parallel scheduling rather than a regression from this change. Non-blocking; filed as KRMA-692 (verification-labeled, parent KRMA-690). Outcome: skipped (out of scope for a localized fix).
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MULQE7XAO2R2KBMJ
Summary: Verified the edited-thumbnail flicker fix (ba24b36): the coordinator's invalidate-on-every-demand bug is fixed with a revision/force guard, matched by an ImageCollection.applyEditedThumbnail guard that still allows a same-revision fallback upgrade. Targeted and full fast-lane tests pass; filed non-blocking KRMA-692 for an unrelated, pre-existing parallel-lane test flake.

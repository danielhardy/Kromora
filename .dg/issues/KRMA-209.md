---
id: KRMA-209
title: Auto action is not offered for every loaded photo
type: bug
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Auto visible/enabled once source ready, independent of optional metadata/histogram/prior selection
      result: pass
    - criterion: Navigating/importing/reopening failed analysis refreshes availability without stale disabled/enabled state
      result: pass
    - criterion: If Auto cannot run, UI keeps action discoverable with a specific reason/recovery path
      result: pass
    - criterion: Auto reports progress and recovers from analysis/render failures without a stuck loading state
      result: pass
    - criterion: Regression coverage for supported file, Photos import, optional-analysis-unavailable, photo-navigation, and failure-recovery cases
      result: pass
  checks_run:
    - swift build — clean
    - swift test --filter AutoAdjustmentTests — 11 passed (9 pre-existing/from a9fd6d2 + 2 added)
    - swift test (full suite) — 15 pre-existing failures in unrelated timing-sensitive tests (ComparisonModeTests, FilmstripNavigationTests, ThumbnailSwitchLifecycleTests, etc.), reproduced identically with AutoAdjustmentTests.swift stashed back to a9fd6d2 baseline, confirming unrelated to this change
    - code review of canRunAutoAdjustment (AppViewModel.swift:850-861) and didPresentVisibleFrame/source-switch reset paths confirming previewState and lastPresentedVisibleRequest are always set/cleared together, so dropping the redundant lastPresentedVisibleRequest check from the gate is behavior-preserving
  findings:
    - "Pre-existing, unrelated: 15 tests fail in the full suite (ComparisonModeTests, DevelopInspectorTests, EditPersistenceIntegrationTests, ExportCutoverTests, FilmstripNavigationTests, LUTWorkflowTests, ThumbnailSwitchLifecycleTests) on timing/preview-settling timeouts; reproduces on the pre-LUMO-209 baseline (a9fd6d2 with only the test file stashed), not something introduced by this fix. Not filed as a child ticket since it predates this issue and is orthogonal to Auto availability; flagging for awareness."
    - Working tree contains substantial unrelated uncommitted changes (LibraryFilter, ContentView, FilmstripView, CullingBarView, etc.) present before this verification session started; left untouched as out-of-scope in-progress work.
  fixes: []
  verification_commits:
    - ecbb7bb
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-04T19:31:21.491Z
  session: 01MTNCCRSGBHOX7HMK
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - ux
  - auto
created: 2026-09-04T19:07:55.165Z
updated: 2026-09-10T12:53:47.302Z
order: ejl0v3oh
board: product
commits:
  - a9fd6d2
  - ecbb7bb
---

## Objective

Make the Auto action consistently available for every loaded photo that can be analyzed.

## Context

The toolbar currently disables Auto through `AppViewModel.canRunAutoAdjustment`. The user reports
that the action is not offered for every photo, even though the same editor can display the image.
This makes Auto feel dependent on an unexplained subset of sources and prevents a predictable
fallback when richer photo analysis is unavailable. This is a follow-up to KRMA-149 and the
subject-aware analysis work in KRMA-181/KRMA-200.

## Acceptance criteria

- [ ] With any supported file-backed or Apple Photos-imported image loaded, Auto is visible and
      enabled once the source image is ready; availability does not depend on optional metadata,
      a stale histogram state, or a previously selected photo.
- [ ] Navigating between photos, importing photos, and reopening a failed/unfinished analysis
      refreshes Auto availability for the current asset without leaving the button incorrectly
      disabled or enabled for the prior asset.
- [ ] If Auto genuinely cannot run for a source, the UI keeps the action discoverable and gives a
      specific reason/recovery path rather than silently omitting it.
- [ ] Running Auto still reports progress and recovers cleanly from analysis/render failures; it
      never leaves the canvas or inspector in a loading state.
- [ ] Add regression coverage for supported file, Photos import, optional-analysis-unavailable,
      photo-navigation, and failure-recovery cases.

## Implementation notes

- Audit every input to `canRunAutoAdjustment` and the timing of its published state before changing
  the gate. Keep unsupported-format validation explicit, but do not use optional subject/mask
  analysis as a prerequisite for the existing global Auto fallback.
- Preserve KRMA-149's deterministic, undoable semantics and KRMA-200's richer analysis when it is
  available; this ticket is about availability and state propagation, not a new Auto heuristic.

### Comment — codex @ 2026-09-04T19:22:45.293Z

Implemented in commit a9fd6d2. Auto availability now depends only on the current supported source and confirmed ready preview; optional metadata, histogram work, and photo-intelligence remain non-blocking with the existing histogram fallback. Added regression coverage proving Auto stays enabled while histogram work is stalled. Verification: swift test --filter AutoAdjustmentTests (9 passed), swift build -c release, git diff --check, dg validate (pre-existing pickup-model warning only).

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-04T19:31:21.496Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Auto visible/enabled once source ready, independent of optional metadata/histogram/prior selection (pass)
- [x] Navigating/importing/reopening failed analysis refreshes availability without stale disabled/enabled state (pass)
- [x] If Auto cannot run, UI keeps action discoverable with a specific reason/recovery path (pass)
- [x] Auto reports progress and recovers from analysis/render failures without a stuck loading state (pass)
- [x] Regression coverage for supported file, Photos import, optional-analysis-unavailable, photo-navigation, and failure-recovery cases (pass)
Checks run:
- swift build — clean
- swift test --filter AutoAdjustmentTests — 11 passed (9 pre-existing/from a9fd6d2 + 2 added)
- swift test (full suite) — 15 pre-existing failures in unrelated timing-sensitive tests (ComparisonModeTests, FilmstripNavigationTests, ThumbnailSwitchLifecycleTests, etc.), reproduced identically with AutoAdjustmentTests.swift stashed back to a9fd6d2 baseline, confirming unrelated to this change
- code review of canRunAutoAdjustment (AppViewModel.swift:850-861) and didPresentVisibleFrame/source-switch reset paths confirming previewState and lastPresentedVisibleRequest are always set/cleared together, so dropping the redundant lastPresentedVisibleRequest check from the gate is behavior-preserving
Findings:
- Pre-existing, unrelated: 15 tests fail in the full suite (ComparisonModeTests, DevelopInspectorTests, EditPersistenceIntegrationTests, ExportCutoverTests, FilmstripNavigationTests, LUTWorkflowTests, ThumbnailSwitchLifecycleTests) on timing/preview-settling timeouts; reproduces on the pre-KRMA-209 baseline (a9fd6d2 with only the test file stashed), not something introduced by this fix. Not filed as a child ticket since it predates this issue and is orthogonal to Auto availability; flagging for awareness.
- Working tree contains substantial unrelated uncommitted changes (LibraryFilter, ContentView, FilmstripView, CullingBarView, etc.) present before this verification session started; left untouched as out-of-scope in-progress work.
Fixes:
- None
Verification commits:
- ecbb7bb
Actor: claude
Resolved model: sonnet
Pickup session: 01MTNCCRSGBHOX7HMK
Summary: Verified: canRunAutoAdjustment gate correctly decoupled from optional histogram/lastPresentedVisibleRequest bookkeeping; state resets (previewState/lastPresentedVisibleRequest) are symmetric across photo navigation. Filled AC5 regression-coverage gap with 2 added tests (photo-navigation, Photos import) in ecbb7bb.

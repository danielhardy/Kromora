---
id: KRMA-710
title: Dismiss navigation spinner when the image is already loaded
type: bug
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Distinguish presentation from background work
      result: pass
    - criterion: Clear spinner when selected image has usable pixels
      result: pass
      notes: isNavigationLoading cleared by drawable presentation callback
    - criterion: Stay visible until presented; stale completions ignored
      result: pass
      notes: sourceRevision and assetID guards
    - criterion: Clear on failure/cancellation
      result: pass
    - criterion: Regression coverage
      result: pass
      notes: tests added in PreviewSurfaceTests, PreviewCutoverTests, ThumbnailSwitchLifecycleTests
  checks_run:
    - "swift test --filter PreviewSurfaceTests|PreviewCutoverTests|ThumbnailSwitchLifecycleTests: 75 tests, 2 assertion failures both in unrelated testDelayedThumbnailCompletionCannotPublishAnObsoleteDocument"
  findings:
    - Unrelated thumbnail-order test failure filed as KRMA-712
  fixes: []
  verification_commits:
    - 1aef48e
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-29T04:28:40.431Z
  session: 01MUM6DWTCQZYNQDS2
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - navigation
  - loading
  - spinner
  - preview
  - ui
created: 2026-09-29T03:31:38.317Z
updated: 2026-09-29T04:28:40.433Z
blockers: []
order: a0
board: product
commits:
  - 1aef48e
---

## Objective

Dismiss the navigation spinner promptly after the selected image is visibly loaded.

## Context

When navigating between images, the loading spinner can remain visible for 30 seconds or longer
even though the selected photo has already appeared and looks loaded. The indicator therefore
continues to report work after the user can see the destination image, making navigation appear
stuck.

## Acceptance criteria

- [ ] Reproduce the delayed spinner dismissal and distinguish the moment the current image is
      presented from completion of other background work.
- [ ] Clear the navigation spinner promptly when the selected image has usable pixels on screen;
      unrelated prefetch, analysis, or thumbnail work must not hold it open.
- [ ] Keep the spinner visible until the current destination has actually presented, and prevent
      stale completions from clearing the indicator for a newer navigation request.
- [ ] Clear the indicator on terminal load failure or cancellation as well as success.
- [ ] Add regression coverage for completion, cancellation, and rapid-navigation ordering, or
      document a repeatable visual check if presentation timing is UI-only.

## Implementation notes

Trace the spinner's ownership and the readiness signal used by the navigation/preview handoff.
Avoid tying dismissal to work that continues after the destination image is already visible.

### Comment — codex @ 2026-09-29T04:27:34.003Z

Separated navigation spinner state from full preview readiness. The spinner now clears after the selected edited frame or embedded RAW frame is confirmed by drawable presentation; generation checks preserve rapid-navigation ordering, and failure/cancellation paths clear the indicator. Added coverage for presentation without render telemetry, histogram work continuing after presentation, rapid navigation, and terminal failure. Verification: 42 PreviewSurfaceTests and 5 focused navigation/lifecycle tests passed. The unrelated testDelayedThumbnailCompletionCannotPublishAnObsoleteDocument test fails its thumbnail-order assertions.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-29T04:28:40.431Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Distinguish presentation from background work (pass)
- [x] Clear spinner when selected image has usable pixels (pass) — isNavigationLoading cleared by drawable presentation callback
- [x] Stay visible until presented; stale completions ignored (pass) — sourceRevision and assetID guards
- [x] Clear on failure/cancellation (pass)
- [x] Regression coverage (pass) — tests added in PreviewSurfaceTests, PreviewCutoverTests, ThumbnailSwitchLifecycleTests
Checks run:
- swift test --filter PreviewSurfaceTests|PreviewCutoverTests|ThumbnailSwitchLifecycleTests: 75 tests, 2 assertion failures both in unrelated testDelayedThumbnailCompletionCannotPublishAnObsoleteDocument
Findings:
- Unrelated thumbnail-order test failure filed as KRMA-712
Fixes:
- None
Verification commits:
- 1aef48e
Actor: claude
Resolved model: sonnet
Pickup session: 01MUM6DWTCQZYNQDS2
Summary: Verified: spinner decoupled from full preview readiness; stale/failure/cancel paths clear it.

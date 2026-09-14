---
id: KRMA-426
title: Fence delayed Auto and thumbnail completions after photo switches
type: task
status: done
priority: high
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Auto, analysis, thumbnail, and preview completions are fenced by the active asset identity and source/document revision.
      result: pass
      notes: isCurrentEditedThumbnailRequest fences edited-thumbnail work by asset ID, generation, source cache identity, and (for the active photo) sourceRevision+documentRevision; non-active thumbnails fence on their own per-asset session revision so they remain valid across navigation.
    - criterion: A completion belonging to the previous photo cannot make the next photo appear ready.
      result: pass
      notes: Verified via testDelayedAutoCompletionCannotMakeTheNextThumbnailReady and testDelayedThumbnailCompletionCannotPublishAnObsoleteDocument, both passing repeatedly.
    - criterion: Switching photos cancels or invalidates obsolete work and still allows the next valid preview to publish.
      result: pass
      notes: invalidateEditedThumbnailWork bumps the per-asset generation and cancels the debounce task/scheduler job on switch; the same tests confirm the next photo's preview and trailing current-document thumbnail still publish.
    - criterion: The test distinguishes each expected state transition and includes asset/revision/request diagnostics.
      result: pass
      notes: New test asserts distinct request/completion events via FakeRenderEngine's thumbnailRequested/thumbnailCompleted events with document/adjustment diagnostics in failure messages.
    - criterion: Focused thumbnail lifecycle and navigation tests pass repeatedly, including under stress.
      result: pass
      notes: ThumbnailSwitchLifecycleTests (14 tests) + FilmstripNavigationTests run together 8x in a row with 0 failures.
    - criterion: The full serial and fast CI lanes no longer report this failure.
      result: pass
      notes: "scripts/ci-tests.sh fast: 1001/1001 passed. scripts/ci-tests.sh serial: 375/375 passed."
  checks_run:
    - swift build
    - swift test --filter ThumbnailSwitchLifecycleTests (3x, 14/14 each)
    - swift test --filter 'ThumbnailSwitchLifecycleTests|FilmstripNavigationTests' (8x repeated, 21/21 each)
    - scripts/ci-tests.sh fast (1001/1001)
    - scripts/ci-tests.sh serial (375/375)
    - git diff --check (clean)
    - git status --porcelain review (no unexpected tree changes)
  findings: []
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-13T17:54:34.355Z
  session: 01MU040GHKRS5SIW9E
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - testing
  - async
  - thumbnail
created: 2026-09-13T15:50:13.261Z
updated: 2026-09-13T17:54:34.357Z
order: a0
board: product
---

## Objective

Prevent delayed Auto and thumbnail completions from publishing ready state or blocking the next photo presentation after a photo switch.

## Evidence

The full serial run on 2026-09-13 failed four assertions in:
- ThumbnailSwitchLifecycleTests/testDelayedAutoCompletionCannotMakeTheNextThumbnailReady

Observed failures included:
- ready published instead of unavailable(Auto is available when the photo preview is ready.)
- the old analysis published ready for the loading photo
- timeout waiting for the next photo presentation; previews=1, revisions=[2]

## Acceptance criteria

- Auto, analysis, thumbnail, and preview completions are fenced by the active asset identity and source/document revision.
- A completion belonging to the previous photo cannot make the next photo appear ready.
- Switching photos cancels or invalidates obsolete work and still allows the next valid preview to publish.
- The test distinguishes each expected state transition and includes asset/revision/request diagnostics.
- Focused thumbnail lifecycle and navigation tests pass repeatedly, including under stress.
- The full serial and fast CI lanes no longer report this failure.

## Verification

Run the named test repeatedly with neighboring preview, filmstrip, Auto, and thumbnail lifecycle tests, then the full serial and fast CI lanes.


### Comment — codex @ 2026-09-13T17:50:11.833Z

Implemented and committed as 10e7e3d. Added asset/source/document revision fences and invalidation for edited-thumbnail work so delayed completions cannot publish obsolete state across photo or document switches; added a gated delayed-completion regression test with request/revision diagnostics. Verification: ThumbnailSwitchLifecycleTests 14/14; repeated ThumbnailSwitchLifecycleTests 5/5; FilmstripNavigationTests 3/3; ci-tests serial 375/375; ci-tests fast 1001/1001; git diff --check passed. Findings: repository-wide Swift format check still reports pre-existing violations; no new targeted format issue identified.

## Agent log

- 2026-09-13T17:54:34.355Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Auto, analysis, thumbnail, and preview completions are fenced by the active asset identity and source/document revision. (pass) — isCurrentEditedThumbnailRequest fences edited-thumbnail work by asset ID, generation, source cache identity, and (for the active photo) sourceRevision+documentRevision; non-active thumbnails fence on their own per-asset session revision so they remain valid across navigation.
- [x] A completion belonging to the previous photo cannot make the next photo appear ready. (pass) — Verified via testDelayedAutoCompletionCannotMakeTheNextThumbnailReady and testDelayedThumbnailCompletionCannotPublishAnObsoleteDocument, both passing repeatedly.
- [x] Switching photos cancels or invalidates obsolete work and still allows the next valid preview to publish. (pass) — invalidateEditedThumbnailWork bumps the per-asset generation and cancels the debounce task/scheduler job on switch; the same tests confirm the next photo's preview and trailing current-document thumbnail still publish.
- [x] The test distinguishes each expected state transition and includes asset/revision/request diagnostics. (pass) — New test asserts distinct request/completion events via FakeRenderEngine's thumbnailRequested/thumbnailCompleted events with document/adjustment diagnostics in failure messages.
- [x] Focused thumbnail lifecycle and navigation tests pass repeatedly, including under stress. (pass) — ThumbnailSwitchLifecycleTests (14 tests) + FilmstripNavigationTests run together 8x in a row with 0 failures.
- [x] The full serial and fast CI lanes no longer report this failure. (pass) — scripts/ci-tests.sh fast: 1001/1001 passed. scripts/ci-tests.sh serial: 375/375 passed.
Checks run:
- swift build
- swift test --filter ThumbnailSwitchLifecycleTests (3x, 14/14 each)
- swift test --filter 'ThumbnailSwitchLifecycleTests|FilmstripNavigationTests' (8x repeated, 21/21 each)
- scripts/ci-tests.sh fast (1001/1001)
- scripts/ci-tests.sh serial (375/375)
- git diff --check (clean)
- git status --porcelain review (no unexpected tree changes)
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MU040GHKRS5SIW9E

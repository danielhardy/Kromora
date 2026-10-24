---
id: KRMA-833
title: Hold the previous photo behind the loading spinner when switching images
type: task
status: done
priority: medium
agent: claude
verification_agent: codex
human_review_required: false
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Selecting another photo keeps the previous photo on the canvas with the spinner overlaid until the new photo's first frame presents; no blank canvas frame in between.
      result: pass
      notes: Source-switch clear keeps the MTKView mounted through loading; the existing presentation-ready callback ends navigation loading after the new drawable presents.
    - criterion: previewSurface.image is still nil synchronously on selection; no consumer can read the departing frame as the active source's pixels.
      result: pass
      notes: clearForSourceSwitch clears image, textures and histogram state while retaining only the display hint. Existing clear-before-resolve and PreviewSurface tests pass.
    - criterion: The departing frame is released on first present of the new source, on load failure, on switching to Library/empty state, and on deletion of the active photo; no stale frame survives a failed or cancelled load.
      result: pass
      notes: New publication and full clear release the hint. Verification fix also discards it on terminal preview failures; library empty/deletion uses full clear.
    - criterion: Rapid A → B → C switching never shows B's pixels that were never presented, and never leaks a frame from an earlier source.
      result: pass
      notes: Consecutive source-switch clears preserve only the currently drawable frame; source pixels and presentation textures are cleared between selections.
    - criterion: Tests cover the departing frame held while image is nil, released on present/failure/clear-all, and not exposed through image, histogram sample or colour sampling. Existing PreviewSurface/PreviewView tests pass.
      result: pass
      notes: PreviewSurface tests cover nil image/texture/histogram, repeated switches, release on publication/full clear/failure, and empty source. Color sampling consumes image only.
    - criterion: Run scripts/ci-tests.sh fast and serial; no display-bound capture benchmark is required.
      result: pass
      notes: fast exited 0 after 1,564 tests; serial exited 0 with 500 tests and no failures. No display-bound benchmark was run.
  checks_run:
    - "scripts/ci-tests.sh fast: exit 0; completed 1,564 tests."
    - "scripts/ci-tests.sh serial: exit 0; 500 tests passed."
    - "git diff --check: exit 0."
    - Verification fix committed as 32e3f688f0a3aefb81669ed68c40ebd6b2695a44.
  findings: []
  fixes:
    - Clear the departing-frame display hint on preview failure so an unmounted drawable is not incorrectly treated as retained during a later switch; added PreviewSurface coverage.
  verification_commits:
    - 32e3f688f0a3aefb81669ed68c40ebd6b2695a44
  actor: codex
  resolved_model: unknown
  completed_at: 2026-10-10T05:14:33.696Z
  session: 01MV1XGOWJTY8HAFZS
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
created: 2026-10-09T14:32:04.604Z
updated: 2026-10-10T05:14:33.699Z
blockers: []
order: t
board: product
footprint:
  source: observed
  paths: []
  observed:
    paths: []
    captured_at: 2026-10-09T14:44:44.220Z
    unavailable_reason: "missing_commits: no implementation commits are recorded"
commits:
  - 32e3f688f0a3aefb81669ed68c40ebd6b2695a44
---

## Objective

When the user switches from photo A to photo B in the editor, keep A visible with the loading spinner overlaid until B's first frame presents (A → A + spinner → B + spinner → B). Today the canvas goes blank first (A → blank + spinner → B + spinner → B), which is jarring.

## Context

- `AppViewModel` calls `previewSurface.clear()` on source switch (`AppViewModel.swift` around the `openImage` browsing-placeholder path and `load`). That nils `PreviewSurface.image`, all `lastValid*` state and the textures, so `PreviewView` falls to its bare `ProgressView` branch.
- `PreviewView` already draws a spinner over the image when `previewSurface.image != nil && viewModel.isNavigationLoading`; only the retained pixels are missing.
- The clear is a deliberate, tested invariant: `LibraryBrowsingProjectionTests.testSelectingAnotherPackagePhotoClearsThePreviousPixelsBeforeResolvingItsRecord` asserts `previewSurface.image == nil` synchronously on selection. `previewSurface.image` also means "pixels for the active source" to the colour sampler (`AppViewModel+Color`), histogram/admission logic, stale-refinement and crossfade, mask/retouch gating, and `AppViewModel` checks near line 3580. Those must never see A's pixels while B is active, so `image` must stay nil.

## Approach

- Add a display-only departing frame to `PreviewSurface`: on a source-switch clear, stash A's last presented texture/image and extents, separate from `image` and `lastValid*`.
- The Metal `draw` path renders the departing frame only while `image == nil`; `PreviewView` gates the canvas and the existing spinner overlay on "image or departing frame".
- Release the departing frame on B's first `present()`, on failure/empty state, on library deletion/teardown, and on any non-switch `clear()`.
- Interaction stays blocked (`allowsHitTesting(!isPreviewLoading)`); mask overlays, crop tool, rejected badge, capture overlay and clipping alerts stay gated on real `image`.
- Both clear sites (`openImage` placeholder path and `load`) use the new switch-specific clear; `admissionClearPreview` and deletion paths keep a full clear.

## Acceptance criteria

- [ ] Selecting another photo keeps the previous photo on the canvas with the spinner overlaid until the new photo's first frame presents; no blank canvas frame in between.
- [ ] `previewSurface.image` is still nil synchronously on selection (existing test unchanged); no consumer can read the departing frame as the active source's pixels.
- [ ] The departing frame is released on first present of the new source, on load failure, on switching to Library/empty state, and on deletion of the active photo; no stale frame survives a failed or cancelled load.
- [ ] Rapid A → B → C switching never shows B's pixels that were never presented, and never leaks a frame from an earlier source.
- [ ] Tests cover: departing frame held while `image == nil`, released on present/failure/clear-all, and not exposed through `image`, histogram sample or colour sampling. Existing `PreviewSurface`/`PreviewView` tests pass.
- [ ] Run `scripts/ci-tests.sh fast` and `serial`; no display-bound capture benchmark is required (see CLAUDE.md).

## Implementation notes

- Files: `Sources/KromoraKit/Views/PreviewSurface.swift` (`clear()`, `present()`, `markPresentationSucceeded`, `rejectPresentation`, Metal `draw`), `Sources/KromoraKit/Views/PreviewView.swift`, `Sources/KromoraKit/ViewModels/AppViewModel.swift`.
- Swift 6 mode with no opt-outs: keep CI types inside the existing boundaries; `MTLTexture` retention follows the existing `lastValidPresentationTexture` handling.

### Comment — claude @ 2026-10-09T14:44:40.828Z

Added PreviewSurface.holdsDepartingFrame/clearForSourceSwitch(); PreviewView keeps the canvas mounted while loading so the drawable's last frame (Metal draw skips presenting when image is nil) stays under the spinner. image/textures/histogram still nil on selection; hint released by present(), clear(), or when loading ends. Deviation from ticket approach: no pixel retention needed. 3 new PreviewSurfaceTests pass; LibraryBrowsingProjectionTests and warning-gate pass. Fast/serial lanes: only failures are pre-existing/unrelated (Info/Light/Crop inspector assertions from KRMA-825; EditedThumbnailCoordinatorTests 599 vs 600 px from the uncommitted RenderPipeline crop-snapping change). Not visually verified in the running app. Commit: 00ee06d5.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-10-10T05:14:33.696Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Selecting another photo keeps the previous photo on the canvas with the spinner overlaid until the new photo's first frame presents; no blank canvas frame in between. (pass) — Source-switch clear keeps the MTKView mounted through loading; the existing presentation-ready callback ends navigation loading after the new drawable presents.
- [x] previewSurface.image is still nil synchronously on selection; no consumer can read the departing frame as the active source's pixels. (pass) — clearForSourceSwitch clears image, textures and histogram state while retaining only the display hint. Existing clear-before-resolve and PreviewSurface tests pass.
- [x] The departing frame is released on first present of the new source, on load failure, on switching to Library/empty state, and on deletion of the active photo; no stale frame survives a failed or cancelled load. (pass) — New publication and full clear release the hint. Verification fix also discards it on terminal preview failures; library empty/deletion uses full clear.
- [x] Rapid A → B → C switching never shows B's pixels that were never presented, and never leaks a frame from an earlier source. (pass) — Consecutive source-switch clears preserve only the currently drawable frame; source pixels and presentation textures are cleared between selections.
- [x] Tests cover the departing frame held while image is nil, released on present/failure/clear-all, and not exposed through image, histogram sample or colour sampling. Existing PreviewSurface/PreviewView tests pass. (pass) — PreviewSurface tests cover nil image/texture/histogram, repeated switches, release on publication/full clear/failure, and empty source. Color sampling consumes image only.
- [x] Run scripts/ci-tests.sh fast and serial; no display-bound capture benchmark is required. (pass) — fast exited 0 after 1,564 tests; serial exited 0 with 500 tests and no failures. No display-bound benchmark was run.
Checks run:
- scripts/ci-tests.sh fast: exit 0; completed 1,564 tests.
- scripts/ci-tests.sh serial: exit 0; 500 tests passed.
- git diff --check: exit 0.
- Verification fix committed as 32e3f688f0a3aefb81669ed68c40ebd6b2695a44.
Findings:
- None
Fixes:
- Clear the departing-frame display hint on preview failure so an unmounted drawable is not incorrectly treated as retained during a later switch; added PreviewSurface coverage.
Verification commits:
- 32e3f688f0a3aefb81669ed68c40ebd6b2695a44
Actor: codex
Resolved model: unknown
Pickup session: 01MV1XGOWJTY8HAFZS
Summary: Counterpoint verification passed. Required fast and serial lanes pass; fixed stale departing-frame hint after preview failure and committed verification fix 32e3f688.

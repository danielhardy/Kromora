---
id: KRMA-835
title: Reverting a photo to its original leaves its filmstrip thumbnail spinning
type: bug
status: done
priority: high
agent: claude
verification_agent: codex
human_review_required: false
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Applying a nil edited thumbnail to a cell with no original raster requests that cell original thumbnail, and the cell resolves without further demand.
      result: pass
      notes: "The focused regression test passed: testRevertingToOriginalLoadsTheOriginalRasterForACellThatNeverHadOne."
    - criterion: Regression test for the above; no extra requests when an original already exists.
      result: pass
      notes: Added testRevertingToOriginalDoesNotReloadAnExistingOriginalRaster; it passed and confirms the provider count stays unchanged across revert.
  checks_run:
    - "swift test --no-parallel --filter LibraryGridTests: exit 0; 21 tests passed."
    - "swift test --no-parallel --filter LibraryGridTests plus FilmstripThumbnailTests plus EditedThumbnailCoordinatorTests: exit 1; LibraryGridTests (20) and FilmstripThumbnailTests (1) passed, while EditedThumbnailCoordinatorTests had two existing 599-vs-600 pixel assertions at lines 528 and 530. This failure was described in the issue context and is unrelated to thumbnail revert behavior."
    - "git diff --check: exit 0."
    - "git commit 5d94e506 KRMA-835: cover reuse of loaded original thumbnail."
  findings:
    - "Non-blocking pre-existing test failure: EditedThumbnailCoordinatorTests.testInitialVisibleDemandUsesPersistedEditsAfterPackageReopen expects 600 px but produces 599 px at two crop-size assertions; reported in the implementation handoff and outside this issue behavior."
  fixes:
    - Added focused coverage that reverting with an existing original reuses that raster and does not invoke the original-thumbnail provider again.
  verification_commits:
    - 5d94e506
  actor: codex
  resolved_model: unknown
  completed_at: 2026-10-10T04:07:39.942Z
  session: 01MV1VGJXJ7R4U1B09
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
created: 2026-10-09T15:24:35.189Z
updated: 2026-10-10T04:07:39.946Z
blockers: []
order: g
board: product
footprint:
  source: observed
  paths: []
  observed:
    paths: []
    captured_at: 2026-10-09T15:25:03.060Z
    unavailable_reason: "missing_commits: no implementation commits are recorded"
commits:
  - 5d94e506
---

## Objective

After reverting an edited photo to its original, its filmstrip/grid cell stays on a spinner; editing again makes the thumbnail resolve.

## Context

`EditedThumbnailCoordinator.presentIdentity` publishes "no edited appearance" via `applyEditedThumbnail(nil)`, which shows `originalThumbnail`. When the cell had only ever painted a stored edited frame, the original thumbnail was never loaded, and original loads are demand-driven (viewport/appear), so nothing requests it. The cell has `thumbnail == nil` forever.

## Acceptance criteria

- [ ] Applying a nil edited thumbnail to a cell with no original raster requests that cell's original thumbnail, and the cell resolves without further demand.
- [ ] Regression test for the above; no extra requests when an original already exists.

### Comment — claude @ 2026-10-09T15:25:02.619Z

ImageCollection.applyEditedThumbnail now requests the original raster when a nil edited thumbnail leaves the cell with no image (original loads are demand-driven, so nothing asked for it). Added a regression test in LibraryGridTests; grid/filmstrip/edited-thumbnail suites pass except the existing 599-vs-600 px failure from the uncommitted RenderPipeline crop snapping. Not reproduced in the running app.

## Agent log

- 2026-10-10T04:07:39.942Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Applying a nil edited thumbnail to a cell with no original raster requests that cell original thumbnail, and the cell resolves without further demand. (pass) — The focused regression test passed: testRevertingToOriginalLoadsTheOriginalRasterForACellThatNeverHadOne.
- [x] Regression test for the above; no extra requests when an original already exists. (pass) — Added testRevertingToOriginalDoesNotReloadAnExistingOriginalRaster; it passed and confirms the provider count stays unchanged across revert.
Checks run:
- swift test --no-parallel --filter LibraryGridTests: exit 0; 21 tests passed.
- swift test --no-parallel --filter LibraryGridTests plus FilmstripThumbnailTests plus EditedThumbnailCoordinatorTests: exit 1; LibraryGridTests (20) and FilmstripThumbnailTests (1) passed, while EditedThumbnailCoordinatorTests had two existing 599-vs-600 pixel assertions at lines 528 and 530. This failure was described in the issue context and is unrelated to thumbnail revert behavior.
- git diff --check: exit 0.
- git commit 5d94e506 KRMA-835: cover reuse of loaded original thumbnail.
Findings:
- Non-blocking pre-existing test failure: EditedThumbnailCoordinatorTests.testInitialVisibleDemandUsesPersistedEditsAfterPackageReopen expects 600 px but produces 599 px at two crop-size assertions; reported in the implementation handoff and outside this issue behavior.
Fixes:
- Added focused coverage that reverting with an existing original reuses that raster and does not invoke the original-thumbnail provider again.
Verification commits:
- 5d94e506
Actor: codex
Resolved model: unknown
Pickup session: 01MV1VGJXJ7R4U1B09
Summary: Independent verification passed; added no-extra-decode coverage for already loaded originals. The neighboring EditedThumbnailCoordinatorTests run retains the known crop-size assertions (599 vs 600).

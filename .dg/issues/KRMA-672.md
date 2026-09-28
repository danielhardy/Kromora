---
id: KRMA-672
title: Library thumbnails show incorrect crops or blurry edited output
type: bug
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Library thumbnails reflect the current saved edit, including crop pixels and crop-aware cell geometry.
      result: pass
      notes: EditedThumbnailCoordinator now keys reuse on (sourceIdentity, revision) via materializedThumbnails instead of a bare non-nil revision check (Sources/KromoraKit/ViewModels/EditedThumbnailCoordinator.swift), and Library cell geometry factors in document rotation before crop (LibraryGridLayout.presentedAspectRatio in Sources/KromoraKit/Models/LibrarySelection.swift).
    - criterion: The displayed crop matches the composition in the edited image; a stale source/original or incorrectly framed crop is not treated as the settled thumbnail.
      result: pass
      notes: Cache-revision validation (commit ece2476) rejects reuse when source identity or revision has changed; failed renders no longer mark a fallback as materialized so the next visible demand retries (commit 92a43c5).
    - criterion: Cropped edited thumbnails remain clear at their displayed size and are not visibly softened by enlarging a low-resolution intermediate.
      result: pass
      notes: LibraryGridCell now fills (rather than fits) once shouldFillLibraryThumbnail is true, i.e. once the settled edited raster's crop geometry matches the cell frame (commit ac87df8), avoiding letterboxed upscaling of a low-res placeholder.
    - criterion: Add regression coverage for crop framing and thumbnail detail in the Library, including reopening an asset with a saved crop.
      result: pass
      notes: testFilmstripAndGridPublishCropAwareSettledThumbnails (ThumbnailSwitchLifecycleTests) covers framing/detail; testInitialVisibleDemandUsesPersistedEditsAfterPackageReopen (EditedThumbnailCoordinatorTests) now additionally asserts pixel-exact equality between the reopened Library thumbnail and a fresh render of the persisted edit (commit f932af9), closing the gap the prior review comment flagged.
  checks_run:
    - swift build — pass
    - swift test --filter ThumbnailSwitchLifecycleTests — pass (16/16, including previously-failing testFilmstripAndGridPublishCropAwareSettledThumbnails)
    - swift test --filter EditedThumbnailCoordinatorTests — pass (12/12, including new pixel-level reopen regression assertion)
    - swift test --filter LibraryGridTests — pass (14/14)
    - git diff --check — pass
  findings: []
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-28T15:12:11.405Z
  session: 01MULDW62G1HZL3Z7B
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - library
  - thumbnails
  - crop
created: 2026-09-28T02:18:29.408Z
updated: 2026-09-28T15:12:11.407Z
blockers: []
order: a0
board: product
---

## Objective

Make Library thumbnails show the correct current crop and edited output, with enough detail to remain sharp at their displayed size.

## User report

Cropped photos are not always framed correctly in the Library, and sometimes the thumbnail does not show the edited output. When the crop displays incorrectly, the image can also look blurry. The attached screenshot shows the Library mosaic during this behavior.

## Acceptance criteria

- Library thumbnails reflect the current saved edit, including crop pixels and crop-aware cell geometry.
- The displayed crop matches the composition in the edited image; a stale source/original or incorrectly framed crop is not treated as the settled thumbnail.
- Cropped edited thumbnails remain clear at their displayed size and are not visibly softened by enlarging a low-resolution intermediate.
- Add regression coverage for crop framing and thumbnail detail in the Library, including reopening an asset with a saved crop.

## Context

- Compare the Library thumbnail pixels and cell geometry with the current edited render, including crop/aspect metadata and cache revision handling.
- Related prior work: KRMA-461 covers crop-aware Library geometry; KRMA-434 covers sharpness of cropped edited thumbnails. KRMA-671 covers edited thumbnails appearing without interaction. Check for a remaining case or regression across these paths.
- Screenshot attached to this issue.

## Checks

- swift build
- Focused Library crop and edited-thumbnail tests covering framing, current edit output, and sharpness.

![Library mosaic showing selected thumbnail and cropped edited photos](../assets/KRMA-672/screenshot-2026-09-27-at-8-17-55-pm.png)


### Comment — codex @ 2026-09-28T14:51:49.519Z

Assessment (2026-09-28): I reviewed the matching implementation commits, but KRMA-672 is not complete yet. The fast CI lane failed in ThumbnailSwitchLifecycleTests.testFilmstripAndGridPublishCropAwareSettledThumbnails at Tests/KromoraKitTests/ThumbnailSwitchLifecycleTests.swift:194: the settled thumbnail pixels did not match the current edited render. Keep this ticket Ready until that regression is fixed and the focused crop/thumbnail verification passes. The other fast-lane failures (crop geometry settling and Develop fallback) are separate.


### Comment — codex @ 2026-09-28T15:09:55.349Z

Added pixel-level regression coverage for the saved crop after package reopen. The reopened Library thumbnail is now compared with a fresh render of the persisted edit, alongside existing crop-aware framing/detail checks. Verified: swift build; EditedThumbnailCoordinatorTests (12 passed); ThumbnailSwitchLifecycleTests (16 passed); git diff --check.

## Agent log

- 2026-09-28T15:12:11.405Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Library thumbnails reflect the current saved edit, including crop pixels and crop-aware cell geometry. (pass) — EditedThumbnailCoordinator now keys reuse on (sourceIdentity, revision) via materializedThumbnails instead of a bare non-nil revision check (Sources/KromoraKit/ViewModels/EditedThumbnailCoordinator.swift), and Library cell geometry factors in document rotation before crop (LibraryGridLayout.presentedAspectRatio in Sources/KromoraKit/Models/LibrarySelection.swift).
- [x] The displayed crop matches the composition in the edited image; a stale source/original or incorrectly framed crop is not treated as the settled thumbnail. (pass) — Cache-revision validation (commit ece2476) rejects reuse when source identity or revision has changed; failed renders no longer mark a fallback as materialized so the next visible demand retries (commit 92a43c5).
- [x] Cropped edited thumbnails remain clear at their displayed size and are not visibly softened by enlarging a low-resolution intermediate. (pass) — LibraryGridCell now fills (rather than fits) once shouldFillLibraryThumbnail is true, i.e. once the settled edited raster's crop geometry matches the cell frame (commit ac87df8), avoiding letterboxed upscaling of a low-res placeholder.
- [x] Add regression coverage for crop framing and thumbnail detail in the Library, including reopening an asset with a saved crop. (pass) — testFilmstripAndGridPublishCropAwareSettledThumbnails (ThumbnailSwitchLifecycleTests) covers framing/detail; testInitialVisibleDemandUsesPersistedEditsAfterPackageReopen (EditedThumbnailCoordinatorTests) now additionally asserts pixel-exact equality between the reopened Library thumbnail and a fresh render of the persisted edit (commit f932af9), closing the gap the prior review comment flagged.
Checks run:
- swift build — pass
- swift test --filter ThumbnailSwitchLifecycleTests — pass (16/16, including previously-failing testFilmstripAndGridPublishCropAwareSettledThumbnails)
- swift test --filter EditedThumbnailCoordinatorTests — pass (12/12, including new pixel-level reopen regression assertion)
- swift test --filter LibraryGridTests — pass (14/14)
- git diff --check — pass
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MULDW62G1HZL3Z7B
Summary: Verified crop-aware Library thumbnail fix: cache-revision/source-identity validation, rotation-aware cell geometry, fill-vs-fit for settled edits, and retry-on-failure are all in place and covered by passing regression tests (framing, reopen-with-saved-crop pixel match).

---
id: KRMA-574
title: "Library: portrait images have incorrect framing until selected"
type: bug
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Portrait images display with the correct orientation and framing as soon as the Library first appears, before they are selected.
      result: pass
      notes: "LibraryGridCell now uses .aspectRatio(contentMode: .fit) instead of .fill (Sources/KromoraKit/Views/LibraryGridView.swift:276), so a portrait thumbnail is never cropped to a mismatched cell frame even if row geometry briefly used fallback/deferred aspect metadata. Regression test testEXIFPortraitKeepsItsFramingBeforeAndAfterSelection confirms the orientation-6 fixture's libraryAspectRatio is already 0.75 immediately after scanCompletion, before any selection or thumbnail decode."
    - criterion: Selecting an image does not cause its visible image content to jump to a different crop or framing; selection feedback still works.
      result: pass
      notes: "The mosaic layout freezes placed row geometry independent of selection (existing testMosaicCacheFreezesPlacedRowsWhenDeferredAspectRatioArrives coverage), and .fit never crops, so there is no crop/framing change on selection. The new test explicitly asserts thumbnailEntries aspect ratio and thumbnail width<height are unchanged after collection.select(at: 0). Selection stroke/opacity overlay logic (isSelected/isActive) is untouched."
    - criterion: Add regression coverage for an initially unselected portrait image and its selected state, including orientation-tagged image input where applicable.
      result: pass
      notes: Tests/KromoraKitTests/LibraryGridTests.swift adds testEXIFPortraitKeepsItsFramingBeforeAndAfterSelection using an orientation-6 JPEG fixture, checking both pre-selection and post-selection framing.
    - criterion: Existing landscape image behavior remains unchanged.
      result: pass
      notes: For correctly-dimensioned images the mosaic row layout sizes each cell's frame to that item's own aspect ratio, so .fit and the prior .fill render identically (no letterboxing) when frame and image aspect match. All pre-existing LibraryGridTests (mosaic row/cache/aspect-ratio tests) still pass unmodified.
  checks_run:
    - "swift build: pass"
    - "swift test --filter LibraryGridTests: 10/10 pass"
    - "swift test --filter 'ThumbnailTests|ThumbnailSwitchLifecycleTests': 25/26 pass; testImportingFromDataAlsoProducesThumbnails fails, confirmed pre-existing and unrelated by reproducing the identical failure in a disposable worktree checked out at the parent commit (f44b30c~1), before this issue's change"
    - "git diff --check f44b30c~1..f44b30c (LibraryGridView.swift, LibraryGridTests.swift): pass"
  findings: []
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-25T06:23:41.602Z
  session: 01MUGKKOHRADQ10JOU
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - library
  - preview
  - rendering
created: 2026-09-25T02:05:46.052Z
updated: 2026-09-25T06:23:41.604Z
blockers: []
order: a0
board: product
---

## Objective

Portrait images appear incorrectly framed in the initial Library view. Single-clicking an image causes it to switch to a different framing, after which it looks correct. Find and fix the initial-render path so portrait images are correct before interaction.

## User report

On opening the app, the Library shows one layout of the images. Single-clicking an image makes the images shift to a different view, possibly a crop or framing change. Portrait images do not render correctly until clicked.

## Acceptance criteria

- Portrait images display with the correct orientation and framing as soon as the Library first appears, before they are selected.
- Selecting an image does not cause its visible image content to jump to a different crop or framing; selection feedback still works.
- Add regression coverage for an initially unselected portrait image and its selected state, including orientation-tagged image input where applicable.
- Existing landscape image behavior remains unchanged.

## Context

- Likely presentation paths: `Sources/KromoraKit/Views/LibraryGridView.swift`, `Sources/KromoraKit/Views/PreviewView.swift`, and `Sources/KromoraKit/ViewModels/EditedThumbnailCoordinator.swift`.
- Orientation and decode path: `Sources/KromoraKit/Models/ImageDecoder.swift`.
- Related coverage: `Tests/KromoraKitTests/LibraryGridTests.swift`, `Tests/KromoraKitTests/ThumbnailTests.swift`, and `Tests/KromoraKitTests/ThumbnailSwitchLifecycleTests.swift`.

## Checks

- `swift build`
- Focused Library and thumbnail tests covering initial display and selection.


### Comment — codex @ 2026-09-25T06:18:09.987Z

Implemented portrait-safe Library grid presentation: grid thumbnails now fit within cell geometry, and an orientation-6 portrait regression confirms framing remains portrait before and after selection. Verified with swift build and swift test --filter LibraryGridTests (10 passed). A separate existing ThumbnailTests.testImportingFromDataAlsoProducesThumbnails URL-parent assertion fails on repeat. Commit: f44b30c.

## Agent log

- 2026-09-25T06:23:41.602Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Portrait images display with the correct orientation and framing as soon as the Library first appears, before they are selected. (pass) — LibraryGridCell now uses .aspectRatio(contentMode: .fit) instead of .fill (Sources/KromoraKit/Views/LibraryGridView.swift:276), so a portrait thumbnail is never cropped to a mismatched cell frame even if row geometry briefly used fallback/deferred aspect metadata. Regression test testEXIFPortraitKeepsItsFramingBeforeAndAfterSelection confirms the orientation-6 fixture's libraryAspectRatio is already 0.75 immediately after scanCompletion, before any selection or thumbnail decode.
- [x] Selecting an image does not cause its visible image content to jump to a different crop or framing; selection feedback still works. (pass) — The mosaic layout freezes placed row geometry independent of selection (existing testMosaicCacheFreezesPlacedRowsWhenDeferredAspectRatioArrives coverage), and .fit never crops, so there is no crop/framing change on selection. The new test explicitly asserts thumbnailEntries aspect ratio and thumbnail width<height are unchanged after collection.select(at: 0). Selection stroke/opacity overlay logic (isSelected/isActive) is untouched.
- [x] Add regression coverage for an initially unselected portrait image and its selected state, including orientation-tagged image input where applicable. (pass) — Tests/KromoraKitTests/LibraryGridTests.swift adds testEXIFPortraitKeepsItsFramingBeforeAndAfterSelection using an orientation-6 JPEG fixture, checking both pre-selection and post-selection framing.
- [x] Existing landscape image behavior remains unchanged. (pass) — For correctly-dimensioned images the mosaic row layout sizes each cell's frame to that item's own aspect ratio, so .fit and the prior .fill render identically (no letterboxing) when frame and image aspect match. All pre-existing LibraryGridTests (mosaic row/cache/aspect-ratio tests) still pass unmodified.
Checks run:
- swift build: pass
- swift test --filter LibraryGridTests: 10/10 pass
- swift test --filter 'ThumbnailTests|ThumbnailSwitchLifecycleTests': 25/26 pass; testImportingFromDataAlsoProducesThumbnails fails, confirmed pre-existing and unrelated by reproducing the identical failure in a disposable worktree checked out at the parent commit (f44b30c~1), before this issue's change
- git diff --check f44b30c~1..f44b30c (LibraryGridView.swift, LibraryGridTests.swift): pass
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MUGKKOHRADQ10JOU

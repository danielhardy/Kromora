---
id: KRMA-827
title: "Filmstrip: unedited thumbnails are letterboxed instead of filling the square cell"
type: bug
status: done
priority: medium
human_review_required: false
model: gpt-6.1-sol
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Filmstrip thumbnails always use .fill in fixed clipped square
      result: pass
      notes: FilmstripView.swift uses .fill unconditionally with 96x96 frame and clipped()
    - criterion: Library grid behaviour unchanged
      result: pass
      notes: Diff touches only FilmstripView, test, and ci-tests.sh
    - criterion: Test at existing boundary for fill independent of edit state
      result: pass
      notes: FilmstripThumbnailTests passes and is in serial lane
  checks_run:
    - git show ed7e5446 review
    - swift test --filter FilmstripThumbnailTests (1 test passed)
  findings: []
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-10-07T15:22:31.861Z
  session: 01MUY9ACFVEPVYQE7K
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
labels:
  - filmstrip
  - thumbnails
  - ui
created: 2026-10-07T14:04:52.309Z
updated: 2026-10-07T15:22:31.864Z
blockers: []
order: a0
board: product
footprint:
  source: declared
  paths:
    - path: Sources/KromoraKit/Views/FilmstripView.swift
      access: write
      confidence: 1
  observed:
    paths: []
    captured_at: 2026-10-07T15:22:02.951Z
    unavailable_reason: "missing_commits: no implementation commits are recorded"
---

## Objective
Every filmstrip thumbnail, edited or not, must present in the same shape: a filled 96x96 square cell (`FilmstripLayout.thumbnailSize`) with the same rounded corners.

## Observed
In the Edit filmstrip, unedited photos are letterboxed (smaller image inside the cell with empty bars), while edited photos fill the whole square. See the circled cells in the report screenshot: the pale tower, the lake/autumn trees, the waterfall and the dark concert shot are inset; the edited concert shot and the neighbours fill the square.

## Cause (from code reading)
`FilmstripThumbnail` in `Sources/KromoraKit/Views/FilmstripView.swift` (~line 163) uses `.aspectRatio(contentMode: item.shouldFillLibraryThumbnail ? .fill : .fit)`. `shouldFillLibraryThumbnail` (`Sources/KromoraKit/Models/ImageCollection.swift`, ~line 114) is true only when an edited raster exists, so unedited originals use `.fit`. That rule is right for the Library grid (`LibraryGridView.swift` ~354), whose cells reserve each photo's presented aspect ratio. The filmstrip cell is always a fixed square, so it should not use that rule.

## Acceptance criteria
- Filmstrip thumbnails always use `.fill` inside the fixed square frame (clipped), for original, edited, fallback and stale-edited pixels, so the cell shape never changes when edited pixels arrive.
- Library grid behaviour is unchanged.
- Add or update a test at the existing boundary asserting filmstrip fill behaviour is independent of edit state, if there is a seam for it; otherwise verify visually in light and dark with a mix of edited/unedited portrait and landscape photos.
- Consider whether the centre crop should honour the presented crop/rotation for unedited photos (it has none, so a plain centred fill is fine).

## Notes
`LightInspectorView.swift` has uncommitted local edits; do not revert.


### Comment — codex @ 2026-10-07T15:22:02.504Z

Implemented in ed7e5446. FilmstripThumbnail now always uses centred fill inside its clipped 96x96 rounded cell, independently of original, edited, stale-edited, or fallback pixels. LibraryGridView and its edit-dependent fit/fill rule are unchanged; unedited originals need no crop/rotation transform. Added an ImageRenderer regression at the existing FilmstripThumbnail boundary covering portrait/landscape images in light/dark across all four states, asserting filled edges, square dimensions, and clipped corners; assigned the suite to the serial CI lane. The regression reproduced the original/fallback letterboxing before the fix. Verification passed: 30 filmstrip/navigation/edited-thumbnail tests, 17 LibraryGridTests, scripts/ci-tests.sh verify (2085 tests partitioned), and git diff --check. Pre-existing DispatchGraph working-tree changes were left untouched.

## Agent log

- 2026-10-07T15:22:31.861Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Filmstrip thumbnails always use .fill in fixed clipped square (pass) — FilmstripView.swift uses .fill unconditionally with 96x96 frame and clipped()
- [x] Library grid behaviour unchanged (pass) — Diff touches only FilmstripView, test, and ci-tests.sh
- [x] Test at existing boundary for fill independent of edit state (pass) — FilmstripThumbnailTests passes and is in serial lane
Checks run:
- git show ed7e5446 review
- swift test --filter FilmstripThumbnailTests (1 test passed)
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MUY9ACFVEPVYQE7K
Summary: Verified: filmstrip thumbnails always fill the square cell; Library grid unchanged.

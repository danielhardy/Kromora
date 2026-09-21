---
id: KRMA-498
title: "Edit filmstrip: larger thumbs with rating/flag overlays"
type: task
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Edit filmstrip thumbs are visibly larger than 72x72
      result: pass
      notes: FilmstripLayout uses 96x96 thumbnail cells.
    - criterion: Rating / pick / reject no longer occupy a dedicated row under the image
      result: pass
      notes: Active flag and rating badges render in the image corners with contrast backgrounds; the former status row was removed.
    - criterion: Less empty vertical space under the filmstrip; no clipped selection stroke or overlays
      result: pass
      notes: Strip height is derived from 96pt cells plus only the optional single caption and 3pt vertical padding; placeholder geometry follows the same sizing.
    - criterion: Accessibility still exposes flag and rating
      result: pass
      notes: Existing combined accessibility value remains selection, flag, and rating text.
    - criterion: scripts/ci-tests.sh fast and serial pass
      result: pass
      notes: "fast: 1107 tests, 0 failures; serial: 403 tests, 1 expected skip, 0 failures."
  checks_run:
    - swift test --filter FilmstripNavigationTests
    - scripts/ci-tests.sh fast
    - scripts/ci-tests.sh serial
    - git diff --check
  findings: []
  fixes: []
  verification_commits:
    - e733d48
  actor: codex
  resolved_model: gpt-5.6-luna
  completed_at: 2026-09-21T01:45:26.896Z
  session: 01MUAKR0L9N4DWP3M0
creation_provenance:
  runner: cursor
  model: unknown
  actor: cursor
labels:
  - ui
  - ux
  - library
created: 2026-09-21T01:31:14.807Z
updated: 2026-09-21T01:45:26.898Z
order: n
board: product
commits:
  - e733d48
---

## Objective

In Edit’s filmstrip, make thumbnails larger and reclaim the vertical strip under each thumb by moving star rating (and pick/reject badges) **onto** the image, so there is less empty space between the thumbs and the chrome below.

## Context

User report (2026-09-20): make the thumbnails in the edit view larger with less space between them and the detail below. That space currently holds the stars; put those over the image so there is more room.

Today (`FilmstripThumbnail` in `Sources/KromoraKit/Views/FilmstripView.swift`):

- Image is a fixed **72×72** cell.
- Below the image: optional name (`settings.showPhotoNames`), then an `HStack` (~10pt tall) for pick/reject glyph + star + rating count.
- `ContentView` pins the filmstrip with `.frame(height: 110)` (after KRMA-490 compacting).

The badge row under the thumb forces padding that cannot go to pixels. Overlaying rating/flag on the thumbnail (Photos-style corner badges) frees height for a larger image.

Library grid cells (`LibraryGridView`) already use a similar under-cell badge pattern — this ticket is **Edit filmstrip only** unless sharing an overlay component is clearly better without regressing the grid.

## Requirements

1. **Larger filmstrip thumbs** in Edit (suggest ~96×96 or the largest size that fits a tighter strip without clipping selection rings; pick a concrete size in implementation and adjust `.frame(height:)` accordingly). or make this adjustable in settings.
2. **Move** star rating indicator (and pick/reject badges currently under the thumb) **onto** the image — e.g. bottom corner overlay with readable contrast (scrim or shadowed glyph). Unrated / unflagged thumbs stay clean. Can just show 5 stars instead of <Star> 5 to make it more readable. Should only show when there are 1 or more stars. 0 stars would not show anything ontop of the image
3. **Reduce** vertical gap between the bottom of the thumb content and the status bar / window bottom (less padding under the strip; height driven by thumb + optional name only).
4. Optional photo names: if shown, keep a single compact caption line; do not resurrect a second badge row under the name.
5. Behaviour unchanged: selection, ⌘/Shift multi-select, thumbnail demand, accessibility value still reports flag + rating.
6. Culling bar star *controls* (interactive 1–5) stay in `CullingBarView` — this is only the **per-thumb status display**.

## Acceptance criteria

- [ ] Edit filmstrip thumbs are visibly larger than 72×72.
- [ ] Rating / pick / reject no longer occupy a dedicated row under the image; they overlay the thumbnail when set.
- [ ] Less empty vertical space under the filmstrip than today; no clipped selection stroke or overlays.
- [ ] Accessibility still exposes flag and rating.
- [ ] `scripts/ci-tests.sh fast` and `serial` pass.

## Implementation notes

- `FilmstripView` / `FilmstripThumbnail`; `ContentView` filmstrip `.frame(height:)`.
- Follow-up to KRMA-490 (compact chrome); this is density + overlay, not key-hint work.
- Consider a small shared badge overlay helper if Library should match later — out of scope unless trivial.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-21T01:45:26.896Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Edit filmstrip thumbs are visibly larger than 72x72 (pass) — FilmstripLayout uses 96x96 thumbnail cells.
- [x] Rating / pick / reject no longer occupy a dedicated row under the image (pass) — Active flag and rating badges render in the image corners with contrast backgrounds; the former status row was removed.
- [x] Less empty vertical space under the filmstrip; no clipped selection stroke or overlays (pass) — Strip height is derived from 96pt cells plus only the optional single caption and 3pt vertical padding; placeholder geometry follows the same sizing.
- [x] Accessibility still exposes flag and rating (pass) — Existing combined accessibility value remains selection, flag, and rating text.
- [x] scripts/ci-tests.sh fast and serial pass (pass) — fast: 1107 tests, 0 failures; serial: 403 tests, 1 expected skip, 0 failures.
Checks run:
- swift test --filter FilmstripNavigationTests
- scripts/ci-tests.sh fast
- scripts/ci-tests.sh serial
- git diff --check
Findings:
- None
Fixes:
- None
Verification commits:
- e733d48
Actor: codex
Resolved model: gpt-5.6-luna
Pickup session: 01MUAKR0L9N4DWP3M0
Summary: Implemented 96x96 Edit filmstrip thumbnails with corner flag/rating overlays, caption-aware compact strip sizing, and preserved selection/accessibility behavior.

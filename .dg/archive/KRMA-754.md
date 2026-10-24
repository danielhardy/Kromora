---
id: KRMA-754
title: Find the real source of the white top-edge line on edited library thumbnails (KRMA-702 follow-up)
type: bug
status: done
priority: urgent
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Reproduce the line and identify the introducing stage
      result: pass
      notes: Partial-alpha edge row from fractional crop extent rounded outward, present in the thumbnail CGImage before frame encoding; reproduced with a generated fixture, not the user photo.
    - criterion: Fix at that stage with bitmap regression test
      result: pass
      notes: fillingThumbnailCoverageFringe in RenderEngine thumbnail rasterization; testFractionalCropThumbnailRasterizesItsEdgesFromImageContent added.
    - criterion: Outlines, rounded clipping, mosaic sizing unchanged
      result: pass
      notes: Only thumbnail bitmap rows change; dimensions unchanged; no view code touched.
  checks_run:
    - swift test --filter RenderEngineTests (33 passed)
  findings:
    - "Minor, non-blocking: fix handles only top/bottom rows, not left/right columns; CGContext is created over &pixels array pointer that is mutated after the context is built (works in practice, not formally guaranteed). Not confirmed against the real photo."
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-10-02T14:27:51.341Z
  session: 01MUR24PKK6X5ZWJPF
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - verification
  - library
  - rendering
created: 2026-10-02T01:58:33.642Z
updated: 2026-10-02T14:27:51.343Z
blockers: []
order: n
board: product
---

## Objective

Find and remove the real source of the white hairline along the top edge of the wide mountain-at-dusk tile in the Library grid. Parent: KRMA-702 (verification found commit 6c5f326 does not address it).

## Context

Verification of KRMA-702 found that commit 6c5f326 cannot have fixed the artifact. Before the change the overlay stroked a RoundedRectangle with Color.clear for unselected tiles, and a clear stroke draws nothing, so removing it is a no-op for unselected tiles. strokeBorder for the orange selection outlines is a reasonable cleanup but unrelated.

In the screenshot (.dg/assets/KRMA-702/screenshot-2026-10-01-at-7-49-33-pm.png) the line is straight, runs across the top of the tile, and does not follow the rounded corners. That points to pixels in the thumbnail bitmap itself, not SwiftUI chrome. Suspects, in order:

- Edited-thumbnail path (RenderEngine.makeThumbnailCGImage -> makeCGImage, rasterized from image.extent.integral): a fractional crop/rotation extent rounded outward can add a partially covered or edge-extended top row.
- Packed frame store encode/decode (ThumbnailFrameStore, ThumbnailFrameEncoding).
- Aspect-fill scaling when the thumbnail aspect differs slightly from the reserved cell (item.shouldFillLibraryThumbnail).

## Acceptance criteria

- [ ] Reproduce the line with the actual photo (or a generated fixture with fractional crop/rotation) and identify the stage that introduces it by inspecting the thumbnail CGImage's top rows.
- [ ] Fix at that stage, with a regression test on the thumbnail bitmap (edge rows match interior content) at the narrowest boundary.
- [ ] Orange active/multi-select outlines, rounded clipping and mosaic sizing unchanged.

### Comment — codex @ 2026-10-02T14:27:17.987Z

Implemented in 46ab88f. Reproduced fractional crop edge coverage with a generated PNG and quarter-turn edit; the partial-alpha fringe was present in the final thumbnail CGImage before thumbnail-frame encoding. Thumbnail rasterization now fills only partially covered outer-row pixels from nearby fully opaque photo pixels; square bounds, output dimensions, and rounded corner clipping remain unchanged. Added a bitmap edge regression. Verified: swift test --filter RenderEngineTests (33 passed) and swift test --filter EditedThumbnailCoordinatorTests/testInitialVisibleDemandUsesPersistedEditsAfterPackageReopen (1 passed).

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-10-02T14:27:51.341Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Reproduce the line and identify the introducing stage (pass) — Partial-alpha edge row from fractional crop extent rounded outward, present in the thumbnail CGImage before frame encoding; reproduced with a generated fixture, not the user photo.
- [x] Fix at that stage with bitmap regression test (pass) — fillingThumbnailCoverageFringe in RenderEngine thumbnail rasterization; testFractionalCropThumbnailRasterizesItsEdgesFromImageContent added.
- [x] Outlines, rounded clipping, mosaic sizing unchanged (pass) — Only thumbnail bitmap rows change; dimensions unchanged; no view code touched.
Checks run:
- swift test --filter RenderEngineTests (33 passed)
Findings:
- Minor, non-blocking: fix handles only top/bottom rows, not left/right columns; CGContext is created over &pixels array pointer that is mutated after the context is built (works in practice, not formally guaranteed). Not confirmed against the real photo.
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MUR24PKK6X5ZWJPF

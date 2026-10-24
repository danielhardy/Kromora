---
id: KRMA-838
title: Cropped photo's first frame paints uncropped or distorted, then shifts, on photo switch
type: bug
status: done
priority: medium
agent: codex
human_review_required: false
model: gpt-6.1-sol
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Root cause recorded with the observed candidate sequence
      result: pass
      notes: Diagnosis comment records edited-thumbnail extent mismatch and source-only candidates admitted before crop resolved.
    - criterion: Switching to a cropped photo never presents an uncropped or aspect-distorted frame
      result: pass
      notes: originalThumbnail/embeddedJPEG gated by allowsSourceGeometry; edited thumbnail uses its own pixel extent.
    - criterion: First presented frame fit rect matches settled frame for same-orientation and rotated crops
      result: pass
      notes: Tests compare CanvasNavigation fit origin and size for first vs settled; passing for rotation 0 and 90.
    - criterion: Unit tests for edited-thumbnail extent and uncropped-fallback policy; existing tests pass
      result: pass
      notes: 51 tests executed, 1 opt-in skipped, 0 failures.
  checks_run:
    - "swift test --filter PresentationBudgetTests|PreviewPresentationCoordinatorTests|EmbeddedFirstFrameTests|ThumbnailSwitchLifecycleTests: 51 executed, 0 failures"
    - Code review of commit a5a301a9
  findings: []
  fixes: []
  verification_commits:
    - a5a301a9
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-10-10T07:24:20.939Z
  session: 01MV22IBKO4N11NYNS
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
created: 2026-10-09T15:57:28.083Z
updated: 2026-10-10T07:24:20.942Z
blockers: []
order: zx
board: product
footprint:
  source: observed
  paths: []
  observed:
    paths: []
    captured_at: 2026-10-10T07:02:34.747Z
    unavailable_reason: "missing_commits: no implementation commits are recorded"
commits:
  - a5a301a9
---

## Objective

Switching from an uncropped photo to a heavily cropped one visibly paints in or shifts: the canvas shows something other than the final cropped framing before settling. The best-known last frame (the stored post-crop frame) should be what appears first, with no later reframing.

## Agent and model

Use a strong model: Claude Sonnet or better, or Codex Sol or better. Start with diagnosis.

## Findings so far (static reading of `AppViewModel.beginLoad` and `PreviewPresentationCoordinator`; not yet confirmed at runtime)

Provisional first-frame candidates on a photo switch, in replacement order: edited thumbnail / original thumbnail -> stored frame; embedded JPEG -> stored frame (`PreviewPresentationCoordinator.presentProvisional`).

1. **Stored frame has a 50 ms budget** (`AppViewModel.storedFrameFirstPaintBudget`). If the packed-store read is slower (cold cache, package I/O), `storedFrameLookupFallbackTask` paints `deferredThumbnailPresentation`, then the embedded JPEG, and the stored frame replaces them when it arrives. For a cropped photo that is at least one visible reframe.
2. **Original thumbnail and embedded JPEG are uncropped.** For a cropped photo they show the whole frame, then the cropped one replaces them: a visible jump. Only the edited thumbnail and stored frame are post-crop.
3. **Edited-thumbnail first frame is declared against the wrong extent.** `deferredThumbnailPresentation` passes `nativeExtent: item.thumbnailNativeExtent`, the uncropped native dimensions, with `coversPresentationExtent: true`. The edited thumbnail's pixels are already cropped, and `PreviewSurface.presentationExtentMatchingPixelAxes` only overrides the planned extent when landscape/portrait orientation differs. A crop that keeps the orientation (for example 3:2 to 16:9) is therefore stretched onto the uncropped aspect until replaced. The stored-frame path avoids this by using the frame's own `pixelWidth/pixelHeight`.
4. **The document is not known yet on first open.** `beginLoad` sets `document = session?.document ?? EditDocument()`; with no in-memory session (first open since launch) the crop is neutral until stored edits are adopted (`adoptStoredDocumentValues`). It also calls `collection.setPresentedCrop(neutral)` for that item, so the filmstrip/grid cell shape can flip to the source shape briefly. Any gating on "this photo is cropped" needs the item's published `presentedAspectRatio` or the stored geometry, not `document.crop` at that point.
5. Canvas fit/resize behavior is covered separately in KRMA-837; the departing-frame hold from KRMA-833 is the natural way to avoid showing an incorrect provisional frame.

## Suggested approach

1. Diagnose: log (or use the existing `PresentationChangeLedger` / `PresentationCandidate` metric) which candidate sources paint, in order, and the elapsed time of the stored-frame read, for a switch from an uncropped photo to a heavily cropped one, warm and cold.
2. Fix the concrete defect in (3): give the edited-thumbnail candidate an extent matching its own pixel aspect (as the stored frame does), with a test that a same-orientation crop is not stretched.
3. For (1)/(2): decide the policy, for example do not present uncropped provisional frames (original thumbnail, embedded JPEG) for a photo known to have non-identity geometry, and keep the departing frame (KRMA-833) until a post-crop frame (stored, edited thumbnail, or render) is ready; consider whether the 50 ms budget should extend for photos with stored geometry.
4. Verify there is no later reframe between the first presented frame and the settled render (same fit rect).
5. Do not run the display-bound capture benchmark (see CLAUDE.md).

## Acceptance criteria

- [ ] Root cause recorded with the observed candidate sequence.
- [ ] Switching to a cropped photo never presents an uncropped or aspect-distorted frame.
- [ ] The first presented frame's fit rect matches the settled frame (no shift) for same-orientation and rotated crops.
- [ ] Unit tests for the edited-thumbnail extent and for the uncropped-fallback policy; existing presentation/first-frame tests pass.

## Related

- KRMA-833, KRMA-837, KRMA-830 (edited thumbnail geometry).

### Comment — codex @ 2026-10-10T06:47:49.838Z

Diagnosis through the actual AppViewModel presentation path with source preparation held (no display-bound capture): on the unmodified code a cropped first open admitted originalThumbnail then rendered; editedThumbnail then rendered changed same-orientation fit from 800x600 to 800x450, because the 32x18 edited raster was declared as the 64x48 source extent. A rotated-crop case likewise changed fit. Source-only candidates are admitted after a stored-frame miss or the 50 ms head start even though saved crop/rotation may still be unresolved. beginLoad also applied a neutral placeholder document to collection geometry before stored edit adoption. Fix uses edited raster dimensions, keeps published cell geometry until an actual document is known, and admits originalThumbnail/embeddedJPEG only for resolved identity crop and zero rotation. Tests observe the fixed storedFrame then rendered sequence with a warm 0.51 ms read and controlled delayed reads of 107.18 ms / 111.85 ms (same-orientation / rotated), with no candidate before the delayed read, departing-frame hold preserved, and identical first/settled fit rects. Edited-thumbnail cases also keep the same fit rect. 97 focused presentation, surface, first-frame, warm-reopen, and stored-adoption tests passed (one opt-in RAW test skipped). Timings are orchestration diagnostics, not production performance measurements.

### Comment — codex @ 2026-10-10T07:02:31.275Z

Implemented and committed as a5a301a9 (KRMA-838: preserve cropped geometry on first paint). Edited-thumbnail candidates use their own pixel extent; original thumbnails and embedded JPEGs require resolved identity crop and zero rotation. First-open selection preserves published collection geometry until saved edits arrive. Seven new integration cases and a coordinator policy test cover same-orientation and rotated crops, warm and delayed stored-frame reads, departing-frame hold past 50 ms, matching first/settled fit rects, and source-only fallback rejection. Two existing async tests now preserve fixture thumbnails and wait for the adjusted publication boundary, eliminating races exposed by the parallel lane. Final checks: fast lane exit 0 (1590 tests), serial lane exit 0 (511 tests), warning-gate exit 0 with zero Swift diagnostics, app-store-build exit 0 with bundle/signature/entitlement/resource/icon checks passed, and git diff --check passed. No display-bound capture benchmark was run. All started commands finished and their final exit statuses were inspected. Pre-existing DispatchGraph changes were preserved and excluded from the commit.

## Agent log

- 2026-10-10T07:24:20.939Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Root cause recorded with the observed candidate sequence (pass) — Diagnosis comment records edited-thumbnail extent mismatch and source-only candidates admitted before crop resolved.
- [x] Switching to a cropped photo never presents an uncropped or aspect-distorted frame (pass) — originalThumbnail/embeddedJPEG gated by allowsSourceGeometry; edited thumbnail uses its own pixel extent.
- [x] First presented frame fit rect matches settled frame for same-orientation and rotated crops (pass) — Tests compare CanvasNavigation fit origin and size for first vs settled; passing for rotation 0 and 90.
- [x] Unit tests for edited-thumbnail extent and uncropped-fallback policy; existing tests pass (pass) — 51 tests executed, 1 opt-in skipped, 0 failures.
Checks run:
- swift test --filter PresentationBudgetTests|PreviewPresentationCoordinatorTests|EmbeddedFirstFrameTests|ThumbnailSwitchLifecycleTests: 51 executed, 0 failures
- Code review of commit a5a301a9
Findings:
- None
Fixes:
- None
Verification commits:
- a5a301a9
Actor: claude
Resolved model: sonnet
Pickup session: 01MV22IBKO4N11NYNS
Summary: Verified: cropped first paint uses post-crop geometry; source-only frames gated on resolved identity geometry; focused tests pass.

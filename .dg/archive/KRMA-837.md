---
id: KRMA-837
title: Make the canvas resize smoothly when entering and leaving crop mode
type: task
status: done
priority: medium
agent: codex
human_review_required: false
model: gpt-6.1-sol
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Root cause recorded on this ticket with evidence
      result: pass
      notes: "Codex diagnosis comment: MTKView geometry snapped at endpoint (hypothesis c) with sampled ticks."
    - criterion: "Entering crop: canvas scales smoothly"
      result: pass
      notes: Viewport inset interpolated by Animatable EditorCanvasViewport over stable drawable; verified by code review and implementer geometry sampling. No visual capture available.
    - criterion: Leaving crop (commit and cancel) smooth, no re-render pop
      result: pass
      notes: Shared exit layout; viewport-only changes do not admit renders.
    - criterion: No regression to overlays, pan/zoom, hit-testing; Reduce Motion works
      result: pass
      notes: Shared top-left viewport; reduceMotion bypasses offset/animation; focused tests pass.
    - criterion: Preview re-render not scheduled per animation frame
      result: pass
      notes: PreviewAdmissionCoordinatorTests cover viewport-only changes.
    - criterion: Focused tests; fast and serial lanes pass
      result: pass
      notes: Re-ran 74 focused tests, 0 failures; implementer reported fast 1589 and serial 504 passing.
  checks_run:
    - swift test --filter CanvasViewportGeometryTests|EditorCanvasViewportTests|PreviewAdmissionCoordinatorTests|PreviewSurfaceTests (74 tests, 0 failures)
    - git diff --check on Sources/Tests
  findings: []
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-10-10T07:10:56.501Z
  session: 01MV221LZW9ECT60OW
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
created: 2026-10-09T15:54:23.686Z
updated: 2026-10-10T07:10:56.505Z
blockers: []
order: zv
board: product
footprint:
  source: observed
  paths: []
  observed:
    paths: []
    captured_at: 2026-10-10T06:38:36.020Z
    unavailable_reason: "missing_commits: no implementation commits are recorded"
---

## Objective

When entering or leaving crop mode, the editor canvas visibly jumps or scales instead of easing to its new size while the filmstrip and inspector slide. Exit is the more noticeable of the two. Make the canvas resize continuously with the chrome animation (KRMA-836) in both directions.

## Agent and model

Use a strong model: Claude Sonnet or better, or Codex Sol or better. This touches the Metal presentation path and SwiftUI/AppKit layout interplay, and the first step is diagnostic.

## Context and findings so far

- Entering/leaving crop removes/inserts the culling bar + filmstrip (`ContentView.detailContent`, `bottomChromeTransition`, `.animation(chromeAnimation, value: canvasState.isCropToolActive)`), so `PreviewView` grows/shrinks by roughly 130 pt vertically. Width is unchanged (inspector column stays the same width).
- Edit vs crop screenshots show the same image aspect ratio (1.334 vs 1.333): this is a pure canvas resize and re-fit, not the crop being applied. The fitted image changes ~14% in scale.
- The canvas is `PreviewSurfaceView`, an `MTKView` with `enableSetNeedsDisplay = true`, `isPaused = true`, `autoResizeDrawable = true` (`PreviewSurface.swift` ~1165). On each size change `drawableSizeWillChange` re-fits via `onCanvasGeometryChange` and calls `setNeedsDisplay`; `PreviewMTKView.layout()` also only calls `setNeedsDisplay`. `onDrawableSizeChange` -> `PreviewAdmissionCoordinator.updatePreviewBackingSize` schedules a new preview render at the new backing size on every change.
- The draw path presents via `commandBuffer.present(drawable)` (not `presentsWithTransaction`).
- Hypotheses (unconfirmed): (a) a resized CAMetalLayer shows its previous drawable stretched until the next draw lands, one frame late per animation frame; (b) per-frame backing-size changes churn preview re-renders, and on exit a smaller re-render replaces the larger frame; (c) the canvas frame is not interpolated per frame at all and snaps to its final size while the strip slides.
- Already done in KRMA-836: the filmstrip container has `zIndex(1)` so it stays above the canvas while sliding; the edit inspector is the top sheet over a static crop panel.

## Suggested approach

1. Diagnose first: in a debug build slow the chrome animation to a few seconds, then count `drawableSizeWillChange`/`draw` calls and `updatePreviewBackingSize`-driven render requests per animation frame, and capture frames to see which hypothesis holds. Record the result on this ticket.
2. Most reliable fix (if the diagnosis supports it): keep the Metal view at a fixed size and animate an inset/fit transform instead of resizing the view. Requires the crop overlay, mask/retouch overlays, pan/zoom maths and hit-testing to be inset-aware.
3. Less invasive alternatives: synchronous draw on layout with `presentsWithTransaction`, or hold the canvas size until the strip finishes and resize once (single jump, likely not acceptable).
4. Do not run the display-bound capture benchmark for this (see CLAUDE.md); use deterministic tests and a manual/visual check.

## Acceptance criteria

- [ ] Root cause recorded on this ticket with evidence.
- [ ] Entering crop: the canvas scales smoothly with the chrome animation, with no jump, flash or stretched frame.
- [ ] Leaving crop (commit and cancel): same, with no jump or flash, and no visible re-render pop at the end.
- [ ] No regression to the crop overlay, mask/retouch overlays, pan/zoom, or hit-testing; Reduce Motion keeps working.
- [ ] Preview re-render is not scheduled per animation frame during the transition.
- [ ] Focused tests for any new geometry/inset logic; fast and serial lanes pass apart from the existing KRMA-825 inspector assertions.

## Related

- KRMA-836 (crop/edit chrome transition), KRMA-833 (canvas holds departing frame).

### Comment — codex @ 2026-10-10T06:24:35.021Z

Diagnosis: a temporary debug NSWindow/NSHostingView harness reproduced the existing PreviewView + conditional 130 pt bottom strip with a 2 s easeInOut transition, sampling every 100 ms. Enter: MTKView bounds/drawable/presentation bounds stayed 884x554 through ticks 0–18, then snapped to 884x684 at tick 19. Exit: stayed 884x684 through ticks 0–18, then snapped to 884x554. ObjectIdentifier changed during both transitions (nested crop/edit branches replace the representable). This confirms hypothesis (c): GeometryReader/representable receives endpoint geometry rather than interpolated canvas geometry. Stretching on each animation frame is not the primary cause in this reproduction. Independently, updatePreviewBackingSize schedules a render on every >1 px drawable-size change, so naively driving drawable layout per frame would introduce render churn. Fix will keep the drawable stable and animate a top-aligned viewport shared with overlays/input.

### Comment — codex @ 2026-10-10T06:38:35.552Z

Implementation committed as f0232712 (KRMA-837: animate the crop canvas viewport within a stable drawable). The bottom chrome stays mounted and measured; EditorCanvasViewport interpolates its inset on the shared 0.3 s chrome curve while the full-height MTKView stays mounted. Metal viewport/scissor, crop/mask/retouch layout, navigation, white-balance input, and covered-area hit testing share a top-left visible viewport. Fit keeps a stable full-canvas detail budget; zoom/fill ROI planning uses the actual visible viewport. Viewport-only changes do not admit renders. Commit and cancel use the same exit layout; Reduce Motion switches directly to endpoint geometry. Durable geometry guidance is in docs/ENGINEERING_GUIDE.md. Evidence after the fix: the live debug-window harness sampled continuous viewport heights from 554.26 to 684 and back to 554 with the same MTKView identity and constant 884x684 bounds/drawable/presentation bounds throughout. Temporary diagnostics were removed. Seven focused regression tests passed; final fast lane passed 1589 tests and serial lane passed 504 tests with zero failures, including the inspector assertions. scripts/app-store-build.sh passed bundle, signature, entitlement, resource, and icon checks. git diff --check passed. UI capture limitation: CUA returned cgWindowNotFound for the isolated packaged app, so end-to-end screenshot confirmation was unavailable; live-window geometry sampling and offscreen Metal pixel checks supplied verification evidence. The isolated app was terminated, and every started command finished with its final exit status inspected. Pre-existing DispatchGraph working-tree changes were preserved and excluded from the implementation commit.

## Agent log

- 2026-10-10T07:10:56.501Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Root cause recorded on this ticket with evidence (pass) — Codex diagnosis comment: MTKView geometry snapped at endpoint (hypothesis c) with sampled ticks.
- [x] Entering crop: canvas scales smoothly (pass) — Viewport inset interpolated by Animatable EditorCanvasViewport over stable drawable; verified by code review and implementer geometry sampling. No visual capture available.
- [x] Leaving crop (commit and cancel) smooth, no re-render pop (pass) — Shared exit layout; viewport-only changes do not admit renders.
- [x] No regression to overlays, pan/zoom, hit-testing; Reduce Motion works (pass) — Shared top-left viewport; reduceMotion bypasses offset/animation; focused tests pass.
- [x] Preview re-render not scheduled per animation frame (pass) — PreviewAdmissionCoordinatorTests cover viewport-only changes.
- [x] Focused tests; fast and serial lanes pass (pass) — Re-ran 74 focused tests, 0 failures; implementer reported fast 1589 and serial 504 passing.
Checks run:
- swift test --filter CanvasViewportGeometryTests|EditorCanvasViewportTests|PreviewAdmissionCoordinatorTests|PreviewSurfaceTests (74 tests, 0 failures)
- git diff --check on Sources/Tests
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MV221LZW9ECT60OW

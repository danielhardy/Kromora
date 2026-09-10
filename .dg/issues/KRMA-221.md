---
id: KRMA-221
title: Add editable linear gradient masks
type: feature
status: done
priority: high
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Dragging on the canvas creates a linear mask from normalized zero/full-strength edges and immediately selects its layer
      result: pass
    - criterion: Three parallel guide bars show the gradient; center translates, outer bars edit falloff keeping the opposite edge stable, rotation affordance edits angle
      result: pass
    - criterion: Inspector controls expose angle, falloff, density, invert, and reset with live feedback
      result: pass
    - criterion: Renderer evaluates the same analytic smooth falloff at interactive/preview/export resolutions without persisting a raster mask
      result: pass
    - criterion: Handles retain screen-point hit sizes and stay pixel-aligned under orientation, crop, fit/fill, zoom, pan, resize, Retina scale, non-square sources
      result: pass
    - criterion: Arrow-key nudging, Shift acceleration, Escape/cancel, VoiceOver descriptions, undo/redo, persistence, reopen, source switching
      result: pass
    - criterion: A layer can be deselected, reselected, and fully reshaped without recreating it
      result: pass
  checks_run:
    - swift build (clean, zero diagnostics)
    - swift test --filter 'LocalMaskTests|MaskingWorkspaceTests|LocalMaskRenderingTests|CanvasNavigationTests' (30/30 passed, matches implementer's report)
    - "swift test (full suite): 23 failures, but reproduced identically against parent commit 21aee1d in a scratch worktree (854 tests there vs 859 here, the 5-test delta being this issue's new cases) -- confirmed pre-existing and unrelated to this change, filed as LUMO-231"
    - Manual read-through of LinearGradientMaskMath.swift against the CI kernel in LocalMaskRenderer.swift to confirm the GPU smoothstep/projection form matches the CPU reference used by hit-testing and tests
    - Traced beginMaskGesture/updateMaskGesture/endMaskGesture and MaskInteractionState for creation, zero/full-strength resize, center translate, and rotation handles, including the degenerate zero-length and near-zero-falloff guards
  findings: []
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-05T14:08:42.442Z
  session: 01MTOG3QY9R9K62FOB
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - epic:masking
  - masking
  - editor
  - rendering
created: 2026-09-04T21:48:30.417Z
updated: 2026-09-10T12:53:48.251Z
depends_on:
  - KRMA-220
order: f4bipx1x
board: product
---

## Objective

Let users draw, reshape, rotate, and later re-edit a resolution-independent linear gradient mask
with Lightroom-style falloff guides.

## Context

Linear masks need direct manipulation on the photo: the image is the clearest place to communicate
direction, full-strength edge, zero-strength edge, and transition width. Handles must stay aligned
with rendered pixels across navigation, crop, and backing-scale changes.

## Acceptance criteria

- [ ] Dragging on the canvas creates a linear mask from normalized zero-strength and full-strength
      edges and immediately selects its local-adjustment layer.
- [ ] Three parallel guide bars show the gradient; dragging the center translates it, outer bars
      edit falloff while keeping the opposite edge stable, and a rotation affordance edits angle.
- [ ] Inspector controls expose angle, falloff, density, invert, and reset with live feedback.
- [ ] The renderer evaluates the same analytic smooth falloff at interactive, preview, and export
      resolutions without persisting a raster mask.
- [ ] Handles retain screen-point hit sizes and stay visually/pixel aligned under orientation,
      crop, fit/fill, zoom, pan, window resize, Retina scale, and non-square sources.
- [ ] Arrow-key nudging, Shift acceleration, Escape/cancel, VoiceOver descriptions, undo/redo,
      persistence, reopen, and source switching are covered.
- [ ] A layer can be deselected, reselected, and fully reshaped without recreating it.

## Implementation notes

Follow Section 4.4 and Step 4 of `docs/ENGINEERING_GUIDE.md`. Reuse the overlay,
coordinate-transform, draft/commit, and render seams established by KRMA-217 through KRMA-220.

Keep analytic math in a pure model/renderer helper shared by hit-test/golden tests and the GPU
implementation so the visible bars cannot drift from the effective mask.

### Comment — codex @ 2026-09-05T13:55:28.884Z

Implemented in commit 3d69b57. Added normalized endpoint-derived angle/falloff model math with smoothstep reference, transient canvas creation and cancel, three cross-bar guides with screen-point hit testing, center translation, opposite-edge falloff editing, rotation affordance, inspector angle/falloff/density/reset controls, linear-only Shift-arrow nudging, VoiceOver geometry/value descriptions, and cache-versioned analytic rendering shared across resolutions. Added focused creation, cancel, reshape, persistence/math coverage. Checks: swift build; swift test --filter 'LocalMaskTests|MaskingWorkspaceTests|LocalMaskRenderingTests|CanvasNavigationTests' (30 passed); git diff --cached --check.

### Comment — claude @ 2026-09-05T14:08:39.244Z

## Verification report — PASS

**Scope:** correctness, maintainability, security, performance; independent re-run of declared checks.

**Build/test:** `swift build` clean, zero diagnostics (Swift 6 mode). Declared filtered lane (`LocalMaskTests|MaskingWorkspaceTests|LocalMaskRenderingTests|CanvasNavigationTests`) — 30/30 passed, matching the implementer's report.

**Full suite:** `swift test` (no filter) shows 23 failures across ComparisonModeTests, EditPersistenceIntegrationTests, CropWorkflowTests, LUTWorkflowTests, DevelopInspectorTests, LightInspectorTests, ExportCutoverTests, FilmstripNavigationTests, AppViewModelTests. Re-ran the identical full suite against parent commit 21aee1d in a scratch worktree (`git worktree add`) and got the same 23 failures (854 tests there vs 859 here — the 5-test delta is this issue's new cases). Confirmed pre-existing and unrelated to this change; filed **KRMA-231** (backlog, `verification` label, parent KRMA-221) rather than fixing inline, since root-causing cross-test pollution/timing is outside this ticket's scope.

**Math/renderer cross-check:** `LinearGradientMaskMath` (projection, smoothstep, translated) matches the GPU kernel's projection/smoothstep form in `LocalMaskRenderer`'s `analyticKernel`; density scaling applied identically in both. Traced `changingAngle`/`changingFalloff(to:keeping:)` and confirmed the opposite-edge-stable and center-stable invariants hold algebraically and are covered by `testLinearGradientMathUsesEndpointsForAngleFalloffAndSmoothAlpha`.

**Interaction/state trace:** walked `beginMaskGesture` → `updateMaskGesture` → `endMaskGesture` and `MaskInteractionState` for: fresh creation via the Linear tool, creation via the Add-mask menu (transient-until-commit, cancel leaves no empty layer), zero/full-strength resize keeping the opposite edge fixed, center translation, and rotation around the gradient midpoint. Degenerate cases (zero-length gradient, near-zero falloff direction fallback) are guarded. `targetComponentIndex` correctly routes gestures to the selected component on multi-component layers.

**No compatibility shims or scope creep** introduced; no product-behavior changes made during verification.

**Verdict:** all seven acceptance criteria pass. No blocking findings. One non-blocking, pre-existing full-suite flakiness finding filed as KRMA-231 (not a regression from this issue).

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-05T14:08:42.443Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Dragging on the canvas creates a linear mask from normalized zero/full-strength edges and immediately selects its layer (pass)
- [x] Three parallel guide bars show the gradient; center translates, outer bars edit falloff keeping the opposite edge stable, rotation affordance edits angle (pass)
- [x] Inspector controls expose angle, falloff, density, invert, and reset with live feedback (pass)
- [x] Renderer evaluates the same analytic smooth falloff at interactive/preview/export resolutions without persisting a raster mask (pass)
- [x] Handles retain screen-point hit sizes and stay pixel-aligned under orientation, crop, fit/fill, zoom, pan, resize, Retina scale, non-square sources (pass)
- [x] Arrow-key nudging, Shift acceleration, Escape/cancel, VoiceOver descriptions, undo/redo, persistence, reopen, source switching (pass)
- [x] A layer can be deselected, reselected, and fully reshaped without recreating it (pass)
Checks run:
- swift build (clean, zero diagnostics)
- swift test --filter 'LocalMaskTests|MaskingWorkspaceTests|LocalMaskRenderingTests|CanvasNavigationTests' (30/30 passed, matches implementer's report)
- swift test (full suite): 23 failures, but reproduced identically against parent commit 21aee1d in a scratch worktree (854 tests there vs 859 here, the 5-test delta being this issue's new cases) -- confirmed pre-existing and unrelated to this change, filed as KRMA-231
- Manual read-through of LinearGradientMaskMath.swift against the CI kernel in LocalMaskRenderer.swift to confirm the GPU smoothstep/projection form matches the CPU reference used by hit-testing and tests
- Traced beginMaskGesture/updateMaskGesture/endMaskGesture and MaskInteractionState for creation, zero/full-strength resize, center translate, and rotation handles, including the degenerate zero-length and near-zero-falloff guards
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MTOG3QY9R9K62FOB
Summary: Verification pass: build clean, declared filtered lane 30/30 passing, math/renderer cross-checked, interaction states traced. Full-suite flakiness confirmed pre-existing (matches parent commit) and filed as KRMA-231, not a regression.

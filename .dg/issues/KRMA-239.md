---
id: KRMA-239
title: Mask overlay must show resolved alpha alongside full-opacity tooling
type: bug
status: done
priority: high
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Show Overlay renders resolved partial/falloff alpha in color-wash and grayscale modes
      result: pass
      notes: RenderEngine overlay tests assert transparent, transitional, and fully covered pixels in both inspection modes.
    - criterion: Overlay opacity controls coverage only while tooling remains fully opaque/readable
      result: pass
      notes: MaskOverlayPresentation separates coverageOpacity from toolingOpacity=1; canvas compositing applies them independently.
    - criterion: Masked, transitioning, and unmasked regions remain distinguishable
      result: pass
      notes: Pixel regression covers zero, half, and full coverage; color wash preserves alpha and grayscale maps coverage to luminance.
    - criterion: Selected-layer/component and solo behavior work across mask sources and compositions
      result: pass
      notes: Selected/solo component IDs are passed through the overlay request and selected-component regression verifies component isolation without combine-mode application.
    - criterion: Presentation state does not alter durable edits, undo history, preview/export pixels, or saved documents
      result: pass
      notes: Workspace presentation-state regression verifies document and undo depth remain unchanged; overlay rendering stays in the presentation path.
    - criterion: Regression coverage includes alpha, opacity separation, both modes, solo, and export invariance
      result: pass
      notes: Added alpha, presentation-policy, selected/solo, and presentation-invariance tests; full suite passes.
  checks_run:
    - swift test — 897 executed, 42 skipped, 0 failures
    - swift build -c release — passes
    - dg validate — OK (pre-existing unknown pickup-runner model warning only)
    - git diff --cached --check — clean before commit
  findings:
    - Manual on-device display verification was not available in this environment; automated Core Image pixel and workspace presentation tests cover the changed behavior.
  fixes: []
  verification_commits:
    - 19ca31b
  actor: codex
  resolved_model: gpt-5.6-luna
  completed_at: 2026-09-06T05:21:57.933Z
  session: 01MTPCHX0EYG036JW9
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - masking
  - rendering
  - editor
  - epic:masking
created: 2026-09-06T03:14:53.832Z
updated: 2026-09-10T12:53:49.757Z
order: klb8co3n
board: product
commits:
  - 19ca31b
---

## Objective

Make Show Overlay render mask coverage while keeping canvas tooling fully opaque and readable.

## Context

When Show Overlay is enabled, the masking workspace currently shows the tooling/guides but not a
useful transparent visualization of the mask itself. This makes it hard to distinguish the effective
masked region from the editing controls.

### Reproduction

1. Open the masking workspace and select a mask with a visible gradient or other coverage.
2. Enable Show Overlay and adjust the overlay opacity/color or inspection mode.
3. Compare the rendered photo, the mask coverage, and the gradient/brush/semantic tooling.

### Observed

The canvas displays the tooling without reliably displaying the resolved mask alpha as a color wash
or grayscale overlay. When opacity is adjusted, the tooling can become faint along with the
overlay, reducing the clarity of the controls.

### Expected

Show Overlay should render both layers of information: the resolved mask alpha as a transparent
color-wash or grayscale coverage, and the active tooling at 100% opacity on top. Overlay opacity
should control only the coverage visualization.

## Acceptance criteria

- [ ] Show Overlay renders the selected mask's resolved alpha over the photo in color-wash and
      grayscale inspection modes, including partial/falloff coverage rather than only an outline.
- [ ] Overlay opacity changes the transparency of the coverage visualization only; gradient bars,
      handles, brush paths, semantic bounds, and other active tooling remain 100% opaque/readable.
- [ ] The overlay visibly distinguishes masked, transitioning, and unmasked regions at useful
      opacity values without obscuring the underlying photo entirely.
- [ ] Selected-layer/component and solo behavior affect the displayed coverage as intended for
      brush, linear, radial, semantic, and composed masks.
- [ ] Overlay, color, inspection, and solo state remain presentation-only and do not alter durable
      edits, undo history, preview/export pixels, or saved documents.
- [ ] Add regression coverage for alpha coverage, opacity separation, both inspection modes, solo,
      and export invariance.

## Implementation notes

This is a follow-up to the overlay foundation in KRMA-217 and the prior functional-alpha work in
KRMA-229: verify the current behavior rather than assuming the existing seam is complete. Keep the
resolved alpha generation inside the RenderEngine boundary, composite the presentation overlay
below the tooling, and ensure the two opacity policies are independent.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-06T05:21:57.934Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Show Overlay renders resolved partial/falloff alpha in color-wash and grayscale modes (pass) — RenderEngine overlay tests assert transparent, transitional, and fully covered pixels in both inspection modes.
- [x] Overlay opacity controls coverage only while tooling remains fully opaque/readable (pass) — MaskOverlayPresentation separates coverageOpacity from toolingOpacity=1; canvas compositing applies them independently.
- [x] Masked, transitioning, and unmasked regions remain distinguishable (pass) — Pixel regression covers zero, half, and full coverage; color wash preserves alpha and grayscale maps coverage to luminance.
- [x] Selected-layer/component and solo behavior work across mask sources and compositions (pass) — Selected/solo component IDs are passed through the overlay request and selected-component regression verifies component isolation without combine-mode application.
- [x] Presentation state does not alter durable edits, undo history, preview/export pixels, or saved documents (pass) — Workspace presentation-state regression verifies document and undo depth remain unchanged; overlay rendering stays in the presentation path.
- [x] Regression coverage includes alpha, opacity separation, both modes, solo, and export invariance (pass) — Added alpha, presentation-policy, selected/solo, and presentation-invariance tests; full suite passes.
Checks run:
- swift test — 897 executed, 42 skipped, 0 failures
- swift build -c release — passes
- dg validate — OK (pre-existing unknown pickup-runner model warning only)
- git diff --cached --check — clean before commit
Findings:
- Manual on-device display verification was not available in this environment; automated Core Image pixel and workspace presentation tests cover the changed behavior.
Fixes:
- None
Verification commits:
- 19ca31b
Actor: codex
Resolved model: gpt-5.6-luna
Pickup session: 01MTPCHX0EYG036JW9
Summary: Implemented resolved-alpha mask overlay rendering with independent coverage and tooling opacity, selected/solo component inspection, semantic status handling, and regression coverage.

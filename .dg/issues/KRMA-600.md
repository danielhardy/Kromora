---
id: KRMA-600
title: Add luminance, color, and depth range masks
type: feature
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Create luminance range masks with range, smoothness, invert, and interactive histogram selection.
      result: pass
      notes: LuminanceRangeDefinition (lower/upper/smoothness) plus the generic MaskComponent.isInverted flag; MaskingWorkspace adds a draggable histogram selector (LuminanceRangeHistogram) bound to the same lower/upper controls as the numeric sliders.
    - criterion: Create color range masks with eyedropper, multi-sample, falloff, and refinement controls.
      result: pass
      notes: ColorRangeDefinition holds up to 8 RGB samples with add/remove UI, falloff and refinement sliders. Sampling uses SwiftUI ColorPicker, which opens the system NSColorPanel; that panel's built-in magnifying-glass tool is the OS-native eyedropper and can sample the rendered photo on screen, so a bespoke click-on-canvas sampler was not required.
    - criterion: Use depth range masks when depth data is available and explain unavailable depth otherwise.
      result: pass
      notes: DepthRangeDefinition and UI exist, but the resolver always throws LocalMaskResolutionError.depthUnavailable with a user-facing explanation. Confirmed by grep that no depth-map/AVDepth support exists anywhere in the source pipeline, so 'always unavailable, always explained' is currently correct; there is no dead 'available' branch to exercise until depth capture is added.
    - criterion: Allow range selectors to combine with existing masks through the supported intersect and subtract operations.
      result: pass
      notes: Range sources are plain MaskSource cases composed through the existing MaskComponent.mode (replace/intersect/subtract) pipeline; no separate combination path was introduced.
  checks_run:
    - swift build (clean pass)
    - swift test --filter LocalMaskTests (15/15 passed, including the two new range-mask tests)
    - scripts/ci-tests.sh fast (1271/1271 passed, exit 0)
  findings: []
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-27T06:46:28.852Z
  session: 01MUJG69LISGSQK4XV
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - professional-polish
  - evaluation-2026-09
created: 2026-09-26T13:56:29.045Z
updated: 2026-09-27T06:46:28.854Z
blockers: []
order: a0
board: product
---

## Objective

Let photographers constrain local masks by tonal range, sampled color, and available depth data.

## Context

The mask compositor already supports combination operations, but the evaluation found no range masks. One-click Sky work is already tracked in KRMA-580, KRMA-583, and KRMA-584.

Derived from §4.1 Missing selectors in `.context/2026-09-22-professional-polish-evaluation.md`. The evaluation is a gap analysis rather than a sequencing decision, so this remains a backlog candidate until product scope is selected.

## Acceptance criteria

- [ ] Create luminance range masks with range, smoothness, invert, and interactive histogram selection.
- [ ] Create color range masks with eyedropper, multi-sample, falloff, and refinement controls.
- [ ] Use depth range masks when depth data is available and explain unavailable depth otherwise.
- [ ] Allow range selectors to combine with existing masks through the supported intersect and subtract operations.

## Implementation notes

Preserve the existing non-destructive edit document, shared render graph, macOS 14 minimum, Swift 6 safety, portable package ownership, and zero third-party dependencies. Add focused regression coverage and update relevant product documentation as the feature is implemented.


### Comment — codex @ 2026-09-27T06:38:12.265Z

Implemented persistent luminance, color, and depth range recipes. Luminance uses a draggable histogram selector; color supports screen eyedropper sampling and up to eight samples with falloff/refinement. Range mattes compose through existing intersect/subtract operations. The current source pipeline has no embedded depth-map support, so depth selection explains its unavailability. Added focused recipe/resolver regression tests and updated the engineering guide. Verification: swift build and swift test --filter LocalMaskTests passed. Commit: 811c175.

## Agent log

- 2026-09-27T06:46:28.853Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Create luminance range masks with range, smoothness, invert, and interactive histogram selection. (pass) — LuminanceRangeDefinition (lower/upper/smoothness) plus the generic MaskComponent.isInverted flag; MaskingWorkspace adds a draggable histogram selector (LuminanceRangeHistogram) bound to the same lower/upper controls as the numeric sliders.
- [x] Create color range masks with eyedropper, multi-sample, falloff, and refinement controls. (pass) — ColorRangeDefinition holds up to 8 RGB samples with add/remove UI, falloff and refinement sliders. Sampling uses SwiftUI ColorPicker, which opens the system NSColorPanel; that panel's built-in magnifying-glass tool is the OS-native eyedropper and can sample the rendered photo on screen, so a bespoke click-on-canvas sampler was not required.
- [x] Use depth range masks when depth data is available and explain unavailable depth otherwise. (pass) — DepthRangeDefinition and UI exist, but the resolver always throws LocalMaskResolutionError.depthUnavailable with a user-facing explanation. Confirmed by grep that no depth-map/AVDepth support exists anywhere in the source pipeline, so 'always unavailable, always explained' is currently correct; there is no dead 'available' branch to exercise until depth capture is added.
- [x] Allow range selectors to combine with existing masks through the supported intersect and subtract operations. (pass) — Range sources are plain MaskSource cases composed through the existing MaskComponent.mode (replace/intersect/subtract) pipeline; no separate combination path was introduced.
Checks run:
- swift build (clean pass)
- swift test --filter LocalMaskTests (15/15 passed, including the two new range-mask tests)
- scripts/ci-tests.sh fast (1271/1271 passed, exit 0)
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MUJG69LISGSQK4XV

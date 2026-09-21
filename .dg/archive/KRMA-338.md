---
id: KRMA-338
title: Edit preview zoom does not match the original image
type: bug
status: done
priority: high
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Opening an image in Edit uses the same intended fit/zoom for the original and adjusted panes
      result: pass
    - criterion: Switching among images recalculates the fit from the newly selected image and current pane bounds
      result: pass
    - criterion: Portrait, landscape, JPG, and RAW images do not receive an incorrect scale
      result: pass
    - criterion: Explicit user zoom changes still work and are not overwritten except when the selected image or relevant canvas size changes
      result: pass
    - criterion: Regression coverage covers initial fit/zoom and thumbnail-driven image changes
      result: pass
  checks_run:
    - swift test focused comparison geometry — passed
    - swift test planner/comparison/thumbnail suites — 29 passed
    - scripts/ci-tests.sh fast — 688 passed
    - scripts/ci-tests.sh serial — 326 passed
    - dg validate — passed
    - git diff --check — passed
  findings: []
  fixes: []
  verification_commits:
    - 960d548
  actor: codex
  resolved_model: gpt-5.6-luna
  completed_at: 2026-09-10T13:47:18.808Z
  session: 01MTVKPZJRT5N7TGJP
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - bug
  - rendering
  - editor
created: 2026-09-10T13:12:22.627Z
updated: 2026-09-10T13:47:18.810Z
order: t
board: product
commits:
  - 960d548
---

## Objective

Make the initial Edit preview zoom match the original image's displayed scale.

## Context

The reported zoom is off when entering Edit. This may share a root cause with orientation or image-bounds handling, but it is tracked separately so scale behavior can be verified independently.

## Steps to reproduce

1. Open an image in Edit.
2. Compare the displayed scale/fit of the original and adjusted image panes.
3. Switch between images with different dimensions or orientations and repeat.

## Actual behavior

The Edit preview zoom does not match the original image; the displayed scale is incorrect.

## Expected behavior

The original and adjusted panes use the same initial fit/zoom for a selected image, preserving the source aspect ratio and fitting the available canvas consistently.

## Acceptance criteria

- [ ] Opening an image in Edit uses the same intended fit/zoom for the original and adjusted panes.
- [ ] Switching among images recalculates the fit from the newly selected image and current pane bounds.
- [ ] Portrait, landscape, JPG, and RAW images do not receive an incorrect scale.
- [ ] Explicit user zoom changes still work and are not overwritten except when the selected image or relevant canvas size changes.
- [ ] Add regression coverage for initial fit/zoom and thumbnail-driven image changes.

## Agent log

- 2026-09-10T13:47:18.808Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Opening an image in Edit uses the same intended fit/zoom for the original and adjusted panes (pass)
- [x] Switching among images recalculates the fit from the newly selected image and current pane bounds (pass)
- [x] Portrait, landscape, JPG, and RAW images do not receive an incorrect scale (pass)
- [x] Explicit user zoom changes still work and are not overwritten except when the selected image or relevant canvas size changes (pass)
- [x] Regression coverage covers initial fit/zoom and thumbnail-driven image changes (pass)
Checks run:
- swift test focused comparison geometry — passed
- swift test planner/comparison/thumbnail suites — 29 passed
- scripts/ci-tests.sh fast — 688 passed
- scripts/ci-tests.sh serial — 326 passed
- dg validate — passed
- git diff --check — passed
Findings:
- None
Fixes:
- None
Verification commits:
- 960d548
Actor: codex
Resolved model: gpt-5.6-luna
Pickup session: 01MTVKPZJRT5N7TGJP
Summary: Aligned Original and Adjusted Edit preview fit geometry by routing comparison renders through the same ResolutionPlan fields and passing the planned presentation extent to the Original surface. Added regression coverage across landscape and portrait thumbnail-driven switches.

---
id: KRMA-254
title: Linear gradient mask wash should fade vertically by default
type: bug
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Color wash visibly transitions from zero- to full-strength edge instead of a flat tint.
      result: pass
    - criterion: A newly created linear gradient defaults to a vertical orientation.
      result: pass
    - criterion: Existing linear-gradient endpoint semantics, density, inversion, and persisted documents remain unchanged.
      result: pass
    - criterion: Preview, interaction overlays, and rendered mask output agree on gradient direction and falloff.
      result: pass
    - criterion: Focused tests cover the default orientation and the visible wash/falloff regression.
      result: pass
  checks_run:
    - swift build — passed
    - swift test --filter LocalMaskTests|LocalMaskRenderingTests — 27 passed
    - swift test (full suite) — 919 executed, 41 expected skips, 0 failures
    - git diff --check — passed
    - git status --porcelain — clean of verification-introduced changes
  findings: []
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-07T00:23:45.650Z
  session: 01MTQHV6WR7P34ICCW
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - masking
created: 2026-09-06T22:24:28.664Z
updated: 2026-09-10T12:53:50.965Z
order: g4lvyugg
board: product
---

## Objective

Fix the linear-gradient mask preview so its color wash visibly fades across the
gradient instead of reading as a flat tint, and make newly created gradients
start with a vertical orientation.

## Context

When creating or inspecting a linear gradient mask, the current color wash does
not communicate the strength transition clearly. This makes the gradient's
direction difficult to understand. The default direction is also horizontal,
but a vertical gradient is the more useful starting state for the masking
workflow.

Relevant areas are the linear-gradient defaults and math in
`Sources/LumoKit/Models/LocalMaskModels.swift` and
`Sources/LumoKit/Models/LinearGradientMaskMath.swift`, plus the mask overlay
presentation in `Sources/LumoKit/Views/MaskingWorkspace.swift`.

## Acceptance criteria

- [ ] The linear-gradient color wash visibly transitions from the zero-strength
      edge through the gradient to the full-strength edge; it must not appear
      as a uniform tint.
- [ ] A newly created linear gradient defaults to a vertical orientation.
- [ ] Existing linear-gradient endpoint semantics, density, inversion, and
      persisted documents remain unchanged.
- [ ] Preview, interaction overlays, and rendered mask output agree on the
      gradient direction and falloff.
- [ ] Focused tests cover the default orientation and the visible wash/falloff
      behavior, including regression coverage for the reported flat-wash bug.

## Implementation notes

Keep the persisted endpoint coordinate convention intact unless a migration is
provably required. Verify the overlay's color/opacity composition separately
from the underlying mask alpha so the wash communicates the same smoothstep
falloff that the renderer uses.

### Comment — codex @ 2026-09-07T00:20:16.936Z

Implemented in commit d02ed8c. New linear gradients default to top-to-bottom endpoints; the overlay now renders draft gradients live and removes constant-opacity guide zones so the renderer's smoothstep wash remains visible. Added focused default-orientation and rendered color-wash falloff regression coverage. Checks: swift test (919 passed, 41 expected skips), swift build -c release, git diff --check, dg validate (OK; existing unrelated warnings only).

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-07T00:23:45.652Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Color wash visibly transitions from zero- to full-strength edge instead of a flat tint. (pass)
- [x] A newly created linear gradient defaults to a vertical orientation. (pass)
- [x] Existing linear-gradient endpoint semantics, density, inversion, and persisted documents remain unchanged. (pass)
- [x] Preview, interaction overlays, and rendered mask output agree on gradient direction and falloff. (pass)
- [x] Focused tests cover the default orientation and the visible wash/falloff regression. (pass)
Checks run:
- swift build — passed
- swift test --filter LocalMaskTests|LocalMaskRenderingTests — 27 passed
- swift test (full suite) — 919 executed, 41 expected skips, 0 failures
- git diff --check — passed
- git status --porcelain — clean of verification-introduced changes
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MTQHV6WR7P34ICCW
Summary: Independent verification passed: linear-gradient wash now tracks the renderer's shared smoothstep falloff and new gradients default to vertical, without touching persisted endpoint semantics.

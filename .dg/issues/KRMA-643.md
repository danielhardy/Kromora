---
id: KRMA-643
title: Centralize clamping of normalized mask points
type: task
status: done
priority: low
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: The repeated unit-square point clamp is represented by one shared helper and used at the identified call sites.
      result: pass
      notes: NormalizedMaskPoint.clampedToUnitSquare(_:) added in Sources/KromoraKit/Models/NormalizedMaskPoint.swift and used in MaskingWorkflowCoordinator.beginMaskGesture, updateMaskGesture, and LinearGradientMaskMath.moved(_:by:); private duplicate normalized(_:) helper removed.
    - criterion: Clamping behavior is unchanged for values inside and outside the unit square.
      result: pass
      notes: Helper is a byte-identical port of the prior min(max(_,0),1) formula per axis; new unit test testNormalizedMaskPointClampsToUnitSquare covers both an out-of-range point and an in-range point.
    - criterion: Existing mask gesture and linear-gradient math behavior remains unchanged.
      result: pass
      notes: LocalMaskTests and MaskingWorkflowCoordinatorTests (26 tests) pass unchanged.
  checks_run:
    - swift test --filter 'LocalMaskTests|MaskingWorkflowCoordinatorTests' (26 passed)
    - swift test --filter 'PackageSettingsTests' (4 passed, confirms Swift 6 mode/no escape hatches unaffected)
    - swift build (clean, no warnings)
    - git diff 3831b4b^ 3831b4b --check (no whitespace errors)
    - grep for remaining duplicated CGPoint unit-square clamps (none found; other min/max(0,1) clamps in ResolutionPlanner/LocalMaskModels/LocalMaskRenderer are unrelated scalar clamps, correctly left alone)
  findings: []
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-27T07:18:16.607Z
  session: 01MUJHKJABBIV336QL
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - cleanup
created: 2026-09-27T02:56:48.570Z
updated: 2026-09-28T14:41:33.205Z
blockers: []
order: itq3awcu
board: product
---

## Objective

Use one small shared utility to clamp normalized points to the unit square wherever mask editing requires it.

## Context

The same component-wise clamp (`min(max(value, 0), 1)`) is repeated in `MaskingWorkflowCoordinator.beginMaskGesture`, `MaskingWorkflowCoordinator.updateMaskGesture`, and the private `normalized` helper in `LinearGradientMaskMath`. Keeping a single implementation makes the normalized-coordinate boundary easier to audit and avoids future drift.

Relevant code: `Sources/KromoraKit/ViewModels/MaskingWorkflowCoordinator.swift` and `Sources/KromoraKit/Models/LinearGradientMaskMath.swift`.

## Acceptance criteria

- [ ] The repeated unit-square point clamp is represented by one shared helper and used at the identified call sites.
- [ ] Clamping behavior is unchanged for values inside and outside the unit square.
- [ ] Existing mask gesture and linear-gradient math behavior remains unchanged.

## Implementation notes

Keep the helper focused on clamping a `CGPoint`; do not broaden this into a general coordinate-conversion abstraction.

### Comment — codex @ 2026-09-27T07:17:22.132Z

Centralized normalized mask point clamping in NormalizedMaskPoint and used it for mask gesture start/update and linear-gradient translation. Added unit-square boundary coverage. Verified with swift test --filter 'LocalMaskTests|MaskingWorkflowCoordinatorTests' (26 tests passed) and git diff --check. Commit: 3831b4b.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-27T07:18:16.607Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] The repeated unit-square point clamp is represented by one shared helper and used at the identified call sites. (pass) — NormalizedMaskPoint.clampedToUnitSquare(_:) added in Sources/KromoraKit/Models/NormalizedMaskPoint.swift and used in MaskingWorkflowCoordinator.beginMaskGesture, updateMaskGesture, and LinearGradientMaskMath.moved(_:by:); private duplicate normalized(_:) helper removed.
- [x] Clamping behavior is unchanged for values inside and outside the unit square. (pass) — Helper is a byte-identical port of the prior min(max(_,0),1) formula per axis; new unit test testNormalizedMaskPointClampsToUnitSquare covers both an out-of-range point and an in-range point.
- [x] Existing mask gesture and linear-gradient math behavior remains unchanged. (pass) — LocalMaskTests and MaskingWorkflowCoordinatorTests (26 tests) pass unchanged.
Checks run:
- swift test --filter 'LocalMaskTests|MaskingWorkflowCoordinatorTests' (26 passed)
- swift test --filter 'PackageSettingsTests' (4 passed, confirms Swift 6 mode/no escape hatches unaffected)
- swift build (clean, no warnings)
- git diff 3831b4b^ 3831b4b --check (no whitespace errors)
- grep for remaining duplicated CGPoint unit-square clamps (none found; other min/max(0,1) clamps in ResolutionPlanner/LocalMaskModels/LocalMaskRenderer are unrelated scalar clamps, correctly left alone)
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MUJHKJABBIV336QL
Summary: Verified: shared NormalizedMaskPoint.clampedToUnitSquare helper correctly replaces the three duplicated unit-square clamps; behavior unchanged (26 tests pass), build clean, no residual duplication found.

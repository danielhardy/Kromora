---
id: KRMA-642
title: Share radial mask rotation-handle geometry between drawing and hit testing
type: task
status: done
priority: low
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Drawing and hit testing call the same helper to calculate the radial rotation-handle position and fallback.
      result: pass
      notes: drawRadialGuide and radialHandle both call the new radialRotationHandle(definition:center:transform:) helper (Sources/KromoraKit/Views/MaskingWorkspace.swift), preserving the same top-point fallback (CGPoint(center.x, center.y - 30)) and 30pt outward projection logic.
    - criterion: Remove the redundant local point-distance helper and use the existing enclosing helper.
      result: pass
      notes: The local `distance` function inside radialHandle was removed; the call site now uses the enclosing MaskCanvasOverlay.distance(_:_:) helper already defined at line 2297.
    - criterion: Existing radial handle appearance and hit-target behavior remain unchanged.
      result: pass
      notes: Handle offset (30pt), hit radius (16pt for rotation and center), and fallback behavior are unchanged; logic was extracted verbatim into the shared helper, not altered.
  checks_run:
    - swift build (clean build succeeded)
    - scripts/ci-tests.sh fast (1,273/1,273 tests passed)
  findings: []
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-27T07:27:28.899Z
  session: 01MUJHSPM32RFMPIJ9
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - cleanup
created: 2026-09-27T02:56:26.203Z
updated: 2026-09-27T07:27:28.901Z
blockers: []
order: a0
board: product
---

## Objective

Use one calculation for the radial mask rotation-handle position so the drawn handle and hit target cannot drift apart.

## Context

`MaskingWorkspace.drawRadialGuide` and `MaskingWorkspace.radialHandle` independently find the top radial point and project a 30-point rotation handle outward from the center. Both use the same fallback when no top point is available. A future change to one calculation could leave the visual handle and click target misaligned. `radialHandle` also defines a local `distance` function even though the enclosing type already has an equivalent helper.

Relevant code: `Sources/KromoraKit/Views/MaskingWorkspace.swift`, especially `drawRadialGuide` and `radialHandle`.

## Acceptance criteria

- [ ] Drawing and hit testing call the same helper to calculate the radial rotation-handle position and fallback.
- [ ] Remove the redundant local point-distance helper and use the existing enclosing helper.
- [ ] Existing radial handle appearance and hit-target behavior remain unchanged.

## Implementation notes

Keep the helper narrow and geometry-focused. Avoid combining rendering and hit-testing policy in the helper; it should return geometry used by both callers.

### Comment — codex @ 2026-09-27T07:23:42.837Z

Implemented shared radial rotation-handle geometry for drawing and hit testing, preserving the existing fallback and hit radius. Removed the redundant local distance helper. Verification: swift build passed; scripts/ci-tests.sh fast passed all 1,273 tests. Commit: cf61af8.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-27T07:27:28.899Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Drawing and hit testing call the same helper to calculate the radial rotation-handle position and fallback. (pass) — drawRadialGuide and radialHandle both call the new radialRotationHandle(definition:center:transform:) helper (Sources/KromoraKit/Views/MaskingWorkspace.swift), preserving the same top-point fallback (CGPoint(center.x, center.y - 30)) and 30pt outward projection logic.
- [x] Remove the redundant local point-distance helper and use the existing enclosing helper. (pass) — The local `distance` function inside radialHandle was removed; the call site now uses the enclosing MaskCanvasOverlay.distance(_:_:) helper already defined at line 2297.
- [x] Existing radial handle appearance and hit-target behavior remain unchanged. (pass) — Handle offset (30pt), hit radius (16pt for rotation and center), and fallback behavior are unchanged; logic was extracted verbatim into the shared helper, not altered.
Checks run:
- swift build (clean build succeeded)
- scripts/ci-tests.sh fast (1,273/1,273 tests passed)
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MUJHSPM32RFMPIJ9

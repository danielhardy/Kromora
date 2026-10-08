---
id: KRMA-824
title: "Tone curve: endpoint thumb becomes unselectable after dropping back in the corner"
type: bug
status: done
priority: medium
agent: claude
verification_agent: codex
human_review_required: false
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: After dragging the bottom-left thumb away and dropping it back at (0,0), it can be selected and dragged again, repeatedly.
      result: pass
      notes: Three repeated move-away/return/reselect cycles on each of Master, Red, Green, and Blue pass through the hit-test and view-model boundaries. The preserved 9 pt plot inset contains the visible thumb inside the graph gesture area. Native manual UI drag was not performed.
    - criterion: Same for the top-right (1,1) thumb.
      result: pass
      notes: The same repeated-cycle regression covers the top-right endpoint on every channel; movement and restored corner selection are asserted.
    - criterion: Endpoint handles draw and hit-test above all other handles (explicit zIndex or equivalent) and the graph.
      result: pass
      notes: Explicit endpoint zIndex raises both endpoints above graph/interior handles. nearestHandle now prioritizes the visible endpoint circle over closer underlying interior centers and uses last-slot precedence when endpoints overlap, matching drawing order. Exposed neighbors and smaller caller hit radii remain selectable.
    - criterion: Add a regression test at the existing boundary (view model / hit-test logic) if the cause is in point selection.
      result: pass
      notes: Overlap regression failed for both endpoints before the verification fix (exit 1, two assertion failures) and passes afterward. Added repeated endpoint move/reselect coverage at the existing view-model/hit-test boundary.
  checks_run:
    - "Independent review of current working-tree implementation: correctness, maintainability, security, performance, graph/plot coordinate consistency, stable gesture slots, and endpoint drawing order. No context.commands were declared."
    - "Baseline swift test --no-parallel --filter LightInspectorTests: exit 0; 26 tests passed."
    - "Pre-fix swift test --no-parallel --filter LightInspectorTests/testVisibleEndpointsWinOverCloserInteriorHandles: exit 1; two expected assertion failures reproduced selection of underlying interior handles."
    - "Final swift test --no-parallel --filter 'LightInspectorTests|LightAdjustmentsTests|PackageSettingsTests|PreviewCoordinatorTests/testInteractiveToneCurvePublishesBeforeGestureEnds': exit 0; 51 tests passed (28 inspector, 17 light model, 5 package invariants, 1 interactive preview)."
    - "scripts/ci-tests.sh warning-gate: exit 0; application and tests built with warnings promoted to errors, no diagnostics."
    - "git diff --check and git diff --cached --check: exit 0."
    - All started background commands finished; final outputs and exit statuses inspected. Native manual UI interaction was not performed.
  findings:
    - "Resolved during verification: visual endpoint zIndex alone did not control graph-level drag selection. In a 102 pt plot with adjacent interior points at 0.02/0.98, presses inside the visible endpoint circles selected underlying interior handles because their centers were closer. This contradicted endpoint hit-test precedence."
  fixes:
    - Localized nearestHandle fix gives visible endpoint circles precedence, matching last-slot drawing order for overlapping endpoints; nearest-center selection remains outside visible endpoint circles.
    - Shared the existing 6 pt visible thumb radius between rendering and hit testing to prevent geometry drift; added overlap/small-radius/exposed-neighbor and repeated move/reselect regression coverage.
    - Preserved and included the pre-existing plot inset changes and implementation endpoint zIndex/tests in the focused issue commit; unrelated DispatchGraph working-tree changes were left untouched.
  verification_commits:
    - b45f73351d1ea64262daf10549ce0caf3f083188
  actor: codex
  resolved_model: unknown
  completed_at: 2026-10-07T15:18:42.681Z
  session: 01MUY90AQ746AF7Z36
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
labels:
  - tone-curve
  - ui
created: 2026-10-07T13:58:04.652Z
updated: 2026-10-07T15:18:42.685Z
blockers: []
order: a0
board: product
footprint:
  source: declared
  paths:
    - path: Sources/KromoraKit/Views/LightInspectorView.swift
      access: write
      confidence: 1
  observed:
    paths: []
    captured_at: 2026-10-07T15:14:15.558Z
    unavailable_reason: "missing_commits: no implementation commits are recorded"
commits:
  - b45f73351d1ea64262daf10549ce0caf3f083188
---

## Objective
The endpoint thumbs on the tone curve must always be grabbable and always render/hit-test on top of any other handle or graph layer.

## Repro
1. Open Edit > Light > Tone Curve (any channel).
2. Drag the bottom-left (0,0) thumb up or right, then drag it back and drop it in the bottom-left corner.
3. The thumb can no longer be selected or dragged again.

## Suspected cause
`ToneCurveEditor` in `Sources/KromoraKit/Views/LightInspectorView.swift` stacks the graph and point handles in a `ZStack`, with handles keyed by array offset (`ForEach(Array(editablePoints.enumerated()), id: \.offset)`). Selection runs through one graph-level `curveDragGesture` (zero-distance drag), so the handle views only own double-click removal. When the point returns to the corner, hit-testing/selection appears to lose it: either another handle or the graph layer sits above it (z-order), or the nearest-point lookup in `updateCurveDrag` no longer picks it. Confirm which.

## Acceptance criteria
- After dragging the bottom-left thumb away and dropping it back at (0,0), it can be selected and dragged again, repeatedly.
- Same for the top-right (1,1) thumb.
- Endpoint handles draw and hit-test above all other handles (explicit `zIndex` or equivalent) and the graph.
- Add a regression test at the existing boundary (view model / hit-test logic) if the cause is in point selection.

## Notes
`LightInspectorView.swift` currently has uncommitted local edits; work with them, do not revert.

## Agent log

- 2026-10-07T15:18:42.681Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] After dragging the bottom-left thumb away and dropping it back at (0,0), it can be selected and dragged again, repeatedly. (pass) — Three repeated move-away/return/reselect cycles on each of Master, Red, Green, and Blue pass through the hit-test and view-model boundaries. The preserved 9 pt plot inset contains the visible thumb inside the graph gesture area. Native manual UI drag was not performed.
- [x] Same for the top-right (1,1) thumb. (pass) — The same repeated-cycle regression covers the top-right endpoint on every channel; movement and restored corner selection are asserted.
- [x] Endpoint handles draw and hit-test above all other handles (explicit zIndex or equivalent) and the graph. (pass) — Explicit endpoint zIndex raises both endpoints above graph/interior handles. nearestHandle now prioritizes the visible endpoint circle over closer underlying interior centers and uses last-slot precedence when endpoints overlap, matching drawing order. Exposed neighbors and smaller caller hit radii remain selectable.
- [x] Add a regression test at the existing boundary (view model / hit-test logic) if the cause is in point selection. (pass) — Overlap regression failed for both endpoints before the verification fix (exit 1, two assertion failures) and passes afterward. Added repeated endpoint move/reselect coverage at the existing view-model/hit-test boundary.
Checks run:
- Independent review of current working-tree implementation: correctness, maintainability, security, performance, graph/plot coordinate consistency, stable gesture slots, and endpoint drawing order. No context.commands were declared.
- Baseline swift test --no-parallel --filter LightInspectorTests: exit 0; 26 tests passed.
- Pre-fix swift test --no-parallel --filter LightInspectorTests/testVisibleEndpointsWinOverCloserInteriorHandles: exit 1; two expected assertion failures reproduced selection of underlying interior handles.
- Final swift test --no-parallel --filter 'LightInspectorTests|LightAdjustmentsTests|PackageSettingsTests|PreviewCoordinatorTests/testInteractiveToneCurvePublishesBeforeGestureEnds': exit 0; 51 tests passed (28 inspector, 17 light model, 5 package invariants, 1 interactive preview).
- scripts/ci-tests.sh warning-gate: exit 0; application and tests built with warnings promoted to errors, no diagnostics.
- git diff --check and git diff --cached --check: exit 0.
- All started background commands finished; final outputs and exit statuses inspected. Native manual UI interaction was not performed.
Findings:
- Resolved during verification: visual endpoint zIndex alone did not control graph-level drag selection. In a 102 pt plot with adjacent interior points at 0.02/0.98, presses inside the visible endpoint circles selected underlying interior handles because their centers were closer. This contradicted endpoint hit-test precedence.
Fixes:
- Localized nearestHandle fix gives visible endpoint circles precedence, matching last-slot drawing order for overlapping endpoints; nearest-center selection remains outside visible endpoint circles.
- Shared the existing 6 pt visible thumb radius between rendering and hit testing to prevent geometry drift; added overlap/small-radius/exposed-neighbor and repeated move/reselect regression coverage.
- Preserved and included the pre-existing plot inset changes and implementation endpoint zIndex/tests in the focused issue commit; unrelated DispatchGraph working-tree changes were left untouched.
Verification commits:
- b45f73351d1ea64262daf10549ce0caf3f083188
Actor: codex
Resolved model: unknown
Pickup session: 01MUY90AQ746AF7Z36
Summary: Verification passed after fixing overlapping endpoint selection. 51 focused tests and zero-warning build passed; regression reproduced failure before the fix. Commit b45f7335. No unresolved findings or child blockers. Native manual UI drag was not performed.

---
id: KRMA-588
title: Make tone-curve endpoints draggable and remove Add Point control
type: task
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Both tone-curve endpoint handles can be dragged horizontally and vertically within the graph, with their displayed positions and rendered curve updating to match.
      result: pass
      notes: editablePoints now includes all points; setToneCurvePoint/moveToneCurvePoint no longer exclude index 0/last.
    - criterion: Endpoint movement preserves valid normalized coordinates, stable point ordering, and safe curve evaluation/rendering, including curves whose endpoints move inward from input 0 or 1.
      result: pass
      notes: setToneCurvePoint clamps input between neighbors for every index including endpoints; value(at:) flat-extrapolates outside [first.input, last.input]; verified via testMovableToneCurveEndpointsNormalizeAndRoundTrip.
    - criterion: Endpoint edits persist and restore through the existing edit-document serialization path; existing tone-curve documents continue to decode with their current behavior.
      result: pass
      notes: New v2 schema (currentVersion=2) explicitly persists endpoint positions; missing version defaults to 1 (fixed 0/1 endpoints) preserving legacy decode behavior, covered by testLegacyToneCurveDecodeKeepsFixedEndpointBehavior and testMovableToneCurveEndpointsPersistThroughEditDocument.
    - criterion: Interior-point dragging, click-to-add, point removal, accessibility editing, and Reset continue to work.
      result: pass
      notes: Existing interior-point/click-to-add/removal/accessibility/reset tests in LightInspectorTests and LightAdjustmentsTests still pass unmodified aside from additions.
    - criterion: Remove the Add Point button from the tone-curve UI; clicking the curve remains the way to add points.
      result: pass
      notes: Button removed from LightInspectorView.swift; only the curve tap gesture calls addToneCurvePoint(input:).
    - criterion: Add or update focused regression coverage for endpoint movement, normalization/persistence, and the editor interaction as appropriate.
      result: pass
      notes: LightAdjustmentsTests gained 3 new tests; LightInspectorTests gained testCurveDragMovesBothEndpointsInBothDimensions.
    - criterion: swift build, focused tone-curve tests, and git diff --check pass.
      result: pass
      notes: swift build succeeds; git diff --check clean; LightAdjustmentsTests+LightInspectorTests (32 tests) pass once verified in isolation from unrelated pre-existing test-target compile failure (see findings).
  checks_run:
    - swift build
    - git diff --check
    - swift test --filter 'LightAdjustmentsTests|LightInspectorTests' (run after temporarily relocating unrelated untracked WIP files RetouchModelTests.swift/RetouchModels.swift/GeometryPointMappingTests.swift/GeometryPointMapping.swift that fail to compile independent of this issue, then restored unchanged)
  findings:
    - Pre-existing, unrelated untracked WIP files (Tests/KromoraKitTests/RetouchModelTests.swift, Tests/KromoraKitTests/GeometryPointMappingTests.swift, Sources/KromoraKit/Models/RetouchModels.swift, Sources/KromoraKit/Models/GeometryPointMapping.swift) reference an EditDocument.retouch API and GeometryPointMapping type that do not exist yet, so `swift test` cannot compile the KromoraKitTests target at all in this shared working tree. This blocks any full `swift test` run regardless of KRMA-588 and is out of scope for this issue's localized fix policy; not modified or fixed here.
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-26T17:02:00.465Z
  session: 01MUIMX9NGLMIUE4I0
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
created: 2026-09-26T00:50:47.108Z
updated: 2026-09-28T14:41:36.479Z
blockers: []
order: s2n4akgm
board: product
---

## Objective

Let photographers reshape the tone curve by dragging both endpoint handles horizontally and vertically, and remove the redundant Add Point control because clicking the graph already adds a point.

## Context

The master RGB tone curve editor is `ToneCurveEditor` in `Sources/KromoraKit/Views/LightInspectorView.swift`. The graph currently supports click-to-add and dragging interior points. The editor comment says endpoint handles are fixed; `LightToneCurve.normalized` in `Sources/KromoraKit/Models/LightAdjustments.swift` always inserts endpoints at inputs 0 and 1, while `AppViewModel+Light.swift` only edits interior points. The Add Point button in the editor adds a midpoint even though the graph gesture already creates points directly on the curve.

Allowing both endpoint handles to move in either graph dimension may require changing the tone-curve model and edit operations while preserving normalized bounds, point ordering, rendering, and persisted-document behavior. Keep click-to-add and the existing reset action.

## Acceptance criteria

- [ ] Both tone-curve endpoint handles can be dragged horizontally and vertically within the graph, with their displayed positions and rendered curve updating to match.
- [ ] Endpoint movement preserves valid normalized coordinates, stable point ordering, and safe curve evaluation/rendering, including curves whose endpoints move inward from input 0 or 1.
- [ ] Endpoint edits persist and restore through the existing edit-document serialization path; existing tone-curve documents continue to decode with their current behavior.
- [ ] Interior-point dragging, click-to-add, point removal, accessibility editing, and Reset continue to work.
- [ ] Remove the Add Point button from the tone-curve UI; clicking the curve remains the way to add points.
- [ ] Add or update focused regression coverage for endpoint movement, normalization/persistence, and the editor interaction as appropriate.
- [ ] `swift build`, focused tone-curve tests, and `git diff --check` pass.

## Implementation notes

- Review `Sources/KromoraKit/Views/LightInspectorView.swift`, `Sources/KromoraKit/Models/LightAdjustments.swift`, and `Sources/KromoraKit/ViewModels/AppViewModel+Light.swift`.
- Review tone-curve coverage in `Tests/KromoraKitTests/` and add focused tests alongside the existing curve/model tests.
- Keep endpoints ordered and distinct from adjacent points when dragged horizontally. Preserve existing curve constraints and deterministic handling of older serialized curves.


### Comment — codex @ 2026-09-26T16:40:02.680Z

Implementation is present in commit 1742e72: both curve endpoints are draggable in input/output, the redundant Add Point control is removed while click-to-add remains, and v2 curve normalization/persistence preserves movable endpoints with legacy v1 decode behavior. Focused model/view-model regression coverage is present for endpoint movement, normalization, persistence, click/add/remove, accessibility editing, and ordering. Verification: swift build and git diff --check pass. swift test --filter 'LightAdjustmentsTests|LightInspectorTests' is blocked during test-target compilation by pre-existing Tests/KromoraKitTests/RetouchModelTests.swift references to missing EditDocument.retouch API; no tone-curve test ran. No additional source changes were needed because the implementation is already committed.

## Agent log

- 2026-09-26T17:02:00.465Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Both tone-curve endpoint handles can be dragged horizontally and vertically within the graph, with their displayed positions and rendered curve updating to match. (pass) — editablePoints now includes all points; setToneCurvePoint/moveToneCurvePoint no longer exclude index 0/last.
- [x] Endpoint movement preserves valid normalized coordinates, stable point ordering, and safe curve evaluation/rendering, including curves whose endpoints move inward from input 0 or 1. (pass) — setToneCurvePoint clamps input between neighbors for every index including endpoints; value(at:) flat-extrapolates outside [first.input, last.input]; verified via testMovableToneCurveEndpointsNormalizeAndRoundTrip.
- [x] Endpoint edits persist and restore through the existing edit-document serialization path; existing tone-curve documents continue to decode with their current behavior. (pass) — New v2 schema (currentVersion=2) explicitly persists endpoint positions; missing version defaults to 1 (fixed 0/1 endpoints) preserving legacy decode behavior, covered by testLegacyToneCurveDecodeKeepsFixedEndpointBehavior and testMovableToneCurveEndpointsPersistThroughEditDocument.
- [x] Interior-point dragging, click-to-add, point removal, accessibility editing, and Reset continue to work. (pass) — Existing interior-point/click-to-add/removal/accessibility/reset tests in LightInspectorTests and LightAdjustmentsTests still pass unmodified aside from additions.
- [x] Remove the Add Point button from the tone-curve UI; clicking the curve remains the way to add points. (pass) — Button removed from LightInspectorView.swift; only the curve tap gesture calls addToneCurvePoint(input:).
- [x] Add or update focused regression coverage for endpoint movement, normalization/persistence, and the editor interaction as appropriate. (pass) — LightAdjustmentsTests gained 3 new tests; LightInspectorTests gained testCurveDragMovesBothEndpointsInBothDimensions.
- [x] swift build, focused tone-curve tests, and git diff --check pass. (pass) — swift build succeeds; git diff --check clean; LightAdjustmentsTests+LightInspectorTests (32 tests) pass once verified in isolation from unrelated pre-existing test-target compile failure (see findings).
Checks run:
- swift build
- git diff --check
- swift test --filter 'LightAdjustmentsTests|LightInspectorTests' (run after temporarily relocating unrelated untracked WIP files RetouchModelTests.swift/RetouchModels.swift/GeometryPointMappingTests.swift/GeometryPointMapping.swift that fail to compile independent of this issue, then restored unchanged)
Findings:
- Pre-existing, unrelated untracked WIP files (Tests/KromoraKitTests/RetouchModelTests.swift, Tests/KromoraKitTests/GeometryPointMappingTests.swift, Sources/KromoraKit/Models/RetouchModels.swift, Sources/KromoraKit/Models/GeometryPointMapping.swift) reference an EditDocument.retouch API and GeometryPointMapping type that do not exist yet, so `swift test` cannot compile the KromoraKitTests target at all in this shared working tree. This blocks any full `swift test` run regardless of KRMA-588 and is out of scope for this issue's localized fix policy; not modified or fixed here.
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MUIMX9NGLMIUE4I0

---
id: KRMA-276
title: Linear-gradient endpoints redraw instead of adjusting gradient length
type: bug
status: done
priority: high
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Dragging the zero-strength endpoint changes only the gradient length while keeping the full-strength endpoint fixed.
      result: pass
      notes: "LinearGradientMaskMath.endpointEdited(edge: .zeroStrength) projects onto the gesture-start axis and calls changingFalloff(keeping: .fullStrength); covered by LocalMaskTests and MaskingWorkspaceTests.testLinearZeroStrengthHandleResizesWithoutReplacingDefinition."
    - criterion: Dragging the full-strength endpoint changes only the gradient length while keeping the zero-strength endpoint fixed.
      result: pass
      notes: "Symmetric edge: .fullStrength path keeps zeroStrengthPoint fixed; covered by testLinearFullStrengthHandleResizesWithoutReplacingDefinition."
    - criterion: Endpoint drags preserve gradient direction/angle and do not enter creation or center translation behavior; crossing/near-zero lengths remain clamped safely.
      result: pass
      notes: Direction is derived from the gesture-start definition (or angle fallback when collapsed); changingFalloff clamps to [0, sqrt(2)]; AppViewModel+Masking.updateMaskGesture switches on activeLinearHandle so .zeroStrength/.fullStrength never fall through to .creation or .center.
    - criterion: Center and rotation handles retain existing translation/rotation semantics.
      result: pass
      notes: Diff does not touch the .center/.rotation cases in AppViewModel+Masking.swift; unchanged and still passing.
    - criterion: Regression tests prove each endpoint updates falloff with the opposite point unchanged, and interaction does not silently replace the definition.
      result: pass
      notes: LocalMaskTests covers the math helper directly (zero/full edit, crossed/clamped case); MaskingWorkspaceTests covers the full gesture path asserting layer/component identity and mode are preserved, not replaced.
    - criterion: Existing masking, rendering, persistence, and undo/redo tests continue to pass.
      result: pass
      notes: "Full deterministic suite: swift test -> 933 executed, 42 skipped, 0 failures."
  checks_run:
    - swift build
    - swift test --filter LocalMaskTests (12 tests, 0 failures)
    - swift test --filter MaskingWorkspaceTests (32 tests, 0 failures)
    - "swift test (full deterministic lane: 933 executed, 42 skipped, 0 failures)"
    - "manual read of commit 41750ca diff: LinearGradientMaskMath.endpointEdited, AppViewModel+Masking.swift call sites, MaskingWorkspace.swift hit-test change, and LocalMaskModels.swift changingFalloff/clamp semantics"
  findings:
    - No blocking issues found. The endpoint-edit math correctly reuses changingFalloff(to:keeping:) with an opposite-edge anchor, clamping is delegated to the model layer (already tested there), and the nearest-hit change to MaskCanvasOverlay.linearHandle correctly resolves overlapping bars for short gradients (fixed 3-element array, no perf concern). Accessibility labels for the linear guide were not touched by this change.
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-07T15:13:48.849Z
  session: 01MTRDNUN1QOF3N75B
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - masking
  - gradients
  - ux
created: 2026-09-07T04:05:10.715Z
updated: 2026-09-10T12:53:52.751Z
order: a0
board: product
---

## Objective

Allow either endpoint of an existing linear-gradient mask to adjust the gradient length while
keeping the opposite endpoint, direction, and gradient placement stable.

## Context

When editing a linear gradient, dragging the zero-strength side or full-strength side should
extend or contract the transition from that side. Instead, the current interaction behaves like a
new gradient draw: the gradient is redrawn/repositioned rather than simply changing its length.
This makes precise mask refinement difficult and can unexpectedly move the gradient's fixed side.

The relevant interaction state and endpoint handles are in
`Sources/LumoKit/Models/MaskInteractionState.swift`,
`Sources/LumoKit/ViewModels/AppViewModel+Masking.swift`, and
`Sources/LumoKit/Views/MaskingWorkspace.swift`. The durable definition is
`LinearGradientDefinition` in `Sources/LumoKit/Models/LocalMaskModels.swift`; its existing
`changingFalloff(to:keeping:)` API expresses the intended opposite-edge-fixed behavior.

## Acceptance criteria

- [ ] Dragging the zero-strength endpoint changes only the gradient length while keeping the
      full-strength endpoint fixed.
- [ ] Dragging the full-strength endpoint changes only the gradient length while keeping the
      zero-strength endpoint fixed.
- [ ] Endpoint drags preserve the gradient direction/angle and do not enter creation or center
      translation behavior; crossing/near-zero lengths remain clamped safely.
- [ ] The center and rotation handles retain their existing translation and rotation semantics.
- [ ] Add regression tests proving each endpoint updates `falloff` with the opposite point
      unchanged, and that the interaction does not silently replace the gradient definition.
- [ ] Existing masking, rendering, persistence, and undo/redo tests continue to pass.

## Implementation notes

- Keep endpoint editing in normalized source coordinates and reuse the model-level
  `changingFalloff(to:keeping:)` semantics so the opposite edge remains anchored.
- Distinguish endpoint editing from creation gestures when resolving the active linear handle;
  pointer movement should be interpreted relative to the gesture-start definition.
- Preserve accessibility labels for the zero-strength and full-strength endpoint handles.

### Comment — codex @ 2026-09-07T04:05:42.127Z

Captured the expected endpoint-editing semantics: dragging either linear-gradient side should reuse the existing definition and adjust falloff with the opposite edge anchored, rather than entering creation/redraw behavior. Relevant code paths are listed in the ticket.

### Comment — codex @ 2026-09-07T15:10:18.840Z

Implementation ready for review in commit 41750ca. Centralized linear endpoint edits in normalized source coordinates using anchored changingFalloff semantics, preserving the opposite edge, direction, and component identity. Endpoint hit-testing now selects the nearest overlapping bar so short gradients can edit either side. Added model and interaction regressions for zero/full-strength edits, clamping, angle preservation, and no silent definition replacement. Verification: swift test (933 executed, 42 expected skips, 0 failures), swift build -c release (passed), git diff --check (passed), dg validate (OK; pre-existing pickup-runner model warning only).

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-07T15:13:48.850Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Dragging the zero-strength endpoint changes only the gradient length while keeping the full-strength endpoint fixed. (pass) — LinearGradientMaskMath.endpointEdited(edge: .zeroStrength) projects onto the gesture-start axis and calls changingFalloff(keeping: .fullStrength); covered by LocalMaskTests and MaskingWorkspaceTests.testLinearZeroStrengthHandleResizesWithoutReplacingDefinition.
- [x] Dragging the full-strength endpoint changes only the gradient length while keeping the zero-strength endpoint fixed. (pass) — Symmetric edge: .fullStrength path keeps zeroStrengthPoint fixed; covered by testLinearFullStrengthHandleResizesWithoutReplacingDefinition.
- [x] Endpoint drags preserve gradient direction/angle and do not enter creation or center translation behavior; crossing/near-zero lengths remain clamped safely. (pass) — Direction is derived from the gesture-start definition (or angle fallback when collapsed); changingFalloff clamps to [0, sqrt(2)]; AppViewModel+Masking.updateMaskGesture switches on activeLinearHandle so .zeroStrength/.fullStrength never fall through to .creation or .center.
- [x] Center and rotation handles retain existing translation/rotation semantics. (pass) — Diff does not touch the .center/.rotation cases in AppViewModel+Masking.swift; unchanged and still passing.
- [x] Regression tests prove each endpoint updates falloff with the opposite point unchanged, and interaction does not silently replace the definition. (pass) — LocalMaskTests covers the math helper directly (zero/full edit, crossed/clamped case); MaskingWorkspaceTests covers the full gesture path asserting layer/component identity and mode are preserved, not replaced.
- [x] Existing masking, rendering, persistence, and undo/redo tests continue to pass. (pass) — Full deterministic suite: swift test -> 933 executed, 42 skipped, 0 failures.
Checks run:
- swift build
- swift test --filter LocalMaskTests (12 tests, 0 failures)
- swift test --filter MaskingWorkspaceTests (32 tests, 0 failures)
- swift test (full deterministic lane: 933 executed, 42 skipped, 0 failures)
- manual read of commit 41750ca diff: LinearGradientMaskMath.endpointEdited, AppViewModel+Masking.swift call sites, MaskingWorkspace.swift hit-test change, and LocalMaskModels.swift changingFalloff/clamp semantics
Findings:
- No blocking issues found. The endpoint-edit math correctly reuses changingFalloff(to:keeping:) with an opposite-edge anchor, clamping is delegated to the model layer (already tested there), and the nearest-hit change to MaskCanvasOverlay.linearHandle correctly resolves overlapping bars for short gradients (fixed 3-element array, no perf concern). Accessibility labels for the linear guide were not touched by this change.
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MTRDNUN1QOF3N75B
Summary: Independent verification pass: reviewed commit 41750ca (endpoint-edit math, hit-test nearest-bar fix, and new regression tests), rebuilt and reran the full deterministic suite (933 executed, 0 failures). All acceptance criteria confirmed; no blocking issues.

---
id: LUMO-235
title: "Linear gradient: new masks open with unusable controls"
type: bug
status: done
priority: high
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Fresh linear creation selects a transient layer/component and enters creation state
      result: pass
    - criterion: First valid drag creates a non-degenerate usable gradient
      result: pass
    - criterion: Post-creation editing targets the new gradient
      result: pass
    - criterion: Cancel leaves no empty durable layer and completion is undoable
      result: pass
    - criterion: Prior selection is preserved when creation is cancelled and zoom/transform paths remain shared
      result: pass
    - criterion: Regression coverage covers fresh creation, prior selection, cancel, and undo
      result: pass
  checks_run:
    - swift test --filter 'MaskingWorkspaceTests|CanvasNavigationTests' (42 passed, 0 failures)
    - git diff --cached --check
  findings:
    - Manual interactive photo/display verification was unavailable in this environment.
  fixes: []
  verification_commits:
    - 4d03ede
  actor: codex
  resolved_model: unknown
  completed_at: 2026-09-06T14:24:22.859Z
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - masking
  - editor
  - epic:masking
created: 2026-09-06T03:14:51.780Z
updated: 2026-09-06T14:24:22.866Z
order: n
board: product
commits:
  - 4d03ede
---

## Objective

Make a newly added linear-gradient mask immediately actionable and editable.

## Context

Adding a new linear gradient currently leaves the user with controls that appear unusable. The
creation state, selected layer/component, and canvas handles do not form a reliable workflow, so a
new gradient can look like it was added while its tools do nothing useful.

### Reproduction

1. Open the masking workspace on a photo with no selected gradient, or add a new mask layer.
2. Choose Linear Gradient and add the mask.
3. Try the first canvas drag, then try the gradient handles and inspector controls.

### Observed

The newly added gradient does not consistently enter a useful creation/editing state. The tools can
appear inert or provide no meaningful visual result, making the new mask effectively unusable.

### Expected

Adding Linear Gradient should select the new layer and component, present a clear creation affordance,
and make the first drag create a meaningful gradient that can immediately be reshaped.

## Acceptance criteria

- [ ] Adding a linear gradient selects the new layer and its linear component and visibly enters a
      creation/editing state.
- [ ] The first valid canvas drag creates non-degenerate zero-strength and full-strength edges and
      produces an immediately visible mask result.
- [ ] After creation, center translation, falloff editing, rotation, inspector controls, and
      keyboard nudging all target the new gradient rather than a previous layer/component.
- [ ] Cancelling an empty or incomplete creation removes the transient layer/component and leaves
      the document unchanged; completing it persists one usable mask with undo support.
- [ ] The workflow remains correct when a different layer/component was previously selected and
      when the canvas is zoomed, panned, cropped, or fit/fill transformed.
- [ ] Add regression coverage for fresh creation, creation after an existing selection, and
      cancel-before-commit.

## Implementation notes

Audit the creation-pending and selected-layer/selected-component transitions introduced by LUMO-221
and the persistent workspace in LUMO-220. Keep transient creation separate from the durable document
until the first valid drag commits it, and ensure the same coordinate transform is used by creation,
hit-testing, rendering, and inspector updates.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-06T03:49:35.979Z: Verification report
Verdict: PASS
Acceptance criteria:
- None supplied
Checks run:
- None
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: codex
Resolved model: gpt-5.6-luna
Pickup session: 01MTP9JP2YHSSKR3VX
Summary: Linear gradient creation now stays transient until a valid drag, preserves layer/component targeting and prior selection, exposes a visible creation prompt, rejects degenerate clicks, and commits one undoable mask. Added fresh, prior-selection, cancel, and undo regression coverage.

- 2026-09-06T14:24:22.864Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Fresh linear creation selects a transient layer/component and enters creation state (pass)
- [x] First valid drag creates a non-degenerate usable gradient (pass)
- [x] Post-creation editing targets the new gradient (pass)
- [x] Cancel leaves no empty durable layer and completion is undoable (pass)
- [x] Prior selection is preserved when creation is cancelled and zoom/transform paths remain shared (pass)
- [x] Regression coverage covers fresh creation, prior selection, cancel, and undo (pass)
Checks run:
- swift test --filter 'MaskingWorkspaceTests|CanvasNavigationTests' (42 passed, 0 failures)
- git diff --cached --check
Findings:
- Manual interactive photo/display verification was unavailable in this environment.
Fixes:
- None
Verification commits:
- 4d03ede
Actor: codex
Resolved model: unknown
Summary: Reconciled the completed linear-gradient creation work; implementation and regression coverage are now preserved in commit 4d03ede.

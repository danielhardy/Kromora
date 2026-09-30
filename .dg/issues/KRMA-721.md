---
id: KRMA-721
title: Make Crop Auto useful or remove the no-op control
type: task
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Record one product outcome (implement or remove Auto)
      result: pass
      notes: Removed; recorded in handoff comment
    - criterion: "If removing: remove button, callback, action, and misleading status/help text; revise no-op test"
      result: pass
      notes: onAuto, runCropAuto, status and accessibility hint removed; no residual references outside the guard test; old no-op test replaced
    - criterion: Manual crop behaviors intact with regression coverage
      result: pass
      notes: CropWorkflowTests 14/14 pass; new guard test passes
    - criterion: Visual verification and rationale recorded
      result: pass
      notes: Handoff records hosted inspector render with no Auto control; not re-rendered by verifier
  checks_run:
    - swift build (pass)
    - swift test --filter MenuCommandTests/testCropInspectorDoesNotAdvertiseUnavailableAutoAction (1 pass)
    - swift test --filter CropWorkflowTests (14 pass)
    - grep for cropAuto/runCropAuto/auto crop in Sources, Tests, docs
  findings:
    - "info: the new guard test asserts on source-text substrings, which is brittle to refactors but acceptable as a non-blocking regression guard."
  fixes: []
  verification_commits:
    - af2688e
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-29T20:30:30.013Z
  session: 01MUN4RCEYVR5DCSNR
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - crop
  - ui
created: 2026-09-29T18:41:48.674Z
updated: 2026-09-29T20:30:30.016Z
blockers: []
order: a0
board: product
commits:
  - af2688e
---

## Objective

Resolve the nonfunctional Auto action in Crop mode. Choose and deliver one clear outcome: implement the advertised automatic crop/straighten behavior, or remove the Auto control and its no-op plumbing.

## User report

The Crop mode “Auto” control does not seem to do anything. It should either be removed or provide useful automatic functionality. If it is removed any "auto crop" code in the system that can be reliably removed should also be cut.

## Current behavior

`CropInspectorView` exposes an Auto button whose help says it will suggest a horizon straighten when reliable evidence is available. It calls `runCropAuto()` in `CanvasWorkflowCoordinator`, which currently makes no crop or straighten change and only sets the status text to “Auto crop: no reliable horizon detected.” `CropTests.testCropAutoNoOpDoesNotTouchGeometryOrGlobalTone` currently codifies that no-op result. Verify this behavior and decide whether the advertised feature is worth implementing before retaining the control.

## Acceptance criteria

- [ ] Make and record one product outcome: implement useful Auto functionality or remove the nonfunctional Auto affordance. Do not leave a button that always reports no result without trying to analyze the image.
- [ ] If implementing Auto: define the exact behavior and scope exposed by the control. At minimum, honor its current “suggest a horizon straighten” description by detecting reliable horizon evidence and updating the in-progress crop straighten draft so the result is visibly reflected in the overlay and preview.
- [ ] If implementing Auto: use deterministic fixtures with known horizon orientation and a no-reliable-horizon case; prove the detected case changes the draft in the correcting direction and the no-evidence case gives an accurate, understandable result without changing geometry.
- [ ] If implementing Auto: keep the result inside the Crop draft until Save, preserve Cancel behavior, avoid modifying unrelated global edits, and verify the resulting crop/straighten preview and committed export geometry.
- [ ] If removing Auto: remove the button, obsolete callback/action and misleading status/help text, and revise the current no-op test rather than preserving code that advertises unavailable behavior.
- [ ] Whichever path is chosen, keep manual aspect, rotate, straighten, flip, perspective, crop drag, Save, and Cancel behaviors intact, and add regression coverage for the chosen behavior.
- [ ] Visually verify the chosen result in Crop mode and record the root cause or product rationale, implementation, and verification commands/results in the handoff.

## Context

Relevant code is in `Sources/KromoraKit/Views/CropInspectorView.swift`, `Sources/KromoraKit/Views/InfoInspectorView.swift`, and `Sources/KromoraKit/ViewModels/CanvasWorkflowCoordinator.swift`. Crop workflow coverage is in `Tests/KromoraKitTests/CropTests.swift`.

Do not broaden this into automatic composition/framing unless that is explicitly defined as the selected product behavior; the current control description promises horizon straighten, not subject-aware reframing.


### Comment — codex @ 2026-09-29T20:29:50.672Z

Root cause: Crop Auto only posted a no-reliable-horizon status and performed no image analysis. Product outcome: removed the unavailable Auto affordance and its callback, status, and forwarding methods; manual Crop controls remain. Visual check: hosted the Crop inspector at 280x820 and inspected the rendered view; Reset, aspect, rotate/flip, straighten, perspective, Cancel, and Save are visible, with no Auto control. Verification: swift test --filter MenuCommandTests/testCropInspectorDoesNotAdvertiseUnavailableAutoAction (1 passed); swift test --filter CropWorkflowTests (14 passed, including draft/cancel/commit, straighten, aspect, and crop-mode regressions). Commit: af2688e.

## Agent log

- 2026-09-29T20:30:30.013Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Record one product outcome (implement or remove Auto) (pass) — Removed; recorded in handoff comment
- [x] If removing: remove button, callback, action, and misleading status/help text; revise no-op test (pass) — onAuto, runCropAuto, status and accessibility hint removed; no residual references outside the guard test; old no-op test replaced
- [x] Manual crop behaviors intact with regression coverage (pass) — CropWorkflowTests 14/14 pass; new guard test passes
- [x] Visual verification and rationale recorded (pass) — Handoff records hosted inspector render with no Auto control; not re-rendered by verifier
Checks run:
- swift build (pass)
- swift test --filter MenuCommandTests/testCropInspectorDoesNotAdvertiseUnavailableAutoAction (1 pass)
- swift test --filter CropWorkflowTests (14 pass)
- grep for cropAuto/runCropAuto/auto crop in Sources, Tests, docs
Findings:
- info: the new guard test asserts on source-text substrings, which is brittle to refactors but acceptable as a non-blocking regression guard.
Fixes:
- None
Verification commits:
- af2688e
Actor: claude
Resolved model: sonnet
Pickup session: 01MUN4RCEYVR5DCSNR
Summary: Verified removal of the no-op Crop Auto control; no residual auto-crop code; tests pass.

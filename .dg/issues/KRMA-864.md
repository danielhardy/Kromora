---
id: KRMA-864
title: Crop mode toolbar renders as one tall orange pill instead of Save/Cancel/Undo
type: bug
status: done
priority: medium
agent: claude
verification_agent: codex
human_review_required: false
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Crop toolbar displays Save, Cancel, and Undo side by side in one glass group, vertically centered without extending into the canvas.
      result: pass
      notes: The explicit HStack enforces horizontal placement. The later screenshot noted in the issue comments confirms the rendered row; this verifier could not relaunch the app because another process held the library package.
  checks_run:
    - swift build (passed)
    - swift test --filter MenuCommandTests (11 tests passed)
    - swift test --filter CropInspectorTests (3 tests passed)
    - Independent code review of commit ea9b6f474f01afe82da0f79bf13fa20bd9ef40bb (no correctness, maintainability, security, or performance findings)
    - Visual check attempted; blocked by existing app alert that the library package is already being written by another process. Screenshot evidence was available in the issue context.
  findings: []
  fixes: []
  verification_commits:
    - ea9b6f474f01afe82da0f79bf13fa20bd9ef40bb
  actor: codex
  resolved_model: gpt-6-luna
  completed_at: 2026-10-11T02:58:46.530Z
  session: 01MV38GOOBA9DKGVVD
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
created: 2026-10-10T18:45:39.783Z
updated: 2026-10-11T02:58:46.533Z
blockers: []
order: t
board: product
commits:
  - ea9b6f474f01afe82da0f79bf13fa20bd9ef40bb
  - ea9b6f474f01afe82da0f79bf13fa20bd9ef40bb
---

## Objective

In Crop mode the window toolbar shows one tall orange capsule at the top right (about 46 x 115 pt, reaching into the content area) with a single undo-style glyph, instead of the Save / Cancel / Undo glass buttons in a row.

## Analysis (from a screenshot and the code; not reproduced locally)

`CropToolbarControls` (Sources/KromoraKit/Views/ContentView.swift) returned three bare `Button`s inside `GlassEffectContainer`, all tagged `glassEffectUnion(id: "crop")`, placed in a `ToolbarItem(.primaryAction)`. With no stack of its own, the children can be laid out vertically; unioned glass then draws one tall capsule (the prominent Save tint is the orange) and hides the other buttons. The structure dates from KRMA-489 and has not changed, so the trigger is probably a recent toolchain or OS update (Xcode 27.0 beta 27A5252f on macOS 27.2), not a code change.

## Work done

The three buttons are now wrapped in an explicit `HStack(spacing: 10)` inside `CropToolbarControls`; buttons, help text, accessibility labels and the union id are unchanged. Build and MenuCommandTests/CropInspectorTests pass.

## Acceptance criteria

- Entering Crop shows Save, Cancel and Undo side by side in one glass group, vertically centred in the toolbar, with no pill extending into the canvas.
- Not yet confirmed visually: the reporter should rebuild and check. If it still renders as a tall pill, capture the view hierarchy (Xcode view debugger or `read_page` equivalent) and consider replacing the container with a `ControlGroup`, as the transfer pill does.


### Comment — claude @ 2026-10-11T01:13:15.501Z

Handoff to verification (implementer: claude; reporter has reviewed). Commit ea9b6f47. CropToolbarControls placed three unioned glass buttons (Save, Cancel, Undo) in a GlassEffectContainer with no stack, so they could lay out vertically and draw one tall orange capsule hiding Save and Cancel after the Xcode 27 beta / macOS 27.2 update. Fix: an explicit HStack(spacing: 10) around them; behavior, help text, accessibility and union id unchanged. The reporter's later screenshot shows the group as a proper row. Tests: MenuCommandTests, CropInspectorTests pass. Check: the toolbar group is vertically centred and a single glass group in light and dark.


### Comment — claude @ 2026-10-11T01:13:24.575Z

Commits for KRMA-864 (oldest first; review with git show <sha>):
- ea9b6f474f01afe82da0f79bf13fa20bd9ef40bb KRMA-864: lay out the crop toolbar buttons in an explicit row

## Agent log

- 2026-10-11T02:58:46.530Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Crop toolbar displays Save, Cancel, and Undo side by side in one glass group, vertically centered without extending into the canvas. (pass) — The explicit HStack enforces horizontal placement. The later screenshot noted in the issue comments confirms the rendered row; this verifier could not relaunch the app because another process held the library package.
Checks run:
- swift build (passed)
- swift test --filter MenuCommandTests (11 tests passed)
- swift test --filter CropInspectorTests (3 tests passed)
- Independent code review of commit ea9b6f474f01afe82da0f79bf13fa20bd9ef40bb (no correctness, maintainability, security, or performance findings)
- Visual check attempted; blocked by existing app alert that the library package is already being written by another process. Screenshot evidence was available in the issue context.
Findings:
- None
Fixes:
- None
Verification commits:
- ea9b6f474f01afe82da0f79bf13fa20bd9ef40bb
Actor: codex
Resolved model: gpt-6-luna
Pickup session: 01MV38GOOBA9DKGVVD
Summary: Verified explicit crop toolbar row; build and focused suites pass.

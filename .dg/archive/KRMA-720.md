---
id: KRMA-720
title: Move Crop reset into the inspector title row
type: task
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Header shows Crop leading and compact link-style Reset trailing
      result: pass
      notes: "HStack with Text, Spacer(minLength: 8), Button.link .callout"
    - criterion: Header Reset retains reset behavior and accessibility hint
      result: pass
      notes: Still calls onReset; hint preserved
    - criterion: Duplicate scrolling Reset removed; Straighten/Perspective resets kept
      result: pass
    - criterion: Aligned, non-overlapping at min/typical/max widths
      result: pass
      notes: By code inspection only (minLength spacer); live-app visual check not run in CLI
    - criterion: Reset visible regardless of scroll position
      result: pass
      notes: Header is outside the ScrollView
    - criterion: Crop title accessibility preserved; Reset has clear name and hint
      result: pass
      notes: Header trait added; label Reset crop
    - criterion: Focused coverage or repeatable visual procedure
      result: pass
      notes: Source-structure test plus documented live-app procedure
    - criterion: Handoff records implementation and verification
      result: pass
  checks_run:
    - "swift test --filter MenuCommandTests/testCropResetLivesInPinnedInspectorTitleRow: passed"
    - "swift test --filter MenuCommandTests: 9 pass, 1 unrelated failure (testViewMenuRoutesRelocatedEditorActionsAndKeepsComparisonToolbarStable) caused by uncommitted toolbar work in ContentView/tests, not this change"
  findings:
    - Coverage is source-text based and does not exercise layout; acceptable given native inspector presentation.
    - Unrelated MenuCommandTests failure from pre-existing uncommitted working-tree changes; left untouched.
  fixes: []
  verification_commits:
    - 1c81a7d
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-29T19:42:08.162Z
  session: 01MUN31ACVRQKD2G2F
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - ui
  - layout
created: 2026-09-29T17:29:59.389Z
updated: 2026-09-29T19:42:08.164Z
blockers: []
order: a0
board: product
commits:
  - 1c81a7d
---

## Objective

Move the full Crop reset action into the Crop inspector title row. Keep “Crop” aligned on the left and show a smaller, link-style “Reset” action aligned on the right.

## User request

In Crop mode, the “Reset” button should be aligned right in the title row as a smaller link.

## Context

`CropInspectorView` in `Sources/KromoraKit/Views/CropInspectorView.swift` currently renders the `Crop` title in its own header row and puts a full-size `Reset` button inside the scrolling crop controls, after Perspective. That action calls `onReset`, which is wired to `viewModel.resetCrop` and returns the crop frame to the full image. The inspector title remains visible while its controls scroll, so placing Reset in the title row makes the global action easier to reach.

The straighten and perspective sections also have their own reset controls. Keep those section-level actions separate and unchanged.

## Acceptance criteria

- [ ] In Crop mode, the inspector header shows “Crop” at the leading edge and a compact, smaller, link-style “Reset” action at the trailing edge of the same row.
- [ ] Activating the header Reset retains the existing full-crop reset behavior and accessibility hint.
- [ ] Remove the duplicate full-size Reset button from the scrolling controls; do not remove the per-control Straighten or Perspective reset actions.
- [ ] Keep the title and Reset aligned, legible, and non-overlapping at the inspector minimum, typical, and maximum widths.
- [ ] The Reset action remains visible and usable regardless of the scroll position within Crop controls.
- [ ] Preserve the Crop title accessibility and provide a clear accessible name and hint for the Reset action.
- [ ] Add or update focused Crop inspector layout/interaction coverage, or record a repeatable visual verification procedure if native inspector presentation requires a live-app check.
- [ ] Record the implementation and verification results in the handoff.

## Implementation notes

Keep the Cancel and Save actions in the existing footer. Limit this change to the full Crop reset placement and styling; retain the reset callback and crop semantics.


### Comment — codex @ 2026-09-29T19:41:29.976Z

Implemented in commit 1c81a7d: moved the full-crop Reset action into the pinned Crop title row as a compact link, preserved its full-image reset callback and accessibility hint, and removed only the duplicate scrolling action. Straighten and Perspective reset controls remain. Verification: `swift test --filter MenuCommandTests/testCropResetLivesInPinnedInspectorTitleRow` passed (1 test, 0 failures). Repeatable live-app visual check: open a photo, enter Crop mode, and resize the inspector to its minimum (240 pt), typical (280 pt), and maximum (360 pt) widths; confirm Crop stays leading and Reset trailing without overlap. Scroll Crop controls to the bottom and confirm Reset stays visible; activate it and verify the crop frame returns to the full image. Confirm Straighten and Perspective resets still work. This native inspector check was not run in this CLI session.

## Agent log

- 2026-09-29T19:42:08.162Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Header shows Crop leading and compact link-style Reset trailing (pass) — HStack with Text, Spacer(minLength: 8), Button.link .callout
- [x] Header Reset retains reset behavior and accessibility hint (pass) — Still calls onReset; hint preserved
- [x] Duplicate scrolling Reset removed; Straighten/Perspective resets kept (pass)
- [x] Aligned, non-overlapping at min/typical/max widths (pass) — By code inspection only (minLength spacer); live-app visual check not run in CLI
- [x] Reset visible regardless of scroll position (pass) — Header is outside the ScrollView
- [x] Crop title accessibility preserved; Reset has clear name and hint (pass) — Header trait added; label Reset crop
- [x] Focused coverage or repeatable visual procedure (pass) — Source-structure test plus documented live-app procedure
- [x] Handoff records implementation and verification (pass)
Checks run:
- swift test --filter MenuCommandTests/testCropResetLivesInPinnedInspectorTitleRow: passed
- swift test --filter MenuCommandTests: 9 pass, 1 unrelated failure (testViewMenuRoutesRelocatedEditorActionsAndKeepsComparisonToolbarStable) caused by uncommitted toolbar work in ContentView/tests, not this change
Findings:
- Coverage is source-text based and does not exercise layout; acceptable given native inspector presentation.
- Unrelated MenuCommandTests failure from pre-existing uncommitted working-tree changes; left untouched.
Fixes:
- None
Verification commits:
- 1c81a7d
Actor: claude
Resolved model: sonnet
Pickup session: 01MUN31ACVRQKD2G2F
Summary: Verified: full Crop reset moved into pinned title row as trailing link button; duplicate removed; per-control resets untouched.

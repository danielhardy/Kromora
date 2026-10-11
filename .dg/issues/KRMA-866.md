---
id: KRMA-866
title: "Crop: drop the duplicate Save/Cancel bar from the inspector and neutralize the Rotate buttons"
type: task
status: done
priority: low
agent: claude
verification_agent: codex
human_review_required: false
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Crop shows Save/Cancel only in the toolbar; the inspector bottom bar is gone and Return/Escape still apply/cancel.
      result: pass
      notes: Inspector Save/Cancel controls and onDone callback are absent; toolbar owns both actions. KeyboardShortcuts still routes Return to commitCrop() and Escape to cancelCrop() while Crop is active. These shortcuts were source-inspected, not exercised in a live UI session.
    - criterion: Rotate buttons are neutral; a flip is orange only when on.
      result: pass
      notes: transformButton applies .tint(nil); flipButton applies the accent only when isOn.
    - criterion: MenuCommandTests, CropInspectorTests and InfoInspector tests pass.
      result: pass
      notes: All 20 selected tests passed.
  checks_run:
    - swift test --filter MenuCommandTests|CropInspectorTests|InfoInspector (20 tests passed)
    - Source review of CropInspectorView, InfoInspectorView, ContentView toolbar ownership, and KeyboardShortcuts Return/Escape handlers
    - Search of Tests/KromoraKitTests to confirm no assertion requires the removed inspector Save/Cancel controls
  findings: []
  fixes: []
  verification_commits: []
  actor: codex
  resolved_model: gpt-6-luna
  completed_at: 2026-10-11T03:06:18.525Z
  session: 01MV38P7N5FF7AJZKS
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
created: 2026-10-10T19:18:44.347Z
updated: 2026-10-11T03:06:18.528Z
blockers: []
order: y
board: product
commits:
  - 17f2ada8818b53d60fcecab5cc0e5f9ca376d4d0
---

## Objective

Crop mode had two sets of Save/Cancel: the glass group in the window toolbar and a Cancel/Save bar at the bottom of the Crop inspector. Keep one. Also, the Rotate buttons were accent-orange while the Flip toggles were neutral, so orange read as an "on" state on buttons that have none.

## Decision

Toolbar only (chosen by the reporter). The toolbar group also carries Undo and sits with the window chrome; the inspector holds only adjustments.

## Work done

- `CropInspectorView`: removed the bottom Divider and Cancel/Save `HStack` and the `onDone` parameter; `onCancel` stays for `onExitCommand`. `InfoInspectorView`'s call site updated.
- Return and Escape are unchanged: the global key monitor in `KeyboardShortcuts.swift` calls `commitCrop()` / `cancelCrop()` while Crop is active, and the toolbar buttons keep their help text.
- `transformButton` (Rotate 90 left/right) now has `.tint(nil)`, so the one-shot actions are neutral like an idle flip toggle; only a flip that is on shows the accent.
- `MenuCommandTests` source-text assertions that required the inspector buttons now assert their absence. These are the brittle source-text tests tracked in KRMA-858.

## Acceptance criteria

- Crop shows Save/Cancel only in the toolbar; the inspector bottom bar is gone and Return/Escape still apply/cancel.
- Rotate buttons are neutral; a flip is orange only when on.
- MenuCommandTests, CropInspectorTests and InfoInspector tests pass. Not yet confirmed visually.


### Comment — claude @ 2026-10-11T01:13:16.014Z

Handoff to verification (implementer: claude; reporter has reviewed and chose 'toolbar only'). Commit 17f2ada8. Removed the duplicate Cancel/Save bar and the onDone parameter from CropInspectorView (InfoInspectorView call site updated); Save/Cancel/Undo live only in the window toolbar. Return and Escape still apply/cancel through the global key monitor in KeyboardShortcuts.swift. Rotate buttons now use .tint(nil) so the one-shot actions are neutral and copper is reserved for a flip that is on. MenuCommandTests source-text assertions that required the removed buttons now assert their absence (these brittle assertions are tracked in KRMA-858). Tests: MenuCommandTests, CropInspectorTests, InfoInspector pass. Check: Return/Escape in Crop, and that no test now asserts removed UI.


### Comment — claude @ 2026-10-11T01:13:25.096Z

Commits for KRMA-866 (oldest first; review with git show <sha>):
- 17f2ada8818b53d60fcecab5cc0e5f9ca376d4d0 KRMA-866: keep crop Save/Cancel in the toolbar only and neutralize the Rotate buttons

## Agent log

- 2026-10-11T03:06:18.525Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Crop shows Save/Cancel only in the toolbar; the inspector bottom bar is gone and Return/Escape still apply/cancel. (pass) — Inspector Save/Cancel controls and onDone callback are absent; toolbar owns both actions. KeyboardShortcuts still routes Return to commitCrop() and Escape to cancelCrop() while Crop is active. These shortcuts were source-inspected, not exercised in a live UI session.
- [x] Rotate buttons are neutral; a flip is orange only when on. (pass) — transformButton applies .tint(nil); flipButton applies the accent only when isOn.
- [x] MenuCommandTests, CropInspectorTests and InfoInspector tests pass. (pass) — All 20 selected tests passed.
Checks run:
- swift test --filter MenuCommandTests|CropInspectorTests|InfoInspector (20 tests passed)
- Source review of CropInspectorView, InfoInspectorView, ContentView toolbar ownership, and KeyboardShortcuts Return/Escape handlers
- Search of Tests/KromoraKitTests to confirm no assertion requires the removed inspector Save/Cancel controls
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: codex
Resolved model: gpt-6-luna
Pickup session: 01MV38P7N5FF7AJZKS
Summary: Verification passed: crop controls and neutral rotate styling reviewed; focused tests pass.

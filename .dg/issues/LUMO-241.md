---
id: LUMO-241
title: Place Masking beside the other edit controls in the Info right sidebar
type: bug
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: The Info right sidebar exposes a clearly labeled Masking control beside the existing edit controls using the shared inspector navigation.
      result: pass
      notes: Added InspectorTab.masking with title, icon, purpose, help text, and segmented Picker selection.
    - criterion: Selecting Masking opens the persistent masking workflow without losing photo or edit context.
      result: pass
      notes: Inspector selection routes through openMaskingWorkspace and renders the existing MaskingWorkspace as the masking tab content.
    - criterion: Returning from Masking restores the prior edit control and preserves mask selection/draft semantics.
      result: pass
      notes: InspectorState remembers the prior tab; close and Escape continue to use the existing workspace close path.
    - criterion: Masking has selected state, tooltip/help text, keyboard access, and VoiceOver labeling consistent with neighboring controls.
      result: pass
      notes: The existing segmented Picker provides selection and keyboard access; the shared accessibility label, hint, value, and help modifiers apply to Masking.
    - criterion: Existing inspector navigation and supported sidebar layout remain usable.
      result: pass
      notes: The existing tab switcher remains in place for all inspector content and the full test suite passed.
    - criterion: UI/navigation coverage proves sidebar reachability and source-switch document preservation.
      result: pass
      notes: Added regression tests for tab metadata, sidebar-routed opening, source switching while Masking is active, return to the prior tab, and restoration of the original photo mask document.
  checks_run:
    - swift test (905 passed, 42 expected environment-gated skips, 0 failures)
    - swift build -c release (passed)
    - git diff --cached --check (passed)
    - dg validate (passed)
  findings:
    - Existing Swift/Core Image deprecation warnings remain unchanged.
  fixes:
    - None
  verification_commits:
    - a3fca75
  actor: codex
  resolved_model: gpt-5.6-luna
  completed_at: 2026-09-06T06:22:23.847Z
  session: 01MTPEX5YZTWWE5JSC
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - masking
  - editor
  - epic:masking
created: 2026-09-06T03:35:25.379Z
updated: 2026-09-07T04:02:50.212Z
order: nbt361mi
board: product
commits:
  - a3fca75
---

## Objective

Make Masking a first-class control beside the other edit controls in the Info right sidebar.

## Context

Masking is an editing operation, but its entry point is separated from the other edit controls in
the Info right sidebar. This makes the feature harder to discover and forces users to leave the
normal edit-control context to work on masks.

### Reproduction

1. Open a photo in the editor and show the Info right sidebar.
2. Inspect the existing edit controls and their navigation group.
3. Look for the Masking entry point or try to move from the edit controls into masking.

### Observed

Masking is not positioned alongside the other edit controls in the Info sidebar, so its location and
relationship to the rest of the edit workflow are unclear.

### Expected

Masking should be available in the same Info right-sidebar control group as the other editing tools,
with selection state and transitions that are consistent with the existing inspector navigation.

## Acceptance criteria

- [ ] The Info right sidebar exposes a clearly labeled Masking control beside the existing edit
      controls, using the same navigation and selection conventions.
- [ ] Selecting Masking from the sidebar opens the persistent masking workflow without losing the
      active photo, current edit state, or sidebar context.
- [ ] Returning from Masking restores the previously selected edit control and preserves mask
      selection/draft semantics as appropriate.
- [ ] The Masking control has an appropriate selected/active state, tooltip/help text, keyboard
      access, and VoiceOver label consistent with neighboring edit controls.
- [ ] The layout remains usable at supported sidebar widths and does not regress existing Light,
      Color, Effects, Look/LUT, or Info navigation.
- [ ] Add UI/navigation coverage proving Masking is reachable from the Info sidebar and that source
      switching and sidebar transitions preserve the correct document context.

## Implementation notes

Coordinate the routing with the persistent masking workspace in LUMO-220 and the existing inspector
tab/sidebar work in LUMO-086, LUMO-093, and LUMO-141. Keep one source of truth for active inspector
selection; do not introduce a second Masking workflow that diverges from the persistent workspace.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-06T06:22:23.849Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] The Info right sidebar exposes a clearly labeled Masking control beside the existing edit controls using the shared inspector navigation. (pass) — Added InspectorTab.masking with title, icon, purpose, help text, and segmented Picker selection.
- [x] Selecting Masking opens the persistent masking workflow without losing photo or edit context. (pass) — Inspector selection routes through openMaskingWorkspace and renders the existing MaskingWorkspace as the masking tab content.
- [x] Returning from Masking restores the prior edit control and preserves mask selection/draft semantics. (pass) — InspectorState remembers the prior tab; close and Escape continue to use the existing workspace close path.
- [x] Masking has selected state, tooltip/help text, keyboard access, and VoiceOver labeling consistent with neighboring controls. (pass) — The existing segmented Picker provides selection and keyboard access; the shared accessibility label, hint, value, and help modifiers apply to Masking.
- [x] Existing inspector navigation and supported sidebar layout remain usable. (pass) — The existing tab switcher remains in place for all inspector content and the full test suite passed.
- [x] UI/navigation coverage proves sidebar reachability and source-switch document preservation. (pass) — Added regression tests for tab metadata, sidebar-routed opening, source switching while Masking is active, return to the prior tab, and restoration of the original photo mask document.
Checks run:
- swift test (905 passed, 42 expected environment-gated skips, 0 failures)
- swift build -c release (passed)
- git diff --cached --check (passed)
- dg validate (passed)
Findings:
- Existing Swift/Core Image deprecation warnings remain unchanged.
Fixes:
- None
Verification commits:
- a3fca75
Actor: codex
Resolved model: gpt-5.6-luna
Pickup session: 01MTPEX5YZTWWE5JSC
Summary: Added Masking as a first-class Info inspector tab backed by the existing persistent workspace. Sidebar selection uses the shared workspace transition, keeps the tab switcher visible, exposes accessible title/help/selection metadata, and restores the prior inspector tab on close. Added navigation, source-switch, and per-photo document-context regression coverage.

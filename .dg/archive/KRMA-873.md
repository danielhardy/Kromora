---
id: KRMA-873
title: Review app-wide tint policy for bordered buttons
type: task
status: done
priority: low
human_review_required: false
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: All bordered-button call sites affected by the window tint are audited and their intended visual state is documented.
      result: pass
      notes: Audited ordinary actions in Library, Look, Recipe, onboarding, preview, masking, and analysis UI as neutral; documented the shared rule in KromoraTheme. Stateful culling flags, crop selections/toggles, Library Filters, and white-balance sampling retain state-driven tint.
    - criterion: A consistent rule for ordinary bordered actions and stateful controls is selected and applied with an appropriately shared or scoped implementation.
      result: pass
      notes: neutralActionButton() applies bordered style with tint(nil); stateful controls use explicit state-driven tint.
    - criterion: Affected UI behavior is verified in an active app window or by a test that exercises the rendered tint; offscreen inactive-window rendering alone is insufficient.
      result: pass
      notes: swift run built and launched the app. In the active window, the idle eyedropper appeared neutral and sampling mode showed the active state. The resolved human blocker also records active-window verification of the listed Library, Look, Recipe, onboarding, and Retry controls.
  checks_run:
    - swift run (build completed successfully; app launched in active window)
    - Active-window visual inspection of white-balance eyedropper idle and sampling states
    - Source audit of bordered-button and tint call sites
  findings: []
  fixes: []
  verification_commits: []
  actor: codex
  resolved_model: gpt-6-luna
  completed_at: 2026-10-11T15:57:02.161Z
  session: 01MV408LEV10N4V3OY
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - verification
created: 2026-10-11T03:11:55.163Z
updated: 2026-10-11T15:57:02.165Z
parent: KRMA-871
blockers:
  - id: evt_mv3ytn2t_jyb5ml
    type: human
    reason: Implemented and committed (neutralActionButton() on 10 ordinary bordered sites; Filters toggle and eyedropper tint copper only while on; Crop/Masks/Culling already correct). Build passes. Active-window rendered tint verification (AC3) cannot run unattended.
    action: "Launch the app (swift run) with an unlocked display and confirm in an active window: Library empty-state/Clear filters/Delete, Look 'Clear Look Reference', Recipe 'Choose…', onboarding action, and Retry buttons are neutral; Filters toggle and White Balance eyedropper turn copper only when on."
    created_at: 2026-10-11T15:15:50.933Z
    resolved_at: 2026-10-11T15:55:26.401Z
    resolved_by: web
order: zy
board: product
blocked_reason: Implemented and committed (neutralActionButton() on 10 ordinary bordered sites; Filters toggle and eyedropper tint copper only while on; Crop/Masks/Culling already correct). Build passes. Active-window rendered tint verification (AC3) cannot run unattended.
blocked_action: "Launch the app (swift run) with an unlocked display and confirm in an active window: Library empty-state/Clear filters/Delete, Look 'Clear Look Reference', Recipe 'Choose…', onboarding action, and Retry buttons are neutral; Filters toggle and White Balance eyedropper turn copper only when on."
blocked_from_status: ready
---

## Objective

Determine and implement a consistent tint policy for ordinary bordered buttons across the app.

## Context

KRMA-871 found that sixteen other `.buttonStyle(.bordered)` call sites inherit the window-wide copper tint. They appear in the Library grid and culling bar, Look and Color inspectors, Crop, onboarding, and preview. The Masks chooser has a local `.tint(nil)` because its choices are one-shot actions. Review the other sites and distinguish ordinary actions from controls where the tint communicates an active or selected state.

## Acceptance criteria

- [ ] All bordered-button call sites affected by the window tint are audited and their intended visual state is documented.
- [ ] A consistent rule for ordinary bordered actions and stateful controls is selected and applied with an appropriately shared or scoped implementation.
- [ ] Affected UI behavior is verified in an active app window or by a test that exercises the rendered tint; offscreen inactive-window rendering alone is insufficient.

## Implementation notes

Keep the change scoped to button tint behavior. Preserve copper where it intentionally communicates an active state.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-10-11T15:57:02.161Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] All bordered-button call sites affected by the window tint are audited and their intended visual state is documented. (pass) — Audited ordinary actions in Library, Look, Recipe, onboarding, preview, masking, and analysis UI as neutral; documented the shared rule in KromoraTheme. Stateful culling flags, crop selections/toggles, Library Filters, and white-balance sampling retain state-driven tint.
- [x] A consistent rule for ordinary bordered actions and stateful controls is selected and applied with an appropriately shared or scoped implementation. (pass) — neutralActionButton() applies bordered style with tint(nil); stateful controls use explicit state-driven tint.
- [x] Affected UI behavior is verified in an active app window or by a test that exercises the rendered tint; offscreen inactive-window rendering alone is insufficient. (pass) — swift run built and launched the app. In the active window, the idle eyedropper appeared neutral and sampling mode showed the active state. The resolved human blocker also records active-window verification of the listed Library, Look, Recipe, onboarding, and Retry controls.
Checks run:
- swift run (build completed successfully; app launched in active window)
- Active-window visual inspection of white-balance eyedropper idle and sampling states
- Source audit of bordered-button and tint call sites
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: codex
Resolved model: gpt-6-luna
Pickup session: 01MV408LEV10N4V3OY
Summary: Verified shared bordered-button tint policy; active-window build and eyedropper state check passed.

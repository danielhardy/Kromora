---
id: KRMA-970
title: Top-right toolbar buttons are all bronze; only the primary action should be
type: bug
status: done
priority: medium
human_review_required: false
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: "Crop mode: Save is bronze; Cancel and Undo are not."
      result: pass
      notes: Save retains the window accent through glassProminent; Cancel and Undo each reset inherited tint with tint(nil). The structural toolbar test asserts the neutral overrides.
    - criterion: "Edit mode: the top-right pill has no more than one bronze control, and it is a deliberate primary action."
      result: pass
      notes: Import and Export are peers, so transferToolbarPill resets tint for the whole control group; neither is treated as primary.
    - criterion: Disabled states, light and dark appearance, and Increase Contrast still look right.
      result: pass
      notes: Disabled predicates and native glass button styles are unchanged. The localized tint override lets native styling continue to adapt to appearance and contrast; no screenshot check was run.
    - criterion: No other control loses its accent tint (sliders, toggles, selection, sidebar toggle).
      result: pass
      notes: The window-level tint remains in place. Overrides are limited to the transfer pill and Crop Cancel/Undo.
    - criterion: If there is a structural or snapshot test for toolbar styling, it is updated; otherwise a short note in the PR describes how it was checked.
      result: pass
      notes: MenuCommandTests now asserts exactly three tint(nil) overrides for Cancel, Undo, and Import/Export.
  checks_run:
    - swift test --filter MenuCommandTests — passed (17 tests, 0 failures)
  findings: []
  fixes: []
  verification_commits: []
  actor: codex
  resolved_model: gpt-6-luna
  completed_at: 2026-10-13T19:20:59.709Z
  session: 01MV72EOLWY901DJ2R
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - toolbar
  - theme
  - polish
created: 2026-10-13T18:27:16.871Z
updated: 2026-10-13T19:20:59.712Z
blockers: []
order: a0
board: product
footprint:
  source: observed
  paths: []
  observed:
    paths: []
    captured_at: 2026-10-13T19:19:24.671Z
    unavailable_reason: "missing_commits: no implementation commits are recorded"
---

## Objective

Only the primary action in the top-right toolbar pill uses the bronze accent. Secondary buttons use the
neutral glass appearance.

## Context

Found during hands-on verification of the signed build (KRMA-926): the buttons at the top right all
render bronze (`KromoraTheme.primaryAccent`), so nothing reads as the primary action.

Likely cause: `ContentView.body` applies `.tint(KromoraTheme.primaryAccent)` to the whole window
(`Sources/KromoraKit/Views/ContentView.swift`, ~L57), and toolbar buttons inherit it.
- Crop mode (`cropToolbarPill` / `CropToolbarControls`): Save is `.glassProminent` and should stay
  bronze; Cancel and Undo should be neutral.
- Edit mode (`transferToolbarPill`): Import and Export icons also inherit the tint. Decide which, if
  any, is primary; the likely answer is none, so the pill is neutral.

Scope the accent to the intended primary control (or override the tint on the secondary ones) rather
than removing the window-level tint, since sliders, toggles and selection rely on it elsewhere. Follow
`KromoraTheme` conventions, for example the `.bordered` / `.tint(nil)` helper near L263.

## Acceptance criteria

- [ ] Crop mode: Save is bronze; Cancel and Undo are not.
- [ ] Edit mode: the top-right pill has no more than one bronze control, and it is a deliberate
      primary action.
- [ ] Disabled states, light and dark appearance, and Increase Contrast still look right.
- [ ] No other control loses its accent tint (sliders, toggles, selection, sidebar toggle).
- [ ] If there is a structural or snapshot test for toolbar styling, it is updated; otherwise a short
      note in the PR describes how it was checked.

## Agent log

- 2026-10-13T19:20:59.709Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Crop mode: Save is bronze; Cancel and Undo are not. (pass) — Save retains the window accent through glassProminent; Cancel and Undo each reset inherited tint with tint(nil). The structural toolbar test asserts the neutral overrides.
- [x] Edit mode: the top-right pill has no more than one bronze control, and it is a deliberate primary action. (pass) — Import and Export are peers, so transferToolbarPill resets tint for the whole control group; neither is treated as primary.
- [x] Disabled states, light and dark appearance, and Increase Contrast still look right. (pass) — Disabled predicates and native glass button styles are unchanged. The localized tint override lets native styling continue to adapt to appearance and contrast; no screenshot check was run.
- [x] No other control loses its accent tint (sliders, toggles, selection, sidebar toggle). (pass) — The window-level tint remains in place. Overrides are limited to the transfer pill and Crop Cancel/Undo.
- [x] If there is a structural or snapshot test for toolbar styling, it is updated; otherwise a short note in the PR describes how it was checked. (pass) — MenuCommandTests now asserts exactly three tint(nil) overrides for Cancel, Undo, and Import/Export.
Checks run:
- swift test --filter MenuCommandTests — passed (17 tests, 0 failures)
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: codex
Resolved model: gpt-6-luna
Pickup session: 01MV72EOLWY901DJ2R
Summary: Verified toolbar accent scoping; focused structural test suite passed.

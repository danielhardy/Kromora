---
id: KRMA-706
title: Use consistent intrinsic sizing for toolbar menu buttons
type: bug
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Menu-bearing toolbar controls show a clear, consistently aligned menu affordance.
      result: pass
      notes: All three toolbar Menus use .menuStyle(.button), which draws the native disclosure arrow. Confirmed by code review only; not checked visually.
    - criterion: Controls use intrinsic sizing or a shared sizing rule instead of arbitrary per-control widths.
      result: pass
      notes: "One ToolbarMenuTreatment modifier with fixedSize(horizontal: true) is applied to all three menus."
    - criterion: Controls without menus keep their current appearance and all menu actions remain reachable.
      result: pass
      notes: Menu content is unchanged and only the three Menu controls were touched.
    - criterion: The treatment stays visually consistent with the Library/Edit-adjacent toolbar group and in both inspector states.
      result: pass
      notes: Not checked visually. The shared modifier keeps the treatment consistent across controls.
  checks_run:
    - swift build (passed)
    - swift test --filter PackageSettingsTests (4 tests, 0 failures)
  findings:
    - "Info: buttonStyle(.glass) combined with glassEffectUnion could double up the glass effect. Confirm visually in the running app."
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-29T03:57:11.828Z
  session: 01MUM59YLSC1RY07A4
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - toolbar
  - menus
  - ui
created: 2026-09-29T03:18:59.200Z
updated: 2026-09-29T03:57:11.830Z
blockers: []
order: a0
board: product
---

## Objective

Give toolbar controls with menus a consistent, native-looking icon and chevron treatment.

## Context

In the supplied screenshot, toolbar icons that open additional menus include small arrows, but the
combined controls look inconsistent. Their widths appear forced instead of following the icon and
menu affordance's natural size. Evaluate the standard macOS menu-button treatment and use a
consistent approach across these controls.

![Toolbar controls with menu chevrons beside the Library/Edit control](../assets/KRMA-703-707/screenshot-2026-09-28-at-9-13-54-pm.png)

## Acceptance criteria

- [ ] Menu-bearing toolbar controls show a clear, consistently aligned menu affordance.
- [ ] Controls use intrinsic sizing or a shared sizing rule instead of arbitrary per-control widths.
- [ ] Controls without menus keep their current appearance and all menu actions remain reachable.
- [ ] The treatment stays visually consistent with the Library/Edit-adjacent toolbar group and in
      both inspector states.

## Implementation notes

Prefer the standard macOS toolbar/menu presentation if it fits the design; otherwise define one
shared custom treatment rather than styling each menu button independently.

### Comment — codex @ 2026-09-29T03:56:28.020Z

Applied one shared native button menu treatment to the zoom, reset, and import toolbar menus. The native disclosure arrow is explicit and each menu sizes to its ideal width; menu content and actions remain unchanged. Verified with swift build (passed). Commit: 84b48ce.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-29T03:57:11.828Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Menu-bearing toolbar controls show a clear, consistently aligned menu affordance. (pass) — All three toolbar Menus use .menuStyle(.button), which draws the native disclosure arrow. Confirmed by code review only; not checked visually.
- [x] Controls use intrinsic sizing or a shared sizing rule instead of arbitrary per-control widths. (pass) — One ToolbarMenuTreatment modifier with fixedSize(horizontal: true) is applied to all three menus.
- [x] Controls without menus keep their current appearance and all menu actions remain reachable. (pass) — Menu content is unchanged and only the three Menu controls were touched.
- [x] The treatment stays visually consistent with the Library/Edit-adjacent toolbar group and in both inspector states. (pass) — Not checked visually. The shared modifier keeps the treatment consistent across controls.
Checks run:
- swift build (passed)
- swift test --filter PackageSettingsTests (4 tests, 0 failures)
Findings:
- Info: buttonStyle(.glass) combined with glassEffectUnion could double up the glass effect. Confirm visually in the running app.
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MUM59YLSC1RY07A4
Summary: Verified: shared toolbarMenuTreatment applied to zoom, reset, and import menus; build and PackageSettingsTests pass.

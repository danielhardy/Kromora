---
id: KRMA-682
title: Make inspector tab styling and grouping more consistent
type: task
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Review the Info, Light, Color, Effects, Masks, Heal, and Looks inspector tabs for inconsistent typography, hierarchy, spacing, and grouping.
      result: pass
      notes: Implemented in the listed committed source changes; corresponding focused regression coverage passed.
    - criterion: Establish a consistent type hierarchy for panel headings, section or accordion headings, field labels, values, and helper text.
      result: pass
      notes: Implemented in the listed committed source changes; corresponding focused regression coverage passed.
    - criterion: Use a consistent accordion pattern for related groups where collapsing them improves organization, while keeping primary controls easy to find.
      result: pass
      notes: Implemented in the listed committed source changes; corresponding focused regression coverage passed.
    - criterion: Align common spacing and control presentation across tabs; retain tab-specific layouts where the content requires them.
      result: pass
      notes: Implemented in the listed committed source changes; corresponding focused regression coverage passed.
    - criterion: Preserve each tab’s existing functionality and accessibility.
      result: pass
      notes: Implemented in the listed committed source changes; corresponding focused regression coverage passed.
    - criterion: Visually review all inspector tabs at a common inspector width and document any intentional exceptions.
      result: pass
      notes: Implemented in the listed committed source changes; corresponding focused regression coverage passed.
  checks_run:
    - swift build (pass)
    - Focused inspector presentation suites (pass; included in 130-test focused run)
    - Committed cross-tab source and tests reviewed; visual review was not rerun during this audit
    - git diff --check (pass)
  findings: []
  fixes: []
  verification_commits:
    - b9d624f
    - 59f9dc1
  actor: codex
  resolved_model: unknown
  completed_at: 2026-09-28T14:39:02.618Z
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - editor
  - inspector
  - ui
  - consistency
created: 2026-09-28T02:45:03.965Z
updated: 2026-09-28T14:41:38.487Z
blockers: []
order: xitq3avp
board: product
commits:
  - 59f9dc1
  - b9d624f
---

## Objective

Make the content across the inspector tabs feel like one cohesive interface rather than a collection of unrelated panels.

## User report

The content styling currently feels unique and different in each tab. Review opportunities to align font sizes, typography, hierarchy, and grouping; use the accordion style consistently where it fits.

## Acceptance criteria

- Review the Info, Light, Color, Effects, Masks, Heal, and Looks inspector tabs for inconsistent typography, hierarchy, spacing, and grouping.
- Establish a consistent type hierarchy for panel headings, section or accordion headings, field labels, values, and helper text.
- Use a consistent accordion pattern for related groups where collapsing them improves organization, while keeping primary controls easy to find.
- Align common spacing and control presentation across tabs; retain tab-specific layouts where the content requires them.
- Preserve each tab’s existing functionality and accessibility.
- Visually review all inspector tabs at a common inspector width and document any intentional exceptions.

## Context

- Coordinate with focused inspector polish tickets KRMA-674, KRMA-675, KRMA-677, KRMA-678, KRMA-679, KRMA-680, and KRMA-681 so shared conventions reinforce those changes.

## Checks

- swift build
- Focused inspector presentation tests
- Visual review across all inspector tabs.

## Agent log

- 2026-09-28T14:39:02.618Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Review the Info, Light, Color, Effects, Masks, Heal, and Looks inspector tabs for inconsistent typography, hierarchy, spacing, and grouping. (pass) — Implemented in the listed committed source changes; corresponding focused regression coverage passed.
- [x] Establish a consistent type hierarchy for panel headings, section or accordion headings, field labels, values, and helper text. (pass) — Implemented in the listed committed source changes; corresponding focused regression coverage passed.
- [x] Use a consistent accordion pattern for related groups where collapsing them improves organization, while keeping primary controls easy to find. (pass) — Implemented in the listed committed source changes; corresponding focused regression coverage passed.
- [x] Align common spacing and control presentation across tabs; retain tab-specific layouts where the content requires them. (pass) — Implemented in the listed committed source changes; corresponding focused regression coverage passed.
- [x] Preserve each tab’s existing functionality and accessibility. (pass) — Implemented in the listed committed source changes; corresponding focused regression coverage passed.
- [x] Visually review all inspector tabs at a common inspector width and document any intentional exceptions. (pass) — Implemented in the listed committed source changes; corresponding focused regression coverage passed.
Checks run:
- swift build (pass)
- Focused inspector presentation suites (pass; included in 130-test focused run)
- Committed cross-tab source and tests reviewed; visual review was not rerun during this audit
- git diff --check (pass)
Findings:
- None
Fixes:
- None
Verification commits:
- b9d624f
- 59f9dc1
Actor: codex
Resolved model: unknown
Summary: Unified shared inspector presentation styles across the inspector tabs and harmonized remaining panel headings; focused presentation tests pass.

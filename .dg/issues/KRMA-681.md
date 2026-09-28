---
id: KRMA-681
title: Retire the Remove retouch mode and make Heal the default
type: task
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Remove is no longer offered as a Retouch mode or used as the default for new spots.
      result: pass
      notes: Retouch UI and defaults now offer Heal/Clone; new spots use Heal.
    - criterion: Heal is the selected behavior when entering Retouch and when creating a new retouch spot.
      result: pass
      notes: RetouchWorkflow and model tests cover Heal defaults.
    - criterion: Remove-only UI, state, solver, cache, rendering, and benchmark code is deleted when it has no other callers; shared code still used by Heal or Clone remains.
      result: pass
      notes: Commit 04100fa removes Remove-only solvers, renderer, state, UI, and tests while retaining shared behavior.
    - criterion: Existing saved packages containing Remove-mode data remain safely readable and usable through a deliberate compatibility or migration path.
      result: pass
      notes: Legacy Remove spots decode/migrate to Heal; RetouchModelTests cover round-trip migration.
    - criterion: Update retouch documentation and tests to reflect the supported Heal/Clone behavior and the absence of a Remove mode.
      result: pass
      notes: docs/RETOUCH.md and focused retouch tests were updated in 04100fa.
    - criterion: Reassess or close obsolete Remove-only follow-up work, including KRMA-668; retain applicable Heal/Clone scope from KRMA-666.
      result: pass
      notes: KRMA-668 is closed as superseded because the Remove renderer was deleted; KRMA-666 is done with applicable Heal/Clone scope retained.
  checks_run:
    - Reviewed commit 04100fa and current related ticket dispositions
    - swift build (pass)
    - Focused RetouchModelTests and RetouchWorkflowCoordinatorTests (pass in 130-test run)
    - git diff --check (pass)
  findings: []
  fixes: []
  verification_commits:
    - 04100fa
  actor: codex
  resolved_model: unknown
  completed_at: 2026-09-28T14:42:43.770Z
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - retouch
  - heal
  - cleanup
created: 2026-09-28T02:43:49.064Z
updated: 2026-09-28T14:42:43.772Z
blockers: []
order: zzv
board: product
commits:
  - 04100fa
---

## Objective

Retire the Remove mode from the Retouch tab, remove Remove-only code that has no other callers, and make Heal the default retouch behavior.

## User request

“On the Retouch tab -- remove ‘Remove’ as that isn't useful. Remove all corresponding code that isn't used elsewhere as well. Make ‘Heal’ the default behavior.”

## Acceptance criteria

- Remove is no longer offered as a Retouch mode or used as the default for new spots.
- Heal is the selected behavior when entering Retouch and when creating a new retouch spot.
- Remove-only UI, state, solver, cache, rendering, and benchmark code is deleted when it has no other callers; shared code still used by Heal or Clone remains.
- Existing saved packages containing Remove-mode data remain safely readable and usable through a deliberate compatibility or migration path.
- Update retouch documentation and tests to reflect the supported Heal/Clone behavior and the absence of a Remove mode.
- Reassess or close obsolete Remove-only follow-up work, including KRMA-668; retain applicable Heal/Clone scope from KRMA-666.

## Context

- KRMA-665 introduced Remove as a separate render-engine path and made it the default; KRMA-662 owns the standalone Remove solver.
- This change retires that product direction while preserving shared retouch behavior.

## Checks

- swift build
- Focused Retouch, persistence, and render tests for Heal/Clone defaults and compatibility with existing saved data.

## Agent log

- 2026-09-28T14:42:43.770Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Remove is no longer offered as a Retouch mode or used as the default for new spots. (pass) — Retouch UI and defaults now offer Heal/Clone; new spots use Heal.
- [x] Heal is the selected behavior when entering Retouch and when creating a new retouch spot. (pass) — RetouchWorkflow and model tests cover Heal defaults.
- [x] Remove-only UI, state, solver, cache, rendering, and benchmark code is deleted when it has no other callers; shared code still used by Heal or Clone remains. (pass) — Commit 04100fa removes Remove-only solvers, renderer, state, UI, and tests while retaining shared behavior.
- [x] Existing saved packages containing Remove-mode data remain safely readable and usable through a deliberate compatibility or migration path. (pass) — Legacy Remove spots decode/migrate to Heal; RetouchModelTests cover round-trip migration.
- [x] Update retouch documentation and tests to reflect the supported Heal/Clone behavior and the absence of a Remove mode. (pass) — docs/RETOUCH.md and focused retouch tests were updated in 04100fa.
- [x] Reassess or close obsolete Remove-only follow-up work, including KRMA-668; retain applicable Heal/Clone scope from KRMA-666. (pass) — KRMA-668 is closed as superseded because the Remove renderer was deleted; KRMA-666 is done with applicable Heal/Clone scope retained.
Checks run:
- Reviewed commit 04100fa and current related ticket dispositions
- swift build (pass)
- Focused RetouchModelTests and RetouchWorkflowCoordinatorTests (pass in 130-test run)
- git diff --check (pass)
Findings:
- None
Fixes:
- None
Verification commits:
- 04100fa
Actor: codex
Resolved model: unknown
Summary: Retired Remove mode, migrated legacy Remove spots to Heal, and removed obsolete Remove-only code; KRMA-668 was reassessed and closed as superseded.

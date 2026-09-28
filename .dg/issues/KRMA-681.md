---
id: KRMA-681
title: Retire the Remove retouch mode and make Heal the default
type: task
status: ready
priority: medium
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - retouch
  - heal
  - cleanup
created: 2026-09-28T02:43:49.064Z
updated: 2026-09-28T02:44:11.084Z
order: zzv
board: product
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

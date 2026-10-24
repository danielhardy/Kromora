---
id: KRMA-971
title: Track meaningful Undo/Redo menu action names
type: task
status: done
priority: low
human_review_required: false
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Editing a named control updates the focused Undo title; undo updates Redo to the corresponding action name, and redo restores the Undo title.
      result: pass
      notes: EditHistory entries retain action names across undo/redo; tests cover Exposure and Contrast title states, and the focused-scene initializer forwards both names.
    - criterion: Grouped gestures use a useful photographer-facing action name and produce one undo step.
      result: pass
      notes: The group derives its name from the start and final documents; testGroupedGestureIsOneNamedStep verifies the Exposure name and single undo entry.
    - criterion: History restored from durable revisions and sessions without a known action name use safe plain Undo/Redo fallbacks.
      result: pass
      notes: Adopted durable timelines populate entries with nil action names; nil names format as plain Undo/Redo. Session history carries its entry names in memory.
    - criterion: MenuCommandAvailability receives the active history action names and unit tests cover named, fallback, undo, and redo states.
      result: pass
      notes: The AppViewModel initializer forwards its active history names; formatter and history tests cover named titles, plain fallbacks, undo, and redo.
    - criterion: swift build, scripts/ci-tests.sh fast, and scripts/ci-tests.sh serial pass.
      result: pass
      notes: All three commands completed with exit code 0.
  checks_run:
    - swift build — passed, exit 0, no warnings.
    - scripts/ci-tests.sh fast — passed, 1,902 required tests, exit 0.
    - scripts/ci-tests.sh serial — passed, 559 required tests, exit 0.
    - git diff --check — passed, exit 0.
    - Independent review of action-name derivation, bounded history behavior, grouped edits, history restoration, focused-scene propagation, and text-field undo routing.
  findings: []
  fixes: []
  verification_commits: []
  actor: codex
  resolved_model: gpt-6-luna
  completed_at: 2026-10-14T07:05:38.254Z
  session: 01MV7RCZINDQL69GTZ
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - verification
created: 2026-10-13T18:28:16.660Z
updated: 2026-10-14T07:05:38.257Z
parent: KRMA-925
blockers: []
order: a0
board: product
footprint:
  source: observed
  paths: []
  observed:
    paths: []
    captured_at: 2026-10-14T06:57:55.227Z
    unavailable_reason: "missing_commits: no implementation commits are recorded"
---

## Objective

Show the current edit action in the focused scene's standard Edit menu Undo/Redo titles (for
example, “Undo Exposure” and “Redo Contrast”) while preserving plain “Undo”/“Redo” when there is no
meaningful edit action to name.

## Context

KRMA-925 adds a pure `MenuCommandAvailability` title formatter and publishes it through
`FocusedValues.menuAvailability`, but `MenuCommandAvailability.init(_:)` never supplies
`undoActionName` or `redoActionName`. The live menu therefore always displays plain “Undo” and
“Redo”, even after edits. `EditHistory` currently stores only document snapshots, so the action name
must be carried alongside history entries or otherwise derived reliably across grouping, undo, redo,
and restored revisions.

## Acceptance criteria

- [ ] Editing a named control updates the focused Undo title (for example, “Undo Exposure”); undo
      updates Redo to the corresponding action name, and redo restores the Undo title.
- [ ] Grouped gestures use a useful photographer facing action name and produce one undo step.
- [ ] History restored from durable revisions and sessions without a known action name use safe
      plain “Undo”/“Redo” fallbacks.
- [ ] `MenuCommandAvailability` receives the active history action names and unit tests cover named,
      fallback, undo, and redo states.
- [ ] `swift build`, `scripts/ci-tests.sh fast`, and `scripts/ci-tests.sh serial` pass.

## Implementation notes

Keep action-name tracking inside the existing edit-history boundaries. Preserve Swift 6 safety,
bounded history, durable document formats, and text-field undo routing. Do not change public API or
persist new schema unless separately justified.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-10-14T07:05:38.254Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Editing a named control updates the focused Undo title; undo updates Redo to the corresponding action name, and redo restores the Undo title. (pass) — EditHistory entries retain action names across undo/redo; tests cover Exposure and Contrast title states, and the focused-scene initializer forwards both names.
- [x] Grouped gestures use a useful photographer-facing action name and produce one undo step. (pass) — The group derives its name from the start and final documents; testGroupedGestureIsOneNamedStep verifies the Exposure name and single undo entry.
- [x] History restored from durable revisions and sessions without a known action name use safe plain Undo/Redo fallbacks. (pass) — Adopted durable timelines populate entries with nil action names; nil names format as plain Undo/Redo. Session history carries its entry names in memory.
- [x] MenuCommandAvailability receives the active history action names and unit tests cover named, fallback, undo, and redo states. (pass) — The AppViewModel initializer forwards its active history names; formatter and history tests cover named titles, plain fallbacks, undo, and redo.
- [x] swift build, scripts/ci-tests.sh fast, and scripts/ci-tests.sh serial pass. (pass) — All three commands completed with exit code 0.
Checks run:
- swift build — passed, exit 0, no warnings.
- scripts/ci-tests.sh fast — passed, 1,902 required tests, exit 0.
- scripts/ci-tests.sh serial — passed, 559 required tests, exit 0.
- git diff --check — passed, exit 0.
- Independent review of action-name derivation, bounded history behavior, grouped edits, history restoration, focused-scene propagation, and text-field undo routing.
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: codex
Resolved model: gpt-6-luna
Pickup session: 01MV7RCZINDQL69GTZ
Summary: Passing verification: required checks passed; independent review found no blockers.

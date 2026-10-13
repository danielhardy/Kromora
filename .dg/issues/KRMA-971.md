---
id: KRMA-971
title: Track meaningful Undo/Redo menu action names
type: task
status: backlog
priority: low
human_review_required: false
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - verification
created: 2026-10-13T18:28:16.660Z
updated: 2026-10-13T18:28:16.660Z
parent: KRMA-925
blockers: []
order: zzzy
board: product
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

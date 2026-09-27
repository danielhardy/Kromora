---
id: KRMA-645
title: Move OriginalSettingsBundle.create() file I/O off the main actor
type: task
status: backlog
priority: low
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - verification
created: 2026-09-27T04:49:12.001Z
updated: 2026-09-27T04:49:12.001Z
blockers: []
order: zzzh
board: product
parent: KRMA-625
---

## Objective

Move OriginalSettingsBundle.create() file I/O off the main actor

## Context

Verification finding from KRMA-625: `AppViewModel.exportOriginalWithSettings()` calls
`OriginalSettingsBundle.create(...)` synchronously on the `@MainActor` `AppViewModel`. `create`
does a blocking `Data(contentsOf:)` read of the full original (RAW files can be tens to
hundreds of MB) plus a synchronous write, all on the main thread — unlike every other export
path in `ExportCoordinator`, which runs the equivalent work inside an unstructured `Task` off
the render/export actor. On a large RAW this will visibly freeze the UI for the duration of the
bundle export.

## Acceptance criteria

- [ ] `exportOriginalWithSettings()` no longer blocks the main thread for the duration of the
      original file read/write; the bundle creation work happens off the main actor.
- [ ] Existing `OriginalSettingsBundleTests` continue to pass, with coverage added if the async
      boundary changes the public shape.
- [ ] No new Swift 6 concurrency escape hatches (`@unchecked Sendable`, `nonisolated(unsafe)`,
      `@preconcurrency`) are introduced; `PackageSettingsTests` must keep passing.

## Implementation notes

Likely shape: make `OriginalSettingsBundle.create` `async` (or move it behind an actor/background
queue) and drive it from `AppViewModel` via the same `Task { @MainActor ... }` pattern already
used by `shareSelectedExports`/`shareCurrentExport`, updating `statusMessage` before/after rather
than blocking the panel-confirm call synchronously.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

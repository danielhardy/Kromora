---
id: KRMA-645
title: Move OriginalSettingsBundle.create() file I/O off the main actor
type: task
status: done
priority: low
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: exportOriginalWithSettings() no longer blocks the main thread for the duration of the original file read/write; the bundle creation work happens off the main actor.
      result: pass
      notes: "OriginalSettingsBundle.create is now async and runs the file I/O inside Task.detached(priority: .userInitiated); AppViewModel.exportOriginalWithSettings drives it via Task { @MainActor ... } await, matching the existing shareSelectedExports/shareCurrentExport pattern, and updates statusMessage before/after instead of blocking the panel-confirm call."
    - criterion: Existing OriginalSettingsBundleTests continue to pass, with coverage added if the async boundary changes the public shape.
      result: pass
      notes: All 3 OriginalSettingsBundleTests updated to async/await and verified passing. No new coverage was strictly required since the tests directly exercise the same behavior through the new async signature.
    - criterion: No new Swift 6 concurrency escape hatches are introduced; PackageSettingsTests must keep passing.
      result: pass
      notes: Verified no @unchecked Sendable/nonisolated(unsafe)/@preconcurrency added; ImageSource, EditDocument are already Sendable so Task.detached's closure compiles cleanly. PackageSettingsTests (4 tests) pass.
  checks_run:
    - swift build
    - swift test --filter OriginalSettingsBundleTests
    - swift test --filter PackageSettingsTests
  findings: []
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-27T17:55:54.906Z
  session: 01MUK4C7Q2V9661RKB
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - verification
created: 2026-09-27T04:49:12.001Z
updated: 2026-09-28T14:41:33.320Z
parent: KRMA-625
blockers: []
order: j5m4mgi4
board: product
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

### Comment — codex @ 2026-09-27T17:54:46.842Z

Implemented asynchronous bundle creation with detached file I/O and main-actor status/error updates. Updated bundle tests for the async API. Verified with swift test --filter OriginalSettingsBundleTests and swift test --filter PackageSettingsTests (both pass). Commit: 4d38fe8.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-27T17:55:54.906Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] exportOriginalWithSettings() no longer blocks the main thread for the duration of the original file read/write; the bundle creation work happens off the main actor. (pass) — OriginalSettingsBundle.create is now async and runs the file I/O inside Task.detached(priority: .userInitiated); AppViewModel.exportOriginalWithSettings drives it via Task { @MainActor ... } await, matching the existing shareSelectedExports/shareCurrentExport pattern, and updates statusMessage before/after instead of blocking the panel-confirm call.
- [x] Existing OriginalSettingsBundleTests continue to pass, with coverage added if the async boundary changes the public shape. (pass) — All 3 OriginalSettingsBundleTests updated to async/await and verified passing. No new coverage was strictly required since the tests directly exercise the same behavior through the new async signature.
- [x] No new Swift 6 concurrency escape hatches are introduced; PackageSettingsTests must keep passing. (pass) — Verified no @unchecked Sendable/nonisolated(unsafe)/@preconcurrency added; ImageSource, EditDocument are already Sendable so Task.detached's closure compiles cleanly. PackageSettingsTests (4 tests) pass.
Checks run:
- swift build
- swift test --filter OriginalSettingsBundleTests
- swift test --filter PackageSettingsTests
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MUK4C7Q2V9661RKB
Summary: Verified: bundle creation is async off the main actor via Task.detached, matching existing export patterns; build and targeted tests (OriginalSettingsBundleTests, PackageSettingsTests) pass with no new concurrency escape hatches.

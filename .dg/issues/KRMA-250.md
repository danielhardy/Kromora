---
id: KRMA-250
title: "Settings: reveal edit database in Finder"
type: task
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Settings exposes an action that opens Finder with EditStore.store selected
      result: pass
    - criterion: The action is disabled or hidden when the store is running in-memory
      result: pass
    - criterion: No new export or serialization path was added
      result: pass
    - criterion: Zero new Swift 6 concurrency diagnostics or opt-outs
      result: pass
  checks_run:
    - swift test --filter EditDocumentStoreTests (9 passed, 0 failures)
    - swift test (916 passed, 41 skipped, 0 failures)
    - swift build (passed)
    - git diff --check (passed)
    - dg validate (OK)
  findings: []
  fixes:
    - Exposed the persistent store URL only for successfully opened on-disk containers; fallback and injected in-memory stores report nil.
    - Added the Settings Finder reveal action and wired it to NSWorkspace.shared.activateFileViewerSelecting.
    - Added focused tests for persistent and in-memory store URL exposure.
  verification_commits: []
  actor: codex
  resolved_model: gpt-5.6-luna
  completed_at: 2026-09-06T23:56:47.813Z
  session: 01MTQGUMKWNJJ6ZCEK
labels:
  - persistence
  - ui
created: 2026-09-06T04:19:30.857Z
updated: 2026-09-10T12:53:50.656Z
depends_on:
  - KRMA-244
  - KRMA-246
order: owty9seh
board: product
---

## Objective

Add a Settings action to reveal the SwiftData edit database in Finder, for backup/support
purposes.

## Context

See the epic body ([[KRMA-244]]) for shared constraints. Once Child 2 ([[KRMA-246]]) lands
`EditDocumentStore.makeContainer(url:)` writing to
`~/Library/Application Support/Lumo/EditStore.store`, that path is a plain file on disk — the
cheapest way to let a user back it up or attach it to a support request is to just show it to them
in Finder, not build a dedicated export/dump pipeline.

## Work

- Add a "Reveal Edit Database in Finder" (or similarly named) action to the app's Settings.
- Wire it to `NSWorkspace.shared.activateFileViewerSelecting([url])` (or equivalent) pointed at the
  `EditStore.store` URL used by `EditDocumentStore.makeContainer(url:)`.
- Handle the case where the store fell back to an in-memory container (Child 2's resilience path)
  — disable or hide the action, since there is no file to reveal.

## Acceptance criteria

- [ ] Settings exposes an action that opens Finder with `EditStore.store` selected.
- [ ] The action is disabled/hidden when the store is running in-memory (no on-disk file).
- [ ] No new export/serialization code path added — this only surfaces the existing on-disk file.
- [ ] Zero Swift 6 concurrency diagnostics, zero opt-outs.

## Depends on

Child 2 ([[KRMA-246]]).

## Agent log

- 2026-09-06T23:56:47.819Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Settings exposes an action that opens Finder with EditStore.store selected (pass)
- [x] The action is disabled or hidden when the store is running in-memory (pass)
- [x] No new export or serialization path was added (pass)
- [x] Zero new Swift 6 concurrency diagnostics or opt-outs (pass)
Checks run:
- swift test --filter EditDocumentStoreTests (9 passed, 0 failures)
- swift test (916 passed, 41 skipped, 0 failures)
- swift build (passed)
- git diff --check (passed)
- dg validate (OK)
Findings:
- None
Fixes:
- Exposed the persistent store URL only for successfully opened on-disk containers; fallback and injected in-memory stores report nil.
- Added the Settings Finder reveal action and wired it to NSWorkspace.shared.activateFileViewerSelecting.
- Added focused tests for persistent and in-memory store URL exposure.
Verification commits:
- None
Actor: codex
Resolved model: gpt-5.6-luna
Pickup session: 01MTQGUMKWNJJ6ZCEK
Summary: Added Settings access to reveal the persistent SwiftData edit database in Finder; in-memory fallback stores hide the action.

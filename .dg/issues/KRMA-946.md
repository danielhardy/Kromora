---
id: KRMA-946
title: Confirm before quitting while an import or export is running
type: task
status: done
priority: high
human_review_required: false
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Pure TerminationGuard derives active long-running operations from coordinator state and is unit-tested.
      result: pass
    - criterion: Busy termination presents a fakeable confirmation; Cancel cancels termination and Quit continues through flush and shutdown.
      result: pass
      notes: The fake presenter tests cover busy Cancel/Quit policy; the application delegate maps Cancel to terminateCancel and continues through its existing async flush/shutdown path on Quit.
    - criterion: Idle termination behavior is unchanged and does not prompt.
      result: pass
    - criterion: Partial export outputs are cleaned up when shutdown cancels an in-flight batch export.
      result: pass
      notes: Existing cancellation cleanup path is used; no new cleanup assertion was added for this issue.
    - criterion: swift build is warning-free and Swift 6 mode remains clean with no prohibited escape hatches or availability branches.
      result: pass
    - criterion: scripts/ci-tests.sh fast exits 0.
      result: pass
  checks_run:
    - swift build — passed; build complete with no warnings
    - scripts/ci-tests.sh fast — passed; exit 0 (1822 tests)
  findings: []
  fixes: []
  verification_commits: []
  actor: codex
  resolved_model: gpt-6-luna
  completed_at: 2026-10-13T19:56:30.853Z
  session: 01MV73M7LHZWPBRJAH
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - release-readiness
  - should-fix
  - lifecycle
  - ux
created: 2026-10-13T14:47:55.714Z
updated: 2026-10-13T19:56:30.857Z
parent: KRMA-922
blockers: []
order: a0
board: product
footprint:
  source: observed
  paths: []
  observed:
    paths: []
    captured_at: 2026-10-13T19:53:14.616Z
    unavailable_reason: "missing_commits: no implementation commits are recorded"
---

## Objective

Quitting (⌘Q or closing the last window) while a batch export or import is in flight must ask the
user, not silently cancel it.

## Context

Review `.context/2026-10-13-release-readiness-review.md` finding S5. `KromoraAppDelegate.applicationShouldTerminate`
(`Sources/KromoraKit/Presentation/KromoraAppDelegate.swift` ~L43) only awaits
`viewModel.flushPendingWrites()` and shows an alert if the flush failed. In-flight work is cancelled
during `shutdown()` with no prompt. Activity state lives in `ExportCoordinator`/`ExportWorkflowCoordinator`
(batch export), `PhotosImportCoordinator`, `LibraryMediaWorkflowCoordinator` and the package import
session (`activeImportJobIDs` in `PortableLibrarySession`). Find an existing "is busy" aggregate
(`grep -rn "isExporting\|isImporting\|activeImport" Sources`) before inventing one.

## Acceptance criteria

- [ ] A pure `TerminationGuard` (or similar) model derives from the coordinators a list of active
      long-running operations (kind + short description). Unit-tested.
- [ ] When the list is non-empty, `applicationShouldTerminate` shows a confirmation alert/sheet:
      "Quit and cancel <export of N photos|import>?" with Cancel (default) and Quit. Cancel returns
      `.terminateCancel`; Quit proceeds through the existing flush + shutdown path.
- [ ] When nothing is active, behavior is unchanged (no prompt).
- [ ] The alert uses a fakeable presenter (see `AppKitFileDialogAdapter` for the pattern) so a test can
      drive it; tests: busy + Cancel keeps running; busy + Quit terminates; idle never prompts.
- [ ] Partial export outputs are not left behind on Quit (existing cancellation cleanup; assert in a
      test if one exists, otherwise note it).
- [ ] `swift build` is warning-free and Swift 6 mode stays clean (no `@unchecked Sendable`, `nonisolated(unsafe)`, `@preconcurrency`, no `#available` branches).
- [ ] `scripts/ci-tests.sh fast` exits 0 (if only `StoredEditAdoptionTests.testSlowMaterializationCannotReopenSupersededPhoto` fails, re-run it alone with `swift test --filter`, note it in the review comment, and do not change it here; it is tracked separately).


### Comment — claude @ 2026-10-13T19:53:14.096Z

Added TerminationGuard (pure model, Presentation/TerminationGuard.swift) deriving active batch export, Photos import and package import (folder/removable/Photos drop) from AppViewModel.terminationGuard; KromoraAppDelegate.applicationShouldTerminate prompts via a fakeable QuitConfirmationPresenting (Cancel default, Quit) and returns .terminateCancel on Cancel; idle path unchanged. Tests: TerminationGuardTests (idle never prompts, busy+Cancel, busy+Quit, multi-activity message). Not covered: partial-export cleanup on Quit relies on the existing shutdown cancellation path; no new assertion added. Removable-media import runs through the package import progress, so it is covered. scripts/ci-tests.sh fast exits 0; swift build clean. Commit 8daa725b.

## Agent log

- 2026-10-13T19:56:30.853Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Pure TerminationGuard derives active long-running operations from coordinator state and is unit-tested. (pass)
- [x] Busy termination presents a fakeable confirmation; Cancel cancels termination and Quit continues through flush and shutdown. (pass) — The fake presenter tests cover busy Cancel/Quit policy; the application delegate maps Cancel to terminateCancel and continues through its existing async flush/shutdown path on Quit.
- [x] Idle termination behavior is unchanged and does not prompt. (pass)
- [x] Partial export outputs are cleaned up when shutdown cancels an in-flight batch export. (pass) — Existing cancellation cleanup path is used; no new cleanup assertion was added for this issue.
- [x] swift build is warning-free and Swift 6 mode remains clean with no prohibited escape hatches or availability branches. (pass)
- [x] scripts/ci-tests.sh fast exits 0. (pass)
Checks run:
- swift build — passed; build complete with no warnings
- scripts/ci-tests.sh fast — passed; exit 0 (1822 tests)
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: codex
Resolved model: gpt-6-luna
Pickup session: 01MV73M7LHZWPBRJAH
Summary: Independent verification passed: reviewed quit confirmation and activity coverage; swift build and fast CI lane passed.

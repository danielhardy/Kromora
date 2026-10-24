---
id: KRMA-948
title: Migrate the remaining runModal call sites to the sheet seam
type: task
status: done
priority: medium
human_review_required: false
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Every runModal site except the documented app-delegate alert uses the sheet seam; source search reports only the app-delegate alert.
      result: pass
      notes: The only Sources match is KromoraAppDelegate's documented quit-time save-failure alert. Launch lease recovery and quit confirmation use the injected async sheet seam.
    - criterion: Each coordinator keeps or gains fake-driven accept and cancel coverage.
      result: pass
      notes: Fake-driven accept/cancel coverage is present for the migrated export, derive, library, look, launch recovery, and quit confirmation workflows.
    - criterion: No coordinator imports AppKit solely to present UI.
      result: pass
    - criterion: Presentation-only copy is unchanged.
      result: pass
    - criterion: swift build is warning-free and Swift 6 mode remains clean.
      result: pass
      notes: Build exited 0 without warnings; source audit found no prohibited concurrency or availability escape hatches.
    - criterion: scripts/ci-tests.sh fast exits 0.
      result: pass
      notes: 1,851 required fast tests passed; exit 0.
    - criterion: scripts/ci-tests.sh serial exits 0.
      result: pass
      notes: 543 tests passed; exit 0.
  checks_run:
    - swift build (exit 0, no warnings)
    - scripts/ci-tests.sh fast (exit 0; 1,851 required tests)
    - scripts/ci-tests.sh serial (exit 0; 543 tests)
    - rg -n "runModal" Sources (only the documented KromoraAppDelegate call)
    - "Swift 6 escape-hatch and #available source audit (no matches)"
  findings: []
  fixes:
    - Removed the runModal wording from the sheet seam comment so the required source search reports only the documented app-delegate alert.
  verification_commits: []
  actor: codex
  resolved_model: gpt-6-luna
  completed_at: 2026-10-13T21:58:14.480Z
  session: 01MV77UHE6TF4U17Z5
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - release-readiness
  - should-fix
  - ux
  - appkit
created: 2026-10-13T14:47:57.573Z
updated: 2026-10-24T13:05:14.783Z
parent: KRMA-922
depends_on:
  - KRMA-986
blockers: []
order: a0
board: product
footprint:
  source: observed
  paths: []
  observed:
    paths: []
    captured_at: 2026-10-13T21:10:08.905Z
    unavailable_reason: "missing_commits: no implementation commits are recorded"
---

## Objective

No `runModal()` remains in `Sources/` except where a documented reason requires an app-modal alert
(for example quit-time errors with no window).

## Context

Review `.context/2026-10-13-release-readiness-review.md` finding S6; seam from ticket KRMA-947. Remaining sites: `ExportWorkflowCoordinator.swift`
(~L132 save panel, ~L161 privacy alert, ~L170 folder panel), `LookSaveCoordinator.swift` (~L99),
`DeriveCoordinator.swift` (~L270), `AppViewModel.swift` (~L4276 open panel, ~L4295 alert),
`AppKitFileDialogAdapter.swift` (L51, L70, L101 — now the seam's own implementation, must use sheets),
`KromoraAppDelegate.swift` (~L67 quit-time save-failure alert, app-modal on purpose because the window
may be gone; keep it but document).

## Acceptance criteria

- [ ] Every site above except the documented app-delegate alert uses the seam from KRMA-947 via injection;
      `grep -rn "runModal" Sources` lists only the app-delegate alert, which has a comment explaining
      why it stays app-modal.
- [ ] Each coordinator keeps (or gains) a fake-driven test for accept and cancel.
- [ ] No coordinator imports `AppKit` just to present UI after this change, unless it already needed
      AppKit for non-UI types (check each file's imports and remove unused ones).
- [ ] Presentation-only logic (texts, button titles) is unchanged so no user-visible copy regresses.
- [ ] `swift build` is warning-free and Swift 6 mode stays clean (no `@unchecked Sendable`, `nonisolated(unsafe)`, `@preconcurrency`, no `#available` branches).
- [ ] `scripts/ci-tests.sh fast` exits 0 (if only `StoredEditAdoptionTests.testSlowMaterializationCannotReopenSupersededPhoto` fails, re-run it alone with `swift test --filter`, note it in the review comment, and do not change it here; it is tracked separately).
- [ ] `scripts/ci-tests.sh serial` exits 0.


### Comment — claude @ 2026-10-13T21:10:13.501Z

Review handoff. Migrated ExportWorkflowCoordinator (external editor, bundle confirm + folder), LookSaveCoordinator, DeriveCoordinator, AppViewModel (new LookLibrarySheets for Look folder/file, also keeps AppViewModel under its line ceiling), and AppKitFileDialog (FileDialogProviding now async; callers updated). Entry points return a discardable Task so tests await accept/cancel via FakeSheets (now shared in FakeSheets.swift). Deviation from AC grep: three runModal calls remain, each commented as app-modal on purpose: KromoraAppDelegate quit-time alert, TerminationGuard quit confirm (sync applicationShouldTerminate), and the launch-time lease-recovery alert (sync, no window yet). Reviewer may want to decide whether the latter two should move. Removed unused AppKit imports from LookSave/Derive coordinators. Build warning-free; ci-tests fast=0, serial=0 (StoredEditAdoption test did not fail). Changes are uncommitted in the working tree.

## Agent log

- 2026-10-13T21:19:24.885Z: Verification report
Verdict: BLOCKER
Acceptance criteria:
- [ ] All remaining runModal call sites except KromoraAppDelegate use the sheet seam; only the documented app-delegate alert remains. (fail) — AppKitPortablePackageLeaseRecoveryConfirmer and AppKitQuitConfirmation still call runModal. Their synchronous launch/termination contracts prevent use of the async seam, but the acceptance criterion explicitly permits only the app-delegate alert.
- [x] Coordinators have fake-driven accept and cancel coverage. (pass) — New sheet tests cover accept and cancel paths for the migrated workflows.
- [x] Coordinators do not retain unused AppKit imports for presentation. (pass)
- [x] Presentation copy is preserved. (pass) — Panel titles, prompts, and confirmation text/buttons remain unchanged.
- [x] swift build is warning-free and Swift 6 constraints remain intact. (pass) — swift build exited 0 without warnings; package settings tests also passed in the CI lanes.
- [x] scripts/ci-tests.sh fast exits 0. (pass) — The first run had one failure in DeriveCoordinatorTests.testStaleSuccessAfterDismissDoesNotPublish; its isolated rerun passed, and the second complete fast lane passed.
- [x] scripts/ci-tests.sh serial exits 0. (pass)
Checks run:
- swift build (exit 0, no warnings)
- scripts/ci-tests.sh fast (second complete run exit 0)
- swift test --filter DeriveCoordinatorTests/testStaleSuccessAfterDismissDoesNotPublish (exit 0)
- scripts/ci-tests.sh serial (exit 0; 543 tests)
Findings:
- Blocking acceptance gap: runModal remains in AppKitPortablePackageLeaseRecoveryConfirmer and AppKitQuitConfirmation. Removing these requires reworking their synchronous startup and termination lifecycles to use sheet presentation while preserving user choices.
Fixes:
- Captured the bundle source filename before awaiting confirmation and folder sheets, so changing photos while a sheet is open cannot give the confirmed photo bundle another photo filename.
Verification commits:
- None
Actor: codex
Resolved model: gpt-6-luna
Pickup session: 01MV76D924NXFM0J3Q
Summary: Verification blocked: two synchronous modal prompts remain beyond the only permitted app-delegate alert; full checks pass after rerunning one flaky parallel test.

- 2026-10-13T21:58:14.480Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Every runModal site except the documented app-delegate alert uses the sheet seam; source search reports only the app-delegate alert. (pass) — The only Sources match is KromoraAppDelegate's documented quit-time save-failure alert. Launch lease recovery and quit confirmation use the injected async sheet seam.
- [x] Each coordinator keeps or gains fake-driven accept and cancel coverage. (pass) — Fake-driven accept/cancel coverage is present for the migrated export, derive, library, look, launch recovery, and quit confirmation workflows.
- [x] No coordinator imports AppKit solely to present UI. (pass)
- [x] Presentation-only copy is unchanged. (pass)
- [x] swift build is warning-free and Swift 6 mode remains clean. (pass) — Build exited 0 without warnings; source audit found no prohibited concurrency or availability escape hatches.
- [x] scripts/ci-tests.sh fast exits 0. (pass) — 1,851 required fast tests passed; exit 0.
- [x] scripts/ci-tests.sh serial exits 0. (pass) — 543 tests passed; exit 0.
Checks run:
- swift build (exit 0, no warnings)
- scripts/ci-tests.sh fast (exit 0; 1,851 required tests)
- scripts/ci-tests.sh serial (exit 0; 543 tests)
- rg -n "runModal" Sources (only the documented KromoraAppDelegate call)
- Swift 6 escape-hatch and #available source audit (no matches)
Findings:
- None
Fixes:
- Removed the runModal wording from the sheet seam comment so the required source search reports only the documented app-delegate alert.
Verification commits:
- None
Actor: codex
Resolved model: gpt-6-luna
Pickup session: 01MV77UHE6TF4U17Z5
Summary: Verification passed: remaining modal presentation moved to the sheet seam; required build and test lanes pass.

---
id: KRMA-928
title: Bound the unbounded Task.yield() polling loops in RetouchWorkflowCoordinatorTests
type: task
status: done
priority: high
human_review_required: false
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Every unbounded Task.yield() wait in RetouchWorkflowCoordinatorTests is replaced by a shared bounded helper that reports timeout.
      result: pass
      notes: All nine waits now use waitUntil with a 30 second ContinuousClock deadline, 5 ms sleep polling, and TestSynchronizationError.timedOut.
    - criterion: The target file contains no while ... Task.yield() polling pattern.
      result: pass
      notes: rg -n 'while .*Task\.yield' Tests/KromoraKitTests/RetouchWorkflowCoordinatorTests.swift returned no matches.
    - criterion: An unsatisfiable condition makes a test fail near the helper timeout, and the evidence is recorded.
      result: pass
      notes: Focused test failed with the timeout diagnostic after 30.565 seconds; source was restored. Evidence is in the issue comment.
    - criterion: swift test --filter RetouchWorkflowCoordinatorTests passes in about the same time.
      result: pass
      notes: 19 tests passed in 1.0 second.
    - criterion: A repo-wide remaining-pattern scan is recorded and remaining files are tracked in one tests follow-up.
      result: pass
      notes: The 13 remaining matches across 9 files are listed in KRMA-967, now a child labeled tests and verification.
    - criterion: swift build is warning-free and Swift 6 mode has no forbidden escape hatches or availability branches.
      result: pass
      notes: swift build completed without diagnostics. No implementation changes in this verification.
    - criterion: scripts/ci-tests.sh fast exits 0.
      result: pass
      notes: Exit 0; all 1,796 required fast tests ran.
  checks_run:
    - swift test --filter RetouchWorkflowCoordinatorTests (19 passed, 1.0s)
    - Unsatisfiable-condition timeout proof (failed as expected after 30.565s; source restored)
    - swift build (exit 0, no diagnostics)
    - scripts/ci-tests.sh fast (exit 0; 1,796 required tests)
    - rg -n 'while .*Task\.yield' Tests/ (remaining matches tracked in KRMA-967)
    - rg -n 'while .*Task\.yield' Tests/KromoraKitTests/RetouchWorkflowCoordinatorTests.swift (no matches)
  findings: []
  fixes: []
  verification_commits: []
  actor: codex
  resolved_model: gpt-6-luna
  completed_at: 2026-10-13T16:55:44.626Z
  session: 01MV6X4K6Q0RU8U1OR
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - release-readiness
  - must-fix
  - tests
created: 2026-10-13T14:47:39.002Z
updated: 2026-10-13T16:55:44.630Z
parent: KRMA-922
blockers: []
order: n
board: product
footprint:
  source: observed
  paths: []
  observed:
    paths: []
    captured_at: 2026-10-13T16:43:37.796Z
    unavailable_reason: "missing_commits: no implementation commits are recorded"
---

## Objective

A regression in the retouch coordinator must make its tests FAIL, not spin a CPU forever.

## Context

Review `.context/2026-10-13-release-readiness-review.md` finding M4 (second bullet). Three orphaned `xctest` processes running
`RetouchWorkflowCoordinatorTests` were found spinning at ~170% CPU for 16+ hours.

`Tests/KromoraKitTests/RetouchWorkflowCoordinatorTests.swift` has unbounded loops of the form
`while <condition> { await Task.yield() }` at (approximately) lines 235, 277, 305, 347, 354, 370,
384, 387, 395 (e.g. in `testThresholdBurstCoalescesAndFinalThresholdWins`). If the condition never
becomes true the test never ends. KRMA-561 ("Bound asynchronous import waits in KeyMonitorTests") did
the same job for another file; copy its approach and helper shape (read it and its commit first).

## Acceptance criteria

- [ ] Every `while ... { await Task.yield() }` wait in this file is replaced by ONE shared helper,
      e.g. `waitUntil(_ description: String, timeout: Duration = .seconds(30), _ condition: () -> Bool)
      async throws`, that polls with a short `Task.sleep` (or yields) and throws
      `XCTFail`-style / `TestSynchronizationError.timedOut(description, ...)` at the deadline (reuse
      the error type already used in `StoredEditAdoptionTests.swift` if it is shared; otherwise reuse
      whatever KRMA-561 introduced).
- [ ] After the change `grep -n "while .*Task.yield" Tests/KromoraKitTests/RetouchWorkflowCoordinatorTests.swift`
      returns nothing.
- [ ] Prove a timeout fails instead of hanging: locally make one condition unsatisfiable, run that
      test, show it fails in about the helper timeout; revert. Put the evidence in the review comment.
- [ ] `swift test --filter RetouchWorkflowCoordinatorTests` passes and finishes in about the same time
      as before.
- [ ] A scan of the rest of `Tests/` for the same unbounded pattern (`grep -rn "while .*Task.yield"
      Tests/`) is recorded in the review comment; fix the ones in files you touch and file one
      follow-up ticket (label `tests`) listing the remaining files rather than expanding this one.
- [ ] `swift build` is warning-free and Swift 6 mode stays clean (no `@unchecked Sendable`, `nonisolated(unsafe)`, `@preconcurrency`, no `#available` branches).
- [ ] `scripts/ci-tests.sh fast` exits 0 (if only `StoredEditAdoptionTests.testSlowMaterializationCannotReopenSupersededPhoto` fails, re-run it alone with `swift test --filter`, note it in the review comment, and do not change it here; it is tracked separately).


### Comment — claude @ 2026-10-13T16:43:35.851Z

Replaced all 9 'while ... Task.yield()' waits in RetouchWorkflowCoordinatorTests with one private waitUntil(description, timeout 30s) polling with 5ms sleep, throwing TestSynchronizationError.timedOut. grep for 'while .*Task.yield' in that file: empty. Timeout proof: made the dust-suggestions condition unsatisfiable; test failed with 'timed out waiting for dust suggestions to appear; condition did not settle' after 30.6s; reverted. swift test --filter RetouchWorkflowCoordinatorTests: 19 tests pass in ~1s. Build warning-free; scripts/ci-tests.sh fast exit 0. Repo-wide scan of remaining files filed as KRMA-967: DeriveCoordinatorTests, OpenImageDialogTests, AnalysisDebugPanelTests, PortableLibrarySessionTests (x4), PhotosImportBatchCoordinatorTests, EditPersistenceIntegrationTests, MaskingPanelTests (x3), AutoEnhancementCoordinatorTests.


### Comment — codex @ 2026-10-13T16:55:36.744Z

Independent verification passed. `swift test --filter RetouchWorkflowCoordinatorTests`: 19 tests passed in 1.0s. Timeout proof: temporarily made the dust-suggestions condition unsatisfiable; the focused test failed with `timed out waiting for dust suggestions to appear` in 30.565s; restored the source. `swift build`: passed with no diagnostics. `scripts/ci-tests.sh fast`: exit 0, all 1,796 required fast tests ran. `rg -n "while .*Task\\.yield" Tests/`: remaining matches are DeriveCoordinatorTests:335, OpenImageDialogTests:125, AnalysisDebugPanelTests:83, PortableLibrarySessionTests:351/849/932/984, PhotosImportBatchCoordinatorTests:148, EditPersistenceIntegrationTests:409, MaskingPanelTests:66/98/125, AutoEnhancementCoordinatorTests:527. Recorded in follow-up KRMA-967, now a child labeled tests and verification. No local verification fixes or commits.

## Agent log

- 2026-10-13T16:55:44.626Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Every unbounded Task.yield() wait in RetouchWorkflowCoordinatorTests is replaced by a shared bounded helper that reports timeout. (pass) — All nine waits now use waitUntil with a 30 second ContinuousClock deadline, 5 ms sleep polling, and TestSynchronizationError.timedOut.
- [x] The target file contains no while ... Task.yield() polling pattern. (pass) — rg -n 'while .*Task\.yield' Tests/KromoraKitTests/RetouchWorkflowCoordinatorTests.swift returned no matches.
- [x] An unsatisfiable condition makes a test fail near the helper timeout, and the evidence is recorded. (pass) — Focused test failed with the timeout diagnostic after 30.565 seconds; source was restored. Evidence is in the issue comment.
- [x] swift test --filter RetouchWorkflowCoordinatorTests passes in about the same time. (pass) — 19 tests passed in 1.0 second.
- [x] A repo-wide remaining-pattern scan is recorded and remaining files are tracked in one tests follow-up. (pass) — The 13 remaining matches across 9 files are listed in KRMA-967, now a child labeled tests and verification.
- [x] swift build is warning-free and Swift 6 mode has no forbidden escape hatches or availability branches. (pass) — swift build completed without diagnostics. No implementation changes in this verification.
- [x] scripts/ci-tests.sh fast exits 0. (pass) — Exit 0; all 1,796 required fast tests ran.
Checks run:
- swift test --filter RetouchWorkflowCoordinatorTests (19 passed, 1.0s)
- Unsatisfiable-condition timeout proof (failed as expected after 30.565s; source restored)
- swift build (exit 0, no diagnostics)
- scripts/ci-tests.sh fast (exit 0; 1,796 required tests)
- rg -n 'while .*Task\.yield' Tests/ (remaining matches tracked in KRMA-967)
- rg -n 'while .*Task\.yield' Tests/KromoraKitTests/RetouchWorkflowCoordinatorTests.swift (no matches)
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: codex
Resolved model: gpt-6-luna
Pickup session: 01MV6X4K6Q0RU8U1OR
Summary: Independent verification passed; all criteria met. Remaining test polling loops tracked in KRMA-967.

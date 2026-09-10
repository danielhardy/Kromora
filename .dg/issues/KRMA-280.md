---
id: KRMA-280
title: Make AppViewModel tests hermetic and eliminate shared defaults/library state
type: task
status: done
priority: high
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Reusable test factory/fixture provides unique UserDefaults per test
      result: pass
    - criterion: Isolated managed-library URL under the test temp directory
      result: pass
    - criterion: WorkspaceNavigationTests and setSourceFolder/raw-AppViewModel callers migrated
      result: pass
    - criterion: Shared defaults preserved only for relaunch/persistence tests, scoped to one isolated suite
      result: pass
    - criterion: Navigation regression passes repeatedly, alone and in the full parallel suite
      result: pass
    - criterion: No test reads or deletes files from the real default Lumo library
      result: pass
  checks_run:
    - swift test --filter WorkspaceNavigationTests (3 consecutive runs, 0 failures)
    - swift test --parallel (957 tests, 0 failures, exit code 0)
    - "grep audit: no raw AppViewModel(...) construction remains outside Fixtures.makeAppViewModel"
    - "grep audit: setSourceFolder callers (ExportCutoverTests, ExportCoordinatorTests) confirmed to route through isolated per-test UserDefaults suites via ImageCollection defaults injection"
    - confirmed AppViewModel/ImageCollection/LUTLibrary all take injected UserDefaults; production default (UserDefaults.standard / ImageCollection.defaultLibraryFolderURL) preserved for non-test callers
  findings:
    - "minor/maintainability (fixed in commit 69223ee): TempDirectoryTestCase setUp/tearDown still reset UserDefaults.standard for the comparisonMode key, left over from before this migration; unreachable now that every AppViewModel test uses an isolated preferences suite. Removed the dead reset and the unused key constant; full parallel suite re-verified green after the change."
  fixes:
    - "Commit 69223ee: removed dead UserDefaults.standard comparisonModeKey reset (setUp/tearDown) and the now-unused comparisonModeKey constant from Tests/LumoKitTests/Fixtures.swift TempDirectoryTestCase."
  verification_commits:
    - 69223ee
    - 69223ee03cd835443c91c4dc9a2ee35ab51e6412
  actor: claude
  resolved_model: unknown
  completed_at: 2026-09-08T18:23:11.936Z
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - test-reliability
created: 2026-09-08T14:41:24.913Z
updated: 2026-09-10T12:53:53.065Z
order: a0
board: product
commits:
  - 69223ee03cd835443c91c4dc9a2ee35ab51e6412
  - 69223ee
---

## Objective\n\nMake AppViewModel-based tests independent of persisted user defaults, the real Application Support library, and other tests running in parallel.\n\n## Context\n\nAppViewModel defaults to UserDefaults.standard and ImageCollection.defaultLibraryFolderURL. Its initializer restores a persisted source-folder bookmark or managed library before tests run. Tests such as ExportCutoverTests and ExportCoordinatorTests call setSourceFolder, which writes imageSourceFolderBookmark into shared defaults. TempDirectoryTestCase removes the temporary folder but leaves the bookmark, allowing a later WorkspaceNavigationTests instance to start in .grid instead of the expected .edit.\n\nThe failure is covered by NavigationStateTests.swift:166-172 and the restore path in AppViewModel.swift:835-849. The fixture setup and cleanup are in Fixtures.swift:355-389.\n\n## Acceptance criteria\n\n- Add a reusable test factory or fixture helper that provides unique UserDefaults for each test or test scenario.\n- Provide an isolated managed-library URL under the test temporary directory.\n- Migrate WorkspaceNavigationTests and tests that call setSourceFolder or construct AppViewModel without injected preferences/library paths.\n- Preserve shared defaults only in tests explicitly verifying persistence across a relaunch, and scope those tests to one isolated suite.\n- The navigation regression passes repeatedly both alone and in the full parallel suite.\n- No test reads or deletes files from the real default Lumo library.\n\n## Verification\n\nRun the focused navigation tests repeatedly, then the full swift test --parallel suite. Confirm that the failure does not reappear when tests are reordered or run concurrently.\n


### Comment — codex @ 2026-09-08T18:15:01.091Z

Implemented in commit 9e2cfbc. Added the TempDirectoryTestCase AppViewModel fixture with unique UserDefaults, in-memory edit stores, isolated managed-library and Look-folder URLs; migrated AppViewModel/LUTLibrary test construction; preserved explicit isolated defaults for relaunch tests; removed teardown access to the real default library. Verification: focused WorkspaceNavigationTests passed 3 consecutive runs; full swift test --parallel completed 957 tests with 0 failures.

## Agent log

- 2026-09-08T18:22:48.981Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] x (pass)
Checks run:
- None
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MTSZPAB9HL7JPYQ3

- 2026-09-08T18:23:11.937Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Reusable test factory/fixture provides unique UserDefaults per test (pass)
- [x] Isolated managed-library URL under the test temp directory (pass)
- [x] WorkspaceNavigationTests and setSourceFolder/raw-AppViewModel callers migrated (pass)
- [x] Shared defaults preserved only for relaunch/persistence tests, scoped to one isolated suite (pass)
- [x] Navigation regression passes repeatedly, alone and in the full parallel suite (pass)
- [x] No test reads or deletes files from the real default Lumo library (pass)
Checks run:
- swift test --filter WorkspaceNavigationTests (3 consecutive runs, 0 failures)
- swift test --parallel (957 tests, 0 failures, exit code 0)
- grep audit: no raw AppViewModel(...) construction remains outside Fixtures.makeAppViewModel
- grep audit: setSourceFolder callers (ExportCutoverTests, ExportCoordinatorTests) confirmed to route through isolated per-test UserDefaults suites via ImageCollection defaults injection
- confirmed AppViewModel/ImageCollection/LUTLibrary all take injected UserDefaults; production default (UserDefaults.standard / ImageCollection.defaultLibraryFolderURL) preserved for non-test callers
Findings:
- minor/maintainability (fixed in commit 69223ee): TempDirectoryTestCase setUp/tearDown still reset UserDefaults.standard for the comparisonMode key, left over from before this migration; unreachable now that every AppViewModel test uses an isolated preferences suite. Removed the dead reset and the unused key constant; full parallel suite re-verified green after the change.
Fixes:
- Commit 69223ee: removed dead UserDefaults.standard comparisonModeKey reset (setUp/tearDown) and the now-unused comparisonModeKey constant from Tests/LumoKitTests/Fixtures.swift TempDirectoryTestCase.
Verification commits:
- 69223ee
- 69223ee03cd835443c91c4dc9a2ee35ab51e6412
Actor: claude
Resolved model: unknown
Summary: Verified: AppViewModel tests are hermetic. All AppViewModel construction in tests now flows through makeAppViewModel/makeTestUserDefaults (unique UserDefaults suite + temp-dir-scoped managed library/Look folder per test); setSourceFolder callers (ExportCutoverTests, ExportCoordinatorTests) write into isolated preferences, not shared defaults; relaunch/persistence tests deliberately reuse one isolated suite across two AppViewModel instances; teardown no longer touches the real default library. Ran focused WorkspaceNavigationTests (3x) and full swift test --parallel (957 tests, 0 failures). Applied one localized fix: removed dead UserDefaults.standard comparisonModeKey reset in TempDirectoryTestCase (now unreachable since every test uses an isolated preferences suite).

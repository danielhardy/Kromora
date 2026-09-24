---
id: KRMA-558
title: Do not report a zero-item folder import as successful when the library is unavailable
type: bug
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: With no open package, choosing a folder does not show a complete, 0 imported, 0 failed status
      result: pass
      notes: openSourceFolder now returns nil and calls reportPortableLibraryUnavailable() instead of building a zero-item ImportOutcomeSummary; verified in testOpeningSourceFolderWithoutLibraryReportsUnavailableErrorWithoutImportSummary for both an empty and a populated folder.
    - criterion: The user sees a clear library-unavailable error with the reason and a next step; the chosen folder is not scanned or written into another store
      result: pass
      notes: reportPortableLibraryUnavailable() surfaces portableLibraryOpenError plus a relaunch instruction via presentError before any folder enumeration; the guard runs before supportedImageURLs(in:) is called, and the fixture image file is confirmed to still exist untouched after the call.
    - criterion: Import actions consistently report or prevent unavailable-session attempts across folder, Photos, drag/drop, and removable media
      result: pass
      notes: openImageDialog, importFromPhotos, importPhotosPickerSelection, openRemovableMedia, importFromRemovableMedia, importSelectedRemovableMedia, handleRemovableMediaImportRequest, chooseSourceFolder, and handleDrop all gate on portableLibrary != nil and call reportPortableLibraryUnavailable(); ContentView disables the corresponding File-menu controls via canImportIntoPortableLibrary. Minor gap noted below (non-blocking).
    - criterion: Tests cover openSourceFolder with portableLibrary == nil, including an empty folder and a non-empty folder, and verify no misleading success summary appears
      result: pass
      notes: testOpeningSourceFolderWithoutLibraryReportsUnavailableErrorWithoutImportSummary and testImportEntryPointsAreGatedWhenLibraryFailedToOpen cover this; both pass.
    - criterion: Normal import summaries and partial-failure counts remain unchanged
      result: pass
      notes: Unaffected code paths (successful/partial-failure ImportOutcomeSummary construction) were not touched by the diff; full AppViewModelTests and ImportOutcomeSummary-adjacent suites pass, and scripts/ci-tests.sh fast (1179 tests) passes.
  checks_run:
    - swift build (clean, no warnings)
    - swift test --filter 'AppViewModelTests|ImportOutcomeSummaryTests|MediaVolumeTests' (36+ tests, 0 failures)
    - scripts/ci-tests.sh fast (1179 tests, exit code 0)
  findings:
    - "Low: AppViewModel.handleDroppedURL(_:) is an ungated single-URL entry point that bypasses the new portableLibrary guard, but has no production caller (ImageDropDelegate only calls the gated handleDrop(_:) with ImageDrop.Payload); exercised only by FileIntegrationBoundaryTests against a valid library. Not a live regression; no child ticket filed given minimal impact. Optional: remove the unused method or route it through handleDrop."
    - "Low: MenuCommands.swift keyboard-shortcut menu items (Import from Photos/Removable Media, Open Image, Open Source Folder) are not visually disabled via canImportIntoPortableLibrary the way ContentView File menu is, though the underlying AppViewModel calls still correctly gate and report the error. Optional follow-up: add .disabled(!viewModel.canImportIntoPortableLibrary) to MenuCommands.swift for UI consistency."
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-23T16:31:19.595Z
  session: 01MUEBHOM31SZQ8O2J
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - import
  - library
  - ux
created: 2026-09-23T15:19:28.772Z
updated: 2026-09-23T16:31:19.598Z
order: zv
board: product
---

## Objective

Make folder-import attempts fail clearly when Kromora has no open portable library, instead of presenting an empty import as a completed operation with zero failures.

## User report

After the library-open error, the user dismissed the alert and tried to import a folder. The UI reported “0 imported.” The exact full status text was not captured.

## Code evidence

- When package/session startup fails, `AppViewModel` keeps `portableLibrary == nil`, stores `portableLibraryOpenError`, and presents the open error. Import controls remain available.
- `openSourceFolder(url:)` checks `portableLibrary` before enumerating the chosen folder. On failure it calls `ImportOutcomeSummary.failure(total: 0, reason: ...)`.
- For `total == 0`, `ImportOutcomeSummary.failure` records `failed == 0`; `status(prefix:)` calls any non-cancelled summary “complete” and prints zero counts. The result can therefore read like an empty successful import even though the operation was rejected because no library is open.
- File-open paths handle unavailable packages separately; keep behavior consistent across folder, Photos, and removable-media entry points.

## Scope

- Represent a package-unavailable operation as an error state, not a completed zero-item import summary.
- Disable or gate import controls when the library failed to open, or retain them only if they lead to a clear repair/retry action.
- Preserve actionable context from `portableLibraryOpenError`, including the lock/contention reason.
- Audit folder, Photos, drag/drop, and removable-media imports for the same no-session path without changing successful import counts.

## Acceptance criteria

- [ ] With no open package, choosing a folder does not show a “complete, 0 imported, 0 failed” status.
- [ ] The user sees a clear library-unavailable error with the reason and a next step; the chosen folder is not scanned or written into another store.
- [ ] Import actions consistently report or prevent unavailable-session attempts across folder, Photos, drag/drop, and removable media.
- [ ] Tests cover `openSourceFolder` with `portableLibrary == nil`, including an empty folder and a non-empty folder, and verify no misleading success summary appears.
- [ ] Normal import summaries and partial-failure counts remain unchanged.

## Likely files and checks

`AppViewModel.swift` (`openSourceFolder`, import entry points and `portableLibraryOpenError`), `ImportOutcomeSummary.swift`, import-related view controls, and `AppViewModelTests.swift` / `ImportOutcomeSummaryTests.swift`. Run focused unavailable-package and import-outcome tests, then the documented fast lane.

## Related issues

KRMA-556 handles stale local writer leases; KRMA-557 handles startup responsiveness. This ticket is limited to user feedback when a package session is unavailable. KRMA-555 concerns import-summary timing while a photo is loading, which is a separate presentation path.


### Comment — codex @ 2026-09-23T16:28:22.061Z

Folder imports now stop before scanning when the portable library is unavailable and show the package error with a relaunch recovery step. Photos, file, drag/drop, and removable-media entry points are gated consistently; normal import summaries are unchanged. Added coverage for empty and populated folders and unavailable entry points. Verification: focused AppViewModel and removable-media tests passed; scripts/ci-tests.sh fast passed. Commit: 1c8d1cb.

## Agent log

- 2026-09-23T16:31:19.595Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] With no open package, choosing a folder does not show a complete, 0 imported, 0 failed status (pass) — openSourceFolder now returns nil and calls reportPortableLibraryUnavailable() instead of building a zero-item ImportOutcomeSummary; verified in testOpeningSourceFolderWithoutLibraryReportsUnavailableErrorWithoutImportSummary for both an empty and a populated folder.
- [x] The user sees a clear library-unavailable error with the reason and a next step; the chosen folder is not scanned or written into another store (pass) — reportPortableLibraryUnavailable() surfaces portableLibraryOpenError plus a relaunch instruction via presentError before any folder enumeration; the guard runs before supportedImageURLs(in:) is called, and the fixture image file is confirmed to still exist untouched after the call.
- [x] Import actions consistently report or prevent unavailable-session attempts across folder, Photos, drag/drop, and removable media (pass) — openImageDialog, importFromPhotos, importPhotosPickerSelection, openRemovableMedia, importFromRemovableMedia, importSelectedRemovableMedia, handleRemovableMediaImportRequest, chooseSourceFolder, and handleDrop all gate on portableLibrary != nil and call reportPortableLibraryUnavailable(); ContentView disables the corresponding File-menu controls via canImportIntoPortableLibrary. Minor gap noted below (non-blocking).
- [x] Tests cover openSourceFolder with portableLibrary == nil, including an empty folder and a non-empty folder, and verify no misleading success summary appears (pass) — testOpeningSourceFolderWithoutLibraryReportsUnavailableErrorWithoutImportSummary and testImportEntryPointsAreGatedWhenLibraryFailedToOpen cover this; both pass.
- [x] Normal import summaries and partial-failure counts remain unchanged (pass) — Unaffected code paths (successful/partial-failure ImportOutcomeSummary construction) were not touched by the diff; full AppViewModelTests and ImportOutcomeSummary-adjacent suites pass, and scripts/ci-tests.sh fast (1179 tests) passes.
Checks run:
- swift build (clean, no warnings)
- swift test --filter 'AppViewModelTests|ImportOutcomeSummaryTests|MediaVolumeTests' (36+ tests, 0 failures)
- scripts/ci-tests.sh fast (1179 tests, exit code 0)
Findings:
- Low: AppViewModel.handleDroppedURL(_:) is an ungated single-URL entry point that bypasses the new portableLibrary guard, but has no production caller (ImageDropDelegate only calls the gated handleDrop(_:) with ImageDrop.Payload); exercised only by FileIntegrationBoundaryTests against a valid library. Not a live regression; no child ticket filed given minimal impact. Optional: remove the unused method or route it through handleDrop.
- Low: MenuCommands.swift keyboard-shortcut menu items (Import from Photos/Removable Media, Open Image, Open Source Folder) are not visually disabled via canImportIntoPortableLibrary the way ContentView File menu is, though the underlying AppViewModel calls still correctly gate and report the error. Optional follow-up: add .disabled(!viewModel.canImportIntoPortableLibrary) to MenuCommands.swift for UI consistency.
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MUEBHOM31SZQ8O2J
Summary: Verified: folder/Photos/drag-drop/removable-media imports now report library-unavailable as an error state instead of a misleading zero-item success summary. Build clean, focused tests and full fast CI lane (1179 tests) pass.

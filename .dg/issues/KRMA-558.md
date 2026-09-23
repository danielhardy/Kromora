---
id: KRMA-558
title: Do not report a zero-item folder import as successful when the library is unavailable
type: bug
status: ready
priority: medium
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - import
  - library
  - ux
created: 2026-09-23T15:19:28.772Z
updated: 2026-09-23T15:19:29.252Z
order: t
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

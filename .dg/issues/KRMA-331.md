---
id: KRMA-331
title: saveBookmark persist failure re-opens silent restoreLibrary fallback on next launch
type: task
status: done
priority: low
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: setSourceFolder surfaces a user-visible message when saveBookmark fails to persist, instead of silently discarding the failure
      result: pass
    - criterion: Add a regression covering setSourceFolder when bookmark creation/validation fails
      result: pass
  checks_run:
    - swift test --filter AppViewModelTests (28 tests, 0 failures)
    - scripts/ci-tests.sh fast (679 tests, 0 failures)
    - git diff --check (clean)
    - manual read-through of ImageCollection.saveBookmark/setSourceFolder and AppViewModel.openSourceFolder/presentError
  findings: []
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-09T23:38:02.626Z
  session: 01MTUQM2A8DYCQM0WM
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - verification
  - library
created: 2026-09-09T22:33:09.304Z
updated: 2026-09-10T12:53:57.482Z
parent: KRMA-329
order: a0
board: product
---

## Objective

saveBookmark persist failure re-opens silent restoreLibrary fallback on next launch

## Context

Found during verification of KRMA-329 (commit 049c2d5). That fix validates a *stored* bookmark
on restore and surfaces an alert instead of silently falling through to `restoreLibrary()`. It
does not close a narrower, related gap: `ImageCollection.saveBookmark(for:)` now returns `Bool`
on persist failure (create/resolve/access all fail), but its only caller, `setSourceFolder`,
discards that return value. If persisting fails, no bookmark is ever written to `defaults`, so on
the next launch `hasPersistedSourceFolderBookmark` is `false` and the app falls through to
`restoreLibrary()` exactly as it did before KRMA-329 — silently showing the managed-library grid
instead of the folder the user picked, with no alert. This is a narrower trigger (failed initial
save, not failed later resolve) and wasn't covered by KRMA-329's acceptance criteria or its
regression test, and all fast-lane tests pass unaffected by it.

**Why:** KRMA-329 exists specifically to stop `restoreLibrary()` from silently masking a broken
source-folder bookmark. This is the same masking behavior reached through the save path instead
of the restore path.

## Acceptance criteria

- [ ] `setSourceFolder` surfaces a user-visible message when `saveBookmark` fails to persist,
      instead of silently discarding the failure.
- [ ] Add a regression covering `setSourceFolder` when bookmark creation/validation fails.

## Implementation notes

See `Sources/LumoKit/Models/ImageCollection.swift` (`setSourceFolder`, `saveBookmark`) and
`Sources/LumoKit/ViewModels/AppViewModel.swift` (`presentError`). Related: KRMA-329.

### Comment — codex @ 2026-09-09T23:36:14.587Z

Implemented and committed as 3e35a8e. ImageCollection.setSourceFolder now returns bookmark persistence success, AppViewModel.openSourceFolder surfaces save failures through the existing alert/status path, and AppViewModelTests covers scoped bookmark creation failure. Verification: swift test passed (1,050 tests, 47 expected skips, 0 failures); git diff --check passed.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-09T23:38:02.626Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] setSourceFolder surfaces a user-visible message when saveBookmark fails to persist, instead of silently discarding the failure (pass)
- [x] Add a regression covering setSourceFolder when bookmark creation/validation fails (pass)
Checks run:
- swift test --filter AppViewModelTests (28 tests, 0 failures)
- scripts/ci-tests.sh fast (679 tests, 0 failures)
- git diff --check (clean)
- manual read-through of ImageCollection.saveBookmark/setSourceFolder and AppViewModel.openSourceFolder/presentError
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MTUQM2A8DYCQM0WM
Summary: Verified: setSourceFolder now returns bookmark persistence result, openSourceFolder surfaces failures via presentError (status + error), and testOpeningSourceFolderSurfacesBookmarkPersistenceFailure exercises the failure path deterministically via a non-file URL. AppViewModelTests (28) and full fast lane (679) pass; no new findings.

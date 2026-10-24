---
id: KRMA-889
title: Bound temporary share export lifecycle
type: task
status: done
priority: low
human_review_required: false
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Keep shared export files available while the sharing service needs them, then remove them after completion or cancellation.
      result: pass
      notes: Each picker/service session retains its own directory until dismissal or service completion/failure.
    - criterion: Clean up failed or abandoned share preparations, including the no-key-window path, without deleting user-selected export destinations.
      result: pass
      notes: Failed preparations and missing-window completion remove only their share directory; the next share sweeps abandoned directories while preserving active sessions.
    - criterion: Add focused tests for completion, cancellation/failure, and cleanup behavior.
      result: pass
      notes: Tests cover picker dismissal, service success/failure callbacks, export failure, no-window cleanup, stale cleanup, overlapping preparations, and user destination preservation.
  checks_run:
    - swift test --filter ExportWorkflowCoordinatorTests — 9 tests, 0 failures
    - git diff --check — passed
  findings:
    - Found that starting a second share deleted the shared temporary root and released the earlier picker delegate while its service could still need the files. Fixed by retaining picker sessions and cleaning their directories independently.
    - The test build reported an unrelated existing unused-value warning in Tests/KromoraKitTests/ColorMixerTests.swift:193 during the first build; the final incremental run emitted no diagnostics.
  fixes:
    - Track pending share URLs and active share directories independently; sweep only abandoned directories and release each live picker session on its terminal callback.
    - Add focused regression tests for overlapping shares, picker dismissal and service terminal callbacks, stale/no-window/failure cleanup, and user export preservation.
  verification_commits:
    - 8e334e24
  actor: codex
  resolved_model: gpt-6-luna
  completed_at: 2026-10-11T21:04:04.414Z
  session: 01MV4AZL7LA1SF8ZPQ
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - verification
  - export
  - maintainability
created: 2026-10-11T17:11:15.237Z
updated: 2026-10-11T21:04:04.417Z
blockers: []
order: n
board: product
footprint:
  source: observed
  paths: []
  observed:
    paths: []
    captured_at: 2026-10-11T20:56:17.320Z
    unavailable_reason: "missing_commits: no implementation commits are recorded"
commits:
  - 8e334e24
---

## Objective

Bound the temporary-file lifecycle for Share exports.

## Context

Child of KRMA-460, from counterpoint verification of KRMA-877.

`ExportWorkflowCoordinator` creates a unique directory beneath `Kromora Share Exports` for each
Share action. Neither the single-photo nor selected-photos path removes completed exports or
abandoned directories, including when no key window is available for the picker. Repeated shares can
therefore accumulate full-resolution TIFFs in temporary storage.

## Acceptance criteria

- [ ] Keep shared export files available while the sharing service needs them, then remove them
      after completion or cancellation.
- [ ] Clean up failed or abandoned share preparations, including the no-key-window path, without
      deleting user-selected export destinations.
- [ ] Add focused tests for completion, cancellation/failure, and cleanup behavior.

## Implementation notes

Preserve the single-photo and selected-photos Share flows. Give temporary artifacts a bounded
lifecycle; never clean up the original, external-editor, or user-selected export destinations.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-10-11T21:04:04.414Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Keep shared export files available while the sharing service needs them, then remove them after completion or cancellation. (pass) — Each picker/service session retains its own directory until dismissal or service completion/failure.
- [x] Clean up failed or abandoned share preparations, including the no-key-window path, without deleting user-selected export destinations. (pass) — Failed preparations and missing-window completion remove only their share directory; the next share sweeps abandoned directories while preserving active sessions.
- [x] Add focused tests for completion, cancellation/failure, and cleanup behavior. (pass) — Tests cover picker dismissal, service success/failure callbacks, export failure, no-window cleanup, stale cleanup, overlapping preparations, and user destination preservation.
Checks run:
- swift test --filter ExportWorkflowCoordinatorTests — 9 tests, 0 failures
- git diff --check — passed
Findings:
- Found that starting a second share deleted the shared temporary root and released the earlier picker delegate while its service could still need the files. Fixed by retaining picker sessions and cleaning their directories independently.
- The test build reported an unrelated existing unused-value warning in Tests/KromoraKitTests/ColorMixerTests.swift:193 during the first build; the final incremental run emitted no diagnostics.
Fixes:
- Track pending share URLs and active share directories independently; sweep only abandoned directories and release each live picker session on its terminal callback.
- Add focused regression tests for overlapping shares, picker dismissal and service terminal callbacks, stale/no-window/failure cleanup, and user export preservation.
Verification commits:
- 8e334e24
Actor: codex
Resolved model: gpt-6-luna
Pickup session: 01MV4AZL7LA1SF8ZPQ
Summary: Counterpoint verification passed after isolating live share sessions and adding lifecycle regression coverage.

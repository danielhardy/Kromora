---
id: KRMA-998
title: Report directory durability failures from fullSyncDirectory
type: bug
status: done
priority: high
human_review_required: false
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: open failure throws; directory sync failure throws; the helper signature matches that behavior
      result: pass
      notes: Missing-path and injected-sync-failure tests both observe thrown errors.
    - criterion: Directory durability uses the same primitive as fullSync when valid, and does not ignore a directory sync error
      result: pass
      notes: fullSyncDirectory delegates to fullSync; an actual directory sync succeeded in this environment. No power-loss test was run.
    - criterion: Tests cover an open failure and a sync failure through a documented seam
      result: pass
      notes: FullSyncDirectoryTests covers a missing path and injected failure; its comment documents the seam because APFS does not fail on demand.
    - criterion: Transaction commit and rollback tests pass, with no silent try? added around directory sync call sites
      result: pass
      notes: PortablePackageTransactionTests passed. Reviewed all fullSyncDirectory call sites; each uses try.
    - criterion: swift build is warning-free and scripts/ci-tests.sh fast exits 0
      result: pass
      notes: Both commands exited 0; the fast lane ran 1,924 required tests.
  checks_run:
    - swift test --filter PortablePackageTransactionTests — exit 0; 11 tests passed
    - swift test --filter FullSyncDirectoryTests — exit 0; 3 tests passed
    - swift build — exit 0; no warnings
    - scripts/ci-tests.sh fast — exit 0; 1,924 required tests passed
    - Reviewed fullSyncDirectory call sites for propagated errors
  findings: []
  fixes: []
  verification_commits:
    - c03d2242
  actor: codex
  resolved_model: gpt-6-luna
  completed_at: 2026-10-14T17:33:56.387Z
  session: 01MV8DX181NM35PHXD
creation_provenance:
  runner: cursor
  model: unknown
  actor: cursor
labels:
  - release-readiness
  - readiness-2026-10-14
  - must-fix
  - storage
created: 2026-10-14T16:08:54.430Z
updated: 2026-10-14T17:33:56.391Z
parent: KRMA-994
blockers: []
order: a0
board: product
context:
  files:
    - Sources/KromoraKit/Models/PortablePackageTransaction.swift
    - Tests/KromoraKitTests/PortablePackageTransactionTests.swift
  docs:
    - CLAUDE.md
    - docs/STORAGE_POLICY.md
    - .context/2026-10-14-release-readiness-review.md
  issues:
    - KRMA-994
    - KRMA-997
  commands:
    - swift test --filter PortablePackageTransactionTests
    - scripts/ci-tests.sh fast
footprint:
  source: observed
  paths: []
  observed:
    paths: []
    captured_at: 2026-10-14T17:29:21.880Z
    unavailable_reason: "missing_commits: no implementation commits are recorded"
commits:
  - c03d2242
---

## Objective

A package transaction must fail when the directory durability sync fails. `fullSyncDirectory` currently reports success when it did not sync.

## Context

Code evidence from the 2026-10-14 review, not an observed power-loss corruption. `fullSyncDirectory` in `Sources/KromoraKit/Models/PortablePackageTransaction.swift` (around line 1232) returns without throwing when `open` fails, and it ignores the `fsync` result. `fullSync` above it throws on `F_FULLFSYNC` failure. Call sites already use `try`.

Sibling KRMA-997 also edits this file. If that work has landed, keep its ownership checks. Do not claim a power-loss test you did not run. Parent epic: KRMA-994. Review finding 3, durability paragraph.

## Acceptance criteria

- [ ] `open` failure throws. `fsync` / `F_FULLFSYNC` failure throws. The function's `throws` signature matches its behavior.
- [ ] Use the same durability primitive as `fullSync` when the platform call is valid for a directory; otherwise throw on the directory `fsync` failure. Do not add an `#available` branch or a non-Apple-Silicon path.
- [ ] A test points the helper at a missing path, or another open failure you can produce without root, and expects a thrown error. A second test, or a fault seam if you cannot force `fsync` to fail on APFS, proves a sync failure is not ignored. Document the seam in the test comment.
- [ ] Existing transaction commit/rollback tests still pass. No silent `try?` is added at the call sites to hide the new error.
- [ ] `swift build` is warning-free. `scripts/ci-tests.sh fast` exits 0.

## Constraints

- Re-read the cited lines before editing. Line numbers drift.
- Swift 6 language mode stays on. No `@unchecked Sendable`, `nonisolated(unsafe)`, `@preconcurrency`, or `#available` branches. No new dependencies.
- Do not run `scripts/run-kromora-capture.sh`. Display-bound numbers already live in `docs/TESTING.md`.
- Preserve unrelated working-tree changes. Do not revert other tickets' edits.
- One issue at a time. Commit subject starts with this issue id. Hand off at `review`; do not mark `done`.


### Comment — claude @ 2026-10-14T17:29:21.357Z

fullSyncDirectory now throws on open failure and uses fullSync (F_FULLFSYNC) on the directory; seam param 'sync' lets tests inject failure. Added FullSyncDirectoryTests (missing path, success, injected sync failure). swift build clean; PortablePackageTransactionTests pass; ci-tests.sh fast exit 0 on rerun (one earlier run had 1 unidentified failing test, did not reproduce). No power-loss test run.

## Agent log

- 2026-10-14T17:33:56.388Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] open failure throws; directory sync failure throws; the helper signature matches that behavior (pass) — Missing-path and injected-sync-failure tests both observe thrown errors.
- [x] Directory durability uses the same primitive as fullSync when valid, and does not ignore a directory sync error (pass) — fullSyncDirectory delegates to fullSync; an actual directory sync succeeded in this environment. No power-loss test was run.
- [x] Tests cover an open failure and a sync failure through a documented seam (pass) — FullSyncDirectoryTests covers a missing path and injected failure; its comment documents the seam because APFS does not fail on demand.
- [x] Transaction commit and rollback tests pass, with no silent try? added around directory sync call sites (pass) — PortablePackageTransactionTests passed. Reviewed all fullSyncDirectory call sites; each uses try.
- [x] swift build is warning-free and scripts/ci-tests.sh fast exits 0 (pass) — Both commands exited 0; the fast lane ran 1,924 required tests.
Checks run:
- swift test --filter PortablePackageTransactionTests — exit 0; 11 tests passed
- swift test --filter FullSyncDirectoryTests — exit 0; 3 tests passed
- swift build — exit 0; no warnings
- scripts/ci-tests.sh fast — exit 0; 1,924 required tests passed
- Reviewed fullSyncDirectory call sites for propagated errors
Findings:
- None
Fixes:
- None
Verification commits:
- c03d2242
Actor: codex
Resolved model: gpt-6-luna
Pickup session: 01MV8DX181NM35PHXD
Summary: Independent verification passed; all declared checks succeeded.

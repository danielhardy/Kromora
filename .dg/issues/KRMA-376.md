---
id: KRMA-376
title: Reconcile current uncommitted work into issue-sized commits
type: task
status: done
priority: urgent
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Inventory and attribute tracked and untracked work
      result: pass
      notes: Reviewed all tracked diffs, untracked source/tests/docs, DG records, and assets; mapped product work to KRMA-371 and records/assets to their issue wave.
    - criterion: Group coherent changes into focused issue-sized commits
      result: pass
      notes: f500869 is KRMA-371 product code/tests; aabd514 is DG records/assets; 479231b is the standalone package-plan document.
    - criterion: Preserve legitimate work and avoid destructive cleanup
      result: pass
      notes: No reset, checkout, clean, rebase, amend, or deletion shortcut was used; all discovered paths were retained or explicitly mapped.
    - criterion: Reconcile tracker records and commit references
      result: pass
      notes: KRMA-371 now references f500869; KRMA-384 tracks the future package plan; lifecycle events and issue records are committed.
    - criterion: Run appropriate verification and finish clean
      result: pass
      notes: Release build, 9 focused tests, dg validate, git diff --check, and local markdown-reference scan passed; no paths remain uncommitted.
  checks_run:
    - swift build -c release
    - swift test --filter LibraryDeletionTests|PhotoAnalysisCacheTests (9 passed)
    - dg validate
    - git diff --check
    - local markdown-reference scan for docs/LIBRARY_PACKAGE_PLAN.md
  findings: []
  fixes: []
  verification_commits:
    - f500869
    - aabd514
    - 479231b
  actor: codex
  resolved_model: gpt-5.6-luna
  completed_at: 2026-09-12T15:27:57.683Z
  session: 01MTYJC2HUXX0HS5MY
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - maintenance
  - git
  - hygiene
created: 2026-09-12T15:13:48.912Z
updated: 2026-09-12T15:27:57.685Z
order: w
board: product
commits:
  - aabd514
  - f500869
  - 479231b
---

## Objective

Safely evaluate the current uncommitted worktree and reconcile it into sensible, issue-sized commits with accurate descriptions and tracker bookkeeping.

## Context

A new wave of work is present in the shared checkout after KRMA-354 was completed. The tree mixes functional source changes, tests, starter Look assets, DG issue/event records, and planning documentation. This ticket is for attribution and cleanup of that later wave. It is not authorization to discard, reset, or blindly commit anything.

## Current baseline

- Branch: main
- HEAD at ticket creation: 815cda7
- 51 dirty paths reported by git
- Tracked changes include library/document persistence, image collection and deletion UI/commands, photo-analysis/cache/rendering code, keyboard shortcuts, and related tests.
- Untracked work includes LibraryDeletionTests.swift, 12 StarterLooks .cube assets, docs/LIBRARY_PACKAGE_PLAN.md, and DG issues/assets/events associated with the recent ticket wave.
- Existing related reconciliation ticket KRMA-354 is complete; do not reopen it unless the investigation proves that this tree is part of its original scope.

## Acceptance criteria

- Inventory every tracked modification and untracked path, including the DG records and assets.
- Inspect diffs, tests, recent history, and related ticket context to determine ownership, intent, and dependency relationships.
- Map each coherent change cluster to an existing issue where appropriate. Create follow-up tickets for work that is real but cannot be safely bundled or whose issue attribution is ambiguous.
- Group the reconciled work into focused commits with descriptive messages. Keep unrelated product code, tests, documentation, generated or tracker bookkeeping, and assets separate when their intent differs. Do not use a blanket commit.
- Preserve all legitimate user and agent work. Do not use git reset, checkout, clean, rebase, amend, or deletion as a cleanup shortcut.
- Reconcile DG issue status, event history, assets, and commit references so the tracker accurately reflects the resulting commits.
- Run appropriate verification for each cluster, including dg validate, git diff --check, relevant focused tests or builds, and any required reference checks.
- Finish with a clean tree for the reconciled scope, or explicitly document every intentionally deferred path and why it remains uncommitted.
- Add a completion comment listing the commit hashes, path groups, ticket mappings, verification commands/results, and any deferred work.

## Suggested investigation areas

- Separate the library deletion implementation and tests from persistence/cache/rendering changes if they represent different user-facing outcomes.
- Determine whether the StarterLooks assets and related DG records belong with the Looks ticket wave or need their own asset/bookkeeping commit.
- Verify whether the library package plan is documentation-only and whether any current source changes implement it.
- Treat existing issue files and event history as records to reconcile, not disposable noise.


### Comment — codex @ 2026-09-12T15:27:57.281Z

Completion reconciliation: f500869 (KRMA-371) contains the Library deletion implementation and tests across Sources/KromoraKit/Models, Sources/KromoraKit/ViewModels/AppViewModel.swift, Sources/KromoraKit/Views, and Tests/KromoraKitTests/{LibraryDeletionTests.swift,PhotoAnalysisCacheTests.swift}; aabd514 contains .dg/.project/events.jsonl, KRMA-356 through KRMA-384 issue records, and the four KRMA-356/359/360/362 assets; 479231b contains docs/LIBRARY_PACKAGE_PLAN.md. KRMA-384 now owns the future package implementation; no paths are deferred or left uncommitted. Verification: swift build -c release; swift test --filter LibraryDeletionTests|PhotoAnalysisCacheTests (9 passed); dg validate; git diff --check; local markdown-reference scan.

## Agent log

- 2026-09-12T15:27:57.684Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Inventory and attribute tracked and untracked work (pass) — Reviewed all tracked diffs, untracked source/tests/docs, DG records, and assets; mapped product work to KRMA-371 and records/assets to their issue wave.
- [x] Group coherent changes into focused issue-sized commits (pass) — f500869 is KRMA-371 product code/tests; aabd514 is DG records/assets; 479231b is the standalone package-plan document.
- [x] Preserve legitimate work and avoid destructive cleanup (pass) — No reset, checkout, clean, rebase, amend, or deletion shortcut was used; all discovered paths were retained or explicitly mapped.
- [x] Reconcile tracker records and commit references (pass) — KRMA-371 now references f500869; KRMA-384 tracks the future package plan; lifecycle events and issue records are committed.
- [x] Run appropriate verification and finish clean (pass) — Release build, 9 focused tests, dg validate, git diff --check, and local markdown-reference scan passed; no paths remain uncommitted.
Checks run:
- swift build -c release
- swift test --filter LibraryDeletionTests|PhotoAnalysisCacheTests (9 passed)
- dg validate
- git diff --check
- local markdown-reference scan for docs/LIBRARY_PACKAGE_PLAN.md
Findings:
- None
Fixes:
- None
Verification commits:
- f500869
- aabd514
- 479231b
Actor: codex
Resolved model: gpt-5.6-luna
Pickup session: 01MTYJC2HUXX0HS5MY
Summary: Reconciled the shared worktree into focused commits f500869, aabd514, and 479231b, with KRMA-384 tracking the standalone portable-library plan. No legitimate work was discarded and no paths remain uncommitted.

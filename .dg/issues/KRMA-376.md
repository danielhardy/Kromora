---
id: KRMA-376
title: Reconcile current uncommitted work into issue-sized commits
type: task
status: claimed
priority: urgent
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - maintenance
  - git
  - hygiene
created: 2026-09-12T15:13:48.912Z
updated: 2026-09-12T15:23:43.650Z
order: w
board: product
claim:
  actor: codex
  session: 01MTYJC2HUXX0HS5MY
  claimed_at: 2026-09-12T15:23:43.650Z
  expires_at: 2026-09-12T16:23:43.650Z
  model: gpt-5.6-luna
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

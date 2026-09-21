---
id: KRMA-295
title: Make adjacent-preview prefetch stored-edit aware
type: task
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Prefetch of an edited-but-never-opened neighbor renders its stored document or is skipped — never the identity document.
      result: pass
      notes: Cold neighbors are resolved via batched editStore.load(for:) before admission; EditDocumentLoadResult.isUsableForPrefetch excludes corrupt records (neutral fallback) and store-wide writeFailure/unknown states, only admitting ready/relinked/legit-content results. Covered by new testAdjacentPrefetchUsesStoredEditsForNeverOpenedNeighbor (FilmstripNavigationTests) and testCorrupt...isUsableForPrefetch assertion (EditDocumentStoreTests); both pass.
    - criterion: Stale prefetch still never reaches the engine after navigation (existing tests keep passing).
      result: pass
      notes: assetID/sourceRevision fences preserved at every await boundary (post-sleep, post-batch-load, pre-enqueue, per-request in the job loop); FilmstripNavigationTests and full fast lane pass unchanged.
  checks_run:
    - swift test --filter FilmstripNavigationTests (5 passed)
    - swift test --filter EditDocumentStoreTests (16 passed)
    - scripts/ci-tests.sh fast (652 passed, exit 0)
    - git status --porcelain (clean apart from pre-existing unrelated untracked benchmark file)
    - manual read of EditDocumentStore.load/relink/finishLoad status transitions against isUsableForPrefetch
  findings:
    - Plan's optional suggestion to suppress prefetch entirely while a LUMO-293 mask refinement is in flight was not implemented; plan explicitly marked it as 'consider', and scope was deliberately kept to prefetch-document correctness. Non-blocking, no ticket filed.
  fixes: []
  verification_commits:
    - cacded2
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-09T01:43:53.541Z
  session: 01MTTFL0UKKQNEIMHB
labels:
  - performance
  - preview
  - prefetch
created: 2026-09-08T23:48:30.817Z
updated: 2026-09-10T12:53:54.317Z
order: a0
board: product
commits:
  - cacded2
---

## Objective

Adjacent-preview prefetch stops rendering wrong (identity) documents for edited neighbors and stops spending actor time on work that is immediately discarded.

## Context

Parent: KRMA-289. scheduleAdjacentPreviewPrefetch (Sources/LumoKit/ViewModels/AppViewModel.swift) builds neighbor requests from in-memory sessions with an EditDocument() fallback, ignoring stored edits for never-opened photos. A prefetched edited neighbor renders the wrong document (then re-renders on open), and each prefetch is two full preview renders on the shared actor 350ms after every open.

## Plan

- Consult the edit store for neighbors without in-memory sessions before enqueueing (batched load, still cancellable on navigation); skip neighbors whose stored state is unknown rather than rendering a known-wrong document.
- Keep the existing guards (assetID/sourceRevision fence before the engine call, editor-lane background priority, 350ms delay); consider suppressing prefetch entirely while a mask refinement (KRMA-293) is in flight.
- Small, deliberate scope: correctness of what is prefetched first, admission tuning second.

## Acceptance

- Prefetch of an edited-but-never-opened neighbor renders its stored document or is skipped — never the identity document.
- Stale prefetch still never reaches the engine after navigation (existing tests keep passing).


### Comment — codex @ 2026-09-09T01:39:43.770Z

Implemented in cacded2. Adjacent preview prefetch now batches edit-store reads for cold neighbors before editor-lane admission, uses stored documents for never-opened edited photos, skips corrupt/unavailable state instead of guessing identity, and preserves the 350 ms delay plus asset/source-revision cancellation fences. Added regression coverage for stored-edit neighbor prefetch and corrupt-record admission. Verification: focused FilmstripNavigationTests/EditDocumentStoreTests passed; CI fast lane 652/652 passed; CI serial lane 290/290 passed; swift build -c release passed; git diff --check passed; dg validate passed with existing model/context warnings.

## Agent log

- 2026-09-09T01:43:53.542Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Prefetch of an edited-but-never-opened neighbor renders its stored document or is skipped — never the identity document. (pass) — Cold neighbors are resolved via batched editStore.load(for:) before admission; EditDocumentLoadResult.isUsableForPrefetch excludes corrupt records (neutral fallback) and store-wide writeFailure/unknown states, only admitting ready/relinked/legit-content results. Covered by new testAdjacentPrefetchUsesStoredEditsForNeverOpenedNeighbor (FilmstripNavigationTests) and testCorrupt...isUsableForPrefetch assertion (EditDocumentStoreTests); both pass.
- [x] Stale prefetch still never reaches the engine after navigation (existing tests keep passing). (pass) — assetID/sourceRevision fences preserved at every await boundary (post-sleep, post-batch-load, pre-enqueue, per-request in the job loop); FilmstripNavigationTests and full fast lane pass unchanged.
Checks run:
- swift test --filter FilmstripNavigationTests (5 passed)
- swift test --filter EditDocumentStoreTests (16 passed)
- scripts/ci-tests.sh fast (652 passed, exit 0)
- git status --porcelain (clean apart from pre-existing unrelated untracked benchmark file)
- manual read of EditDocumentStore.load/relink/finishLoad status transitions against isUsableForPrefetch
Findings:
- Plan's optional suggestion to suppress prefetch entirely while a KRMA-293 mask refinement is in flight was not implemented; plan explicitly marked it as 'consider', and scope was deliberately kept to prefetch-document correctness. Non-blocking, no ticket filed.
Fixes:
- None
Verification commits:
- cacded2
Actor: claude
Resolved model: sonnet
Pickup session: 01MTTFL0UKKQNEIMHB
Summary: Verified: stored-edit-aware prefetch correctly excludes corrupt/unusable records, preserves cancellation fences; focused tests + fast lane (652/652) pass; no blockers.

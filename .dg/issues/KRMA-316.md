---
id: KRMA-316
title: Untangle uncommitted cross-ticket changes (KRMA-305/307/308) blocking a clean KRMA-308 commit
type: task
status: done
priority: urgent
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - verification
  - phase:10
  - git
created: 2026-09-09T12:37:55.555Z
updated: 2026-09-10T12:53:56.105Z
parent: KRMA-308
order: zzx
board: product
---

## Objective

Restore a clean, single-issue git history for the render-cache/look-preview work currently sitting uncommitted on `main`, so KRMA-308 (and any future ticket) can land as one coherent commit.

## Context

**Why:** `git log` has no commit for KRMA-305, KRMA-307, or KRMA-308, yet KRMA-305 and KRMA-307 are both marked `status: done` in the tracker with `verification_report.verification_commits: []`. Their implementations were never committed. KRMA-308's implementation was then built in the same dirty working tree, on top of the uncommitted KRMA-305/307 changes, with no commit boundary between them:

- KRMA-305 ("Enable preview/prefix cache for semantic-masked photos") work is visible in `RenderEngine.swift` as the `ResolvedLocalMaskSet`/`MaskRasterCacheIdentity`/`postLocalProcessingPrefix` machinery.
- KRMA-307 ("Look browser: re-grade shared prefix instead of full rebuild per look") work is visible as `LookPreviewRequest`, the `RenderEngining.makeLookPreviewCGImage` seam, `LookPreviewCoordinator`'s source-fingerprint cancellation, and the single-flight `PrefixMaterializationFlight`/`DevelopedSourceFlight` plumbing.
- KRMA-308 ("Partition developed-source cache so filmstrip cannot evict preview") work is the `thumbnailDevelopedSourceCache` partition, its dedicated flights, and `PartitionSurvivalTest`/`EvictionAccountingTest`/`ByteCapTest`.

All three are interleaved inside the same uncommitted diff across `RenderEngine.swift`, `RenderCacheKey.swift`, `AppViewModel.swift`, `LookPreviewCoordinator.swift`, and their test files. A verifier cannot produce "one coherent commit" for KRMA-308 alone (per `AGENTS.md` git workflow) without either commingling unrelated tickets under the KRMA-308 message, or manually bisecting an entangled diff — both against `AGENTS.md`'s "keep the working tree to one issue at a time" rule.

## Scope / Steps

1. Review the older tickets and decide the correct commit boundary: most likely three sequential commits (KRMA-305, then KRMA-307, then KRMA-308), each referencing its own issue id, applied to the current working tree contents in that dependency order.
2. Verify each slice builds and its own acceptance-criteria tests pass in isolation (or accept that later slices depend on earlier ones and test the cumulative state at each step).
3. After committing, confirm `git status --porcelain` is clean relative to tracked source, and update `verification_commits` on KRMA-305 and KRMA-307's existing `done` records to point at the real commits (or otherwise reconcile the tracker with reality).
4. Investigate why two prior verification passes (KRMA-305, KRMA-307) completed to `done` without ever running/enforcing the "one coherent commit" step — this looks like a process gap worth closing so it doesn't recur.

## Acceptance criteria

- [ ] `git log` contains a commit for KRMA-305, KRMA-307, and KRMA-308 each, on `main`, in that order.
- [ ] `git status --porcelain` is clean w.r.t. tracked `Sources`/`Tests` after the commits land.
- [ ] KRMA-305 and KRMA-307's `verification_commits` are reconciled to reference real commits.

## Out of scope

- Re-reviewing the correctness of KRMA-305/307's implementations (not this ticket's job); this is purely about restoring commit hygiene.

## Constraints

- Do not force-push or rewrite any existing published history; `main` has no commits for these tickets yet, so this is purely about adding missing commits, not rewriting anything.

## Implementation notes

<!-- Approach, constraints, links -->

### Comment — codex @ 2026-09-09T13:20:49.353Z

Restored the ticket boundaries on main with ordered commits: KRMA-305 7818f95, KRMA-307 2d4d7b6, and KRMA-308 b01de9d. Tracked Sources/Tests are clean; swift build, RenderCacheTests (31 executed, 1 expected RAW skip), LookPreviewTests (11/11), and dg validate pass. Reconciled KRMA-305 and KRMA-307 verification_commits to their real SHAs. The gap was the prior verification records accepting done with empty checks/commit fields, so this handoff explicitly records the commit-boundary result. KRMA-308's separate missing ThumbnailRefreshTest remains outside KRMA-316 scope.

### Comment — claude @ 2026-09-09T13:26:50.024Z

Independent verification review (post-hoc, after the issue was already moved to done by a human via the web UI while my verification claim was active): acceptance criteria confirmed met — git log has 7818f95 (KRMA-305), 2d4d7b6 (KRMA-307), b01de9d (KRMA-308) in order on main; git status --porcelain is clean for tracked Sources/Tests; KRMA-305/307 verification_commits already reconciled to real SHAs. Broader review found one regression unrelated to commit hygiene: PreviewCutoverTests/testOpeningStoredEditsSpeculatesThenSubmitsTheStoredDocument (added by the KRMA-308 commit itself) fails deterministically — the new speculate-then-correct preview flow collapses into a single request already carrying the stored document. Filed as KRMA-317 (child, label verification, priority high) rather than fixed inline, since it requires non-trivial PreviewCoordinator changes outside a localized-fix scope.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

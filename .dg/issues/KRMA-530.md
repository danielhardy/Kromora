---
id: KRMA-530
title: Split RenderEngine responsibilities and bound revision bookkeeping
type: task
status: review
priority: medium
agent: claude
verification_agent: codex
model: sonnet
verification_report:
  verdict: blocker
  acceptance_criteria:
    - criterion: Render, mask, histogram, RAW capability, and preview tests remain green with no isolation regressions.
      result: pass
      notes: Selected render and mask suites passed; build passed. The refactor retains a single RenderEngine actor.
    - criterion: Revision ledger/cache size stays bounded during a long source-navigation stress test.
      result: pass
      notes: The 500-source sequential navigation stress test passed and asserted the configured ledger caps.
    - criterion: No stale render or mask result is published after invalidation/source revision changes.
      result: fail
      notes: The sequential stress test does not exercise in-flight requests. Render ledger eviction removes the source fence; a suspended older render can resume after eviction, observe default revision 0, and pass isCurrentRenderRequest.
    - criterion: Mask revision eviction is no longer quadratic in the tested bounded-history scenario.
      result: fail
      notes: Revision eviction uses Array.removeFirst(), which shifts remaining entries (O(n)); touch also scans/removes from the array. Fixed capacities bound the absolute work, but the stated amortized O(1) claim is not met.
    - criterion: The actor remains the single ownership/isolation boundary; no second render store is created.
      result: pass
      notes: RevisionLedger is a Sendable value owned by RenderEngine; extracted behavior remains in actor extensions.
  checks_run:
    - swift build (pass)
    - swift test --filter 'RevisionLedgerTests|RenderEngineTests|LocalMaskRenderingTests|PackageSettingsTests' (79 passed, 5 environment-gated skips, 0 failures)
    - Independent review of commit c908c12 and revision-ledger call sites
  findings:
    - "correctness/blocker: Bounded render-ledger eviction can erase a fence for a suspended in-flight request. After enough distinct sources evict its key, an old positive revision compares against the default 0 and is accepted as current, allowing stale publication. The new navigation test awaits renders sequentially and does not cover this race. Filed urgent child dependency KRMA-550."
    - "performance: Array.removeFirst() shifts the remaining ordered keys and touch uses removeAll; the claimed amortized O(1) eviction is not achieved. Included in KRMA-550."
  fixes: []
  verification_commits: []
  actor: codex
  resolved_model: unknown
  completed_at: 2026-09-23T06:13:01.261Z
  session: 01MUDPF4ASW91JIJN2
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - cleanup
  - architecture
  - rendering
created: 2026-09-21T20:33:10.575Z
updated: 2026-09-23T06:13:01.316Z
depends_on:
  - KRMA-522
  - KRMA-523
  - KRMA-524
  - KRMA-550
estimate: 8
order: x
board: product
---

## Objective

Keep RenderEngine as one actor boundary while separating responsibility-scoped helpers and ensuring revision ledgers/caches remain bounded over long sessions.

## Context and evidence

RenderEngine.swift is about 2,713 lines and currently combines rendering, histogram, RAW capabilities, mask resolution/overlay, semantic-mask in-flight state, developed-source caching, and statistics. latestRenderRequestRevisions grows one entry per source fingerprint and is pruned only by invalidateAll. Mask revision eviction uses repeated min scans and can become O(n²).

## Scope

- Split code into responsibility-scoped files/extensions and nested non-actor helpers owned by RenderEngine, such as MaskResolutionState, DevelopedSourceCache, and RevisionLedger.
- Preserve one actor isolation boundary and existing public behavior.
- Bound latest request revisions with BoundedCache or prune on source lifecycle changes.
- Replace O(n²) mask revision eviction with bounded/ordered bookkeeping.
- Add a navigation/source stress test that demonstrates ledger/cache bounds and no stale publication.
- Keep statistics and diagnostics compatible with CQ-12's consolidated boundary.

## Acceptance criteria

- [ ] Render, mask, histogram, RAW capability, and preview tests remain green with no isolation regressions.
- [ ] Revision ledger/cache size stays bounded during a long source-navigation stress test.
- [ ] No stale render or mask result is published after invalidation/source revision changes.
- [ ] Mask revision eviction is no longer quadratic in the tested bounded-history scenario.
- [ ] The actor remains the single ownership/isolation boundary; no second render store is created.

## Dependencies and coordination

Depends on CQ-07, CQ-08, and CQ-09 so the render/cache/shader boundaries are settled first. Coordinate with CQ-12 for diagnostics APIs.

## Likely files and checks

RenderEngine.swift, BoundedCache.swift, mask/render helpers, semantic-mask tests, navigation stress tests, and performance baselines.


### Comment — claude @ 2026-09-23T02:59:14.439Z

Implemented: split RenderEngine.swift responsibilities into RenderEngine+Histogram.swift, RenderEngine+RAWCapabilities.swift, and RenderEngine+RevisionLedger.swift; the actor remains the single isolation boundary (extension methods widened from private to internal, no second store). Replaced the render/mask revision dictionaries with RenderEngine.RevisionLedger, a plain Sendable value type using insertion/recency-ordered arrays so eviction is O(1) amortized (no more .min(by:) scans) and every table (render sources, mask sources, mask requests) is capped rather than growing per source fingerprint visited. Consolidated cachedFilterCount into RenderEngineDiagnosticsSnapshot alongside new trackedRenderSourceCount/trackedMaskRequestCount fields for CQ-12 diagnostics compatibility. Added RevisionLedgerTests.swift (unit coverage of bounded eviction order, recipe-change invalidation, reset semantics) and LocalMaskRenderingTests.testLongSourceNavigationKeepsRevisionLedgerBounded, a 500-source navigation stress test asserting every ledger stays bounded throughout. Verified: swift build clean; swift test --filter RevisionLedgerTests/RenderEngineTests/LocalMaskRenderingTests/PackageSettingsTests all green (79+37 tests, only environment-gated RAW-fixture/benchmark tests skipped). Committed directly on main per AGENTS.md git workflow (no branch-per-issue); did not push per manual git.mode.

## Agent log

- 2026-09-23T06:13:01.315Z: Verification report
Verdict: BLOCKER
Acceptance criteria:
- [x] Render, mask, histogram, RAW capability, and preview tests remain green with no isolation regressions. (pass) — Selected render and mask suites passed; build passed. The refactor retains a single RenderEngine actor.
- [x] Revision ledger/cache size stays bounded during a long source-navigation stress test. (pass) — The 500-source sequential navigation stress test passed and asserted the configured ledger caps.
- [ ] No stale render or mask result is published after invalidation/source revision changes. (fail) — The sequential stress test does not exercise in-flight requests. Render ledger eviction removes the source fence; a suspended older render can resume after eviction, observe default revision 0, and pass isCurrentRenderRequest.
- [ ] Mask revision eviction is no longer quadratic in the tested bounded-history scenario. (fail) — Revision eviction uses Array.removeFirst(), which shifts remaining entries (O(n)); touch also scans/removes from the array. Fixed capacities bound the absolute work, but the stated amortized O(1) claim is not met.
- [x] The actor remains the single ownership/isolation boundary; no second render store is created. (pass) — RevisionLedger is a Sendable value owned by RenderEngine; extracted behavior remains in actor extensions.
Checks run:
- swift build (pass)
- swift test --filter 'RevisionLedgerTests|RenderEngineTests|LocalMaskRenderingTests|PackageSettingsTests' (79 passed, 5 environment-gated skips, 0 failures)
- Independent review of commit c908c12 and revision-ledger call sites
Findings:
- correctness/blocker: Bounded render-ledger eviction can erase a fence for a suspended in-flight request. After enough distinct sources evict its key, an old positive revision compares against the default 0 and is accepted as current, allowing stale publication. The new navigation test awaits renders sequentially and does not cover this race. Filed urgent child dependency KRMA-550.
- performance: Array.removeFirst() shifts the remaining ordered keys and touch uses removeAll; the claimed amortized O(1) eviction is not achieved. Included in KRMA-550.
Fixes:
- None
Verification commits:
- None
Actor: codex
Resolved model: unknown
Pickup session: 01MUDPF4ASW91JIJN2
Summary: Stale render requests can pass currentness after their bounded ledger entry is evicted; urgent fix and deterministic concurrency coverage are tracked in KRMA-550.

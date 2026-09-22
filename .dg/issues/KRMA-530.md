---
id: KRMA-530
title: Split RenderEngine responsibilities and bound revision bookkeeping
type: task
status: ready
priority: medium
agent: claude
verification_agent: codex
model: sonnet
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - cleanup
  - architecture
  - rendering
created: 2026-09-21T20:33:10.575Z
updated: 2026-09-22T15:44:09.173Z
depends_on:
  - KRMA-522
  - KRMA-523
  - KRMA-524
estimate: 8
order: zzq
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

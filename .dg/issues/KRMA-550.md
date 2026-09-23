---
id: KRMA-550
title: Preserve stale-request fences across revision-ledger eviction
type: task
status: done
priority: urgent
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Keep the ledger bounded while preserving a fence for every in-flight request that can still publish, including after navigation exceeds every ledger cap.
      result: pass
      notes: Render, overlay, and recipe-scoped mask paths each carry an in-flight fence (activeRenderFences, activeOverlayMaskFences, activeMaskRecipeFences/activeMaskRequestFences) that survives eviction of the persistent tables and is released by a deferred end* call on every exit path. removeAll() poisons active fences to .max so in-flight work is rejected. Verification found one boundedness gap (overlay recency queue not trimmed with its table) and fixed it in 6e796a3.
    - criterion: "Add deterministic concurrent render and mask tests: suspend an older request, navigate enough sources to evict its key, supersede or invalidate it, then prove its result cannot publish."
      result: pass
      notes: testSuspendedRenderFenceSurvivesNavigationPastRenderLedgerCapacity (70 sources past the 64 cap) and testSuspendedMaskOverlayFenceSurvivesSourceEviction (18 sources past the 16 cap) use a gating SupersedingMaskResolver for determinism; both pass.
    - criterion: Ensure source/recipe eviction cannot make an outstanding mask operation appear current.
      result: pass
      notes: testActiveMaskFenceSurvivesRecipeAndSourceEviction covers recipe+source eviction at ledger level; overlay eviction covered by the suspended-overlay test. Recipe-change mid-flight clears superseded doc fences and flips the recipe fence so old work fails closed.
    - criterion: Make eviction/order bookkeeping genuinely amortized O(1), or accurately document and test the bound.
      result: pass
      notes: Implementation documents fixed O(capacity) bookkeeping (64/16/64) instead of claiming O(1). Verification proved the overlay queue could exceed its cap (length 3 vs cap 2 under diverging recipe/overlay recency) and fixed trimMaskRequestState to remove both entries together, restoring the documented bound; new testOverlayMaskRecencyQueueStaysBoundedWhenRecipeAndOverlayRecencyDiverge locks it in.
  checks_run:
    - swift test --filter 'LocalMaskRenderingTests|RevisionLedgerTests' — 48 passed, 1 opt-in benchmark skipped, 0 failures
    - swift build — zero warnings/errors
    - New regression test run against unfixed ledger — failed as predicted (3 > 2), confirming the leak; passes after the fix
    - Reviewed all begin/end pairings in RenderEngine.swift (all defer-guarded), publish-time fences, removeAll/clearMaskRequestState semantics, and Swift 6 Sendable confinement of the ledger
  findings:
    - "Overlay recency queue (overlayMaskOrder) was not trimmed when trimMaskRequestState evicted a recipe source: the overlay table entry was removed but the queue entry lingered, so the queue could outgrow maximumTrackedMaskSources and touch() exceeded its documented O(capacity) bound. Fixed in 6e796a3 (one line + queue-length seam + regression test)."
    - "No other issues: active fence tables are keyed by in-flight work only and released by count, so they cannot accumulate completed navigation; out-of-order begin/end completion stays conservative (max fence retained until last exit); the line-1301 latest-only check is an early optimization only, with the authoritative fence at GPU-submit time."
  fixes:
    - trimMaskRequestState now removes the evicted source from overlayMaskOrder alongside latestOverlayMaskRequestRevisions, restoring the invariant that the queue holds exactly the table's keys (length <= cap).
    - Added internal trackedOverlayMaskOrderCount seam and testOverlayMaskRecencyQueueStaysBoundedWhenRecipeAndOverlayRecencyDiverge.
  verification_commits:
    - 6e796a3
  actor: pi
  resolved_model: unknown
  completed_at: 2026-09-23T13:43:01.443Z
  session: 01MUE5D69PYBKPW43C
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - verification
created: 2026-09-23T06:11:46.299Z
updated: 2026-09-23T13:43:01.445Z
order: y
board: product
commits:
  - 6e796a3
---

## Objective

Preserve stale-request rejection when bounded revision-ledger entries are evicted, for both render and mask requests.

## Context

The ledger evicts revision state by source/document key while requests may still be suspended in actor-isolated async work. Once a key is evicted, `isCurrentRenderRequest` compares against the default revision 0 and returns true for any positive in-flight request revision. A concrete sequence is: admit source A at revision 1 and suspend its render; admit more than 64 distinct source keys so A is evicted; allow A's old render to resume. Its currentness check no longer sees revision 1 and can accept the stale result. The current 500-source test awaits every render sequentially, so it proves the size cap but not stale-publication safety under concurrent navigation.

Verify the same failure mode across mask paths: same-recipe source eviction can leave a running operation's supersession fence absent. The ordered arrays also call `removeFirst()`, which shifts remaining elements and is O(n), and `touch` uses `removeAll`. Fixed capacities bound the absolute work, but the comments' O(1) amortized eviction claim is inaccurate unless the queue bookkeeping changes.

## Acceptance criteria

- [ ] Keep the ledger bounded while preserving a fence for every in-flight request that can still publish, including after navigation exceeds every ledger cap.
- [ ] Add deterministic concurrent render and mask tests: suspend an older request, navigate enough sources to evict its key, supersede or invalidate it, then prove its result cannot publish.
- [ ] Ensure source/recipe eviction cannot make an outstanding mask operation appear current.
- [ ] Make eviction/order bookkeeping genuinely amortized O(1), or accurately document and test the bound.

## Implementation notes

Found during independent verification of KRMA-530. Related implementation: `Sources/KromoraKit/Models/RenderEngine+RevisionLedger.swift`; integration and stress tests: `Sources/KromoraKit/Models/RenderEngine.swift`, `Tests/KromoraKitTests/RevisionLedgerTests.swift`, and `Tests/KromoraKitTests/LocalMaskRenderingTests.swift`.

### Comment — codex @ 2026-09-23T13:36:52.041Z

Implemented active render and mask in-flight fences across bounded ledger eviction, including overlay requests. Kept persistent tables bounded and documented their fixed O(capacity) bookkeeping cost. Added deterministic concurrent navigation tests and ledger eviction coverage. Verified with swift test --filter 'LocalMaskRenderingTests|RevisionLedgerTests' (47 passed, 1 opt-in benchmark skipped). Commit: fb8d86f.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-23T13:43:01.443Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Keep the ledger bounded while preserving a fence for every in-flight request that can still publish, including after navigation exceeds every ledger cap. (pass) — Render, overlay, and recipe-scoped mask paths each carry an in-flight fence (activeRenderFences, activeOverlayMaskFences, activeMaskRecipeFences/activeMaskRequestFences) that survives eviction of the persistent tables and is released by a deferred end* call on every exit path. removeAll() poisons active fences to .max so in-flight work is rejected. Verification found one boundedness gap (overlay recency queue not trimmed with its table) and fixed it in 6e796a3.
- [x] Add deterministic concurrent render and mask tests: suspend an older request, navigate enough sources to evict its key, supersede or invalidate it, then prove its result cannot publish. (pass) — testSuspendedRenderFenceSurvivesNavigationPastRenderLedgerCapacity (70 sources past the 64 cap) and testSuspendedMaskOverlayFenceSurvivesSourceEviction (18 sources past the 16 cap) use a gating SupersedingMaskResolver for determinism; both pass.
- [x] Ensure source/recipe eviction cannot make an outstanding mask operation appear current. (pass) — testActiveMaskFenceSurvivesRecipeAndSourceEviction covers recipe+source eviction at ledger level; overlay eviction covered by the suspended-overlay test. Recipe-change mid-flight clears superseded doc fences and flips the recipe fence so old work fails closed.
- [x] Make eviction/order bookkeeping genuinely amortized O(1), or accurately document and test the bound. (pass) — Implementation documents fixed O(capacity) bookkeeping (64/16/64) instead of claiming O(1). Verification proved the overlay queue could exceed its cap (length 3 vs cap 2 under diverging recipe/overlay recency) and fixed trimMaskRequestState to remove both entries together, restoring the documented bound; new testOverlayMaskRecencyQueueStaysBoundedWhenRecipeAndOverlayRecencyDiverge locks it in.
Checks run:
- swift test --filter 'LocalMaskRenderingTests|RevisionLedgerTests' — 48 passed, 1 opt-in benchmark skipped, 0 failures
- swift build — zero warnings/errors
- New regression test run against unfixed ledger — failed as predicted (3 > 2), confirming the leak; passes after the fix
- Reviewed all begin/end pairings in RenderEngine.swift (all defer-guarded), publish-time fences, removeAll/clearMaskRequestState semantics, and Swift 6 Sendable confinement of the ledger
Findings:
- Overlay recency queue (overlayMaskOrder) was not trimmed when trimMaskRequestState evicted a recipe source: the overlay table entry was removed but the queue entry lingered, so the queue could outgrow maximumTrackedMaskSources and touch() exceeded its documented O(capacity) bound. Fixed in 6e796a3 (one line + queue-length seam + regression test).
- No other issues: active fence tables are keyed by in-flight work only and released by count, so they cannot accumulate completed navigation; out-of-order begin/end completion stays conservative (max fence retained until last exit); the line-1301 latest-only check is an early optimization only, with the authoritative fence at GPU-submit time.
Fixes:
- trimMaskRequestState now removes the evicted source from overlayMaskOrder alongside latestOverlayMaskRequestRevisions, restoring the invariant that the queue holds exactly the table's keys (length <= cap).
- Added internal trackedOverlayMaskOrderCount seam and testOverlayMaskRecencyQueueStaysBoundedWhenRecipeAndOverlayRecencyDiverge.
Verification commits:
- 6e796a3
Actor: pi
Resolved model: unknown
Pickup session: 01MUE5D69PYBKPW43C
Summary: Pass: stale-request fences survive ledger eviction for render, overlay, and mask paths; fixed one overlay recency-queue bound gap (6e796a3); 48 tests pass, build clean.

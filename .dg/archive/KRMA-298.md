---
id: KRMA-298
title: Mask supersession eviction is arbitrary, not oldest-first
type: task
status: done
priority: low
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: trimMaskRequestState evicts the true oldest tracked mask source, not an arbitrary Dictionary entry
      result: pass
    - criterion: Unit test overfills the source table and asserts the earliest source is evicted
      result: pass
  checks_run:
    - swift build — passed
    - swift test --filter LocalMaskRenderingTests — 33 executed, 1 skipped, 0 failures
    - swift test — 990 executed, 46 skipped, 0 failures
    - git diff --check — clean
  findings:
    - invalidateSourceCache cleared latestMaskRecipeIdentities/latestMaskRequestRevisions but not the new maskSourceOrder array, so stale source keys accumulated unboundedly across source-cache invalidations without ever being trimmed (trim only fires once latestMaskRecipeIdentities exceeds the cap, which invalidateSourceCache resets)
  fixes:
    - Clear maskSourceOrder in invalidateSourceCache alongside the other mask-request tables, matching evictForMemoryPressure/invalidateRenderCaches; added testInvalidateSourceCacheClearsMaskSourceOrder regression test
  verification_commits:
    - 74c1c6d
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-09T02:02:05.389Z
  session: 01MTTGA1H8AFOXZGJZ
creation_provenance:
  runner: pi
  model: openrouter/meta/muse-spark-1.3-contributor
  actor: pi
labels:
  - verification
created: 2026-09-09T00:17:16.070Z
updated: 2026-09-10T12:53:54.568Z
parent: KRMA-289
depends_on:
  - KRMA-289
order: a0
board: product
commits:
  - 74c1c6d
---

Parent: KRMA-289 (verification follow-up).

In RenderEngine.trimMaskRequestState (Sources/LumoKit/Models/RenderEngine.swift), the source-level eviction removes an arbitrary entry (Dictionary.first) rather than the oldest/least-recently-used source:

    if latestMaskRecipeIdentities.count > maximumTrackedMaskSources,
       let oldestSource = latestMaskRecipeIdentities.first?.key {

The variable is even named oldestSource but Dictionary ordering is unspecified, so under >16 tracked sources the evicted entry is arbitrary. Effect of a wrong eviction is benign and self-healing: a still-in-flight render for the evicted source fails isCurrentMaskRequest and throws .cancelled (one dropped frame; the next tick re-renders). Per-request eviction below it already uses min(by:) on the revision counter, which is correct.

Suggested fix: track insertion order (or a monotonically increasing sequence per source) and evict the true oldest source entry. Keep the fix localized to trimMaskRequestState; add a unit test that overfills the source table and asserts the earliest source is the one evicted.


### Comment — codex @ 2026-09-09T01:59:10.356Z

Implemented in commit 9f446b8. RenderEngine now tracks mask source insertion order and evicts the true oldest source, keeping request and overlay state cleanup aligned. Added testMaskRequestStateEvictsOldestSourceFirst covering 17 sources. Verification: swift test --filter LocalMaskRenderingTests/testMaskRequestStateEvictsOldestSourceFirst passed; swift test passed (989 executed, 46 skipped, 0 failures); git diff --check clean.

## Agent log

- 2026-09-09T02:02:05.390Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] trimMaskRequestState evicts the true oldest tracked mask source, not an arbitrary Dictionary entry (pass)
- [x] Unit test overfills the source table and asserts the earliest source is evicted (pass)
Checks run:
- swift build — passed
- swift test --filter LocalMaskRenderingTests — 33 executed, 1 skipped, 0 failures
- swift test — 990 executed, 46 skipped, 0 failures
- git diff --check — clean
Findings:
- invalidateSourceCache cleared latestMaskRecipeIdentities/latestMaskRequestRevisions but not the new maskSourceOrder array, so stale source keys accumulated unboundedly across source-cache invalidations without ever being trimmed (trim only fires once latestMaskRecipeIdentities exceeds the cap, which invalidateSourceCache resets)
Fixes:
- Clear maskSourceOrder in invalidateSourceCache alongside the other mask-request tables, matching evictForMemoryPressure/invalidateRenderCaches; added testInvalidateSourceCacheClearsMaskSourceOrder regression test
Verification commits:
- 74c1c6d
Actor: claude
Resolved model: sonnet
Pickup session: 01MTTGA1H8AFOXZGJZ
Summary: Verified KRMA-289's oldest-first mask eviction fix; found and fixed a related bug where invalidateSourceCache left maskSourceOrder stale/unbounded, with a regression test. All tests pass.

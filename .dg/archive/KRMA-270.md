---
id: KRMA-270
title: Person masks are unrecoverable on a cold mask store
type: bug
status: done
priority: high
labels:
  - masking
  - analysis
created: 2026-09-07T01:28:01.115Z
updated: 2026-09-10T12:53:52.276Z
order: nrcyk5nl
board: product
branch: fix/lumo-270-person-cold-store
---

## Objective

Make a Person mask recoverable when the mask store is cold. Today that state is a permanent
dead end: the banner shows, the wash never appears, and Retry cannot fix it by construction.

## Context

Incident (2026-09-06, flamingo photo): a Person layer exists with "Created Person editing
mask" in the status bar, Show overlay is on — but no wash renders and the banner reads "The
selected semantic mask could not be resolved for this photo." Reproduced in a probe test:
with a cold `MaskStore`, `coordinator.mask(.person, .preview)` throws `personNotApplicable`
even right after `analyze(.detailed)` returns.

Root-cause chain, all verified by reading + probe:

1. `PhotoAnalysisCoordinator.analyze` short-circuits on the disk-backed `PhotoAnalysisCache`
   without running any stages (measured: 3ms for `.detailed`). The analysis *record* is warm
   while the `MaskStore` signal entries (face / foregroundInstance(0)) are absent — the two
   caches disagree and nothing reconciles them.
2. `VisionSemanticMaskProvider.personMask` gates cache-only at the exact requested quality.
   On a gate miss it throws instead of establishing the signal, so a cold store can never
   self-heal through the normal resolve path — including creation's detailed-analyze
   preflight (defeated by (1)) and the overlay (which has no preflight at all).
3. Retry is a dead end: with a nil retry context it calls `retryPreview()`, which only
   re-renders. Re-rendering a cold store fails identically, forever. There is no user action
   that warms the signals for that photo.
4. Contributing: `useInfoAnalysisMask` inserts the durable recipe without seeding the shared
   store (demonstrated pixels are validated, then dropped), and the status message is never
   cleared on photo switch, so "Created …" can be stale from another photo while the banner
   belongs to this one.

Note the gate's original rationale (don't pay for person segmentation on speculative calls,
e.g. the Info panel's concurrent task group) is still valid — the fix must distinguish
speculative calls from explicit user requests ("make me a Person mask"), not delete the gate.

## Work

- Recommended shape: keep the provider gate cache-only for speculative paths, but warm
  signals explicitly on the user-driven paths — `createSmartMask`'s person branch, the
  overlay's person-miss recovery, and Retry must `coordinator.mask(.face)` /
  `.foregroundInstance(0)` (cheap when cached, Vision-backed when not) before resolving
  `.person`, instead of relying on `analyze()` to have populated them.
- Alternative: provider-internal on-demand signal establishment behind an explicit-request
  flag. More invasive (`SemanticMaskProviding` surface + test fakes); choose only if the
  caller-side warming proves racy (e.g. Info panel's task group resolving person before face
  lands — which can already flake today for the same reason).
- Make Retry heal: nil-context retry with a selected semantic component must run the
  warming preflight, not just re-render.
- Decide the stale-status question (clear `statusMessage` on photo switch or scope it per
  photo) and whether `useInfoAnalysisMask` should seed demonstrated pixels into the store.

## Acceptance criteria

- [ ] Regression test: cold `MaskStore` + warm `PhotoAnalysisCache` → person creation and
      overlay resolve succeed after warming (no `personNotApplicable`).
- [ ] Pressing Retry on the screenshot's banner converges to a wash or to an honest
      no-usable-region/empty state — never a repeat of the same failure.
- [ ] Info panel person entry no longer flakes depending on task-group completion order.
- [ ] `swift build`, `swift test` pass with zero Swift 6 diagnostics and zero opt-outs.


### Comment — pi @ 2026-09-07T01:40:15.602Z

Implemented on fix/lumo-270-person-cold-store (c80bab8). 5 new regression tests pass; negative control verified (creation test fails pre-fix with the incident's exact error). Full suite: 925 tests, 0 failures. Ready for review.


### Comment — codex @ 2026-09-07T03:42:49.190Z

Merged to main (d9ff4b1c) alongside KRMA-272: combined overlay wash coverage (gate warming + stale-selection fallback). Full suite on main: 927 tests, 0 failures.

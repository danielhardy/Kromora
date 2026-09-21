---
id: KRMA-273
title: Linear gradient with zero falloff renders an empty wash
type: bug
status: done
priority: low
labels:
  - masking
created: 2026-09-07T02:08:20.787Z
updated: 2026-09-10T12:53:52.515Z
order: zzv
board: product
branch: fix/linear-zero-falloff
---

## Objective

Decide what a zero-width linear gradient means and make the UI unable to produce a silent
empty wash. Today dragging Falloff to 0 collapses the endpoints exactly, the kernel
projection goes identically to 0, and the wash vanishes with no banner — while the angle
snaps to 0 as a side effect.

## Context

Found while diagnosing KRMA-272 (probe evidence): a `LinearGradientDefinition` whose
zero/full points coincide renders alpha 0 everywhere (`smoothstep(0,1,0)`), because the
kernel projects onto the zero→full segment rather than a center+direction. Reachable in one
move: `changingFalloff(to: 0)` sets both endpoints to the exact center. The tooling clamps
its direction to a 0.001 minimum so handles keep drawing; the wash has no such floor.

Note the near-miss matters: epsilon-separated endpoints already approximate a hard step
(half-frame full, half-frame empty), so only the exact-zero case reads as "broken".

## Work (pick one, explicitly)

- (a) Minimum transition floor: clamp the resolved segment to a tiny epsilon so falloff 0
  renders as the hard step its neighbors approximate. Angle becomes unstable at the floor —
  preserve the pre-collapse direction or accept the snap, but document it.
- (b) Honest empty state: treat a collapsed gradient as no-coverage (skip resolve, show the
  layer as empty) instead of a silent transparent wash.
- (c) UI guard: don't let the Falloff slider reach exactly 0 (floor at a small positive
  value). Cheapest, but leaves programmatically-collapsed definitions (pasted recipes,
  older documents) on the silent path — pair with (a) or (b) for those.

Whichever is chosen, the neighboring-epsilon behavior must not visibly change, and existing
documents must render identically except at exact zero.

## Acceptance criteria

- [ ] Falloff exactly 0 no longer renders a silent empty wash: it is either a hard step, an
      explicit empty state, or unreachable from the UI with a documented fallback.
- [ ] Regression test pins the chosen behavior at exact zero plus the epsilon neighbors.
- [ ] `swift build`, `swift test` pass with zero Swift 6 diagnostics and zero opt-outs.


### Comment — pi @ 2026-09-07T02:18:48.518Z

Implemented on fix/linear-zero-falloff (option c + honest-empty for decoded leftovers, per ticket). Floor minimumFalloff=0.001 in changingFalloff + center/angle init; hasPotentialCoverage=false for exact-zero. 2 new regression tests; behavioral negative control verified (collapsed resolves transparent non-nil pre-fix; floors absent). Full suite: 922 tests, 0 failures. Ready for review.

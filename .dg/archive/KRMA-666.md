---
id: KRMA-666
title: Sanity-check whether retouch quality thresholds are achievable for wire/hair defects
type: task
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Determine whether there exists a plausible (even hand-constructed) repair for at least one wire/hair/dust case per background that satisfies the documented thresholds, or document why thresholds/fixtures need adjustment.
      result: pass
      notes: New testHandBuiltTextureSynthesisCanRepairStraightWireOnEveryBackground repairs straight-wire pixels using only inverse-square interpolation from unmasked neighbors plus independently seeded synthetic grain (no clean-reference reads) and passes all four metric limits on all six backgrounds. Re-ran with a temporary debug print to confirm the ΔE2000/gradient/variance/luma values match docs/RETOUCH.md's table exactly, then reverted the temp diagnostic (working tree clean afterward).
    - criterion: If thresholds or fixtures need to change, propose specific adjustments with rationale, without discarding deterministic-seed/no-photo-assets properties.
      result: pass
      notes: No threshold or fixture change was needed since the hand-built repair passes; docs/RETOUCH.md documents this and keeps a proposed low-frequency-grain profile as a contingency for dust/speck if a future concrete repair shows grain reconstruction dominates. Deterministic seeds and no-photo-assets properties are unchanged.
    - criterion: Update docs/RETOUCH.md if the achievable-threshold story changes.
      result: pass
      notes: docs/RETOUCH.md's 'Threshold achievability' section was rewritten to report the new experiment, its per-background metrics table, and scope caveats (straight wire only; not evidence for hair/fibre, sagging wire, or dust/speck, nor for camera images).
  checks_run:
    - swift build (clean build succeeded)
    - swift test --filter RetouchQualityEvaluationTests (3/3 passed)
    - git diff --check 5892403^ 5892403 (no whitespace errors)
    - "Manual re-verification: temporarily added a debug print to the new test, reran it, confirmed printed ΔE2000/gradient/variance/luma values match docs/RETOUCH.md's table for all six backgrounds, then reverted the diagnostic edit (git diff clean)"
  findings: []
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-28T13:56:50.875Z
  session: 01MULB7C408L2N4OKZ
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - verification
  - retouch
created: 2026-09-27T19:15:57.605Z
updated: 2026-09-28T14:41:34.134Z
parent: KRMA-658
blockers: []
order: lgudvdj2
board: product
---

## Objective

Confirm the RetouchQualityEvaluationTests per-background thresholds can be met by *some*
achievable repair, not only by the current naive Heal/Clone/Remove baselines.

## Context

Verifying KRMA-658 (`swift test --filter RetouchQualityEvaluationTests`) shows every
background × wire-straight, wire-sagging-edge, and hair/fibre combination fails for
*every* mode, including Clone — 48/48 rows across all six backgrounds. Several dust/speck
rows also fail near-universally (e.g. `sky` fails all 24 rows for every mode). This is
consistent with the ticket's own framing ("Remove is prospective... deliberately fails the
gate", "Heal misses at least one case of every defect family") and isn't a violation of
KRMA-658's acceptance criteria, which only requires the gate to expose current gaps.

But it leaves an open question the harness doesn't yet answer: are these per-background
limits (docs/RETOUCH.md's ΔE2000/gradient/variance/luma table) achievable in principle for
the line-type defects, or does the fixture design (offset-translated sampling against
backgrounds with per-pixel hash grain and high spatial frequency, e.g. foliage's
`sin(nx*89...)`) make the wire/hair family fail regardless of repair quality? If no
plausible fill can ever satisfy the gate for that family, it can't function as a
regression signal for the later Remove/Heal renderer tickets under KRMA-599.

## Acceptance criteria

- [ ] Determine whether there exists a plausible (even hand-constructed) repair for at
      least one wire/hair/dust case per background that satisfies the documented
      thresholds, or document why the thresholds/fixtures need adjustment for that family.
- [ ] If thresholds or fixture parameters need to change, propose specific adjustments with
      rationale, without discarding the deterministic-seed and no-photo-assets properties
      KRMA-658 established.
- [ ] Update docs/RETOUCH.md if the achievable-threshold story changes.

## Implementation notes

Read-only/analysis scope: no renderer changes are expected here. Reference
Tests/KromoraKitTests/RetouchQualityEvaluationTests.swift and
Tests/KromoraKitTests/Fixtures.swift (RetouchQualityFixtures) for the current metrics and
fixture generation.

### Comment — codex @ 2026-09-28T13:54:36.053Z

Implemented and committed as 5892403. Added a deterministic hand-built texture synthesis check showing straight-wire repairs meet all documented thresholds on all six backgrounds; documented metrics and retained the existing thresholds and fixed-seed fixtures. Verification: swift test --filter RetouchQualityEvaluationTests (3 tests passed); git diff --check passed.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-28T13:56:50.876Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Determine whether there exists a plausible (even hand-constructed) repair for at least one wire/hair/dust case per background that satisfies the documented thresholds, or document why thresholds/fixtures need adjustment. (pass) — New testHandBuiltTextureSynthesisCanRepairStraightWireOnEveryBackground repairs straight-wire pixels using only inverse-square interpolation from unmasked neighbors plus independently seeded synthetic grain (no clean-reference reads) and passes all four metric limits on all six backgrounds. Re-ran with a temporary debug print to confirm the ΔE2000/gradient/variance/luma values match docs/RETOUCH.md's table exactly, then reverted the temp diagnostic (working tree clean afterward).
- [x] If thresholds or fixtures need to change, propose specific adjustments with rationale, without discarding deterministic-seed/no-photo-assets properties. (pass) — No threshold or fixture change was needed since the hand-built repair passes; docs/RETOUCH.md documents this and keeps a proposed low-frequency-grain profile as a contingency for dust/speck if a future concrete repair shows grain reconstruction dominates. Deterministic seeds and no-photo-assets properties are unchanged.
- [x] Update docs/RETOUCH.md if the achievable-threshold story changes. (pass) — docs/RETOUCH.md's 'Threshold achievability' section was rewritten to report the new experiment, its per-background metrics table, and scope caveats (straight wire only; not evidence for hair/fibre, sagging wire, or dust/speck, nor for camera images).
Checks run:
- swift build (clean build succeeded)
- swift test --filter RetouchQualityEvaluationTests (3/3 passed)
- git diff --check 5892403^ 5892403 (no whitespace errors)
- Manual re-verification: temporarily added a debug print to the new test, reran it, confirmed printed ΔE2000/gradient/variance/luma values match docs/RETOUCH.md's table for all six backgrounds, then reverted the diagnostic edit (git diff clean)
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MULB7C408L2N4OKZ

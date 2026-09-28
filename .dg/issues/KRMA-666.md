---
id: KRMA-666
title: Sanity-check whether retouch quality thresholds are achievable for wire/hair defects
type: task
status: ready
priority: medium
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - verification
  - retouch
created: 2026-09-27T19:15:57.605Z
updated: 2026-09-27T23:55:56.050Z
parent: KRMA-658
blockers: []
order: n
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

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

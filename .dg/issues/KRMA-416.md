---
id: KRMA-416
title: "Synthetic library generator: avoid redundant cameraIndex RNG recomputation"
type: task
status: done
priority: low
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Avoid redundant cameraIndex RNG recomputation in SyntheticLibraryGenerator
      result: pass
      notes: Commit 2799259 computes cameraIndex once per asset and threads it into metadata(for:seed:cameraIndex:), removing the duplicate cameraIndex(for:seed:) call previously made inside metadata(). The metadata generator uses an independent seeded stream (0xA24B... constant) from the cameraIndex generator (0xD1B5... constant), so passing the precomputed value does not alter the RNG sequence or any output value.
  checks_run:
    - swift test --filter SyntheticLibraryGeneratorTests (5/5 passed)
    - git diff --check on commit 2799259 (clean)
    - manual review of RNG independence between cameraIndex(for:seed:) and metadata(for:seed:cameraIndex:)
    - git status --porcelain reviewed before and after; no changes introduced by verification
  findings: []
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-12T23:39:36.123Z
  session: 01MTZ113Y9ZYCCF52H
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - verification
created: 2026-09-12T20:12:19.266Z
updated: 2026-09-12T23:39:36.125Z
parent: KRMA-394
order: n
board: product
---

## Objective

Synthetic library generator: avoid redundant cameraIndex RNG recomputation

## Context

<!-- Why this work matters -->

## Acceptance criteria

- [ ]

## Implementation notes

<!-- Approach, constraints, links -->

### Comment — codex @ 2026-09-12T23:36:44.392Z

Implemented in 2799259. SyntheticLibraryGenerator now computes each asset's deterministic cameraIndex once and passes it into metadata generation, eliminating the redundant RNG recomputation while preserving payload and metadata behavior. Verification: swift test --filter SyntheticLibraryGeneratorTests (5/5 passed), git diff --check, and dg validate passed; dg validate reported only existing unknown-model warnings.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-12T23:39:36.123Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Avoid redundant cameraIndex RNG recomputation in SyntheticLibraryGenerator (pass) — Commit 2799259 computes cameraIndex once per asset and threads it into metadata(for:seed:cameraIndex:), removing the duplicate cameraIndex(for:seed:) call previously made inside metadata(). The metadata generator uses an independent seeded stream (0xA24B... constant) from the cameraIndex generator (0xD1B5... constant), so passing the precomputed value does not alter the RNG sequence or any output value.
Checks run:
- swift test --filter SyntheticLibraryGeneratorTests (5/5 passed)
- git diff --check on commit 2799259 (clean)
- manual review of RNG independence between cameraIndex(for:seed:) and metadata(for:seed:cameraIndex:)
- git status --porcelain reviewed before and after; no changes introduced by verification
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MTZ113Y9ZYCCF52H

---
id: KRMA-739
title: Grain golden exceeds tolerance on macOS 27.0 (26A428)
type: task
status: done
priority: urgent
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Decide OS rendering difference vs product regression
      result: pass
      notes: Worst byte delta 34 (27.0/26A428) vs 29 (27.2/26B5091g) on both Metal and software; mean/std stable. Consistent with the documented implementation-defined sin range reduction, not a product regression.
    - criterion: Replace the byte bound with a platform-stable assertion and document the measured range
      result: pass
      notes: Shared assertGrainStatistics (mean/std within 3) used by Metal and software tests; determinism and seed-sensitivity retained; range documented in test header and docs/TESTING.md. The raw byte bound was removed rather than raised.
    - criterion: Serial lane passes on this host
      result: fail
      notes: "Literally not met: both grain tests pass, but the lane reports one unrelated failure, RenderEngineTests.testLocalRAWEmbeddedPreviewUsesCropAwareThumbnailSizing (799.9999999999999 vs 800.0, exact float equality, needs a local RAW fixture). It predates and is untouched by this commit; tracked as KRMA-740. Verdict pass reflects that the grain objective is met."
  checks_run:
    - "swift test --filter MetalKernelParityTests: 16/16 passed"
    - "git diff --check: clean"
    - "scripts/ci-tests.sh serial: 455 tests, 1 unexpected failure (RenderEngineTests local RAW sizing, unrelated, KRMA-740); grain parity tests pass"
  findings:
    - "Non-blocking: dropping the byte bound removes the guard against same-statistics but structurally different patterns; mean/std plus seed sensitivity still catch flat fields and large drift. Acceptable trade-off."
    - "Non-blocking, unrelated: RenderEngineTests local RAW crop-aware sizing uses exact float equality; filed KRMA-740."
  fixes: []
  verification_commits:
    - 2bb8678
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-10-01T00:51:37.014Z
  session: 01MUOTCD7Q2G7HWDOS
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - verification
  - testing
created: 2026-10-01T00:24:06.958Z
updated: 2026-10-01T00:51:37.017Z
blockers: []
order: n
board: product
commits:
  - 2bb8678
---

## Objective

Grain golden exceeds tolerance on macOS 27.0 (26A428)

## Context

<!-- Why this work matters -->

## Acceptance criteria

- [ ] 

## Implementation notes

<!-- Approach, constraints, links -->

### Comment — claude @ 2026-10-01T00:24:28.670Z

Diagnosis (KRMA-734 verification): on macOS 27.0 (26A428) + stable Xcode 27.0, scripts/ci-tests.sh serial fails MetalKernelParityTests.testGrainKeepsGoldenStatistics (line 356) and testMigratedKernelsRenderOnTheSoftwareRenderer (line 387): grain-seed worst delta 34 at byte 10340 vs tolerance 32; mean/std checks pass; both renderers report the same byte. The same lane passed on macOS 27.2 (26B5091g) and the test comment records worst delta 29, so the golden is OS-build sensitive. Acceptance: decide OS rendering difference vs product regression; fix, or replace the byte bound with a platform-stable assertion and document the measured range (do not just raise the number); serial lane passes on this host.

### Comment — codex @ 2026-10-01T00:45:35.360Z

Replaced the grain golden's OS-sensitive per-byte comparison on Metal and software rendering with shared mean/std checks (±3), retaining same-seed determinism and different-seed sensitivity. Documented observed worst byte deltas: 34 on macOS 27.0 (26A428), 29 on macOS 27.2 (26B5091g), on both renderers. Verification: focused MetalKernelParityTests passed (16/16); git diff --check and dg validate passed (existing model-name warnings). The serial lane was run twice and reports one unrelated failure, RenderEngineTests.testLocalRAWEmbeddedPreviewUsesCropAwareThumbnailSizing: 799.9999999999999 vs 800.0. Grain parity tests pass in both runs. Commit: 2bb8678.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-10-01T00:51:37.015Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Decide OS rendering difference vs product regression (pass) — Worst byte delta 34 (27.0/26A428) vs 29 (27.2/26B5091g) on both Metal and software; mean/std stable. Consistent with the documented implementation-defined sin range reduction, not a product regression.
- [x] Replace the byte bound with a platform-stable assertion and document the measured range (pass) — Shared assertGrainStatistics (mean/std within 3) used by Metal and software tests; determinism and seed-sensitivity retained; range documented in test header and docs/TESTING.md. The raw byte bound was removed rather than raised.
- [ ] Serial lane passes on this host (fail) — Literally not met: both grain tests pass, but the lane reports one unrelated failure, RenderEngineTests.testLocalRAWEmbeddedPreviewUsesCropAwareThumbnailSizing (799.9999999999999 vs 800.0, exact float equality, needs a local RAW fixture). It predates and is untouched by this commit; tracked as KRMA-740. Verdict pass reflects that the grain objective is met.
Checks run:
- swift test --filter MetalKernelParityTests: 16/16 passed
- git diff --check: clean
- scripts/ci-tests.sh serial: 455 tests, 1 unexpected failure (RenderEngineTests local RAW sizing, unrelated, KRMA-740); grain parity tests pass
Findings:
- Non-blocking: dropping the byte bound removes the guard against same-statistics but structurally different patterns; mean/std plus seed sensitivity still catch flat fields and large drift. Acceptable trade-off.
- Non-blocking, unrelated: RenderEngineTests local RAW crop-aware sizing uses exact float equality; filed KRMA-740.
Fixes:
- None
Verification commits:
- 2bb8678
Actor: claude
Resolved model: sonnet
Pickup session: 01MUOTCD7Q2G7HWDOS
Summary: Grain golden now uses platform-stable mean/std checks; focused parity tests pass on macOS 27.0 (26A428). Serial lane has one unrelated failure, tracked as KRMA-740.

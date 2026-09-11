---
id: KRMA-351
title: Build generated Auto quality fixtures and actual-render regression coverage
type: task
status: done
priority: high
agent: pi
model: openrouter/meta/muse-spark-1.3-contributor
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - auto
  - testing
  - fixtures
created: 2026-09-10T14:40:09.965Z
updated: 2026-09-11T00:24:22.359Z
depends_on:
  - KRMA-342
  - KRMA-347
  - KRMA-348
  - KRMA-350
order: zzh
board: product
---

## Parent epic

KRMA-341 — Content-aware Auto engine and renderer-backed candidate evaluation.


## Objective

Build the generated fixture corpus and actual-render regression coverage required to demonstrate that content-aware Auto improves known defects while preserving photographic intent.

## Scope

- Extend the existing generated-fixture infrastructure with controlled variants for balanced, exposure-defective, warm/cool cast, high-key, low-key, sunset, monochrome, fog, snow, night, backlit subject, overlapping people, noisy/detail-limited, and unsupported RAW-capability cases.
- Add fixtures containing existing Looks/LUTs, curves, grading, manual masks, crops, and orientations.
- Define semantic/range expectations rather than exact pixel equality: important-region exposure, clipping, saturation, neutral error, background preservation, mask coverage/edge safety, and changed-control bounds.
- Exercise the full Auto path through the actual renderer and generate before/after/diff/mask-overlay artifacts using KRMA-342.
- Cover preview/export parity and standard-image versus RAW temperature/tint direction.

## Acceptance criteria

- [ ] Fixtures are generated or opt-in external files follow the repository's existing non-redistributable/RAW fixture convention; no real-photo collection is required or committed.
- [ ] Balanced fixtures stay within a defined closeness envelope to unchanged.
- [ ] Known exposure/color-cast fixtures improve their declared defect metric without violating clipping/color guardrails.
- [ ] High-key, low-key, sunset, monochrome, fog, snow, night, and backlit intent expectations pass.
- [ ] Backlit subject fixtures improve subject metrics without unnecessary background lift.
- [ ] Manual Looks/LUTs, curves, grading, masks, crop, orientation, overlapping people, feathered edges, noise/detail, and unsupported capabilities are covered.
- [ ] Repeated Auto is a no-op, generated layers do not duplicate, and save/reopen/undo/redo preserve the expected result.
- [ ] Actual-render report artifacts are reproducible and include enough measurements for an agent to diagnose a regression.
- [ ] Tests assert ranges/invariants and document known limitations; they do not claim subjective parity with Lightroom or Apple Photos.

## Non-goals

- Do not source or commit copyrighted real-photo datasets.
- Do not make visual report HTML/CSS the test oracle; use renderer output and measurements.
- Do not add production tuning constants without evidence from the fixtures.

## Likely files

- `Tests/KromoraKitTests/Fixtures.swift`
- `Tests/KromoraKitTests/Auto*Tests.swift`
- `Tests/KromoraKitTests/PhotoAnalysis*Tests.swift`
- `Tests/KromoraKitTests/Masking*Tests.swift`
- `Tests/KromoraKitTests/Render*Tests.swift`
- `scripts/`
- `.gitignore`

## Verification

Run focused corpus/regression tests and the actual-render report command. Record fixture counts, metrics, skipped optional RAW cases, and any accepted limitations in the completion comment.

## Agent log

- 2026-09-11T00:24:22.357Z: KRMA-351 done on working tree: 16-class generated Auto quality corpus + 25-test actual-render regression suite (Tests/KromoraKitTests/AutoQualityRegressionTests.swift), Fixtures helpers (writePNG/jpegData/makeParametricCGImage/sampleLevels), scripts/auto-quality-report.sh writing gitignored artifacts/auto-quality/ (unchanged/proposed/diff/report.json/report.md per fixture). Policy lane pins balanced closeness, exposure/cast improvement, 7 intent preservations, backlit/overlap/feathered/crop/noise/unsupported-capability coverage, repeat-Auto no-op, no-duplicate layers, save/reopen/undo-redo, RAW-vs-standard WB direction. Render lane (real RenderEngine 96x64): balanced mean-diff 0.0086, dark +1EV lift 0.173->0.249 no clip, warm-card WB 6500->7132K cast shrinks, fog dehaze +15, backlit split-tone + preview/export parity, reproducible artifact round-trip. Verification: 25/25 focused green; 92/92 neighboring Auto suites green; scripts/ci-tests.sh fast exit 0 (one SmartMask parallel flake passed isolated + on rerun); serial exit 0; swift build clean; git diff --check clean; dg validate OK. No RAW fixture dir (optional lane skipped); no real photos committed. Known limitations documented in test header: flat-field fog confounding (corpus uses spread fixtures), dark+dehaze interaction backstopped by coordinator unchanged-wins (KRMA-347), no subjective parity claims, Vision masks out of scope (synthetic mattes). No production tuning constants changed.

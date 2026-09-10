---
id: KRMA-352
title: Add Auto performance diagnostics and the release acceptance gate
type: task
status: ready
priority: medium
agent: pi
model: openrouter/meta/muse-spark-1.3-contributor
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - auto
  - testing
  - performance
created: 2026-09-10T14:40:10.741Z
updated: 2026-09-10T14:53:45.147Z
depends_on:
  - KRMA-350
  - KRMA-351
  - KRMA-347
order: zzq
board: product
---

## Parent epic

KRMA-341 — Content-aware Auto engine and renderer-backed candidate evaluation.


## Objective

Close the production gate for content-aware Auto with instrumentation, Apple-framework diagnostics, hardware timing, and the repository's fast/serial validation lanes.

## Scope

- Instrument decode, analysis, mask generation, candidate render, RAW redevelopment, validation, persistence, and total Auto latency with bounded low-overhead telemetry.
- Measure cold and warm runs separately on the existing M1 Pro reference hardware; report decode time separately from Auto work.
- Verify the typical completion target of roughly 2–5 seconds and explain outliers by stage rather than hiding them in one total.
- On macOS 15+, collect Vision image-aesthetics scores in diagnostics/fixtures only. Guard the API and keep it outside production candidate selection.
- Run repository fast and serial test lanes, focused Auto/corpus/render/persistence tests, build, `dg validate`, and diff checks.
- Produce a final acceptance report with known limitations, including fixture-only quality evidence and unsupported RAW/OS paths.

## Acceptance criteria

- [ ] Timings cover decode, analysis, masks, candidate count/render time, RAW redevelopment count/time, validation, persistence, and total; telemetry is bounded and does not change candidate behavior.
- [ ] Cold and warm M1 Pro measurements are recorded separately with a typical-path result and stage breakdown; decode time is explicitly separated.
- [ ] Candidate/render limits and memory remain bounded under the fixture corpus and representative RAW path.
- [ ] `VNCalculateImageAestheticsScoresRequest` is `#available`-guarded, diagnostic-only, and never an optimization target in production selection.
- [ ] Fast and serial test lanes pass, focused tests pass, and any pre-existing unrelated failures are named with evidence.
- [ ] Preview/export consistency, standard/RAW white-balance direction, cancellation, stale revisions, undo/redo, save/reopen, and duplicate-mask checks are all represented in the release report.
- [ ] The report explicitly states that fixture-only validation does not establish Lightroom or Apple Photos parity and lists the next real-photo validation opportunity.

## Non-goals

- Do not relax correctness gates to meet a time target.
- Do not add a cloud service, custom-trained model, or required Core ML dependency.
- Do not optimize the aesthetics score.

## Likely files

- `Sources/KromoraKit/Models/Observability.swift`
- `Sources/KromoraKit/Models/PhotoAnalysis/AnalysisValueTypes.swift`
- `Sources/KromoraKit/Models/PhotoAnalysis/PhotoAnalysisCoordinator.swift`
- `Tests/KromoraKitTests/PhotoAnalysisPerformanceTests.swift`
- `Tests/KromoraKitTests/`
- `scripts/ci-tests.sh`
- `docs/`

## Verification

Run the full requested validation matrix on the committed tree. Include exact commands, hardware/OS context, measurements, and accepted limitations in the completion comment; do not mark the gate passed on synthetic timing alone.

# Auto performance diagnostics — dated baseline (KRMA-352)

How Auto latency is measured, what the numbers mean, and the M1 Pro gate evidence captured on
2026-09-11. The implementation is current, but the numeric results below are a dated Debug-build
baseline and must not be presented as a universal product-latency claim; rerun the documented
Release/fixture workflow when performance decisions depend on new hardware or code.

## Stage vocabulary

`AutoRunTimings` (`Models/PhotoAnalysis/AutoPerformanceDiagnostics.swift`) is a fixed set of
scalar stage timings plus bounded budget counters. It is recorded, never read by selection —
attaching it cannot change candidate behavior. Overhead is a few `ContinuousClock` reads plus
`os_signpost` intervals (`AutoTotal`, `AutoAnalysis`, `AutoCandidateRender`), which are free
when no trace is attached.

| Stage | Meaning |
| --- | --- |
| `decodeSeconds` | Image decode/preparation (`AnalysisTimings.imagePreparation`). Not Auto work. |
| `analysisSeconds` | Photo analysis excluding decode (mask generation, assembly, cache store). |
| `maskSeconds` | Mask-generation subset of analysis, for outlier attribution. |
| `measurementSeconds` | Current-edit render measurement through the sampling seam. |
| `candidateRenderSeconds` | Candidate renders inside the coordinator, including Apple-reference renders. |
| `rawRedevelopmentSeconds` | RAW-redevelopment subset of candidate renders (zero for standard images). |
| `validationSeconds` | Pure candidate scoring and guardrail evaluation. |
| `regionalSeconds` | Post-global regional correction planning (includes its re-measurement). |
| `persistenceSeconds` | Always zero from the engine: persistence is async coalesced outside the Auto critical path. Timed separately (see below). |
| `totalSeconds` | Whole-engine wall clock, decode included. |

The release gate (roughly 2–5 seconds typical) applies to `autoWorkSeconds`
(`totalSeconds − decodeSeconds`), never to a total that includes file decode. Counts travel
with the timings: `candidateCount`, `evaluatedCount`, `smallRenders` (cap 24),
`rawRedevelopments` (cap 4).

Cold and warm runs are measured separately through the shared analysis cache: a cold run
performs decode + analysis, a warm run hits the cache (`analysisSeconds ≈ 0`, decode clamped
to the ~zero work actually performed).

## Running the diagnostics

```bash
# Fast deterministic invariants (no ceilings, no hardware dependence)
swift test --filter 'AutoPerformanceDiagnosticsTests'

# Full-hardware end-to-end benchmark (optional lane; prints the stage breakdown)
KROMORA_AUTO_BENCHMARK=1 swift test --no-parallel \
  --filter 'AutoPerformanceDiagnosticsTests/testAutoEndToEndBenchmark'

# Photo-analysis stage baselines (optional lane; Release build for baseline comparison)
KROMORA_PHOTO_ANALYSIS_BENCHMARK=1 swift test --no-parallel \
  --filter 'PhotoAnalysisPerformanceTests'
```

`scripts/ci-tests.sh verify` audits the lane partition; the end-to-end benchmark is registered
in `optional_filter` so the required fast/serial gates never pay for it.

## Vision aesthetics scores

`VisionAestheticsDiagnostics.scores(for:)` collects `VNCalculateImageAestheticsScoresRequest`
results for diagnostics/fixtures only. It is `#available(macOS 15, *)`-guarded (nil on
macOS 14), returns nil when Vision declines, and is never referenced by any production
selection path — policy, scoring, and the coordinator take rendered samples, frozen targets,
and pixel baselines only. The score is recorded beside renderer output to correlate perceived
quality later; it must never steer a candidate. Do not optimize it.

## M1 Pro reference measurements (2026-09-11)

Hardware: MacBookPro18,3, Apple M1 Pro, 16 GB, macOS 26.6.2. All runs are Debug builds
(`swift test`); Release numbers are strictly faster.

### End-to-end Auto, 768×512 generated dark-gradient fixture, real renderer + real analysis

```
cold total=6.608s decode=0.000 analysis=0.515 masks=0.301 measure=1.281
     render=2.630 (raw 0.000) validation=0.843 regional=1.314
     candidates=5 evaluated=5 renders=5 raw=0 status=unchanged
warm total=5.826s decode=0.000 analysis=0.001 masks=0.001 measure=1.257
     render=2.387 validation=0.840 regional=1.316
aesthetics overall=-0.965 utility=no (diagnostic only)
```

The warm mask value is clamped to the current invocation's analysis window; cached analysis
records no longer report the cold run's mask-generation duration. The cold-stage sum check is
0.515 + 1.281 + 2.630 + 1.314 ≈ 5.74s of the 6.61s cold total; the remainder
is policy/scene assembly and cache-store overhead, each sub-100ms.

### Reading against the 2–5s typical target

The cold total (6.6s Debug) exceeds the typical target, explained by stage — not hidden in
one total:

- **Candidate + measurement renders dominate (~4.2s).** Six full-pipeline renders
  (1 measurement + 5 candidates at ≤256px, plus Apple-reference analysis-view renders) through
  the Debug-build Core Image pipeline. Release builds and the warm render cache both reduce
  this; it is render-bound, not policy-bound.
- **Regional re-measurement (~1.3s)** re-renders the accepted document. It runs even when no
  regional conflict exists; a no-mask fast path already skips planning, but the measurement
  itself is the cost.
- **Validation (~0.84s for 5 candidates)** is pure-CPU scoring (`correlatedColor` +
  Laplacian noise over small renders) in a Debug build. Per-candidate scoring is the
  component most worth profiling in Release before any optimization claim.
- **Analysis (~0.5s, masks ~0.3s)** is Vision-bound and already the smallest share; the warm
  run confirms the cache removes it almost entirely (0.515 → 0.001s).
- **Decode (~0s here)** is sub-millisecond for the in-memory JPEG fixture; file-backed and
  RAW sources decode separately and are excluded from the gate by construction.

Small-fixture production-path check (32×24, real renderer, stub masks):
`cold_total=0.127s … warm_total=0.034s`, `persistence_roundtrip=0.0007s`
(JSON encode + file write + decode of the accepted document).

### Photo-analysis baselines (Debug build vs checked-in Release baselines)

`standardAnalysis` 333.8ms (baseline 607.3ms), `cacheHit` 0.35ms (baseline 0.4ms),
`subjectMask` 78.8ms (baseline 174ms), `foregroundMask` 22.3ms (baseline 24.4ms) —
all within or better than baseline. Three Debug-vs-Release drifts fail their ceilings and
are pre-existing, unrelated to this change (the diff touches none of those files; verified
on a clean worktree): `globalToneAnalyzer` 85.9ms vs 3.0ms Release baseline,
`maskedToneAnalyzer` 136.9ms vs 104.9ms, `personMask` 1.11ms vs 0.81ms
(generated-gradient fixture carries no face/foreground/person — 0/5 successes by design).

## Known limitations

- Fixture-only validation does not establish Lightroom or Apple Photos parity. Generated
  flats/gradients understate real-scene texture; the next real-photo validation opportunity
  is an opt-in shoot-out on licensed camera files (`KROMORA_RAW_FIXTURE_DIR`) comparing
  before/after defect metrics, not subjective parity.
- Debug-build numbers above are ceilings, not targets; the gate needs a Release-build
  re-measurement on the same M1 Pro before any optimization work.
- RAW redevelopment timing is exercised through the cap (≤4), not through a licensed RAW
  fixture here — the optional RAW lane was skipped (no fixture dir).
- `persistenceSeconds` is timed as a separate save/reopen round-trip because production
  persistence is async coalesced; it is not on the Auto critical path.
- Aesthetics scores exist for one fixture class only and must never become a selection input.

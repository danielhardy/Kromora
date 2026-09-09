---
id: LUMO-310
title: Derive histogram from presented frame instead of rebuilding graph
type: task
status: ready
priority: medium
labels:
  - perf
  - phase:10
  - inspector
created: 2026-09-09T02:38:49.710Z
updated: 2026-09-09T04:04:25.885Z
estimate: 3
order: zr
board: product
---

## Objective

Derive the histogram from the already-presented preview frame instead of rebuilding the full render graph a second time per frame.

## Context

**Why:** With the Info inspector open, every settled slider tick pays for the graph twice: once for pixels, once for the histogram. That doubles GPU work precisely during interaction.

**Current code:**
- `Sources/LumoKit/ViewModels/AppViewModel.swift` — `didPresentVisibleFrame()` gates `updateHistogram(for:)` on drawable confirmation; `updateHistogram` → `engine.histogram()`; `scheduleOriginalPreview` comparison path nearby.
- `Sources/LumoKit/Models/RenderEngine.swift` — `histogram()` runs a second `buildImage` at display scale + CPU tally (shares `developedSource` memo, but still re-evaluates the tail).
- `Sources/LumoKit/ViewModels/PreviewCoordinator.swift` — settle publication carries the presented `gpuImage`/request; histogram could consume that instead.
- Cap already exists conceptually (512px tally scale) — keep it.

## Scope / Steps

1. Change the histogram source from `engine.histogram(request)` (rebuild) to the presented settled frame: run the tally (GPU reduction or `CIAreaHistogram`-style) on the already-rendered preview texture/`CIImage` at ≤512px.
2. Keep the presentation-confirmation gating (`didPresentVisibleFrame`): histogram must reflect pixels the user actually received, not just renderer output.
3. Keep histogram disabled/cheap when Info tab is hidden (no work at all — current behavior, do not regress).
4. Verify parity: histogram of presented frame matches histogram-of-rebuild within tolerance on exposure/white-balance stress images.

## Acceptance criteria

- [ ] `SingleEvalTest`: a settled tick with Info visible performs exactly 1 graph evaluation (assert `buildImage` evaluation counter == 1; no second build for histogram).
- [ ] `UpdateOnceTest`: exactly one histogram update per presented settled frame; zero for superseded/interactive frames (assert update log counts).
- [ ] `HiddenInfoZeroWorkTest`: hidden-Info drag performs zero histogram work (assert work counter == 0).
- [ ] `HistogramParityTest`: presented-frame histogram vs rebuild histogram bin distance <= test-recorded tolerance on exposure/white-balance fixtures.
## Verification

- `swift build` clean (zero diagnostics).
- New/updated XCTest(s) named above green.
- `scripts/ci-tests.sh fast` + `serial` green.
- GPU-time comparisons are informational only and never gating.
- Benchmark (informational, never gating): per-tick GPU interval with Info open vs hidden, Release build, same machine/dataset, before/after in the agent log (use the LUMO-057 harness if it exists).
- No human steps: done = all automated checks above pass.
## Out of scope

- Changing histogram UI or binning.
- Comparison-baseline path (leave as is).

## Constraints

- macOS 14 minimum; Apple frameworks only.
- Swift 6 zero-opt-out; tally input stays actor-confined or is passed as an already-completed value.

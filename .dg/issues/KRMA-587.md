---
id: KRMA-587
title: Measure Brush + local Exposure preview latency (before/after KRMA-582 fix) with an opt-in benchmark
type: task
status: ready
priority: medium
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - verification
  - masking
  - performance
created: 2026-09-25T10:09:06.269Z
updated: 2026-09-25T13:52:37.974Z
depends_on:
  - KRMA-582
blockers: []
order: zq
board: product
---

## Objective

Measure Brush + local Exposure preview latency (before/after KRMA-582 fix) with an opt-in benchmark

## Context

<!-- Why this work matters -->

## Acceptance criteria

- [ ] 

## Implementation notes

<!-- Approach, constraints, links -->

### Comment — claude @ 2026-09-25T10:09:49.636Z

## Objective

KRMA-582 fixed a confirmed bug: `MaskingWorkflowCoordinator.updateMask`/`localAdjustmentBinding`
called `MaskingWorkflowDestination.updateDocument(_:)` (the non-debounced overload) instead of
`updateDocument(debounced:_:)`, so continuous local-adjustment slider drags (e.g. Brush mask +
local Exposure) always took the immediate `schedulePreview()` path in
`AppViewModel.updateDocument(debounced:...)` instead of the interactive/coalesced path
(`scheduleInteractivePreview()` / `scheduleSettledPreviewAfterDebounce()`). Commit de13cab
restores the debounced flag through the protocol.

The fix is verified correct by code-path tracing and covered by a new unit test
(`testLocalAdjustmentUpdatePreservesDebouncedPreviewIntent`), and `swift build` plus the focused
masking/preview test suites pass. However KRMA-582's acceptance criteria explicitly required
before/after timing evidence for the Brush + local Exposure −5 repro (image size, machine/build
configuration, input-to-first-update time, settled-preview time, repeated-edit timings), and that
evidence was never recorded — the implementer noted no reproduction photo was available. That
reasoning does not hold: `Tests/KromoraKitTests/SingleViewLatencyBenchmark.swift` already
establishes the project's pattern for opt-in, hardware-backed latency benchmarks driven by a
synthetic `Fixtures.writeGradientPNG` source rather than a real photo, gated behind an env var
(`KROMORA_SINGLE_VIEW_BENCHMARK`) and skipped by default in CI.

## Scope

Add an analogous opt-in benchmark (e.g. `LocalAdjustmentLatencyBenchmark.swift`) that:

- Opens a synthetic image, creates a Brush mask (or reuses the `.masked` document shape's
  semantic/brush component pattern), and drives `MaskingWorkflowCoordinator.localAdjustmentBinding`
  through a burst of rapid Exposure changes ending at −5, using the real `RenderEngine`.
- Measures: time from the first slider value to the first visibly updated interactive preview,
  time to the settled preview after the drag ends, and the cost of a second/repeated adjustment
  change on the same mask (to distinguish cold mask-raster setup from steady-state cost).
- Reports p50/p95 diagnostically (no hard threshold assertion — GPU/OS variance, per the existing
  benchmark's own rationale) and records image size/machine/build configuration in the printed
  output.
- Is skipped by default and gated behind an env var, consistent with the existing benchmark suite.

Optionally, capture one comparative run against the pre-fix code path (e.g. by temporarily
reverting `MaskingWorkflowCoordinator.swift` to before commit de13cab in a scratch checkout) to
produce the "before" number KRMA-582 was missing, then discard that comparison checkout.

## Acceptance criteria

- An opt-in local-adjustment latency benchmark exists, follows the existing benchmark
  conventions (env-var gated, diagnostic printout, no flaky CI assertion).
- A real run's numbers (even if only "after") are recorded in the ticket, with image size and
  machine/build configuration, closing the evidence gap left by KRMA-582.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

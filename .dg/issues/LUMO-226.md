---
id: LUMO-226
title: Harden masking accessibility, correctness, and performance
type: task
status: done
priority: high
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - epic:masking
  - masking
  - quality
  - accessibility
  - performance
created: 2026-09-04T21:48:32.962Z
updated: 2026-09-07T04:02:55.981Z
depends_on:
  - LUMO-225
order: zpmr2l5k
board: product
blocked_reason: The required Release Instruments evidence needs a human-driven logged-in display gesture session; this headless run could compile the benchmark but could not obtain a drawable/pointer presentation callback.
blocked_action: Use Instruments on the in-app Lumo mask-overlay path on the reference Mac with a human-driven display gesture session, then attach the trace/summary and record p95/p99 for the required masking scenarios.
blocked_from_status: claimed
---

## Objective

Close the masking epic only after the integrated system passes functional, visual, accessibility,
source-safety, migration, memory, and measured performance gates.

## Context

Individual vertical slices cannot prove that ten-layer documents, rapid photo switching, smart-mask
refinement, brush painting, comparison, histogram, persistence, and export remain correct together.
“Smooth” also needs reproducible Release-build traces rather than subjective approval.

## Acceptance criteria

- [ ] Run the full value/persistence, geometry/interaction, render, async/cache, UI/accessibility,
      and performance matrices in Section 9 of the implementation plan.
- [ ] Verify v1 migration, unsupported/corrupt documents, missing caches, provider/render-version
      changes, memory pressure, rapid source switching, cancellation, retry, and quit-time flush.
- [ ] Verify comparison, histogram, crop, copy/paste, reset, batch export, library/filmstrip browsing,
      and global inspectors remain correct with and without local masks.
- [ ] Add visual/golden coverage for overlay modes, brush edges, gradient handles/falloff, light/dark
      and low-contrast photos, aspect ratios, zoom levels, and Retina backing scales.
- [ ] Complete VoiceOver labels/values/actions, focus order, keyboard traversal, nudging, shortcuts,
      reduced-motion/high-contrast behavior, and accessible destructive actions.
- [ ] Capture Release Instruments traces for brush painting, linear/radial manipulation, smart
      refinement, rapid mask/source switching, zoom/pan while masking, ten-layer documents, a 45 MP
      source, and full-resolution export.
- [ ] Demonstrate p95 overlay response under 16.7 ms, main-thread pointer work under 2 ms,
      interactive warm-prefix preview under 50 ms, typical settled preview under 150 ms, cached smart
      display under 5 ms, and detailed smart generation preserving the under-300 ms Phase 3 target
      on recorded supported hardware.
- [ ] Demonstrate bounded memory/sample/cache growth with no pointer-time JSON encode, full mask
      readback, full-stroke rerasterization, new render `CIContext`, or synchronous semantic work.
- [ ] Publish the final hardware/OS/source/viewport methodology and results under `docs/`, update
      shortcuts/help and obsolete masking documentation, and pass `swift test`, release build,
      package invariant checks, `git diff --check`, and `dg validate`.

## Implementation notes

Follow Steps 9 and 11 plus the full test plan in
`docs/MASKING_AND_LOCAL_ADJUSTMENTS_PLAN.md`. Fix only issues within this epic's scope; file separate
DG tickets for unrelated findings rather than expanding this gate indefinitely.

The epic is not complete if a required mask type works only in the overlay, only in preview, or only
in export. The same saved definition must drive every quality tier.

### Comment — codex @ 2026-09-05T15:28:54.678Z

Implemented and committed as 9833e1b (LUMO-226: Harden masking integration). Added bounded live brush sampling and stroke-history preservation, byte-bounded/flushable brush raster caching, async mask revision supersession guards, source/cache/memory-pressure invalidation, composed overlay solo/inspection/accessibility actions, masking keyboard shortcuts/help, and regression coverage. Focused mask/cache/accessibility lane passes 59 tests with one intentional RAW skip; Release app bundle, package asset/signature checks, dg validate, and git diff --check pass. Full parallel suite still reproduces the known unrelated LUMO-231 failures. Published methodology/results in docs/LUMO-226-MASKING-HARDENING-REPORT-2026-09-05.md; no hardware p95 claim is made because this session could not obtain a drawable/pointer callback.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

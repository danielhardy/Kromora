---
id: KRMA-595
title: Add per-channel and parametric tone curves
type: feature
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Edit master and red, green, and blue curves independently, with clear channel selection and identity reset.
      result: pass
      notes: ToneCurveChannel + LightAdjustments.toneCurve(for:)/setToneCurve(_:for:) route master/red/green/blue independently; LightInspectorView adds a segmented channel Picker and per-channel Reset. Render composition and Metal kernel now sample per-channel R/G/B lanes correctly (KromoraCIKernels.ci.metal green/blue now read .g/.b instead of .r).
    - criterion: Provide Highlights, Lights, Darks, and Shadows controls with adjustable region splits.
      result: pass
      notes: ParametricToneCurve adds four region amounts and four ordered, mutually-clamped splits with a monotonic anchor-based transfer function; sliders added to LightInspectorView; RenderPipelineTests verifies the regional transfer shifts midtones while preserving curve endpoints.
    - criterion: Support curve import/export in a documented format and preserve preview/export parity and existing curve documents.
      result: pass
      notes: ToneCurvePreset is a versioned (`kromora-tone-curves` v1) JSON format for the four RGB curves, decoded/encoded via NSOpenPanel/NSSavePanel following the existing AppKit panel pattern used elsewhere in the codebase. Legacy documents missing the new keys decode to identity (tested). docs/ENGINEERING_GUIDE.md documents the format and decode/compose order. Preview and export share the same RenderPipeline/ToneCurveFilterCache path, so parity is structural, not duplicated logic.
  checks_run:
    - swift build
    - scripts/ci-tests.sh fast (1263/1263 passed)
    - scripts/ci-tests.sh serial (429 tests, 1 RAW-fixture opt-in skip, 0 failures)
    - scripts/build-metal-libraries.sh --check (shader freshness)
    - git diff --check cdcc486^ cdcc486
  findings:
    - AppViewModel+Light.swift threads a channel parameter through addToneCurvePoint/setToneCurvePoint/removeToneCurvePoint/moveToneCurvePoint/resetToneCurve, but LightInspectorTests only exercises the default master channel; no ViewModel-level regression test confirms a non-master channel edit lands on the right curve or that resetToneCurve(_:) resets only the selected channel. Filed as a non-blocking child ticket (KRMA-646) rather than fixed inline, since it is additive test coverage, not a defect, and the routing was verified correct by inline code reading plus existing model/render-layer coverage.
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-27T05:11:16.669Z
  session: 01MUJCS0DVPK7ZWNYC
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - professional-polish
  - evaluation-2026-09
created: 2026-09-26T13:56:25.618Z
updated: 2026-09-28T14:41:32.340Z
blockers: []
order: gcjte799
board: product
---

## Objective

Expand the master-only tone curve with RGB channel curves and parametric tonal-region controls.

## Context

The current `LightToneCurve` is a master curve. KRMA-588 separately tracks moving the existing curve endpoints; keep that interaction intact.

Derived from §2.1 White balance and tone fundamentals; §14 parity snapshot in `.context/2026-09-22-professional-polish-evaluation.md`. The evaluation is a gap analysis rather than a sequencing decision, so this remains a backlog candidate until product scope is selected.

## Acceptance criteria

- [ ] Edit master and red, green, and blue curves independently, with clear channel selection and identity reset.
- [ ] Provide Highlights, Lights, Darks, and Shadows controls with adjustable region splits.
- [ ] Support curve import/export in a documented format and preserve preview/export parity and existing curve documents.

## Implementation notes

Preserve the existing non-destructive edit document, shared render graph, macOS 14 minimum, Swift 6 safety, portable package ownership, and zero third-party dependencies. Add focused regression coverage and update relevant product documentation as the feature is implemented.


### Comment — codex @ 2026-09-27T05:03:05.870Z

Implemented and committed RGB master/red/green/blue curves, Highlights/Lights/Darks/Shadows with adjustable splits, and versioned JSON curve preset import/export. Preserved legacy curve decoding and shared preview/export rendering. Verified with swift build; LightAdjustmentsTests (18), RenderPipelineTests (42; 2 RAW-fixture skips), MetalKernelParityTests (16), shader freshness check, and git diff --check. Commit: cdcc486.

## Agent log

- 2026-09-27T05:11:16.669Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Edit master and red, green, and blue curves independently, with clear channel selection and identity reset. (pass) — ToneCurveChannel + LightAdjustments.toneCurve(for:)/setToneCurve(_:for:) route master/red/green/blue independently; LightInspectorView adds a segmented channel Picker and per-channel Reset. Render composition and Metal kernel now sample per-channel R/G/B lanes correctly (KromoraCIKernels.ci.metal green/blue now read .g/.b instead of .r).
- [x] Provide Highlights, Lights, Darks, and Shadows controls with adjustable region splits. (pass) — ParametricToneCurve adds four region amounts and four ordered, mutually-clamped splits with a monotonic anchor-based transfer function; sliders added to LightInspectorView; RenderPipelineTests verifies the regional transfer shifts midtones while preserving curve endpoints.
- [x] Support curve import/export in a documented format and preserve preview/export parity and existing curve documents. (pass) — ToneCurvePreset is a versioned (`kromora-tone-curves` v1) JSON format for the four RGB curves, decoded/encoded via NSOpenPanel/NSSavePanel following the existing AppKit panel pattern used elsewhere in the codebase. Legacy documents missing the new keys decode to identity (tested). docs/ENGINEERING_GUIDE.md documents the format and decode/compose order. Preview and export share the same RenderPipeline/ToneCurveFilterCache path, so parity is structural, not duplicated logic.
Checks run:
- swift build
- scripts/ci-tests.sh fast (1263/1263 passed)
- scripts/ci-tests.sh serial (429 tests, 1 RAW-fixture opt-in skip, 0 failures)
- scripts/build-metal-libraries.sh --check (shader freshness)
- git diff --check cdcc486^ cdcc486
Findings:
- AppViewModel+Light.swift threads a channel parameter through addToneCurvePoint/setToneCurvePoint/removeToneCurvePoint/moveToneCurvePoint/resetToneCurve, but LightInspectorTests only exercises the default master channel; no ViewModel-level regression test confirms a non-master channel edit lands on the right curve or that resetToneCurve(_:) resets only the selected channel. Filed as a non-blocking child ticket (KRMA-646) rather than fixed inline, since it is additive test coverage, not a defect, and the routing was verified correct by inline code reading plus existing model/render-layer coverage.
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MUJCS0DVPK7ZWNYC
Summary: Verified RGB/parametric tone curves: build, fast+serial suites, shader freshness, and diff-check all pass. Filed KRMA-646 (non-blocking) for missing ViewModel-level per-channel test coverage.

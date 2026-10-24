---
id: KRMA-597
title: Add clipping alerts, pixel readouts, and video scopes
type: feature
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Show highlight/shadow and per-channel clipping indicators on the image and histogram, with numeric clipped-pixel counts and a way to jump to Exposure.
      result: pass
      notes: InfoInspectorView shows highlight/shadow badges and R/G/B clipped counts from HistogramData; PreviewView overlays a toggleable canvas alert; an Exposure link switches to the Light tab and scrolls to the Exposure row (showExposureControl).
    - criterion: Show pre/post RGB and Lab cursor readouts in documented scales.
      result: pass
      notes: HistogramData.readout computes sRGB 8-bit + CIE L*a*b* (D65 2 degree) from the bounded sample; InfoInspectorView renders Pre/Post RGB and Lab. Scales are documented in docs/ENGINEERING_GUIDE.md. HistogramTests covers a known red-pixel Lab value and out-of-bounds lookup.
    - criterion: Add waveform, RGB parade, and vectorscope modes while retaining RGB and luminance histogram views.
      result: pass
      notes: HistogramChart.Mode gained waveform/parade/vectorscope cases alongside the existing rgb/luma/red/green/blue cases; all draw from the same bounded sample buffer.
    - criterion: Keep overlays toggleable and ensure measurement coordinates follow crop and zoom.
      result: pass
      notes: showClippingAlerts toggles the canvas overlay. updatePixelReadout maps the cursor point through the canvas navigation transform and layout/virtual image extents (crop + zoom aware) before indexing into the sample buffer.
  checks_run:
    - swift build
    - scripts/ci-tests.sh fast (1263 tests, 0 failures)
    - scripts/ci-tests.sh serial (429 tests, 1 skipped, 0 failures)
    - swift test --filter PreviewAdmissionCoordinatorTests|ThumbnailSwitchLifecycleTests|HistogramTests (post-fix regression check, 0 failures)
    - git diff --check
  findings:
    - "Performance/medium: PreviewMTKView.updateTrackingAreas() now installs a .mouseMoved tracking area unconditionally (previously gated on isWhiteBalanceSampling), and mouseMoved always invoked the cursor-point callback, so every mouse pixel of hover over the canvas updated AppViewModel's @Published pixelReadout/pixelReadoutBefore and broadcast objectWillChange app-wide, even when the Info tab (the only place that reads them) was not visible. Fixed in commit 81cfd45."
  fixes:
    - "Sources/KromoraKit/Views/PreviewView.swift: gate the onCursorPoint closure to only call viewModel.updatePixelReadout when the inspector is presented and the active tab is .info."
  verification_commits:
    - 81cfd45
    - 81cfd4536fadba79a74f298999fe329a44bea9b2
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-27T05:29:56.886Z
  session: 01MUJDDPAXGRIH8IPH
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - professional-polish
  - evaluation-2026-09
created: 2026-09-26T13:56:26.985Z
updated: 2026-09-28T14:41:32.397Z
blockers: []
order: gihu1zbw
board: product
commits:
  - 81cfd4536fadba79a74f298999fe329a44bea9b2
  - 81cfd45
---

## Objective

Make exposure and color evaluation visible through clipping feedback, cursor measurements, and professional histogram scopes.

## Context

The current histogram has RGB and luminance channels but no clipping badges, cursor readouts, or waveform/parade/vectorscope modes.

Derived from §2.1 White balance and tone fundamentals; §9 Viewing, comparison, and proofing ergonomics in `.context/2026-09-22-professional-polish-evaluation.md`. The evaluation is a gap analysis rather than a sequencing decision, so this remains a backlog candidate until product scope is selected.

## Acceptance criteria

- [ ] Show highlight/shadow and per-channel clipping indicators on the image and histogram, with numeric clipped-pixel counts and a way to jump to Exposure.
- [ ] Show pre/post RGB and Lab cursor readouts in documented scales.
- [ ] Add waveform, RGB parade, and vectorscope modes while retaining RGB and luminance histogram views.
- [ ] Keep overlays toggleable and ensure measurement coordinates follow crop and zoom.

## Implementation notes

Preserve the existing non-destructive edit document, shared render graph, macOS 14 minimum, Swift 6 safety, portable package ownership, and zero third-party dependencies. Add focused regression coverage and update relevant product documentation as the feature is implemented.


### Comment — codex @ 2026-09-27T05:19:59.327Z

Implemented sampled clipping feedback, pre/post cursor RGB and Lab readouts, waveform/RGB parade/vectorscope modes, a toggleable canvas alert, and an Exposure shortcut. Documented the measurement scales and bounded-sample counts. Verified with HistogramTests (10 passing), PreviewAdmissionCoordinatorTests (5 passing), and git diff --check. Commit: 6f8135f.

## Agent log

- 2026-09-27T05:29:56.886Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Show highlight/shadow and per-channel clipping indicators on the image and histogram, with numeric clipped-pixel counts and a way to jump to Exposure. (pass) — InfoInspectorView shows highlight/shadow badges and R/G/B clipped counts from HistogramData; PreviewView overlays a toggleable canvas alert; an Exposure link switches to the Light tab and scrolls to the Exposure row (showExposureControl).
- [x] Show pre/post RGB and Lab cursor readouts in documented scales. (pass) — HistogramData.readout computes sRGB 8-bit + CIE L*a*b* (D65 2 degree) from the bounded sample; InfoInspectorView renders Pre/Post RGB and Lab. Scales are documented in docs/ENGINEERING_GUIDE.md. HistogramTests covers a known red-pixel Lab value and out-of-bounds lookup.
- [x] Add waveform, RGB parade, and vectorscope modes while retaining RGB and luminance histogram views. (pass) — HistogramChart.Mode gained waveform/parade/vectorscope cases alongside the existing rgb/luma/red/green/blue cases; all draw from the same bounded sample buffer.
- [x] Keep overlays toggleable and ensure measurement coordinates follow crop and zoom. (pass) — showClippingAlerts toggles the canvas overlay. updatePixelReadout maps the cursor point through the canvas navigation transform and layout/virtual image extents (crop + zoom aware) before indexing into the sample buffer.
Checks run:
- swift build
- scripts/ci-tests.sh fast (1263 tests, 0 failures)
- scripts/ci-tests.sh serial (429 tests, 1 skipped, 0 failures)
- swift test --filter PreviewAdmissionCoordinatorTests|ThumbnailSwitchLifecycleTests|HistogramTests (post-fix regression check, 0 failures)
- git diff --check
Findings:
- Performance/medium: PreviewMTKView.updateTrackingAreas() now installs a .mouseMoved tracking area unconditionally (previously gated on isWhiteBalanceSampling), and mouseMoved always invoked the cursor-point callback, so every mouse pixel of hover over the canvas updated AppViewModel's @Published pixelReadout/pixelReadoutBefore and broadcast objectWillChange app-wide, even when the Info tab (the only place that reads them) was not visible. Fixed in commit 81cfd45.
Fixes:
- Sources/KromoraKit/Views/PreviewView.swift: gate the onCursorPoint closure to only call viewModel.updatePixelReadout when the inspector is presented and the active tab is .info.
Verification commits:
- 81cfd45
- 81cfd4536fadba79a74f298999fe329a44bea9b2
Actor: claude
Resolved model: sonnet
Pickup session: 01MUJDDPAXGRIH8IPH
Summary: Verified clipping alerts, cursor readouts, and waveform/parade/vectorscope scopes; build and full fast+serial suites pass. Applied a localized fix gating the cursor pixel-readout callback to the Info tab to stop unconditional app-wide @Published churn on every canvas hover.

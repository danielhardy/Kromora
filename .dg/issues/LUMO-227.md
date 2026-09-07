---
id: LUMO-227
title: Close the mask overlay 16.7ms display-latency gate with Instruments trace
type: task
status: done
priority: urgent
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - verification
  - epic:masking
  - masking
  - performance
created: 2026-09-04T22:17:26.637Z
updated: 2026-09-07T04:02:55.930Z
order: zkg4lvt7
board: product
blocked_reason: A real AppKit pointer stream is required for the acceptance trace, but the available desktop automation delivered zero pointer events to the capture host; claiming p95/p99 from the synthetic harness would be invalid.
blocked_action: Historical action retired in LUMO-230; the standalone capture wrapper and host are no longer available. Use the in-app overlay path with Instruments if this gate is reopened.
blocked_from_status: claimed
---

## Objective

Determine, with real Instruments trace evidence, whether the transparent Metal sibling overlay
architecture chosen in LUMO-217 can meet the Step 0 acceptance gate (overlay input-to-present p95
under 16.7 ms), or whether the architecture decision needs revisiting.

## Context

LUMO-217 prototyped a transparent Metal sibling (`MaskOverlaySurfaceView`/`MaskOverlayRenderer`)
for pointer-frequency mask overlays and recorded a Release baseline
(`docs/LUMO-217-MASK-OVERLAY-BASELINE-2026-09-04.md`). The main-thread state-update budget passed
(p95 0.020 ms, target < 2 ms), but the end-to-end overlay display latency did not: p95 40.334 ms
against a 16.7 ms target, measured with `MaskOverlayPerformanceBenchmark` under an aggressively
back-to-back synthetic input stream (no inter-frame pacing) rather than a real pointer trace. The
existing persistent-preview direct-display benchmark independently shows a 24-25 ms presentation
cadence on the same host, suggesting part of the gap may be present-cadence/vsync related rather
than specific to the sibling-view approach — but this has not been measured directly.

LUMO-217's own report explicitly declines to claim the display gate as met and calls for this
follow-up before Step 0's performance gate is treated as closed.

## Acceptance criteria

- [ ] Capture an Instruments trace (Points of Interest + Metal System Trace) of the
      `LUMO_MASK_OVERLAY_PROTOTYPE=1` build driven by a **real AppKit pointer stream** (not the
      synthetic back-to-back benchmark loop), on the same reference host/config documented in
      LUMO-217's baseline.
- [ ] Attribute the 40.334 ms p95 gap: identify how much is drawable/vsync presentation cadence
      (compare against the existing ~24-25 ms persistent-preview cadence) vs. sibling-view-specific
      overhead (pipeline setup, command buffer scheduling, `addPresentedHandler` timing, etc).
- [ ] Record updated p95/p99 numbers under the real pointer stream, using the same table format as
      `docs/LUMO-217-MASK-OVERLAY-BASELINE-2026-09-04.md`.
- [ ] State explicitly whether the 16.7 ms gate is met, and if not, whether it is achievable with
      the current sibling-view architecture or requires reconsidering the alternative (an added
      `PreviewSurfaceView` Metal pass) recorded in `ADR-LUMO-217-lumo-217-transparent-metal-sibling-overlay.md`.
- [ ] Update the ADR and baseline doc with the trace findings; do not silently change the
      architecture decision without documenting why.

## Notes

Out of scope: durable mask persistence, new tools, or `EditDocument`/`AppViewModel` changes. This
is a measurement/decision follow-up to LUMO-217, not new product behavior.


### Comment — codex @ 2026-09-04T22:53:09.979Z

Implemented the trace-only follow-up infrastructure: overlay-specific Points of Interest signposts, a Release-only LumoMaskOverlayCapture AppKit host, and scripts/run-lumo-227-capture.sh. Updated the baseline, ADR, and README with the capture procedure and preserved the architecture decision. Verification: targeted Observability/MaskOverlay tests pass; Release LumoMaskOverlayCapture build passes; git diff --check and dg validate pass. Three xctrace runs on the reference host produced diagnostic traces but desktop automation delivered input_events=0/presentations=0, so no real-pointer p95/p99 or cadence attribution was claimed.

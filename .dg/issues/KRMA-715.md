---
id: KRMA-715
title: Smooth out hesitation in slider value animations
type: bug
status: review
priority: medium
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - interaction
  - ui
created: 2026-09-29T16:44:14.772Z
updated: 2026-10-02T04:13:18.348Z
blockers:
  - id: evt_mun4xehs_zc41fz
    type: human
    reason: Live visual reproduction is blocked because the existing Kromora.app process holds the library package lock; the test instance cannot open that package, and the user report does not identify the slider or transition to exercise.
    action: Quit the currently running Kromora.app and provide the affected slider plus the action/transition that shows the hesitation so I can reproduce and visually verify it.
    created_at: 2026-09-29T20:34:39.136Z
    resolved_at: 2026-09-29T23:19:24.783Z
    resolved_by: web
  - id: evt_munb0und_t3k4jk
    type: human
    reason: The code path fix and deterministic tests are complete, but the required live reproduction and visual verification cannot be completed because no affected slider or transition is identified and the running app may hold the package lock.
    action: Quit the running Kromora.app and provide the affected slider plus the exact action or selection transition that shows the hesitation, including source and target values if known.
    created_at: 2026-09-29T23:25:17.737Z
    resolved_at: 2026-09-29T23:27:54.481Z
    resolved_by: web
  - id: evt_munbfx0x_izmaw4
    type: human
    reason: The focused tests pass, but live visual verification of the clarified Edit-view photo-selection transition is blocked by a visible macOS Terminal media-library permission prompt covering Kromora.
    action: Dismiss the open Terminal media-library permission prompt using your preferred choice, then bring Kromora to the foreground in Edit view so the unedited-to-edited image transition can be visually checked.
    created_at: 2026-09-29T23:37:00.657Z
order: zh
board: product
blocked_reason: The focused tests pass, but live visual verification of the clarified Edit-view photo-selection transition is blocked by a visible macOS Terminal media-library permission prompt covering Kromora.
blocked_action: Dismiss the open Terminal media-library permission prompt using your preferred choice, then bring Kromora to the foreground in Edit view so the unedited-to-edited image transition can be visually checked.
blocked_from_status: ready
---

## Objective

Find and fix the subtle pause or stutter in slider value animations so the knob and filled track move smoothly and consistently for the full transition.

## User report

There is a subtle hesitation in the animation on the sliders: motion starts, stops briefly, then continues. The motion should stay smooth and consistent throughout the transition. The exact trigger and affected slider have not yet been specified; reproduce and record them before settling on a cause.

## Context

The app uses `NeutralOriginSlider`, an AppKit-backed slider shared by many inspector controls. Its `Coordinator.present(_:on:animated:)` performs programmatic value animation, and `updateNSView` can request presentation again as SwiftUI updates the representable. Investigate whether repeated target updates, cancellation/restart behavior, scheduling cadence, layout or redraw work, or another interaction is interrupting progress. These are investigation leads, not an assumed root cause.

KRMA-700 and KRMA-713 concern loss of sharpness in the photo preview during adjustment drags. Keep this issue focused on the slider control motion; connect the work only if investigation shows a shared cause.

## Acceptance criteria

- [ ] Reproduce the hesitation in the running macOS app and record the trigger, affected sliders, source and target values, and whether it occurs on selection changes, programmatic updates, drag interaction, or another transition.
- [ ] Identify and document the root cause in the control-update, animation, scheduling, redraw, or layout path.
- [ ] Make the slider knob and fill progress smoothly and continuously for the full transition, without visible pauses, restarts, backwards motion, or jumps when state updates arrive during animation.
- [ ] Keep the slider synchronized with the latest bound value when a transition is superseded, and ensure canceled or stale animation work cannot overwrite a newer value.
- [ ] Preserve direct pointer tracking, keyboard adjustments, accessibility values, and correct slider behavior when changing the selected photo; an animation must not fight active user input.
- [ ] Add focused regression coverage for the diagnosed transition and for interruption/superseding updates, using deterministic timing or a controllable animation driver where practical.
- [ ] Visually verify representative inspector sliders in the running app across the reproduced transition and record the procedure and result.
- [ ] Keep the change scoped to slider value animation unless the root cause requires a small shared fix; do not bundle unrelated preview-render quality work.

## Investigation notes

Start at `Sources/KromoraKit/Views/NeutralOriginSlider.swift`, especially `updateNSView`, `Coordinator.present`, and the animation cancellation/update path. Compare the slider thumb and fill together. Distinguish a pause in the control animation from delayed image-preview rendering during a drag.


### Comment — codex @ 2026-09-29T23:25:12.781Z

Implemented velocity-preserving retargeting for in-flight slider value animations. Changing bound targets no longer cancels and restarts the 380 ms animation; the Hermite segment preserves the current value and velocity, and pointer tracking/immediate updates still cancel safely. Added deterministic curve regression coverage. Verified with swift test --filter NeutralOriginSliderTests (23 passed) and git diff --check. The live reproduction and visual verification remain pending because the issue does not identify the slider or transition to exercise; the existing Kromora process is running. Commit: 484d073.


## Human -- 2026-09-29 5:26PM MT 

This effects all sliders. The easiest way to reproduce it is to have image A with no edits and Image B with edits (example max exposure). When you move between while in edit view you can see the sliders start/stop/continue... it is very very fast but it should be ultra smooth


### Comment — codex @ 2026-09-29T23:37:00.440Z

The clarified reproduction is selection changes in Edit view from an unedited image to an edited image; the report says the behavior affects all sliders and gives max Exposure as an example. The root cause was repeated target updates restarting the 380 ms AppKit animation from its current value. Commit 484d073 retargets the active curve with a cubic Hermite segment that preserves position and velocity. Verification: swift test --filter NeutralOriginSliderTests (23 passed), git diff --check. I could not complete live visual verification: a macOS permission prompt for Terminal is covering the app and intercepting interaction. Exact photo identity and Exposure target value remain unspecified.


### Comment — claude @ 2026-10-02T02:08:13.884Z

Follow-up filed as KRMA-755 (stored edits are published only after source preparation, about 650 ms after the image) and KRMA-756 (make the photo-switch slider transition a single continuous move, with the live visual verification this ticket still needs). The velocity-preserving retargeting here is still correct; the remaining hesitation comes from the document arriving in two steps about a second apart, which is what those tickets address.


### Comment — codex @ 2026-10-02T04:13:18.347Z

KRMA-756 implementation update (commit 8b8c59e): the inspector now holds each slider's outgoing presentation and accessibility readout while the newly selected photo's stored document is pending, then animates directly to the incoming document. Deterministic tests cover the hold-to-target transition and keyboard interruption; focused tests and fast/serial lanes pass. Release visual verification is still pending because the currently open Kromora.app owns the library package lock. The library contains a reproducible pair: DSC03843.ARW at +0.00 EV to DSC01019.ARW at +1.21 EV and +10 Contrast.

---
id: KRMA-500
title: "Crop inspector: match slider label style and double-click reset"
type: task
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Crop straighten / perspective labels match caption-sized resettable labels used in Light/Color.
      result: pass
      notes: Straighten, Vertical, Horizontal use ResettableAdjustmentLabel (.caption, secondary).
    - criterion: Double-click on Straighten, Vertical, and Horizontal labels resets that value to neutral and refreshes the preview.
      result: pass
      notes: Reset closures in InfoInspectorView call setCropStraightenAngle(0)/setCropVerticalPerspective(0)/setCropHorizontalPerspective(0), which schedule the interactive preview. Verified by code inspection; no dedicated UI test.
    - criterion: Crop geometry sliders use NeutralOriginSlider and visually match other Edit sliders.
      result: pass
      notes: "All three sliders migrated with neutral: 0 and matching accessibility title/readout, same pattern as EffectsInspectorView."
    - criterion: Accessibility reset action still works without a mouse.
      result: pass
      notes: Label provides the named action; sliders also add Reset to neutral, consistent with other inspectors.
    - criterion: scripts/ci-tests.sh fast and serial pass.
      result: pass
      notes: "fast: 1107 tests run; serial: 403 executed, 1 skipped (documented RAW fixture), 0 failures."
  checks_run:
    - swift build
    - scripts/ci-tests.sh fast
    - scripts/ci-tests.sh serial
    - manual diff review of CropInspectorView.swift and InfoInspectorView.swift
  findings:
    - "info: value readouts next to the labels keep the default body font while other inspectors use caption monospaced readouts; cosmetic, allowed by the issue, no ticket created."
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-21T01:54:27.174Z
  session: 01MUALBBV8O19NSJV6
creation_provenance:
  runner: cursor
  model: unknown
  actor: cursor
labels:
  - crop
  - ui
  - ux
created: 2026-09-21T01:33:29.982Z
updated: 2026-09-21T01:54:27.175Z
order: a0
board: product
---

## Objective

Crop-mode adjustment rows use the same label typography, double-click-to-reset behaviour, and slider chrome as Light / Color / Effects — not larger headlines and stock SwiftUI sliders.

## Context

User report (2026-09-20): in crop mode the labels are larger than elsewhere; they also lack double-click to reset and should have it. Slider visual style should match the rest of the app.

### Today vs the rest of Edit

| | Crop (`CropInspectorView`) | Light / Color / etc. |
| --- | --- | --- |
| Per-control label | `Text(…).font(.headline)` (Straighten, Vertical, Horizontal, section titles) | `ResettableAdjustmentLabel` → `.font(.caption)` + secondary colour |
| Double-click reset | Missing | `ResettableAdjustmentLabel` + accessibility action |
| Slider | Stock `SwiftUI.Slider` | `NeutralOriginSlider` / `TemperatureSlider` (custom thumb, coloured tracks where applicable, neutral-origin fill) |

Straighten and perspective already have `onBeginInteraction` / `onEndInteraction` and VM setters (`setCropStraightenAngle`, `setCropVerticalPerspective`, `setCropHorizontalPerspective`). Reset of individual geometry fields can call those with identity (0) or go through existing `resetCrop` / draft helpers — prefer per-control reset to neutral for that control only (match other inspectors), not a full crop Reset unless double-click is on a section header that means “reset all geometry.”

Related: KRMA-499 (global thumb size — crop should use the shared slider so it picks that up), KRMA-487 (perspective behaviour), KRMA-488 (track vibrancy on NeutralOriginSlider).

## Requirements

1. **Label style** — Straighten, Vertical, Horizontal (and any other per-slider labels in the crop inspector) use `ResettableAdjustmentLabel` (or identical `.caption` / secondary styling). Section headers like “Aspect” / “Rotate and Flip” / “Perspective” may stay slightly stronger if needed for grouping, but must not look like oversized body headlines next to Light’s caption rows; prefer matching other inspectors’ disclosure/section patterns.
2. **Double-click reset** — Double-clicking those labels resets that control to neutral (straighten `0°`, perspective `0`, etc.) and updates the live preview the same way a slider change would. VoiceOver keeps the named accessibility reset action (already part of `ResettableAdjustmentLabel`).
3. **Slider chrome** — Replace crop’s stock `Slider`s with `NeutralOriginSlider` (neutral at 0 for straighten ±45° and perspective ±max), including readout alignment consistent with other rows (value on the trailing side of the label row is fine).
4. Behaviour of drag interaction, Done/Cancel, and full **Reset** button at the bottom of the crop inspector unchanged except that per-control double-click reset is additive.
5. Do not invent a parallel label component — reuse `ResettableAdjustmentLabel`.

## Acceptance criteria

- [ ] Crop straighten / perspective labels match caption-sized resettable labels used in Light/Color.
- [ ] Double-click on Straighten, Vertical, and Horizontal labels resets that value to neutral and refreshes the preview.
- [ ] Crop geometry sliders use `NeutralOriginSlider` and visually match other Edit sliders (thumb/track family).
- [ ] Accessibility reset action still works without a mouse.
- [ ] `scripts/ci-tests.sh fast` and `serial` pass; optional focused test that crop reset callbacks fire on the label seam if cheap.

## Implementation notes

- `Sources/KromoraKit/Views/CropInspectorView.swift` — `straightenSection`, `perspectiveSlider`.
- Wire `reset:` closures from `InfoInspectorView` into view-model one-liners that zero the draft field and call `scheduleInteractivePreview` / settled path as appropriate.
- Related: KRMA-499, KRMA-487, KRMA-488.

### Comment — codex @ 2026-09-21T01:51:59.419Z

Implemented crop inspector parity: Straighten, Vertical, and Horizontal now use ResettableAdjustmentLabel with double-click and accessibility reset actions; all crop geometry controls use NeutralOriginSlider centered at neutral with aligned readouts. Resets route through the existing crop setters so draft state and interactive preview updates remain unchanged. Verification: scripts/ci-tests.sh fast (1,107 passed), scripts/ci-tests.sh serial (403 passed, 1 documented RAW-fixture skip), swift test --filter CropWorkflowTests (14 passed), swift build, dg validate.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-21T01:54:27.174Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Crop straighten / perspective labels match caption-sized resettable labels used in Light/Color. (pass) — Straighten, Vertical, Horizontal use ResettableAdjustmentLabel (.caption, secondary).
- [x] Double-click on Straighten, Vertical, and Horizontal labels resets that value to neutral and refreshes the preview. (pass) — Reset closures in InfoInspectorView call setCropStraightenAngle(0)/setCropVerticalPerspective(0)/setCropHorizontalPerspective(0), which schedule the interactive preview. Verified by code inspection; no dedicated UI test.
- [x] Crop geometry sliders use NeutralOriginSlider and visually match other Edit sliders. (pass) — All three sliders migrated with neutral: 0 and matching accessibility title/readout, same pattern as EffectsInspectorView.
- [x] Accessibility reset action still works without a mouse. (pass) — Label provides the named action; sliders also add Reset to neutral, consistent with other inspectors.
- [x] scripts/ci-tests.sh fast and serial pass. (pass) — fast: 1107 tests run; serial: 403 executed, 1 skipped (documented RAW fixture), 0 failures.
Checks run:
- swift build
- scripts/ci-tests.sh fast
- scripts/ci-tests.sh serial
- manual diff review of CropInspectorView.swift and InfoInspectorView.swift
Findings:
- info: value readouts next to the labels keep the default body font while other inspectors use caption monospaced readouts; cosmetic, allowed by the issue, no ticket created.
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MUALBBV8O19NSJV6
Summary: Verified: crop inspector labels use ResettableAdjustmentLabel with double-click/accessibility reset via existing setters; all geometry sliders use NeutralOriginSlider. Fast and serial CI lanes pass.

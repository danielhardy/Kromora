---
id: KRMA-655
title: Add animated zebra overlay for clipped highlights
type: feature
status: backlog
priority: medium
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - product
  - ui
  - clipping
created: 2026-09-27T16:16:12.867Z
updated: 2026-09-27T16:16:38.997Z
order: zzzzx
board: product
---

## Objective

Add a toggleable zebra overlay that marks clipped highlight regions on the photo with animated diagonal dashed lines, similar to the exposure zebras shown in Sony cameras.

## Context

The current canvas clipping feedback reports total highlight and shadow counts in a small badge. It does not show where clipped highlights occur. The attached camera-screen reference shows a bright lamp area marked by diagonal zebra stripes; the requested behavior is a moving dashed pattern over the clipped image regions.

Relevant existing code:

- `Sources/KromoraKit/Views/PreviewView.swift` — displays the current clipping alert overlay over the canvas.
- `Sources/KromoraKit/Models/KromoraSettings.swift` — persists the `showClippingAlerts` preference.
- `Sources/KromoraKit/Models/Histogram.swift` — computes histogram bins and clipping counts from the rendered preview.
- `Sources/KromoraKit/Views/InfoInspectorView.swift` — displays numeric clipping counts.
- `Tests/KromoraKitTests/HistogramTests.swift` and Preview/canvas overlay tests — likely locations for focused coverage.

KRMA-616 includes focus peaking for focus evidence. This ticket is specifically for exposure zebras that reveal clipped image tones; do not treat these as the same overlay.

## Acceptance criteria

- [ ] Draw animated diagonal dashed zebra marks only over clipped highlight regions of the current rendered photo, so the user can see where highlights have reached the display clipping ceiling.
- [ ] Keep the pattern aligned with the displayed image through crop, zoom, pan, and preview updates; it must not cover the surrounding inspector or window chrome.
- [ ] Make the zebra overlay toggleable through the existing clipping-alert control or an equally clear control, and keep the numeric histogram clipping counts available.
- [ ] Keep the overlay presentation-only: it does not change rendered pixels, saved edits, exports, or editing hit testing.
- [ ] Keep animation lightweight and respect the system Reduce Motion setting.
- [ ] Add focused tests for identifying/displaying clipped regions and for overlay visibility/state, and update relevant documentation.

## Implementation notes

Use the rendered image representation and clipping definition consistently with the histogram; do not infer positions from aggregate counts alone. Preserve the existing highlight/shadow count behavior. Keep the overlay coordinate mapping correct for the displayed crop and canvas transform, and preserve macOS 14, Swift 6, and zero third-party dependencies.

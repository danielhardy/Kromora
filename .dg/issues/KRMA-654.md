---
id: KRMA-654
title: Remove histogram pixel readout and Exposure shortcut
type: task
status: backlog
priority: medium
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - product
  - ui
  - cleanup
created: 2026-09-27T15:57:17.051Z
updated: 2026-09-27T15:58:12.057Z
order: zzzzv
board: product
---

## Objective

Remove the cursor pixel readout shown beneath the Info histogram (Pre/Post RGB and Lab values, plus its hover hint) and remove the “Exposure” shortcut link. Remove code that exists only to support these two UI elements.

## Context

The pixel readout is rendered in the histogram section of `Sources/KromoraKit/Views/InfoInspectorView.swift`. `PreviewView` forwards canvas cursor coordinates to `AppViewModel.updatePixelReadout`, which samples the bounded rendered histogram and publishes `pixelReadout` / `pixelReadoutBefore`. `HistogramData.readout` in `Sources/KromoraKit/Models/Histogram.swift` converts the sampled RGB value to Lab.

The “Exposure” link calls `AppViewModel.showExposureControl()`, which changes the selected inspector tab and increments `exposureScrollRequest`; `LightInspectorView` observes that request to scroll to its Exposure row. The exposure adjustment itself is a core editing control and must remain.

Relevant files include:

- `Sources/KromoraKit/Views/InfoInspectorView.swift`
- `Sources/KromoraKit/Views/PreviewView.swift`
- `Sources/KromoraKit/Models/Histogram.swift`
- `Sources/KromoraKit/ViewModels/AppViewModel.swift`
- `Sources/KromoraKit/Views/LightInspectorView.swift`
- `Tests/KromoraKitTests/HistogramTests.swift`
- `docs/ENGINEERING_GUIDE.md`

## Acceptance criteria

- [ ] Remove the Info histogram pixel readout row, including Pre/Post RGB, Lab, and the “Hover over photo for pixel readout” hint. Remove the dedicated canvas-hover sampling callback and view-model state/method if repository-wide reference checks confirm they have no other use.
- [ ] Remove the “Exposure” link from the histogram and its dedicated routing/scroll-request plumbing if it has no other callers. Keep the Exposure control, its normal navigation, and all exposure editing behavior.
- [ ] Remove pixel-readout-only model code and tests, including `PixelReadout` and RGB-to-Lab conversion, when no remaining feature depends on them.
- [ ] Retain histogram plotting, channel selection, clipping counts, and spatial scopes. In particular, waveform, parade, and vectorscope currently read the sampled RGB buffer; keep any sample data or processing they still require.
- [ ] Update documentation that describes the removed cursor readout or Exposure shortcut while preserving accurate histogram and exposure documentation.
- [ ] Search for all removed symbols and UI labels to confirm there are no dangling references, then run the relevant build and focused tests.

## Implementation notes

Inspect current callers before deleting shared plumbing. `HistogramData.samples` is not exclusively for cursor sampling: `HistogramChart` uses it for waveform, parade, and vectorscope rendering. Remove only behavior and data processing that are no longer used after the UI changes. Do not alter unrelated pre-existing working-tree changes.

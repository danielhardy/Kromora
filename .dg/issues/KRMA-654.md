---
id: KRMA-654
title: Remove histogram pixel readout and Exposure shortcut
type: task
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Remove Info histogram pixel readout row (Pre/Post RGB, Lab, hover hint) and dedicated cursor sampling callback/view-model state
      result: pass
      notes: HStack readout block, updatePixelReadout, pixelReadout/pixelReadoutBefore, PreviewMTKView.onCursorPoint, and PreviewView's onCursorPoint wiring are all removed; grep confirms zero remaining references.
    - criterion: Remove Exposure link and its dedicated routing/scroll-request plumbing while keeping Exposure control and normal navigation
      result: pass
      notes: Button('Exposure')/showExposureControl()/exposureScrollRequest/ScrollViewReader scroll-to-exposure removed from LightInspectorView; LightControl.exposure row and normal Light tab navigation remain intact.
    - criterion: Remove pixel-readout-only model code and tests (PixelReadout, RGB-to-Lab conversion) when unused elsewhere
      result: pass
      notes: PixelReadout struct and HistogramData.readout() deleted from Histogram.swift; corresponding HistogramTests assertions removed; no remaining references repo-wide.
    - criterion: Retain histogram plotting, channel selection, clipping counts, and spatial scopes; keep sample data waveform/parade/vectorscope still need
      result: pass
      notes: HistogramData.samples and its waveform/parade/vectorscope consumers untouched; clipping count row (R/G/B) retained in InfoInspectorView.
    - criterion: Update documentation describing removed cursor readout / Exposure shortcut while keeping accurate histogram/exposure docs
      result: pass
      notes: "docs/ENGINEERING_GUIDE.md updated: removed hover-sampling and Exposure-shortcut description, added note that Exposure remains in the Light inspector."
    - criterion: Search for dangling references to removed symbols/labels; run relevant build and focused tests
      result: pass
      notes: Verifier re-ran repo-wide grep for pixelReadout/PixelReadout/originalHistogram/exposureScrollRequest/showExposureControl/onCursorPoint/updatePixelReadout/publishAdmissionOriginalHistogram — zero hits. swift build succeeded; HistogramTests (10), PreviewAdmissionCoordinatorTests (5), PackageSettingsTests (4) all passed.
  checks_run:
    - swift build
    - swift test --filter 'HistogramTests|PreviewAdmissionCoordinatorTests' (15 passed)
    - swift test --filter 'PackageSettingsTests' (4 passed, confirms zero Swift 6 concurrency escape hatches introduced)
    - grep -rn for all removed symbols/labels across Sources and Tests (no dangling references)
  findings: []
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-27T17:21:12.063Z
  session: 01MUK33FJQ0DGBV304
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - product
  - ui
  - cleanup
created: 2026-09-27T15:57:17.051Z
updated: 2026-09-27T17:21:12.065Z
blockers: []
order: a0
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


### Comment — codex @ 2026-09-27T17:19:52.933Z

Removed the histogram cursor readout and Exposure shortcut, including dedicated sampling and routing state. Preserved RGB samples for waveform/parade/vectorscope and white balance sampling. Updated engineering guidance. Verified with swift build and focused HistogramTests + PreviewAdmissionCoordinatorTests (15 passed). Commit: a766b8d.

## Agent log

- 2026-09-27T17:21:12.063Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Remove Info histogram pixel readout row (Pre/Post RGB, Lab, hover hint) and dedicated cursor sampling callback/view-model state (pass) — HStack readout block, updatePixelReadout, pixelReadout/pixelReadoutBefore, PreviewMTKView.onCursorPoint, and PreviewView's onCursorPoint wiring are all removed; grep confirms zero remaining references.
- [x] Remove Exposure link and its dedicated routing/scroll-request plumbing while keeping Exposure control and normal navigation (pass) — Button('Exposure')/showExposureControl()/exposureScrollRequest/ScrollViewReader scroll-to-exposure removed from LightInspectorView; LightControl.exposure row and normal Light tab navigation remain intact.
- [x] Remove pixel-readout-only model code and tests (PixelReadout, RGB-to-Lab conversion) when unused elsewhere (pass) — PixelReadout struct and HistogramData.readout() deleted from Histogram.swift; corresponding HistogramTests assertions removed; no remaining references repo-wide.
- [x] Retain histogram plotting, channel selection, clipping counts, and spatial scopes; keep sample data waveform/parade/vectorscope still need (pass) — HistogramData.samples and its waveform/parade/vectorscope consumers untouched; clipping count row (R/G/B) retained in InfoInspectorView.
- [x] Update documentation describing removed cursor readout / Exposure shortcut while keeping accurate histogram/exposure docs (pass) — docs/ENGINEERING_GUIDE.md updated: removed hover-sampling and Exposure-shortcut description, added note that Exposure remains in the Light inspector.
- [x] Search for dangling references to removed symbols/labels; run relevant build and focused tests (pass) — Verifier re-ran repo-wide grep for pixelReadout/PixelReadout/originalHistogram/exposureScrollRequest/showExposureControl/onCursorPoint/updatePixelReadout/publishAdmissionOriginalHistogram — zero hits. swift build succeeded; HistogramTests (10), PreviewAdmissionCoordinatorTests (5), PackageSettingsTests (4) all passed.
Checks run:
- swift build
- swift test --filter 'HistogramTests|PreviewAdmissionCoordinatorTests' (15 passed)
- swift test --filter 'PackageSettingsTests' (4 passed, confirms zero Swift 6 concurrency escape hatches introduced)
- grep -rn for all removed symbols/labels across Sources and Tests (no dangling references)
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MUK33FJQ0DGBV304

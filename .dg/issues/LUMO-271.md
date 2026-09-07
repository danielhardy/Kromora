---
id: LUMO-271
title: Vignette produces rectangular GPU artifacts after repeated zoom
type: bug
status: ready
priority: high
labels:
  - effects
  - rendering
  - preview
  - metal
created: 2026-09-07T01:44:45.580Z
updated: 2026-09-07T04:02:57.674Z
order: a0
board: product
---

## Objective

Ensure a nonzero global vignette remains a single smooth full-frame effect while zooming a large
RAW preview. The canvas must not show rectangular regions with different vignette strength or
stale pixels.

## Context

Observed on 2026-09-06 with the attached screenshot while editing a 42MP RAW in the Develop tab
(screenshot metadata shows `DSC04485.ARW`, 7952×5304). Reproduction sequence:

1. Open the RAW and enter Develop.
2. Set Vignette Amount to approximately `15.947309`.
3. Zoom in and out repeatedly.
4. Observe hard rectangular tonal/vignette boundaries inside the photo.

Expected: one smooth, symmetric vignette over the complete current image frame, invariant in
appearance apart from magnification and source-detail changes.

Actual: rectangular subregions appear to have different processing, as if the vignette or a prior
preview frame were evaluated/presented in tiles. The amount is probably not numerically special;
any nonzero amount enables the vignette stage, while zero bypasses it.

Code evaluation indicates the durable pipeline applies vignette once, after crop/LUT, in
`Sources/LumoKit/Models/RenderPipeline.swift:115-121`. The effect is implemented by a custom
`CIKernel` using global image-extent geometry (`RenderPipeline.swift:541-568, 764-798`). Zoom can
change the resolution-pyramid level and then transform/crop the completed GPU image for display
(`ResolutionPlanner.swift:82-118`, `PreviewSurface.swift:330-348`). This points to a tiled native-
resolution evaluation or stale/partial Metal presentation path rather than duplicate persisted
vignette state.

First diagnostic: compare the canvas after reproduction with a full-resolution PNG export. A clean
export isolates the defect to preview presentation; matching rectangular artifacts in the export
implicate the custom vignette kernel or large-image render path.

## Acceptance criteria

- [ ] Reproduce the issue with a nonzero vignette on a large RAW, including repeated zoom-in/zoom-
      out transitions across preview resolution levels.
- [ ] Preview shows one continuous full-frame vignette with no rectangular seams, stale regions, or
      mixed-strength subareas at fit, zoomed, and zoomed-back-out states.
- [ ] The vignette is applied exactly once in the shared render pipeline and remains consistent
      between preview and full-resolution export.
- [ ] Add a regression test covering nonzero vignette plus large/tiled rendering and zoom-level
      transitions; use a real Metal presentation test where the defect requires GPU evaluation.
- [ ] Existing effects, preview, render-cache, and export tests pass without weakening assertions.

## Implementation notes

- Preserve the post-crop/output-frame semantics of vignette.
- Do not solve the symptom by making a nonzero vignette neutral or by disabling zoom-driven detail
  upgrades.
- Inspect both the custom `CIKernel` tile behavior and the completed-texture-to-drawable path before
  changing cache keys or preview lifecycle state.
- The existing unit coverage tests vignette math and zoom presentation separately, but does not
  cover their combined large-Metal path.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

---
id: KRMA-271
title: Vignette produces rectangular GPU artifacts after repeated zoom
type: bug
status: done
priority: high
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Reproduce the issue with a nonzero vignette on a large RAW, including repeated zoom-in/zoom-out transitions across preview resolution levels.
      result: pass
    - criterion: Preview shows one continuous full-frame vignette with no rectangular seams, stale regions, or mixed-strength subareas at fit, zoomed, and zoomed-back-out states.
      result: pass
    - criterion: The vignette is applied exactly once in the shared render pipeline and remains consistent between preview and full-resolution export.
      result: pass
    - criterion: Add a regression test covering nonzero vignette plus large/tiled rendering and zoom-level transitions; use a real Metal presentation test where the defect requires GPU evaluation.
      result: pass
    - criterion: Existing effects, preview, render-cache, and export tests pass without weakening assertions.
      result: pass
  checks_run:
    - swift build - passed
    - swift build -c release - passed
    - swift test - 931 executed, 42 skipped, 0 failures
    - swift test --filter testLargeVignetteCompletedTextureHasNoZoomTileSeams - 1 passed
    - git diff --check - clean
    - git status --porcelain - clean aside from DispatchGraph bookkeeping
    - dg validate - OK with pre-existing unrelated pickup-runner model warning
  findings:
    - grainKernel (RenderPipeline.swift:804) uses the same sampler-based, position-dependent pattern (samplerCoord(image) + extent geometry) that just caused the vignette seam bug; grain may exhibit the same tiled-Metal artifact on large images at deep zoom. Filed as LUMO-277 (child, verification label) rather than fixed here since it is outside this tickets acceptance criteria and needs its own regression test.
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-07T15:02:02.543Z
  session: 01MTRD7J4CBJFV7CFG
labels:
  - effects
  - rendering
  - preview
  - metal
created: 2026-09-07T01:44:45.580Z
updated: 2026-09-10T12:53:52.356Z
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

### Comment — codex @ 2026-09-07T14:57:45.371Z

Implemented in commit 6f14b45. Replaced the pointwise vignette sampler kernel/ROI path with a destination-coordinate CIColorKernel so large tiled GPU evaluation uses stable full-frame geometry. Added a large completed-texture repeated-zoom seam regression plus an opt-in real CAMetalDrawable presentation regression. Verification: swift test — 931 passed, 42 expected skips; swift build -c release; git diff --check.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-07T15:02:02.544Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Reproduce the issue with a nonzero vignette on a large RAW, including repeated zoom-in/zoom-out transitions across preview resolution levels. (pass)
- [x] Preview shows one continuous full-frame vignette with no rectangular seams, stale regions, or mixed-strength subareas at fit, zoomed, and zoomed-back-out states. (pass)
- [x] The vignette is applied exactly once in the shared render pipeline and remains consistent between preview and full-resolution export. (pass)
- [x] Add a regression test covering nonzero vignette plus large/tiled rendering and zoom-level transitions; use a real Metal presentation test where the defect requires GPU evaluation. (pass)
- [x] Existing effects, preview, render-cache, and export tests pass without weakening assertions. (pass)
Checks run:
- swift build - passed
- swift build -c release - passed
- swift test - 931 executed, 42 skipped, 0 failures
- swift test --filter testLargeVignetteCompletedTextureHasNoZoomTileSeams - 1 passed
- git diff --check - clean
- git status --porcelain - clean aside from DispatchGraph bookkeeping
- dg validate - OK with pre-existing unrelated pickup-runner model warning
Findings:
- grainKernel (RenderPipeline.swift:804) uses the same sampler-based, position-dependent pattern (samplerCoord(image) + extent geometry) that just caused the vignette seam bug; grain may exhibit the same tiled-Metal artifact on large images at deep zoom. Filed as KRMA-277 (child, verification label) rather than fixed here since it is outside this tickets acceptance criteria and needs its own regression test.
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MTRD7J4CBJFV7CFG
Summary: Verified: CIColorKernel destCoord() fix eliminates the tiled vignette seam; full suite (931 tests) and release build pass. Filed KRMA-277 as a non-blocking follow-up: grainKernel shares the same samplerCoord pattern and may need the same treatment.

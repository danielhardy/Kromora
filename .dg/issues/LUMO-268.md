---
id: LUMO-268
title: Cap preview-quality mask working resolution
type: task
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Decision recorded with measurements (cap threshold/scope, or reasons it stays uncapped)
      result: pass
    - criterion: Side-by-side capped vs full-res comparison test within tolerance on feathered and hard-edge fixtures
      result: pass
    - criterion: Export/.render path provably untouched
      result: pass
  checks_run:
    - swift build — clean, zero diagnostics, Swift 6 strict concurrency intact
    - swift test --filter LocalMaskRenderingTests — 33 executed, 1 skipped (opt-in benchmark), 0 failures
    - scripts/ci-tests.sh fast — 1 unrelated failure (see findings)
    - git bisect of LUTWorkflowTests failure across 1731b84..bca796a — isolated to LUMO-308 (b01de9d), not LUMO-268
  findings:
    - "Re-verified the prior verifier's fix (commit 1731b84): rasterImage() previously rescanned mask.values with allSatisfy on every render frame, including export, to choose nearest/linear sampling; now reads a cached NormalizedMask.isBinary computed once at construction. Confirmed correct and covered."
    - "Cap correctly scoped: only .semantic component sources at MaskQuality.preview (RenderQuality .thumbnail/.interactive/.preview) go through SemanticMaskPreviewResolution.targetSize; .fullResolution/.export (MaskQuality.render) and non-semantic descriptors (.brush/.linear/.radial) stay at full extent. Confirmed the interactive canvas settles on RenderQuality.preview (PreviewCoordinator), which is the tier that actually hits the 1:1-zoom cliff described in the ticket, and that RenderQuality.fullResolution has no live production call site other than an unused makeCGImage(scale:) overload."
    - "Found an unrelated, pre-existing regression: LUTWorkflowTests.testExternalImportCanBeSelectedByIDAndSendsItThroughPreviewRequest fails on current main. Bisected to LUMO-308 (commit b01de9d), well outside LUMO-268's commit range (a964546, 1731b84). Filed as backlog child LUMO-319 (parent LUMO-268, label verification) rather than fixed here — root-causing it is outside a localized fix and the intervening 30+ commits are unrelated to mask rendering."
  fixes: []
  verification_commits:
    - bca796a
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-09T14:18:27.532Z
  session: 01MTU699ZHGJT86UDB
labels:
  - masking
  - performance
created: 2026-09-07T01:14:46.878Z
updated: 2026-09-09T14:18:27.534Z
order: a0
board: product
commits:
  - bca796a
---

## Objective

Determine whether `.preview`-quality semantic masks can resolve at a capped working
resolution instead of the full render extent, letting Core Image upscale the smooth mask to
display. This is the only lever that avoids 60M-element work on zoomed-in previews entirely
rather than merely accelerating it.

## Context

The interactive preview correctly renders at planned display resolution (~2MP typical), so the
common case is already bounded. The cliff is 1:1 zoom on a 60MP photo: the resolver upscales
the 768×512 seed to the full extent in Swift (tens of seconds in debug, seconds in release),
and the result can never be cached (240MB vs 64MB budget). But a person mask is almost
everywhere low-frequency — its information content is the 768×512 seed — and GPU upscaling of
a smooth alpha mask is visually free.

## Work (measure-first)

- Prototype: clamp `targetSize` for `.preview`-quality semantic resolves to a working cap
  (candidate: 4MP / 2560px long edge) in `CoordinatorLocalMaskResolver` or
  `resolvedLocalMasks`, leaving `.render`/export untouched at full resolution.
- Validate visually, not just numerically: feathered edges, hair-level person boundaries at
  1:1, and hard-edged definitions (density 1, no feather, inverted) must show no visible
  regression vs full-res masks. If hard edges regress, scope the cap to feathered/soft
  definitions only.
- Measure: wall time for a 1:1 preview render with a person layer before/after, debug and
  release.

## Acceptance criteria

- [ ] Decision recorded with measurements: either the cap lands with the chosen threshold
      and scope, or the ticket documents why full-res preview masks stay (with numbers).
- [ ] If it lands: side-by-side render comparison test (capped vs full-res) within stated
      tolerance on feathered and hard-edge fixtures.
- [ ] Export/`.render` path provably untouched (existing render tests).


### Comment — codex @ 2026-09-09T14:06:24.481Z

Implemented and verified in commit a964546. Decision: land the preview semantic-mask working-resolution cap at min(4,000,000 pixels, 2,560px long edge), scoped to preview-tier semantic components; Core Image upscales the resulting smooth raster at display time. Full-resolution and export/render-quality semantic paths remain uncapped. Debug benchmark on the 6000x4000 1:1 fixture, 3 iterations: capped 2,476.344 ms vs full-res 14,804.247 ms (5.98x). Release: capped 1,305.340 ms vs full-res 7,694.259 ms (5.89x). The side-by-side capped/full comparison passed for soft/feathered and binary hard-edge/inverted fixtures (RGBA8 tolerance <=5 and <=1 respectively). Preview-vs-export target-size coverage passed, and the existing RenderEngineTests passed 29/29 executed with 3 expected RAW skips. The focused LocalMaskRenderingTests passed 33/33.

## Agent log

- 2026-09-09T14:18:27.532Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Decision recorded with measurements (cap threshold/scope, or reasons it stays uncapped) (pass)
- [x] Side-by-side capped vs full-res comparison test within tolerance on feathered and hard-edge fixtures (pass)
- [x] Export/.render path provably untouched (pass)
Checks run:
- swift build — clean, zero diagnostics, Swift 6 strict concurrency intact
- swift test --filter LocalMaskRenderingTests — 33 executed, 1 skipped (opt-in benchmark), 0 failures
- scripts/ci-tests.sh fast — 1 unrelated failure (see findings)
- git bisect of LUTWorkflowTests failure across 1731b84..bca796a — isolated to LUMO-308 (b01de9d), not LUMO-268
Findings:
- Re-verified the prior verifier's fix (commit 1731b84): rasterImage() previously rescanned mask.values with allSatisfy on every render frame, including export, to choose nearest/linear sampling; now reads a cached NormalizedMask.isBinary computed once at construction. Confirmed correct and covered.
- Cap correctly scoped: only .semantic component sources at MaskQuality.preview (RenderQuality .thumbnail/.interactive/.preview) go through SemanticMaskPreviewResolution.targetSize; .fullResolution/.export (MaskQuality.render) and non-semantic descriptors (.brush/.linear/.radial) stay at full extent. Confirmed the interactive canvas settles on RenderQuality.preview (PreviewCoordinator), which is the tier that actually hits the 1:1-zoom cliff described in the ticket, and that RenderQuality.fullResolution has no live production call site other than an unused makeCGImage(scale:) overload.
- Found an unrelated, pre-existing regression: LUTWorkflowTests.testExternalImportCanBeSelectedByIDAndSendsItThroughPreviewRequest fails on current main. Bisected to LUMO-308 (commit b01de9d), well outside LUMO-268's commit range (a964546, 1731b84). Filed as backlog child LUMO-319 (parent LUMO-268, label verification) rather than fixed here — root-causing it is outside a localized fix and the intervening 30+ commits are unrelated to mask rendering.
Fixes:
- None
Verification commits:
- bca796a
Actor: claude
Resolved model: sonnet
Pickup session: 01MTU699ZHGJT86UDB
Summary: Independent verification pass: the preview semantic-mask working-resolution cap is correctly scoped (preview-tier .semantic components only; render/export untouched) and the prior verifier's per-frame rescan fix (1731b84) holds up under re-review. All 33 LocalMaskRenderingTests pass and the build is clean under Swift 6 strict concurrency. Found and filed an unrelated pre-existing regression (LUMO-308 broke a LUT workflow test) as backlog child LUMO-319 -- not a blocker for this ticket.

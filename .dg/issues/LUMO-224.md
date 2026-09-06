---
id: LUMO-224
title: Add persistent smart Foreground and Background local masks
type: feature
status: done
priority: high
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - epic:masking
  - masking
  - photo-intelligence
  - rendering
created: 2026-09-04T21:48:31.831Z
updated: 2026-09-05T15:00:14.328Z
depends_on:
  - LUMO-201
  - LUMO-202
  - LUMO-219
  - LUMO-220
order: a0
board: product
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Stable user-facing Foreground target as union of usable foreground instances
      result: pass
    - criterion: Foreground/Background share segmentation work and are complementary
      result: pass
    - criterion: Persist semantic target, generation version, edge feather, edge shift, density, inversion; not solely RegionMaskReference
      result: pass
    - criterion: Cached/preview-quality result shown first, replaced by render quality without changing layer identity
      result: pass
    - criterion: Missing/version-invalid cache regenerates through coordinator/provider/store path; failures explicit and recoverable
      result: pass
    - criterion: Asset ID, source fingerprint, request revision, quality, provider version checked before publishing/rendering
      result: pass
    - criterion: Rapid switching/cancellation cannot display/export another photo's mask
      result: pass
    - criterion: Export waits for correct render-quality result or reports actionable failure; lower-quality fallback requires explicit choice
      result: pass
    - criterion: Existing Subject/Person/Face targets remain available through the same durable model
      result: pass
    - criterion: Cache hit/dedup/cancellation/regeneration/progressive-replacement/local-slider/persistence/reopen/cache-deletion/preview-export tests pass
      result: pass
  checks_run:
    - swift build — clean
    - swift test --filter 'SmartMaskTests|LocalMaskRenderingTests|MaskingWorkspaceTests|PhotoAnalysisCoordinatorTests|VisionSemanticMaskProviderTests' — 36 executed, 0 failures
    - dg validate — OK (pre-existing runner-model warning only)
    - git show 74c7f52 (full diff read) against LUMO-224 acceptance criteria and docs/MASKING_AND_LOCAL_ADJUSTMENTS_PLAN.md Sections 4.2/6/Step 7
  findings:
    - "LUMO-232 (non-blocking): the requestRevision guard added to RenderEngine.resolvedLocalMasks is vacuously true on every path (cache hits are re-stamped to match before the check; resolver results echo the same value back), so it does not actually detect staleness — real revision-staleness protection lives in AppViewModel's own sourceRevision/displayRevision publication gate."
    - "LUMO-233 (non-blocking): PhotoAnalysisCoordinator.performMask now special-cases kind == .background with its own foreground-union+invert composition, making VisionSemanticMaskProvider's own .background case unreachable from production code (only exercised by a test that calls the provider directly) — a duplicate, independently-maintained composition of the same result."
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-05T15:00:14.325Z
  session: 01MTOI9MQOZK4BWMWN
---

## Objective

Turn the existing semantic mask foundation into durable, editable Foreground and Background local
adjustment layers with progressive preview/refinement and safe regeneration.

## Context

LUMO-201 exposes selection-only semantic previews and LUMO-202 provides render-quality refinement,
but cache-backed `RegionMask` pixels are not a durable edit. A saved layer must remember what to
select, regenerate after cache deletion, and never attach a late result to another photo.

## Acceptance criteria

- [ ] Add a stable user-facing Foreground target representing the union of usable foreground
      instances; instance numbering is not the primary Foreground UI.
- [ ] Foreground and Background share segmentation/in-flight work and are complementary when
      produced from the same result.
- [ ] Persist semantic target, generation compatibility/version, edge feather, edge shift,
      density, and inversion; do not make a `RegionMaskReference` the sole source of truth.
- [ ] Creating/reselecting a smart mask displays a valid cached or preview-quality result first and
      replaces it with refined render quality without changing the layer identity.
- [ ] Missing or version-invalid cache data regenerates through the existing coordinator/provider/
      store path; failures remain explicit and recoverable without deleting the definition.
- [ ] Asset ID, source fingerprint, request revision, quality, and provider version are checked
      before any async result is published or rendered.
- [ ] Rapid switching/cancellation cannot display or export another photo's mask.
- [ ] Export waits for the correct render-quality result or reports an actionable failure; any
      lower-quality fallback requires explicit user choice.
- [ ] Existing Subject, Person, and Face targets remain available through the same durable model.
- [ ] Cache hit, deduplication, cancellation, regeneration, progressive replacement, local slider,
      persistence/reopen, cache deletion, and preview/export tests pass.

## Implementation notes

Follow Sections 4.2 and 6 plus Step 7 of `docs/MASKING_AND_LOCAL_ADJUSTMENTS_PLAN.md`. Reuse
`PhotoAnalysisCoordinator`, `VisionSemanticMaskProvider`, `MaskStore`, `MaskRefinement`,
`RegionMask`, and `MaskOperations`; do not create a parallel Vision/cache path.

All analysis remains on-device, asynchronous, cancellable, and independent from unrelated creative
slider values.

### Comment — codex @ 2026-09-05T14:55:59.375Z

Implemented persistent smart Foreground/Background masks in commit 74c7f52. Added durable semantic recipes with generation/settings metadata, stable Foreground union and complementary Background caching, coordinator-backed regeneration/refinement, provider/source/asset/quality/revision validation, shared preview/export wiring, cancellation/source-switch safety, and focused regression coverage. Verification: swift build; swift test --filter 'SmartMaskTests|LocalMaskRenderingTests|MaskingWorkspaceTests|PhotoAnalysisCoordinatorTests|VisionSemanticMaskProviderTests' (36 passed); additional smart/coordinator/provider suite (18 passed); dg validate and git diff --check passed.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-05T15:00:14.327Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Stable user-facing Foreground target as union of usable foreground instances (pass)
- [x] Foreground/Background share segmentation work and are complementary (pass)
- [x] Persist semantic target, generation version, edge feather, edge shift, density, inversion; not solely RegionMaskReference (pass)
- [x] Cached/preview-quality result shown first, replaced by render quality without changing layer identity (pass)
- [x] Missing/version-invalid cache regenerates through coordinator/provider/store path; failures explicit and recoverable (pass)
- [x] Asset ID, source fingerprint, request revision, quality, provider version checked before publishing/rendering (pass)
- [x] Rapid switching/cancellation cannot display/export another photo's mask (pass)
- [x] Export waits for correct render-quality result or reports actionable failure; lower-quality fallback requires explicit choice (pass)
- [x] Existing Subject/Person/Face targets remain available through the same durable model (pass)
- [x] Cache hit/dedup/cancellation/regeneration/progressive-replacement/local-slider/persistence/reopen/cache-deletion/preview-export tests pass (pass)
Checks run:
- swift build — clean
- swift test --filter 'SmartMaskTests|LocalMaskRenderingTests|MaskingWorkspaceTests|PhotoAnalysisCoordinatorTests|VisionSemanticMaskProviderTests' — 36 executed, 0 failures
- dg validate — OK (pre-existing runner-model warning only)
- git show 74c7f52 (full diff read) against LUMO-224 acceptance criteria and docs/MASKING_AND_LOCAL_ADJUSTMENTS_PLAN.md Sections 4.2/6/Step 7
Findings:
- LUMO-232 (non-blocking): the requestRevision guard added to RenderEngine.resolvedLocalMasks is vacuously true on every path (cache hits are re-stamped to match before the check; resolver results echo the same value back), so it does not actually detect staleness — real revision-staleness protection lives in AppViewModel's own sourceRevision/displayRevision publication gate.
- LUMO-233 (non-blocking): PhotoAnalysisCoordinator.performMask now special-cases kind == .background with its own foreground-union+invert composition, making VisionSemanticMaskProvider's own .background case unreachable from production code (only exercised by a test that calls the provider directly) — a duplicate, independently-maintained composition of the same result.
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MTOI9MQOZK4BWMWN
Summary: Counterpoint verification passed: independent review of 74c7f52 confirms durable Foreground/Background semantic recipes, shared segmentation/complementary background, coordinator-backed regeneration/refinement with asset/source/quality/version validation, and cancellation-safe progressive mask overlay replacement. Checks: swift build clean; swift test --filter 'SmartMaskTests|LocalMaskRenderingTests|MaskingWorkspaceTests|PhotoAnalysisCoordinatorTests|VisionSemanticMaskProviderTests' (36 passed); dg validate OK. Two non-blocking findings filed as LUMO-232 and LUMO-233 (child, labeled verification).

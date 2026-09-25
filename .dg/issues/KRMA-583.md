---
id: KRMA-583
title: Add production on-device Sky semantic mask provider
type: feature
status: backlog
priority: high
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - vision
  - masking
  - core-ml
  - performance
created: 2026-09-25T03:17:08.906Z
updated: 2026-09-25T03:17:59.945Z
depends_on:
  - KRMA-580
blockers: []
order: zzzv
board: product
---

## Objective

Productionize automatic on-device Sky masking in Kromora using the pretrained Core ML semantic-segmentation model selected and validated by KRMA-580. Add one production semantic class, `sky`, and keep scene-class extraction generic so more classes could be added later without a second provider architecture.

This issue depends on KRMA-580. Use the exact checkpoint, redistribution conclusion, Core ML artifact/conversion path, Sky class index, and input/output contract recorded by that spike. Do not guess these values or repeat the full model-selection exercise. If the spike is not a go, stop before adding or shipping a model artifact and record the blocker.

## Architecture

Add a scene-semantic provider that owns the model-specific inference and maps a requested semantic class from the shared class prediction result:

```text
SceneSemanticMaskProvider
    ↓
shared scene-segmentation inference
    ↓
class prediction map
    ↓
requested semantic class (.sky)
    ↓
analysis-space matte
```

Expose only `sky` in this issue. Keep class extraction generic enough for future vegetation, water, building, or ground classes, but do not add those classes or a broad masking architecture redesign.

## Implementation requirements

### Model ownership and lifecycle

- Add one selected Core ML model artifact to the appropriate app/package resource location, following the license and attribution requirements from KRMA-580.
- Do not duplicate model copies or introduce conversion dependencies into the app’s runtime dependency graph.
- Provide one appropriately scoped, lazily initialized model service/instance reused across images. Keep initialization and inference off the main actor/thread.
- Keep model ownership small and aligned with Kromora’s current architecture; do not introduce a general ML service framework.

### Preprocessing and output mapping

- Implement the exact resize/crop behavior, RGB ordering, normalization, and orientation policy documented by KRMA-580.
- Do not stretch a square model output to the photo. Map output coordinates back through the model’s resize/crop transform to the analysis image dimensions, preserving aspect and crop behavior.
- Produce a grayscale/alpha matte in Kromora’s analysis-image coordinate space, suitable for `RegionMask`/`NormalizedMask` and existing mask rendering.
- Keep mask/image coordinate conventions explicit and ensure the rendered matte aligns pixel-for-pixel with the analysis image.

### Sky extraction and edge quality

- Extract `sky` using the exact class ID and logits/probability/class-map interpretation documented by the spike.
- Generate a Sky-selected / non-Sky-unselected mask. Use confidence values if they improve results and the spike justifies the policy.
- Preserve useful soft output when available. Use only the simplest appropriate interpolation/refinement when mapping to analysis dimensions.
- Do not draw synthetic geometry, return a rectangular fallback, or silently substitute a full-frame mask.
- If there are no meaningful Sky pixels, return the existing semantic-mask not-applicable/unavailable behavior. Do not create an empty active mask or accidental full-frame inverse.

### Cache and concurrency

- Integrate with the existing semantic-mask cache/version system. Include model/checkpoint/provider version in cache identity so a future model change invalidates incompatible mattes.
- Deduplicate concurrent inference for the same source/image analysis and reuse the complete scene class map if it serves the requested class.
- Keep cancellation and cache/source identity fences consistent with existing providers.
- If one model pass produces the complete scene map, later scene-class requests should extract/cache their class matte from that result rather than rerun inference.

### Masking workflow

- Expose `.sky` as the only new scene-semantic target through the existing semantic mask and local-mask workflow so the generated result can be selected and edited like other semantic masks.
- Do not expose vegetation, water, buildings, ground, or other model classes.
- Avoid redesigning Add Mask or the masking workspace.

## Tests

Add deterministic tests around:

- class-map to Sky matte extraction and exact class ID mapping from KRMA-580
- non-square model input/output and image-space coordinate mapping
- resize/crop transform and orientation handling
- correct output dimensions and representative coverage
- no-Sky/unavailable behavior without empty active masks or full-frame inversions
- provider/model version participation in cache identity
- reuse of one cached scene-class result for multiple class extraction requests, if exposed by the architecture
- source/cache identity, concurrency deduplication, and cancellation as appropriate
- existing Vision Person, Face, Foreground, and Subject behavior remaining unchanged

Use synthetic class maps for stable unit coverage. Add at least one smoke/integration test with the actual model when practical and supported by the license/resource setup; do not make the entire suite depend on nondeterministic model output.

## Diagnostics

When debug diagnostics are enabled, make it possible to inspect or record:

- model input and output dimensions
- analysis/source image dimensions and mapping transform
- Sky class index
- Sky pixel coverage
- inference duration

Do not add noisy production logging by default.

## Acceptance criteria

- Sky inference runs entirely on-device with the selected pretrained model and no custom training.
- The model is loaded once/reused appropriately, and inference does not block the UI thread.
- One scene-model inference can be reused for concurrent or later requests for the same analysis identity.
- The provider returns an analysis-space Sky matte that aligns correctly with the photo and works through existing mask rendering/local adjustment paths.
- No-sky images report the semantic target as unavailable/not applicable rather than creating empty or full-frame masks.
- Model/provider changes invalidate cached Sky results.
- Only `sky` is exposed; existing Vision-backed semantic providers and behavior are unchanged.
- The implementation follows KRMA-580 licensing, artifact, preprocessing, class-index, and output-mapping findings.
- Handoff documents provider/model locations, preprocessing and class mapping, cache behavior, measured average inference latency, and the path for adding another semantic class.

## Context

- Prerequisite model decision and exact contract: KRMA-580, on-device pretrained semantic Sky feasibility spike.
- Existing provider boundary and Vision provider: `Sources/KromoraKit/Models/PhotoAnalysis/VisionSemanticMaskProvider.swift`.
- Coordinator/cache integration: `Sources/KromoraKit/Models/PhotoAnalysis/PhotoAnalysisCoordinator.swift` and `MaskStore.swift`.
- Analysis image and mask value types: `AnalysisImage.swift`, `RegionMask.swift`, `AnalysisValueTypes.swift`, and `MaskOperations.swift` in `Sources/KromoraKit/Models/PhotoAnalysis/`.
- Local semantic mask recipe and rendering path: `Sources/KromoraKit/Models/LocalMaskModels.swift`, `LocalMaskRendering.swift`, and `LocalMaskRenderer.swift`.
- Project constraints: macOS 14+ and zero third-party runtime dependencies (`CLAUDE.md`).

## Checks

- `swift build`
- Run relevant semantic-mask, model/provider, photo-analysis, local-mask rendering, and masking-workflow tests.
- Run the actual-model smoke test when practical.
- `git diff --check`

## Out of scope

- Sky replacement, generative fill, or user-selected models.
- Training or fine-tuning.
- Exposing vegetation, water, building, ground, or other scene classes.
- Changing Person, Face, Foreground, or Subject providers.
- Edge-refinement UI or broad masking-architecture redesign.

## Handoff

Document the provider and model resource locations, exact model/checkpoint and license, preprocessing pipeline, class/output mapping, image-space transform, cache/version behavior, average inference latency, no-Sky behavior, and how another semantic class can reuse the scene prediction result.

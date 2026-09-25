---
id: KRMA-580
title: "Feasibility spike: on-device pretrained semantic Sky mask"
type: task
status: backlog
priority: medium
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - vision
  - masking
  - research
  - core-ml
created: 2026-09-25T03:02:00.429Z
updated: 2026-09-25T03:56:23.028Z
blockers: []
order: zx
board: product
---

## Objective

Determine whether Kromora can generate a useful automatic Sky matte locally on-device using an existing pretrained semantic-segmentation model. This is a feasibility and architecture spike with a minimal prototype, not production masking UI work.

Kromora does not want to train a custom model. Start by evaluating a small pretrained model with a known Sky class, with SegFormer B0 fine-tuned on ADE20K as the first candidate. Consider another off-the-shelf model only if it is materially easier to convert and ship on Apple platforms at comparable quality.

## Constraints

- No custom training, fine-tuning, or dataset creation.
- Inference must run fully on-device; photo data must not be sent to a service.
- Prefer Core ML and Apple frameworks for runtime integration.
- Preserve Kromora’s zero third-party runtime dependency constraint. Conversion tooling may use documented Python packages in a reproducible development script.
- Do not implement the final Add Mask → Sky UI or redesign the masking architecture.
- Keep the prototype small; it may live outside the production provider if that makes the feasibility work faster.

## Candidate

Evaluate SegFormer B0 pretrained/fine-tuned on ADE20K first. Confirm that the exact checkpoint includes a Sky class and verify the applicable licenses for the checkpoint, model code, and dataset. Prefer the smallest checkpoint that meets the quality bar. An alternative pretrained model is acceptable if the comparison explains why it is easier to convert/package on macOS with comparable Sky quality.

## Investigation requirements

### 1. Model acquisition and redistribution

- Record the exact model/checkpoint source, version or revision, class set, and expected downloaded and converted file sizes.
- Identify licenses for the weights, architecture/code, and training dataset separately.
- Confirm whether the selected artifacts may legally be redistributed in a commercial macOS application. Record evidence or unresolved legal questions; do not assume a permissive license from the model name alone.
- Record attribution and notice requirements.

### 2. Core ML conversion

- Determine whether the model converts and runs cleanly in Core ML on the project’s supported macOS deployment target.
- Prefer a reproducible conversion script in the repository over manual conversion steps.
- Record required Python, conversion tool, and package versions. Keep conversion dependencies out of the app’s runtime dependency graph.
- Record whether any unsupported layers, custom operations, or post-processing are required.

### 3. Input/output contract

Document the concrete model contract:

- model input width/height and color format
- RGB channel ordering and normalization
- output tensor shape and data type
- whether output contains logits, probabilities, or class IDs
- exact Sky class ID for the selected checkpoint
- resize/crop/letterbox policy and coordinate mapping from model output back to the analysis image
- confidence threshold or argmax policy, if applicable
- conversion of the class map into a grayscale/alpha matte

### 4. Prototype inference

Build the smallest deterministic harness needed to:

1. load the converted model,
2. preprocess a real image at the intended analysis resolution,
3. run local inference,
4. extract the Sky class,
5. map the matte back to analysis-image dimensions, and
6. save or inspect the matte in a useful grayscale/overlay form.

The prototype need not enter production masking code. Preserve source image dimensions and mapping metadata so coordinate mistakes can be distinguished from model quality.

### 5. Performance

Measure on Apple Silicon and record:

- converted model file size
- model load time
- first inference time
- warm inference time
- peak or approximate memory usage, if practical
- hardware, macOS version, Core ML compute-unit configuration, and analysis input dimensions

Use at least one representative Kromora-sized source image, but run inference at the model’s intended analysis resolution rather than full photo resolution. Report whether latency is reasonable for an interactive photo editor.

### 6. Quality

Test a small, varied set of images covering:

- clear blue sky
- cloudy or overcast sky
- sunset or sunrise
- sky partly hidden by trees
- skyline/buildings
- mountain horizon
- no-sky exterior
- indoor scene

Save sample masks or screenshots for review. Record obvious failure modes, including trees classified as sky, water classified as sky, bright windows classified as sky, horizon leakage, gaps between leaves, missed clouds, and false positives when there is no sky.

Compare against crude heuristics only as a baseline to show whether the pretrained model provides a meaningful improvement. Do not tune a custom classifier or train any model.

### 7. Integration fit

- Describe how the output would fit Kromora’s `SemanticMaskProviding` boundary and existing `AnalysisImage`, `RegionMask`, `NormalizedMask`, and `MaskStore` flow.
- Prefer returning the same kind of analysis-space grayscale matte used by existing semantic-mask providers.
- Identify cache/versioning, model resource packaging, memory, cancellation, and macOS availability considerations for a production provider.
- Keep any production-facing changes minimal and explicitly separate them from the feasibility prototype.

## Success criteria

The spike can recommend proceeding only if the evidence supports all of these:

- fully on-device inference with no custom training
- licensing that permits commercial redistribution of required artifacts
- a reproducible conversion/package path
- acceptable file size, memory use, and latency for an interactive editor
- masks meaningfully better than crude heuristics on the varied cases
- output can be represented in Kromora’s existing analysis-space mask format

If any criterion fails, document the blocker and recommend an alternative or no-go.

## Deliverables

- prototype inference harness and reproducible conversion script, if conversion is viable
- converted test model artifact when practical and legally distributable; otherwise document a reproducible download/build path without committing a large or restricted artifact
- model source, checkpoint/version, class set, license, notices, input/output contract, and conversion requirements
- measured file size, model load time, first/warm inference latency, and memory estimate
- saved sample mattes/screenshots for the varied quality set
- observed failure modes and recommendation on whether to proceed
- recommendation for the exact model/checkpoint to productionize, or a documented no-go

## Context

- Existing semantic provider boundary and Vision implementation: `Sources/KromoraKit/Models/PhotoAnalysis/VisionSemanticMaskProvider.swift`.
- Analysis and cache integration: `Sources/KromoraKit/Models/PhotoAnalysis/PhotoAnalysisCoordinator.swift` and `MaskStore.swift`.
- Analysis-space image and matte value types: `Sources/KromoraKit/Models/PhotoAnalysis/AnalysisImage.swift`, `RegionMask.swift`, and `AnalysisValueTypes.swift`.
- `CLAUDE.md` requires macOS 14+ and zero third-party runtime dependencies.
- Related but separate UI issue: KRMA-567 (select a mask by clicking its canvas pin); do not implement Sky creation UI in this spike.

## Checks

Run prototype/conversion checks appropriate to the chosen model, including a clean documented conversion or model-load/inference path. Then run:

- `git diff --check`

Record all commands and their results in the handoff. A production `swift build` is required only if production code or package resources are changed; do not add heavyweight dependencies or artifacts just to make the spike compile as an app feature.

## Out of scope

- Custom model training or fine-tuning.
- Add Mask → Sky production UX.
- Sky replacement, generative fill, edge-refinement UI, or user-painted corrections.
- Water, vegetation, or building masks.
- Shipping a large scene-segmentation framework.

## Handoff

Clearly document the selected model/checkpoint or no-go, source and license, commercial redistribution conclusion, converted model size, inference latency and hardware, Sky class index, preprocessing/output mapping, observed mask quality and failure modes, production integration risks, and the recommendation on whether to proceed.

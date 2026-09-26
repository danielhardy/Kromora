---
id: KRMA-593
title: Make Auto more decisive with Light and Color improvements
type: feature
status: backlog
priority: high
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - auto
  - quality
created: 2026-09-26T03:05:01.511Z
updated: 2026-09-26T03:05:17.993Z
order: zzzzq
board: product
context:
  files:
    - Sources/KromoraKit/Models/PhotoAnalysis/AutoEnhancementPolicy.swift
    - Sources/KromoraKit/Models/PhotoAnalysis/AutoEnhancementCoordinator.swift
    - Tests/KromoraKitTests/AutoEnhancementPolicyTests.swift
    - Tests/KromoraKitTests/AutoQualityRegressionTests.swift
    - Tests/KromoraKitTests/ContentAwareAutoEngineTests.swift
    - Tests/KromoraKitTests/AutoAdjustmentTests.swift
  docs:
    - docs/AUTO_EXPOSURE_POLICY.md
    - docs/AUTO_PERFORMANCE.md
  issues:
    - KRMA-507
  commands:
    - scripts/auto-quality-report.sh
    - swift test --filter 'AutoEnhancementPolicyTests|AutoQualityRegressionTests|ContentAwareAutoEngineTests|AutoAdjustmentTests'
    - dg validate
    - git diff --check
---

## Objective

Make Auto less conservative and more visibly useful by applying stronger, evidence-supported corrections to both Light and Color. When a photo benefits from both, Auto should improve both tonal balance and colorfulness rather than returning a barely changed result.

## Context

This is a quality improvement to the shipped content-aware Auto workflow, not a request to move every slider on every image. The current workflow renders and scores multiple candidates, then rejects candidates for clipping, excessive saturation, unsupported color error, or insufficient measured improvement. Its color policy is explicitly restrained: it skips mixed-light, monochrome, sunset-warm, and night scenes, and only boosts vibrance for reliably measured low-colorfulness images. This can leave useful Light or Color improvements unapplied or too subtle.

Revisit candidate strength, evidence thresholds, and selection scoring together. Keep the renderer-backed before/after comparison and scene-intent guardrails; do not substitute larger fixed slider values for image-quality evaluation. A meaningful correction may change Light, Color, or both depending on the photo. Do not require a color boost for already vivid, monochrome, or intentionally warm/night images.

Related behavior: KRMA-507 established that Auto replaces only its owned global Light/Color values as one undoable operation while preserving unrelated edits. Preserve that contract.

Relevant implementation and quality references:
- `Sources/KromoraKit/Models/PhotoAnalysis/AutoEnhancementPolicy.swift`
- `Sources/KromoraKit/Models/PhotoAnalysis/AutoEnhancementCoordinator.swift`
- `Tests/KromoraKitTests/AutoQualityRegressionTests.swift`
- `docs/AUTO_EXPOSURE_POLICY.md`

## Acceptance criteria

- [ ] Define a representative quality matrix with underexposed/flat-light, muted-color, color-cast, balanced, high-key, low-key, sunset, night, monochrome, and backlit photos; record what visible change Auto should make for each relevant case.
- [ ] Photos with measured tonal problems receive a clearly visible Light correction when the rendered candidate improves tone without violating clipping and scene-intent guardrails.
- [ ] Muted-color photos with reliable color evidence receive a clearly visible vibrance or saturation correction. A photo with evidence for both tonal and color improvement receives both; images without that evidence are not forced to change both categories.
- [ ] Tests inspect rendered before/after results and assert that the intended Light and Color changes are perceptible and improve their target measurements; proposal-field changes alone are insufficient.
- [ ] Balanced, monochrome, intentionally warm/night, and already-vivid photos retain their character and avoid harmful clipping, oversaturation, or unsupported neutralization.
- [ ] Auto remains one undoable operation and preserves unrelated document state, including masks and user-owned local adjustments.
- [ ] Update `docs/AUTO_EXPOSURE_POLICY.md` with the calibrated policy, evidence thresholds, and guardrails.

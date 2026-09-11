---
id: KRMA-355
title: Integrate regional Auto corrections into the production Auto run
type: bug
status: done
priority: urgent
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: The real ContentAwareAutoEngine path derives post-global regional evidence and invokes the existing AutoRegionalCorrections planner/apply seam when a material conflict is measured.
      result: pass
      notes: ContentAwareAutoEngine.run now re-measures the selected global candidate via CurrentEditMeasurer/MaskStore, derives subject/background/cast evidence, and calls AutoRegionalCorrections.plan/applying for improved/unchanged/noCandidate statuses; cancelled/staleRevision/renderUnavailable paths skip measurement and plan from existing layer names only.
    - criterion: Accepted results can contain at most three Auto-owned semantic layers, while existing user-owned layers remain unchanged and repeated Auto runs do not duplicate generated layers.
      result: pass
      notes: Cap enforced in AutoRegionalCorrections.plan (layers.prefix(AutoRegionalPurpose.maximumLayers)). Reconciliation by autoProvenance.stableIdentity in both AutoRegionalCorrections.applying and EditDocument.applyingAutoResult protects user layers and prevents duplicate generated layers on repeat runs; hasAutoLayers() short-circuits re-planning once Auto layers exist.
    - criterion: Renderer-backed tests cover a regional conflict that creates a layer and missing/global evidence that leaves the document unchanged with an explained result.
      result: pass
      notes: ContentAwareAutoEngineTests adds testRegionalConflictAddsEditableAutoLayersThroughProductionPath (real RenderEngine, split-tone fixture, asserts Auto-Subject layer, cap, user-layer preservation, and no duplication on repeat run/second Auto invocation) and testNoMasksKeepBalancedDocumentUnchangedWithRegionalReasons (no masks, unchanged status, explained reasons).
  checks_run:
    - swift build
    - swift test --filter ContentAwareAutoEngineTests|AutoEnhancementResultTests|AutoRegionalCorrectionsTests|EditDocumentTests
    - scripts/ci-tests.sh fast (839/839 passed)
    - scripts/ci-tests.sh serial (328/328 passed)
    - scripts/check-swift-format.sh
    - dg validate
  findings:
    - "Low severity, correctness: AutoEnhancementResult.from populated generatedLayerIDs from every localAdjustments entry in coordinator.document instead of only the newly generated Auto layers (Sources/KromoraKit/Models/AutoEnhancementResult.swift:234), so pre-existing user-owned layers were mislabeled as generated. Latent (isNoOp is the only consumer today, and the regional-only-improved branch always adds at least one new layer when reached), but mislabels the field for any future consumer. Fixed in this pass."
  fixes:
    - Filtered generatedLayerIDs to isAutoOwned layers only (Sources/KromoraKit/Models/AutoEnhancementResult.swift:234), matching the existing pattern in EditDocument.applyingAutoResult.
  verification_commits:
    - e52b555
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-11T00:00:01.880Z
  session: 01MTW6RCKUQQA3ITY8
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - verification
created: 2026-09-10T23:31:19.875Z
updated: 2026-09-11T00:00:01.882Z
parent: KRMA-341
depends_on:
  - KRMA-348
order: a0
board: product
commits:
  - e52b555
---

## Objective

Wire the existing KRMA-348 regional planner into the production content-aware Auto path.

## Context

The current production action reaches `ContentAwareAutoEngine.run()`, which measures regions and
evaluates global native/Apple candidates, but never calls `AutoRegionalCorrections.plan()` or
`AutoRegionalCorrections.applying()`. As a result, the implemented and tested KRMA-348 planner can
never create `Auto — Subject`, `Auto — Background`, or `Auto — Color` layers for a real Auto
invocation, so the epic objective and regional correction acceptance criteria are not met.

Keep the existing RegionMask/MaskStore and renderer seams, preserve manual layers, keep the result
atomic/undoable, and add an end-to-end production-path regression test with a material regional
conflict plus a no-conflict/no-mask case.

## Acceptance criteria

- [ ] The real `ContentAwareAutoEngine` path derives post-global regional evidence and invokes the
      existing `AutoRegionalCorrections` planner/apply seam when a material conflict is measured.
- [ ] Accepted results can contain at most three Auto-owned semantic layers, while existing
      user-owned layers remain unchanged and repeated Auto runs do not duplicate generated layers.
- [ ] Renderer-backed tests cover a regional conflict that creates a layer and missing/global
      evidence that leaves the document unchanged with an explained result.

## Implementation notes

<!-- Approach, constraints, links -->

### Comment — codex @ 2026-09-10T23:55:58.977Z

Implemented in dc9ad28. ContentAwareAutoEngine now re-measures the selected global candidate through CurrentEditMeasurer/MaskStore, derives subject/background/cast evidence, invokes AutoRegionalCorrections.plan/applying, supports regional-only accepted results, preserves user layers, caps generated layers through the existing planner, and aborts cleanly on cancellation. Added renderer-backed conflict/no-mask regression tests. Verification: swift test (1,212 passed, 47 skipped), scripts/check-swift-format.sh, dg validate (OK; existing unknown-model warnings only).

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-11T00:00:01.880Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] The real ContentAwareAutoEngine path derives post-global regional evidence and invokes the existing AutoRegionalCorrections planner/apply seam when a material conflict is measured. (pass) — ContentAwareAutoEngine.run now re-measures the selected global candidate via CurrentEditMeasurer/MaskStore, derives subject/background/cast evidence, and calls AutoRegionalCorrections.plan/applying for improved/unchanged/noCandidate statuses; cancelled/staleRevision/renderUnavailable paths skip measurement and plan from existing layer names only.
- [x] Accepted results can contain at most three Auto-owned semantic layers, while existing user-owned layers remain unchanged and repeated Auto runs do not duplicate generated layers. (pass) — Cap enforced in AutoRegionalCorrections.plan (layers.prefix(AutoRegionalPurpose.maximumLayers)). Reconciliation by autoProvenance.stableIdentity in both AutoRegionalCorrections.applying and EditDocument.applyingAutoResult protects user layers and prevents duplicate generated layers on repeat runs; hasAutoLayers() short-circuits re-planning once Auto layers exist.
- [x] Renderer-backed tests cover a regional conflict that creates a layer and missing/global evidence that leaves the document unchanged with an explained result. (pass) — ContentAwareAutoEngineTests adds testRegionalConflictAddsEditableAutoLayersThroughProductionPath (real RenderEngine, split-tone fixture, asserts Auto-Subject layer, cap, user-layer preservation, and no duplication on repeat run/second Auto invocation) and testNoMasksKeepBalancedDocumentUnchangedWithRegionalReasons (no masks, unchanged status, explained reasons).
Checks run:
- swift build
- swift test --filter ContentAwareAutoEngineTests|AutoEnhancementResultTests|AutoRegionalCorrectionsTests|EditDocumentTests
- scripts/ci-tests.sh fast (839/839 passed)
- scripts/ci-tests.sh serial (328/328 passed)
- scripts/check-swift-format.sh
- dg validate
Findings:
- Low severity, correctness: AutoEnhancementResult.from populated generatedLayerIDs from every localAdjustments entry in coordinator.document instead of only the newly generated Auto layers (Sources/KromoraKit/Models/AutoEnhancementResult.swift:234), so pre-existing user-owned layers were mislabeled as generated. Latent (isNoOp is the only consumer today, and the regional-only-improved branch always adds at least one new layer when reached), but mislabels the field for any future consumer. Fixed in this pass.
Fixes:
- Filtered generatedLayerIDs to isAutoOwned layers only (Sources/KromoraKit/Models/AutoEnhancementResult.swift:234), matching the existing pattern in EditDocument.applyingAutoResult.
Verification commits:
- e52b555
Actor: claude
Resolved model: sonnet
Pickup session: 01MTW6RCKUQQA3ITY8
Summary: Verified KRMA-355: production Auto path correctly wires post-global regional measurement into AutoRegionalCorrections plan/apply, layer cap and dedup hold, and new renderer-backed tests cover conflict and no-mask cases. Fixed a latent generatedLayerIDs mislabeling bug (commit e52b555). Full build, fast+serial CI lanes, and swift-format all pass.

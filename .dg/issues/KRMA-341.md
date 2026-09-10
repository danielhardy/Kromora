---
id: KRMA-341
title: Content-aware Auto engine and renderer-backed candidate evaluation
type: feature
status: ready
priority: high
agent: pi
verification_agent: codex
model: openrouter/meta/muse-spark-1.3-contributor
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - auto
  - photo-intelligence
  - rendering
created: 2026-09-10T14:39:07.864Z
updated: 2026-09-10T22:53:31.840Z
depends_on:
  - KRMA-181
order: v
board: product
---

## Objective

Build Kromora’s production content-aware Auto engine. Auto should inspect the current rendered edit, generate coordinated editable proposals, render and score bounded candidates through the real pipeline, add local corrections only when global edits cannot solve a measured regional conflict, and apply one durable reviewable result.

This is a follow-on to the completed Photo Intelligence foundation in KRMA-181 and KRMA-182–207. Reuse those analysis-image, semantic-mask, regional-statistics, coordinator, cache, fixture, and tuning seams; do not create a second analysis or mask subsystem.

## Delivery sequence

1. KRMA-342 — renderer-backed evaluation/reporting foundation
2. KRMA-343–344 — current-render measurements and scene/confidence evidence
3. KRMA-345–346 — pure coordinated policy and Apple enhancement reference
4. KRMA-347 — asynchronous candidate generation, bounded search, scoring, and selection
5. KRMA-348 — selective Auto-owned regional corrections
6. KRMA-349–350 — result provenance, persistence, UI integration, cancellation, and undo
7. KRMA-351–352 — fixture/regression coverage, performance, diagnostics, and release gate

## Cross-ticket constraints

- Apple frameworks only for the initial implementation: Vision, Core Image, Accelerate, Metal where already justified. No cloud processing, custom training, or required Core ML model bundle.
- Keep image data on-device. New interfaces are internal and must remain Swift 6 actor-safe; value types crossing async boundaries are `Sendable`, `Codable` where persisted, and testable without image objects.
- Preserve existing Looks/LUTs, grading, curves, mixer settings, crop/composition, manual masks, and photographic intent unless a ticket explicitly owns the relevant behavior.
- Auto must degrade gracefully: missing masks or optional signals reduce confidence and scope; they do not invalidate usable global measurements.
- Use the actual `RenderEngine` for evaluation and preview/export parity. CSS or synthetic approximations are not evidence of visual correctness.
- Do not claim Lightroom/Apple Photos parity from fixture-only testing. Record limitations and measured hardware results.

## Epic acceptance criteria

- [ ] Existing balanced images remain close to unchanged while known fixture exposure/color-cast defects improve.
- [ ] High-key, low-key, sunset, monochrome, fog, snow, night, and backlit intent is preserved; backlit subjects can improve without unnecessarily lifting the background.
- [ ] Auto changes are coordinated, bounded, editable, explainable, and represented by one `AutoEnhancementResult` value.
- [ ] Candidate selection always includes unchanged, uses a bounded render budget, rejects guardrail violations, and chooses the best completed acceptable candidate.
- [ ] At most three Auto-owned local layers are created, no duplicate layers accumulate, and manually modified Auto layers become user-owned.
- [ ] One invocation applies atomically as one undo operation, respects revision/cancellation guards, and leaves the document unchanged after render or validation failure.
- [ ] Repeating Auto on an unchanged successful result is a no-op with a clear message.
- [ ] Generated fixtures and actual renderer reports cover correction quality, intent preservation, masks, RAW/standard white-balance direction, preview/export consistency, undo/redo, save/reopen, and cancellation.
- [ ] Cold and warm timing is measured separately on the existing M1 Pro reference, decode time is reported separately, and the typical path targets 2–5 seconds.
- [ ] Fast and serial repository test lanes pass, with any unrelated baseline failures explicitly documented.

## Out of scope

- Training or shipping a custom model.
- Cloud or network image analysis.
- Automatic crop, grain, creative grading, Looks, or arbitrary user-mask replacement.
- Optimizing Apple’s aesthetics score for production selection; it is diagnostics-only initially.

## Source context

- `Sources/KromoraKit/Models/AutoAdjustment.swift`
- `Sources/KromoraKit/Models/PhotoAnalysis/`
- `Sources/KromoraKit/Models/RenderEngine.swift`
- `Sources/KromoraKit/Models/EditDocument.swift`
- `Sources/KromoraKit/Models/LocalMaskModels.swift`
- `Sources/KromoraKit/Models/EditDocumentStore.swift`
- `Sources/KromoraKit/Models/EditHistory.swift`
- `Sources/KromoraKit/ViewModels/AppViewModel+Light.swift`
- `Sources/KromoraKit/ViewModels/EditPersistenceCoordinator.swift`
- `Tests/KromoraKitTests/`
- `scripts/ci-tests.sh`

## Agent handoff

Each child ticket is independently reviewable. Before implementation, read the completed KRMA-181 child tickets and inspect the current Kromora names/types rather than copying stale Lumo-era paths from older documentation. Add focused tests with every production change and leave generated reports outside the committed source tree.


### Comment — pi @ 2026-09-10T15:18:11.234Z

Progress increment: KRMA-342 (renderer-backed evaluation/reporting foundation, delivery-sequence step 1) is implemented on branch krma-342-auto-evaluation with a full completion summary recorded in its comment thread: AutoCandidateEvaluation seam, analysis-view transform, diff/mask-overlay artifacts, 9/9 focused tests green, artifact generator scripts/auto-evaluation-report.sh. KRMA-342 remains claimed by pi pending session handoff to review/verification; remaining children KRMA-343-352 are still dependency-blocked and out of scope for this increment. Epic stays claimed; no epic acceptance boxes checked yet.


### Comment — pi @ 2026-09-10T16:59:21.903Z

Progress increment: KRMA-343 (current-render measurement pipeline, delivery-sequence step 2) is implemented on main at 71d167a with a full completion summary in its comment thread: CurrentEditMeasurer + CurrentEditSampling seam, linear/display tone, pixel-correlated color/neutrals, separate highlight headroom, regional measurement with independent confidence, bounded deterministic native detail, revision-guarded cache identity; 22/22 focused tests green, neighboring suites + fast/serial lanes green. KRMA-343 moved to review for verification; remaining children KRMA-344-352 still dependency-blocked and out of scope for this increment. Epic stays claimed; no epic acceptance boxes checked yet.


### Comment — pi @ 2026-09-10T18:19:35.037Z

Progress increment: KRMA-344 (scene classification evidence + per-signal confidence, delivery-sequence step 2) is implemented in the working tree with a full completion summary in its comment thread: 7 continuous scene likelihoods, VisionSceneClassifier adapter (nil-on-failure, on-device), SceneProvenance, AutoSignalConfidence aggregation, persisted sceneClassifications preserving the scene-is-pure-function-of-facts invariant, CurrentEditMeasurement bridge; 19/19 focused tests green, corpus + fast/serial lanes green. KRMA-344 moved to review for verification; remaining children KRMA-345-352 still out of scope for this increment. Epic stays claimed; no epic acceptance boxes checked yet.


### Comment — pi @ 2026-09-10T19:03:26.458Z

Progress increment: KRMA-345 (pure coordinated AutoEnhancementPolicy proposals, delivery-sequence step 3) is implemented on main at 9103358 with a full completion summary in its comment thread: exposure-first residual coordination, neutral-or-agreement white balance with correct RAW/standard direction, restrained color, fog-only dehaze, byte-for-byte preservation of user-owned state, advisory-only masks; 20/20 focused tests green, Auto suites + fast/serial lanes green. KRMA-345 moved to done for verification; KRMA-346 (Apple enhancement reference) is now unblocked, remaining children KRMA-346-352 out of scope for this increment. Epic stays claimed; no epic acceptance boxes checked yet.


### Comment — pi @ 2026-09-10T20:10:30.582Z

Progress increment: KRMA-348 (selective Auto-owned regional correction layers, delivery-sequence step 5) is implemented on branch krma-348-regional-corrections at 7d8fa20 with a full completion summary in its comment thread: pure AutoRegionalCorrections planner emitting at most three ordinary editable semantic recipes only on material post-global conflict with explained skips, feathered landmark-derived face mattes intersected with person/foreground support replacing rectangle treatment, 21/21 focused tests green, Auto suites + masking/rotation neighbors green, fast/serial lanes green. KRMA-348 moved to review for verification; remaining children KRMA-349-352 still out of scope for this increment. Epic stays claimed; no epic acceptance boxes checked yet.


### Comment — pi @ 2026-09-10T22:53:26.911Z

Progress increment: no new implementation this session. Verified KRMA-348 branch state (krma-348-regional-corrections at 7d8fa20): 21/21 AutoRegionalCorrectionsTests green, working tree clean aside from .dg bookkeeping churn, no source changes made. KRMA-342-347 are done; KRMA-348 remains in review pending verification_agent (codex), so KRMA-349-352 stay dependency-blocked and out of scope. Epic stays claimed; no epic acceptance boxes checked yet.

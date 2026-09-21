---
id: KRMA-341
title: Content-aware Auto engine and renderer-backed candidate evaluation
type: feature
status: done
priority: high
agent: codex
verification_agent: codex
model: gpt-5.6-luna
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: The production content-aware Auto invocation adds selective Auto-owned regional corrections when global edits cannot solve a measured regional conflict.
      result: pass
      notes: Current ContentAwareAutoEngine performs post-global renderer-backed regional measurement and invokes AutoRegionalCorrections.plan/applying; the real conflict regression creates an editable Auto-Subject layer.
    - criterion: Candidate evaluation, guardrails, cancellation, revision fencing, and atomic persistence apply through the real renderer.
      result: pass
      notes: Coordinator, AppViewModel integration, renderer-backed conflict/no-mask tests, persistence/lifecycle tests, and required fast/serial lanes pass.
    - criterion: Auto result ownership and repeat-run no-op behavior are durable and user-editable.
      result: pass
      notes: Ownership transitions, stable provenance reconciliation, schema-v4 document round trips, repeat-run no-op behavior, undo/redo, and save/reopen coverage pass.
  checks_run:
    - git diff --check (pass)
    - dg validate (pass; known unknown-model warnings only)
    - swift build (pass)
    - focused Auto/regional/result/persistence/quality/diagnostics tests (119 passed, 1 expected opt-in skip)
    - scripts/ci-tests.sh fast (872/872 passed)
    - scripts/ci-tests.sh serial (328/328 passed)
    - scripts/ci-tests.sh verify (pass; required lanes disjoint)
    - scripts/auto-quality-report.sh (25 policy tests and 6 actual-render tests passed)
    - KROMORA_AUTO_BENCHMARK=1 swift test --no-parallel --filter AutoPerformanceDiagnosticsTests/testAutoEndToEndBenchmark (pass; cold 6.561s, warm 5.917s; warm masks 0.001s after fix)
    - KROMORA_PHOTO_ANALYSIS_BENCHMARK=1 swift test --no-parallel --filter PhotoAnalysisPerformanceTests (3 documented baseline drift failures; 5 other tests passed)
    - scripts/check-swift-format.sh (baseline violations in touched pre-existing/new KRMA-351/352 files; no violation on verification-added lines)
    - production call-site search for AutoRegionalCorrections.plan/applying (present)
  findings:
    - "[fixed][diagnostics] Warm analysis-cache hits reused cached mask-generation duration, misreporting stale mask latency despite no mask work in the current invocation. ContentAwareAutoEngine now clamps maskSeconds to the current analysis window, with a cold/warm regression assertion and corrected release note."
    - "[non-blocking][performance] Debug end-to-end Auto remains above the rough 2-5s target (cold 6.561s, warm 5.917s); the existing KRMA-352 release note attributes this to renderer measurement, candidate renders, regional re-measurement, and Debug scoring. No correctness gate was relaxed."
    - "[non-blocking][baseline] The opt-in photo-analysis benchmark still shows the documented global-tone, masked-tone, and person-mask baseline drifts; required fast/serial lanes pass and the changed Auto path is not implicated."
  fixes:
    - Clamped cached mask timing to the current invocation window in Sources/KromoraKit/Models/PhotoAnalysis/ContentAwareAutoEngine.swift.
    - Added a warm-run mask-timing regression assertion in Tests/KromoraKitTests/AutoPerformanceDiagnosticsTests.swift.
    - Updated docs/AUTO_PERFORMANCE.md so the warm mask measurement reflects cache-hit behavior.
  verification_commits: []
  actor: codex
  resolved_model: unknown
  completed_at: 2026-09-11T00:58:11.885Z
  session: 01MTW8ORVON0HV4QFA
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - auto
  - photo-intelligence
  - rendering
created: 2026-09-10T14:39:07.864Z
updated: 2026-09-11T00:58:11.888Z
depends_on:
  - KRMA-181
order: a0
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


### Comment — pi @ 2026-09-10T23:01:03.378Z

Progress increment: no new implementation this session. Verified krma-348-regional-corrections at 7d8fa20 in an isolated throwaway worktree (main tree untouched): 21/21 AutoRegionalCorrectionsTests green, 89/89 Auto-filtered tests green, 41/41 Masking tests green, 7/7 VisionSemanticMaskProviderTests green, swift build clean. KRMA-342-347 are done (346/347 verified PASS, commits d424821/854beac live on branches, not yet on main); KRMA-348 remains in review pending verification_agent (codex), so KRMA-349-352 stay dependency-blocked and out of scope. Noted integration gap: verified 346/347 commits are not in main history (main at 93773a9, post-345); left unmerged deliberately to avoid diverging the stacked 348 review branch — integration should land with or after 348 verification. Epic stays claimed; no epic acceptance boxes checked yet.


### Comment — codex @ 2026-09-10T23:27:10.924Z

Implementation increment complete on main. Integrated the verified KRMA-346/347/348 stack (Core Image reference fitting, bounded renderer-backed coordinator, selective Auto-owned regional recipes) and added KRMA-349/350 core seams: Codable Sendable AutoEnhancementResult with scalar validation/provenance, explicit Auto/user layer ownership with manual-edit release, stable source/document/algorithm/render fingerprints, schema v4 migration defaults, duplicate-safe layer reconciliation, current-render ContentAwareAutoEngine orchestration, real RenderEngine Auto action integration, atomic history/persistence apply, cancellation/stale guards, and no-op status. Focused suites: AutoEnhancementResult 5, coordinator 19, regional 21, persistence/document 29, AppViewModel Auto 11; repository fast lane 834/834 passed. swift build, dg validate, and git diff --check pass. Commits: d5fdff5, 20cef62, efba752, d0bab1f, df936ac. Remaining release-corpus/performance gate work is tracked by KRMA-351/352.

## Agent log

- 2026-09-10T23:32:41.484Z: Verification report
Verdict: BLOCKER
Acceptance criteria:
- [ ] The production content-aware Auto invocation adds selective Auto-owned regional corrections when global edits cannot solve a measured regional conflict. (fail) — ContentAwareAutoEngine.run() rehydrates masks and measures regions, then sends only global native and Apple proposals to AutoEnhancementCoordinator. It never invokes AutoRegionalCorrections.plan() or AutoRegionalCorrections.applying(); the only plan/apply call sites are AutoRegionalCorrectionsTests. Therefore a real Auto action cannot create any regional layer.
- [x] Candidate evaluation, guardrails, cancellation, revision fencing, and atomic persistence apply through the real renderer. (pass) — Reviewed the coordinator and AppViewModel integration; focused coordinator/persistence tests and both required lanes pass.
- [x] Auto result ownership and repeat-run no-op behavior are durable and user-editable. (pass) — Reviewed AutoEnhancementResult, schema-v4 decoding, ownership transitions, fingerprinting, and reconciliation tests; no separate blocker found in these seams.
Checks run:
- git diff --check (pass)
- dg validate (pass; only existing unknown-model warnings)
- swift build (pass)
- swift test --filter KromoraKitTests.AutoEnhancementCoordinatorTests (19/19 passed)
- swift test --filter KromoraKitTests.AutoRegionalCorrectionsTests (21/21 passed)
- swift test --filter KromoraKitTests.AutoAdjustmentTests (11/11 passed)
- swift test --filter KromoraKitTests.EditPersistenceIntegrationTests (11/11 passed)
- scripts/ci-tests.sh fast (834/834 passed)
- scripts/ci-tests.sh serial (328/328 passed)
- rg verification: AutoRegionalCorrections.plan/applying has no production call sites
Findings:
- [blocker][correctness] Sources/KromoraKit/Models/PhotoAnalysis/ContentAwareAutoEngine.swift:51-124 measures regional masks but builds the coordinator only from global native/Apple proposals. AutoRegionalCorrections.plan() and applying() are never called from production code; repo-wide search finds those calls only in AutoRegionalCorrectionsTests. Consequently the real Auto action can never add Auto — Subject, Auto — Background, or Auto — Color layers, so the epic objective and regional-conflict acceptance criterion remain unmet despite the isolated KRMA-348 planner tests passing.
Fixes:
- None
Verification commits:
- None
Actor: codex
Resolved model: unknown
Pickup session: 01MTW5Q8VUDZTJW9OH
Summary: Blocker: production ContentAwareAutoEngine never invokes the implemented regional correction planner, so real Auto runs cannot create selective Auto-owned layers; see urgent child KRMA-355.

- 2026-09-11T00:58:11.885Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] The production content-aware Auto invocation adds selective Auto-owned regional corrections when global edits cannot solve a measured regional conflict. (pass) — Current ContentAwareAutoEngine performs post-global renderer-backed regional measurement and invokes AutoRegionalCorrections.plan/applying; the real conflict regression creates an editable Auto-Subject layer.
- [x] Candidate evaluation, guardrails, cancellation, revision fencing, and atomic persistence apply through the real renderer. (pass) — Coordinator, AppViewModel integration, renderer-backed conflict/no-mask tests, persistence/lifecycle tests, and required fast/serial lanes pass.
- [x] Auto result ownership and repeat-run no-op behavior are durable and user-editable. (pass) — Ownership transitions, stable provenance reconciliation, schema-v4 document round trips, repeat-run no-op behavior, undo/redo, and save/reopen coverage pass.
Checks run:
- git diff --check (pass)
- dg validate (pass; known unknown-model warnings only)
- swift build (pass)
- focused Auto/regional/result/persistence/quality/diagnostics tests (119 passed, 1 expected opt-in skip)
- scripts/ci-tests.sh fast (872/872 passed)
- scripts/ci-tests.sh serial (328/328 passed)
- scripts/ci-tests.sh verify (pass; required lanes disjoint)
- scripts/auto-quality-report.sh (25 policy tests and 6 actual-render tests passed)
- KROMORA_AUTO_BENCHMARK=1 swift test --no-parallel --filter AutoPerformanceDiagnosticsTests/testAutoEndToEndBenchmark (pass; cold 6.561s, warm 5.917s; warm masks 0.001s after fix)
- KROMORA_PHOTO_ANALYSIS_BENCHMARK=1 swift test --no-parallel --filter PhotoAnalysisPerformanceTests (3 documented baseline drift failures; 5 other tests passed)
- scripts/check-swift-format.sh (baseline violations in touched pre-existing/new KRMA-351/352 files; no violation on verification-added lines)
- production call-site search for AutoRegionalCorrections.plan/applying (present)
Findings:
- [fixed][diagnostics] Warm analysis-cache hits reused cached mask-generation duration, misreporting stale mask latency despite no mask work in the current invocation. ContentAwareAutoEngine now clamps maskSeconds to the current analysis window, with a cold/warm regression assertion and corrected release note.
- [non-blocking][performance] Debug end-to-end Auto remains above the rough 2-5s target (cold 6.561s, warm 5.917s); the existing KRMA-352 release note attributes this to renderer measurement, candidate renders, regional re-measurement, and Debug scoring. No correctness gate was relaxed.
- [non-blocking][baseline] The opt-in photo-analysis benchmark still shows the documented global-tone, masked-tone, and person-mask baseline drifts; required fast/serial lanes pass and the changed Auto path is not implicated.
Fixes:
- Clamped cached mask timing to the current invocation window in Sources/KromoraKit/Models/PhotoAnalysis/ContentAwareAutoEngine.swift.
- Added a warm-run mask-timing regression assertion in Tests/KromoraKitTests/AutoPerformanceDiagnosticsTests.swift.
- Updated docs/AUTO_PERFORMANCE.md so the warm mask measurement reflects cache-hit behavior.
Verification commits:
- None
Actor: codex
Resolved model: unknown
Pickup session: 01MTW8ORVON0HV4QFA

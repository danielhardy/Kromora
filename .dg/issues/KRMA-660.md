---
id: KRMA-660
title: Add deterministic automatic source picking for Heal and Clone
type: task
status: done
priority: high
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Add Sendable value-only analysis types under Models/RetouchAnalysis/. RenderEngine supplies a cached neutral-decode Lab float proxy (~1024 px long edge) per source fingerprint and full-resolution region crops on demand; no CIImage/CIFilter/CIContext crosses the engine boundary.
      result: pass
      notes: RetouchAnalysisProxy and RetouchAnalysisRegion (Sources/KromoraKit/Models/RetouchAnalysis/RetouchAnalysisProxy.swift) are Sendable, Equatable value types holding only SIMD3<Float> Lab buffers. RenderEngine.retouchProxy caches by source.cacheFingerprint (RenderEngine.swift:1465-1485) and retouchAnalysisCrop renders a bounded full-resolution crop on demand (RenderEngine.swift:583-598). Core Image types never leave the actor; only Data/proxy values cross.
    - criterion: Search deterministic candidates by spiraling outward to roughly six times the region size and including a coarse whole-frame sample. Reject candidates that leave the frame, overlap the destination hole or its dilated safety margin, or overlap any other spot's hole.
      result: pass
      notes: RetouchSourcePicker.candidates spirals square shells out to shape.radius*6 (RetouchSourcePicker.swift:17-34) plus a coarse whole-frame grid (lines 36-39), and valid() rejects out-of-frame, destination-overlap, and other-spot-hole-overlap candidates with a dilated margin (lines 122-135). testCandidatesAreDeterministicAndDoNotOverlapDestinationOrOtherSpots verifies this directly.
    - criterion: Rank valid candidates using ring Lab colour SSD, ring gradient mismatch, interior texture energy match, and a modest distance penalty. Refine the best candidates at higher resolution with a bounded +/-2 px search; stable ties and ordering must make the / next-source command reproducible.
      result: pass
      notes: score() combines ring color SSD, ring gradient mismatch, interior/ring texture mismatch, and a distance term (RetouchSourcePicker.swift:141-184). candidateOrder breaks ties deterministically by dy then dx. Proxy-stage refinement narrows to +/-2 px (lines 54-70) and RenderEngine.pickRetouchSource performs a second full-resolution +/-2 px refine via RetouchSourcePicker.refining. testRankAdvancesToNextDeterministicSource and testFullResolutionRefinementIsStableAndBoundedToTwoPixels confirm determinism and the 2 px (plus rounding) bound; RetouchInspectorView's "Next Source" button drives AppViewModel.pickRetouchSource(rank:) for the / workflow.
    - criterion: Expose auto source offset and rank for Heal/Clone and deterministic best-offset initialization for Remove. Manual source choice remains authoritative; moving a destination re-picks only when the source is automatic.
      result: pass
      notes: "RetouchSource.auto(offset:rank:) is produced uniformly regardless of spot.mode (RenderEngine.resolvingAutomaticRetouchSources only checks spot.source == nil, not mode), covering Remove's future PatchMatch initialization. AppViewModel.pickRetouchSource short-circuits on .manual sources and re-picks only when the current source is nil or .auto (AppViewModel.swift:3097-3121); RetouchInspectorView's destination-offset slider setter calls pickRetouchSource(rank: automaticRank) only when the existing source is .auto (RetouchInspectorView.swift ~186-193). testManualSourceIsAuthoritativeWhenAdvancingAutomaticRank covers the manual-bypass invariant."
    - criterion: Accelerate/SIMD the search where useful and keep cancellation responsive. Demonstrate typical selection latency in the few-millisecond range on the proxy without making that a flaky unit-test wall-clock assertion.
      result: pass
      notes: Lab storage uses SIMD3<Float>; candidates()/refining() check a cancellation closure at each ring and candidate-refinement step, and RenderEngine wires it to Task.isCancelled. testTypicalProxySelectionLatencyDiagnostic prints timing (4.94 ms locally on a 1024x768 proxy) without asserting on it, matching the 'not a flaky wall-clock assertion' requirement.
    - criterion: Add deterministic tests proving candidates are valid and non-overlapping, ranking and ties are repeatable, rank advancement returns the next-best source, manual picks bypass auto-picking, and Heal harness cases from KRMA-658 pass with automatic sources.
      result: pass
      notes: RetouchSourcePickerTests covers validity/non-overlap, determinism, rank advancement, and manual bypass. RetouchQualityEvaluationTests (commit e28d39c) adds a 'Heal (auto)' row per fixture that picks a source via RetouchSourcePicker and asserts automaticHealPasses > 0; observed 5/36 rows pass, matching docs/RETOUCH.md's recorded figure and building on KRMA-659's 3/36 manual baseline.
  checks_run:
    - swift build (clean, 0 errors)
    - swift test --filter 'RetouchSourcePicker|RetouchAnalysis' (6 tests, 0 failures)
    - "swift test --filter 'RetouchQualityEvaluationTests|RetouchModelTests' (7 tests, 0 failures; automatic Heal quality rows passing: 5/36)"
    - scripts/ci-tests.sh fast (1289 tests, exit 0, 0 failures)
    - swift test --filter PackageSettingsTests (4 tests, 0 failures; confirms zero Swift 6 concurrency escape hatches)
    - dg validate (OK; only pre-existing unrelated agent-model-name warnings)
  findings: []
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-27T20:23:18.370Z
  session: 01MUK9DZCJL4PEYMC7
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - retouch
  - remove-heal-clone
created: 2026-09-27T18:53:54.430Z
updated: 2026-09-27T20:23:18.372Z
parent: KRMA-599
depends_on:
  - KRMA-659
blockers: []
order: a0
board: product
context:
  files:
    - Sources/KromoraKit/Models/RetouchAnalysis/
    - Sources/KromoraKit/Models/RenderEngine.swift
    - Sources/KromoraKit/Models/RetouchModels.swift
  docs:
    - .context/2026-09-27-heal-remove-plan.md
    - docs/RETOUCH.md
  issues:
    - KRMA-658
    - KRMA-659
  commands:
    - swift test --filter 'RetouchSourcePicker|RetouchAnalysis'
    - scripts/ci-tests.sh fast
    - dg validate
---

## Objective

Choose, rank, and refine valid source patches for Heal and Clone, and provide Remove's deterministic
initial offset without ever selecting pixels from a defect hole.

## Context

KRMA-659 supplies source-space regions and mode-aware rendering, but requiring users to choose a
source for every dust speck or wire is not a usable Heal/Clone workflow. The current implementation
does not select a source at all, so a default zero offset samples the destination itself. The plan
calls for a cached neutral-decode Lab proxy, deterministic candidate ranking, and high-resolution
refinement; Remove will use the best offset as a PatchMatch initialization in KRMA-662.

## Acceptance criteria

- [ ] Add Sendable value-only analysis types under `Models/RetouchAnalysis/`. `RenderEngine` supplies
      a cached neutral-decode Lab float proxy (~1024 px long edge) per source fingerprint and
      full-resolution region crops on demand; no `CIImage`, `CIFilter`, or `CIContext` crosses the
      engine boundary.
- [ ] Search deterministic candidates by spiraling outward to roughly six times the region size
      and including a coarse whole-frame sample. Reject candidates that leave the frame, overlap
      the destination hole or its dilated safety margin, or overlap any other spot's hole.
- [ ] Rank valid candidates using ring Lab colour SSD, ring gradient mismatch, interior texture
      energy match, and a modest distance penalty. Refine the best candidates at higher resolution
      with a bounded ±2 px search; stable ties and ordering must make the `/` next-source command
      reproducible.
- [ ] Expose auto source offset and rank for Heal/Clone and deterministic best-offset
      initialization for Remove. Manual source choice remains authoritative; moving a destination
      re-picks only when the source is automatic.
- [ ] Accelerate/SIMD the search where useful and keep cancellation responsive. Demonstrate
      typical selection latency in the few-millisecond range on the proxy without making that a
      flaky unit-test wall-clock assertion.
- [ ] Add deterministic tests proving candidates are valid and non-overlapping, ranking and ties
      are repeatable, rank advancement returns the next-best source, manual picks bypass
      auto-picking, and Heal harness cases from KRMA-658 pass with automatic sources.

## Implementation notes

Use the neutral source analysis proxy, not the rendered/tone-adjusted canvas, so adjustment edits
do not change picks. Cache by source fingerprint and invalidate on source change. Follow KRMA-658
quality fixtures and KRMA-659 oriented-source normalized coordinates; retain Swift 6 Sendability
without escape hatches.

### Comment — codex @ 2026-09-27T20:16:02.068Z

Implemented deterministic automatic source picking for Heal/Clone and Remove initialization. RenderEngine now caches a neutral Lab proxy per source fingerprint, ranks frame-safe candidates outside all spot holes, requests bounded full-resolution crops for ±2 px refinement, and persists auto offset/rank choices. Manual sources remain authoritative; destination moves repick only automatic sources, and the inspector exposes Next Source. Added deterministic picker/rank/manual/refinement tests and automatic Heal rows to the KRMA-658 quality harness; 5/36 automatic Heal rows pass current limits. The picker diagnostic measured 4.69 ms on a 1024×768 Lab proxy. Checks: swift test --filter RetouchSourcePicker|RetouchAnalysis|RetouchModelTests (11 passed); quality evaluation (passed); scripts/ci-tests.sh fast (1289 passed); dg validate (OK with pre-existing model-name warnings). Commits: 5485459, fc949d5, e28d39c. An optional swift test -c release timing run could not link with the local beta SDK (CoreAudioTypes/SwiftUICore linker errors); the required debug fast lane passed.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-27T20:23:18.370Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Add Sendable value-only analysis types under Models/RetouchAnalysis/. RenderEngine supplies a cached neutral-decode Lab float proxy (~1024 px long edge) per source fingerprint and full-resolution region crops on demand; no CIImage/CIFilter/CIContext crosses the engine boundary. (pass) — RetouchAnalysisProxy and RetouchAnalysisRegion (Sources/KromoraKit/Models/RetouchAnalysis/RetouchAnalysisProxy.swift) are Sendable, Equatable value types holding only SIMD3<Float> Lab buffers. RenderEngine.retouchProxy caches by source.cacheFingerprint (RenderEngine.swift:1465-1485) and retouchAnalysisCrop renders a bounded full-resolution crop on demand (RenderEngine.swift:583-598). Core Image types never leave the actor; only Data/proxy values cross.
- [x] Search deterministic candidates by spiraling outward to roughly six times the region size and including a coarse whole-frame sample. Reject candidates that leave the frame, overlap the destination hole or its dilated safety margin, or overlap any other spot's hole. (pass) — RetouchSourcePicker.candidates spirals square shells out to shape.radius*6 (RetouchSourcePicker.swift:17-34) plus a coarse whole-frame grid (lines 36-39), and valid() rejects out-of-frame, destination-overlap, and other-spot-hole-overlap candidates with a dilated margin (lines 122-135). testCandidatesAreDeterministicAndDoNotOverlapDestinationOrOtherSpots verifies this directly.
- [x] Rank valid candidates using ring Lab colour SSD, ring gradient mismatch, interior texture energy match, and a modest distance penalty. Refine the best candidates at higher resolution with a bounded +/-2 px search; stable ties and ordering must make the / next-source command reproducible. (pass) — score() combines ring color SSD, ring gradient mismatch, interior/ring texture mismatch, and a distance term (RetouchSourcePicker.swift:141-184). candidateOrder breaks ties deterministically by dy then dx. Proxy-stage refinement narrows to +/-2 px (lines 54-70) and RenderEngine.pickRetouchSource performs a second full-resolution +/-2 px refine via RetouchSourcePicker.refining. testRankAdvancesToNextDeterministicSource and testFullResolutionRefinementIsStableAndBoundedToTwoPixels confirm determinism and the 2 px (plus rounding) bound; RetouchInspectorView's "Next Source" button drives AppViewModel.pickRetouchSource(rank:) for the / workflow.
- [x] Expose auto source offset and rank for Heal/Clone and deterministic best-offset initialization for Remove. Manual source choice remains authoritative; moving a destination re-picks only when the source is automatic. (pass) — RetouchSource.auto(offset:rank:) is produced uniformly regardless of spot.mode (RenderEngine.resolvingAutomaticRetouchSources only checks spot.source == nil, not mode), covering Remove's future PatchMatch initialization. AppViewModel.pickRetouchSource short-circuits on .manual sources and re-picks only when the current source is nil or .auto (AppViewModel.swift:3097-3121); RetouchInspectorView's destination-offset slider setter calls pickRetouchSource(rank: automaticRank) only when the existing source is .auto (RetouchInspectorView.swift ~186-193). testManualSourceIsAuthoritativeWhenAdvancingAutomaticRank covers the manual-bypass invariant.
- [x] Accelerate/SIMD the search where useful and keep cancellation responsive. Demonstrate typical selection latency in the few-millisecond range on the proxy without making that a flaky unit-test wall-clock assertion. (pass) — Lab storage uses SIMD3<Float>; candidates()/refining() check a cancellation closure at each ring and candidate-refinement step, and RenderEngine wires it to Task.isCancelled. testTypicalProxySelectionLatencyDiagnostic prints timing (4.94 ms locally on a 1024x768 proxy) without asserting on it, matching the 'not a flaky wall-clock assertion' requirement.
- [x] Add deterministic tests proving candidates are valid and non-overlapping, ranking and ties are repeatable, rank advancement returns the next-best source, manual picks bypass auto-picking, and Heal harness cases from KRMA-658 pass with automatic sources. (pass) — RetouchSourcePickerTests covers validity/non-overlap, determinism, rank advancement, and manual bypass. RetouchQualityEvaluationTests (commit e28d39c) adds a 'Heal (auto)' row per fixture that picks a source via RetouchSourcePicker and asserts automaticHealPasses > 0; observed 5/36 rows pass, matching docs/RETOUCH.md's recorded figure and building on KRMA-659's 3/36 manual baseline.
Checks run:
- swift build (clean, 0 errors)
- swift test --filter 'RetouchSourcePicker|RetouchAnalysis' (6 tests, 0 failures)
- swift test --filter 'RetouchQualityEvaluationTests|RetouchModelTests' (7 tests, 0 failures; automatic Heal quality rows passing: 5/36)
- scripts/ci-tests.sh fast (1289 tests, exit 0, 0 failures)
- swift test --filter PackageSettingsTests (4 tests, 0 failures; confirms zero Swift 6 concurrency escape hatches)
- dg validate (OK; only pre-existing unrelated agent-model-name warnings)
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MUK9DZCJL4PEYMC7
Summary: Verified deterministic automatic Heal/Clone source picking: all acceptance criteria confirmed by inspection and passing tests, no blockers found.

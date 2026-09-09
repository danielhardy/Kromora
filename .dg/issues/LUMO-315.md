---
id: LUMO-315
title: Add required acceptance tests for GPU-backed processing prefix (LUMO-304)
type: task
status: done
priority: urgent
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: "NoCPUUploadOnLUTTickTest: a LUT/grain-only change on a warm developed source performs zero CPU allocs and zero re-uploads (mock-context counters == 0)."
      result: pass
      notes: testNoCPUUploadOnLUTTickTest asserts processingPrefixCPUReadbacks and processingPrefixTextureSubmissions deltas are 0 across the second tick, and that the prefix cache records exactly one hit. Passed.
    - criterion: "PrefixPixelParityTest: texture-backed prefix output vs CPU reference path output are pixel-equal within 1 LSB."
      result: pass
      notes: testPrefixPixelParityTest runs the same request through a normal (texture) RenderEngine and an injected-CIContext (CPU) RenderEngine and asserts pixel equality within tolerance 1, plus asserts each engine only exercised its own path (texture submissions vs CPU readbacks). Passed.
    - criterion: "NonGPUFallbackTest: forcing the non-GPU conformer keeps output correct and exercises the materializedPrefixImage -> materializedImage fallback branch."
      result: pass
      notes: "testNonGPUFallbackTest uses RenderEngine(context: CIContext()) to force the fallback, asserts pixel parity against the normal engine, and asserts processingPrefixCPUReadbacks == 1 / processingPrefixTextureSubmissions == 0, confirming the CPU branch actually ran. Passed."
    - criterion: "PressureEvictsTexturePrefixTest: simulated memory warning evicts texture-backed prefix entries (count == 0, bytes == 0)."
      result: pass
      notes: testPressureEvictsTexturePrefixTest warms the prefix cache, calls evictForMemoryPressure(), and asserts processingPrefix cache count/costBytes drop to 0 with evictions >= 1. Passed.
    - criterion: "SettledPublishCountTest: one settle produces exactly one publication with a non-nil frame; a concurrent invalidate during the new async commitAndWaitForCompletion re-entrancy window cannot cause a double publish or a stale/duplicate cache insert."
      result: pass
      notes: testSettledPublishCountTest installs a one-shot processingPrefixCompletionHook that pauses inside the actor re-entrancy window opened by the new `await commitAndWaitForCompletion` suspension, calls engine.invalidateRenderCaches() while paused (exercising cancelProcessingPrefixFlights(), which was added in the same commit specifically to close this window), then releases. Asserts exactly one publication, a non-nil frame, and processingPrefix cache count == 0 (the stale flight's token no longer matches after invalidation, so its result is discarded rather than inserted). Verified stable across 5 repeated runs.
  checks_run:
    - swift build (clean, zero warnings)
    - swift test --filter RenderEngineProcessingPrefixAcceptanceTests (5/5 passed; testSettledPublishCountTest re-run 5x, stable)
    - swift test --filter 'RenderEngineTests|PreviewCoordinatorTests|RenderCacheTests' (73 passed, 5 skipped, matches implementer's claimed 29/13/31)
    - "swift test --filter PackageSettingsTests (3/3 passed: Swift 6 mode, tools version, zero concurrency escape hatches)"
    - "scripts/ci-tests.sh fast lane equivalent: swift test --parallel --skip (serial+optional suites) (682 passed, 0 failures)"
    - "scripts/ci-tests.sh serial lane equivalent: swift test --no-parallel --filter (serial suites) --skip (optional) (306 executed, 9 skipped, 2 pre-existing failures unrelated to this change)"
  findings:
    - "Non-blocking, pre-existing: LUTWorkflowTests.testExternalImportCanBeSelectedByIDAndSendsItThroughPreviewRequest and PreviewCutoverTests.testOpeningStoredEditsSpeculatesThenSubmitsTheStoredDocument fail intermittently on timing assertions against FakeRenderEngine/dirty-worktree state; neither test touches RenderEngine.swift or the new acceptance-test file. This matches the pre-existing failures already documented in LUMO-304's completion comment and blocker note, predating commit 88e6008. No child ticket filed since it is already tracked history, not new."
  fixes: []
  verification_commits:
    - bca796a
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-09T13:41:12.445Z
  session: 01MTU53QK5WLFM8Z75
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - verification
created: 2026-09-09T10:33:00.506Z
updated: 2026-09-09T13:41:12.447Z
parent: LUMO-304
order: a0
board: product
commits:
  - bca796a
---

## Objective

Add the five acceptance-criteria tests LUMO-304 specified but shipped without, covering the
texture-backed processing-prefix path added in commit 88e6008.

## Context

LUMO-304 ("Keep processing prefixes on the GPU") listed five named acceptance tests as
done-criteria. Verification of that issue found the implementation commit (88e6008) touched only
`RenderEngine.swift`, `RenderEngineResources.swift`, and `BoundedCache.swift` — zero test files.
None of the five named tests exist anywhere in the repo. The implementer's completion comment
claims "focused Metal texture tests passed," but no such tests are present, and the pre-existing
`RenderCacheTests` suite (22/22) does not exercise this behavior — it predates the change.

## Acceptance criteria

- [ ] `NoCPUUploadOnLUTTickTest`: with a warm developed source, a LUT/grain-only change performs
      zero `toBitmap` CPU allocs and zero re-uploads (instrumented mock-context counters == 0).
- [ ] `PrefixPixelParityTest`: texture-backed prefix output vs CPU reference path output are
      pixel-equal within 1 LSB on the fixture set.
- [ ] `NonGPUFallbackTest`: with the non-GPU conformer forced, output is correct and the CPU path
      still exists (fallback branch coverage asserted) — this exercises the
      `materializedPrefixImage` fallback to `materializedImage` when `commandQueue`/texture
      allocation fails.
- [ ] `PressureEvictsTexturePrefixTest`: simulated memory warning evicts texture-backed prefix
      entries (count == 0, bytes == 0) via `RenderEngine.evictForMemoryPressure()`.
- [ ] `SettledPublishCountTest`: one settle produces exactly one publication with a non-nil frame
      (flicker/blank ruled out by log assertion). Pay particular attention to the new `await
      commitAndWaitForCompletion(...)` suspension point inside `processingPrefix(...)` (now
      `async`) — this is a new actor-reentrancy window between building the prefix and inserting it
      into `processingPrefixCache` that did not exist when `materializedImage` was synchronous;
      confirm a concurrent invalidate/settle during that window cannot cause a double publish or a
      stale/duplicate cache insert.

## Implementation notes

- Touch points: `Sources/LumoKit/Models/RenderEngine.swift` (`materializedPrefixImage`,
  `processingPrefix`, `materializedImage` CPU fallback), `RenderEngineResources.swift`
  (`makeProcessingTexture`).
- `swift build` is clean and the change is otherwise localized and reasonable; this ticket is
  test-coverage-only, not a design objection.

### Comment — codex @ 2026-09-09T13:34:07.030Z

Implemented in bca796a. Added all five GPU processing-prefix acceptance tests: zero CPU readbacks/reuploads on LUT-only ticks, GPU/CPU pixel parity, forced CPU fallback, memory-pressure eviction, and exactly-once settled publication under concurrent invalidation. Added diagnostic counters and fixed in-flight prefix cancellation on invalidation to prevent stale cache insertion. Verification: focused acceptance suite 5/5, RenderEngineTests 29/29, PreviewCoordinatorTests 13/13, RenderCacheTests 31/31, and swift build passed. The broader suite still has the three pre-existing PreviewCutover/LUTWorkflow timing/assertion failures documented in the issue context.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-09T13:41:12.445Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] NoCPUUploadOnLUTTickTest: a LUT/grain-only change on a warm developed source performs zero CPU allocs and zero re-uploads (mock-context counters == 0). (pass) — testNoCPUUploadOnLUTTickTest asserts processingPrefixCPUReadbacks and processingPrefixTextureSubmissions deltas are 0 across the second tick, and that the prefix cache records exactly one hit. Passed.
- [x] PrefixPixelParityTest: texture-backed prefix output vs CPU reference path output are pixel-equal within 1 LSB. (pass) — testPrefixPixelParityTest runs the same request through a normal (texture) RenderEngine and an injected-CIContext (CPU) RenderEngine and asserts pixel equality within tolerance 1, plus asserts each engine only exercised its own path (texture submissions vs CPU readbacks). Passed.
- [x] NonGPUFallbackTest: forcing the non-GPU conformer keeps output correct and exercises the materializedPrefixImage -> materializedImage fallback branch. (pass) — testNonGPUFallbackTest uses RenderEngine(context: CIContext()) to force the fallback, asserts pixel parity against the normal engine, and asserts processingPrefixCPUReadbacks == 1 / processingPrefixTextureSubmissions == 0, confirming the CPU branch actually ran. Passed.
- [x] PressureEvictsTexturePrefixTest: simulated memory warning evicts texture-backed prefix entries (count == 0, bytes == 0). (pass) — testPressureEvictsTexturePrefixTest warms the prefix cache, calls evictForMemoryPressure(), and asserts processingPrefix cache count/costBytes drop to 0 with evictions >= 1. Passed.
- [x] SettledPublishCountTest: one settle produces exactly one publication with a non-nil frame; a concurrent invalidate during the new async commitAndWaitForCompletion re-entrancy window cannot cause a double publish or a stale/duplicate cache insert. (pass) — testSettledPublishCountTest installs a one-shot processingPrefixCompletionHook that pauses inside the actor re-entrancy window opened by the new `await commitAndWaitForCompletion` suspension, calls engine.invalidateRenderCaches() while paused (exercising cancelProcessingPrefixFlights(), which was added in the same commit specifically to close this window), then releases. Asserts exactly one publication, a non-nil frame, and processingPrefix cache count == 0 (the stale flight's token no longer matches after invalidation, so its result is discarded rather than inserted). Verified stable across 5 repeated runs.
Checks run:
- swift build (clean, zero warnings)
- swift test --filter RenderEngineProcessingPrefixAcceptanceTests (5/5 passed; testSettledPublishCountTest re-run 5x, stable)
- swift test --filter 'RenderEngineTests|PreviewCoordinatorTests|RenderCacheTests' (73 passed, 5 skipped, matches implementer's claimed 29/13/31)
- swift test --filter PackageSettingsTests (3/3 passed: Swift 6 mode, tools version, zero concurrency escape hatches)
- scripts/ci-tests.sh fast lane equivalent: swift test --parallel --skip (serial+optional suites) (682 passed, 0 failures)
- scripts/ci-tests.sh serial lane equivalent: swift test --no-parallel --filter (serial suites) --skip (optional) (306 executed, 9 skipped, 2 pre-existing failures unrelated to this change)
Findings:
- Non-blocking, pre-existing: LUTWorkflowTests.testExternalImportCanBeSelectedByIDAndSendsItThroughPreviewRequest and PreviewCutoverTests.testOpeningStoredEditsSpeculatesThenSubmitsTheStoredDocument fail intermittently on timing assertions against FakeRenderEngine/dirty-worktree state; neither test touches RenderEngine.swift or the new acceptance-test file. This matches the pre-existing failures already documented in LUMO-304's completion comment and blocker note, predating commit 88e6008. No child ticket filed since it is already tracked history, not new.
Fixes:
- None
Verification commits:
- bca796a
Actor: claude
Resolved model: sonnet
Pickup session: 01MTU53QK5WLFM8Z75
Summary: Verified: all five named acceptance tests (NoCPUUploadOnLUTTickTest, PrefixPixelParityTest, NonGPUFallbackTest, PressureEvictsTexturePrefixTest, SettledPublishCountTest) exist, are correct, and pass reliably; no fixes needed.

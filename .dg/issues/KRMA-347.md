---
id: KRMA-347
title: Build the asynchronous bounded Auto candidate coordinator and selector
type: feature
status: done
priority: urgent
agent: pi
model: openrouter/meta/muse-spark-1.3-contributor
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Candidate generation and evaluation are asynchronous, cancellable, and actor-safe; the policy remains pure
      result: pass
    - criterion: Unchanged, native, Apple-reference, and reduced-strength candidates are represented explicitly with provenance
      result: pass
    - criterion: Render budget counters are observable and hard-bounded (24 small renders, 4 RAW redevelopments)
      result: pass
    - criterion: Scoring uses frozen targets and separate global/important-region metrics; missing regional evidence degrades rather than fabricating
      result: pass
    - criterion: Candidates violating clipping, color, or mask-edge guardrails are rejected even if their aggregate score is higher
      result: pass
    - criterion: The unchanged candidate wins when improvement is negligible
      result: pass
    - criterion: Cancellation, navigation, revision mismatch, render failure, and validation failure return without applying edits and without leaking tasks/caches
      result: pass
    - criterion: Focused tests verify candidate ordering, budget limits, tie-breaking, RAW cap, cancellation, stale revision, guardrail rejection, and unchanged-wins behavior
      result: pass
  checks_run:
    - swift build — clean
    - swift test --filter AutoEnhancementCoordinatorTests — 19/19 green (18 original + 1 added)
    - scripts/ci-tests.sh fast — 807 tests, 0 failures
    - scripts/ci-tests.sh serial — 328 tests, 0 failures
    - git diff --check — clean
    - manual grep for @unchecked Sendable / nonisolated(unsafe) / @preconcurrency — none found
  findings:
    - "Test-coverage gap (fixed): the mask-edge guardrail (AutoCandidateScoring.maskEdgeRejectionCap, score.swift:588) had no direct unit test — only clipping and saturation guardrails were exercised. Added testMaskEdgeGuardrailRejectsSpikyContrastWhenMasksWereAdded, which drives a real contrast-spike render through AutoCandidateScoring.score with addedMaskCount>0 and confirms rejection, plus confirms the same spike does not reject when no masks were added. Low severity: v1 proposals never set addedMaskCount>0 (KRMA-348 owns mask creation), so this path was previously untested but not reachable in production yet."
  fixes:
    - Added AutoEnhancementCoordinatorTests.testMaskEdgeGuardrailRejectsSpikyContrastWhenMasksWereAdded (test-only; no production code changed)
  verification_commits:
    - 854beac
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-10T19:38:35.741Z
  session: 01MTVXGBUCL3TOGLB5
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - auto
  - rendering
  - performance
created: 2026-09-10T14:40:07.179Z
updated: 2026-09-10T19:38:35.744Z
depends_on:
  - KRMA-342
  - KRMA-344
  - KRMA-345
  - KRMA-346
order: a0
board: product
commits:
  - 854beac
---

## Parent epic

KRMA-341 — Content-aware Auto engine and renderer-backed candidate evaluation.


## Objective

Introduce an asynchronous `AutoEnhancementCoordinator` and bounded candidate evaluator that turns native and Apple-reference proposals into a validated editable result through the real renderer.

## Scope

- Always include the unchanged current document as a candidate.
- Generate the native proposal, Apple-reference proposal when available, and reduced-strength alternatives.
- Freeze source/document revisions, analysis facts, scene intent, confidence, and targets for the entire run; candidates must not redefine their own evaluation targets.
- Apply proposals to a copy, render through `RenderEngine`, and score important-region exposure, clipping, neutral-color error where supported, excessive saturation, lost contrast, noise amplification, and mask-edge artifacts.
- Penalize unnecessary movement from the current edit, changed-control count, and mask count. Prefer the simpler candidate when quality is effectively tied.
- Enforce a maximum of 24 small candidate renders and no more than four expensive RAW redevelopments. Stop on convergence or a time budget and select the best completed acceptable candidate.
- Reject guardrail violations and return a structured no-acceptable-candidate result without mutating the document.

## Acceptance criteria

- [ ] Candidate generation and evaluation are asynchronous, cancellable, and actor-safe; the policy remains pure.
- [ ] Unchanged, native, Apple-reference, and reduced-strength candidates are represented explicitly with provenance.
- [ ] Render budget counters are observable and hard-bounded (24 total small renders, 4 RAW redevelopments unless a documented configuration overrides them for tests).
- [ ] Scoring uses frozen targets and separate global/important-region metrics; missing regional evidence degrades the score rather than fabricating it.
- [ ] Candidates violating clipping, color, or mask-edge guardrails are rejected even if their aggregate score is higher.
- [ ] The unchanged candidate wins when improvement is negligible, and the result says no further improvement was found.
- [ ] Cancellation, navigation, revision mismatch, render failure, and validation failure return without applying edits and without leaking tasks/caches.
- [ ] Focused tests verify candidate ordering, budget limits, tie-breaking, RAW cap, cancellation, stale revision, guardrail rejection, and unchanged-wins behavior.

## Non-goals

- Do not persist the result or change UI state here.
- Do not add local corrections beyond consuming proposal metadata; KRMA-348 owns mask creation.
- Do not use Apple aesthetics score for production selection.

## Likely files

- `Sources/KromoraKit/Models/AutoAdjustment.swift`
- `Sources/KromoraKit/Models/PhotoAnalysis/PhotoAnalysisCoordinator.swift`
- `Sources/KromoraKit/Models/RenderEngine.swift`
- `Sources/KromoraKit/Models/RenderRequest.swift`
- `Sources/KromoraKit/Models/ImageWorkScheduler.swift`
- `Sources/KromoraKit/Models/RenderCacheKey.swift`
- `Tests/KromoraKitTests/`

## Verification

Use fake/injected renderers for deterministic budget and failure tests, plus at least one actual-render fixture test. Measure candidate counts and cancellation completion in the fast lane.


### Comment — pi @ 2026-09-10T19:35:33.337Z

Implementation complete on main (working tree; 1 production file + 1 test file, +~1500 lines). Asynchronous bounded Auto candidate coordinator and selector:

What was built
- AutoEnhancementCoordinator.swift (new): AutoCandidateProvenance (unchanged/native/apple-reference/reduced-strength with provenance), pure AutoCandidateGenerator (unchanged always index zero, full-strength proposals, 50% reduced fallbacks, no-ops contribute nothing), frozen AutoEvaluationTargets (intent-preserving 0.48 placement pulled toward baseline by high/low-key/night evidence, neutral reference gated on credible non-mixed evidence, top-4 important regions by measured support), pure AutoCandidateScoring (global + important-region exposure from the candidate's own pixels, clipping/neutral/saturation/contrast-loss/noise/mask-edge-proxy/movement/complexity terms, missing evidence degrades via explicit penalty), hard-bounded AutoCoordinatorConfiguration (24 small renders, 4 RAW redevelopments, 8s time budget, improvement/tie/convergence tuning — overridable per-run as the documented test seam), and the Sendable AutoEnhancementCoordinator struct over the narrow CurrentEditSampling seam (RenderEngine in production; no CIImage/CIFilter crosses the boundary).
- Selection: guardrail rejection (clipping/color/mask-edge) even when the total wins; unchanged never rejected; tie-break prefers fewer controls then fewer masks then generation order; negligible improvement returns unchanged with a 'no further improvement' message; all-changed-rejected returns structured noCandidate; cancellation/staleness/render-failure return without applying and without task/cache leaks (sequential evaluation, revision checked at start, per-candidate, and pre-selection).
- 18 AutoEnhancementCoordinatorTests green: ordering, no-op exclusion, range clamping, low-key intent freeze, missing-evidence degradation, unmeasurable-render rejection, clipping guardrail (+ unchanged never rejected), improved selection, unchanged-wins negligible, all-rejected noCandidate, tie-break simplicity, small-render cap, RAW cap, zero time budget, stale revision (zero renders), gated-sampler mid-run cancellation, plus one real-RenderEngine gradient-fixture run proving the production seam.

Verification: 18/18 focused green; scripts/ci-tests.sh fast exit 0 (807 tests); scripts/ci-tests.sh serial exit 0; swift build clean (only pre-existing kernel deprecation warnings); git diff --check clean; no Swift 6 escape hatches. No persistence/UI changes, no mask creation (KRMA-348), no aesthetics-score selection per non-goals.

## Agent log

- 2026-09-10T19:38:35.742Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Candidate generation and evaluation are asynchronous, cancellable, and actor-safe; the policy remains pure (pass)
- [x] Unchanged, native, Apple-reference, and reduced-strength candidates are represented explicitly with provenance (pass)
- [x] Render budget counters are observable and hard-bounded (24 small renders, 4 RAW redevelopments) (pass)
- [x] Scoring uses frozen targets and separate global/important-region metrics; missing regional evidence degrades rather than fabricating (pass)
- [x] Candidates violating clipping, color, or mask-edge guardrails are rejected even if their aggregate score is higher (pass)
- [x] The unchanged candidate wins when improvement is negligible (pass)
- [x] Cancellation, navigation, revision mismatch, render failure, and validation failure return without applying edits and without leaking tasks/caches (pass)
- [x] Focused tests verify candidate ordering, budget limits, tie-breaking, RAW cap, cancellation, stale revision, guardrail rejection, and unchanged-wins behavior (pass)
Checks run:
- swift build — clean
- swift test --filter AutoEnhancementCoordinatorTests — 19/19 green (18 original + 1 added)
- scripts/ci-tests.sh fast — 807 tests, 0 failures
- scripts/ci-tests.sh serial — 328 tests, 0 failures
- git diff --check — clean
- manual grep for @unchecked Sendable / nonisolated(unsafe) / @preconcurrency — none found
Findings:
- Test-coverage gap (fixed): the mask-edge guardrail (AutoCandidateScoring.maskEdgeRejectionCap, score.swift:588) had no direct unit test — only clipping and saturation guardrails were exercised. Added testMaskEdgeGuardrailRejectsSpikyContrastWhenMasksWereAdded, which drives a real contrast-spike render through AutoCandidateScoring.score with addedMaskCount>0 and confirms rejection, plus confirms the same spike does not reject when no masks were added. Low severity: v1 proposals never set addedMaskCount>0 (KRMA-348 owns mask creation), so this path was previously untested but not reachable in production yet.
Fixes:
- Added AutoEnhancementCoordinatorTests.testMaskEdgeGuardrailRejectsSpikyContrastWhenMasksWereAdded (test-only; no production code changed)
Verification commits:
- 854beac
Actor: claude
Resolved model: sonnet
Pickup session: 01MTVXGBUCL3TOGLB5
Summary: Independent verification pass: coordinator matches spec, all budgets/guardrails/cancellation paths hold under fast+serial CI (1135 tests green); added missing mask-edge guardrail unit test.

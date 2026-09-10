---
id: KRMA-347
title: Build the asynchronous bounded Auto candidate coordinator and selector
type: feature
status: ready
priority: urgent
agent: pi
model: openrouter/meta/muse-spark-1.3-contributor
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - auto
  - rendering
  - performance
created: 2026-09-10T14:40:07.179Z
updated: 2026-09-10T14:53:41.668Z
depends_on:
  - KRMA-342
  - KRMA-344
  - KRMA-345
  - KRMA-346
order: zv
board: product
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

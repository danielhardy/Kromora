---
id: KRMA-346
title: Add Core Image automatic-enhancement reference proposal fitting
type: feature
status: done
priority: high
agent: pi
model: openrouter/meta/muse-spark-1.3-contributor
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Core Image automatic enhancement is invoked through a testable internal adapter with no network or third-party dependency
      result: pass
    - criterion: The adapter returns a value-only reference/provenance result and never stores CI filters as the user's edit
      result: pass
    - criterion: Reference intent is fitted through Kromora's existing exposure/tone/color/white-balance mappings with bounded residual error; unsupported effects are omitted and reported
      result: pass
    - criterion: RAW and standard-image inputs use the correct source/render color space and white-balance direction
      result: pass
    - criterion: Existing Looks/LUTs, grading, curves, masks, crop, and decorative effects are not lost while producing the reference proposal
      result: pass
    - criterion: Unsupported OS/API, malformed image, and Core Image failure paths return a graceful unavailable result and do not block native proposals
      result: pass
    - criterion: Focused tests cover deterministic fixtures, unavailable/failure paths, provenance, and no opaque-filter persistence
      result: pass
  checks_run:
    - swift build — clean, 0 diagnostics
    - swift test --filter AppleEnhancementReferenceTests — 21 passed, 0 failures
    - scripts/ci-tests.sh fast — 789 tests, 0 failures
    - scripts/ci-tests.sh serial — 328 tests, 0 failures
    - git diff --check — clean
    - dg validate — OK (pre-existing unrelated warnings only)
    - grep for @unchecked Sendable / nonisolated(unsafe) / @preconcurrency / force-unwraps in the new file — none found
    - git status --porcelain — clean tree aside from pre-existing .dg bookkeeping churn
  findings: []
  fixes: []
  verification_commits:
    - d424821
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-10T19:20:16.817Z
  session: 01MTVWR2Q36U6IMH2L
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - auto
  - apple-frameworks
  - rendering
created: 2026-09-10T14:40:05.868Z
updated: 2026-09-10T19:20:16.820Z
depends_on:
  - KRMA-342
  - KRMA-343
  - KRMA-345
order: a0
board: product
commits:
  - d424821
---

## Parent epic

KRMA-341 — Content-aware Auto engine and renderer-backed candidate evaluation.


## Objective

Add an Apple-frameworks-first proposal source using Core Image's automatic enhancement suggestions, then fit that reference through Kromora's editable controls instead of persisting an opaque filter stack.

## Scope

- Add an internal adapter around Core Image automatic enhancement analysis/rendering that is isolated from the policy and coordinator.
- Treat the Apple output as a reference proposal, not authoritative truth and not a persisted filter chain.
- Compare the reference render or filter intent to Kromora-supported controls and return a bounded value-only proposal with provenance and confidence.
- Respect the analysis view exclusions and restore the complete edit for final evaluation.
- Keep the adapter available only on supported Apple OS/runtime combinations and return an explicit unavailable result otherwise.

## Acceptance criteria

- [ ] Core Image automatic enhancement is invoked through a testable internal adapter with no network or third-party dependency.
- [ ] The adapter returns a value-only reference/provenance result and never stores CI filters as the user's edit.
- [ ] Reference intent is fitted through Kromora's existing exposure/tone/color/white-balance mappings with bounded residual error; unsupported effects are omitted and reported.
- [ ] RAW and standard-image inputs use the correct source/render color space and white-balance direction.
- [ ] Existing Looks/LUTs, grading, curves, masks, crop, and decorative effects are not lost while producing the reference proposal.
- [ ] Unsupported OS/API, malformed image, and Core Image failure paths return a graceful unavailable result and do not block native proposals.
- [ ] Focused tests cover deterministic fixtures, unavailable/failure paths, provenance, and no opaque-filter persistence.

## Non-goals

- Do not ship a Core ML model in this ticket.
- Do not select the final candidate here.
- Do not claim the Apple reference is perceptually superior for every image.

## Likely files

- `Sources/KromoraKit/Models/RenderEngine.swift`
- `Sources/KromoraKit/Models/RenderEngineResources.swift`
- `Sources/KromoraKit/Models/RenderRequest.swift`
- `Sources/KromoraKit/Models/PhotoAnalysis/`
- `Sources/KromoraKit/Models/AutoAdjustment.swift`
- `Tests/KromoraKitTests/`

## Verification

Run focused Core Image/reference tests on the supported macOS SDK and confirm the standard test lane still builds on the minimum deployment target.


### Comment — pi @ 2026-09-10T19:15:40.302Z

Implementation complete on branch krma-346-apple-reference at d424821 (3 files, +1659/-2). Core Image automatic-enhancement reference fitting:

What was built
- AppleEnhancementReference.swift (new): CIAutoAdjustmentDescriptor around CIImage.autoAdjustmentFilters() — the sole Core Image boundary, method-local CIImage/CIFilter/CIContext, value-only AppleSuggestedEffect + reference pixels out (probed on macOS 26 SDK: CIVibrance/CIToneCurve/CIHighlightShadowAdjust; red-eye/face/crop map to .unsupported). Pure deterministic AppleReferenceFitter compares reference vs baseline pixels through the existing RenderedPixelAnalyzer tone/color mappings and reproduces the delta via exposure (±1.25 EV), damped residual tails, WB with pinned RAW-photographic vs standard-inverted direction, and restrained vibrance/saturation; dehaze/curves/mixer never fitted. AppleReferenceProposal carries only editable Kromora values + provenance (filter names, omitted effects, fit method, strength, analysis/complete hashes, bounded residual, capped confidence); every failure is an explicit .unavailable code that never blocks native proposals.
- Adapter renders the analysis-view document as the fitting baseline (LUT/grading/grain/vignette excluded) and applies fitted values onto the complete edit, preserving finish byte-for-byte.
- RenderStackTests: AppleEnhancementReference.swift added to the one-shot-sampler allowlist with justification (method-local uncached context, once per Auto invocation, outside the live graph).
- 21 AppleEnhancementReferenceTests green (range/invariant assertions): pinned filter mapping incl. NaN sanitization, all six unavailable paths, exposure/WB-direction fitting, finish preservation + analysis-view sampler assertion + provenance hashes, mixed-frame WB omission, unsupported-effect reporting, intent-only fallback, production-descriptor graceful structure on a real gradient, determinism.

Verification: 21/21 focused green; neighboring Auto suites green; scripts/ci-tests.sh fast exit 0; serial 328 tests 0 failures; swift build clean (only pre-existing kernel deprecation warnings); dg validate OK; git diff --check clean; no Sendable opt-outs. No image leaves the device; no Core ML model; no candidate selection (KRMA-347 owns that).

## Agent log

- 2026-09-10T19:20:16.818Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Core Image automatic enhancement is invoked through a testable internal adapter with no network or third-party dependency (pass)
- [x] The adapter returns a value-only reference/provenance result and never stores CI filters as the user's edit (pass)
- [x] Reference intent is fitted through Kromora's existing exposure/tone/color/white-balance mappings with bounded residual error; unsupported effects are omitted and reported (pass)
- [x] RAW and standard-image inputs use the correct source/render color space and white-balance direction (pass)
- [x] Existing Looks/LUTs, grading, curves, masks, crop, and decorative effects are not lost while producing the reference proposal (pass)
- [x] Unsupported OS/API, malformed image, and Core Image failure paths return a graceful unavailable result and do not block native proposals (pass)
- [x] Focused tests cover deterministic fixtures, unavailable/failure paths, provenance, and no opaque-filter persistence (pass)
Checks run:
- swift build — clean, 0 diagnostics
- swift test --filter AppleEnhancementReferenceTests — 21 passed, 0 failures
- scripts/ci-tests.sh fast — 789 tests, 0 failures
- scripts/ci-tests.sh serial — 328 tests, 0 failures
- git diff --check — clean
- dg validate — OK (pre-existing unrelated warnings only)
- grep for @unchecked Sendable / nonisolated(unsafe) / @preconcurrency / force-unwraps in the new file — none found
- git status --porcelain — clean tree aside from pre-existing .dg bookkeeping churn
Findings:
- None
Fixes:
- None
Verification commits:
- d424821
Actor: claude
Resolved model: sonnet
Pickup session: 01MTVWR2Q36U6IMH2L
Summary: Verified: Apple Core Image automatic-enhancement reference fitting is a clean, value-only adapter — no CIFilter/CIImage persisted, correct RAW/standard WB direction, analysis-view baseline preserves Looks/LUTs/grading/masks/crop, all unavailable paths explicit. Reran fast (789) and serial (328) lanes plus the 21 focused tests: all green. No findings, no fixes needed.

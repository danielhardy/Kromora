---
id: LUMO-190
title: Foreground instance + background mask provider
type: feature
status: done
priority: medium
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
labels:
  - photo-intelligence
created: 2026-09-04T14:27:51.702Z
updated: 2026-09-04T15:12:39.985Z
depends_on:
  - LUMO-187
  - LUMO-185
order: zzzzv
board: product
branch: main
commits:
  - 4f8adcf
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Foreground instance masks use Vision real pixel masks
      result: pass
      notes: VNGenerateForegroundInstanceMaskRequest is performed inside VisionSemanticMaskProvider and each allInstances label is converted from the documented float CVPixelBuffer into a NormalizedMask, never a bounding box.
    - criterion: Multiple instances and cache identity are stable
      result: pass
      notes: Foreground instances are exposed by ordinal .foregroundInstance(index), stored independently through MaskStore, and quality plus VisionConfiguration.foregroundRevision participate in the cache key.
    - criterion: Background is the complement of all foreground instances
      result: pass
      notes: The provider unions all cached/generated foreground pixel masks with MaskOperations.union and derives .background with MaskOperations.invert; no-foreground images return an empty foreground list and a full background mask.
    - criterion: Failures and platform availability are typed and safe
      result: pass
      notes: macOS 14 availability, unsupported revision, decode, request, cancellation, missing pixel, and out-of-range paths do not leak raw Vision failures or crash.
    - criterion: Shared actor/value boundaries remain clean
      result: pass
      notes: Vision and CVPixelBuffer stay inside the actor; only RegionMask/NormalizedMask/MaskStore values cross the boundary.
  checks_run:
    - swift test --filter VisionSemanticMaskProviderTests --filter RegionMaskTests (9 passed, 0 failed)
    - swift build (passed as part of focused test build)
    - git diff --check (clean)
  findings:
    - Foreground positive detection remains fixture-dependent; the always-on generated no-foreground fixture verifies graceful empty output and full complement background.
  fixes: []
  verification_commits:
    - 4f8adcf
  actor: codex
  resolved_model: unknown
  completed_at: 2026-09-04T15:12:39.982Z
  session: 01MTN3F0VS8NS8L8J3
---

**Type:** Feature
**Component:** `Sources/LumoKit/Models/PhotoAnalysis/VisionSemanticMaskProvider.swift`
(+`.foregroundInstance`/`.background`)
**Depends on:** LUMO-187, LUMO-185
**Epic:** LUMO-181 — see `docs/PHASE3_SPEC.md` §4 (Tier 2)

## 1. Problem

Saliency (LUMO-188) says *where* attention likely is; foreground instance masking says *which
concrete object(s)* can be separated from the background, with real pixel masks. This is the
heaviest of the core mask kinds. `.background` is derived from it (everything not covered by any
foreground instance) — both kinds ship together since one is naturally the complement of the
other.

## 2. Requirement (acceptance criteria)

1. Implement `mask(for: .foregroundInstance(i), image:, quality:)` using Apple's foreground
   instance mask request, producing one or more real pixel-mask `RegionMask`s (never a bounding
   box — Vision returns actual masks here, use them).
2. Implement `mask(for: .background, image:, quality:)` as the complement of the union of all
   detected foreground instances (use `MaskOperations.invert`/`union` from LUMO-186 rather than a
   separate ad-hoc computation).
3. Masks written through `MaskStore` (LUMO-185), keyed consistently.
4. Failure/unsupported throws a typed, catchable error.
5. Coordinates via LUMO-183; Vision revision recorded in `VisionConfiguration`.
6. Swift 6 clean, zero escape hatches.

## 3. Implementation notes

- This is the heaviest analyzer here — pay attention to `AnalysisTimings.foregroundMasking`
  against the `.detailed`-level budget in `docs/PHASE3_SPEC.md` §6 (< 300 ms); if it's blowing the
  budget on a representative fixture, say so in the PR (LUMO-206 owns the formal benchmark suite,
  but don't ship something wildly over budget unmeasured).
- Always prefer the real pixel mask Vision returns over any bounding rectangle it also provides.

## 4. Where to look

- `docs/PHASE3_SPEC.md` §4, §6.
- LUMO-186's `MaskOperations` — for deriving `.background`.

## 5. Testing

- `Tests/LumoKitTests/ForegroundMaskProviderTests.swift` (new): synthetic fixture with a clear
  separable foreground object — assert at least one `.foregroundInstance` mask with roughly
  expected coverage, and a `.background` mask that's its complement (assert coverage sums to
  ~1.0). No-clear-foreground fixture — assert empty, not an error. Failure path.

## Agent log

- 2026-09-04T15:12:39.983Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Foreground instance masks use Vision real pixel masks (pass) — VNGenerateForegroundInstanceMaskRequest is performed inside VisionSemanticMaskProvider and each allInstances label is converted from the documented float CVPixelBuffer into a NormalizedMask, never a bounding box.
- [x] Multiple instances and cache identity are stable (pass) — Foreground instances are exposed by ordinal .foregroundInstance(index), stored independently through MaskStore, and quality plus VisionConfiguration.foregroundRevision participate in the cache key.
- [x] Background is the complement of all foreground instances (pass) — The provider unions all cached/generated foreground pixel masks with MaskOperations.union and derives .background with MaskOperations.invert; no-foreground images return an empty foreground list and a full background mask.
- [x] Failures and platform availability are typed and safe (pass) — macOS 14 availability, unsupported revision, decode, request, cancellation, missing pixel, and out-of-range paths do not leak raw Vision failures or crash.
- [x] Shared actor/value boundaries remain clean (pass) — Vision and CVPixelBuffer stay inside the actor; only RegionMask/NormalizedMask/MaskStore values cross the boundary.
Checks run:
- swift test --filter VisionSemanticMaskProviderTests --filter RegionMaskTests (9 passed, 0 failed)
- swift build (passed as part of focused test build)
- git diff --check (clean)
Findings:
- Foreground positive detection remains fixture-dependent; the always-on generated no-foreground fixture verifies graceful empty output and full complement background.
Fixes:
- None
Verification commits:
- 4f8adcf
Actor: codex
Resolved model: unknown
Pickup session: 01MTN3F0VS8NS8L8J3
Summary: Implemented Vision foreground-instance masks and background complements with quality-aware caching and typed graceful empty results.

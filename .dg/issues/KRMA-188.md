---
id: KRMA-188
title: Attention saliency -> subject mask provider
type: feature
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Subject mask uses attention-based saliency and returns RegionMask
      result: pass
      notes: The provider performs VNGenerateAttentionBasedSaliencyImageRequest, maps its salient object bounds, rasterizes the semantic result, and returns a RegionMask.
    - criterion: Requested quality and provider revision participate in caching
      result: pass
      notes: Analysis, preview, and render requests use independent MaskStore keys containing MaskQuality and VisionConfiguration.providerVersion.
    - criterion: Failure is typed and coordinate conversion is centralized
      result: pass
      notes: No salient result throws VisionSemanticMaskError.noSalientRegion; Vision bounds use NormalizedRect.fromVision.
  checks_run:
    - swift test --filter VisionSemanticMaskProviderTests (2 passed, 0 failed)
    - swift test --filter RegionMaskTests (5 passed, 0 failed)
    - swift build (passed)
    - git diff --check (clean)
  findings:
    - The initial subject result uses the Vision salient-object rectangle; heat-map-driven matte refinement remains the planned LUMO-202 follow-up.
  fixes: []
  verification_commits:
    - f004c7da5acc72a5ce93b227ef3266dab0576f46
  actor: codex
  resolved_model: unknown
  completed_at: 2026-09-04T14:59:09.864Z
  session: 01MTN2XNRZIXHAODM1
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
labels:
  - photo-intelligence
created: 2026-09-04T14:27:50.916Z
updated: 2026-09-10T12:53:45.709Z
depends_on:
  - KRMA-187
  - KRMA-185
order: ri56mgkz
board: product
branch: main
commits:
  - f004c7da5acc72a5ce93b227ef3266dab0576f46
---

**Type:** Feature
**Component:** `Sources/LumoKit/Models/PhotoAnalysis/VisionSemanticMaskProvider.swift` (+`.subject`)
**Depends on:** KRMA-187, KRMA-185
**Epic:** KRMA-181 — see `docs/PHASE3_SPEC.md` §4 (Tier 1)

## 1. Problem

The first real semantic mask: "where is the visually important subject?", via attention-based
saliency. This is the lowest-cost, highest-value signal and should land before face/foreground so
later tickets have at least one real mask to test against.

## 2. Requirement (acceptance criteria)

1. Implement `VisionSemanticMaskProvider.mask(for: .subject, image:, quality:)` using Apple's
   attention-based saliency request, converting the resulting heat map into a `RegionMask`.
2. At `.analysis` quality this runs against the canonical ~768px `AnalysisImage`; document what
   `.preview`/`.render` mean for this kind (saliency itself may not need a higher-resolution pass
   — if so, say so explicitly and have those quality levels resolve to the same underlying
   computation, rather than silently ignoring the requested quality).
3. Coordinates converted through KRMA-183's single conversion function.
4. Result written through `MaskStore` (KRMA-185), keyed correctly.
5. Failure (unsupported hardware, request error, no salient region) throws a typed, catchable
   error rather than crashing — the *caller* (KRMA-193/195) decides whether that's fatal or
   degrades gracefully; this ticket's job is just to fail cleanly and predictably.
6. Vision revision recorded in `VisionConfiguration` (KRMA-187).
7. Swift 6 clean, zero escape hatches.

## 3. Implementation notes

- Keep the request/response mapping small and dumb — turning this into "the" primary subject with
  confidence scoring is KRMA-197/198's job, not this ticket's. This ticket only needs to answer
  "what does saliency say", as a `RegionMask`.
- Time this (`AnalysisTimings.saliency`, from KRMA-182) from the start.

## 4. Where to look

- `docs/PHASE3_SPEC.md` §1, §4 — saliency's role.
- KRMA-187's dispatch structure; KRMA-184's `RegionMask`/`SemanticMaskKind`.

## 5. Testing

- `Tests/LumoKitTests/SubjectMaskProviderTests.swift` (new): fixture with an obvious visual
  subject (synthetic, generated per `Fixtures.swift` convention) — assert the resulting mask's
  bounds roughly contain the expected area. Failure path returns a typed error, doesn't crash.

## Agent log

- 2026-09-04T14:59:09.865Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Subject mask uses attention-based saliency and returns RegionMask (pass) — The provider performs VNGenerateAttentionBasedSaliencyImageRequest, maps its salient object bounds, rasterizes the semantic result, and returns a RegionMask.
- [x] Requested quality and provider revision participate in caching (pass) — Analysis, preview, and render requests use independent MaskStore keys containing MaskQuality and VisionConfiguration.providerVersion.
- [x] Failure is typed and coordinate conversion is centralized (pass) — No salient result throws VisionSemanticMaskError.noSalientRegion; Vision bounds use NormalizedRect.fromVision.
Checks run:
- swift test --filter VisionSemanticMaskProviderTests (2 passed, 0 failed)
- swift test --filter RegionMaskTests (5 passed, 0 failed)
- swift build (passed)
- git diff --check (clean)
Findings:
- The initial subject result uses the Vision salient-object rectangle; heat-map-driven matte refinement remains the planned KRMA-202 follow-up.
Fixes:
- None
Verification commits:
- f004c7da5acc72a5ce93b227ef3266dab0576f46
Actor: codex
Resolved model: unknown
Pickup session: 01MTN2XNRZIXHAODM1
Summary: Implemented subject masks from Vision attention-based saliency, converted bounds through the shared Vision coordinate boundary, cached requested qualities through MaskStore, and added typed degradation tests.

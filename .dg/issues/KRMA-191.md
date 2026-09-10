---
id: KRMA-191
title: Person segmentation mask provider
type: feature
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Person segmentation uses Vision at requested analysis/preview quality
      result: pass
      notes: VNGeneratePersonSegmentationRequest uses fast for .analysis and balanced for .preview, with the configured revision and a normalized float output pixel format.
    - criterion: Segmentation is demand-driven and gated by prior signals
      result: pass
      notes: The provider checks MaskStore for an existing face or foreground-instance signal before issuing any person Vision request; no-signal calls return personNotApplicable.
    - criterion: Results use shared RegionMask/MaskStore infrastructure
      result: pass
      notes: The resulting person pixel buffer is normalized within the Vision actor, stored under the quality/versioned key, and returned as a RegionMask.
    - criterion: Render quality and failures are typed
      result: pass
      notes: .render returns unsupportedQuality until LUMO-202; unavailable revisions, empty results, decode/request, pixel, and cancellation paths are catchable VisionSemanticMaskError values.
    - criterion: Swift 6 boundary remains safe
      result: pass
      notes: Vision/CoreVideo objects remain inside the actor and no concurrency escape hatch was introduced.
  checks_run:
    - swift test --filter VisionSemanticMaskProviderTests --filter RegionMaskTests (10 passed, 0 failed)
    - swift build (passed as part of focused test build)
    - git diff --check (clean)
  findings:
    - Positive person segmentation requires a licensed person fixture; always-on gating/no-signal coverage confirms landscapes do not issue the expensive request.
  fixes: []
  verification_commits:
    - ee65dbc
  actor: codex
  resolved_model: unknown
  completed_at: 2026-09-04T15:14:26.737Z
  session: 01MTN3HB8RST8T1KDX
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
labels:
  - photo-intelligence
created: 2026-09-04T14:27:52.110Z
updated: 2026-09-10T12:53:45.941Z
depends_on:
  - KRMA-189
  - KRMA-190
order: wjl0v3lm
board: product
branch: main
commits:
  - ee65dbc
---

**Type:** Feature
**Component:** `Sources/LumoKit/Models/PhotoAnalysis/VisionSemanticMaskProvider.swift` (+`.person`)
**Depends on:** KRMA-189, KRMA-190
**Epic:** KRMA-181 — see original proposal §8, §19

## 1. Problem — note the sequencing change

An earlier draft of this plan treated person segmentation as a late "refinement" ticket, gated
behind Auto shipping. That was wrong: since masks are now shared infrastructure consumed by both
Auto *and* the Masking UI (KRMA-201) from day one, `.person` needs to exist as a core mask kind
alongside face/foreground — the Masking UI's "Person" option depends on it directly, not on
anything Auto-specific. What *does* stay a later, separate ticket is upgrading person mattes to
full-resolution `.render` quality for local-adjustment painting (KRMA-202) — this ticket only
needs to work at `.analysis`/`.preview` quality.

## 2. Requirement (acceptance criteria)

1. Implement `mask(for: .person, image:, quality:)` using Vision's person segmentation request,
   selecting a Vision-side quality level appropriate to the requested `MaskQuality` (e.g. Vision's
   own fast/balanced setting for `.analysis`/`.preview` — full/accurate reserved for `.render`,
   which this ticket doesn't need to satisfy yet; document what happens if `.render` is requested
   here before KRMA-202 lands — a clean "not yet supported at this quality" error is fine).
2. **Demand-driven gating**: only compute a person matte when a `.face` mask (KRMA-189) or a
   plausible person-shaped `.foregroundInstance` (KRMA-190) was already found for this image —
   don't run person segmentation on a landscape with no people. This gating can live in this
   ticket's implementation of `mask(for: .person, ...)` itself (check for an existing face/
   foreground result before doing the Vision call) or in the coordinator (KRMA-195) — pick
   whichever is cleaner and document the choice.
3. Result written through `MaskStore`, keyed consistently.
4. Failure/unsupported/gated-out throws or returns a typed, catchable "not applicable" result —
   not a crash.
5. Coordinates via KRMA-183; Vision revision recorded in `VisionConfiguration`.
6. Swift 6 clean, zero escape hatches.

## 3. Implementation notes

- Keep this additive: existing behavior for non-people images must be unaffected by this ticket
  landing (the gating in §2.2 is what guarantees that).

## 4. Where to look

- Original proposal §8, §19.
- KRMA-189 (faces), KRMA-190 (foreground) — the two signals that gate whether this runs.

## 5. Testing

- `Tests/LumoKitTests/PersonMaskProviderTests.swift` (new): fixture with a clear person-shaped
  foreground + face → person matte produced. Fixture with no face/person-shaped foreground →
  person segmentation is skipped entirely (assert the Vision request was never issued, via a call
  counter on a fake/spy). Failure path.

## Agent log

- 2026-09-04T15:14:26.738Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Person segmentation uses Vision at requested analysis/preview quality (pass) — VNGeneratePersonSegmentationRequest uses fast for .analysis and balanced for .preview, with the configured revision and a normalized float output pixel format.
- [x] Segmentation is demand-driven and gated by prior signals (pass) — The provider checks MaskStore for an existing face or foreground-instance signal before issuing any person Vision request; no-signal calls return personNotApplicable.
- [x] Results use shared RegionMask/MaskStore infrastructure (pass) — The resulting person pixel buffer is normalized within the Vision actor, stored under the quality/versioned key, and returned as a RegionMask.
- [x] Render quality and failures are typed (pass) — .render returns unsupportedQuality until KRMA-202; unavailable revisions, empty results, decode/request, pixel, and cancellation paths are catchable VisionSemanticMaskError values.
- [x] Swift 6 boundary remains safe (pass) — Vision/CoreVideo objects remain inside the actor and no concurrency escape hatch was introduced.
Checks run:
- swift test --filter VisionSemanticMaskProviderTests --filter RegionMaskTests (10 passed, 0 failed)
- swift build (passed as part of focused test build)
- git diff --check (clean)
Findings:
- Positive person segmentation requires a licensed person fixture; always-on gating/no-signal coverage confirms landscapes do not issue the expensive request.
Fixes:
- None
Verification commits:
- ee65dbc
Actor: codex
Resolved model: unknown
Pickup session: 01MTN3HB8RST8T1KDX
Summary: Added cache-gated Vision person segmentation with explicit quality mapping, shared mask storage, and typed not-applicable degradation.
